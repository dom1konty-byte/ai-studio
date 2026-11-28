import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pult_studii/app/app.dart';
import 'package:pult_studii/models/quick_replies.dart';
import 'package:pult_studii/services/process_runner.dart';
import 'package:pult_studii/services/readme_parser.dart';
import 'package:pult_studii/services/site_preview.dart';
import 'package:pult_studii/services/voice_input.dart';
import 'package:pult_studii/state/app_controller.dart';

import 'fakes.dart';

class FakeVoice implements VoiceInput {
  FakeVoice({this.result = true});

  final bool result;
  int calls = 0;

  @override
  Future<bool> trigger() async {
    calls++;
    return result;
  }
}

ProcResult _handler(String exe, List<String> args, String? cwd) {
  final k = args.join(' ');
  if (args.length == 1 && args.first == '--version') {
    return ProcResult(0, '$exe version 1.0\n');
  }
  if (k == 'auth status') return const ProcResult(0);
  if (k == 'remote get-url origin') {
    return const ProcResult(0, 'https://github.com/dom/ai-studio.git\n');
  }
  if (k.startsWith('branch -r')) {
    return const ProcResult(0, 'origin/main\norigin/alpha\norigin/beta\n');
  }
  if (k == 'show origin/main:projects/README.md') {
    return const ProcResult(0, sampleReadme);
  }
  if (k.startsWith('show ')) return const ProcResult(128, '', 'fatal');
  if (k == 'branch --show-current') return const ProcResult(0, 'alpha\n');
  if (k.startsWith('rev-parse --verify --quiet origin/')) {
    return const ProcResult(0, 'fff0000\n');
  }
  if (k.startsWith('api ') && k.contains('/alpha.yml/')) {
    return const ProcResult(0,
        '{"workflow_runs":[{"event":"push","head_repository":{"full_name":"dom/ai-studio"},"id":7,"status":"completed","conclusion":"success","updated_at":"2999-01-01T00:00:00Z"}]}');
  }
  if (k.startsWith('api ')) return const ProcResult(1, '', 'gh: Not Found (HTTP 404)');
  return const ProcResult(0);
}

Future<void> _settle(WidgetTester t, {int ms = 50}) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(Duration(milliseconds: ms));
  }
}

Future<(AppController, FakeProc)> _start(WidgetTester tester,
    {VoiceInput? voice}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final proc = FakeProc(_handler);
  final controller = AppController(
      proc: proc,
      storage: MemoryStorage(
          state: {'repoPath': 'C:\\ai-studio'}, readme: sampleReadme),
      downloadsDir: 'C:\\Downloads',
      voice: voice,
      autoRefresh: null);
  await tester.pumpWidget(RubkaApp(controller: controller));
  controller.init();
  await _settle(tester);
  return (controller, proc);
}

Future<String> _raw(int port, String request) async {
  final s = await Socket.connect('127.0.0.1', port);
  s.write(request);
  await s.flush();
  final out = StringBuffer();
  await for (final chunk in s.cast<List<int>>().transform(utf8.decoder)) {
    out.write(chunk);
  }
  s.destroy();
  return out.toString();
}

