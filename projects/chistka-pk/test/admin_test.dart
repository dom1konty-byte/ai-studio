import 'dart:io';
import 'dart:typed_data';

import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/cleaner.dart';
import 'package:chistka_pk/core/journal.dart';
import 'package:chistka_pk/core/leftovers.dart';
import 'package:chistka_pk/core/models.dart';
import 'package:chistka_pk/core/png.dart';
import 'package:chistka_pk/core/programs.dart';
import 'package:chistka_pk/core/target_guard.dart';
import 'package:chistka_pk/core/whitelist.dart';
import 'package:chistka_pk/platform/platform_api.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:chistka_pk/state/startup_service.dart';
import 'package:chistka_pk/core/startup.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

const _sys = r'C:\Windows';
const _wu = r'C:\Windows\SoftwareDistribution\Download';
const _pf = r'C:\Windows\Prefetch';

CleanTarget _t(String dir, {String? base = _sys}) => CleanTarget(dir, base: base, minSegments: 3);

void main() {
  group('админ-цели очистки: ровно два пути', () {
    test('пути строятся от SystemRoot', () {
      expect(adminCleanPath(CategoryId.winUpdate, _sys), _wu);
      expect(adminCleanPath(CategoryId.prefetch, _sys), _pf);
      expect(adminCleanPath(CategoryId.temp, _sys), isNull);
      expect(adminCleanSubpaths.length, 2);
    });
    test('точный путь с base = SystemRoot принимается (регистр и слэши не важны)', () {
      expect(isAdminCleanTarget(CategoryId.winUpdate, _t(_wu), _sys), isTrue);
      expect(isAdminCleanTarget(CategoryId.prefetch, _t(_pf), _sys), isTrue);
      expect(isAdminCleanTarget(CategoryId.prefetch, _t('c:/windows/PREFETCH'), 'C:\\Windows\\'), isTrue);
    });
    test('любой другой путь отклоняется', () {
      for (final dir in [
        r'C:\Windows',
        r'C:\Windows\System32',
        r'C:\Windows\Temp',
        r'C:\Windows\SoftwareDistribution',
        r'C:\Windows\SoftwareDistribution\Download\sub',
        r'C:\Windows\Prefetch\ReadyBoot',
        r'C:\Windows\Prefetch\..\System32',
        r'D:\Windows\Prefetch',
        r'C:\Prefetch',
        r'\\srv\share\Prefetch',
      ]) {
        expect(isAdminCleanTarget(CategoryId.prefetch, _t(dir), _sys), isFalse, reason: dir);
        expect(isAdminCleanTarget(CategoryId.winUpdate, _t(dir), _sys), isFalse, reason: dir);
      }
    });
    test('чужая категория или чужая база — отказ', () {
      expect(isAdminCleanTarget(CategoryId.temp, _t(_pf), _sys), isFalse);
      expect(isAdminCleanTarget(CategoryId.prefetch, _t(_pf, base: r'C:\'), _sys), isFalse);
      expect(isAdminCleanTarget(CategoryId.prefetch, _t(_pf, base: null), _sys), isFalse);
      expect(isAdminCleanTarget(CategoryId.prefetch, _t(_pf), r'C:\Other'), isFalse);
    });
    test('обе цели проходят общую защиту путей (SystemRoot защищён от очистки целиком)', () {
      final prot = protectedPathsOf(const Env({'SystemRoot': _sys}));
      expect(isSafeCleanTarget(_wu, protectedPaths: prot, minSegments: 4), isTrue);
      expect(isSafeCleanTarget(_pf, protectedPaths: prot, minSegments: 3), isTrue);
      expect(isSafeCleanTarget(_sys, protectedPaths: prot, minSegments: 2), isFalse);
    });
    test('без режима администратора в каталоге этих строк нет', () {
      final cats = buildCatalog(const Env({'SystemRoot': _sys}));
      expect(cats.any((c) => c.adminOnly), isFalse);
      expect(cats.any((c) => c.id == CategoryId.winUpdate || c.id == CategoryId.prefetch), isFalse);
    });
  });

  group('Cleaner: админ-категории', () {
    late Directory tmp;
    late FakePlatform platform;
    late CleanLog log;
    late File logFile;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('chisto_admin');
      platform = FakePlatform();
      logFile = File('${tmp.path}${Platform.pathSeparator}log.txt');
      log = CleanLog(logFile);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    Category wu({String dir = _wu}) => Category(
        id: CategoryId.winUpdate, title: 'Кэш обновлений Windows', hint: '', adminOnly: true, targets: [_t(dir)]);

    Future<void> run(Cleaner c, Category cat) =>
        c.run(categories: [cat], filesToRecycle: const [], userRoots: const [], skipBrowsers: false);

    test('служба останавливается до очистки и запускается после', () async {
      await run(Cleaner(platform, log, admin: true), wu());
      expect(platform.tools, [
        r'C:\Windows\System32\net.exe stop wuauserv',
        r'C:\Windows\System32\net.exe start wuauserv',
      ]);
    });

    test('служба не запущена: ни stop, ни start', () async {
      platform.toolOutput = 'SERVICE_NAME: wuauserv\n        STATE              : 1  STOPPED\n';
      await run(Cleaner(platform, log, admin: true), wu());
      expect(platform.tools, isEmpty);
      expect(platform.queries.single, endsWith('sc.exe query wuauserv'));
    });

    test('parseServiceRunning', () {
      expect(parseServiceRunning('        STATE              : 4  RUNNING\n'), isTrue);
      expect(parseServiceRunning('        СОСТОЯНИЕ          : 4  RUNNING\n'), isTrue);
      expect(parseServiceRunning('        STATE              : 1  STOPPED\n'), isFalse);
      expect(parseServiceRunning('        STATE              : 3  STOP_PENDING\n'), isFalse);
      expect(parseServiceRunning('ошибка'), isNull);
      expect(parseServiceRunning(null), isNull);
    });

    test('служба запускается обратно, даже если остановка упала', () async {
      platform.onTool = (c) {
        if (c.contains('stop')) throw StateError('boom');
      };
      await run(Cleaner(platform, log, admin: true), wu());
      expect(platform.tools.last, endsWith('start wuauserv'));
    });

    test('без прав администратора категория пропущена: службы не трогаем', () async {
      await run(Cleaner(platform, log), wu());
      expect(platform.tools, isEmpty);
      await log.flush();
      expect(logFile.readAsStringSync(), contains('нужны права администратора'));
    });

    test('цель не из белого списка админ-категории отклоняется и пишется в журнал', () async {
      final c = Cleaner(platform, log, admin: true);
      final cat = Category(
          id: CategoryId.prefetch, title: 'Prefetch', hint: '', adminOnly: true, targets: [_t(r'C:\Windows\System32')]);
      await c.cleanTarget(cat, cat.targets.first, CleanSummary());
      await log.flush();
      expect(logFile.readAsStringSync(), contains('не входит в список системных папок'));
    });
  });

  group('реестр: HKLM только в режиме администратора', () {
    test('без админа HKLM не удаляется никогда', () {
      expect(isSafeRegDeleteKey(r'HKLM\SOFTWARE\Foo'), isFalse);
      expect(isSafeRegDeleteKey(r'HKLM\SOFTWARE\Acme\Foo'), isFalse);
      expect(isSafeRegDeleteKey(r'HKLM\SOFTWARE\WOW6432Node\Foo'), isFalse);
    });
    test('с админом: HKLM\\SOFTWARE\\<не из чёрного списка>', () {
      expect(isSafeRegDeleteKey(r'HKLM\SOFTWARE\Foo', admin: true), isTrue);
      expect(isSafeRegDeleteKey(r'HKLM\SOFTWARE\Acme\Foo', admin: true), isTrue);
      expect(isSafeRegDeleteKey(r'HKLM\Software\WOW6432Node\Acme', admin: true), isTrue);
      expect(isSafeRegDeleteKey(r'HKCU\Software\Foo', admin: true), isTrue);
    });
    test('с админом: чёрный список и служебные ветки — никогда', () {
      for (final k in [
        r'HKLM\SOFTWARE',
        r'HKLM',
        r'HKLM\SOFTWARE\Microsoft',
        r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion',
        r'HKLM\SOFTWARE\Classes',
        r'HKLM\SOFTWARE\Classes\Foo',
        r'HKLM\SOFTWARE\Policies',
        r'HKLM\SOFTWARE\Policies\Foo',
        r'HKLM\SOFTWARE\WOW6432Node',
        r'HKLM\SOFTWARE\WOW6432Node\Microsoft',
        r'HKLM\SOFTWARE\WOW6432Node\Microsoft\Foo',
        r'HKLM\SOFTWARE\WOW6432Node\Classes',
        r'HKLM\SOFTWARE\Clients',
        r'HKLM\SOFTWARE\RegisteredApplications',
        r'HKLM\SOFTWARE\Acme\Microsoft',
        r'HKLM\SOFTWARE\Foo\..\Microsoft',
        r'HKLM\SYSTEM\Foo',
        r'HKLM\SAM\Foo',
        r'HKLM\SOFTWARE\Foo*',
        r'HKLM\SOFTWARE\\Foo',
      ]) {
        expect(isSafeRegDeleteKey(k, admin: true), isFalse, reason: k);
      }
    });
    test('запись Uninstall HKLM — ровно один уровень и только с админом', () {
      const a = r'HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall';
      const w = r'HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall';
      expect(isSafeRegDeleteKey('$a\\Foo', uninstallEntry: true), isFalse);
      expect(isSafeRegDeleteKey('$a\\Foo', uninstallEntry: true, admin: true), isTrue);
      expect(isSafeRegDeleteKey('$w\\Foo', uninstallEntry: true, admin: true), isTrue);
      expect(isSafeRegDeleteKey(a, uninstallEntry: true, admin: true), isFalse);
      expect(isSafeRegDeleteKey('$a\\Foo\\Bar', uninstallEntry: true, admin: true), isFalse);
      expect(isSafeRegDeleteKey(r'HKLM\SOFTWARE\Foo', uninstallEntry: true, admin: true), isFalse);
    });

    Future<List<Leftover>> find({required bool admin}) => findLeftovers(
          name: 'Foo Editor',
          publisher: 'Acme',
          installLocation: '',
          env: const Env({'APPDATA': r'C:\Users\X\AppData\Roaming', 'LOCALAPPDATA': r'C:\Users\X\AppData\Local'}),
          listDir: (_) async => const [],
          regSubKeys: (k) async => k == r'HKLM\SOFTWARE' ? ['Foo Editor', 'Microsoft'] : const [],
          sizeOf: (_, __) async => 0,
          admin: admin,
        );

    test('поиск: ключ HKLM удаляем только с админом', () async {
      final user = await find(admin: false);
      expect(user.single.path, r'HKLM\SOFTWARE\Foo Editor');
      expect(user.single.deletable, isFalse);
      final adm = await find(admin: true);
      expect(adm.single.deletable, isTrue);
    });

    group('LeftoverCleaner', () {
      late Directory tmp;
      late FakePlatform platform;
      setUp(() {
        tmp = Directory.systemTemp.createTempSync('chisto_hklm');
        platform = FakePlatform();
      });
      tearDown(() => tmp.deleteSync(recursive: true));

      LeftoverCleaner make({required bool admin}) => LeftoverCleaner(
            platform: platform,
            log: CleanLog(File('${tmp.path}${Platform.pathSeparator}log.txt')),
            env: const Env({'APPDATA': r'C:\Users\X\AppData\Roaming'}),
            backupDir: '${tmp.path}${Platform.pathSeparator}backup',
            admin: admin,
            guard: (a, b, c) => null,
          );
      Leftover reg(String k, {bool deletable = true, bool uninstall = false}) => Leftover(
          kind: LeftoverKind.registry,
          path: k,
          exact: true,
          deletable: deletable,
          isUninstallEntry: uninstall);

      test('админ: сначала экспорт .reg, потом удаление', () async {
        final out = await make(admin: true).run([reg(r'HKLM\SOFTWARE\Acme\Foo')]);
        expect(out.single.ok, isTrue);
        expect(platform.callOrder, [r'export HKLM\SOFTWARE\Acme\Foo', r'delete HKLM\SOFTWARE\Acme\Foo']);
      });

      test('экспорт не удался — ключ HKLM не удаляется', () async {
        platform.exportOk = false;
        final out = await make(admin: true).run([reg(r'HKLM\SOFTWARE\Acme\Foo')]);
        expect(out.single.ok, isFalse);
        expect(platform.deleted, isEmpty);
      });

      test('без админа HKLM не удаляется даже если помечен удаляемым', () async {
        final out = await make(admin: false).run([reg(r'HKLM\SOFTWARE\Acme\Foo')]);
        expect(out.single.ok, isFalse);
        expect(platform.callOrder, isEmpty);
      });

      test('админ: ключ из чёрного списка не удаляется', () async {
        final out = await make(admin: true)
            .run([reg(r'HKLM\SOFTWARE\Microsoft\Foo'), reg(r'HKLM\SOFTWARE\Classes\Foo')]);
        expect(out.every((o) => !o.ok), isTrue);
        expect(platform.callOrder, isEmpty);
      });

      test('админ: запись Uninstall HKLM — экспорт и удаление', () async {
        const k = r'HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Foo';
        final out = await make(admin: true).run([reg(k, uninstall: true)]);
        expect(out.single.ok, isTrue);
        expect(platform.deleted, [k]);
      });

      test('папка вне корней этого окружения не уходит в Корзину', () async {
        final out = await make(admin: true).run(
            [Leftover(kind: LeftoverKind.folder, path: r'C:\Program Files\Foo', isDir: true, exact: true)],
        );
        expect(out.single.ok, isFalse);
        expect(platform.moved, isEmpty);
      });
    });
  });

  group('AppController: режим администратора', () {
    late FakePlatform platform;
    late AppController c;
    late int exits;

    AppController make() => AppController(
          platform: platform,
          env: const Env({}),
          downloadsScan: (_) async => [],
          largeScan: (_, __) async => [],
          exitApp: () async => exits++,
        );

    setUp(() {
      platform = FakePlatform();
      exits = 0;
      c = make();
    });

    test('режим определяется по токену процесса, а не по настройке', () async {
      await c.init();
      expect(c.adminMode, isFalse);
      platform.elevated = true;
      final c2 = make();
      await c2.init();
      expect(c2.adminMode, isTrue);
    });

    test('включение: перезапуск с правами и выход', () async {
      await c.init();
      expect(await c.setAdminMode(true), RelaunchResult.started);
      expect(platform.relaunches, [true]);
      expect(exits, 1);
    });

    test('отказ в UAC: выхода нет, переключатель можно трогать снова', () async {
      await c.init();
      platform.relaunchResult = RelaunchResult.cancelled;
      expect(await c.setAdminMode(true), RelaunchResult.cancelled);
      expect(exits, 0);
      expect(c.adminBusy, isFalse);
      expect(c.canToggleAdmin, isTrue);
      expect(c.adminMode, isFalse);
    });

    test('выключение: перезапуск без прав', () async {
      platform.elevated = true;
      await c.init();
      await c.setAdminMode(false);
      expect(platform.relaunches, [false]);
      expect(exits, 1);
    });

    test('то же состояние — ничего не делаем', () async {
      await c.init();
      await c.setAdminMode(false);
      expect(platform.relaunches, isEmpty);
    });
  });

  group('автозагрузка HKLM / общая папка в режиме администратора', () {
    test('canChange зависит от права записи в ключ StartupApproved', () async {
      final p = FakePlatform();
      p.regStrings[StartupSource.hklmRun.runKey!.toLowerCase()] = {'Foo': r'C:\foo.exe'};
      final svc = StartupService(p, const Env({}), lister: (_) async => []);
      expect((await svc.load()).single.canChange, isFalse);
      p.writableKeys.add(StartupSource.hklmRun.approvedKey.toLowerCase());
      expect((await svc.load()).single.canChange, isTrue);
      p.writableKeys.add(StartupSource.commonFolder.approvedKey.toLowerCase());
    });
  });

  group('значок и папка установки программы', () {
    Program prog({
      String icon = '',
      String il = '',
      String un = '',
      int kb = 0,
      String key = 'k',
    }) =>
        Program(
          name: 'Foo',
          publisher: '',
          sizeKb: kb,
          installDate: null,
          displayIcon: icon,
          installLocation: il,
          uninstallString: un,
          quietUninstallString: '',
          hive: 'HKLM',
          keyPath: key,
        );

    test('DisplayIcon: путь, индекс, кавычки, %VAR%', () {
      IconSource? p(String s) => parseDisplayIcon(s, env: {'ProgramFiles': r'C:\Program Files'});
      expect(p(r'C:\a\x.exe'), const IconSource(r'C:\a\x.exe', 0));
      expect(p(r'C:\a\x.exe,2'), const IconSource(r'C:\a\x.exe', 2));
      expect(p(r'C:\a\x.dll, -101'), const IconSource(r'C:\a\x.dll', -101));
      expect(p(r'"C:\a b\x.exe",1'), const IconSource(r'C:\a b\x.exe', 1));
      expect(p(r'"C:\a b\x.exe"'), const IconSource(r'C:\a b\x.exe', 0));
      expect(p(r'%ProgramFiles%\Foo\f.ico'), const IconSource(r'C:\Program Files\Foo\f.ico', 0));
    });
    test('DisplayIcon: мусор → null', () {
      for (final s in ['', 'x.exe', r'\\srv\a.exe', r'C:\a\readme.txt', r'"C:\a\x.exe', r'C:\a\x.exe,abc', r'"C:\a\x.exe" /s']) {
        expect(parseDisplayIcon(s), isNull, reason: s);
      }
    });
    test('источник значка: DisplayIcon, иначе exe удаления, иначе нет', () {
      bool ex(String s) => true;
      expect(iconSourceOf(prog(icon: r'C:\a\x.exe,0', un: r'"C:\a\u.exe"'), fileExists: ex),
          const IconSource(r'C:\a\x.exe', 0));
      expect(iconSourceOf(prog(un: r'"C:\a\u.exe" /S'), fileExists: ex), const IconSource(r'C:\a\u.exe', 0));
      expect(iconSourceOf(prog(un: r'MsiExec.exe /I{ABC}'), fileExists: ex), isNull);
      expect(iconSourceOf(prog(icon: r'C:\a\x.exe,0'), fileExists: (_) => false), isNull);
      expect(iconSourceOf(prog()), isNull);
    });
    test('папка установки: InstallLocation (если папка есть)', () {
      expect(installFolderOf(prog(il: r'"C:\Program Files\Foo\"'), dirExists: (_) => true), r'C:\Program Files\Foo');
      expect(installFolderOf(prog(il: r'C:\Program Files\Foo'), dirExists: (_) => false), isNull);
      expect(installFolderOf(prog(il: 'relative'), dirExists: (_) => true), isNull);
    });
    test('папка установки: папка exe удаления — только внутри Program Files/AppData', () {
      const env = {
        'ProgramFiles': r'C:\Program Files',
        'LOCALAPPDATA': r'C:\Users\X\AppData\Local',
      };
      String? f(String un) => installFolderOf(prog(un: un),
          env: env, dirExists: (_) => true, fileExists: (_) => true);
      expect(f(r'"C:\Program Files\Foo\unins000.exe" /S'), r'C:\Program Files\Foo');
      expect(f(r'"C:\Users\X\AppData\Local\Bar\u.exe"'), r'C:\Users\X\AppData\Local\Bar');
      expect(f(r'"C:\Other\u.exe"'), isNull);
      expect(f(r'"C:\Program Files\u.exe"'), isNull);
      expect(f(r'"C:\Windows\System32\u.exe"'), isNull);
    });
    test('итог: число программ и сумма размеров', () {
      expect(programsSummary([prog(kb: 1024 * 1024), prog(kb: 1024 * 512)]),
          'Всего программ: 2 · 1,5 ГБ');
      expect(programsSummary([prog()]), 'Всего программ: 1');
      expect(programsSummary([]), 'Всего программ: 0');
    });

    test('контроллер: значок берётся один раз на источник (кэш), нет источника — null', () async {
      final p = FakePlatform()..iconBytes = Uint8List.fromList([1, 2, 3]);
      final c = AppController(
        platform: p,
        env: const Env({}),
        downloadsScan: (_) async => [],
        largeScan: (_, __) async => [],
        fileExists: (_) => true,
      );
      final a = prog(icon: r'C:\a\x.exe,0', key: 'a');
      final b = prog(icon: r'C:\A\X.exe,0', key: 'b');
      expect(await c.programIcon(a), [1, 2, 3]);
      expect(await c.programIcon(b), [1, 2, 3]);
      expect(p.iconCalls, [r'C:\a\x.exe,0']);
      expect(await c.programIcon(prog(key: 'c')), isNull);
    });
  });

  group('PNG', () {
    test('кодирует RGBA: подпись, размеры, данные восстанавливаются', () {
      final rgba = Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 128, 0, 0, 255, 0, 1, 2, 3, 4]);
      final png = encodePngRgba(2, 2, rgba);
      expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final bd = ByteData.sublistView(png);
      expect(bd.getUint32(16), 2);
      expect(bd.getUint32(20), 2);
      // IDAT: после IHDR (8 + 25 байт) идёт длина и тип
      final len = bd.getUint32(33);
      expect(String.fromCharCodes(png.sublist(37, 41)), 'IDAT');
      final raw = ZLibDecoder().convert(png.sublist(41, 41 + len));
      expect(raw.length, 2 * (1 + 8));
      expect(raw.sublist(1, 9), rgba.sublist(0, 8));
      expect(raw.sublist(10, 18), rgba.sublist(8, 16));
    });
    test('неверный размер данных — ошибка', () {
      expect(() => encodePngRgba(2, 2, Uint8List(4)), throwsArgumentError);
    });
  });
}
