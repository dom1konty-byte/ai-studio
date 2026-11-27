import 'dart:io';

import 'package:chistka_pk/core/disk_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('chisto_map'));
  tearDown(() => root.deleteSync(recursive: true));

  void file(String rel, int n) {
    final f = File('${root.path}${Platform.pathSeparator}$rel');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(List.filled(n, 1));
  }

  test('размеры подпапок считаются вглубь и сортируются по убыванию', () {
    file('small/a.bin', 10);
    file('big/a.bin', 100);
    file('big/deep/b.bin', 200);
    file('mid/a.bin', 50);
    final res = scanSubfoldersSync(root.path);
    expect(res.map((e) => e.name), ['big', 'mid', 'small']);
    expect(res.map((e) => e.bytes), [300, 50, 10]);
    expect(res.any((e) => e.denied), isFalse);
  });

  test('ссылки не обходятся', () {
    file('real/a.bin', 100);
    final outside = Directory.systemTemp.createTempSync('chisto_out');
    addTearDown(() => outside.deleteSync(recursive: true));
    File('${outside.path}${Platform.pathSeparator}x.bin').writeAsBytesSync(List.filled(999, 1));
    Link('${root.path}${Platform.pathSeparator}lnk').createSync(outside.path);
    final res = scanSubfoldersSync(root.path);
    expect(res.map((e) => e.name), ['real']);
    expect(res.single.bytes, 100);
  });

  test('недоступная папка не роняет скан', () {
    file('ok/a.bin', 5);
    final d = Directory('${root.path}${Platform.pathSeparator}locked')..createSync();
    File('${d.path}${Platform.pathSeparator}s.bin').writeAsBytesSync([1, 2, 3]);
    Process.runSync('chmod', ['000', d.path]);
    addTearDown(() => Process.runSync('chmod', ['755', d.path]));
    final res = scanSubfoldersSync(root.path);
    expect(res.length, 2);
    expect(res.firstWhere((e) => e.name == 'ok').bytes, 5);
    final locked = res.firstWhere((e) => e.name == 'locked');
    // под root chmod не действует — тогда папка просто читается
    expect(locked.denied || locked.bytes == 3, isTrue);
  });

  test('несуществующая папка даёт пустой список', () {
    expect(scanSubfoldersSync('${root.path}${Platform.pathSeparator}nope'), isEmpty);
  });

  test('хлебные крошки', () {
    final c = breadcrumbs(r'C:\', r'C:\Users\Me');
    expect(c.map((e) => e.label), [r'C:\', 'Users', 'Me']);
    expect(c.last.path, r'C:\Users\Me');
    expect(breadcrumbs(r'C:\', r'C:\').length, 1);
  });
}
