import 'dart:convert';
import 'dart:io';

import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/models.dart';
import 'package:chistka_pk/core/settings.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

AppController _make(FakePlatform p, String dir) => AppController(
      platform: p,
      env: const Env({}),
      dataDir: dir,
      exePath: r'C:\Apps\ChistoDisk\chistka_pk.exe',
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
    );

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chisto_set'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('settings.json', () {
    test('нет файла или мусор: значения по умолчанию', () async {
      final f = File('${tmp.path}/settings.json');
      expect((await SettingsStore(f).load()).minimizeToTray, isTrue);
      expect((await SettingsStore(f).load()).autostart, isFalse);
      f.writeAsStringSync('{{{ не json');
      expect((await SettingsStore(f).load()).minimizeToTray, isTrue);
    });

    test('сохранение и чтение', () async {
      final store = SettingsStore(File('${tmp.path}/sub/settings.json'));
      await store.save(const AppSettings(
          autostart: true, minimizeToTray: false, trayHintShown: true, quickCategories: ['temp']));
      final s = await store.load();
      expect(s.autostart, isTrue);
      expect(s.minimizeToTray, isFalse);
      expect(s.trayHintShown, isTrue);
      expect(s.quickCategories, ['temp']);
    });
  });

  group('выбор категорий быстрой очистки', () {
    test('браузер запущен: кэш браузеров пропускается', () {
      final r = pickQuickCategories(['temp', 'browsers', 'logs'], browserRunning: true);
      expect(r.ids, [CategoryId.temp, CategoryId.logs]);
      expect(r.skippedBrowsers, isTrue);
    });
    test('браузер не запущен: кэш остаётся', () {
      final r = pickQuickCategories(['temp', 'browsers'], browserRunning: false);
      expect(r.ids, [CategoryId.temp, CategoryId.browsers]);
      expect(r.skippedBrowsers, isFalse);
    });
    test('Загрузки, Большие файлы и неизвестное не попадают', () {
      final r = pickQuickCategories(['downloads', 'big', 'xyz', 'temp', 'temp'],
          browserRunning: false);
      expect(r.ids, [CategoryId.temp]);
    });
  });

  group('автозапуск (фейк реестра)', () {
    const runKey = r'hkcu\software\microsoft\windows\currentversion\run';

    test('включение пишет только своё значение, выключение удаляет только его', () async {
      final p = FakePlatform();
      p.regStrings[runKey] = {'Other': r'C:\Other.exe'};
      final c = _make(p, tmp.path);
      await c.init();
      expect(c.autostartOn, isFalse);
      expect(await c.setAutostart(true), isTrue);
      expect(p.regStrings[runKey], {
        'Other': r'C:\Other.exe',
        'ChistoDisk': r'"C:\Apps\ChistoDisk\chistka_pk.exe" --tray',
      });
      expect(c.autostartOn, isTrue);
      expect(await c.setAutostart(false), isTrue);
      expect(p.regStrings[runKey], {'Other': r'C:\Other.exe'});
      final saved = jsonDecode(File('${tmp.path}/settings.json').readAsStringSync()) as Map;
      expect(saved['autostart'], isFalse);
    });

    test('при запуске состояние берётся из реестра', () async {
      final p = FakePlatform();
      p.regStrings[runKey] = {'ChistoDisk': 'x'};
      final c = _make(p, tmp.path);
      await c.init();
      expect(c.autostartOn, isTrue);
    });
  });

  group('быстрая очистка', () {
    test('нет сохранённого выбора: ничего не чистит, подсказка', () async {
      final p = FakePlatform();
      final c = _make(p, tmp.path);
      await c.init();
      final msg = await c.quickClean();
      expect(msg, contains('Сначала'));
      expect(p.binEmptied, isFalse);
    });

    test('чистит выбранное, кэш браузеров при запущенном браузере пропускает', () async {
      File('${tmp.path}/settings.json').writeAsStringSync(jsonEncode({
        'quickCategories': ['recycle', 'browsers', 'downloads'],
      }));
      final p = FakePlatform()..browsers = ['Chrome'];
      final c = _make(p, tmp.path);
      await c.init();
      final msg = await c.quickClean();
      expect(p.binEmptied, isTrue);
      expect(msg, startsWith('Освобождено'));
      expect(msg, contains('браузер'));
      expect(p.notifications.single, startsWith('ЧистоДиск|Освобождено'));
      expect(p.moved, isEmpty); // Загрузки не трогаем
    });

    test('обычная очистка запоминает выбор', () async {
      final p = FakePlatform();
      final c = _make(p, tmp.path);
      await c.init();
      await c.analyze();
      await c.clean();
      expect(c.settings.quickCategories, contains('recycle'));
      final saved = jsonDecode(File('${tmp.path}/settings.json').readAsStringSync()) as Map;
      expect(saved['quickCategories'], contains('recycle'));
    });
  });
}
