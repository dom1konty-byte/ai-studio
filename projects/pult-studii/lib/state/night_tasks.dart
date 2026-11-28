import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../models/scheduled_task.dart';
import '../services/app_storage.dart';
import '../services/rate_limit.dart';
import '../services/sleep_guard.dart';
import 'chat_controller.dart';

/// Готов ли чат принять запланированное сообщение.
enum NightReadiness { ready, wait, blocked }

/// Итог выполнения задачи.
class NightOutcome {
  const NightOutcome(this.ok, this.result);

  final bool ok;
  final String result;
}

/// Чат, которому адресована задача (подменяется в тестах).
abstract class NightTarget {
  NightReadiness get readiness;

  /// Почему чат закрыт (для [NightReadiness.blocked]).
  String get blockedText;

  /// Отправить текст как обычное сообщение; завершится в конце хода.
  Future<NightOutcome> run(String text, String label);
}

/// Обёртка над настоящим чатом.
class ChatNightTarget implements NightTarget {
  ChatNightTarget(this.chat);

  final ChatController chat;

  @override
  NightReadiness get readiness {
    if (chat.blockedReason != null) return NightReadiness.blocked;
    if (chat.preparing || chat.working || chat.rcOpen || chat.limitBlocked) {
      return NightReadiness.wait;
    }
    return NightReadiness.ready;
  }

  @override
  String get blockedText => 'Чат закрыт: ${chat.blockedReason ?? ''}';

  @override
  Future<NightOutcome> run(String text, String label) async {
    await chat.send(text, scheduled: label);
    final ok = chat.lastTurnOk;
    final text = _last(ok ? MsgKind.director : MsgKind.error);
    return NightOutcome(ok, brief(text));
  }

  String _last(MsgKind kind) {
    for (final m in chat.messages.reversed) {
      if (m.kind == kind) return m.text;
    }
    return '';
  }
}

/// Краткий текст результата: без переносов, до 120 символов.
String brief(String s) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = t.runes.toList();
  if (runes.length <= 120) return t;
  return '${String.fromCharCodes(runes.take(119)).trimRight()}…';
}

/// «Задача на ночь»: сообщения директору по расписанию.
class NightTasks extends ChangeNotifier {
  NightTasks({
    required this.state,
    required DateTime Function() clock,
    required this.targetFor,
    this.guard,
    this.every = const Duration(seconds: 30),
    this.onDone,
  }) : _now = clock;

  final StateRepo state;
  final DateTime Function() _now;

  /// Чат по ключу (создаёт, если ещё не открыт).
  final NightTarget? Function(String key) targetFor;
  final SleepGuard? guard;

  /// Как часто проверять время (null — таймер не нужен, тесты зовут [tick]).
  final Duration? every;

  /// Задача выполнена успешно (для уведомления Windows).
  final void Function(ScheduledTask task)? onDone;

  final List<ScheduledTask> tasks = [];

  /// Пропущенные: время прошло, пока AI Studio была закрыта.
  final Set<String> missed = {};
  final Set<String> _running = {};
  Timer? _timer;
  bool _awake = false;
  bool _disposed = false;
  int _seq = 0;

  List<ScheduledTask> get waiting => [
        for (final t in tasks)
          if (t.waiting) t,
      ];

  /// Ждущие задачи этого чата (включая пропущенные), по времени.
  List<ScheduledTask> waitingFor(String key) =>
      [for (final t in waiting) if (t.key == key) t]
        ..sort((a, b) => a.when.compareTo(b.when));

  /// Пропущенные задачи (плашка при запуске).
  List<ScheduledTask> get missedTasks =>
      [for (final t in waiting) if (missed.contains(t.id)) t];

  /// Ближайшая ждущая задача чата (не пропущенная).
  ScheduledTask? nextFor(String key) {
    final list = [
      for (final t in waitingFor(key))
        if (!missed.contains(t.id)) t,
    ];
    return list.isEmpty ? null : list.first;
  }

  /// Прочитать задачи из state.json; прошедшие помечаются пропущенными.
  void load() {
    tasks
      ..clear()
      ..addAll(state.nightTasks().map(ScheduledTask.fromJson).whereType<ScheduledTask>());
    missed.clear();
    final now = _now();
    for (final t in tasks) {
      if (t.waiting && !t.when.isAfter(now)) missed.add(t.id);
    }
    _changed(save: false);
  }

