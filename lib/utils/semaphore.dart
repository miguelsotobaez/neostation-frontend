import 'dart:async';

/// A simple asynchronous counting semaphore that limits how many concurrent
/// tasks may hold a slot at once. Callers [acquire] before entering the guarded
/// section and [release] when done; excess callers wait in FIFO order.
class Semaphore {
  final int maxCount;
  int _currentCount = 0;
  final List<Completer<void>> _waitQueue = [];

  Semaphore(this.maxCount);

  /// Acquires a slot in the semaphore, waiting if the [maxCount] is reached.
  ///
  /// With a [timeout], a caller that has waited that long gives up and throws
  /// [TimeoutException] instead of waiting forever. Giving up also drops the
  /// caller's place in the queue — otherwise a later [release] would hand its
  /// slot to a task that no longer exists, permanently shrinking the pool.
  Future<void> acquire({Duration? timeout}) async {
    if (_currentCount < maxCount) {
      _currentCount++;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);

    if (timeout == null) {
      await completer.future;
      return;
    }

    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      final wasStillQueued = _waitQueue.remove(completer);
      if (!wasStillQueued && completer.isCompleted) {
        // A slot was granted in the same turn the timeout fired, so this
        // caller does hold one despite giving up — hand it straight back
        // rather than leaking it.
        release();
      }
      rethrow;
    }
  }

  /// Releases a slot in the semaphore and notifies the next waiting task.
  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeAt(0);
      completer.complete();
    } else {
      _currentCount--;
    }
  }
}
