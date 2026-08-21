/* A minimal disc-image reader over libchdr.
 *
 * The Dart side needs one primitive to hash a disc the way RetroAchievements
 * does: "give me the 2048 user-data bytes of logical sector N of track T".
 * Everything above that — ISO9660 parsing, locating a console's boot
 * executable, the MD5 itself — stays in Dart, where it is testable and shared
 * with the .cue/.bin and .iso readers that need no native code at all.
 *
 * So this layer is deliberately thin: it owns only what libchdr forces into C,
 * which is the CHD hunk cache and the track layout maths (frame padding and
 * stored pregaps) that decide which physical frame a track's sector lives in.
 *
 * The API is flat integers and byte buffers, no structs across the FFI
 * boundary, so the Dart bindings stay hand-checkable.
 */

#ifndef FLUTTER_CHD_H
#define FLUTTER_CHD_H

#include <stdint.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Bytes of user data in a data sector. Every console RetroAchievements hashes
 * from a disc stores its filesystem in 2048-byte sectors, whatever the
 * container wraps them in. */
#define NCHD_SECTOR_SIZE 2048

/* nchd_track_field() selectors. */
#define NCHD_FIELD_NUMBER 0 /* track number as the disc labels it (1-based) */
#define NCHD_FIELD_MODE 1   /* NCHD_MODE_* */
#define NCHD_FIELD_SECTORS 2 /* readable sectors, stored pregap excluded */
/* The track's own first sector as the disc addresses it. A filesystem's
 * internal sector numbers are disc-absolute, so a caller reading a data track
 * that is not the first one has to subtract this. */
#define NCHD_FIELD_START_LBA 3

/* Track modes. Anything that is not audio carries a filesystem. A DVD image
 * has no track metadata to take a mode from and no sector headers either, so
 * it is reported as the plain data track it reads as. */
#define NCHD_MODE_AUDIO 0
#define NCHD_MODE_MODE1 1
#define NCHD_MODE_MODE2 2

/* nchd_open_* failure reasons. Distinguishing them matters: an unsupported
 * codec is a build problem to fix, a bad file is a ROM problem to report. */
#define NCHD_OK 0
#define NCHD_ERR_OPEN 1        /* the file could not be opened or is not a CHD */
#define NCHD_ERR_NO_TRACKS 2   /* opened, but describes no readable track */
#define NCHD_ERR_UNSUPPORTED 3 /* a codec this build cannot decompress */
#define NCHD_ERR_MEMORY 4

typedef struct nchd_disc nchd_disc;

/* Opens a CHD by filesystem path. Returns NULL on failure, writing the reason
 * to *out_error when it is not NULL. */
FFI_PLUGIN_EXPORT nchd_disc *nchd_open(const char *path, int32_t *out_error);

/* Opens a CHD from an already-open file descriptor, which the reader takes
 * ownership of and closes in nchd_close().
 *
 * This is the Android path: a ROM there is a SAF `content://` URI with no
 * filesystem path libchdr could open, but the platform will hand out a
 * descriptor for one. Returns NULL and closes nothing on failure. */
FFI_PLUGIN_EXPORT nchd_disc *nchd_open_fd(int32_t fd, int32_t *out_error);

/* Number of tracks, or 0 if disc is NULL. */
FFI_PLUGIN_EXPORT int32_t nchd_track_count(nchd_disc *disc);

/* One NCHD_FIELD_* property of a track, by 0-based index. Returns -1 for an
 * unknown track or field. */
FFI_PLUGIN_EXPORT int32_t nchd_track_field(nchd_disc *disc, int32_t track_index,
                                           int32_t field);

/* Copies the NCHD_SECTOR_SIZE user-data bytes of logical sector `lba` of a
 * track into `out`, which must have room for them. Sector 0 is the first
 * sector after any stored pregap, so the numbering matches what the disc's
 * filesystem refers to.
 *
 * Returns the byte count written, or a negative value if the sector is out of
 * range or could not be decompressed. */
FFI_PLUGIN_EXPORT int32_t nchd_read_sector(nchd_disc *disc, int32_t track_index,
                                           uint32_t lba, uint8_t *out);

/* Closes the disc and everything it owns. Safe to call with NULL. */
FFI_PLUGIN_EXPORT void nchd_close(nchd_disc *disc);

#ifdef __cplusplus
}
#endif

#endif /* FLUTTER_CHD_H */
