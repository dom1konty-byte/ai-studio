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
  testWidgets('Главный экран до анализа: «Очистить» неактивна, Загрузки выключены',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ChistoApp(controller: _controller()));
    await tester.pump();
    await tester.pump();

    expect(find.text('Очистка'), findsWidgets); // панель + заголовок экрана
    expect(find.text('Нажмите «Анализ»'), findsOneWidget);

    final clean = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Очистить'));
    expect(clean.onPressed, isNull);
    final analyze = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Анализ'));
    expect(analyze.onPressed, isNotNull);

    final tile = find.widgetWithText(CheckboxListTile, 'Загрузки');
    await tester.scrollUntilVisible(tile, 200);
    final downloads = tester.widget<CheckboxListTile>(tile);
    expect(downloads.value, isFalse);
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
