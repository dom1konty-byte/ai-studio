import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/update.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:chistka_pk/state/update_network.dart';
import 'package:chistka_pk/ui/app.dart';
import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

Map<String, Object?> rel(String tag, {bool draft = false, bool pre = false, bool assets = true}) => {
      'tag_name': tag,
      'draft': draft,
      'prerelease': pre,
      'assets': assets
          ? [
              {
                'name': 'ChistoDisk-setup.exe',
                'browser_download_url':
                    'https://github.com/dom1konty-byte/ai-studio/releases/download/$tag/ChistoDisk-setup.exe'
              },
              {
                'name': 'ChistoDisk-setup.exe.sha256',
                'browser_download_url':
                    'https://github.com/dom1konty-byte/ai-studio/releases/download/$tag/ChistoDisk-setup.exe.sha256'
              },
            ]
          : [],
    };

class FakeNet implements UpdateNetwork {
  FakeNet(this.latest, {this.payload = const [0x4D, 0x5A, 3], this.sum, this.gate});
  UpdateInfo? latest;
  bool fail = false;
  int calls = 0;
  final List<int> payload;
  String? sum;
  Completer<void>? gate;

  @override
  Future<UpdateInfo?> fetchLatest() async {
    calls++;
    if (fail) throw const SocketException('нет сети');
    return latest;
  }

  @override
  Future<String> fetchText(Uri url) async => '${sum ?? sha256.convert(payload)}  ChistoDisk-setup.exe\n';

  @override
  Future<void> download(Uri url, File dest, void Function(int, int) onProgress) async {
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(payload);
    onProgress(1, payload.length);
    if (gate != null) await gate!.future;
    onProgress(payload.length, payload.length);
  }
}

UpdateInfo info(String v, {String? digest}) => UpdateInfo(
      installerDigest: digest,
      version: v,
      installerUrl: Uri.parse('https://github.com/x/ChistoDisk-setup.exe'),
      checksumUrl: Uri.parse('https://github.com/x/ChistoDisk-setup.exe.sha256'),
    );

