import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pult_studii/models/models.dart';
import 'package:pult_studii/models/scheduled_task.dart';
import 'package:pult_studii/services/app_storage.dart';
import 'package:pult_studii/services/sleep_guard.dart';
import 'package:pult_studii/state/night_tasks.dart';
import 'package:pult_studii/ui/night_dialog.dart';

import 'fakes.dart';

class FakeTarget implements NightTarget {
  NightReadiness ready = NightReadiness.ready;
  final sent = <String>[];
  final labels = <String>[];
  Completer<NightOutcome>? hold;
  NightOutcome outcome = const NightOutcome(true, 'готово');

  @override
  NightReadiness get readiness => ready;

  @override
  String get blockedText => 'Чат закрыт: нет папки';

  @override
  Future<NightOutcome> run(String text, String label) {
    sent.add(text);
    labels.add(label);
    final h = hold;
    return h == null ? Future.value(outcome) : h.future;
  }
}

class FakeGuard implements SleepGuard {
  final calls = <bool>[];

  @override
  void keepAwake(bool on) => calls.add(on);
}

class Rig {
  Rig({Map<String, dynamic>? state, DateTime? start})
      : storage = MemoryStorage(state: state ?? {}),
        now = start ?? DateTime(2026, 11, 28, 23, 0) {
    repo = StateRepo(storage);
    night = make();
  }

  final MemoryStorage storage;
  DateTime now;
  late StateRepo repo;
  final target = FakeTarget();
  final guard = FakeGuard();
  late NightTasks night;

  NightTasks make() => NightTasks(
        state: repo,
        clock: () => now,
        guard: guard,
        every: null,
        targetFor: (_) => target,
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);
}

