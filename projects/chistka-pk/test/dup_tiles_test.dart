import 'dart:async';
import 'dart:io';

import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/duplicates.dart';
import 'package:chistka_pk/core/models.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:chistka_pk/ui/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_platform.dart';

DupGroup _group() => DupGroup([
      FileInfo(r'C:\Users\X\Documents\a.jpg', 5 * 1024 * 1024, DateTime(2020)),
      FileInfo(r'C:\Users\X\Downloads\a (1).jpg', 5 * 1024 * 1024, DateTime(2023)),
    ]);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chisto_duptile'));
  tearDown(() => tmp.deleteSync(recursive: true));

  AppController make({DupScanner? dup, EmptyDirsScan? empty, FakePlatform? p}) => AppController(
        platform: p ?? FakePlatform(),
        env: Env({'USERPROFILE': tmp.path}),
        dataDir: '${tmp.path}/data',
        downloadsScan: (_) async => [],
        largeScan: (_, __) async => [],
        dupScanner: dup,
        emptyDirsScan: empty,
      );

  Future<void> pump(WidgetTester tester, AppController c) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChistoApp(controller: c));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Дубликаты: поиск, итог, панель, нельзя отметить все, подтверждение', (tester) async {
    final job = Completer<List<DupGroup>>();
    final c = make(dup: (roots, progress) {
      progress('Сравниваю: Загрузки…');
      return DupScanJob(job.future, () {});
    });
    await pump(tester, c);
    await tester.tap(find.text('Найти').at(2));
    await tester.pump();
    expect(find.text('Сравниваю: Загрузки…'), findsOneWidget);
    expect(find.text('Стоп'), findsOneWidget);
    job.complete([_group()]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Найдено 1 группа, 5,0 МБ лишнего'), findsOneWidget);
    // по умолчанию отмечена вся группа, кроме самой старой
    expect(c.dupSelected, {r'C:\Users\X\Downloads\a (1).jpg'});

    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    expect(c.layer, Layer.dupes);
    expect(find.text('Оставить'), findsOneWidget);
    // отметить единственную неотмеченную копию нельзя
    final g = c.dupGroups.single;
    expect(c.toggleDup(g, g.keeper.path, true), isFalse);
    expect(c.dupSelected.length, 1);
    await tester.tap(find.byKey(ValueKey('dup-${g.files[1].path}')));
    await tester.pumpAndSettle();
    expect(c.dupSelected, isEmpty);
    await tester.tap(find.byKey(ValueKey('dup-${g.files[1].path}')));
    await tester.pumpAndSettle();
    expect(c.dupSelected.length, 1);

    await tester.tap(find.byKey(const Key('dupes-recycle')));
    await tester.pumpAndSettle();
    expect(find.text('Переместить 1 файл (5,0 МБ) в Корзину?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(c.platform is FakePlatform && (c.platform as FakePlatform).moved.isEmpty, isTrue);
  });

  testWidgets('Дубликаты: «Стоп» отменяет поиск', (tester) async {
    var cancelled = false;
    final c = make(dup: (_, __) => DupScanJob(Completer<List<DupGroup>>().future, () => cancelled = true));
    await pump(tester, c);
    await tester.tap(find.text('Найти').at(2));
    await tester.pump();
    await tester.tap(find.text('Стоп'));
    await tester.pump();
    expect(cancelled, isTrue);
    expect(c.dupState, LoadState.idle);
  });

  testWidgets('Дубликаты: пусто — «Пусто ✓», без «Выбрать»', (tester) async {
    final c = make(dup: (_, __) => DupScanJob(Future.value(<DupGroup>[]), () {}));
    await pump(tester, c);
    await tester.tap(find.text('Найти').at(2));
    await tester.pumpAndSettle();
    expect(find.text('Пусто ✓'), findsOneWidget);
    expect(find.text('Выбрать'), findsNothing);
  });

  testWidgets('Пустые папки: итог, список, OneDrive не отмечен, удаление через Корзину', (tester) async {
    final p = FakePlatform();
    final c = AppController(
      platform: p,
      env: Env({'USERPROFILE': tmp.path, 'LOCALAPPDATA': '${tmp.path}/la'}),
      dataDir: '${tmp.path}/data',
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
      emptyDirsScan: (_) async => [
        r'C:\Users\X\Documents\a\b',
        r'C:\Users\X\Documents\a',
        r'C:\Users\X\OneDrive\Desktop\z',
      ],
    );
    await pump(tester, c);
    await tester.tap(find.text('Найти').at(3));
    await tester.pumpAndSettle();
    expect(find.text('Найдено 3 пустые папки'), findsOneWidget);
    expect(c.emptySelected, {r'C:\Users\X\Documents\a\b', r'C:\Users\X\Documents\a'});
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    expect(c.layer, Layer.emptyDirs);
    expect(find.text('0 файлов'), findsNWidgets(3));
    // снимаем вложенную — родитель тоже снимается
    c.toggleEmptyDirPath(r'C:\Users\X\Documents\a\b', false);
    expect(c.emptySelected, isEmpty);
    c.setAllEmptyDirs(true);
    await tester.pump();
    await tester.tap(find.byKey(const Key('empty-recycle')));
    await tester.pumpAndSettle();
    expect(find.text('Переместить 3 пустые папки в Корзину?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(p.moved, isEmpty);
  });
}
