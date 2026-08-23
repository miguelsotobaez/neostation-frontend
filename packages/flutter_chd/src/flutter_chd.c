#include "flutter_chd.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "libchdr/chd.h"
#include "libchdr/cdrom.h"

#if _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

/* Red Book allows 99 tracks; a CHD cannot describe more. */
#define NCHD_MAX_TRACKS 99

/* CD frames are grouped into hunks and every track is padded out to a multiple
 * of this many frames, so a track's first frame is not simply the sum of the
 * lengths before it. */
#define NCHD_TRACK_PADDING 4

/* The 12-byte sync pattern that opens a raw data sector. Its presence is what
 * tells us where the user data starts, which varies by how the track was
 * stored — see nchd_sector_data_offset(). */
static const uint8_t kSyncHeader[12] = {0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                                        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00};

typedef struct {
  int32_t number;
  int32_t mode;
  uint32_t frames;    /* total stored length, pregap included */
  uint32_t pregap;    /* leading frames that are gap rather than track data */
  uint32_t start;     /* first physical frame of the track within the CHD */
  uint32_t start_lba; /* first sector of the track as the disc addresses it */
  int32_t flat;       /* frames are bare user data, with no sector header */
  int32_t raw;        /* frames are full 2352-byte sectors, sync and all */
  int32_t data_offset; /* where the user data starts within a stored frame */
} nchd_track;

struct nchd_disc {
  chd_file *chd;
  FILE *fp; /* non-NULL when this reader opened the file itself */
  uint32_t unit_bytes;
  uint32_t frames_per_hunk;
  uint8_t *hunk;
  uint32_t hunk_number;
  int32_t hunk_loaded;
  int32_t track_count;
  nchd_track tracks[NCHD_MAX_TRACKS];
};

static uint32_t nchd_padding_frames(uint32_t frames) {
  return ((frames + NCHD_TRACK_PADDING - 1) & ~(uint32_t)(NCHD_TRACK_PADDING - 1)) -
         frames;
}

/* Where a track's 2048 bytes of user data start inside a stored frame.
 *
 * A CHD frame is not always a raw 2352-byte sector. chdman stores a track at
 * the size its type declares and pads the frame out to 2448, so only the
 * `_RAW` types carry a sync pattern and a header to step over; a cooked track
 * begins with the user data itself. That distinction is what a `.iso` turned
 * into a CHD with `chdman createcd` runs into: it becomes TYPE:MODE1, 2048
 * cooked bytes at offset zero, which is how most PS2 discs in a library are
 * stored. Reading those 16 bytes in lands mid-header, and every lookup on the
 * disc quietly misses. */
static int32_t nchd_data_offset_for_type(const char *type) {
  if (strcmp(type, "MODE1_RAW") == 0) return 16;
  if (strcmp(type, "MODE2_RAW") == 0) return 24;
  /* MODE2/2336 and MODE2_FORM_MIX begin at the 8-byte subheader. */
  if (strcmp(type, "MODE2") == 0 || strcmp(type, "MODE2_FORM_MIX") == 0) {
    return 8;
  }
  /* MODE1, MODE2_FORM1, MODE2_FORM2 and AUDIO are user data from byte zero. */
  return 0;
}

/* Whether the frames of a track of this type hold a whole raw sector. */
static int32_t nchd_is_raw_type(const char *type) {
  const size_t length = strlen(type);
  return length > 4 && strcmp(type + length - 4, "_RAW") == 0;
}

static int32_t nchd_mode_for_type(const char *type) {
  if (type[0] == 'A') return NCHD_MODE_AUDIO; /* AUDIO */
  if (strncmp(type, "MODE2", 5) == 0) return NCHD_MODE_MODE2;
  return NCHD_MODE_MODE1; /* MODE1, MODE1_RAW, and anything unfamiliar */
}

/* Reads track `index` (0-based, in the order the CHD stores them) into `track`,
 * leaving `start` for the caller to accumulate. Returns the frames this track
 * occupies including its padding, or 0 when there is no such track. */
