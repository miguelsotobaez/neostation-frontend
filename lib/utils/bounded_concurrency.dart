import '../services/logger_service.dart';

final _log = LoggerService.instance;

/// Runs [task] over [items] with at most [concurrency] tasks in flight,
/// invoking [onEach] after each completion (for progress).
///
/// Intended for batches of small, independent network fetches — theme assets,
/// system definitions — where wall-clock time is dominated by per-request
/// round-trip latency rather than bandwidth, so a bounded pool cuts it
/// roughly linearly.
///
/// A single failing task never aborts the batch: failures are logged against
/// [label] and the pool moves on. Safe on Dart's single-threaded event loop —
/// the `next` cursor is only ever read and advanced synchronously, with no
/// await point in between.
Future<void> runBounded<T>(
  List<T> items,
  int concurrency,
  Future<void> Function(T item) task, {
  void Function()? onEach,
  String label = 'Bounded task',
}) async {
  if (items.isEmpty) return;
  int next = 0;

  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= items.length) return;
      try {
        await task(items[i]);
      } catch (e) {
        _log.w('$label failed for item ${items[i]}: $e');
      }
      onEach?.call();
    }
  }

  final workerCount = concurrency < items.length ? concurrency : items.length;
  await Future.wait(List.generate(workerCount, (_) => worker()));
}
