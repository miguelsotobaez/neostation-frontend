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
  Future<void> acquire() async {
    if (_currentCount < maxCount) {
      _currentCount++;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
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
