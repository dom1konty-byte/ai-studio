
import 'package:chistka_pk/platform/mini_window.dart';
import 'package:chistka_pk/platform/show_guard.dart';
import 'package:chistka_pk/platform/window_hide.dart';
import 'package:chistka_pk/ui/glass.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('клик по трею: видимое обычное окно -> на передний план, не мини', () {
    expect(trayClickAction(visible: true, minimized: false, miniMode: false),
        TrayClickAction.focusWindow);
    expect(trayClickAction(visible: false, minimized: false, miniMode: false),
        TrayClickAction.openMini);
    expect(trayClickAction(visible: true, minimized: true, miniMode: false),
        TrayClickAction.openMini);
    expect(trayClickAction(visible: true, minimized: false, miniMode: true),
        TrayClickAction.openMini);
  });

  test('MiniWindow.apply: строго по очереди, _on после успеха', () async {
    var running = 0, maxRunning = 0;
    final order = <bool>[];
    var fail = true;
    final w = MiniWindow(body: (mini) async {
      running++;
      maxRunning = running > maxRunning ? running : maxRunning;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      order.add(mini);
      running--;
      if (fail) throw StateError('x');
    });
    await w.apply(true); // сбой — флаг не ставится
    expect(w.isOn, isFalse);
    fail = false;
    final a = w.apply(true);
    final b = w.apply(false);
    final c = w.apply(true);
    await Future.wait([a, b, c]);
    expect(maxRunning, 1);
    expect(order, [true, true, false, true]);
    expect(w.isOn, isTrue);
  });

  test('SavedBounds: восстановление и сброс', () {
    final b = SavedBounds();
    expect(b.take(), isNull); // нет сохранённых -> центр 1000x680
    b.save(const Rect.fromLTWH(10, 20, 900, 700));
    expect(b.take(), const Rect.fromLTWH(10, 20, 900, 700));
    expect(b.take(), isNull);
  });

  testWidgets('ShowGuard: страховочный показ через 2,5 с', (tester) async {
    var fired = 0;
    final g = ShowGuard(onTimeout: () => fired++)..start();
    await tester.pump(const Duration(milliseconds: 2400));
    expect(fired, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(fired, 1);
    final g2 = ShowGuard(onTimeout: () => fired++)..start();
    g2.markShown();
    await tester.pump(const Duration(seconds: 3));
    expect(fired, 1);
    expect(g.shown, isFalse);
  });

  testWidgets('волны останавливаются при скрытии окна и идут при показе', (tester) async {
    windowShown.value = true;
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: WavesBackground())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    windowShown.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isFalse);
    windowShown.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  test('скрытие окна мгновенное: волны стоят, границы сохранены, затем hide', () async {
    final log = <String>[];
    windowShown.value = true;
    await hideWindowNow(
      pause: () {
        windowShown.value = false;
        log.add('pause');
      },
      saveBounds: () async => log.add('bounds'),
      hide: () async => log.add('hide'),
    );
    expect(log, ['pause', 'bounds', 'hide']);
    expect(windowShown.value, isFalse);
    windowShown.value = true;
  });

  test('скрытие: ошибка сохранения границ не мешает спрятать окно', () async {
    var hidden = false;
    await hideWindowNow(
      pause: () {},
      saveBounds: () async => throw Exception('x'),
      hide: () async => hidden = true,
    );
    expect(hidden, isTrue);
  });
}
