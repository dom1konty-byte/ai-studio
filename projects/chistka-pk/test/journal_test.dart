import 'dart:io';

import 'package:chistka_pk/core/journal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('chisto_journal'));
  tearDown(() => dir.deleteSync(recursive: true));

  File logFile() => File('${dir.path}${Platform.pathSeparator}log.txt');

  test('\\t \\r \\n в имени файла заменяются пробелом: одна запись = одна строка', () async {
    final log = CleanLog(logFile());
    await log.add('Кэш', 'C:\\a\tb\r\nc.tmp', 5, 'удалено');
    await log.flush();
    final lines = logFile().readAsLinesSync();
    expect(lines.length, 1);
    expect(lines.single.split('\t').length, 5);
    expect(lines.single, contains('C:\\a b  c.tmp'));
  });

  test('log.txt больше 2 МБ переименовывается в log.old.txt', () async {
    final f = logFile()..writeAsBytesSync(List.filled(CleanLog.maxBytes + 1, 65));
    final log = CleanLog(f);
    await log.add('Кэш', 'x', 1, 'удалено');
    await log.flush();
    final old = File('${dir.path}${Platform.pathSeparator}log.old.txt');
    expect(old.existsSync(), isTrue);
    expect(old.lengthSync(), CleanLog.maxBytes + 1);
    expect(f.lengthSync(), lessThan(1000));
  });

  test('маленький журнал не ротируется, запись дописывается', () async {
    final f = logFile()..writeAsStringSync('старое\n');
    final log = CleanLog(f);
    await log.add('Кэш', 'x', 1, 'удалено');
    await log.flush();
    expect(File('${dir.path}${Platform.pathSeparator}log.old.txt').existsSync(), isFalse);
    expect(f.readAsLinesSync().length, 2);
  });
}
