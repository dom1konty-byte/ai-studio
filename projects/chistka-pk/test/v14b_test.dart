import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/clean_anim.dart';
import 'package:chistka_pk/core/settings.dart';
import 'package:chistka_pk/platform/mini_window.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:chistka_pk/ui/app.dart';
import 'package:chistka_pk/ui/clean_fx.dart';
import 'package:chistka_pk/ui/mini_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_platform.dart';

AppController _make({String? dir, FakePlatform? p}) => AppController(
      platform: p ?? FakePlatform(),
      env: const Env({}),
      dataDir: dir,
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
    );

Future<void> _pump(WidgetTester tester, AppController c, {bool onboarding = false}) async {
  tester.view.physicalSize = const Size(1200, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChistoApp(controller: c, onboarding: onboarding));
  await tester.pump();
  await tester.pump();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chisto_v14b'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('п.39 счёт вниз', () {
    test('countdownBytes: от total к 0 по доле оставшегося', () {
      expect(countdownBytes(1000, 1), 1000);
      expect(countdownBytes(1000, 0.5), 500);
      expect(countdownBytes(1000, 0), 0);
    });
    test('countdownBytes: мусор ограничен', () {
      expect(countdownBytes(1000, 2), 1000);
      expect(countdownBytes(1000, -1), 0);
      expect(countdownBytes(1000, double.nan), 0);
      expect(countdownBytes(0, 0.5), 0);
      expect(countdownBytes(-5, 0.5), 0);
    });
    testWidgets('DoneBurst: рисуется и заканчивается за ~900 мс', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Center(child: DoneBurst(size: 56, color: Color(0xFF0F9D9A)))));
      expect(find.byKey(const Key('done-burst')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: doneBurstMs + 50));
      expect(tester.hasRunningAnimations, isFalse);
    });
    testWidgets('WaveSweep: бежит при active, без анимаций — нет блика', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: WaveSweep(active: true, child: SizedBox(width: 200, height: 50))));
      expect(find.byKey(const Key('wave-sweep')), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(
          home: WaveSweep(active: false, child: SizedBox(width: 200, height: 50))));
      expect(find.byKey(const Key('wave-sweep')), findsNothing);
    });
    testWidgets('disableAnimations: сразу галочка, без бегущих анимаций', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(const MaterialApp(
          home: Column(children: [
        DoneBurst(size: 56, color: Color(0xFF0F9D9A)),
        WaveSweep(active: true, child: SizedBox(width: 100, height: 40)),
      ])));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byKey(const Key('wave-sweep')), findsNothing);
    });
  });

  group('п.43 подсказки', () {
    test('флаг onboardingDone по умолчанию false и сохраняется', () async {
      expect(const AppSettings().onboardingDone, isFalse);
      final c = _make(dir: tmp.path);
      await c.init();
      await c.finishOnboarding();
      final c2 = _make(dir: tmp.path);
      await c2.init();
      expect(c2.settings.onboardingDone, isTrue);
    });

    testWidgets('показываются при первом запуске; «Далее» ×3 и «Понятно» ставят флаг', (tester) async {
      final c = _make();
      await _pump(tester, c, onboarding: true);
      await tester.pump();
      expect(find.byKey(const Key('onboarding')), findsOneWidget);
      expect(find.text('Здесь очистка'), findsOneWidget);
      for (final t in ['Компьютер', 'Программы', 'Значок у часов']) {
        await tester.tap(find.byKey(const Key('onboarding-next')));
        await tester.pump();
        expect(find.descendant(of: find.byKey(const Key('onboarding-bubble')), matching: find.text(t)),
            findsOneWidget);
      }
      expect(find.text('Понятно'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pump();
      await tester.pump();
      expect(c.settings.onboardingDone, isTrue);
      expect(find.byKey(const Key('onboarding')), findsNothing);
    });

    testWidgets('«Пропустить» ставит флаг; в следующий раз не показываются', (tester) async {
      final c = _make();
      await _pump(tester, c, onboarding: true);
      await tester.pump();
      await tester.tap(find.byKey(const Key('onboarding-skip')));
      await tester.pump();
      await tester.pump();
      expect(c.settings.onboardingDone, isTrue);
      expect(find.byKey(const Key('onboarding')), findsNothing);
    });

    testWidgets('«Показать подсказки снова» в Настройках', (tester) async {
      final c = _make();
      await c.init();
      await c.finishOnboarding();
      await _pump(tester, c, onboarding: true);
      c.go(Section.settings);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('onboarding')), findsNothing);
      await tester.tap(find.byKey(const Key('show-onboarding')));
      await tester.pump();
      await tester.pump();
      expect(c.settings.onboardingDone, isFalse);
      expect(c.section, Section.main);
      expect(find.byKey(const Key('onboarding')), findsOneWidget);
    });
  });

  group('п.44 звук', () {
    test('настройка по умолчанию вкл., сохраняется', () async {
      expect(const AppSettings().cleanSound, isTrue);
      final c = _make(dir: tmp.path);
      await c.init();
      await c.setCleanSound(false);
      final c2 = _make(dir: tmp.path);
      await c2.init();
      expect(c2.settings.cleanSound, isFalse);
    });

    test('быстрая очистка играет звук; выключено — тишина', () async {
      final p = FakePlatform();
      final c = _make(dir: tmp.path, p: p);
      await c.init();
      c.settings = c.settings.copyWith(quickCategories: ['temp']);
      await c.quickClean();
      expect(p.soundPlays, hasLength(1));
      expect(p.soundPlays.single, endsWith('drop.wav'));
      await c.setCleanSound(false);
      await c.quickClean();
      expect(p.soundPlays, hasLength(1));
    });

    test('WAV: 44,1 кГц, mono, 16 бит, не длиннее 0,4 с', () {
      final f = File('assets/sounds/drop.wav').readAsBytesSync();
      final d = ByteData.sublistView(f);
      expect(String.fromCharCodes(f.sublist(0, 4)), 'RIFF');
      expect(d.getUint16(22, Endian.little), 1);
      expect(d.getUint32(24, Endian.little), 44100);
      expect(d.getUint16(34, Endian.little), 16);
      expect((f.length - 44) / 2 / 44100, lessThanOrEqualTo(0.4));
    });
  });

  group('п.48 мини-окно', () {
    test('позиция: правый нижний угол рабочей области с учётом масштаба', () {
      final pos = miniPosition(const Rect.fromLTRB(0, 0, 3000, 1560), 1.5);
      expect(pos.dx, 3000 / 1.5 - 360 - 12);
      expect(pos.dy, 1560 / 1.5 - 480 - 12);
    });

    test('speedWhen: сегодня / вчера / дата', () {
      final now = DateTime(2026, 8, 12, 20);
      expect(speedWhen(DateTime(2026, 8, 12, 14, 32), now), 'сегодня 14:32');
      expect(speedWhen(DateTime(2026, 8, 11, 9, 5), now), 'вчера 09:05');
      expect(speedWhen(DateTime(2026, 8, 1, 9, 5), now), '01.08 09:05');
    });

    test('контроллер: переключение режимов вызывает оконный хук', () async {
      final c = _make();
      final calls = <bool>[];
      c.miniWindowHook = (m) async => calls.add(m);
      await c.setMiniMode(true);
      await c.setMiniMode(true);
      expect(c.miniMode, isTrue);
      await c.setMiniMode(false);
      expect(c.miniMode, isFalse);
      expect(calls, [true, false]);
    });

    testWidgets('мини-вид рендерится; «Открыть ЧистоДиск» возвращает полный вид', (tester) async {
      final c = _make();
      await _pump(tester, c);
      expect(find.byKey(const Key('mini-view')), findsNothing);
      await c.setMiniMode(true);
      await tester.pump();
      expect(find.byKey(const Key('mini-view')), findsOneWidget);
      expect(find.byKey(const Key('mini-ring')), findsOneWidget);
      expect(find.byKey(const Key('mini-quick')), findsOneWidget);
      expect(find.text('Ещё не замеряли'), findsOneWidget);
      expect(find.text('Замерить'), findsOneWidget);
      await tester.tap(find.byKey(const Key('mini-open')));
      await tester.pump();
      expect(c.miniMode, isFalse);
      expect(find.byKey(const Key('mini-view')), findsNothing);
    });

    testWidgets('Esc в мини-виде прячет окно (hideMini)', (tester) async {
      final c = _make();
      var hidden = 0;
      c.hideMiniHook = () async {
        hidden++;
        await c.setMiniMode(false);
      };
      await _pump(tester, c);
      await c.setMiniMode(true);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(hidden, 1);
      expect(c.miniMode, isFalse);
    });

    test('quickClean ставит quickFreedBytes (для итога в мини-окне)', () async {
      final c = _make(dir: tmp.path);
      await c.init();
      c.settings = c.settings.copyWith(quickCategories: ['temp']);
      await c.quickClean();
      expect(c.quickFreedBytes, isNotNull);
    });

    testWidgets('мини-вид: итог «Освобождено» и анимация очистки', (tester) async {
      final c = _make();
      await _pump(tester, c);
      await c.setMiniMode(true);
      c.quickFreedBytes = 2048;
      c.notifyListeners();
      await tester.pump();
      expect(find.byKey(const Key('mini-freed')), findsOneWidget);
      expect(find.text('Освобождено 2,0 КБ'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
