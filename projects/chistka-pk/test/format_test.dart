import 'package:chistka_pk/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('размеры', () {
    expect(formatSize(0), '0 Б');
    expect(formatSize(512), '512 Б');
    expect(formatSize(1023), '1023 Б');
    expect(formatSize(1024), '1,0 КБ');
    expect(formatSize((48.3 * 1024 * 1024).round()), '48,3 МБ');
    expect(formatSize((2.1 * 1024 * 1024 * 1024).round()), '2,1 ГБ');
    expect(formatSize(1024 * 1024 * 1024), '1,0 ГБ');
  });

  test('слово «файл»', () {
    expect(filesWord(1), '1 файл');
    expect(filesWord(3), '3 файла');
    expect(filesWord(11), '11 файлов');
    expect(filesWord(17), '17 файлов');
    expect(filesWord(21), '21 файл');
  });

  test('дата', () {
    expect(formatDate(DateTime(2026, 8, 12)), '12.08.2026');
  });
}
