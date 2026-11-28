import 'dart:io';

import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/procs.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:chistka_pk/state/computer_service.dart';
import 'package:chistka_pk/ui/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_platform.dart';

const _disk = '[{"FriendlyName":"Samsung SSD","MediaType":"SSD","HealthStatus":"Healthy",'
    '"Size":512110190592,"DeviceId":"0","IsSystem":true,"Temperature":38,"Wear":4,'
    '"PowerOnHours":1234,"ReadErrorsTotal":0}]';

const _battery = '<BatteryReport><Batteries><Battery><DesignCapacity>50000</DesignCapacity>'
    '<FullChargeCapacity>43000</FullChargeCapacity><CycleCount>187</CycleCount>'
    '</Battery></Batteries></BatteryReport>';

SysSample _sample(int wall, int cpuChrome, {int idle = 0, int kernel = 0, int user = 0}) => SysSample(
      wallMs: wall,
      idle: idle,
      kernel: kernel,
      user: user,
      memLoadPercent: 61,
      totalPhys: 16 << 30,
      availPhys: 6 << 30,
      cores: 4,
      procs: [
        const RawProc(pid: 4, name: 'System', memory: 1000),
        RawProc(pid: 10, name: 'chrome.exe', cpuTime: cpuChrome, memory: 300 << 20),
        RawProc(pid: 11, name: 'chrome.exe', cpuTime: cpuChrome, memory: 200 << 20),
      ],
    );