void main() {
  group('версии', () {
    test('semver сравнивается числами', () {
      expect(compareVersions('1.10.0', '1.9.2'), greaterThan(0));
      expect(compareVersions('1.3.0', '1.3.0+5'), 0);
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(isNewerVersion('1.3.1', '1.3.0'), isTrue);
      expect(isNewerVersion('1.3.0', '1.3.0'), isFalse);
      expect(isNewerVersion('abc', '1.0.0'), isFalse);
    });
  });

  group('выбор релиза', () {
    test('берёт самый новый нужный; draft, prerelease и чужие теги отбрасываются', () {
      final r = pickLatestRelease([
        rel('chistka-pk-v1.9.0'),
        rel('chistka-pk-v1.10.0'),
        rel('chistka-pk-v9.0.0', draft: true),
        rel('chistka-pk-v8.0.0', pre: true),
        rel('other-app-v7.0.0'),
        rel('v6.0.0'),
        rel('chistka-pk-v5.0.0', assets: false),
        rel('chistka-pk-vмусор'),
      ]);
      expect(r?.version, '1.10.0');
      expect(r?.installerUrl.path, endsWith('ChistoDisk-setup.exe'));
      expect(r?.checksumUrl.path, endsWith('.sha256'));
    });
    test('нет подходящих или не список: null', () {
      expect(pickLatestRelease([rel('x-v1')]), isNull);
      expect(pickLatestRelease({'a': 1}), isNull);
      expect(pickLatestFromBody('не json'), isNull);
      expect(pickLatestFromBody(jsonEncode([rel('chistka-pk-v2.0.0')]))?.version, '2.0.0');
    });
    test('ассет с небезопасным адресом отбрасывается', () {
      final r = rel('chistka-pk-v2.0.0');
      ((r['assets'] as List)[0] as Map)['browser_download_url'] = 'http://github.com/a.exe';
      expect(pickLatestRelease([r]), isNull);
    });
  });

  test('проверка адреса скачивания', () {
    bool ok(String u) => isSafeDownloadUrl(Uri.parse(u));
    expect(ok('https://github.com/a/b'), isTrue);
    expect(ok('https://objects.githubusercontent.com/x'), isTrue);
    expect(ok('http://github.com/a'), isFalse);
    expect(ok('https://evil.com/github.com'), isFalse);
    expect(ok('https://github.com.evil.com/a'), isFalse);
    expect(ok('https://evilgithubusercontent.com/a'), isFalse);
    expect(ok('ftp://github.com/a'), isFalse);
    expect(ok('https://release-assets.githubusercontent.com/x'), isTrue);
    expect(ok('https://other.githubusercontent.com/x'), isFalse);
    expect(ok('https://raw.githubusercontent.com/x'), isFalse);
  });

  group('безопасность выбора релиза', () {
    test('версия нормализуется, мусор после версии отбрасывает релиз', () {
      expect(normalizeReleaseVersion('1.3'), '1.3.0');
      expect(normalizeReleaseVersion('01.3.0'), '1.3.0');
      expect(normalizeReleaseVersion('1.3.0-beta'), isNull);
      expect(normalizeReleaseVersion('1.3.0+4'), isNull);
      expect(normalizeReleaseVersion('1.3.0/../x'), isNull);
      expect(normalizeReleaseVersion('1.3.0 '), isNull);
      expect(pickLatestRelease([rel('chistka-pk-v2.0.0-evil')]), isNull);
      expect(pickLatestRelease([rel('chistka-pk-v2.0')])?.version, '2.0.0');
    });

    test('адрес ассета обязан быть из релиза этого тега', () {
      final r = rel('chistka-pk-v2.0.0');
      ((r['assets'] as List)[0] as Map)['browser_download_url'] =
          'https://github.com/dom1konty-byte/ai-studio/releases/download/chistka-pk-v1.0.0/ChistoDisk-setup.exe';
      expect(pickLatestRelease([r]), isNull);
      final r2 = rel('chistka-pk-v2.0.0');
      ((r2['assets'] as List)[1] as Map)['browser_download_url'] =
          'https://github.com/evil/repo/releases/download/chistka-pk-v2.0.0/ChistoDisk-setup.exe.sha256';
      expect(pickLatestRelease([r2]), isNull);
      final r3 = rel('chistka-pk-v2.0.0');
      ((r3['assets'] as List)[0] as Map)['browser_download_url'] =
          'https://objects.githubusercontent.com/dom1konty-byte/ai-studio/releases/download/chistka-pk-v2.0.0/ChistoDisk-setup.exe';
      expect(pickLatestRelease([r3]), isNull);
    });

    test('digest: берётся sha256, непонятный — релиз отбрасывается', () {
      final good = rel('chistka-pk-v2.0.0');
      ((good['assets'] as List)[0] as Map)['digest'] = 'sha256:${'AB' * 32}';
      expect(pickLatestRelease([good])?.installerDigest, 'ab' * 32);
      final bad = rel('chistka-pk-v2.0.0');
      ((bad['assets'] as List)[0] as Map)['digest'] = 'md5:123';
      expect(pickLatestRelease([bad]), isNull);
      expect(pickLatestRelease([rel('chistka-pk-v2.0.0')])?.installerDigest, isNull);
    });

    test('MZ и тексты этапов', () {
      expect(looksLikeExe([0x4D, 0x5A, 0]), isTrue);
      expect(looksLikeExe([0x50, 0x4B]), isFalse);
      expect(looksLikeExe([0x4D]), isFalse);
      expect(updateStageText(UpdateStage.downloading, 24537907, 63963136), 'Скачиваю 23,4 из 61,0 МБ');
      expect(updateStageText(UpdateStage.downloading, 5, 0), 'Скачиваю…');
      expect(updateStageText(UpdateStage.verifying, 0, 0), 'Проверяю файл…');
      expect(updateStageText(UpdateStage.launching, 0, 0), 'Запускаю установщик…');
    });
  });

  test('разбор sha256', () {
    final h = 'A' * 64;
    expect(parseSha256('$h  ChistoDisk-setup.exe\n'), 'a' * 64);
    expect(parseSha256('  $h'), 'a' * 64);
    expect(parseSha256('abc'), isNull);
    expect(parseSha256('${'g' * 64}  x'), isNull);
    expect(parseSha256(''), isNull);
  });

  test('раз в сутки', () {
    final now = DateTime(2026, 1, 2, 12);
    expect(isUpdateCheckDue(null, now), isTrue);
    expect(isUpdateCheckDue(now.subtract(const Duration(hours: 23)), now), isFalse);
    expect(isUpdateCheckDue(now.subtract(const Duration(hours: 24)), now), isTrue);
    expect(isUpdateCheckDue(now.add(const Duration(hours: 1)), now), isTrue);
  });

  group('контроллер', () {
    late Directory tmp;
    late DateTime now;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('chisto_upd');
      now = DateTime(2026, 5, 1, 10);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    AppController make(FakeNet net, {List<String>? launched, bool? exited}) => AppController(
          platform: FakePlatform(),
          env: const Env({}),
          dataDir: tmp.path,
          downloadsScan: (_) async => [],
          largeScan: (_, __) async => [],
          updateNetwork: net,
          clock: () => now,
          exitApp: () async => launched?.add('exit'),
          launchInstaller: (exe, args) async => launched?.add('$exe ${args.join(' ')}'),
        );

    test('автопроверка раз в сутки и выключатель', () async {
      final net = FakeNet(info('9.0.0'));
      final c = make(net);
      await c.autoCheckUpdates();
      expect(net.calls, 1);
      expect(c.availableUpdate?.version, '9.0.0');
      await c.autoCheckUpdates();
      expect(net.calls, 1); // ещё не сутки
      now = now.add(const Duration(hours: 25));
      await c.setAutoUpdate(false);
      await c.autoCheckUpdates();
      expect(net.calls, 1);
      await c.setAutoUpdate(true);
      await c.autoCheckUpdates();
      expect(net.calls, 2);
    });

    test('сеть упала: тихо, отметка не ставится', () async {
      final net = FakeNet(null)..fail = true;
      final c = make(net);
      await c.autoCheckUpdates();
      expect(c.availableUpdate, isNull);
      expect(c.settings.lastUpdateCheck, isNull);
      expect(await c.checkForUpdates(), UpdateCheck.error);
    });

    test('старая или та же версия: обновления нет', () async {
      final c = make(FakeNet(info(appVersion)));
      expect(await c.checkForUpdates(), UpdateCheck.upToDate);
      expect(c.showUpdateBanner, isFalse);
    });

    test('установка: хеш совпал — установщик запущен с флагами и выход', () async {
      final log = <String>[];
      final c = make(FakeNet(info('9.0.0')), launched: log);
      await c.checkForUpdates();
      expect(await c.installUpdate(), isNull);
      expect(log.first, contains('ChistoDisk-setup-9.0.0.exe /SP- /SILENT /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS'));
      expect(log.last, 'exit');
    });

    test('установка: хеш не совпал — файл удалён, установщик не запущен', () async {
      final log = <String>[];
      final c = make(FakeNet(info('9.0.0'), sum: '0' * 64), launched: log);
      await c.checkForUpdates();
      expect(await c.installUpdate(), 'Файл повреждён, попробуйте позже.');
      expect(log, isEmpty);
      expect(Directory('${tmp.path}/update').listSync(), isEmpty);
    });
  });

  group('установка: защита', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('chisto_upd2'));
    tearDown(() => tmp.deleteSync(recursive: true));
    AppController make(FakeNet net, {List<String>? launched}) => AppController(
          platform: FakePlatform(),
          env: const Env({}),
          dataDir: '${tmp.path}/data',
          downloadsScan: (_) async => [],
          largeScan: (_, __) async => [],
          updateNetwork: net,
          exitApp: () async => launched?.add('exit'),
          launchInstaller: (exe, args) async => launched?.add(exe),
        );

    test('не MZ — файл удалён, установщик не запущен', () async {
      final log = <String>[];
      final c = make(FakeNet(info('9.0.0'), payload: [1, 2, 3]), launched: log);
      await c.checkForUpdates();
      expect(await c.installUpdate(), 'Файл повреждён, попробуйте позже.');
      expect(log, isEmpty);
      expect(Directory('${tmp.path}/data/update').listSync(), isEmpty);
    });

    test('digest не совпал с .sha256 — отказ до скачивания', () async {
      final log = <String>[];
      final c = make(FakeNet(info('9.0.0', digest: 'f' * 64)), launched: log);
      await c.checkForUpdates();
      expect(await c.installUpdate(), 'Файл повреждён, попробуйте позже.');
      expect(log, isEmpty);
    });

    test('digest совпал — установка идёт', () async {
      final log = <String>[];
      final payload = [0x4D, 0x5A, 3];
      final c = make(FakeNet(info('9.0.0', digest: sha256.convert(payload).toString()), payload: payload),
          launched: log);
      await c.checkForUpdates();
      expect(await c.installUpdate(), isNull);
      expect(log.last, 'exit');
    });

    test('занято: операция идёт — обновление не стартует', () async {
      final c = make(FakeNet(info('9.0.0')));
      await c.checkForUpdates();
      c.uninstallBusy = true;
      expect(await c.installUpdate(), 'Дождитесь окончания операции.');
      c.uninstallBusy = false;
      c.bigState = LoadState.loading;
      expect(await c.installUpdate(), 'Дождитесь окончания операции.');
    });

    test('отмена: скачивание прервано, частичный файл удалён', () async {
      final log = <String>[];
      final gate = Completer<void>();
      final c = make(FakeNet(info('9.0.0'), gate: gate), launched: log);
      await c.checkForUpdates();
      final f = c.installUpdate();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.updateInstalling, isTrue);
      expect(c.updateReceived, 1);
      c.cancelUpdate();
      expect(await f, '');
      gate.complete();
      expect(log, isEmpty);
      expect(Directory('${tmp.path}/data/update').listSync(), isEmpty);
      expect(c.updateInstalling, isFalse);
    });
  });

  testWidgets('баннер появляется при новой версии, «Позже» скрывает', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tmp = Directory.systemTemp.createTempSync('chisto_upd_ui');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final c = AppController(
      platform: FakePlatform(),
      env: const Env({}),
      dataDir: tmp.path,
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
      updateNetwork: FakeNet(info('9.9.9')),
    );
    await tester.pumpWidget(ChistoApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update-banner')), findsNothing);
    await tester.runAsync(c.checkForUpdates);
    await tester.pumpAndSettle();
    expect(find.text('Доступна версия 9.9.9'), findsOneWidget);
    expect(find.text('Обновить'), findsOneWidget);
    await tester.tap(find.byKey(const Key('update-later')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update-banner')), findsNothing);
  });
}
