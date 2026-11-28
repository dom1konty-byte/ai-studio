import 'dart:async';
import 'dart:collection';

/// Очередь задач: одновременно выполняется не более [limit].
class AsyncPool {
  AsyncPool(this.limit);
  final int limit;
  int _running = 0;
  int maxRunning = 0;
  final _queue = Queue<void Function()>();

  Future<T> run<T>(Future<T> Function() task) {
    final c = Completer<T>();
    _queue.add(() {
      _running++;
      if (_running > maxRunning) maxRunning = _running;
      task().then(c.complete, onError: c.completeError).whenComplete(() {
        _running--;
        _next();
      });
    });
    _next();
    return c.future;
  }

  void _next() {
    while (_running < limit && _queue.isNotEmpty) {
      _queue.removeFirst()();
    }
  }
}