void main() {
  late Directory tmp;
  late FakePlatform fp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chisto_comp');
    fp = FakePlatform()
      ..utf8Output = _disk
      ..samples = [_sample(0, 0), _sample(2000, 10000000, idle: 600, kernel: 1000, user: 0)];
    fp.onTool = (call) {
      if (call.contains('/batteryreport')) {
        File(call.split('/output ').last).writeAsStringSync(_battery);
      }
    };
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  AppController make({bool battery = true}) => AppController(
        platform: fp,
        env: Env({
          'USERPROFILE': tmp.path,
          if (battery) 'LOCALAPPDATA': '${tmp.path}/local',
        }),
        dataDir: '${tmp.path}/data',
        downloadsScan: (_) async => [],
        largeScan: (_, __) async => [],
      );

  Future<void> open(WidgetTester tester, AppController c) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChistoApp(controller: c));
    await tester.pump();
    c.go(Section.computer);
    for (var i = 0; i < 100; i++) {
      final s = c.computer;
      if (s.healthLoad != ComputerLoad.loading &&
          s.healthLoad != ComputerLoad.idle &&
          s.batteryLoad != ComputerLoad.loading &&
          s.batteryLoad != ComputerLoad.idle) {
        break;
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('плитки показывают итог; батареи нет — плитки нет', (tester) async {
    final c = make(battery: false);
    await open(tester, c);
    expect(find.text('SSD · Исправен · 38°'), findsOneWidget);
    expect(find.textContaining('ЦП 70 % · Память 61 %'), findsNothing); // сначала один снимок
    expect(find.byKey(const Key('tile-battery')), findsNothing);
    expect(fp.utf8Calls.single, contains('powershell.exe'));
    expect(fp.utf8Timeout, const Duration(seconds: 20));
    await close(tester);
  });

  testWidgets('ЦП и память обновляются раз в 2 с; фон останавливает опрос', (tester) async {
    final c = make();
    await open(tester, c);
    expect(c.computer.polling, isTrue);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('ЦП 40 % · Память 61 %'), findsOneWidget);
    expect(find.text('Износ 14 %'), findsOneWidget);
    expect(fp.utf8Calls.where((x) => x.contains('powershell')), hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    final n = fp.sampleCalls;
    await tester.pump(const Duration(seconds: 6));
    expect(fp.sampleCalls, n);
    expect(c.computer.polling, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(c.computer.polling, isTrue);
    await close(tester);
    expect(c.computer.polling, isFalse);
  });

  testWidgets('здоровье: подробности поверх, Назад закрывает', (tester) async {
    final c = make();
    await open(tester, c);
    await tester.tap(find.byKey(const Key('tile-health')));
    await tester.pumpAndSettle();
    expect(c.layer, Layer.health);
    expect(find.byKey(const Key('disk-card')), findsOneWidget);
    expect(find.text('Исправен'), findsOneWidget);
    expect(find.text('Износ 4 %'), findsOneWidget);
    expect(find.text('38 °C'), findsNothing);
    expect(find.text('Температура: 38 °C'), findsOneWidget);
    await tester.tap(find.byKey(const Key('layer-back')));
    await tester.pumpAndSettle();
    expect(c.layer, Layer.none);
    await close(tester);
  });

  testWidgets('здоровье без температуры: нужен режим администратора', (tester) async {
    fp.utf8Output = '{"FriendlyName":"X","MediaType":"SSD","HealthStatus":"Healthy"}';
    final c = make();
    await open(tester, c);
    await tester.tap(find.text('Открыть').first);
    await tester.pumpAndSettle();
    expect(find.text('Нужен режим администратора'), findsOneWidget);
    expect(find.byKey(const Key('admin-enable')), findsOneWidget);
    await close(tester);
  });

  testWidgets('здоровье без данных при включённом админе: «Нет данных», без кнопки', (tester) async {
    fp.utf8Output = '{"FriendlyName":"X","MediaType":"SSD","HealthStatus":"Healthy"}';
    final c = make();
    await c.init();
    c.adminMode = true;
    await open(tester, c);
    await tester.tap(find.text('Открыть').first);
    await tester.pumpAndSettle();
    expect(find.text('Нет данных'), findsOneWidget);
    expect(find.text('Нужен режим администратора'), findsNothing);
    expect(find.byKey(const Key('admin-enable')), findsNothing);
    await close(tester);
  });

  testWidgets('здоровье: сбой запроса — «Не удалось», повтор', (tester) async {
    fp.utf8Output = null;
    final c = make();
    await open(tester, c);
    expect(find.text('Не удалось'), findsOneWidget);
    fp.utf8Output = _disk;
    await tester.tap(find.text('Повторить'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('SSD · Исправен · 38°'), findsOneWidget);
    await close(tester);
  });

  testWidgets('батарея: кольцо и ёмкости; файл удалён', (tester) async {
    final c = make();
    await open(tester, c);
    await tester.tap(find.byKey(const Key('tile-battery')));
    await tester.pumpAndSettle();
    expect(c.layer, Layer.battery);
    expect(find.byKey(const Key('wear-ring')), findsOneWidget);
    expect(find.text('Новая ёмкость 50\u00A0000 мВт·ч'), findsOneWidget);
    expect(find.text('Сейчас 43\u00A0000 мВт·ч'), findsOneWidget);
    expect(find.text('Циклов зарядки: 187'), findsOneWidget);
    expect(File('${tmp.path}/local/ChistoDisk/tmp/battery.xml').existsSync(), isFalse);
    expect(fp.utf8Calls.any((x) => x.contains('powercfg.exe /batteryreport /xml /output')), isTrue);
    expect(fp.utf8Timeout, const Duration(seconds: 30));
    await close(tester);
  });

  testWidgets('процессы: шкалы, таблица, системный не завершается, Chrome группой', (tester) async {
    final c = make();
    await open(tester, c);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tile-procs')));
    await tester.pumpAndSettle();
    expect(c.layer, Layer.procs);
    expect(find.text('Процессор 40 %'), findsOneWidget);
    expect(find.text('Память 10,0 из 16,0 ГБ'), findsOneWidget);
    expect(find.text('chrome.exe (2)'), findsOneWidget);
    // у System кнопка неактивна
    final sys = find.ancestor(of: find.text('System'), matching: find.byType(DataRow));
    expect(sys, findsNothing); // DataRow не предок виджетов — проверяем через кнопки
    expect(find.byKey(const Key('kill-system')), findsNothing);
    expect(find.byKey(const Key('kill-chrome.exe')), findsOneWidget);
    // отмена
    await tester.tap(find.byKey(const Key('kill-chrome.exe')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Завершить «chrome.exe»?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(fp.killed, isEmpty);
    // подтверждение — все процессы группы
    await tester.tap(find.byKey(const Key('kill-chrome.exe')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kill-confirm')));
    await tester.pumpAndSettle();
    expect(fp.killed, [10, 11]);
    await close(tester);
  });

  testWidgets('завершение: ошибка доступа — «Нужен режим администратора»', (tester) async {
    fp.killResult = KillResult.denied;
    final c = make();
    await open(tester, c);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    c.openComputerLayer(Layer.procs);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kill-chrome.exe')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kill-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Нужен режим администратора'), findsOneWidget);
    await close(tester);
  });

  test('terminateGroup не трогает защищённое и подменённое имя', () async {
    final c = make();
    final s = c.computer;
    await s.tick();
    await s.tick();
    final sys = s.groups.firstWhere((g) => g.name == 'System');
    expect(sys.isProtected, isTrue);
    expect(await s.terminateGroup(sys), KillResult.failed);
    expect(fp.killed, isEmpty);
    // PID 10 «стал» другим процессом — его не убиваем
    final chrome = s.groups.firstWhere((g) => g.name == 'chrome.exe');
    fp.samples = [
      SysSample(
        wallMs: 9,
        idle: 0,
        kernel: 0,
        user: 0,
        memLoadPercent: 1,
        totalPhys: 1,
        availPhys: 1,
        cores: 4,
        procs: const [
          RawProc(pid: 10, name: 'other.exe'),
          RawProc(pid: 11, name: 'chrome.exe'),
        ],
      ),
    ];
    fp.sampleCalls = 0;
    await s.terminateGroup(chrome);
    expect(fp.killed, [11]);
    s.dispose();
  });
}
