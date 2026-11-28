import 'dart:async';
import 'dart:isolate';

/// Набор запущенных Isolate, которые можно убить разом («Стоп» в плитке).
class KillGroup {
  final Map<Isolate, void Function()> _running = {};

  int get running => _running.length;

  /// Убивает все Isolate группы; их future сразу завершаются ошибкой.
  void killAll() {
    final all = Map.of(_running);
    _running.clear();
    for (final e in all.entries) {
      e.key.kill(priority: Isolate.immediate);
      e.value();
    }
  }
}

void _entry(List<Object?> msg) {
  final fn = msg[0] as Object? Function();
  final port = msg[1] as SendPort;
  try {
    port.send(<Object?>[true, fn()]);
  } catch (e) {
    port.send(<Object?>[false, e.toString()]);
  }
}

/// Как `Isolate.run`, но Isolate регистрируется в [group]: `group.killAll()`
/// настоящим образом останавливает работу, а future завершается ошибкой.
/// [fn] не должна захватывать ничего, что нельзя отправить в Isolate.
Future<T> runKillable<T>(T Function() fn, KillGroup group) async {
  final port = ReceivePort();
  final done = Completer<T>();
  Isolate? iso;
  void finish() {
    port.close();
    if (iso != null) group._running.remove(iso);
  }

  void killed() {
    if (!done.isCompleted) done.completeError(StateError('остановлено'));
    port.close();
  }

  port.listen((m) {
    if (done.isCompleted) return;
    if (m is List && m.length == 2) {
      if (m[0] == true) {
        done.complete(m[1] as T);
      } else {
        done.completeError(StateError('${m[1]}'));
      }
    } else {
      done.completeError(StateError('остановлено')); // onExit без результата
    }
    finish();
  });
  try {
    iso = await Isolate.spawn(_entry, <Object?>[fn, port.sendPort], onExit: port.sendPort);
    group._running[iso] = killed;
  } catch (e) {
    finish();
    rethrow;
  }
  return done.future;
}
