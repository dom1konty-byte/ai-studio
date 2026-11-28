import 'dart:async';

import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/programs.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

const _env = {
  'ProgramFiles': r'C:\Program Files',
  'ProgramFiles(x86)': r'C:\Program Files (x86)',
  'LOCALAPPDATA': r'C:\Users\X\AppData\Local',
  'APPDATA': r'C:\Users\X\AppData\Roaming',
  'ProgramData': r'C:\ProgramData',
  'SystemRoot': r'C:\Windows',
};

Program prog({
  String name = 'Foo Editor',
  String install = '',
  String uninstall = '',
  String icon = '',
  int kb = 0,
}) =>
    Program(
      name: name,
      publisher: '',
      sizeKb: kb,
      installDate: null,
      displayIcon: icon,
      installLocation: install,
      uninstallString: uninstall,
      quietUninstallString: '',
      hive: 'HKLM',
      keyPath: r'HKLM\U\' + name,
    );

String? pick(Program p) =>
    sizeFolderOf(p, env: _env, dirExists: (_) => true, fileExists: (_) => true);

void main() {
  group('выбор папки для размера программы', () {
    test('InstallLocation внутри Program Files — берём её', () {
      expect(pick(prog(install: r'C:\Program Files\Foo')), r'C:\Program Files\Foo');
      expect(pick(prog(install: r'"C:\Program Files (x86)\Foo"')), r'C:\Program Files (x86)\Foo');
      expect(pick(prog(install: r'C:\Users\X\AppData\Local\Programs\Foo')),
          r'C:\Users\X\AppData\Local\Programs\Foo');
      expect(pick(prog(install: r'C:\ProgramData\Foo')), r'C:\ProgramData\Foo');
    });

    test('нет InstallLocation — папка программы удаления, затем папка DisplayIcon', () {
      expect(pick(prog(uninstall: r'"C:\Program Files\Foo\unins000.exe" /S')), r'C:\Program Files\Foo');
      expect(pick(prog(icon: r'C:\Program Files\Foo\foo.exe,0')), r'C:\Program Files\Foo');
      // InstallLocation приоритетнее
      expect(
          pick(prog(
              install: r'C:\Program Files\Foo',
              uninstall: r'"C:\Program Files\Other\u.exe"')),
          r'C:\Program Files\Foo');
    });

    test('недопустимая InstallLocation пропускается — берём следующий источник', () {
      expect(
          pick(prog(install: r'C:\Windows\System32', icon: r'C:\Program Files\Foo\foo.exe')),
          r'C:\Program Files\Foo');
    });

    test('сам Program Files / AppData / корень диска — не считаем', () {
      for (final d in [
        r'C:\Program Files',
        r'C:\Program Files (x86)',
        r'C:\Users\X\AppData\Local',
        r'C:\Users\X\AppData\Roaming',
        r'C:\ProgramData',
        r'C:\',
        r'D:\',
        r'C:',
      ]) {
        expect(pick(prog(install: d)), isNull, reason: d);
      }
    });

    test('Windows, System32, Common Files и другие общие папки — не считаем', () {
      for (final d in [
        r'C:\Windows',
        r'C:\Windows\System32',
        r'C:\Windows\Installer\Foo',
        r'C:\Program Files\Common Files',
        r'C:\Program Files\Common Files\Foo Shared',
        r'C:\Program Files (x86)\Common Files\Foo',
        r'C:\Program Files\WindowsApps\Foo',
        r'C:\Users\X\AppData\Local\Programs',
        r'C:\Users\X\AppData\Local\Microsoft',
      ]) {
        expect(pick(prog(install: d)), isNull, reason: d);
      }
      // msiexec живёт в System32 — папку программы из него не берём
      expect(pick(prog(uninstall: r'MsiExec.exe /X{AAAA}')), isNull);
    });

    test('другой диск: только если имя папки содержит имя программы', () {
      expect(pick(prog(name: 'Steam', install: r'D:\Games\Steam')), r'D:\Games\Steam');
      expect(pick(prog(name: 'Foo Editor', install: r'D:\Apps\FooEditor 3')), r'D:\Apps\FooEditor 3');
      expect(pick(prog(name: 'Steam', install: r'D:\Games')), isNull);
      expect(pick(prog(name: 'Steam', install: r'D:\Other\Tool')), isNull);
      expect(pick(prog(name: 'Foo Editor', install: r'D:\Foo')), isNull); // имя папки короче имени
      expect(pick(prog(name: 'Steam', install: r'D:\Steam')), r'D:\Steam');
    });

    test('папки нет на диске — null', () {
      expect(
          sizeFolderOf(prog(install: r'C:\Program Files\Foo'),
              env: _env, dirExists: (_) => false, fileExists: (_) => true),
          isNull);
    });
  });

  test('итог «Всего» учитывает посчитанные размеры и ставит ≈', () {
    final a = prog(name: 'A', kb: 1024); // 1 МБ
    final b = prog(name: 'B');
    final list = [a, b];
    expect(programsSummary(list), 'Всего программ: 2 · ${_fmt(1024 * 1024)}');
    final withApprox = programsSummary(list, {b.keyPath: 1024 * 1024});
    expect(withApprox, startsWith('Всего программ: 2 · ≈ '));
    expect(programBytes(b, {b.keyPath: 5}), 5);
    expect(programBytes(a, {a.keyPath: 5}), 1024 * 1024);
  });

  test('сортировка по размеру учитывает посчитанное', () {
    final a = prog(name: 'A', kb: 10);
    final b = prog(name: 'B');
    final res = filterAndSort([a, b], '', ProgramSort.size, {b.keyPath: 1024 * 1024});
    expect(res.first.name, 'B');
  });

  test('контроллер: размеры считаются в фоне очередью не более 2 одновременно', () async {
    final platform = FakePlatform();
    platform.uninstallEntries = [
      for (var i = 0; i < 6; i++)
        RawUninstall('HKLM', 'HKLM\\Software\\Uninstall\\k$i', {
          'DisplayName': 'Prog $i',
          'InstallLocation': 'C:\\Program Files\\Prog$i',
        }),
      RawUninstall('HKLM', r'HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\sized', {
        'DisplayName': 'Sized',
        'EstimatedSize': '100',
        'InstallLocation': r'C:\Program Files\Sized',
      }),
    ];
    var running = 0, maxRunning = 0;
    final asked = <String>[];
    final gates = <Completer<int>>[];
    final c = AppController(
      platform: platform,
      env: const Env(_env),
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
      dirExists: (_) => true,
      fileExists: (_) => true,
      sizeOf: (path, isDir) async {
        asked.add(path);
        running++;
        if (running > maxRunning) maxRunning = running;
        final g = Completer<int>();
        gates.add(g);
        final v = await g.future;
        running--;
        return v;
      },
    );
    await c.loadPrograms();
    await Future<void>.delayed(Duration.zero);
    expect(asked.length, 2); // очередь: только двое сразу
    expect(c.programApprox, isEmpty);
    while (asked.length < 6 || gates.any((g) => !g.isCompleted)) {
      for (final g in gates.where((g) => !g.isCompleted).toList()) {
        g.complete(2048);
      }
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(maxRunning, lessThanOrEqualTo(2));
    expect(asked, isNot(contains(r'C:\Program Files\Sized'))); // есть EstimatedSize — не считаем
    expect(c.programApprox.length, 6);
    expect(c.programApprox.values.every((v) => v == 2048), isTrue);
  });

  group('план размеров: общие папки', () {
    Program game(String n, {String install = '', String? sizeless}) => Program(
          name: n,
          publisher: '',
          sizeKb: 0,
          installDate: null,
          displayIcon: '',
          installLocation: install,
          uninstallString: r'"C:\Program Files (x86)\Steam\steam.exe" steam://uninstall/',
          quietUninstallString: '',
          hive: 'HKLM',
          keyPath: r'HKLM\U\' + n,
        );

    Map<String, String> plan(List<Program> l, {String? steam}) => planProgramSizeFolders(l,
        env: _env, steamPath: steam, dirExists: (_) => true, fileExists: (_) => true);

    test('игры Steam не получают размер всего Steam', () {
      final a = game('A', install: r'C:\Program Files (x86)\Steam\steamapps\common\A');
      final b = game('B');
      final steam = prog(name: 'Steam', install: r'C:\Program Files (x86)\Steam');
      final p = plan([a, b, steam], steam: r'C:\Program Files (x86)\Steam');
      expect(p[a.keyPath], r'C:\Program Files (x86)\Steam\steamapps\common\A');
      expect(p.containsKey(b.keyPath), isFalse); // запасная папка общая — «—»
      expect(p.containsKey(steam.keyPath), isFalse); // Steam целиком и предок игры
    });

    test('запасная папка одной программы берётся, общей двух — нет', () {
      final one = prog(name: 'Solo App', uninstall: r'"C:\Program Files\Solo\unins.exe"');
      expect(plan([one])[one.keyPath], r'C:\Program Files\Solo');
      final x = prog(name: 'Xapp', uninstall: r'"C:\Program Files\Shared\u.exe"');
      final y = prog(name: 'Yapp', icon: r'C:\Program Files\Shared\y.exe,0');
      expect(plan([x, y]), isEmpty);
    });

    test('Package Cache и предок чужого InstallLocation исключены', () {
      final cache = prog(name: 'Redist', install: r'C:\ProgramData\Package Cache\{abc}');
      expect(plan([cache]), isEmpty);
      final parent = prog(name: 'Suite', install: r'C:\Program Files\Vendor');
      final child = prog(name: 'Child', install: r'C:\Program Files\Vendor\Child');
      final p = plan([parent, child]);
      expect(p.containsKey(parent.keyPath), isFalse);
      expect(p[child.keyPath], r'C:\Program Files\Vendor\Child');
    });

    test('контроллер: одна папка считается один раз (кэш)', () async {
      var calls = 0;
      final a = prog(name: 'AppA', install: r'C:\Program Files\Same');
      final b = prog(name: 'AppB', install: r'C:\Program Files\Same');
      final platform = FakePlatform()..uninstallEntries = [];
      final c = AppController(
        platform: platform,
        env: const Env(_env),
        dataDir: '/tmp/x',
        downloadsScan: (_) async => [],
        largeScan: (_, __) async => [],
        dirExists: (_) => true,
        sizeOf: (path, isDir) async {
          calls++;
          return 1000;
        },
      );
      c.programs = [a, b];
      await c.debugStartProgramSizes();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, 1);
      expect(c.programApprox.length, 2);
    });
  });
}

String _fmt(int b) => programsSummary([prog(kb: b ~/ 1024)]).split(' · ').last;
