import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:chistka_pk/ui/app.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

AppController _controller([FakePlatform? p]) => AppController(
      platform: p ?? FakePlatform(),
      env: const Env({}),
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
    );

void main() {
  testWidgets('Пульт до анализа: размер не показан, Загрузки не запущены, ничего не удалено',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final p = FakePlatform();
    final c = _controller(p);
    await tester.pumpWidget(ChistoApp(controller: c));
    await tester.pump();
    await tester.pump();

    expect(find.text('Очистка'), findsWidgets); // панель + заголовок экрана
    // Анализ стартует сам (в фоне), но ничего не удаляет.
    expect(c.phase, isNot(Phase.cleaning));
    expect(c.phase, isNot(Phase.done));
    expect(c.downloadsSelected, isEmpty);
    expect(c.downloadsState, LoadState.idle);
    expect(find.text('Найти'), findsNWidgets(4)); // Загрузки, Большие файлы, Дубликаты, Пустые папки
    expect(p.binEmptied, isFalse);
    expect(p.moved, isEmpty);
  });

  Future<void> pumpWith(WidgetTester tester, int freeGb) async {
    tester.view.physicalSize = const Size(1000, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final p = FakePlatform()..freeBytes = freeGb * 1024 * 1024 * 1024;
    final c = _controller(p);
    await tester.pumpWidget(ChistoApp(controller: c));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Плашка «Мало места» видна при свободно < 10 ГБ', (tester) async {
    await pumpWith(tester, 6);
    expect(find.textContaining('Мало места'), findsOneWidget);
  });

  testWidgets('Плашка «Мало места» скрыта при свободно >= 10 ГБ', (tester) async {
    await pumpWith(tester, 10);
    expect(find.textContaining('Мало места'), findsNothing);
  });
}
