import 'dart:io';
import 'dart:typed_data';

/// Identifies which emulator core wrote a RetroArch save state, from the state
/// bytes alone.
///
/// A save state is only loadable by the core that produced it: a state written
/// by FCEUmm will not load in Mesen, and RetroArch's failure is silent — it
/// reports that it is loading and then does nothing. That makes an incompatible
/// state indistinguishable from a working one *until* it is needed, which is
/// how cloud sync can quietly replace a good local state with one that can
/// never be resumed.
///
/// The core's identity is recoverable without any server-side convention, which
/// is what makes this usable when saves are shared with other frontends: they
/// upload a plain `<game>.state` like everyone else, and the bytes still say
/// who wrote them.
///
/// Layout, working outwards:
///
/// * **RZIP wrapper** (optional — RetroArch applies it when
///   `savestate_compression` is on): `#RZIPv` + version + `#`, a `uint32`
///   chunk size, a `uint64` total size, then per chunk a `uint32` compressed
///   length followed by a zlib stream.
/// * **RASTATE container**: `RASTATE` + version, then `(4-byte tag,
///   uint32 length)` blocks. The `MEM ` block holds the core's serialized
///   state.
/// * **The core's own state** begins that block, and cores start it with a
///   magic of their own — `FCS` for FCEUmm, `MST` for Mesen.
///
/// Only the *first* few bytes of the `MEM ` block are returned, as an opaque
/// token. Nothing here needs to know which core a given magic belongs to: the
/// question asked at sync time is "did the same core write both of these?",
/// and comparing two tokens answers it without a registry to keep current.
abstract final class RetroArchStateSignature {
  static const List<int> _rzipMagic = [0x23, 0x52, 0x5a, 0x49, 0x50, 0x76];
  static const List<int> _rastateMagic = [
    0x52, 0x41, 0x53, 0x54, 0x41, 0x54, 0x45, // 'RASTATE'
  ];

  /// Offset of the first zlib stream in an RZIP file: magic(6) + version(1) +
  /// `#`(1) + chunk size(4) + total size(8) + first chunk length(4).
  static const int _rzipPayloadOffset = 24;

  /// Enough inflated bytes to reach the `MEM ` block's first bytes. The blocks
  /// before it are short headers, so this never needs to be large — and being
  /// bounded is the point: a PS2 state runs to megabytes and none of it past
  /// the header is of any interest here.
  static const int _inflateLimit = 512;

  /// An opaque token identifying the core that wrote [bytes], or `null` when it
  /// cannot be determined.
  ///
  /// Returning `null` is a normal outcome, not an error: a state may be
  /// uncompressed in a form not recognised here, come from a core that begins
  /// its state with no magic, or not be a RetroArch state at all (a standalone
  /// emulator's own format). Callers must treat `null` as "no opinion" and fall
  /// back to whatever they would have done without this check — never as
  /// "incompatible", which would block syncs that work today.
  static Uint8List? of(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final container = _startsWith(data, _rzipMagic) ? _inflate(data) : data;
    if (container == null) return null;
    return _memBlock(container);
  }

  /// Whether [a] and [b] were written by *different* cores.
  ///
  /// False whenever either side cannot be identified, so an unrecognised state
  /// never blocks a transfer on a guess.
  static bool differ(List<int>? a, List<int>? b) {
    if (a == null || b == null) return false;
    final sa = of(a), sb = of(b);
    if (sa == null || sb == null) return false;
    if (sa.length != sb.length) return true;
    for (var i = 0; i < sa.length; i++) {
      if (sa[i] != sb[i]) return true;
    }
    return false;
  }

  /// Inflates just the head of an RZIP file's first chunk.
  static Uint8List? _inflate(Uint8List data) {
    if (data.length <= _rzipPayloadOffset) return null;
    try {
      final filter = RawZLibFilter.inflateFilter();
      filter.process(
        data,
        _rzipPayloadOffset,
        // A short prefix of the compressed stream is plenty to yield the few
        // hundred inflated bytes wanted, and caps the work on a huge state.
        data.length < _rzipPayloadOffset + 4096
            ? data.length
            : _rzipPayloadOffset + 4096,
      );
      final out = <int>[];
      for (;;) {
        final chunk = filter.processed(flush: false);
        if (chunk == null || chunk.isEmpty) break;
        out.addAll(chunk);
        if (out.length >= _inflateLimit) break;
      }
      return out.isEmpty ? null : Uint8List.fromList(out);
    } catch (_) {
      // Corrupt or unexpected compression: no opinion.
      return null;
    }
  }

  /// The first bytes of the RASTATE `MEM ` block — the core's own magic.
  static Uint8List? _memBlock(Uint8List buf) {
    if (!_startsWith(buf, _rastateMagic)) return null;
    var p = _rastateMagic.length + 1; // + version byte
    while (p + 8 <= buf.length) {
      final tag = buf.sublist(p, p + 4);
      final size = _u32(buf, p + 4);
      p += 8;
      if (tag[0] == 0x4d &&
          tag[1] == 0x45 &&
          tag[2] == 0x4d &&
          tag[3] == 0x20) {
        // 'MEM '
        final end = p + 4;
        if (end > buf.length) return null;
        return buf.sublist(p, end);
      }
      // A block claiming a size past the buffer means the header is malformed
      // or truncated by the bounded inflate above; either way, stop.
      if (size <= 0 || p + size > buf.length) return null;
      p += size;
    }
    return null;
  }

  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static bool _startsWith(Uint8List data, List<int> magic) {
    if (data.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (data[i] != magic[i]) return false;
    }
    return true;
  }
}
