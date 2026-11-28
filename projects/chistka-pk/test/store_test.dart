import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/programs.dart';
import 'package:chistka_pk/core/store_apps.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

const _json = '''[
{"Name":"Microsoft.WindowsCalculator","PackageFullName":"Microsoft.WindowsCalculator_11.2.0_x64__8wekyb3d8bbwe","PackageFamilyName":"Microsoft.WindowsCalculator_8wekyb3d8bbwe","DisplayName":"ms-resource:AppStoreName","Publisher":"Microsoft Corporation","LogoFile":"C:\\\\x\\\\Logo.scale-200.png","AppId":"App","InstallLocation":"C:\\\\Program Files\\\\WindowsApps\\\\calc","InstallDate":"2025-03-04","NonRemovable":false,"SignatureKind":"Store","SizeBytes":2048},
{"Name":"Microsoft.WindowsStore","PackageFullName":"Microsoft.WindowsStore_1_x64__8wekyb3d8bbwe","PackageFamilyName":"Microsoft.WindowsStore_8wekyb3d8bbwe","DisplayName":"Microsoft Store","Publisher":"Microsoft","AppId":"App","SignatureKind":"System","NonRemovable":false,"SizeBytes":null},
{"Name":"Bad","PackageFullName":"bad name; calc","AppId":"A"}
]''';

Program _p(String n, {bool store = false}) => Program(
      name: n,
      publisher: '',
      sizeKb: 1,
      installDate: null,
      displayIcon: '',
      installLocation: '',
      uninstallString: '',
      quietUninstallString: '',
      hive: store ? 'STORE' : 'HKCU',
      keyPath: store ? 'store:$n' : 'k$n',
      storeFullName: store ? n : null,
    );

