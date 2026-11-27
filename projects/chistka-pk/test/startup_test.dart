import 'dart:typed_data';

import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/startup.dart';
import 'package:chistka_pk/state/startup_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

void main() {
  group('StartupApproved: разбор', () {
    test('нет значения или пусто = включено', () {
      expect(parseApproved(null), isTrue);
      expect(parseApproved(Uint8List(0)), isTrue);
    });
    test('чётный первый байт = включено, нечётный = выключено', () {
      expect(parseApproved(Uint8List.fromList([2, 0, 0, 0])), isTrue);
      expect(parseApproved(Uint8List.fromList([6, 0, 0, 0])), isTrue);
      expect(parseApproved(Uint8List.fromList([3, 0, 0, 0])), isFalse);
      expect(parseApproved(Uint8List.fromList([7, 0, 0, 0])), isFalse);
    });
  });

  group('StartupApproved: сборка', () {
    test('включить = 02 и 11 нулей', () {
      final b = buildApproved(true, DateTime.utc(2026, 1, 1));
      expect(b, Uint8List.fromList([2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]));
    });
    test('выключить = 03 00 00 00 + FILETIME', () {
      final t = DateTime.utc(2026, 1, 1);
      final b = buildApproved(false, t);
      expect(b.length, 12);
      expect(b.sublist(0, 4), [3, 0, 0, 0]);
      final bd = ByteData.sublistView(b);
      final ft = bd.getUint32(4, Endian.little) | (bd.getUint32(8, Endian.little) << 32);
      expect(ft, filetimeOf(t));
      expect(parseApproved(b), isFalse);
    });
    test('FILETIME: эпоха Unix = 116444736000000000', () {
      expect(filetimeOf(DateTime.utc(1970)), 116444736000000000);
    });
  });

  group('источники', () {
    test('ключи StartupApproved и права', () {
      expect(StartupSource.hkcuRun.approvedKey, endsWith(r'StartupApproved\Run'));
      expect(StartupSource.hkcuRun.approvedKey, startsWith('HKCU'));
      expect(StartupSource.hklmRun32.approvedKey, startsWith(r'HKLM\'));
      expect(StartupSource.hklmRun32.approvedKey, endsWith('Run32'));
      expect(StartupSource.commonFolder.approvedKey, endsWith('StartupFolder'));
      expect(StartupSource.hkcuRun.needsAdmin, isFalse);
      expect(StartupSource.userFolder.needsAdmin, isFalse);
      expect(StartupSource.hklmRun.needsAdmin, isTrue);
      expect(StartupSource.commonFolder.needsAdmin, isTrue);
    });
  });

  group('StartupService (фейк)', () {
    late FakePlatform p;
    late StartupService svc;
    final t = DateTime.utc(2026, 5, 5);

    setUp(() {
      p = FakePlatform();
      p.regStrings[StartupSource.hkcuRun.runKey!.toLowerCase()] = {
        'Telegram': r'"C:\T\Telegram.exe" -autostart',
      };
      p.regStrings[StartupSource.hklmRun.runKey!.toLowerCase()] = {'Tool': r'C:\Tool.exe'};
      svc = StartupService(
        p,
        const Env({'APPDATA': r'C:\U\AppData\Roaming', 'ProgramData': r'C:\PD'}),
        lister: (dir) async => dir.startsWith(r'C:\U') ? ['Notes.lnk', 'desktop.ini'] : [],
        now: () => t,
      );
    });

    test('читает все источники, состояние из StartupApproved, desktop.ini пропущен', () async {
      p.regBinaries[StartupSource.hkcuRun.approvedKey.toLowerCase()] = {
        'Telegram': Uint8List.fromList([3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
      };
      final items = await svc.load();
      expect(items.map((e) => e.name), ['Notes', 'Telegram', 'Tool']);
      expect(items.firstWhere((e) => e.name == 'Telegram').enabled, isFalse);
      expect(items.firstWhere((e) => e.name == 'Notes').enabled, isTrue);
      expect(items.firstWhere((e) => e.name == 'Notes').path,
          r'C:\U\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Notes.lnk');
    });

    test('HKLM без прав: выключатель неактивен, запись не пишется', () async {
      final items = await svc.load();
      final tool = items.firstWhere((e) => e.name == 'Tool');
      expect(tool.canChange, isFalse);
      expect(await svc.setEnabled(tool, false), isFalse);
      expect(p.regBinaries[StartupSource.hklmRun.approvedKey.toLowerCase()], isNull);
    });

    test('HKLM с правами: пишет в StartupApproved', () async {
      p.writableKeys.add(StartupSource.hklmRun.approvedKey.toLowerCase());
      final tool = (await svc.load()).firstWhere((e) => e.name == 'Tool');
      expect(tool.canChange, isTrue);
      expect(await svc.setEnabled(tool, false), isTrue);
      expect(p.regBinaries[StartupSource.hklmRun.approvedKey.toLowerCase()]!['Tool']![0], 3);
    });

    test('выключение не трогает запись Run и ярлык; обратное включение работает', () async {
      var tg = (await svc.load()).firstWhere((e) => e.name == 'Telegram');
      expect(await svc.setEnabled(tg, false), isTrue);
      final runKey = StartupSource.hkcuRun.runKey!.toLowerCase();
      expect(p.regStrings[runKey], {'Telegram': r'"C:\T\Telegram.exe" -autostart'});
      tg = (await svc.load()).firstWhere((e) => e.name == 'Telegram');
      expect(tg.enabled, isFalse);
      expect(await svc.setEnabled(tg, true), isTrue);
      tg = (await svc.load()).firstWhere((e) => e.name == 'Telegram');
      expect(tg.enabled, isTrue);
    });

    test('ярлык из папки: имя значения — полное имя файла', () async {
      final notes = (await svc.load()).firstWhere((e) => e.name == 'Notes');
      await svc.setEnabled(notes, false);
      expect(p.regBinaries[StartupSource.userFolder.approvedKey.toLowerCase()]!.keys,
          ['Notes.lnk']);
    });
  });
}