void main() {
  test('если время уже прошло — завтра', () {
    final now = DateTime(2026, 11, 28, 3, 0);
    expect(nextOccurrence(now, 2, 0), DateTime(2026, 11, 29, 2, 0));
    expect(nextOccurrence(now, 7, 0), DateTime(2026, 11, 28, 7, 0));
    expect(nextOccurrence(now, 3, 0), DateTime(2026, 11, 29, 3, 0));
    expect(nextOccurrence(DateTime(2026, 12, 31, 23, 0), 2, 0),
        DateTime(2027, 1, 1, 2, 0));
  });

  test('выполнение по таймеру и запись в state.json', () async {
    final r = Rig();
    r.night.add(
        key: 'alpha',
        text: 'Сделай ночью',
        when: nextOccurrence(r.now, 2, 0));
    await r.night.tick();
    expect(r.target.sent, isEmpty);
    r.now = DateTime(2026, 11, 29, 2, 0, 5);
    await r.night.tick();
    expect(r.target.sent, ['Сделай ночью']);
    expect(r.target.labels, ['02:00']);
    expect(r.night.tasks.single.status, TaskStatus.done);
    expect(r.night.tasks.single.result, 'готово');
    await r.night.tick();
    expect(r.target.sent, hasLength(1));
    await r.settle();
    final again = r.make()..load();
    expect(again.tasks.single.status, TaskStatus.done);
    expect(again.missed, isEmpty);
  });

  test('директор работает — ждём конца хода, не дублируем', () async {
    final r = Rig();
    r.night.add(
        key: 'alpha', text: 'Ночь', when: r.now.add(const Duration(hours: 1)));
    r.now = r.now.add(const Duration(hours: 2));
    r.target.ready = NightReadiness.wait;
    await r.night.tick();
    expect(r.target.sent, isEmpty);
    expect(r.night.tasks.single.status, TaskStatus.waiting);
    r.target.ready = NightReadiness.ready;
    r.target.hold = Completer<NightOutcome>();
    final first = r.night.tick();
    await r.night.tick(); // второй тик, пока ход идёт
    expect(r.target.sent, hasLength(1));
    r.target.hold!.complete(const NightOutcome(true, 'ок'));
    await first;
    expect(r.night.tasks.single.status, TaskStatus.done);
  });

  test('ошибка хода и закрытый чат', () async {
    final r = Rig();
    r.night.add(key: 'alpha', text: 'А', when: r.now);
    r.target.outcome = const NightOutcome(false, 'упало');
    await r.night.tick();
    expect(r.night.tasks.single.status, TaskStatus.error);
    expect(r.night.tasks.single.result, 'упало');
    r.night.add(key: 'alpha', text: 'Б', when: r.now);
    r.target.ready = NightReadiness.blocked;
    await r.night.tick();
    expect(r.night.tasks.last.status, TaskStatus.error);
    expect(r.target.sent, ['А']);
  });

  test('пропущенные после перезапуска сами не запускаются', () async {
    final r = Rig();
    final t = r.night.add(
        key: 'alpha', text: 'Ночь', when: DateTime(2026, 11, 29, 2, 0));
    await r.settle();
    // AI Studio закрыли, открыли утром
    final morning = Rig(start: DateTime(2026, 11, 29, 8, 0));
    morning.storage.state = r.storage.state;
    morning.repo = StateRepo(morning.storage);
    await morning.repo.load();
    morning.night = morning.make()..load();
    expect(morning.night.missedTasks.single.id, t.id);
    await morning.night.tick();
    expect(morning.target.sent, isEmpty);
    expect(morning.guard.calls, isEmpty);
    morning.night.runNow(t.id);
    await morning.settle();
    expect(morning.target.sent, ['Ночь']);
    expect(morning.night.tasks.single.status, TaskStatus.done);
    expect(morning.night.missedTasks, isEmpty);
  });

  test('отмена пропущенной и ждущей', () async {
    final r = Rig();
    final a = r.night.add(key: 'alpha', text: 'А', when: r.now);
    final b = r.night.add(
        key: 'alpha', text: 'Б', when: r.now.add(const Duration(hours: 3)));
    r.night.cancel(a.id);
    r.night.cancel(b.id);
    r.now = r.now.add(const Duration(hours: 4));
    await r.night.tick();
    expect(r.target.sent, isEmpty);
    expect(r.night.waiting, isEmpty);
    expect(r.night.tasks.every((t) => t.status == TaskStatus.cancelled), isTrue);
  });

  test('«не спать»: включается и снимается', () async {
    final r = Rig();
    final t = r.night.add(
        key: 'alpha',
        text: 'А',
        when: r.now.add(const Duration(hours: 1)),
        keepAwake: true);
    expect(r.guard.calls, [true]);
    r.night.add(
        key: 'alpha', text: 'Б', when: r.now.add(const Duration(hours: 2)));
    expect(r.guard.calls, [true]);
    r.now = r.now.add(const Duration(hours: 1, minutes: 1));
    await r.night.tick();
    expect(r.night.tasks.first.status, TaskStatus.done);
    expect(r.guard.calls, [true, false]);
    expect(t.status, TaskStatus.done);
    final c = r.night.add(
        key: 'alpha',
        text: 'В',
        when: r.now.add(const Duration(hours: 1)),
        keepAwake: true);
    r.night.cancel(c.id);
    expect(r.guard.calls, [true, false, true, false]);
  });

  test('сообщение по расписанию сохраняется в истории', () {
    final m = ChatMessage(MsgKind.user, 'Ночь', scheduled: '02:00');
    final back = ChatMessage.fromJsonLine(m.toJsonLine())!;
    expect(back.scheduled, '02:00');
    expect(ChatMessage.fromJsonLine(ChatMessage(MsgKind.user, 'x').toJsonLine())!
        .scheduled, isNull);
  });

  group('окно', () {
    Future<void> open(WidgetTester tester, DateTime now,
        [void Function(NightRequest?)? onResult]) async {
      tester.view.physicalSize = const Size(960, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open'),
              onPressed: () => unawaited(showNightDialog(context,
                      initialText: 'Сделай ночью', clock: () => now)
                  .then((r) => onResult?.call(r))),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
    }

    testWidgets('нет переполнения на 960×600', (tester) async {
      await open(tester, DateTime(2026, 11, 28, 3, 0));
      expect(tester.takeException(), isNull);
      expect(find.text('Запланировать'), findsOneWidget);
      expect(find.text(nightHint), findsOneWidget);
      expect(find.text('через 1 ч'), findsOneWidget);
      expect(find.byKey(const Key('night-awake')), findsOneWidget);
    });

    testWidgets('02:00 уже прошло — завтра; «Запланировать» отдаёт время',
        (tester) async {
      NightRequest? got;
      await open(tester, DateTime(2026, 11, 28, 3, 0), (r) => got = r);
      expect(find.text('завтра в 02:00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('night-quick-в 07:00')));
      await tester.pump();
      expect(find.text('сегодня в 07:00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('night-submit')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(got?.text, 'Сделай ночью');
      expect(got?.when, DateTime(2026, 11, 28, 7, 0));
      expect(got?.keepAwake, isTrue);
    });
  });
}
