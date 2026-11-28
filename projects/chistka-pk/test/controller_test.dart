import 'dart:io';

import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

AppController make(FakePlatform p, Env env, {String? dataDir}) => AppController(
      platform: p,
      env: env,
      dataDir: dataDir,
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
    );

void main() {
  test('нет LOCALAPPDATA и APPDATA: журнал не пишется в systemTemp, очистка не запускается', () async {
    final p = FakePlatform();
    final c = make(p, const Env({}));
    expect(c.logFile, isNull);
    await c.init();
    await c.analyze();
    expect(c.canClean, isTrue);
    await c.clean();
    expect(p.binEmptied, isFalse);
    expect(c.failedAll, isTrue);
    expect(c.errorMessage, isNotNull);
  });

  test('LOCALAPPDATA пуста, есть APPDATA: журнал в APPDATA\\ChistoDisk', () {
    final c = make(FakePlatform(), const Env({'APPDATA': r'C:\Users\X\AppData\Roaming'}));
    expect(c.logFile!.path, startsWith(r'C:\Users\X\AppData\Roaming\ChistoDisk'));
  });

  test('исключение посреди очистки: итог сохранён, статистика обновлена', () async {
    final dir = Directory.systemTemp.createTempSync('chisto_ctl');
    addTearDown(() => dir.deleteSync(recursive: true));
    final p = FakePlatform();
    final c = make(p, const Env({}), dataDir: dir.path);
    await c.init();
    await c.analyze();
    p.diskCalls = 0;
    p.throwOnSecondDisk = true; // диск читается до и после очистки: второй вызов падает
    await c.clean();
    expect(c.failedAll, isTrue);
    expect(c.summary, isNotNull);
    expect(c.summary!.freedBytes, 1000);
    expect(c.totalFreedEver, 1000);
  });

  test('userRoots: небезопасные и внешние корни (OneDrive) отбрасываются', () {
    final c = make(
      FakePlatform(),
      const Env({
        'USERPROFILE': r'C:\Users\X',
        'OneDrive': r'\\server\share',
      }),
    );
    expect(c.userRoots, [
      r'C:\Users\X\Downloads',
      r'C:\Users\X\Documents',
      r'C:\Users\X\Desktop',
    ]);
    final d = make(
      FakePlatform(),
      const Env({'USERPROFILE': r'C:\Users\X', 'OneDrive': r'D:\Other'}),
    );
    expect(d.userRoots.any((r) => r.startsWith(r'D:')), isFalse);
    final ok = make(
      FakePlatform(),
      const Env({'USERPROFILE': r'C:\Users\X', 'OneDrive': r'C:\Users\X\OneDrive'}),
    );
    expect(ok.userRoots, contains(r'C:\Users\X\OneDrive\Desktop'));
  });
}
