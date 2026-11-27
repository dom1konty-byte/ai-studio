import 'dart:io';

import 'package:chistka_pk/core/empty_dirs.dart';
import 'package:chistka_pk/core/journal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

final sep = Platform.pathSeparator;

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('chisto_empty'));
  tearDown(() => root.deleteSync(recursive: true));

  String d(String rel) {
    final x = Directory('${root.path}$sep${rel.replaceAll('/', sep)}')..createSync(recursive: true);
    return x.path;
  }

  String rel(String path) => path.substring(root.path.length + 1).replaceAll(sep, '/');

  test('вложенные пустые найдены, самые глубокие первыми; сам корень — никогда', () {
    d('a/b/c');
    d('x');
    final res = findEmptyDirsSync([root.path]);
    expect(res.map(rel).toSet(), {'a', 'a/b', 'a/b/c', 'x'});
    expect(res.first, endsWith('c'));
    expect(res.contains(root.path), isFalse);
  });

  test('пустой корень не попадает в результат', () {
    expect(findEmptyDirsSync([root.path]), isEmpty);
  });

  test('файл во вложенной папке — вся цепочка не пуста', () {
    d('a/b/c');
    File('${root.path}${sep}a${sep}b${sep}c${sep}f.txt').writeAsStringSync('x');
    d('a/empty');
    final res = findEmptyDirsSync([root.path]);
    expect(res.map(rel), ['a/empty']);
  });

  test('ссылка не обходится и не считается пустой; папка со ссылкой не пуста', () {
    final target = Directory.systemTemp.createTempSync('chisto_empty_t');
    addTearDown(() => target.deleteSync(recursive: true));
    Directory('${target.path}${sep}inner').createSync();
    d('holder');
    try {
      Link('${root.path}${sep}holder${sep}lnk').createSync(target.path);
    } catch (_) {
      return;
    }
    final res = findEmptyDirsSync([root.path]);
    expect(res, isEmpty); // holder содержит ссылку, inner за ссылкой не виден
    expect(Directory('${target.path}${sep}inner').existsSync(), isTrue);
  });

  test('скрытые папки (и по имени с точкой) не трогаем, родитель не пуст', () {
    d('p/.hid');
    d('q/vis');
    final res = findEmptyDirsSync([root.path]);
    expect(res.map(rel), ['q/vis', 'q']);
  });

  test('корень внутри другого корня и его предки не попадают', () {
    final inner = d('outer/inner');
    d('outer/other');
    final res = findEmptyDirsSync([root.path, inner]);
    expect(res.map(rel).toSet(), {'outer/other'});
  });

  test('isDirEmptyNow: перепроверка видит новый файл', () {
    final a = d('a/b');
    expect(isDirEmptyNow(a), isTrue);
    File('$a${sep}f.txt').writeAsStringSync('x');
    expect(isDirEmptyNow(a), isFalse);
    expect(isDirEmptyNow('$a${sep}x'), isFalse);
  });

  test('выбор: родитель отмечает вложенные, снятие вложенной снимает родителей', () {
    const all = [r'C:\U\a\b\c', r'C:\U\a\b', r'C:\U\a', r'C:\U\x'];
    final sel = <String>{};
    toggleEmptyDir(all, sel, r'C:\U\a\b', true);
    expect(sel, {r'C:\U\a\b', r'C:\U\a\b\c'});
    toggleEmptyDir(all, sel, r'C:\U\a\b\c', false);
    expect(sel, isEmpty);
  });

  test('OneDrive определяется по переменной и по имени', () {
    expect(isInOneDrive(r'C:\Users\X\OneDrive\Desktop\a', r'C:\Users\X\OneDrive'), isTrue);
    expect(isInOneDrive(r'C:\Users\X\OneDrive - Work\a', null), isTrue);
    expect(isInOneDrive(r'C:\Users\X\Documents\a', r'C:\Users\X\OneDrive'), isFalse);
  });

  group('удаление', () {
    const roots = [r'C:\Users\X\Documents', r'C:\Users\X\Desktop'];

    EmptyDirCleaner make(FakePlatform p, {bool Function(String)? empty, String? Function(String)? guard}) {
      return EmptyDirCleaner(
        platform: p,
        log: CleanLog(File('${root.path}${sep}log.txt')),
        userRoots: roots,
        guard: (path, r, isDir) => guard?.call(path) ?? (isDir ? null : 'не папка'),
        isEmpty: empty ?? (_) => true,
      );
    }

    test('только в Корзину, самые глубокие первыми, по одной', () async {
      final p = FakePlatform();
      final res = await make(p).run([
        r'C:\Users\X\Documents\a',
        r'C:\Users\X\Documents\a\b\c',
        r'C:\Users\X\Documents\a\b',
      ]);
      expect(p.moved, [
        r'C:\Users\X\Documents\a\b\c',
        r'C:\Users\X\Documents\a\b',
        r'C:\Users\X\Documents\a',
      ]);
      expect(p.moveCalls, 3);
      expect(res.recycled, 3);
    });

    test('корень, чужие и небезопасные пути — пропуск', () async {
      final p = FakePlatform();
      final res = await make(p).run([
        r'C:\Users\X\Documents',
        r'c:\users\x\documents\',
        r'C:\Users\X\Documents\..\Secret\z',
        r'C:\Windows\Temp\z',
        r'D:\Other\z',
        r'\\srv\share\z',
        r'C:\Users\X',
      ]);
      expect(p.moved, isEmpty);
      expect(res.skipped, 7);
    });

    test('перепроверка: непустая папка и отказ защиты ссылок не удаляются', () async {
      final p = FakePlatform();
      final res = await make(
        p,
        empty: (path) => !path.endsWith('full'),
        guard: (path) => path.endsWith('lnk') ? 'это ссылка' : null,
      ).run([
        r'C:\Users\X\Documents\full',
        r'C:\Users\X\Documents\lnk',
        r'C:\Users\X\Documents\ok',
      ]);
      expect(p.moved, [r'C:\Users\X\Documents\ok']);
      expect(res.recycled, 1);
      expect(res.skipped, 2);
    });

    test('Корзина отказала — не считается удалённой', () async {
      final p = FakePlatform()..skipReasons[r'C:\Users\X\Documents\a'] = 'нет Корзины';
      final res = await make(p).run([r'C:\Users\X\Documents\a']);
      expect(res.recycled, 0);
      expect(res.skipped, 1);
    });
  });
}
