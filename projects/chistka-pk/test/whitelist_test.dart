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
}
