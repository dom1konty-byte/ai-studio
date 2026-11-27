import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/whitelist.dart';
import 'package:flutter_test/flutter_test.dart';

Env env(Map<String, String> extra) => Env({
      'USERPROFILE': r'C:\Users\X',
      'LOCALAPPDATA': r'C:\Users\X\AppData\Local',
      'APPDATA': r'C:\Users\X\AppData\Roaming',
      'SystemRoot': r'C:\Windows',
      'ProgramFiles': r'C:\Program Files',
      'ProgramFiles(x86)': r'C:\Program Files (x86)',
      ...extra,
    });

void main() {
  const safe = r'C:\Users\X\AppData\Local\Temp';

  group('TEMP: принимается только безопасное', () {
    test('TEMP игнорируется: всегда LOCALAPPDATA\\Temp', () {
      expect(resolveUserTemp(env({'TEMP': safe}))!.dir, safe);
      expect(resolveUserTemp(env({'TEMP': '$safe\\sub'}))!.dir, safe);
      expect(resolveUserTemp(env({'TEMP': r'C:\Users\X\AppData\Local\Foo\Temp'}))!.dir, safe);
    });
    test('TEMP в коротком виде 8.3 → используется LOCALAPPDATA\\Temp', () {
      final e = env({
        'LOCALAPPDATA': r'C:\Users\Дамир\AppData\Local',
        'TEMP': r'C:\Users\4D0A~1\AppData\Local\Temp',
      });
      final r = resolveUserTemp(e)!;
      expect(r.dir, r'C:\Users\Дамир\AppData\Local\Temp');
      expect(r.base, r'C:\Users\Дамир\AppData\Local');
    });
    for (final bad in [
      r'C:\',
      r'C:\Users\X',
      r'C:\Users\X\Documents',
      r'C:\Windows',
      r'C:\Windows\Temp',
      r'C:\Temp',
      r'D:\Users\X\AppData\Local\Temp',
      r'\\srv\share\Temp',
      r'C:\Users\X\AppData\Local\Temp\..\..',
      '',
    ]) {
      test('TEMP="$bad" заменяется на %LOCALAPPDATA%\\Temp', () {
        final r = resolveUserTemp(env({'TEMP': bad}));
        expect(r!.dir, safe);
      });
    }
    test('TEMP=%USERPROFILE% заменяется', () {
      expect(resolveUserTemp(env({'TEMP': r'C:\Users\X'}))!.dir, safe);
    });
    test('нет LOCALAPPDATA — цели нет', () {
      final e = Env({'USERPROFILE': r'C:\Users\X', 'TEMP': r'C:\Users\X'});
      expect(resolveUserTemp(e), isNull);
    });
    test('результат проходит общую защиту, а плохие значения — нет', () {
      final e = env({'TEMP': r'C:\'});
      final prot = protectedPathsOf(e);
      expect(isSafeCleanTarget(resolveUserTemp(e)!.dir, protectedPaths: prot), isTrue);
      for (final bad in [r'C:\', r'C:\Users\X', r'C:\Windows']) {
        expect(isSafeCleanTarget(bad, protectedPaths: prot), isFalse);
      }
    });
  });

  test('защищённые папки включают профиль, Documents/Downloads, Windows, Program Files', () {
    final p = protectedPathsOf(env({'OneDrive': r'C:\Users\X\OneDrive'}));
    expect(p, containsAll([
      r'C:\Users\X',
      r'C:\Users\X\Documents',
      r'C:\Users\X\Desktop',
      r'C:\Users\X\Downloads',
      r'C:\Users\X\Pictures',
      r'C:\Users\X\OneDrive',
      r'C:\Windows',
      r'C:\Program Files',
      r'C:\Program Files (x86)',
    ]));
  });

  test('диск системы берётся из SystemRoot', () {
    expect(systemDriveRoot(Env({'SystemRoot': r'D:\Windows'})), r'D:\');
    expect(systemDriveRoot(Env({'SystemDrive': 'e:'})), r'E:\');
    expect(systemDriveRoot(const Env({})), r'C:\');
  });

  group('Steam', () {
    final prot = protectedPathsOf(env({}));
    String? check(String? raw, {bool steamExe = true, bool dir = true}) => validSteamPath(
          raw,
          prot,
          dirExists: (_) => dir,
          fileExists: (f) => steamExe && f.toLowerCase().endsWith('steam.exe'),
        );
    test('нормальный путь принимается (слэши исправляются)', () {
      expect(check(r'C:\Program Files (x86)\Steam'), r'C:\Program Files (x86)\Steam');
      expect(check('D:/Games/Steam'), r'D:\Games\Steam');
    });
    test('UNC, относительные, пустые, без steam.exe, несуществующие — отклоняются', () {
      expect(check(null), isNull);
      expect(check(''), isNull);
      expect(check(r'\\srv\share\Steam'), isNull);
      expect(check(r'Steam'), isNull);
      expect(check(r'C:\Program Files (x86)\Steam', steamExe: false), isNull);
      expect(check(r'C:\Program Files (x86)\Steam', dir: false), isNull);
    });
    test('защита: корень диска, профиль, Windows, Program Files — отклоняются', () {
      expect(check(r'C:\'), isNull);
      expect(check(r'C:\Users\X'), isNull);
      expect(check(r'C:\Windows'), isNull);
      expect(check(r'C:\Program Files (x86)'), isNull);
      expect(check(r'C:\Users'), isNull);
    });
    test('без Steam нет строки Steam в каталоге (и нет пути по умолчанию)', () {
      final cats = buildCatalog(env({}), steamPath: null);
      expect(cats.any((c) => c.id.name == 'steam'), isFalse);
    });
  });

  test('buildCatalog с мусорным окружением не создаёт целей вне безопасных папок', () {
    final bad = Env({
      'TEMP': r'C:\',
      'LOCALAPPDATA': r'C:\',
      'APPDATA': r'C:\Users\X',
      'USERPROFILE': r'C:\Users\X',
      'SystemRoot': r'C:\',
    });
    final cats = buildCatalog(bad);
    for (final c in cats) {
      for (final t in c.targets) {
        fail('неожиданная цель ${t.dir}');
      }
    }
  });
}
