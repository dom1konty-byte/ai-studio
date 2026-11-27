import 'dart:io';

import 'package:chistka_pk/core/cleaner.dart';
import 'package:chistka_pk/core/journal.dart';
import 'package:chistka_pk/core/models.dart';
import 'package:chistka_pk/core/scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

final String sep = Platform.pathSeparator;

/// Пробуем создать ссылку: без прав (Windows без админа/режима разработчика) кейс пропускаем.
String? _linkSkipReason() {
  final d = Directory.systemTemp.createTempSync('chisto_probe');
  try {
    Link('${d.path}${sep}l').createSync('${d.path}${sep}t', recursive: false);
    return null;
  } catch (e) {
    return 'нет прав на создание ссылок: $e';
  } finally {
    d.deleteSync(recursive: true);
  }
}

class Env {
  Env() {
    base = Directory.systemTemp.createTempSync('chisto_clean');
    cache = Directory('${base.path}${sep}cache')..createSync();
    outside = Directory('${base.path}${sep}outside')..createSync();
    logFile = File('${base.path}${sep}logs${sep}log.txt');
    log = CleanLog(logFile);
    platform = FakePlatform();
    cleaner = Cleaner(platform, log);
  }
  late Directory base, cache, outside;
  late File logFile;
  late CleanLog log;
  late FakePlatform platform;
  late Cleaner cleaner;

  File file(Directory d, String name, int size) =>
      File('${d.path}$sep$name')..writeAsBytesSync(List.filled(size, 7));

  Category get cat => Category(
        id: CategoryId.temp,
        title: 'Временные',
        hint: '',
        targets: [CleanTarget(cache.path)],
      );

  void dispose() => base.deleteSync(recursive: true);
}

