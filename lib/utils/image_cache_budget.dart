/// How much decoded image data the app is allowed to keep resident.
///
/// Flutter's [ImageCache] holds *decoded* bitmaps, so its budget is close to a
/// floor on the process's memory once the user has browsed a library with
/// artwork: the cache fills to its cap and, by design, never gives anything
/// back on its own.
///
/// Desktop used to take the largest budget unconditionally while Android
/// scaled its budget to the device. That is the wrong way round: a desktop
/// build runs on everything from a 4 GB mini PC to a 64 GB tower, and the one
/// that cannot spare 400 MB of box art is exactly the one that was being asked
/// for it. Both now come from the same table.
class ImageCacheBudget {
  const ImageCacheBudget({
    required this.maximumSize,
    required this.maximumSizeBytes,
  });

  /// Entry-count cap, mapped onto [ImageCache.maximumSize].
  final int maximumSize;

  /// Byte cap, mapped onto [ImageCache.maximumSizeBytes]. This is the limit
  /// that actually binds in practice; the count rarely gets there first.
  final int maximumSizeBytes;

  /// Megabytes of [maximumSizeBytes], for logging.
  int get maximumSizeMb => maximumSizeBytes ~/ (1024 * 1024);

  /// The budget for a machine with [ramGb] gigabytes of physical RAM.
  ///
  /// A null [ramGb] means the platform would not tell us. That takes the
  /// smallest budget rather than the largest, because guessing high costs a
  /// small machine hundreds of megabytes it does not have, while guessing low
  /// costs a large machine nothing but some re-decoding on scrollback.
  factory ImageCacheBudget.forRam(int? ramGb) {
    if (ramGb == null || ramGb <= 2) {
      return const ImageCacheBudget(
        maximumSize: 300,
        maximumSizeBytes: 40 * 1024 * 1024,
      );
    }
    if (ramGb <= 4) {
      return const ImageCacheBudget(
        maximumSize: 600,
        maximumSizeBytes: 80 * 1024 * 1024,
      );
    }
    if (ramGb <= 8) {
      return const ImageCacheBudget(
        maximumSize: 1000,
        maximumSizeBytes: 200 * 1024 * 1024,
      );
    }
    return const ImageCacheBudget(
      maximumSize: 1500,
      maximumSizeBytes: 400 * 1024 * 1024,
    );
  }
}
