import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pult_studii/models/models.dart';
import 'package:pult_studii/services/app_storage.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('rubka_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('R2: битая строка и битый UTF-8 пропускаются', () async {
    final dir = Directory(p.join(tmp.path, 'chats'))..createSync();
    final bytes = <int>[
      ...utf8.encode('${ChatMessage(MsgKind.user, 'привет').toJsonLine()}\n'),
      0xff, 0xfe, 0x0a, // не UTF-8
      ...utf8.encode('{broken json\n'),
      ...utf8.encode('[1,2]\n'),
      ...utf8.encode('${ChatMessage(MsgKind.director, 'ответ').toJsonLine()}\n'),
    ];
    File(p.join(dir.path, 'alpha.jsonl')).writeAsBytesSync(bytes);
    final list = await FileStorage(tmp.path).loadChat('alpha');
    expect(list.map((m) => m.text), ['привет', 'ответ']);
  });

  test('нет файла истории — пустой список', () async {
    expect(await FileStorage(tmp.path).loadChat('nope'), isEmpty);
  });

  test('R12: параллельные записи не теряются и не ломают строки', () async {
    final s = FileStorage(tmp.path);
    await Future.wait([
      for (var i = 0; i < 30; i++) s.appendChat('alpha', ChatMessage(MsgKind.user, 'м$i')),
      for (var i = 0; i < 10; i++) s.saveState({'n': i}),
    ]);
    final list = await s.loadChat('alpha');
    expect(list, hasLength(30));
    expect((await s.loadState())['n'], 9);
    expect(
        tmp.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
  });
}
