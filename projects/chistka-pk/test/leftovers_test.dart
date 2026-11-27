import 'dart:io';

import 'package:chistka_pk/core/catalog.dart' show Env;
import 'package:chistka_pk/core/journal.dart';
import 'package:chistka_pk/core/leftovers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

const _env = Env({
  'APPDATA': r'C:\Users\X\AppData\Roaming',
  'LOCALAPPDATA': r'C:\Users\X\AppData\Local',
  'ProgramData': r'C:\ProgramData',
  'ProgramFiles': r'C:\Program Files',
  'ProgramFiles(x86)': r'C:\Program Files (x86)',
  'USERPROFILE': r'C:\Users\X',
  'PUBLIC': r'C:\Users\Public',
});

FsEntry d(String n) => FsEntry(n, isDir: true);
FsEntry f(String n) => FsEntry(n, isDir: false);

const _sm = r'C:\Users\X\AppData\Roaming\Microsoft\Windows\Start Menu\Programs';
const _smAll = r'C:\ProgramData\Microsoft\Windows\Start Menu\Programs';

Map<String, List<FsEntry>> _tree() => {
      r'c:\users\x\appdata\roaming': [d('Foo Editor'), d('Microsoft'), d('Acme'), d('Other')],
      r'c:\users\x\appdata\roaming\microsoft': [d('Foo Editor'), d('Windows')],
      r'c:\users\x\appdata\roaming\acme': [d('Foo Editor'), d('Else')],
      r'c:\users\x\appdata\local': [d('Programs'), d('Temp'), d('Packages')],
      r'c:\users\x\appdata\local\programs': [d('fooeditor'), d('Another')],
      r'c:\users\x\appdata\local\temp': [d('Foo Editor')],
      r'c:\users\x\appdata\local\packages': [d('Foo Editor')],
      r'c:\programdata': [d('Microsoft'), d('Foo Editor Data')],
      r'c:\programdata\microsoft': [d('Foo Editor')],
      r'c:\program files': [d('Common Files'), d('FooEd'), d('Foo Editor Pro'), d('Acme')],
      r'c:\program files\common files': [d('Foo Editor')],
      r'c:\program files\acme': [d('Foo Editor (x64)')],
      r'c:\program files (x86)': [d('Google'), d('NVIDIA Corporation')],
      r'c:\program files (x86)\google': [d('Foo Editor')],
      _sm.toLowerCase(): [f('Foo Editor.lnk'), d('Foo Editor'), f('Notepad.lnk'), d('Accessories')],
      '${_sm.toLowerCase()}\\accessories': [f('Foo Editor Help.lnk')],
      _smAll.toLowerCase(): [f('Foo Editor Launcher.lnk')],
      r'c:\users\x\desktop': [f('Foo Editor.lnk'), f('readme.txt'), d('Foo Editor')],
      r'c:\users\public\desktop': [f('Foo.lnk')],
    };

const _regTree = <String, List<String>>{
  r'HKCU\Software': ['Foo Editor', 'Microsoft', 'Acme', 'Classes', 'Policies'],
  r'HKCU\Software\Acme': ['Foo Editor', 'Else'],
  r'HKCU\Software\Acme\Foo Editor': ['Sub'],
  r'HKLM\SOFTWARE': ['Foo Editor', 'Microsoft', 'Wow6432Node'],
  r'HKLM\SOFTWARE\WOW6432Node': ['Acme'],
  r'HKLM\SOFTWARE\WOW6432Node\Acme': ['Foo Editor'],
};

Future<List<Leftover>> _find({String il = ''}) {
  final tree = _tree();
  return findLeftovers(
    name: 'Foo Editor 2.5.1 (x64)',
    publisher: 'Acme, Inc.',
    installLocation: il,
    env: _env,
    listDir: (dir) async => tree[dir.toLowerCase()] ?? const [],
    regSubKeys: (k) async => _regTree[k] ?? const [],
    sizeOf: (path, isDir) async => 10,
  );
}