void main() {
  group('адрес сайта', () {
    test('pages.dev и workers.dev в README', () {
      const readme = '# Сайт\n'
          'Репозиторий: https://github.com/dom/ai-studio\n'
          'Опубликован: [тут](https://moy-sait.pages.dev/).\n';
      expect(findSiteUrl([readme, null]), 'https://moy-sait.pages.dev/');
      expect(findSiteUrl(['x https://bot.example.workers.dev, ok']),
          'https://bot.example.workers.dev');
    });

    test('«Сайт:» и «Адрес:», отчёт после README', () {
      expect(findSiteUrl(['пусто', '- Сайт: https://example.com/a.']),
          'https://example.com/a');
      expect(findSiteUrl(['Адрес: https://example.org']),
          'https://example.org');
    });

    test('pages.dev важнее обычного адреса; http и мусор не берём', () {
      expect(
          findSiteUrl([
            'Сайт: https://example.com/',
            'Тут https://x.pages.dev/',
          ]),
          'https://x.pages.dev/');
      expect(findSiteUrl(['Сайт: http://example.com/']), isNull);
      expect(findSiteUrl(['https://github.com/dom/repo']), isNull);
      expect(findSiteUrl(['Сайт: пока нет']), isNull);
      expect(findSiteUrl(const []), isNull);
    });

    test('тип «Сайт» и проверка локального адреса', () {
      expect(isSiteType('Сайт'), isTrue);
      expect(isSiteType('Программа Windows'), isFalse);
      expect(isLocalPreviewUrl('http://127.0.0.1:5000/'), isTrue);
      expect(isLocalPreviewUrl('http://localhost:5000/'), isFalse);
      expect(isLocalPreviewUrl('http://127.0.0.1/'), isFalse);
      expect(isLocalPreviewUrl('http://127.0.0.1.evil.com:5000/'), isFalse);
      expect(isLocalPreviewUrl('http://127.0.0.1:5000/x'), isFalse);
      expect(isLocalPreviewUrl('https://127.0.0.1:5000/'), isFalse);
      expect(isLocalPreviewUrl('http://a@127.0.0.1:5000/'), isFalse);
      expect(isLocalPreviewUrl('http://127.0.0.1:5000/ x'), isFalse);
      expect(isLocalPreviewUrl(null), isFalse);
    });
  });

  group('локальный сервер сайта', () {
    late Directory tmp;
    late Directory site;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('v13-site-');
      site = Directory(p.join(tmp.path, 'dist'))..createSync();
      File(p.join(site.path, 'index.html')).writeAsStringSync('<h1>Привет</h1>');
      File(p.join(site.path, 'style.css')).writeAsStringSync('h1{color:red}');
      File(p.join(tmp.path, 'secret.txt')).writeAsStringSync('секрет');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('поиск папки: dist, нужна сборка, пусто', () async {
      expect((await locateSiteRoot(tmp.path)).path, site.path);
      final empty = Directory(p.join(tmp.path, 'e'))..createSync();
      final r = await locateSiteRoot(empty.path);
      expect(r.path, isNull);
      expect(r.needsBuild, isFalse);
      File(p.join(empty.path, 'package.json')).writeAsStringSync('{}');
      Directory(p.join(empty.path, 'public')).createSync();
      File(p.join(empty.path, 'public', 'index.html')).writeAsStringSync('x');
      final b = await locateSiteRoot(empty.path);
      expect(b.path, isNull);
      expect(b.needsBuild, isTrue);
    });

    test('Content-Type по расширению', () {
      expect(contentTypeFor('a.html'), startsWith('text/html'));
      expect(contentTypeFor('a.CSS'), startsWith('text/css'));
      expect(contentTypeFor('a.js'), startsWith('text/javascript'));
      expect(contentTypeFor('a.svg'), 'image/svg+xml');
      expect(contentTypeFor('a.woff2'), 'font/woff2');
      expect(contentTypeFor('a.png'), 'image/png');
      expect(contentTypeFor('a.bin'), 'application/octet-stream');
    });

    test('отдаёт index.html и css, 404 на ../, только 127.0.0.1', () async {
      final s = await StaticSiteServer.start(site.path);
      addTearDown(s.stop);
      expect(s.host, '127.0.0.1');
      expect(isLocalPreviewUrl(s.url), isTrue);

      final client = HttpClient();
      addTearDown(client.close);
      final index = await (await client.getUrl(Uri.parse(s.url))).close();
      expect(index.statusCode, 200);
      expect(index.headers.contentType?.mimeType, 'text/html');
      expect(await index.transform(utf8.decoder).join(), '<h1>Привет</h1>');

      final css = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:${s.port}/style.css')))
          .close();
      expect(css.statusCode, 200);
      expect(css.headers.contentType?.mimeType, 'text/css');
      await css.drain<void>();

      final missing = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:${s.port}/nope.js')))
          .close();
      expect(missing.statusCode, 404);
      await missing.drain<void>();

      final host = '127.0.0.1:${s.port}';
      for (final path in [
        '/../secret.txt',
        '/%2e%2e/secret.txt',
        '/..%2fsecret.txt',
        '/a/../../secret.txt',
      ]) {
        final r = await _raw(s.port,
            'GET $path HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n');
        expect(r, startsWith('HTTP/1.1 404'), reason: path);
        expect(r, isNot(contains('секрет')), reason: path);
      }

      // чужой Host (подмена адреса) — отказ
      final evil = await _raw(s.port,
          'GET / HTTP/1.1\r\nHost: evil.example\r\nConnection: close\r\n\r\n');
      expect(evil, startsWith('HTTP/1.1 403'));
      // не GET — отказ
      final post = await _raw(s.port,
          'POST / HTTP/1.1\r\nHost: $host\r\nContent-Length: 0\r\n'
          'Connection: close\r\n\r\n');
      expect(post, startsWith('HTTP/1.1 405'));
    });

    test('симлинк наружу не отдаётся', () async {
      try {
        Link(p.join(site.path, 'out.txt'))
            .createSync(p.join(tmp.path, 'secret.txt'));
      } catch (_) {
        return; // нет прав на симлинки — пропускаем
      }
      final s = await StaticSiteServer.start(site.path);
      addTearDown(s.stop);
      final r = await _raw(
          s.port,
          'GET /out.txt HTTP/1.1\r\nHost: 127.0.0.1:${s.port}\r\n'
          'Connection: close\r\n\r\n');
      expect(r, startsWith('HTTP/1.1 404'));
      expect(r, isNot(contains('секрет')));
    });

    test('SitePreview: гаснет по таймеру и по stop', () async {
      final pv = SitePreview(lifetime: const Duration(milliseconds: 100));
      final url = await pv.start(site.path);
      expect(pv.running, isTrue);
      final uri = Uri.parse(url);
      final s = await Socket.connect(uri.host, uri.port);
      await s.close();
      s.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(pv.running, isFalse);
      await expectLater(Socket.connect(uri.host, uri.port), throwsException);
      await pv.stop();
    });
  });

  group('быстрые кнопки', () {
    test('наборы проекта и Офиса', () {
      expect(quickRepliesFor(office: false), [
        'Что сейчас по проекту?',
        'Продолжай',
        'Выпускай',
        'Покажи скриншот',
      ]);
      expect(quickRepliesFor(office: true), [
        'Какие проекты ждут меня?',
        'Статус всех проектов',
      ]);
    });

    testWidgets('нажатие отправляет текст; пока директор работает — скрыты',
        (tester) async {
      final (controller, proc) = await _start(tester);
      await tester.tap(find.byKey(const Key('project-alpha')));
      await _settle(tester);

      expect(find.byKey(const Key('quick-replies')), findsOneWidget);
      expect(find.text('Продолжай'), findsOneWidget);

      final gate = Completer<int>();
      proc.queue.add(FakeRunning(const [
        '{"type":"system","subtype":"init","session_id":"s1"}',
      ], exitGate: gate));
      await tester.tap(find.byKey(const Key('quick-Продолжай')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(proc.started.single, contains(endsWith('Задача: Продолжай')));
      expect(find.byKey(const Key('quick-replies')), findsNothing);
      expect(tester.takeException(), isNull);

      gate.complete(0);
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('голосовой ввод', () {
    testWidgets('кнопка фокусирует поле и вызывает Win+H', (tester) async {
      final voice = FakeVoice();
      final (controller, _) = await _start(tester, voice: voice);
      await tester.tap(find.byKey(const Key('project-alpha')));
      await _settle(tester);

      expect(find.byKey(const Key('voice-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('voice-button')));
      await tester.pump();
      expect(voice.calls, 0); // пауза ~150 мс
      await tester.pump(const Duration(milliseconds: 200));
      expect(voice.calls, 1);
      expect(tester.takeException(), isNull);
    });

    test('не сработало — подсказка про Win+H', () async {
      final voice = FakeVoice(result: false);
      final controller = AppController(
          proc: FakeProc(_handler),
          storage: MemoryStorage(),
          downloadsDir: 'C:\\d',
          voice: voice,
          autoRefresh: null);
      addTearDown(controller.dispose);
      final toasts = <String>[];
      controller.toasts.listen(toasts.add);
      await controller.startVoice();
      await Future<void>.delayed(Duration.zero);
      expect(voice.calls, 1);
      expect(toasts, [voiceFallbackText]);
      expect(voiceFallbackText, contains('Win+H'));
    });
  });

  group('скачать заметнее', () {
    testWidgets('⬇ только у строки с успешной сборкой', (tester) async {
      final (controller, _) = await _start(tester);
      expect(find.byKey(const Key('dl-alpha')), findsOneWidget); // сборка ок
      expect(find.byKey(const Key('dl-beta')), findsNothing); // сборки нет
      final btn = tester.widget<IconButton>(find.byKey(const Key('dl-alpha')));
      expect(btn.tooltip, startsWith('Скачать сборку от '));
      expect(tester.takeException(), isNull);
    });

    testWidgets('меню ⋯ у сайта: «Открыть сайт»', (tester) async {
      final (controller, _) = await _start(tester);
      await tester.tap(find.byKey(const Key('project-alpha')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('chat-menu')));
      await _settle(tester);
      expect(find.text('Открыть сайт'), findsOneWidget);
    });
  });
}
