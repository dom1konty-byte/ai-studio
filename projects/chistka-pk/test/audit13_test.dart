import 'dart:io';

import 'package:chistka_pk/core/battery.dart';
import 'package:chistka_pk/core/duplicates.dart';
import 'package:chistka_pk/core/hidden.dart';
import 'package:chistka_pk/core/killable.dart';
import 'package:chistka_pk/core/models.dart';
import 'package:chistka_pk/core/procs.dart';
import 'package:flutter_test/flutter_test.dart';

int _sleepForever() {
  var x = 0;
  final sw = Stopwatch()..start();
  while (sw.elapsed < const Duration(seconds: 30)) {
    x++;
  }
  return x;
}

int _quick() => 42;

void main() {
  test('облачные атрибуты OneDrive: не читать', () {
    expect(isCloudAttributes(0x400000), isTrue); // RECALL_ON_DATA_ACCESS
    expect(isCloudAttributes(0x40000), isTrue); // RECALL_ON_OPEN
    expect(isCloudAttributes(0x1000), isTrue); // OFFLINE
    expect(isCloudAttributes(0x20 | 0x1000), isTrue);
    expect(isCloudAttributes(0x20), isFalse); // ARCHIVE
    expect(isCloudAttributes(0x2 | 0x4), isFalse); // hidden|system — другая проверка
    expect(isCloudOnly('/нет/такого'), isFalse); // не Windows — false
  });

  test('поиск дубликатов пропускает облачные файлы, не открывая их', () {
    final d = Directory.systemTemp.createTempSync('chisto_cloud');
    addTearDown(() => d.deleteSync(recursive: true));
    final data = List.filled(2048, 7);
    for (final n in ['a.bin', 'b.bin', 'cloud.bin']) {
      File('${d.path}/$n').writeAsBytesSync(data);
    }
    final res = scanDuplicatesSync([d.path],
        minSize: 1000, hidden: (_) => false, cloudOnly: (p) => p.endsWith('cloud.bin'));
    expect(res, hasLength(1));
    expect(res.single.files.map((f) => f.name).toSet(), {'a.bin', 'b.bin'});
  });

  test('прогресс: не чаще раза в 200 мс, с процентом', () {
    var now = DateTime(2026);
    final t = ProgressThrottle(clock: () => now);
    expect(t.allow(), isTrue);
    now = now.add(const Duration(milliseconds: 100));
    expect(t.allow(), isFalse);
    now = now.add(const Duration(milliseconds: 100));
    expect(t.allow(), isTrue);
    expect(dupProgressText(1, 4), 'Ищу… 25 %');
    expect(dupProgressText(9, 4), 'Ищу… 100 %');
    expect(dupProgressText(0, 0), 'Ищу… 0 %');
  });

  test('группировка сообщает проценты', () {
    final d = Directory.systemTemp.createTempSync('chisto_pct');
    addTearDown(() => d.deleteSync(recursive: true));
    final files = <FileInfo>[];
    for (var i = 0; i < 40; i++) {
      final f = File('${d.path}/f$i')..writeAsBytesSync(List.filled(100, i % 2));
      files.add(FileInfo(f.path, 100, DateTime(2020)));
    }
    final stages = <String>[];
    groupDuplicatesSync(files, onStage: stages.add);
    expect(stages.any((s) => RegExp(r'^Ищу… \d+ %$').hasMatch(s)), isTrue);
  });

  test('перепроверка перед удалением учитывает дату изменения', () {
    final d = Directory.systemTemp.createTempSync('chisto_mod');
    addTearDown(() => d.deleteSync(recursive: true));
    final a = File('${d.path}/a')..writeAsBytesSync([1, 2, 3]);
    final b = File('${d.path}/b')..writeAsBytesSync([1, 2, 3]);
    final mA = a.lastModifiedSync();
    final mB = b.lastModifiedSync();
    final g = DupGroup([FileInfo(a.path, 3, mA), FileInfo(b.path, 3, mB)]);
    final sel = {g.files.last.path};
    expect(planDupDelete([g], sel).files, hasLength(1));
    // файл изменили после поиска (тот же размер, другая дата)
    File(g.files.last.path).setLastModifiedSync(mB.add(const Duration(hours: 1)));
    final p = planDupDelete([g], sel);
    expect(p.files, isEmpty);
    expect(p.skipped, 1);
    expect(sameModified(DateTime(2026, 1, 1, 0, 0, 1), DateTime(2026)), isTrue);
    expect(sameModified(DateTime(2026, 1, 1, 0, 1), DateTime(2026)), isFalse);
  });

  test('runKillable: результат и настоящее убийство', () async {
    final g = KillGroup();
    expect(await runKillable(_quick, g), 42);
    expect(g.running, 0);
    final f = runKillable(_sleepForever, g);
    final fail = expectLater(f, throwsA(isA<StateError>()));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(g.running, 1);
    g.killAll();
    await fail;
    expect(g.running, 0);
  });

  test('новые системные процессы в запрете', () {
    for (final n in [
      'taskhostw.exe', 'WUDFHost.exe', 'lsm.exe', 'dllhost.exe', 'SmartScreen.exe',
      'SecurityHealthSystray.exe', 'SearchIndexer.exe', 'ApplicationFrameHost.exe',
      'sgrmbroker.exe', 'MsSense.exe', 'NisSrv.exe', 'wlanext.exe', 'dashost.exe',
    ]) {
      expect(isProtectedProcess(n, 1234), isTrue, reason: n);
    }
    expect(isProtectedProcess('notepad.exe', 1234), isFalse);
  });

  test('батарея: полная ёмкость 0 — «нет данных»', () {
    expect(const BatteryInfo(design: 50000, full: 0).noData, isTrue);
    expect(const BatteryInfo(design: 50000, full: 40000).noData, isFalse);
  });
}