static uint32_t nchd_read_track_metadata(chd_file *chd, uint32_t index,
                                         nchd_track *track) {
  char metadata[512];
  char type[64];
  char subtype[64];
  char pgtype[64];
  char pgsub[64];
  uint32_t length = 0;
  int number = 0;
  int frames = 0;
  int pregap = 0;
  int postgap = 0;
  int pad = 0;

  memset(track, 0, sizeof(*track));
  metadata[0] = '\0';
  pgtype[0] = '\0';

  /* CHT2 is what chdman writes today, and the only form that carries the
   * pregap — which decides whether sector 0 of the track is its first stored
   * frame or a few hundred frames in. */
  if (chd_get_metadata(chd, CDROM_TRACK_METADATA2_TAG, index, metadata,
                       sizeof(metadata), &length, NULL, NULL) == CHDERR_NONE) {
    if (sscanf(metadata, CDROM_TRACK_METADATA2_FORMAT, &number, type, subtype,
               &frames, &pregap, pgtype, pgsub, &postgap) != 8) {
      return 0;
    }
  } else if (chd_get_metadata(chd, CDROM_TRACK_METADATA_TAG, index, metadata,
                              sizeof(metadata), &length, NULL,
                              NULL) == CHDERR_NONE) {
    if (sscanf(metadata, CDROM_TRACK_METADATA_FORMAT, &number, type, subtype,
               &frames) != 4) {
      return 0;
    }
  } else if (chd_get_metadata(chd, GDROM_TRACK_METADATA_TAG, index, metadata,
                              sizeof(metadata), &length, NULL,
                              NULL) == CHDERR_NONE) {
    /* GD-ROM states its own padding rather than implying it. */
    if (sscanf(metadata, GDROM_TRACK_METADATA_FORMAT, &number, type, subtype,
               &frames, &pad, &pregap, pgtype, pgsub, &postgap) != 9) {
      return 0;
    }
  } else {
    return 0;
  }

  if (frames <= 0) return 0;

  track->number = number;
  track->mode = nchd_mode_for_type(type);
  track->raw = nchd_is_raw_type(type);
  track->data_offset = nchd_data_offset_for_type(type);
  track->frames = (uint32_t)frames;
  /* A declared pregap is always present in the image and always counted in
   * FRAMES, whatever PGTYPE says. The `V` prefix chdman writes there means the
   * pregap was not in the *source* image, not that it is absent from this one:
   * it synthesises the frames and stores them as silence. Measured on a real
   * PC Engine CD, whose data track declares `PGTYPE:VMODE1_RAW PREGAP:225` and
   * begins 225 frames of zeroes into its own span — and confirmed by
   * arithmetic, since the sum of every track's FRAMES plus padding accounts for
   * the whole file exactly. Reading a track from frame 0 lands in that silence
   * and identifies nothing. */
  track->pregap = pregap > 0 ? (uint32_t)pregap : 0u;
  if (track->pregap > track->frames) track->pregap = 0u;

  if (pad > 0) return track->frames + (uint32_t)pad;
  return track->frames + nchd_padding_frames(track->frames);
}

/* Describes a DVD image as the single flat track it is, returning 1 when the
 * CHD is one.
 *
 * A DVD carries none of the metadata above. `chdman createdvd` writes no track
 * entry at all — only a `DVD ` tag with an empty payload — and stores the image
 * as an unbroken run of 2048-byte sectors with no sync pattern, no header and
 * no subheader. There is nothing to enumerate, so the layout comes from the
 * header instead: one data track covering every sector in the file.
 *
 * The unit size is what decides it rather than the tag. A unit of exactly one
 * sector's worth of user data can hold nothing but user data, the tag says no
 * more than that, and not every writer leaves one behind. A container that
 * turns out to carry no filesystem then fails where it already did, in the
 * ISO9660 probe above this. */
static int32_t nchd_add_dvd_track(const chd_header *header, nchd_disc *disc) {
  uint64_t frames;
  nchd_track *track;

  if (header->unitbytes != NCHD_SECTOR_SIZE) return 0;

  frames = header->logicalbytes / header->unitbytes;
  if (frames == 0) return 0;
  /* Sector numbers cross the FFI boundary as int32; a dual-layer DVD is about
   * four million sectors, so this only ever bites a malformed header. */
  if (frames > (uint64_t)0x7FFFFFFF) frames = (uint64_t)0x7FFFFFFF;

  track = &disc->tracks[0];
  memset(track, 0, sizeof(*track));
  track->number = 1;
  track->mode = NCHD_MODE_MODE1;
  track->frames = (uint32_t)frames;
  track->flat = 1;
  disc->track_count = 1;
  return 1;
}

