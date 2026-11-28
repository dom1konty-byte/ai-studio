import 'package:chistka_pk/state/app_controller.dart';
import 'package:chistka_pk/ui/app.dart';
import 'package:chistka_pk/ui/glass.dart';
import 'package:chistka_pk/ui/shell.dart';
import 'package:chistka_pk/ui/window_fx.dart';
import 'package:chistka_pk/core/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_platform.dart';

Future<void> _pump(WidgetTester tester, AppController c, {bool onboarding = false}) async {
  tester.view.physicalSize = const Size(1000, 680);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChistoApp(controller: c, onboarding: onboarding));
}

void main() {
  tearDown(() => windowShown.value = true);

  testWidgets('главный экран виден сразу, без заставки; тяжёлая работа — после кадра + 300 мс',
      (tester) async {
    final p = FakePlatform();
    final c = AppController(
      platform: p,
      env: const Env({}),
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
    )..holdHeavy();
    await _pump(tester, c);
    // Первый кадр: главный экран уже на месте, ждать 2 с не нужно.
    expect(find.byType(Shell), findsOneWidget);
    expect(find.byKey(const Key('splash')), findsNothing);
    expect(p.diskCalls, 0);
    await tester.pump(const Duration(milliseconds: 250));
    expect(p.diskCalls, 0); // ещё держим тяжёлую работу
    expect(c.heavyHeld, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump();
    expect(c.heavyHeld, isFalse);
    expect(p.diskCalls, greaterThan(0));
  });

  testWidgets('подсказки первого запуска показываются сразу после первого кадра', (tester) async {
    final c = AppController(
      platform: FakePlatform(),
      env: const Env({}),
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
    );
    await _pump(tester, c, onboarding: true);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('onboarding')), findsOneWidget);
    expect(find.byType(Shell), findsOneWidget);
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
    await _pump(tester, c);
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
}