void main() {
  final notWin = Platform.isWindows ? null : 'белый список работает с путями Windows';
  final linkSkip = notWin ?? _linkSkipReason();

  Env setup() {
    final e = Env();
    addTearDown(e.dispose);
    return e;
  }

  test('удаляет содержимое корня кэша, корень остаётся', () async {
    final e = setup();
    e.file(e.cache, 'a.tmp', 100);
    final sub = Directory('${e.cache.path}${sep}sub${sep}deep')..createSync(recursive: true);
    e.file(sub, 'b.tmp', 200);
    final s = CleanSummary();
    await e.cleaner.cleanTarget(e.cat, e.cat.targets.first, s);
    expect(e.cache.existsSync(), isTrue);
    expect(e.cache.listSync(), isEmpty);
    expect(s.deletedFiles, 2);
    expect(s.freedBytes, 300);
    expect(s.skippedFiles, 0);
  }, skip: notWin);

  test('файлы вне корня (соседняя папка) не тронуты', () async {
    final e = setup();
    e.file(e.cache, 'a.tmp', 10);
    final other = e.file(e.outside, 'keep.txt', 10);
    final sibling = Directory('${e.base.path}${sep}cache2')..createSync();
    final keep2 = e.file(sibling, 'keep2.txt', 10);
    await e.cleaner.cleanTarget(e.cat, e.cat.targets.first, CleanSummary());
    expect(other.existsSync(), isTrue);
    expect(keep2.existsSync(), isTrue);
  }, skip: notWin);

  test('пустой кэш и несуществующая папка: без ошибок', () async {
    final e = setup();
    final s = CleanSummary();
    await e.cleaner.cleanTarget(e.cat, e.cat.targets.first, s);
    await e.cleaner.cleanTarget(
        e.cat, CleanTarget('${e.base.path}${sep}nope'), s);
    expect(s.deletedFiles, 0);
    expect(s.skippedFiles, 0);
    expect(e.cache.existsSync(), isTrue);
  }, skip: notWin);

  test('путь цели с .. нормализуется, соседи целы', () async {
    final e = setup();
    final sub = Directory('${e.cache.path}${sep}sub')..createSync();
    e.file(e.cache, 'a.tmp', 10);
    final keep = e.file(e.outside, 'keep.txt', 10);
    final t = CleanTarget('${sub.path}$sep..');
    final s = CleanSummary();
    await e.cleaner.cleanTarget(e.cat, t, s);
    expect(keep.existsSync(), isTrue);
    expect(File('${e.cache.path}${sep}a.tmp').existsSync(), isFalse);
  }, skip: notWin);

  test('файл в Корзину: путь с .. из пользовательской папки не проходит', () async {
    final e = setup();
    final inside = e.file(e.cache, 'ok.bin', 5);
    final victim = e.file(e.outside, 'victim.bin', 5);
    final sneaky = '${e.cache.path}$sep..${sep}outside${sep}victim.bin';
    final s = await e.cleaner.run(
      categories: [],
      filesToRecycle: [
        FileInfo(inside.path, 5, DateTime.now()),
        FileInfo(sneaky, 5, DateTime.now()),
      ],
      userRoots: [e.cache.path],
      skipBrowsers: false,
    );
    expect(e.platform.moved, [inside.path]);
    expect(victim.existsSync(), isTrue);
    expect(s.skippedFiles, 1);
    expect(s.deletedFiles, 1);
  }, skip: notWin);

  test('ссылка внутри корня на внешнюю папку: внешние файлы не удалены', () async {
    final e = setup();
    final secret = e.file(e.outside, 'secret.bin', 50);
    e.file(e.cache, 'a.tmp', 10);
    Link('${e.cache.path}${sep}lnk').createSync('..${sep}outside');
    final s = CleanSummary();
    await e.cleaner.cleanTarget(e.cat, e.cat.targets.first, s);
    expect(secret.existsSync(), isTrue);
    expect(e.outside.existsSync(), isTrue);
    expect(s.deletedFiles, 1);
    // сканер ссылку тоже не обходит
    final r = await scanTarget(CleanTarget(e.cache.path));
    expect(r.files, lessThanOrEqualTo(1));
  }, skip: linkSkip);

  test('ссылка на внешнюю папку с абсолютным путём: внешнее цело, сканер не считает', () async {
    final e = setup();
    final secret = e.file(e.outside, 'secret.bin', 5000);
    Link('${e.cache.path}${sep}lnk').createSync(e.outside.path);
    final r = await scanTarget(CleanTarget(e.cache.path));
    expect(r.bytes, 0);
    expect(r.files, 0);
    await e.cleaner.cleanTarget(e.cat, e.cat.targets.first, CleanSummary());
    expect(secret.existsSync(), isTrue);
  }, skip: linkSkip);

  test('занятый файл пропускается и считается пропущенным', () async {
    final e = setup();
    final locked = e.file(e.cache, 'busy.tmp', 100);
    final free = e.file(e.cache, 'free.tmp', 20);
    final raf = locked.openSync(mode: FileMode.append);
    try {
      raf.lockSync(FileLock.exclusive);
      final s = CleanSummary();
      await e.cleaner.cleanTarget(e.cat, e.cat.targets.first, s);
      expect(free.existsSync(), isFalse);
      expect(locked.existsSync(), isTrue);
      expect(s.skippedFiles, 1);
      expect(s.deletedFiles, 1);
      expect(s.freedBytes, 20);
    } finally {
      raf.closeSync();
    }
  }, skip: notWin);

  test('Загрузки и Большие файлы идут через moveToRecycleBin, а не delete', () async {
    final e = setup();
    final a = e.file(e.cache, 'old.zip', 500);
    final b = e.file(e.cache, 'big.iso', 900);
    final s = await e.cleaner.run(
      categories: [],
      filesToRecycle: [
        FileInfo(a.path, 500, DateTime(2020)),
        FileInfo(b.path, 900, DateTime(2020)),
      ],
      userRoots: [e.cache.path],
      skipBrowsers: false,
    );
    expect(e.platform.moved, [a.path, b.path]);
    // фейк ничего не удаляет: если файлы пропали, их удалили напрямую
    expect(a.existsSync(), isTrue);
    expect(b.existsSync(), isTrue);
    expect(s.recycledBytes, 1400);
    expect(s.freedBytes, 0);
    expect(s.deletedFiles, 2);
  }, skip: notWin);

  test('журнал пишет строки, статистика суммируется', () async {
    final e = setup();
    e.file(e.cache, 'a.tmp', 100);
    e.file(e.cache, 'b.tmp', 250);
    final dl = e.file(e.outside, 'dl.zip', 40);
    final s = await e.cleaner.run(
      categories: [e.cat],
      filesToRecycle: [FileInfo(dl.path, 40, DateTime(2020))],
      userRoots: [e.outside.path],
      skipBrowsers: false,
    );
    expect(s.freedBytes, 350);
    expect(s.recycledBytes, 40);
    expect(s.deletedFiles, 3);
    expect(s.skippedFiles, 0);
    expect(s.logFailed, isFalse);
    expect(s.freeBefore, isNotNull);
    final lines = e.logFile.readAsLinesSync();
    expect(lines.length, 3);
    expect(lines.where((l) => l.contains('\tудалено')).length, 2);
    expect(lines.where((l) => l.contains('\tв Корзину')).length, 1);
    expect(lines.any((l) => l.contains('a.tmp\t100\t')), isTrue);
  }, skip: notWin);

  test('Корзина: пустая очищается раньше отправки файлов', () async {
    final e = setup();
    final s = await e.cleaner.run(
      categories: [
        const Category(id: CategoryId.recycle, title: 'Корзина', hint: '', targets: []),
      ],
      filesToRecycle: [],
      userRoots: [],
      skipBrowsers: false,
    );
    expect(e.platform.binEmptied, isTrue);
    expect(s.freedBytes, 1000);
    expect(s.deletedFiles, 2);
  }, skip: notWin);
}