static nchd_disc *nchd_create(chd_file *chd, FILE *fp, int32_t *out_error) {
  const chd_header *header = chd_get_header(chd);
  nchd_disc *disc;
  uint32_t start = 0;
  uint32_t start_lba = 0;
  uint32_t index;

  if (header == NULL || header->unitbytes == 0 ||
      header->hunkbytes < header->unitbytes) {
    if (out_error != NULL) *out_error = NCHD_ERR_OPEN;
    return NULL;
  }

  disc = (nchd_disc *)calloc(1, sizeof(nchd_disc));
  if (disc == NULL) {
    if (out_error != NULL) *out_error = NCHD_ERR_MEMORY;
    return NULL;
  }

  disc->chd = chd;
  disc->fp = fp;
  disc->unit_bytes = header->unitbytes;
  disc->frames_per_hunk = header->hunkbytes / header->unitbytes;
  disc->hunk_loaded = 0;
  disc->hunk = (uint8_t *)malloc(header->hunkbytes);
  if (disc->hunk == NULL) {
    free(disc);
    if (out_error != NULL) *out_error = NCHD_ERR_MEMORY;
    return NULL;
  }

  for (index = 0; index < NCHD_MAX_TRACKS; index++) {
    nchd_track track;
    uint32_t occupied = nchd_read_track_metadata(chd, index, &track);
    if (occupied == 0) break;
    track.start = start;
    /* The disc addresses the gap before the track proper, so the track's own
     * first sector is that far past where the previous track's data ended. */
    track.start_lba = start_lba + track.pregap;
    disc->tracks[disc->track_count++] = track;
    start += occupied;
    start_lba = track.start_lba + (track.frames - track.pregap);
  }

  if (disc->track_count == 0 && !nchd_add_dvd_track(header, disc)) {
    free(disc->hunk);
    free(disc);
    if (out_error != NULL) *out_error = NCHD_ERR_NO_TRACKS;
    return NULL;
  }

  if (out_error != NULL) *out_error = NCHD_OK;
  return disc;
}

static int32_t nchd_error_for(chd_error err) {
  switch (err) {
    case CHDERR_UNSUPPORTED_VERSION:
    case CHDERR_UNSUPPORTED_FORMAT:
    case CHDERR_NOT_SUPPORTED:
      return NCHD_ERR_UNSUPPORTED;
    case CHDERR_OUT_OF_MEMORY:
      return NCHD_ERR_MEMORY;
    default:
      return NCHD_ERR_OPEN;
  }
}

static FILE *nchd_fopen(const char *path) {
#if _WIN32
  /* fopen() on Windows takes the active code page, so a ROM with an accented
   * or Japanese filename — common enough in a real library — would not open. */
  FILE *file = NULL;
  int wide_length = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
  wchar_t *wide_path;
  if (wide_length <= 0) return NULL;
  wide_path = (wchar_t *)malloc((size_t)wide_length * sizeof(wchar_t));
  if (wide_path == NULL) return NULL;
  if (MultiByteToWideChar(CP_UTF8, 0, path, -1, wide_path, wide_length) > 0) {
    file = _wfopen(wide_path, L"rb");
  }
  free(wide_path);
  return file;
#else
  return fopen(path, "rb");
#endif
}

FFI_PLUGIN_EXPORT nchd_disc *nchd_open(const char *path, int32_t *out_error) {
  chd_file *chd = NULL;
  chd_error err;
  FILE *fp;
  nchd_disc *disc;

  if (path == NULL) {
    if (out_error != NULL) *out_error = NCHD_ERR_OPEN;
    return NULL;
  }

  fp = nchd_fopen(path);
  if (fp == NULL) {
    if (out_error != NULL) *out_error = NCHD_ERR_OPEN;
    return NULL;
  }

  err = chd_open_file(fp, CHD_OPEN_READ, NULL, &chd);
  if (err != CHDERR_NONE) {
    fclose(fp);
    if (out_error != NULL) *out_error = nchd_error_for(err);
    return NULL;
  }

  disc = nchd_create(chd, fp, out_error);
  if (disc == NULL) {
    chd_close(chd);
    fclose(fp);
  }
  return disc;
}