void main() {
  group('нормализация имён', () {
    test('версии, x64, регистр, пробелы, дефисы', () {
      expect(normalizeName('7-Zip 23.01 (x64)'), '7zip');
      expect(normalizeName('Python 3.12.1 (64-bit)'), 'python');
      expect(normalizeName('Foo   Bar-Baz'), 'foobarbaz');
      expect(normalizeName('Notepad++'), 'notepad');
      expect(normalizeName('Мой Редактор 2.0'), 'мойредактор');
      expect(normalizeName('Foo Editor 2.5.1 (x64)'), 'fooeditor');
      expect(normalizeName('FOO_EDITOR'), 'fooeditor');
    });
    test('издатель без Inc/LLC/ООО', () {
      expect(normalizePublisher('Acme, Inc.'), 'acme');
      expect(normalizePublisher('Acme LLC'), 'acme');
      expect(normalizePublisher('ООО Ромашка'), 'ромашка');
    });
  });

  group('уверенность совпадений', () {
    final k = NameKey('Foo Editor 2.5.1 (x64)', 'Acme');
    test('точно', () {
      expect(matchName('Foo Editor', k), MatchLevel.exact);
      expect(matchName('fooeditor', k), MatchLevel.exact);
      expect(matchName('Foo-Editor (x64)', k), MatchLevel.exact);
    });
    test('возможно', () {
      expect(matchName('Foo Editor Pro', k), MatchLevel.possible);
      expect(matchName('Foo', k), MatchLevel.none); // короче 4 символов как первое слово
    });
    test('не совпало', () {
      expect(matchName('Other', k), MatchLevel.none);
    });
    test('токены короче 3 символов не ищем', () {
      final s = NameKey('AB', 'Acme');
      expect(matchName('AB', s), MatchLevel.none);
      expect(matchName('ABC', s), MatchLevel.none);
    });
    test('первое слово как возможное совпадение', () {
      final t = NameKey('Telegram Desktop', '');
      expect(matchName('Telegram', t), MatchLevel.possible);
      expect(matchName('Telegram Desktop', t), MatchLevel.exact);
    });
  });

  group('чёрный список', () {
    test('известные имена', () {
      for (final n in [
        'Microsoft', 'microsoft', 'Common Files', 'Google', 'Mozilla', 'NVIDIA',
        'NVIDIA Corporation', 'Intel', 'AMD', 'Packages', 'Programs', 'Temp',
        'WindowsApps', 'Microsoft Shared', 'Package Cache', 'Installer', 'Classes',
        'Policies', 'Wow6432Node', 'ChistoDisk', 'Windows Defender', 'Microsoft Office',
      ]) {
        expect(isBlacklistedName(n), isTrue, reason: n);
      }
      expect(isBlacklistedName('Foo Editor'), isFalse);
    });
    test('даже точное совпадение имени не пробивает чёрный список', () {
      expect(matchName('Microsoft', NameKey('Microsoft', 'Microsoft')), MatchLevel.none);
      expect(matchName('Common Files', NameKey('Common Files', '')), MatchLevel.none);
    });
  });

  group('поиск остатков', () {
    test('находит нужное, не заходит в Microsoft/Common Files/Google/Temp/Packages', () async {
      final res = await _find(il: r'C:\Program Files\FooEd');
      final paths = res.map((e) => e.path).toList();
      for (final p in paths) {
        final low = p.toLowerCase();
        expect(low.contains('microsoft') && !low.contains(r'start menu'), isFalse, reason: p);
        expect(low.contains('common files'), isFalse, reason: p);
        expect(low.contains(r'\google'), isFalse, reason: p);
        expect(low.contains(r'\temp'), isFalse, reason: p);
        expect(low.contains(r'\packages'), isFalse, reason: p);
      }
      // точные
      final exact = res.where((e) => e.exact).map((e) => e.path).toSet();
      expect(exact, contains(r'C:\Users\X\AppData\Roaming\Foo Editor'));
      expect(exact, contains(r'C:\Users\X\AppData\Roaming\Acme\Foo Editor'));
      expect(exact, contains(r'C:\Users\X\AppData\Local\Programs\fooeditor'));
      expect(exact, contains(r'C:\Program Files\Acme\Foo Editor (x64)'));
      expect(exact, contains(r'C:\Program Files\FooEd')); // InstallLocation
      expect(exact, contains('$_sm\\Foo Editor.lnk'));
      expect(exact, contains('$_sm\\Foo Editor'));
      expect(exact, contains(r'C:\Users\X\Desktop\Foo Editor.lnk'));
      expect(exact, contains(r'HKCU\Software\Foo Editor'));
      expect(exact, contains(r'HKCU\Software\Acme\Foo Editor'));
      // возможные
      final maybe = res.where((e) => !e.exact).map((e) => e.path).toSet();
      expect(maybe, contains(r'C:\Program Files\Foo Editor Pro'));
      expect(maybe, contains(r'C:\Program Files\Acme')); // папка издателя
      expect(maybe, contains(r'C:\ProgramData\Foo Editor Data'));
      expect(maybe, contains('$_smAll\\Foo Editor Launcher.lnk'));
      // ярлык внутри уже найденной папки Пуска отдельно не ищется
      expect(paths.any((p) => p.endsWith('Foo Editor Help.lnk')), isFalse);
      // обычные файлы и чужое
      expect(paths.any((p) => p.endsWith('readme.txt')), isFalse);
      expect(paths.any((p) => p.endsWith('Notepad.lnk')), isFalse);
    });

    test('реестр HKLM — только показ', () async {
      final res = await _find();
      final hklm = res.where((e) => e.path.startsWith('HKLM')).toList();
      expect(hklm, isNotEmpty);
      expect(hklm.every((e) => !e.deletable), isTrue);
      expect(res.where((e) => e.path.startsWith('HKCU')).every((e) => e.deletable), isTrue);
      expect(res.any((e) => e.path == r'HKCU\Software\Microsoft'), isFalse);
      expect(res.any((e) => e.path == r'HKCU\Software\Classes'), isFalse);
    });

    test('корни и их родители не предлагаются; InstallLocation вне корней игнорируется', () async {
      for (final il in [r'C:\Program Files', r'C:\Program Files\Common Files', r'C:\Windows', r'D:\Games\Foo', 'C:\\']) {
        final res = await _find(il: il);
        final paths = res.map((e) => e.path.toLowerCase()).toSet();
        expect(paths.contains(il.toLowerCase()), isFalse, reason: il);
      }
    });

    test('короткое имя и издатель — ничего не ищем', () async {
      final tree = _tree();
      final res = await findLeftovers(
        name: 'AB',
        publisher: 'X',
        installLocation: '',
        env: _env,
        listDir: (dir) async => tree[dir.toLowerCase()] ?? const [],
        regSubKeys: (k) async => _regTree[k] ?? const [],
        sizeOf: (p, isDir) async => 1,
      );
      expect(res, isEmpty);
    });

    test('isOfferablePath: корень, родитель, чёрный список', () {
      final roots = LeftoverRoots(_env);
      expect(isOfferablePath(r'C:\Program Files', roots), isFalse);
      expect(isOfferablePath(r'C:\Users\X\AppData', roots), isFalse);
      expect(isOfferablePath(r'C:\Users\X\AppData\Roaming', roots), isFalse);
      expect(isOfferablePath(r'C:\Users\X\AppData\Roaming\Microsoft', roots), isFalse);
      expect(isOfferablePath(r'C:\Users\X\Desktop', roots), isFalse);
      expect(isOfferablePath(r'C:\Windows\Foo', roots), isFalse);
      expect(isOfferablePath(r'C:\Program Files\Foo', roots), isTrue);
    });
  });

  group('проверки реестра', () {
    test('удалять можно только HKCU\\Software\\… глубиной от 3', () {
      expect(isSafeRegDeleteKey(r'HKCU\Software\Foo'), isTrue);
      expect(isSafeRegDeleteKey(r'HKCU\Software\Acme\Foo'), isTrue);
      expect(isSafeRegDeleteKey(r'HKCU\Software'), isFalse);
      expect(isSafeRegDeleteKey('HKCU'), isFalse);
      expect(isSafeRegDeleteKey(r'HKLM\SOFTWARE\Foo'), isFalse);
      expect(isSafeRegDeleteKey(r'HKCU\Software\Microsoft'), isFalse);
      expect(isSafeRegDeleteKey(r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Foo'), isFalse);
      expect(isSafeRegDeleteKey(r'HKCU\Software\Foo\..\Microsoft'), isFalse);
      expect(isSafeRegDeleteKey(r'HKCU\Control Panel\Foo'), isFalse);
    });
    test('запись Uninstall — строго на один уровень', () {
      const base = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall';
      expect(isSafeRegDeleteKey('$base\\Foo', uninstallEntry: true), isTrue);
      expect(isSafeRegDeleteKey(base, uninstallEntry: true), isFalse);
      expect(isSafeRegDeleteKey('$base\\Foo\\Bar', uninstallEntry: true), isFalse);
      expect(isSafeRegDeleteKey(r'HKCU\Software\Foo', uninstallEntry: true), isFalse);
    });
  });

  group('удаление остатков', () {
    late Directory tmp;
    late FakePlatform platform;
    late CleanLog log;
    late LeftoverCleaner cleaner;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('chisto_left');
      platform = FakePlatform();
      log = CleanLog(File('${tmp.path}${Platform.pathSeparator}log.txt'));
      cleaner = LeftoverCleaner(
        platform: platform,
        log: log,
        env: _env,
        backupDir: '${tmp.path}${Platform.pathSeparator}backup',
        guard: (path, root, isDir) => null,
        now: () => DateTime(2026, 11, 27, 9, 5, 3),
      );
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    Leftover folder(String p) => Leftover(kind: LeftoverKind.folder, path: p, isDir: true, exact: true);
    Leftover reg(String k, {bool deletable = true, bool uninstall = false}) => Leftover(
        kind: LeftoverKind.registry, path: k, exact: true, deletable: deletable, isUninstallEntry: uninstall);

    test('папки идут только в Корзину', () async {
      final out = await cleaner.run([folder(r'C:\Users\X\AppData\Roaming\Foo Editor')]);
      expect(out.single.ok, isTrue);
      expect(platform.moved, [r'C:\Users\X\AppData\Roaming\Foo Editor']);
      expect(platform.deleted, isEmpty);
      expect(platform.exported, isEmpty);
    });

    test('чёрный список, корни и чужие пути не доходят до Корзины', () async {
      final out = await cleaner.run([
        folder(r'C:\Users\X\AppData\Roaming\Microsoft'),
        folder(r'C:\Program Files\Common Files'),
        folder(r'C:\Program Files'),
        folder(r'C:\Users\X\AppData\Roaming'),
        folder(r'C:\Windows\Foo'),
        folder(r'D:\Foo'),
        folder(r'C:\Users\X'),
      ]);
      expect(out.every((o) => !o.ok), isTrue);
      expect(platform.moved, isEmpty);
      expect(platform.moveCalls, 0);
    });

    test('проверка ссылок (guard) блокирует удаление', () async {
      final c2 = LeftoverCleaner(
        platform: platform,
        log: log,
        env: _env,
        backupDir: tmp.path,
        guard: (path, root, isDir) => 'это ссылка',
      );
      final out = await c2.run([folder(r'C:\Program Files\Foo')]);
      expect(out.single.ok, isFalse);
      expect(platform.moved, isEmpty);
    });

    test('вложенный путь не отправляется отдельно', () async {
      final out = await cleaner.run([
        folder(r'C:\Program Files\Acme'),
        folder(r'C:\Program Files\Acme\Foo'),
      ]);
      expect(platform.moved, [r'C:\Program Files\Acme']);
      expect(out.where((o) => o.ok), hasLength(2));
    });

    test('Program Files без прав: «нужны права администратора»', () async {
      platform.skipReasons[r'C:\Program Files\Foo'] = 'Windows не удалила файл';
      final out = await cleaner.run([folder(r'C:\Program Files\Foo')]);
      expect(out.single.ok, isFalse);
      expect(out.single.message, contains('нужны права администратора'));
    });

    test('реестр: сначала экспорт, потом удаление', () async {
      final out = await cleaner.run([reg(r'HKCU\Software\Foo Editor')]);
      expect(out.single.ok, isTrue);
      expect(platform.callOrder, [r'export HKCU\Software\Foo Editor', r'delete HKCU\Software\Foo Editor']);
    });

    test('экспорт не удался — удаление реестра не вызывается', () async {
      platform.exportOk = false;
      final out = await cleaner.run([reg(r'HKCU\Software\Foo Editor')]);
      expect(out.single.ok, isFalse);
      expect(out.single.message, contains('резервная копия не создана'));
      expect(platform.callOrder, [r'export HKCU\Software\Foo Editor']);
      expect(platform.deleted, isEmpty);
    });

    test('HKLM и опасные ключи не трогаются', () async {
      final out = await cleaner.run([
        reg(r'HKLM\SOFTWARE\Foo', deletable: false),
        reg(r'HKCU\Software\Microsoft'),
        reg(r'HKCU\Software'),
        reg(r'HKCU\Software\Foo\..\Classes'),
      ]);
      expect(out.every((o) => !o.ok), isTrue);
      expect(platform.callOrder, isEmpty);
    });

    test('запись Uninstall HKCU удаляется с копией, HKLM — нет', () async {
      const base = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall';
      final out = await cleaner.run([
        reg('$base\\Foo', uninstall: true),
        reg(r'HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\Bar', deletable: false, uninstall: true),
      ]);
      expect(out.where((o) => o.ok), hasLength(1));
      expect(platform.callOrder, ['export $base\\Foo', 'delete $base\\Foo']);
    });

    test('ошибка удаления после экспорта — не успех', () async {
      platform.deleteOk = false;
      final out = await cleaner.run([reg(r'HKCU\Software\Foo Editor')]);
      expect(out.single.ok, isFalse);
    });

    test('имя резервной копии: дата и безопасное имя', () {
      expect(cleaner.backupFileName(r'HKCU\Software\Acme\Foo Editor'), '20261127-090503_Acme_Foo_Editor.reg');
    });

    test('всё попадает в журнал', () async {
      await cleaner.run([folder(r'C:\Program Files\Foo'), reg(r'HKCU\Software\Foo Editor')]);
      final text = log.file.readAsStringSync();
      expect(text, contains(r'C:\Program Files\Foo'));
      expect(text, contains(r'HKCU\Software\Foo Editor'));
    });
  });
}
