import 'package:chistka_pk/core/programs.dart';
import 'package:flutter_test/flutter_test.dart';

RawUninstall raw(String key, Map<String, String> v, {String hive = 'HKLM'}) =>
    RawUninstall(hive, '$hive\\Software\\Uninstall\\$key', v);

void main() {
  group('фильтр системных записей', () {
    final entries = [
      raw('a', {'DisplayName': 'Notepad++', 'Publisher': 'Don HO', 'EstimatedSize': '4096'}),
      raw('b', {'Publisher': 'Без имени'}),
      raw('c', {'DisplayName': 'Системный', 'SystemComponent': '1'}),
      raw('d', {'DisplayName': 'Дочерний', 'ParentKeyName': 'OperatingSystem'}),
      raw('e', {'DisplayName': 'Security Update', 'ReleaseType': 'Security Update'}),
      raw('f', {'DisplayName': 'Fix', 'ReleaseType': 'Hotfix'}),
      raw('KB5001234', {'DisplayName': 'Обновление'}),
      raw('g', {'DisplayName': 'KB5009999'}),
      raw('h', {'DisplayName': 'Мой Редактор 2', 'InstallDate': '20240315'}),
      raw('i', {'DisplayName': '  '}),
      raw('j', {'DisplayName': 'SystemComponent=0', 'SystemComponent': '0'}),
    ];

    test('остаются только обычные программы, кириллица читается', () {
      final names = buildPrograms(entries).map((e) => e.name).toList();
      expect(names, ['Notepad++', 'Мой Редактор 2', 'SystemComponent=0']);
    });

    test('поля: размер, дата, издатель', () {
      final p = buildPrograms(entries).first;
      expect(p.sizeKb, 4096);
      expect(p.sizeBytes, 4096 * 1024);
      expect(p.publisher, 'Don HO');
      final q = buildPrograms(entries)[1];
      expect(q.installDate, DateTime(2024, 3, 15));
    });

    test('одинаковые имя и издатель из разных веток схлопываются', () {
      final r = buildPrograms([
        raw('x', {'DisplayName': 'Foo', 'Publisher': 'Bar'}, hive: 'HKLM'),
        raw('x', {'DisplayName': 'foo', 'Publisher': 'bar'}, hive: 'HKLM32'),
      ]);
      expect(r, hasLength(1));
    });

    test('parseInstallDate', () {
      expect(parseInstallDate('20250102'), DateTime(2025, 1, 2));
      expect(parseInstallDate('2025-01-02'), isNull);
      expect(parseInstallDate('20251302'), isNull);
      expect(parseInstallDate(null), isNull);
    });
  });

  group('поиск и сортировка', () {
    final list = buildPrograms([
      raw('1', {'DisplayName': 'Beta', 'Publisher': 'Zed', 'EstimatedSize': '100', 'InstallDate': '20200101'}),
      raw('2', {'DisplayName': 'alpha', 'Publisher': 'Acme', 'EstimatedSize': '900', 'InstallDate': '20230101'}),
      raw('3', {'DisplayName': 'Gamma', 'Publisher': 'Acme'}),
    ]);

    test('по размеру: большие выше, без размера в конце', () {
      expect(filterAndSort(list, '', ProgramSort.size).map((p) => p.name), ['alpha', 'Beta', 'Gamma']);
    });
    test('по дате: новые выше, без даты в конце', () {
      expect(filterAndSort(list, '', ProgramSort.date).map((p) => p.name), ['alpha', 'Beta', 'Gamma']);
    });
    test('по имени без учёта регистра', () {
      expect(filterAndSort(list, '', ProgramSort.name).map((p) => p.name), ['alpha', 'Beta', 'Gamma']);
    });
    test('поиск по имени и издателю', () {
      expect(filterAndSort(list, 'ALP', ProgramSort.name).map((p) => p.name), ['alpha']);
      expect(filterAndSort(list, 'acme', ProgramSort.name), hasLength(2));
      expect(filterAndSort(list, 'нет такой', ProgramSort.name), isEmpty);
    });
  });

  group('разбор строки удаления', () {
    final existing = <String>{
      r'c:\program files\foo\unins000.exe',
      r'c:\foo\uninst.exe',
      r'c:\program files\foo bar\uninstall.exe',
      r'c:\program files\foo\u.exe',
      r'c:\program files\foo\unins.exe',
      r'c:\program\unins.exe',
    };
    bool ex(String p) => existing.contains(p.toLowerCase());
    UninstallCommand? parse(String s, {Map<String, String> env = const {}}) =>
        parseUninstallString(s, env: env, fileExists: ex);

    test('в кавычках с аргументами', () {
      final c = parse(r'"C:\Program Files\Foo\unins000.exe" /SILENT');
      expect(c!.exe, r'C:\Program Files\Foo\unins000.exe');
      expect(c.args, '/SILENT');
    });
    test('в кавычках без аргументов', () {
      final c = parse(r'"C:\Foo\uninst.exe"');
      expect(c!.exe, r'C:\Foo\uninst.exe');
      expect(c.args, '');
    });
    test('без кавычек, путь с пробелами', () {
      final c = parse(r'C:\Program Files\Foo Bar\uninstall.exe /allusers');
      expect(c!.exe, r'C:\Program Files\Foo Bar\uninstall.exe');
      expect(c.args, '/allusers');
    });
    test('без кавычек: самый короткий существующий .exe, а не резка по первому пробелу', () {
      // C:\Program не существует и не .exe → идём дальше по пробелам
      final c = parse(r'C:\Program Files\Foo\unins.exe /S /x.exe');
      expect(c!.exe, r'C:\Program Files\Foo\unins.exe');
      expect(c.args, '/S /x.exe');
    });
    test('файла нет → null (программа удаления не найдена)', () {
      expect(parse(r'"C:\Missing\u.exe" /S'), isNull);
      expect(parse(r'C:\Missing Dir\u.exe /S'), isNull);
    });
    test('относительный, UNC и не-exe пути отвергаются', () {
      expect(parse(r'u.exe /S'), isNull);
      expect(parse(r'"..\Foo\u.exe"'), isNull);
      expect(parse(r'"\\server\share\u.exe"'), isNull);
      expect(parse(r'"C:\Foo\uninst.bat"'), isNull);
      expect(parse(r'cmd.exe /c del x'), isNull);
    });
    test('MsiExec /I{GUID} → /X{GUID}, запуск из System32', () {
      final c = parse('MsiExec.exe /I{12345678-ABCD-1234-ABCD-1234567890AB}',
          env: {'SystemRoot': r'C:\Windows'});
      expect(c!.exe, r'C:\Windows\System32\msiexec.exe');
      expect(c.args, '/X{12345678-ABCD-1234-ABCD-1234567890AB}');
    });
    test('msiexec с чужим путём заменяется на системный', () {
      final c = parse(r'"C:\evil\msiexec.exe" /X{AAAA-BBBB} /qn', env: {'SystemRoot': r'C:\Windows'});
      expect(c!.exe, r'C:\Windows\System32\msiexec.exe');
      expect(c.args, '/X{AAAA-BBBB} /qn');
    });
    test('rundll32 → System32', () {
      final c = parse(r'rundll32.exe advpack.dll,LaunchINFSection x.inf', env: {'SystemRoot': r'D:\Win'});
      expect(c!.exe, r'D:\Win\System32\rundll32.exe');
      expect(c.args, 'advpack.dll,LaunchINFSection x.inf');
    });
    test('переменные окружения раскрываются', () {
      final c = parse(r'"%ProgramFiles%\Foo\u.exe" -x', env: {'ProgramFiles': r'C:\Program Files'});
      expect(c!.exe, r'C:\Program Files\Foo\u.exe');
    });
    test('пустая и битая строки → null', () {
      expect(parse(''), isNull);
      expect(parse('   '), isNull);
      expect(parse(r'"C:\Foo\u.exe /S'), isNull);
    });
  });
}
