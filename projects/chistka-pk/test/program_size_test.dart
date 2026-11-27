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
}

String _fmt(int b) => programsSummary([prog(kb: b ~/ 1024)]).split(' · ').last;
