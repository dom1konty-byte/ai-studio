import 'dart:io';

import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/leftovers.dart';
import 'package:chistka_pk/core/programs.dart';
import 'package:chistka_pk/platform/platform_api.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

const _uninst = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall';

RawUninstall _entry(String key, {String hive = 'HKCU', String? uninstall}) => RawUninstall(
      hive,
      hive == 'HKCU'
          ? '$_uninst\\$key'
          : r'HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\' + key,
      {
        'DisplayName': 'Foo Editor',
        'Publisher': 'Acme',
        'UninstallString': uninstall ?? r'"C:\Program Files\Foo\unins000.exe" /SILENT',
      },
    );

void main() {
  late Directory tmp;
  late FakePlatform platform;
  late AppController c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chisto_prog');
    platform = FakePlatform();
    c = AppController(
      platform: platform,
      env: const Env({'LOCALAPPDATA': r'C:\Users\X\AppData\Local', 'APPDATA': r'C:\Users\X\AppData\Roaming'}),
      dataDir: tmp.path,
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
      listDir: (dir) async => const [],
      sizeOf: (p, d) async => 0,
      leftoverGuard: (p, r, d) => null,
      fileExists: (p) => true,
      uninstallPollInterval: const Duration(milliseconds: 1),
      uninstallTimeout: const Duration(milliseconds: 200),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('loadPrograms: список из платформы, системные скрыты', () async {
    platform.uninstallEntries = [
      _entry('a'),
      RawUninstall('HKLM', r'HKLM\X\b', {'DisplayName': 'Sys', 'SystemComponent': '1'}),
    ];
    await c.loadPrograms();
    expect(c.programsState, LoadState.loaded);
    expect(c.programs.map((p) => p.name), ['Foo Editor']);
  });

  test('uninstall: запускает разобранную команду; запись осталась — остатки не ищем', () async {
    platform.uninstallEntries = [_entry('a')];
    await c.loadPrograms();
    await c.uninstall(c.programs.single);
    expect(platform.uninstallCalls, [r'C:\Program Files\Foo\unins000.exe|/SILENT']);
    expect(c.leftoverProgram, isNull);
    expect(c.programMessage, contains('всё ещё в списке'));
    expect(c.programMessage, contains('Проверить и найти остатки'));
    expect(c.recheckProgram, isNotNull);
    expect(c.uninstallBusy, isFalse);
    expect(c.uninstallWaiting, isFalse);
  });

  test('uninstall: запись исчезла — открывается экран остатков', () async {
    platform.uninstallEntries = [
      _entry('a'),
      RawUninstall('HKCU', '$_uninst\\keep', {'DisplayName': 'Keep'}),
    ];
    await c.loadPrograms();
    final prog = c.programs.firstWhere((p) => p.name == 'Foo Editor');
    platform.onUninstall = () => platform.uninstallEntries = [platform.uninstallEntries.last];
    await c.uninstall(prog);
    expect(c.leftoverProgram, same(prog));
    expect(c.leftoverState, LoadState.loaded);
    expect(c.programs.map((p) => p.name), ['Keep']);
  });

  test('uninstall: отмена UAC — остатки не ищем', () async {
    platform.uninstallEntries = [_entry('a')];
    await c.loadPrograms();
    platform.uninstallResult = const UninstallRun(started: false, cancelled: true);
    await c.uninstall(c.programs.single);
    expect(c.leftoverProgram, isNull);
    expect(c.programMessage, contains('отменено'));
  });

  test('uninstall: нет UninstallString — ничего не запускается', () async {
    platform.uninstallEntries = [_entry('a', uninstall: '')];
    await c.loadPrograms();
    await c.uninstall(c.programs.single);
    expect(platform.uninstallCalls, isEmpty);
    expect(c.programMessage, contains('Программа удаления не найдена'));
    expect(c.forceOffer, isNotNull);
  });

  test('принудительное удаление HKCU: программа удаления не запускается, запись — с копией', () async {
    platform.uninstallEntries = [_entry('a')];
    await c.loadPrograms();
    await c.forceRemove(c.programs.single);
    expect(platform.uninstallCalls, isEmpty);
    final entry = c.leftovers.firstWhere((l) => l.isUninstallEntry);
    expect(c.leftoverSelected, contains(entry));
    await c.deleteLeftovers();
    expect(platform.callOrder, ['export $_uninst\\a', 'delete $_uninst\\a']);
    expect(c.leftovers.any((l) => l.isUninstallEntry), isFalse);
    expect(File('${tmp.path}${Platform.pathSeparator}log.txt').readAsStringSync(), contains('a'));
  });

  test('принудительное удаление HKLM: только показ, не отмечено, реестр не трогается', () async {
    platform.uninstallEntries = [_entry('a', hive: 'HKLM')];
    await c.loadPrograms();
    await c.forceRemove(c.programs.single);
    final entry = c.leftovers.firstWhere((l) => l.isUninstallEntry);
    expect(entry.deletable, isFalse);
    expect(c.leftoverSelected, isEmpty);
    c.toggleLeftover(entry, true);
    expect(c.leftoverSelected, isEmpty);
    await c.deleteLeftovers();
    expect(platform.callOrder, isEmpty);
  });

  test('экспорт не удался — запись Uninstall остаётся', () async {
    platform.uninstallEntries = [_entry('a')];
    platform.exportOk = false;
    await c.loadPrograms();
    await c.forceRemove(c.programs.single);
    await c.deleteLeftovers();
    expect(platform.deleted, isEmpty);
    expect(c.leftovers.any((l) => l.isUninstallEntry), isTrue);
  });

  test('uninstall: файл программы удаления не найден — не запускаем, предлагаем принудительное', () async {
    final c2 = AppController(
      platform: platform,
      env: const Env({'LOCALAPPDATA': r'C:\Users\X\AppData\Local'}),
      dataDir: tmp.path,
      listDir: (dir) async => const [],
      sizeOf: (p, d) async => 0,
      leftoverGuard: (p, r, d) => null,
      fileExists: (p) => false,
    );
    platform.uninstallEntries = [_entry('a')];
    await c2.loadPrograms();
    await c2.uninstall(c2.programs.single);
    expect(platform.uninstallCalls, isEmpty);
    expect(c2.forceOffer, isNotNull);
  });

  test('uninstall: запись исчезает позже — ждём опросом, затем остатки', () async {
    platform.uninstallEntries = [_entry('a'), RawUninstall('HKCU', '$_uninst\\keep', {'DisplayName': 'Keep'})];
    await c.loadPrograms();
    final prog = c.programs.firstWhere((p) => p.name == 'Foo Editor');
    var reads = 0;
    platform.onRead = () {
      if (++reads == 4) platform.uninstallEntries = [platform.uninstallEntries.last];
    };
    await c.uninstall(prog);
    expect(reads, greaterThanOrEqualTo(4));
    expect(c.leftoverProgram, same(prog));
  });

  test('uninstall: ненулевой код выхода попадает в сообщение', () async {
    platform.uninstallEntries = [_entry('a')];
    await c.loadPrograms();
    platform.uninstallResult = const UninstallRun(started: true, exitCode: 5);
    await c.uninstall(c.programs.single);
    expect(c.programMessage, contains('кодом 5'));
  });

  test('uninstall: отмена ожидания, затем «Проверить и найти остатки»', () async {
    final slow = AppController(
      platform: platform,
      env: const Env({'LOCALAPPDATA': r'C:\Users\X\AppData\Local'}),
      dataDir: tmp.path,
      listDir: (dir) async => const [],
      sizeOf: (p, d) async => 0,
      leftoverGuard: (p, r, d) => null,
      fileExists: (p) => true,
      uninstallPollInterval: const Duration(seconds: 30),
      uninstallTimeout: const Duration(minutes: 5),
    );
    platform.uninstallEntries = [_entry('a'), RawUninstall('HKCU', '$_uninst\\keep', {'DisplayName': 'Keep'})];
    await slow.loadPrograms();
    final prog = slow.programs.firstWhere((p) => p.name == 'Foo Editor');
    final fut = slow.uninstall(prog);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(slow.uninstallWaiting, isTrue);
    slow.cancelUninstallWait();
    await fut;
    expect(slow.recheckProgram, same(prog));
    expect(slow.leftoverProgram, isNull);
    // пользователь дождался окончания удаления
    platform.uninstallEntries = [platform.uninstallEntries.last];
    await slow.recheckAndFindLeftovers();
    expect(slow.leftoverProgram, same(prog));
  });

  test('closeLeftovers возвращает к списку', () async {
    platform.uninstallEntries = [_entry('a')];
    await c.loadPrograms();
    await c.forceRemove(c.programs.single);
    c.closeLeftovers();
    expect(c.leftoverProgram, isNull);
    expect(c.programsState, LoadState.idle);
  });

  test('isUserHive', () {
    expect(buildPrograms([_entry('a')]).single.isUserHive, isTrue);
    expect(buildPrograms([_entry('a', hive: 'HKLM')]).single.isUserHive, isFalse);
    expect(LeftoverKind.values, hasLength(3));
  });
}
