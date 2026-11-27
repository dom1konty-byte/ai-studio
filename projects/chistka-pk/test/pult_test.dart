import 'dart:async';
import 'dart:io';

import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/models.dart';
import 'package:chistka_pk/core/scanner.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:chistka_pk/ui/app.dart';
import 'package:chistka_pk/ui/splash.dart';
import 'package:chistka_pk/ui/window_fx.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_platform.dart';

AppController _make({
  Directory? tmp,
  FakePlatform? platform,
  DownloadsScan? downloads,
  LargeScan? large,
}) =>
    AppController(
      platform: platform ?? FakePlatform(),
      env: tmp == null ? const Env({}) : Env({'USERPROFILE': tmp.path}),
      dataDir: tmp == null ? null : '${tmp.path}/data',
      downloadsScan: downloads ?? (_) async => [],
      largeScan: large ?? (_, __) async => [],
    );

Future<void> _pump(WidgetTester tester, AppController c,
    {Size size = const Size(1200, 760), bool splash = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChistoApp(controller: c, splash: splash));
  await tester.pump();
  await tester.pump();
}

/// Очистка пишет журнал настоящими файлами — ждём её вне «фальшивого» времени теста.
Future<void> _untilDone(WidgetTester tester, AppController c) async {
  for (var i = 0; i < 100 && c.phase != Phase.done; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chisto_pult');
    // downloadsDir = "<profile>\Downloads": на Linux это папка с обратной чертой в имени.
    Directory('${tmp.path}\\Downloads').createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('Пульт: полоска диска, быстрая очистка и 5 плиток в 3 колонки', (tester) async {
    await _pump(tester, _make(tmp: tmp));
    expect(find.textContaining('Диск '), findsOneWidget);
    expect(find.text('Быстрая очистка'), findsOneWidget);
    expect(find.text('Что чистить?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Очистить'), findsOneWidget);
    final titles = ['Загрузки', 'Большие файлы', 'Дубликаты', 'Пустые папки', 'Карта диска'];
    for (final t in titles) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // Первый ряд — три плитки, второй — две.
    final y = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
    expect(y[0], y[1]);
    expect(y[1], y[2]);
    expect(y[3], y[4]);
    expect(y[3], greaterThan(y[0]));
    // Полоса быстрой очистки — 88 px.
    final strip = find.ancestor(of: find.text('Быстрая очистка'), matching: find.byType(Container)).first;
    expect(tester.getSize(strip).height, greaterThanOrEqualTo(88));
    // Дубликаты и Пустые папки — рабочие плитки (кнопка «Найти»).
    expect(find.text('Скоро'), findsNothing);
    expect(find.text('Найти'), findsNWidgets(4));
  });

  testWidgets('Две колонки при узком содержимом', (tester) async {
    await _pump(tester, _make(tmp: tmp), size: const Size(1000, 700));
    final a = tester.getTopLeft(find.text('Загрузки'));
    final b = tester.getTopLeft(find.text('Большие файлы'));
    final c = tester.getTopLeft(find.text('Дубликаты'));
    expect(a.dy, b.dy);
    expect(c.dy, greaterThan(a.dy));
  });

  testWidgets('«Что чистить?»: панель с галочками категорий, запускает анализ', (tester) async {
    final c = _make(tmp: tmp);
    await _pump(tester, c);
    expect(find.byKey(const Key('what-to-clean-panel')), findsNothing);
    await tester.tap(find.byKey(const Key('what-to-clean')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('what-to-clean-panel')), findsOneWidget);
    expect(c.phase, Phase.ready);
    expect(find.byType(CheckboxListTile), findsWidgets);
    expect(find.byKey(const ValueKey('cat-recycle')), findsOneWidget);
    final box = tester.widget<CheckboxListTile>(find.byKey(const ValueKey('cat-recycle')));
    expect(box.value, isTrue);
    await tester.tap(find.byKey(const ValueKey('cat-recycle')));
    await tester.pump();
    expect(c.rows.firstWhere((r) => r.category.id == CategoryId.recycle).selected, isFalse);
    // Свернуть обратно.
    await tester.tap(find.byKey(const Key('what-to-clean')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('what-to-clean-panel')), findsNothing);
  });

  testWidgets('«Очистить» без анализа: сначала анализ, потом очистка; в полосе «Освобождено»',
      (tester) async {
    final p = FakePlatform();
    final c = _make(tmp: tmp, platform: p);
    await _pump(tester, c);
    expect(find.textContaining('Можно освободить'), findsNothing);
    await tester.tap(find.byKey(const Key('quick-clean')));
    await _untilDone(tester, c);
    expect(p.binEmptied, isTrue);
    expect(c.phase, Phase.done);
    expect(find.textContaining('Освобождено'), findsOneWidget);
    expect(find.text('Подробнее'), findsOneWidget);
    // «Подробнее» — прежний экран «Итог».
    await tester.tap(find.text('Подробнее'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Удалено файлов'), findsOneWidget);
    await tester.tap(find.text('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('Подробнее'), findsOneWidget);
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(c.phase, Phase.idle);
    expect(find.widgetWithText(FilledButton, 'Очистить'), findsOneWidget);
  });

  testWidgets('Браузер запущен: диалог как раньше, «Пропустить» не чистит кэш', (tester) async {
    final p = FakePlatform()..browsers = ['Chrome'];
    final c = _make(tmp: tmp, platform: p);
    await _pump(tester, c);
    // Анализ уже сделан: отмечен кэш браузеров.
    final r = c.rows.firstWhere((r) => r.category.id == CategoryId.browsers);
    r.bytes = 500;
    r.status = RowStatus.done;
    c.phase = Phase.ready;
    c.toggleRow(r, true);
    await tester.pump();
    await tester.tap(find.byKey(const Key('quick-clean')));
    await tester.pumpAndSettle();
    expect(find.text('Закройте браузер'), findsOneWidget);
    await tester.tap(find.text('Пропустить кэш браузеров'));
    await _untilDone(tester, c);
    expect(c.phase, Phase.done);
    expect(c.summary!.browsersSkipped, isTrue);
  });

  testWidgets('Загрузки: Найти → процесс → итог → Выбрать → список поверх → Назад', (tester) async {
    final gate = Completer<List<FileInfo>>();
    final now = DateTime.now();
    final c = _make(tmp: tmp, downloads: (_) => gate.future);
    await _pump(tester, c);
    expect(find.text('Найти'), findsNWidgets(4));
    await tester.tap(find.text('Найти').first);
    await tester.pump();
    expect(find.text('Ищу…'), findsOneWidget);
    expect(find.text('Стоп'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    gate.complete([
      FileInfo('C:/d/old.iso', 3 * 1024 * 1024, now.subtract(const Duration(days: 90))),
      FileInfo('C:/d/mid.zip', 2048, now.subtract(const Duration(days: 15))),
      FileInfo('C:/d/new.txt', 100, now.subtract(const Duration(days: 1))),
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Найдено 1, 3'), findsOneWidget); // старше 30 дней
    expect(find.text('Выбрать'), findsOneWidget);
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('layer-back')), findsOneWidget);
    expect(find.text('old.iso'), findsOneWidget);
    expect(find.text('mid.zip'), findsNothing);
    expect(c.downloadsSelected, isEmpty); // ничего не отмечено
    // «Назад» закрывает слой.
    await tester.tap(find.byKey(const Key('layer-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('layer-back')), findsNothing);
    expect(c.layer, Layer.none);
  });

  testWidgets('Загрузки: ошибка поиска — «Не удалось» и «Повторить»', (tester) async {
    var n = 0;
    final c = _make(tmp: tmp, downloads: (_) async {
      if (n++ == 0) throw const FileSystemException('x');
      return [];
    });
    await _pump(tester, c);
    await tester.tap(find.text('Найти').first);
    await tester.pumpAndSettle();
    expect(find.text('Не удалось'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Пусто ✓'), findsOneWidget);
  });

  testWidgets('Загрузки: «Стоп» отменяет поиск, поздний результат игнорируется', (tester) async {
    final gate = Completer<List<FileInfo>>();
    final c = _make(tmp: tmp, downloads: (_) => gate.future);
    await _pump(tester, c);
    await tester.tap(find.text('Найти').first);
    await tester.pump();
    await tester.tap(find.text('Стоп'));
    await tester.pump();
    gate.complete([FileInfo('C:/d/x', 1, DateTime(2020))]);
    await tester.pumpAndSettle();
    expect(c.downloadsState, LoadState.idle);
    expect(c.downloads, isEmpty);
  });

  testWidgets('Фильтр Загрузок: по умолчанию «Старше 30 дней», Все / Новые переключают список',
      (tester) async {
    final now = DateTime.now();
    final c = _make(tmp: tmp, downloads: (_) async => [
          FileInfo('C:/d/old.iso', 3000, now.subtract(const Duration(days: 90))),
          FileInfo('C:/d/mid.zip', 2000, now.subtract(const Duration(days: 15))),
          FileInfo('C:/d/new.txt', 100, now.subtract(const Duration(days: 1))),
        ]);
    await _pump(tester, c);
    await tester.tap(find.text('Найти').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    expect(c.downloadsFilter, DownloadsFilter.old);
    final seg = tester.widget<SegmentedButton<DownloadsFilter>>(find.byKey(const Key('downloads-filter')));
    expect(seg.selected, {DownloadsFilter.old});
    expect(find.text('old.iso'), findsOneWidget);
    expect(find.text('new.txt'), findsNothing);

    await tester.tap(find.text('Все'));
    await tester.pumpAndSettle();
    expect(find.text('old.iso'), findsOneWidget);
    expect(find.text('mid.zip'), findsOneWidget);
    expect(find.text('new.txt'), findsOneWidget);
    expect(c.downloadsSelected, isEmpty);

    await tester.tap(find.textContaining('Новые'));
    await tester.pumpAndSettle();
    expect(find.text('new.txt'), findsOneWidget);
    expect(find.text('old.iso'), findsNothing);

    // Отметка и смена фильтра: отмеченное вне фильтра снимается.
    await tester.tap(find.text('Все'));
    await tester.pumpAndSettle();
    c.toggleDownload('C:/d/old.iso', true);
    c.setDownloadsFilter(DownloadsFilter.recent);
    expect(c.downloadsSelected, isEmpty);
  });

  testWidgets('Загрузки: удаление только в Корзину, после подтверждения', (tester) async {
    final p = FakePlatform();
    final file = File('${tmp.path}\\Downloads/old.iso')..writeAsStringSync('x');
    final now = DateTime.now();
    final c = _make(tmp: tmp, platform: p, downloads: (_) async => [
          FileInfo(file.path, 5, now.subtract(const Duration(days: 90))),
        ]);
    await c.init();
    await _pump(tester, c);
    await tester.tap(find.text('Найти').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'В Корзину')).onPressed, isNull);
    c.toggleDownload(file.path, true);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'В Корзину'));
    await tester.pumpAndSettle();
    expect(p.moved, isEmpty); // ждём подтверждения
    await tester.tap(find.widgetWithText(FilledButton, 'В Корзину').last);
    await _untilDone(tester, c);
    // Путь Linux не проходит Windows-защиту очистки: файл пропущен, но слой закрыт,
    // а итог показан (удаление насовсем невозможно: только moveToRecycleBin).
    expect(p.moved.every((m) => m == file.path), isTrue);
    expect(c.layer, Layer.none);
    expect(c.phase, Phase.done);
    expect(c.downloadsRecycled, isNotNull);
  });

  testWidgets('Карта диска: «Открыть» → экран поверх, Esc закрывает', (tester) async {
    final c = _make(tmp: tmp);
    await _pump(tester, c);
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(c.layer, Layer.map);
    expect(find.text('Только просмотр, ничего не удаляется'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(c.layer, Layer.none);
  });

  testWidgets('Большие файлы: итог в плитке и «Выбрать»', (tester) async {
    final c = _make(tmp: tmp, large: (_, __) async => [
          FileInfo('C:/v/a.mkv', 2 * 1024 * 1024 * 1024, DateTime(2024)),
          FileInfo('C:/v/b.mkv', 1024 * 1024 * 1024, DateTime(2024)),
        ]);
    await _pump(tester, c);
    await tester.tap(find.text('Найти').at(1));
    await tester.pumpAndSettle();
    expect(find.textContaining('Найдено 2, 3'), findsOneWidget);
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    expect(c.layer, Layer.big);
    expect(find.text('a.mkv'), findsOneWidget);
  });

  testWidgets('Компьютер: плитки «Здоровье диска» и «Что тормозит» вместо заглушек', (tester) async {
    final c = _make(tmp: tmp);
    await _pump(tester, c);
    c.go(Section.computer);
    await tester.pumpAndSettle();
    for (final t in ['Здоровье диска', 'Что тормозит']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Скоро'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  group('заставка', () {
    testWidgets('показывается ~1 с и пропускается щелчком', (tester) async {
      await _pump(tester, _make(tmp: tmp), splash: true);
      expect(find.byKey(const Key('splash')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('splash')), findsOneWidget);
      await tester.tap(find.byKey(const Key('splash')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('splash')), findsNothing);
    });

    testWidgets('сама заканчивается за ~1,15 с', (tester) async {
      await _pump(tester, _make(tmp: tmp), splash: true);
      await tester.pump(const Duration(milliseconds: splashMs - 100));
      expect(find.byKey(const Key('splash')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('splash')), findsNothing);
    });

    testWidgets('нет заставки при --tray (splash: false)', (tester) async {
      await _pump(tester, _make(tmp: tmp));
      expect(find.byKey(const Key('splash')), findsNothing);
    });

    testWidgets('нет заставки при «Убрать анимации»', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pump(tester, _make(tmp: tmp), splash: true);
      expect(find.byKey(const Key('splash')), findsNothing);
    });
  });

  group('плавное сворачивание (содержимое внутри Flutter)', () {
    testWidgets('содержимое уменьшается к правому нижнему углу и затухает за 220 мс', (tester) async {
      await _pump(tester, _make(tmp: tmp));
      expect(windowFx.amount, 0);
      var done = false;
      windowFx.playHide().then((_) => done = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      expect(windowFx.amount, inExclusiveRange(0, 1));
      expect(done, isFalse);
      await tester.pump(const Duration(milliseconds: 120));
      expect(done, isTrue);
      expect(windowFx.amount, 1);
      final op = tester.widget<Opacity>(find.descendant(
          of: find.byType(WindowFxHost), matching: find.byType(Opacity)).first);
      expect(op.opacity, 0);
      windowFx.reset();
      await tester.pump();
      expect(windowFx.amount, 0);
    });

    testWidgets('показ: prepareShow прячет содержимое, playShow возвращает', (tester) async {
      await _pump(tester, _make(tmp: tmp));
      windowFx.prepareShow();
      await tester.pump();
      expect(windowFx.amount, 1);
      var done = false;
      windowFx.playShow().then((_) => done = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 230));
      expect(done, isTrue);
      expect(windowFx.amount, 0);
    });

    testWidgets('«Убрать анимации»: без ожидания', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pump(tester, _make(tmp: tmp));
      var done = false;
      windowFx.playHide().then((_) => done = true);
      await tester.pump();
      expect(done, isTrue);
      windowFx.reset();
    });
  });
}
