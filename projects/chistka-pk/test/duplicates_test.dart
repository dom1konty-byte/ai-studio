import 'dart:io';
import 'dart:typed_data';

import 'package:chistka_pk/core/duplicates.dart';
import 'package:chistka_pk/core/journal.dart';
import 'package:chistka_pk/core/models.dart';
import 'package:chistka_pk/core/empty_dirs.dart';
import 'package:chistka_pk/core/cleaner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

final sep = Platform.pathSeparator;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('chisto_dup'));
  tearDown(() => dir.deleteSync(recursive: true));

  File mk(String name, List<int> bytes, {DateTime? at}) {
    final f = File('${dir.path}$sep$name');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    if (at != null) f.setLastModifiedSync(at);
    return f;
  }

  FileInfo info(File f) => FileInfo(f.path, f.lengthSync(), f.lastModifiedSync());
  List<int> data(int n, int seed) => Uint8List.fromList([for (var i = 0; i < n; i++) (i * 7 + seed) & 255]);

  test('разные размеры — не дубликаты', () {
    final a = mk('a.bin', data(1000, 1));
    final b = mk('b.bin', data(1001, 1));
    expect(groupDuplicatesSync([info(a), info(b)]), isEmpty);
  });

  test('одинаковый размер, разное содержимое — не дубликаты (середина и конец)', () {
    // отличие только в середине большого файла: частичный хеш совпадёт, полный — нет
    final n = partialHashChunk * 4;
    final x = data(n, 3);
    final y = List<int>.of(x)..[n ~/ 2] ^= 0xFF;
    final a = mk('a.bin', x);
    final b = mk('b.bin', y);
    final c = mk('c.bin', data(n, 9));
    expect(groupDuplicatesSync([info(a), info(b), info(c)]), isEmpty);
  });

  test('одинаковые — одна группа, старая копия первая', () {
    final x = data(300000, 5);
    final old = mk('old.bin', x, at: DateTime(2020));
    final newer = mk('sub${sep}new.bin', x, at: DateTime(2024));
    final third = mk('third.bin', x, at: DateTime(2022));
    mk('other.bin', data(300000, 6));
    final g = groupDuplicatesSync([for (final f in dir.listSync(recursive: true).whereType<File>()) info(f)]);
    expect(g.length, 1);
    expect(g.single.files.length, 3);
    expect(g.single.keeper.path, old.path);
    expect(g.single.wasted, 600000);
    expect(g.single.files.map((f) => f.path), [old.path, third.path, newer.path]);
  });

  test('scanDuplicatesSync: маленькие, скрытые и ссылки пропущены', () {
    final x = data(2000, 1);
    mk('a.bin', x);
    mk('b.bin', x);
    mk('tiny1.bin', data(10, 1));
    mk('tiny2.bin', data(10, 1));
    mk('.hidden.bin', x);
    mk('.git${sep}z.bin', x);
    final res = scanDuplicatesSync([dir.path], minSize: 1000);
    expect(res.length, 1);
    expect(res.single.files.length, 2);
    expect(res.single.files.every((f) => !f.path.contains('.hidden') && !f.path.contains('.git')), isTrue);
    // порог по умолчанию — 1 МБ
    expect(scanDuplicatesSync([dir.path]), isEmpty);
    expect(minDuplicateSize, 1024 * 1024);
  });

  test('ссылки не обходятся', () {
    final outside = Directory.systemTemp.createTempSync('chisto_dup_out');
    addTearDown(() => outside.deleteSync(recursive: true));
    final x = data(2000, 2);
    File('${outside.path}${sep}o.bin').writeAsBytesSync(x);
    mk('a.bin', x);
    try {
      Link('${dir.path}${sep}lnk').createSync(outside.path);
    } catch (_) {
      return; // нет прав на ссылки
    }
    expect(scanDuplicatesSync([dir.path], minSize: 1000), isEmpty);
  });

  group('правило «одна копия остаётся»', () {
    DupGroup grp(int n) => DupGroup([
          for (var i = 0; i < n; i++) FileInfo('C:\\d\\f$i.bin', 100, DateTime(2020 + i)),
        ]);

    test('по умолчанию отмечены все, кроме самой старой', () {
      final g = grp(3);
      final sel = defaultDupSelection([g]);
      expect(sel, {'C:\\d\\f1.bin', 'C:\\d\\f2.bin'});
      expect(sel.contains(g.keeper.path), isFalse);
    });

    test('нельзя отметить последнюю неотмеченную копию', () {
      final g = grp(3);
      final sel = defaultDupSelection([g]);
      expect(lockedDupPath(g, sel), g.keeper.path);
      expect(trySelectDup(g, sel, g.keeper.path, true), isFalse);
      expect(sel.length, 2);
      // снимаем одну — теперь можно отметить любую из двух неотмеченных, но не обе
      expect(trySelectDup(g, sel, 'C:\\d\\f1.bin', false), isTrue);
      expect(trySelectDup(g, sel, g.keeper.path, true), isTrue);
      expect(lockedDupPath(g, sel), 'C:\\d\\f1.bin');
      expect(trySelectDup(g, sel, 'C:\\d\\f1.bin', true), isFalse);
      expect(sel.length, 2);
    });

    test('при любой последовательности щелчков хоть одна копия не отмечена', () {
      final g = grp(4);
      final sel = <String>{};
      for (var r = 0; r < 3; r++) {
        for (final f in g.files) {
          trySelectDup(g, sel, f.path, true);
          expect(sel.length < g.files.length, isTrue);
        }
      }
      expect(sel.length, 3);
    });

    test('план удаления: отмечены все — группа пропускается', () {
      final g = grp(2);
      final plan = planDupDelete([g], {for (final f in g.files) f.path}, check: (_) => true);
      expect(plan.files, isEmpty);
      expect(plan.skipped, 2);
    });
  });

  group('перепроверка перед удалением', () {
    test('файл пропал или изменил размер — не удаляется', () {
      final x = data(2000, 1);
      final keep = mk('keep.bin', x, at: DateTime(2020));
      final gone = mk('gone.bin', x, at: DateTime(2021));
      final grew = mk('grew.bin', x, at: DateTime(2022));
      final ok = mk('ok.bin', x, at: DateTime(2023));
      final g = DupGroup([info(keep), info(gone), info(grew), info(ok)]);
      final sel = defaultDupSelection([g]);
      gone.deleteSync();
      grew.writeAsBytesSync([...x, 1]);
      final plan = planDupDelete([g], sel);
      expect(plan.files.map((f) => f.path), [ok.path]);
      expect(plan.skipped, 2);
    });

    test('оставшаяся копия пропала — вся группа не удаляется', () {
      final x = data(2000, 1);
      final keep = mk('keep.bin', x, at: DateTime(2020));
      final b = mk('b.bin', x, at: DateTime(2021));
      final g = DupGroup([info(keep), info(b)]);
      final sel = defaultDupSelection([g]);
      keep.deleteSync();
      final plan = planDupDelete([g], sel);
      expect(plan.files, isEmpty);
      expect(plan.skipped, 1);
      expect(b.existsSync(), isTrue);
    });
  });

  test('удаление дубликатов — только через Корзину (фейк), оставшаяся копия цела', () async {
    final x = data(2000, 1);
    final keep = mk('keep.bin', x, at: DateTime(2020));
    final b = mk('b.bin', x, at: DateTime(2021));
    final g = DupGroup([info(keep), info(b)]);
    final plan = planDupDelete([g], defaultDupSelection([g]));
    final p = FakePlatform();
    final log = CleanLog(File('${dir.path}${sep}log.txt'));
    await Cleaner(p, log, systemDrive: 'C:\\', systemRoot: 'C:\\Windows').run(
      categories: const [],
      filesToRecycle: plan.files,
      userRoots: [dir.path],
      skipBrowsers: false,
    );
    // фейк ничего не удаляет сам: файлы на месте, в Корзину ушёл только b
    expect(p.moved.length, Platform.isWindows ? 1 : 0);
    if (Platform.isWindows) expect(p.moved.single, b.path);
    expect(keep.existsSync(), isTrue);
    expect(b.existsSync(), isTrue);
  });

  test('сам список Корзины не обходит свои пути: EmptyDirCleaner не нужен здесь', () {
    expect(isDirEmptyNow('${dir.path}${sep}nope'), isFalse);
  });
}
