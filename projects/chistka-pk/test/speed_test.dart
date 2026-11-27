import 'dart:async';
import 'dart:io';

import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/speed.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:chistka_pk/ui/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_platform.dart';

class FakeNet implements SpeedNetwork {
  FakeNet({this.fail});
  final SpeedException? fail;

  @override
  Future<double> pingOnce(SpeedCancel cancel) async {
    if (fail != null) throw fail!;
    return 12;
  }

  @override
  Stream<int> download(Duration limit, SpeedCancel cancel) async* {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      yield 1000000;
    }
  }

  @override
  Stream<int> upload(Duration limit, SpeedCancel cancel) => download(limit, cancel);
}

SpeedResult _r(int i) => SpeedResult(
    time: DateTime(2026, 1, 1, 0, i), pingMs: 10, jitterMs: 1, downMbps: i.toDouble(), upMbps: 2);

void main() {
  test('расчёты', () {
    expect(mbps(1250000, 1), 10);
    expect(mbps(100, 0), 0);
    expect(median([3, 1, 2]), 2);
    expect(median([4, 1, 2, 3]), 2.5);
    expect(median([]), 0);
    expect(jitter([10, 12, 10]), 2);
    expect(jitter([5]), 0);
    expect(gaugeFraction(0), 0);
    expect(gaugeFraction(5000), 1);
    expect(gaugeFraction(100), inInclusiveRange(0.6, 0.7));
  });

  test('история: 10 последних, новая первой', () {
    var h = <SpeedResult>[];
    for (var i = 0; i < 12; i++) {
      h = addToHistory(h, _r(i));
    }
    expect(h.length, 10);
    expect(h.first.downMbps, 11);
    expect(h.last.downMbps, 2);
  });

  test('история: сохранение и чтение', () async {
    final dir = Directory.systemTemp.createTempSync('speed');
    addTearDown(() => dir.deleteSync(recursive: true));
    final s = SpeedHistoryStore(File('${dir.path}/speed.json'));
    expect(await s.load(), isEmpty);
    await s.save([_r(1), _r(2)]);
    final l = await s.load();
    expect(l.length, 2);
    expect(l.first.downMbps, 1);
    File('${dir.path}/speed.json').writeAsStringSync('мусор');
    expect(await s.load(), isEmpty);
  });

  test('SpeedTester: фазы и результат', () async {
    final t = SpeedTester(FakeNet(), pingCount: 3, phaseDuration: const Duration(seconds: 1));
    final ev = await t.run(SpeedCancel()).toList();
    expect(ev.map((e) => e.phase).toSet(),
        {SpeedPhase.ping, SpeedPhase.download, SpeedPhase.upload, SpeedPhase.done});
    final r = ev.last.result!;
    expect(r.pingMs, 12);
    expect(r.downMbps, greaterThan(0));
    expect(r.upMbps, greaterThan(0));
  });

  test('SpeedTester: ошибка сети', () async {
    final t = SpeedTester(FakeNet(fail: const SpeedException()), pingCount: 2);
    expect(t.run(SpeedCancel()).toList(), throwsA(isA<SpeedException>()));
  });

  test('SpeedTester: отмена закрывает поток без результата', () async {
    final c = SpeedCancel();
    final t = SpeedTester(FakeNet(), pingCount: 3, phaseDuration: const Duration(seconds: 1));
    final ev = <SpeedEvent>[];
    final done = t.run(c).listen((e) {
      ev.add(e);
      if (e.phase == SpeedPhase.download) c.cancel();
    }).asFuture<void>();
    await done;
    expect(ev.any((e) => e.phase == SpeedPhase.done), isFalse);
  });

  test('Стоп во время пинга -> повторный старт работает', () async {
    HttpOverrides.global = null; // настоящая сеть вместо заглушки flutter_test
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var n = 0;
    server.listen((r) async {
      n++;
      if (n == 1) await Future<void>.delayed(const Duration(seconds: 5)); // зависший пинг
      try {
        r.response.statusCode = 200;
        await r.response.close();
      } catch (_) {}
    });
    final net = CloudflareSpeedNetwork(host: 'http://127.0.0.1:${server.port}');
    final c1 = SpeedCancel();
    final first = net.pingOnce(c1);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    c1.cancel();
    await first; // при отмене возвращает 0, без исключения
    final c2 = SpeedCancel();
    final ms = await net.pingOnce(c2);
    expect(ms, greaterThan(0));
    c2.cancel();
  });

  testWidgets('«Начать» запускает тест и показывает итог', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('speedui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = AppController(
      platform: FakePlatform(),
      env: const Env({}),
      dataDir: dir.path,
      speedNetwork: FakeNet(),
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
    );
    await tester.pumpWidget(ChistoApp(controller: c));
    await tester.pump();
    await tester.tap(find.text('Интернет'));
    await tester.pumpAndSettle();
    expect(find.text('Замеров пока нет'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('speed-button')));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Готово'), findsOneWidget);
    expect(find.byKey(const Key('speed-ping')), findsOneWidget);
    expect(find.text('12.0'), findsWidgets);
    expect(find.text('Замеров пока нет'), findsNothing);
  });
}