FFI_PLUGIN_EXPORT nchd_disc *nchd_open_fd(int32_t fd, int32_t *out_error) {
#if _WIN32
  (void)fd;
  if (out_error != NULL) *out_error = NCHD_ERR_OPEN;
  return NULL;
#else
  chd_file *chd = NULL;
  chd_error err;
  nchd_disc *disc;
  FILE *fp = fdopen((int)fd, "rb");

  if (fp == NULL) {
    if (out_error != NULL) *out_error = NCHD_ERR_OPEN;
    return NULL;
  }

  err = chd_open_file(fp, CHD_OPEN_READ, NULL, &chd);
  if (err != CHDERR_NONE) {
    fclose(fp);
    if (out_error != NULL) *out_error = nchd_error_for(err);
    return NULL;
  }

  disc = nchd_create(chd, fp, out_error);
  if (disc == NULL) {
    chd_close(chd);
    fclose(fp);
  }
  return disc;
#endif
}

FFI_PLUGIN_EXPORT int32_t nchd_track_count(nchd_disc *disc) {
  return disc == NULL ? 0 : disc->track_count;
}

FFI_PLUGIN_EXPORT int32_t nchd_track_field(nchd_disc *disc, int32_t track_index,
                                           int32_t field) {
  const nchd_track *track;
  if (disc == NULL || track_index < 0 || track_index >= disc->track_count) {
    return -1;
  }
  track = &disc->tracks[track_index];
  switch (field) {
    case NCHD_FIELD_NUMBER:
      return track->number;
    case NCHD_FIELD_MODE:
      return track->mode;
    case NCHD_FIELD_SECTORS:
      return (int32_t)(track->frames - track->pregap);
    case NCHD_FIELD_START_LBA:
      return (int32_t)track->start_lba;
    default:
      return -1;
  }
}

/* Where the 2048 bytes of user data begin within a stored frame.
 *
 * The track's type decides it (see nchd_data_offset_for_type). Within a raw
 * track the sector's own sync pattern is the better authority on which header
 * it carries, because a mode 1 and a mode 2 sector are both 2352 bytes and a
 * cue sheet can name the wrong one; byte 15 is the sector's mode. A cooked
 * track has no sync pattern to consult and none to mistake, so its declared
 * offset stands. */
static int32_t nchd_sector_data_offset(const uint8_t *sector,
                                       const nchd_track *track) {
  if (track->raw &&
      memcmp(sector, kSyncHeader, sizeof(kSyncHeader)) == 0) {
    return sector[15] == 2 ? 24 : 16;
  }
  return track->data_offset;
}

static int32_t nchd_load_hunk(nchd_disc *disc, uint32_t hunk_number) {
  if (disc->hunk_loaded && disc->hunk_number == hunk_number) return 1;
  if (chd_read(disc->chd, hunk_number, disc->hunk) != CHDERR_NONE) {
    disc->hunk_loaded = 0;
    return 0;
  }
  disc->hunk_number = hunk_number;
  disc->hunk_loaded = 1;
  return 1;
}

FFI_PLUGIN_EXPORT int32_t nchd_read_sector(nchd_disc *disc, int32_t track_index,
                                           uint32_t lba, uint8_t *out) {
  const nchd_track *track;
  uint32_t frame;
  uint32_t hunk_number;
  uint32_t frame_offset;
  const uint8_t *sector;
  int32_t data_offset;

  if (disc == NULL || out == NULL || track_index < 0 ||
      track_index >= disc->track_count) {
    return -1;
  }

  track = &disc->tracks[track_index];
  if (lba >= track->frames - track->pregap) return -1;

  /* Skip the track's pregap, so sector 0 is the first sector of the track's
   * own data rather than the silence in front of it. */
  frame = track->start + track->pregap + lba;
  hunk_number = frame / disc->frames_per_hunk;
  frame_offset = (frame % disc->frames_per_hunk) * disc->unit_bytes;

  if (!nchd_load_hunk(disc, hunk_number)) return -2;

  sector = disc->hunk + frame_offset;
  /* A flat track's frame *is* the user data: there is no header to step over,
   * and looking for one would both drop the first 16 bytes of the sector and
   * run past the end of the frame. */
  data_offset = track->flat ? 0 : nchd_sector_data_offset(sector, track);
  if ((uint32_t)data_offset + NCHD_SECTOR_SIZE > disc->unit_bytes) return -3;

  memcpy(out, sector + data_offset, NCHD_SECTOR_SIZE);
  return NCHD_SECTOR_SIZE;
}

FFI_PLUGIN_EXPORT void nchd_close(nchd_disc *disc) {
  if (disc == NULL) return;
  if (disc->chd != NULL) chd_close(disc->chd);
  if (disc->fp != NULL) fclose(disc->fp);
  free(disc->hunk);
  free(disc);
}
