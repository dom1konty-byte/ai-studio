import 'package:chistka_pk/state/app_controller.dart';
import 'package:chistka_pk/ui/app.dart';
import 'package:chistka_pk/ui/frame_log.dart';
import 'package:chistka_pk/ui/glass.dart';
import 'package:chistka_pk/ui/splash.dart';
import 'package:chistka_pk/ui/window_fx.dart';
import 'package:chistka_pk/core/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_platform.dart';

/// Платформа, запоминающая момент первого тяжёлого вызова.
class _TimedPlatform extends FakePlatform {
  _TimedPlatform(this.clock);
  final Stopwatch clock;
  Duration? firstHeavy;

  void _mark() => firstHeavy ??= clock.elapsed;

  @override
  Future<bool> isElevated() async {
    _mark();
    return false;
  }

  @override
  Future<({int free, int total})?> diskSpace(String root) {
    _mark();
    return super.diskSpace(root);
  }
}

Future<void> _pump(WidgetTester tester, AppController c, {bool splash = true}) async {
  tester.view.physicalSize = const Size(1000, 680);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChistoApp(controller: c, splash: splash));
}

void main() {
  tearDown(() => windowShown.value = true);

  testWidgets('тяжёлая инициализация не стартует до конца заставки', (tester) async {
    final clock = Stopwatch();
    final p = _TimedPlatform(clock);
    final c = AppController(
      platform: p,
      env: const Env({}),
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
    )..holdHeavy();
    await _pump(tester, c);
    await tester.pump();
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 1,9 с: заставка ещё идёт — платформа не тронута, волны остановлены.
    expect(find.byKey(const Key('splash')), findsOneWidget);
    expect(p.firstHeavy, isNull);
    expect(p.diskCalls, 0);
    expect(windowShown.value, isFalse);
    clock.start();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('splash')), findsNothing);
    expect(p.firstHeavy, isNotNull);
    expect(windowShown.value, isTrue);
  });

  testWidgets('пропуск щелчком тоже запускает тяжёлую работу', (tester) async {
    final p = FakePlatform();
    final c = AppController(
      platform: p,
      env: const Env({}),
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
    )..holdHeavy();
    await _pump(tester, c);
    await tester.pump(const Duration(milliseconds: 300));
    expect(p.diskCalls, 0);
    await tester.tap(find.byKey(const Key('splash')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.byKey(const Key('splash')), findsNothing);
    expect(p.diskCalls, greaterThan(0));
  });

  testWidgets('заставка длится 2 с', (tester) async {
    expect(splashMs, 2000);
    final c = AppController(
      platform: FakePlatform(),
      env: const Env({}),
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
    );
    await _pump(tester, c);
    await tester.pump(const Duration(milliseconds: 1950));
    expect(find.byKey(const Key('splash')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('splash')), findsNothing);
  });

  test('длительности: закрытие 380 мс, открытие 340 мс', () {
    expect(windowFxHideDuration.inMilliseconds, 380);
    expect(windowFxShowDuration.inMilliseconds, 340);
    expect(windowFxHideScale, 0.94);
    expect(windowFxShowScale, 0.94);
  });

  testWidgets('закрытие: ещё идёт в 370 мс, готово к 390 мс; открытие — 340 мс', (tester) async {
    final c = AppController(
      platform: FakePlatform(),
      env: const Env({}),
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
    );
    await _pump(tester, c, splash: false);
    await tester.pump();
    var hidden = false;
    windowFx.playHide().then((_) => hidden = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 370));
    expect(hidden, isFalse);
    await tester.pump(const Duration(milliseconds: 20));
    expect(hidden, isTrue);
    windowFx.reset();
    windowFx.prepareShow();
    await tester.pump();
    var shown = false;
    windowFx.playShow().then((_) => shown = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 330));
    expect(shown, isFalse);
    await tester.pump(const Duration(milliseconds: 20));
    expect(shown, isTrue);
  });

  test('FrameStats считает кадры', () {
    final s = FrameStats()
      ..add(8)
      ..add(30)
      ..add(10);
    expect(s.count, 3);
    expect(s.max, 30);
    expect(s.slow, 1);
    expect(s.avg, closeTo(16, 0.01));
  });
}