  /// Запланировать. Возвращает задачу.
  ScheduledTask add({
    required String key,
    required String text,
    required DateTime when,
    bool keepAwake = false,
  }) {
    final t = ScheduledTask(
      id: '${_now().microsecondsSinceEpoch}-${_seq++}',
      key: key,
      text: text.trim(),
      when: when,
      keepAwake: keepAwake,
    );
    tasks.add(t);
    _changed();
    return t;
  }

  ScheduledTask? _byId(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Отменить ждущую задачу.
  void cancel(String id) {
    final t = _byId(id);
    if (t == null || !t.waiting || _running.contains(id)) return;
    t.status = TaskStatus.cancelled;
    missed.remove(id);
    _changed();
  }

  /// «Выполнить сейчас»: время = сейчас, дальше как обычно (ждёт конца хода).
  void runNow(String id) {
    final t = _byId(id);
    if (t == null || !t.waiting || _running.contains(id)) return;
    t.when = _now();
    missed.remove(id);
    _changed();
    unawaited(tick());
  }

  /// Одна проверка: что пора — отправить. Таймер зовёт раз в [every].
  Future<void> tick() async {
    if (_disposed) return;
    final now = _now();
    final due = [
      for (final t in waiting)
        if (!t.when.isAfter(now) &&
            !missed.contains(t.id) &&
            !_running.contains(t.id))
          t,
    ]..sort((a, b) => a.when.compareTo(b.when));
    final started = <Future<void>>[];
    final busyKeys = <String>{};
    for (final t in due) {
      if (!busyKeys.add(t.key)) continue; // одна задача на чат за раз
      final target = targetFor(t.key);
      if (target == null) continue;
      switch (target.readiness) {
        case NightReadiness.wait:
          break;
        case NightReadiness.blocked:
          t.status = TaskStatus.error;
          t.result = brief(target.blockedText);
          _changed();
        case NightReadiness.ready:
          started.add(_execute(t, target));
      }
    }
    await Future.wait(started);
  }

  Future<void> _execute(ScheduledTask t, NightTarget target) async {
    _running.add(t.id);
    var outcome = const NightOutcome(false, 'не удалось отправить');
    try {
      outcome = await target.run(t.text, hhmm(t.when));
    } catch (e) {
      outcome = NightOutcome(false, brief('$e'));
    }
    _running.remove(t.id);
    t.status = outcome.ok ? TaskStatus.done : TaskStatus.error;
    t.result = outcome.result;
    _changed();
    if (outcome.ok) {
      try {
        onDone?.call(t);
      } catch (_) {}
    }
  }

  void _changed({bool save = true}) {
    if (save) _save();
    _syncGuard();
    _syncTimer();
    if (!_disposed) notifyListeners();
  }

  void _save() {
    // Выполненные храним недолго: последние 30.
    final done = tasks.where((t) => !t.waiting).toList();
    if (done.length > 30) {
      final drop = done.take(done.length - 30).toSet();
      tasks.removeWhere(drop.contains);
    }
    unawaited(() async {
      try {
        await state.setNightTasks([for (final t in tasks) t.toJson()]);
      } catch (_) {}
    }());
  }

  /// Не спать, пока есть ждущие задачи с галочкой (пропущенные не считаются).
  void _syncGuard() {
    final need = tasks.any((t) => t.waiting && t.keepAwake && !missed.contains(t.id));
    if (need == _awake) return;
    _awake = need;
    try {
      guard?.keepAwake(need);
    } catch (_) {}
  }

  /// Таймер живёт, только пока есть что ждать.
  void _syncTimer() {
    final e = every;
    final need = e != null && !_disposed && waiting.any((t) => !missed.contains(t.id));
    if (need && _timer == null) {
      _timer = Timer.periodic(e, (_) => unawaited(tick()));
    } else if (!need && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (_awake) {
      _awake = false;
      try {
        guard?.keepAwake(false);
      } catch (_) {}
    }
    super.dispose();
  }
}
