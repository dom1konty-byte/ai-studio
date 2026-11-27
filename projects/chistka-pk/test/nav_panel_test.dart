import 'dart:convert';
import 'dart:io';

import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/settings.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:chistka_pk/ui/about_dialog.dart';
import 'package:chistka_pk/ui/app.dart';
import 'package:chistka_pk/ui/nav_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_platform.dart';

AppController _controller({String? dir}) => AppController(
      platform: FakePlatform(),
      env: const Env({}),
      dataDir: dir,
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
    );

Finder _inNav(Finder f) => find.descendant(of: find.byType(NavPanel), matching: f);

Future<void> _pump(WidgetTester tester, AppController c, {Size size = const Size(1000, 680)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChistoApp(controller: c));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('Группа «Очистка» раскрывается и сворачивается', (tester) async {
    await _pump(tester, _controller());
    for (final t in ['Загрузки', 'Большие файлы', 'Карта диска']) {
      expect(_inNav(find.text(t)), findsOneWidget);
    }
    expect(_inNav(find.text('Интернет')), findsOneWidget);

    await tester.tap(_inNav(find.text('Очистка')).first); // заголовок группы
    await tester.pumpAndSettle();
    expect(_inNav(find.text('Загрузки')), findsNothing);
    expect(_inNav(find.text('Программы')), findsOneWidget);

    await tester.tap(_inNav(find.text('Очистка')).first);
    await tester.pumpAndSettle();
    expect(_inNav(find.text('Загрузки')), findsOneWidget);
  });

  testWidgets('Узкая панель (< 120 px): только иконки с подсказками', (tester) async {
    final c = _controller()..previewNavWidth(80);
    await _pump(tester, c);
    expect(_inNav(find.text('Программы')), findsNothing);
    expect(_inNav(find.text('ЧистоДиск')), findsNothing);
    expect(_inNav(find.byIcon(Icons.apps_outlined)), findsOneWidget);
    expect(_inNav(find.byIcon(Icons.download_outlined)), findsOneWidget); // иконка подпункта
    expect(find.byTooltip('Программы'), findsOneWidget);
    expect(find.byTooltip('Настройки'), findsOneWidget);
    expect(find.byTooltip('Журнал'), findsOneWidget);
  });

  testWidgets('Узкое окно 900x600: панель с 6+4 пунктами помещается', (tester) async {
    await _pump(tester, _controller(), size: const Size(900, 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Клик по логотипу открывает «О программе»', (tester) async {
    await _pump(tester, _controller());
    await tester.tap(find.byKey(const Key('nav-logo')));
    await tester.pumpAndSettle();
    expect(find.text('Издатель: Дамир'), findsOneWidget);
    expect(find.text('Версия $appVersion'), findsOneWidget);
    expect(find.text('Предложить идею / связь'), findsOneWidget);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.text('Издатель: Дамир'), findsNothing);
  });

  testWidgets('Перетаскивание края меняет ширину в пределах 64–360', (tester) async {
    final c = _controller();
    await _pump(tester, c);
    expect(c.settings.navWidth, defaultNavWidth);
    await tester.drag(find.byKey(const Key('nav-edge')), const Offset(-1000, 0));
    await tester.pump();
    expect(c.settings.navWidth, minNavWidth);
    await tester.drag(find.byKey(const Key('nav-edge')), const Offset(1000, 0));
    await tester.pump();
    expect(c.settings.navWidth, maxNavWidth);
    // Распознаватель двойного нажатия держит таймер — дать ему истечь.
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('Пункт «Интернет» открывает тест скорости', (tester) async {
    await _pump(tester, _controller());
    await tester.tap(_inNav(find.text('Интернет')));
    await tester.pumpAndSettle();
    expect(find.text('Нажмите «Начать»'), findsOneWidget);
  });

  testWidgets('Плашка администратора скрыта по умолчанию', (tester) async {
    await _pump(tester, _controller());
    expect(find.text('Режим администратора'), findsNothing);
  });

  group('ширина панели в settings.json', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('chisto_nav'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('сохраняется, ограничивается и читается при запуске', () async {
      final c = _controller(dir: tmp.path);
      await c.init();
      await c.setNavWidth(500);
      final saved = jsonDecode(File('${tmp.path}/settings.json').readAsStringSync()) as Map;
      expect(saved['navWidth'], maxNavWidth);
      await c.setNavWidth(100);
      final c2 = _controller(dir: tmp.path);
      await c2.init();
      expect(c2.settings.navWidth, 100);
    });

    test('мусор в файле — ширина по умолчанию', () {
      expect(AppSettings.fromJson({'navWidth': 'abc'}).navWidth, defaultNavWidth);
      expect(AppSettings.fromJson({'navWidth': 5}).navWidth, minNavWidth);
    });
  });

  test('версия в коде совпадает с pubspec.yaml', () {
    final v = RegExp(r'^version:\s*([0-9.]+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!
        .group(1);
    expect(appVersion, v);
  });
}
