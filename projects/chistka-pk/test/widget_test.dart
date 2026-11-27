import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:chistka_pk/ui/app.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

AppController _controller() => AppController(
      platform: FakePlatform(),
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

    expect(find.text('Очистка'), findsOneWidget);
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
}
