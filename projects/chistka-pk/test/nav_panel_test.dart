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
  testWidgets('Навигация плоская: 5 пунктов, групп нет, внизу Настройки и Журнал', (tester) async {
    await _pump(tester, _controller());
    for (final t in ['Очистка', 'Компьютер', 'Программы', 'Автозагрузка', 'Интернет']) {
      expect(_inNav(find.text(t)), findsOneWidget);
    }
    // Бывшие подпункты группы больше не пункты панели.
    for (final t in ['Загрузки', 'Большие файлы', 'Карта диска']) {
      expect(_inNav(find.text(t)), findsNothing);
    }
    expect(find.byType(ExpansionTile), findsNothing);
    expect(_inNav(find.byType(PopupMenuButton<Section>)), findsNothing);
    expect(find.byTooltip('Настройки'), findsOneWidget);
    expect(find.byTooltip('Журнал'), findsOneWidget);
    // Настройки и Журнал рядом, в одной строке.
    final s = tester.getCenter(find.byTooltip('Настройки'));
    final j = tester.getCenter(find.byTooltip('Журнал'));
    expect(s.dy, j.dy);

    await tester.tap(_inNav(find.text('Компьютер')));
    await tester.pumpAndSettle();
    expect(c0(tester), Section.computer);
    expect(find.text('Здоровье диска'), findsOneWidget);
  });

  testWidgets('Узкая панель (< 120 px): только иконки с подсказками', (tester) async {
    final c = _controller()..previewNavWidth(80);
    await _pump(tester, c);
    expect(_inNav(find.text('Программы')), findsNothing);
    expect(_inNav(find.text('ЧистоДиск')), findsNothing);
    for (final i in [
      Icons.cleaning_services_outlined,
      Icons.computer_outlined,
      Icons.apps_outlined,
      Icons.rocket_launch_outlined,
      Icons.network_check,
    ]) {
      expect(_inNav(find.byIcon(i)), findsOneWidget);
    }
    for (final t in ['Очистка', 'Компьютер', 'Программы', 'Автозагрузка', 'Интернет', 'Настройки', 'Журнал']) {
      expect(find.byTooltip(t), findsOneWidget);
    }
    await tester.tap(find.byTooltip('Компьютер'));
    await tester.pumpAndSettle();
    expect(c.section, Section.computer);
  });

  testWidgets('Узкое окно 900x600: панель помещается', (tester) async {
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

  testWidgets('Двойной клик по краю: плавно 240 -> 72 и обратно, ширина сохраняется в конце', (tester) async {
    final c = _controller();
    await _pump(tester, c);
    Future<void> dbl() async {
      final p = tester.getCenter(find.byKey(const Key('nav-edge')));
      await tester.tapAt(p);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(p);
      await tester.pump();
    }

    await dbl();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = tester.getSize(find.byType(NavPanel)).width - 6;
    expect(mid, inExclusiveRange(72, 240)); // посередине анимации
    expect(c.settings.navWidth, defaultNavWidth); // в настройках ещё старое
    await tester.pumpAndSettle();
    expect(c.settings.navWidth, 72);
    await dbl();
    await tester.pumpAndSettle();
    expect(c.settings.navWidth, defaultNavWidth);
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

Section c0(WidgetTester tester) =>
    (tester.widget<NavPanel>(find.byType(NavPanel))).controller.section;