void main() {
  test('разбор JSON Store: имя, размер, дата, замок; плохой пакет отброшен', () {
    final l = parseStoreApps(_json);
    expect(l.length, 2);
    expect(l[0].name, 'WindowsCalculator');
    expect(l[0].publisher, 'Microsoft Corporation');
    expect(l[0].sizeKb, 2);
    expect(l[0].installDate, DateTime(2025, 3, 4));
    expect(l[0].storeAppId, 'App');
    expect(l[0].locked, isFalse);
    expect(l[0].isStore, isTrue);
    expect(l[1].name, 'Microsoft Store');
    expect(l[1].locked, isTrue);
  });

  test('один объект, число SignatureKind, мусор', () {
    final one = parseStoreApps(
        '{"Name":"A.B","PackageFullName":"A.B_1_x64__x","SignatureKind":4,"InstallDate":"\\/Date(1700000000000)\\/"}');
    expect(one.single.locked, isTrue);
    expect(one.single.installDate, isNotNull);
    expect(parseStoreApps('not json'), isEmpty);
    expect(parseStoreApps(''), isEmpty);
  });

  test('неудаляемые', () {
    expect(isLockedStoreApp('X.Y', nonRemovable: true), isTrue);
    expect(isLockedStoreApp('X.Y', signatureKind: 'System'), isTrue);
    for (final n in [
      'Microsoft.WindowsStore',
      'microsoft.vclibs.140.00',
      'Microsoft.NET.Native.Runtime.2.2',
      'Microsoft.UI.Xaml.2.8',
      'MicrosoftWindows.Client.CBS',
      'windows.immersivecontrolpanel',
      'Microsoft.LockApp',
    ]) {
      expect(isLockedStoreApp(n), isTrue, reason: n);
    }
    expect(isLockedStoreApp('Microsoft.WindowsCalculator'), isFalse);
    expect(isLockedStoreApp('SpotifyAB.SpotifyMusic'), isFalse);
  });

  test('валидация PackageFullName', () {
    expect(isValidPackageFullName('Microsoft.Foo_1.2.3.0_x64__8wekyb3d8bbwe'), isTrue);
    expect(isValidPackageFullName('a_b~c-d'), isTrue);
    expect(isValidPackageFullName(''), isFalse);
    expect(isValidPackageFullName('a b'), isFalse);
    expect(isValidPackageFullName('a;calc'), isFalse);
    expect(isValidPackageFullName('a"b'), isFalse);
    expect(isValidPackageFullName(r'$env:X'), isFalse);
  });

  test('имя ярлыка', () {
    expect(shortcutFileName(r'A\B/C:D*E?F"G<H>I|J'), 'ABCDEFGHIJ');
    expect(shortcutFileName('  Foo.  '), 'Foo');
    expect(shortcutFileName('???'), 'Программа');
  });

  test('аргументы ярлыка Store', () {
    final p = Program(
        name: 'n', publisher: '', sizeKb: 0, installDate: null, displayIcon: '',
        installLocation: '', uninstallString: '', quietUninstallString: '',
        hive: 'STORE', keyPath: 'store:x', storeFullName: 'x',
        storeFamily: 'Fam_8wek', storeAppId: 'App');
    expect(storeShortcutArgs(p), r'shell:AppsFolder\Fam_8wek!App');
    expect(storeShortcutArgs(_p('a')), isNull);
  });

  test('цель ярлыка обычной программы', () {
    final p = Program(
        name: 'Foo', publisher: '', sizeKb: 0, installDate: null,
        displayIcon: r'"C:\Foo\foo.exe",0', installLocation: r'C:\Foo',
        uninstallString: '', quietUninstallString: '', hive: 'HKCU', keyPath: 'k');
    expect(shortcutTargetOf(p, fileExists: (_) => true), r'C:\Foo\foo.exe');
    expect(
        shortcutTargetOf(p,
            fileExists: (_) => false,
            exesIn: (_) => [r'C:\Foo\unins000.exe', r'C:\Foo\run.exe']),
        r'C:\Foo\run.exe');
    expect(shortcutTargetOf(p, fileExists: (_) => false, exesIn: (_) => [r'C:\Foo\a.exe', r'C:\Foo\b.exe']),
        isNull);
  });

  test('фильтр переключателя', () {
    final r = [_p('r1'), _p('r2')];
    final s = [_p('s1', store: true)];
    expect(programsOfKind(r, s, ProgramKind.regular).length, 2);
    expect(programsOfKind(r, s, ProgramKind.store).single.name, 's1');
    expect(programsOfKind(r, s, ProgramKind.all).map((e) => e.name), ['r1', 'r2', 's1']);
  });

  group('контроллер', () {
    late FakePlatform platform;
    late AppController c;
    setUp(() {
      platform = FakePlatform();
      c = AppController(
        platform: platform,
        env: const Env({'SystemRoot': r'C:\Windows'}),
        downloadsScan: (_) async => [],
        largeScan: (_, __) async => [],
        listDir: (dir) async => const [],
        sizeOf: (p, d) async => 0,
        leftoverGuard: (p, r, d) => null,
        fileExists: (p) => true,
      );
    });

    test('загрузка Store и удаление через CD_PKG с таймаутом 120 с', () async {
      platform.psResult = (code: 0, out: _json, err: '');
      c.setProgramKind(ProgramKind.store);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.storeApps.length, 2);
      expect(platform.psCalls.first.timeout, const Duration(seconds: 30));
      expect(c.visiblePrograms.length, 2);

      final calc = c.storeApps.first;
      await c.uninstallStore(calc);
      final rm = platform.psCalls.firstWhere((x) => x.env.containsKey('CD_PKG'));
      expect(rm.env['CD_PKG'], calc.storeFullName);
      expect(rm.script.contains(calc.storeFullName!), isFalse);
      expect(rm.timeout, const Duration(seconds: 120));
      expect(c.programMessage, contains('удалено'));
    });

    test('неудаляемое не удаляется', () async {
      platform.psResult = (code: 0, out: _json, err: '');
      await c.loadStoreApps();
      final store = c.storeApps.firstWhere((p) => p.locked);
      final before = platform.psCalls.length;
      await c.uninstallStore(store);
      expect(platform.psCalls.length, before);
    });

    test('ошибка удаления на экран', () async {
      platform.psResult = (code: 0, out: _json, err: '');
      await c.loadStoreApps();
      platform.psResult = (code: 1, out: '', err: 'Отказано в доступе\nстрока 2');
      await c.uninstallStore(c.storeApps.first);
      expect(c.programMessage, contains('Отказано в доступе'));
    });

    test('ярлык Store и все приложения', () async {
      platform.psResult = (code: 0, out: _json, err: '');
      await c.loadStoreApps();
      await c.createDesktopShortcut(c.storeApps.first);
      final call = platform.psCalls.last;
      expect(call.env['CD_NAME'], 'WindowsCalculator');
      expect(call.env['CD_ARGS'], r'shell:AppsFolder\Microsoft.WindowsCalculator_8wekyb3d8bbwe!App');
      expect(call.env['CD_TARGET'], r'C:\Windows\explorer.exe');
      await c.openAllApps();
      expect(platform.openAllAppsCalls, 1);
    });
  });
}
