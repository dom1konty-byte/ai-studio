import 'package:chistka_pk/core/whitelist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const temp = r'C:\Users\Dam\AppData\Local\Temp';
  const roots = [temp, r'C:\Windows\Temp'];

  test('внутри корня — можно', () {
    expect(isInsideAllowedRoot(r'C:\Users\Dam\AppData\Local\Temp\a.tmp', roots), isTrue);
    expect(isInsideAllowedRoot(r'C:\Users\Dam\AppData\Local\Temp\x\y\z.log', roots), isTrue);
    expect(isInsideAllowedRoot(r'C:\Windows\Temp\q', roots), isTrue);
  });

  test('регистр и слеши не важны', () {
    expect(isInsideAllowedRoot(r'c:\users\dam\appdata\local\TEMP\a.tmp', roots), isTrue);
    expect(isInsideAllowedRoot('C:/Users/Dam/AppData/Local/Temp/a.tmp', roots), isTrue);
  });

  test('сам корень — нельзя', () {
    expect(isInsideAllowedRoot(temp, roots), isFalse);
    expect(isInsideAllowedRoot('$temp\\', roots), isFalse);
  });

  test('«..» не выводит за корень', () {
    expect(isInsideAllowedRoot('$temp\\..\\..\\Documents\\f.txt', roots), isFalse);
    expect(isInsideAllowedRoot('$temp\\..\\Temp\\f.txt', roots), isTrue);
    expect(isInsideAllowedRoot('$temp\\a\\..\\..\\..\\..\\x', roots), isFalse);
  });

  test('соседняя папка с тем же началом имени — нельзя', () {
    expect(isInsideAllowedRoot(r'C:\Users\Dam\AppData\Local\Temp2\a.tmp', roots), isFalse);
    expect(isInsideAllowedRoot(r'C:\Users\Dam\AppData\Local\Tempo', roots), isFalse);
  });

  test('чужие и относительные пути — нельзя', () {
    expect(isInsideAllowedRoot(r'C:\Users\Dam\Documents\a.docx', roots), isFalse);
    expect(isInsideAllowedRoot(r'Temp\a.tmp', roots), isFalse);
    expect(isInsideAllowedRoot('', roots), isFalse);
    expect(isInsideAllowedRoot(r'C:\Users\Dam\AppData\Local\Temp\a', const []), isFalse);
  });

  test('корень диска как «корень» не принимается', () {
    expect(isInsideAllowedRoot(r'C:\Windows\x', const [r'C:\']), isFalse);
  });

  group('isSafeCleanTarget', () {
    const prot = [
      r'C:\Users\X',
      r'C:\Users\X\Documents',
      r'C:\Users\X\Downloads',
      r'C:\Windows',
      r'C:\Program Files',
    ];
    bool ok(String p, {int min = 4}) =>
        isSafeCleanTarget(p, protectedPaths: prot, minSegments: min);

    test('нормальные цели проходят', () {
      expect(ok(r'C:\Users\X\AppData\Local\Temp'), isTrue);
      expect(ok(r'c:/users/x/appdata/local/temp'), isTrue);
      expect(ok(r'C:\Windows\Temp', min: 3), isTrue);
    });
    test('корень диска, профиль, предки и системные папки отклоняются', () {
      expect(ok(r'C:\'), isFalse);
      expect(ok(r'C:'), isFalse);
      expect(ok(r'C:\Users'), isFalse);
      expect(ok(r'C:\Users\X'), isFalse);
      expect(ok(r'c:\users\x\documents'), isFalse);
      expect(ok(r'C:\Users\X\Downloads'), isFalse);
      expect(ok(r'C:\Windows', min: 2), isFalse);
      expect(ok(r'C:\Program Files', min: 2), isFalse);
      expect(ok(''), isFalse);
    });
    test('мало сегментов', () {
      expect(ok(r'C:\Windows\Temp'), isFalse); // 3 < 4
      expect(ok(r'C:\a\b'), isFalse);
    });
    test('UNC, \\?\\, \\.\\, ":" не на месте, относительные', () {
      expect(ok(r'\\server\share\a\b\c'), isFalse);
      expect(ok(r'\\?\C:\Users\X\AppData\Local\Temp'), isFalse);
      expect(ok(r'\\.\C:\Users\X\AppData\Local\Temp'), isFalse);
      expect(ok(r'C:\Users\X\AppData\Local\Temp:stream'), isFalse);
      expect(ok(r'C:\Users\X\A:B\Local\Temp'), isFalse);
      expect(ok(r'Users\X\AppData\Local\Temp'), isFalse);
      expect(ok(r'\Users\X\AppData\Local\Temp'), isFalse);
    });
    test('хвостовые точки и пробелы в сегментах', () {
      expect(ok(r'C:\Users\X\AppData\Local\Temp.'), isFalse);
      expect(ok(r'C:\Users\X\AppData\Local\Temp '), isFalse);
      expect(ok(r'C:\Users\X\AppData\Local...\Temp'), isFalse);
    });
    test('.. не позволяет выйти в защищённую папку', () {
      expect(ok(r'C:\Users\X\AppData\Local\Temp\..\..\..'), isFalse);
    });
  });

  group('Корзина: пропуск небезопасных путей', () {
    test('причины', () {
      expect(recycleSkipReason(r'C:\Users\X\Downloads\a.zip'), isNull);
      expect(recycleSkipReason(r'\\srv\share\a.zip'), isNotNull);
      expect(recycleSkipReason(r'\\?\C:\a.zip'), isNotNull);
      expect(recycleSkipReason('C:\\${'a' * 260}'), contains('259'));
      expect(recycleSkipReason('C:\\${'a' * 250}'), isNull);
      expect(recycleSkipReason(r'C:\a\*.zip'), isNotNull);
      expect(recycleSkipReason(r'relative\a.zip'), isNotNull);
    });
    test('pFrom: пути через \\0 и двойной \\0 в конце', () {
      expect(buildDoubleNullList([r'C:\a', r'C:\b']),
          [...r'C:\a'.codeUnits, 0, ...r'C:\b'.codeUnits, 0, 0]);
    });
  });
}
