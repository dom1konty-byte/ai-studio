import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pult_studii/app/app.dart';
import 'package:pult_studii/app/theme.dart';
import 'package:pult_studii/services/process_runner.dart';
import 'package:pult_studii/state/app_controller.dart';

import 'fakes.dart';

const _alphaReadme = '''
| Имя | Папка | Тип | Этап | Ветка | Создан |
|---|---|---|---|---|---|
| Альфа | [`alpha`](alpha/) | Сайт | Дизайн ✅ ждёт «да» | `alpha` | 2026-11-01 |
''';

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
  if (k == 'show origin/alpha:projects/README.md') {
    return const ProcResult(0, _alphaReadme);
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

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Color? _tagColor(WidgetTester t, String slug) {
  final box = t.widget<Container>(find.byKey(Key('tag-$slug')));
  return (box.decoration as BoxDecoration?)?.color;
}

Future<AppController> _start(WidgetTester tester, Size size,
    {bool two = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = AppController(
      proc: FakeProc(_handler),
      storage: MemoryStorage(
          state: {'repoPath': 'C:\\ai-studio'},
          readme: two ? sampleReadme : _alphaReadme),
      downloadsDir: 'C:\\Downloads',
      autoRefresh: null);
  await tester.pumpWidget(RubkaApp(controller: controller));
  controller.init();
  await _settle(tester);
  return controller;
}

void main() {
  testWidgets('доска, метка «ждёт да», чат и кнопка «Да»', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final proc = FakeProc(_handler);
    final storage =
        MemoryStorage(state: {'repoPath': 'C:\\ai-studio'}, readme: _alphaReadme);
    final controller = AppController(
        proc: proc,
        storage: storage,
        downloadsDir: 'C:\\Downloads',
        autoRefresh: null);

    await tester.pumpWidget(RubkaApp(controller: controller));
    controller.init();
    await _settle(tester);

    expect(find.text('Альфа'), findsOneWidget);
    expect(find.text('Бета'), findsOneWidget);
    expect(_tagColor(tester, 'alpha'), Rubka.tagWaitBg); // ждёт «да»
    expect(_tagColor(tester, 'beta'), Rubka.tagIdleBg); // сборки нет
    expect(find.text('Выбери проект'), findsOneWidget);
    expect(find.byKey(const Key('btn-usage')), findsOneWidget);
    expect(find.byKey(const Key('btn-setup')), findsOneWidget);
    expect(find.byKey(const Key('new-project')), findsOneWidget);

    await tester.tap(find.byKey(const Key('project-alpha')));
    await _settle(tester);

    expect(find.text('Напиши, что сделать'), findsOneWidget);
    expect(find.byKey(const Key('approval-card')), findsOneWidget);
    expect(find.text('Нужно твоё решение'), findsOneWidget);
    expect(find.byKey(const Key('approve-yes')), findsOneWidget);
    expect(find.byKey(const Key('approve-fix')), findsOneWidget);
    expect(find.byKey(const Key('stage-pill')), findsOneWidget);

    proc.queue.add(FakeRunning(const [
      '{"type":"system","subtype":"init","session_id":"s1"}',
      '{"type":"assistant","message":{"content":[{"type":"text","text":"Принято"}]}}',
      '{"type":"result","subtype":"success","is_error":false,"result":"Принято","session_id":"s1"}',
    ]));
    await tester.tap(find.byKey(const Key('approve-yes')));
    await _settle(tester);

    expect(proc.started.single, contains(endsWith('Задача: да')));
    expect(find.textContaining('Принято', findRichText: true), findsWidgets);
    expect(find.text('да'), findsOneWidget); // сообщение Дамира в ленте
  });

  testWidgets('меню ⋯ содержит пункты', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = AppController(
        proc: FakeProc(_handler),
        storage: MemoryStorage(
            state: {'repoPath': 'C:\\ai-studio'}, readme: _alphaReadme),
        downloadsDir: 'C:\\Downloads',
        autoRefresh: null);

    await tester.pumpWidget(RubkaApp(controller: controller));
    controller.init();
    await _settle(tester);
    await tester.tap(find.byKey(const Key('project-alpha')));
    await _settle(tester);

    expect(find.text('Документы'), findsNothing);
    await tester.tap(find.byKey(const Key('chat-menu')));
    await _settle(tester);

    expect(find.text('Документы'), findsOneWidget);
    expect(find.text('Скачать сборку'), findsOneWidget);
    expect(find.text('Продолжить на телефоне'), findsOneWidget);
    expect(find.text('Открыть для телефона'), findsOneWidget);
    expect(find.text('Расходы'), findsOneWidget);
    expect(find.text('Новый чат'), findsOneWidget);
    expect(find.text('На телефон'), findsNothing); // «Сайт», не приложение
  });

  testWidgets('нет git → экран настройки с командой', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final proc = FakeProc((exe, args, cwd) =>
        exe == 'git' ? const ProcResult(-1, '', 'нет') : _handler(exe, args, cwd));
    final controller = AppController(
        proc: proc,
        storage: MemoryStorage(state: {'repoPath': 'C:\\ai-studio'}),
        downloadsDir: 'C:\\Downloads',
        autoRefresh: null);

    await tester.pumpWidget(RubkaApp(controller: controller));
    controller.init();
    await _settle(tester);

    expect(find.text('Мастер первого запуска'), findsOneWidget);
    expect(find.text('Git'), findsOneWidget);
    expect(find.text('Установить выбранное'), findsOneWidget);
    expect(find.text('Проверить снова'), findsOneWidget);
  });

  testWidgets('Настройка: нет переполнения на 960x600, все шаги', (tester) async {
    tester.view.physicalSize = const Size(960, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final proc = FakeProc((exe, args, cwd) =>
        exe == 'git' ? const ProcResult(-1, '', 'нет') : _handler(exe, args, cwd));
    final controller = AppController(
        proc: proc,
        storage: MemoryStorage(state: {'repoPath': 'C:\\ai-studio'}),
        downloadsDir: 'C:\\Downloads',
        autoRefresh: null);

    await tester.pumpWidget(RubkaApp(controller: controller));
    controller.init();
    await _settle(tester);

    expect(find.byKey(const Key('btn-setup')), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(Key('step-$i')));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'шаг $i');
    }
    expect(find.byType(Switch), findsWidgets); // шаг «Уведомления»
  });

  testWidgets('плитка «ждут да» показывает число и открывает чат',
      (tester) async {
    await _start(tester, const Size(1200, 760));

    expect(tester.widget<Text>(find.byKey(const Key('waits-count'))).data, '1');
    expect(find.byKey(const Key('chat-title')), findsNothing);

    await tester.tap(find.byKey(const Key('tile-waits')));
    await _settle(tester);

    expect(find.byKey(const Key('chat-title')), findsOneWidget);
    expect(find.byKey(const Key('approval-card')), findsOneWidget);
  });

  for (final size in const [Size(960, 600), Size(1200, 760)]) {
    testWidgets('нет переполнения при ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      await _start(tester, size, two: true);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('project-alpha')));
      await _settle(tester);
      expect(find.byKey(const Key('approval-card')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('nav-chats')));
      await _settle(tester);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('office-tile')));
      await _settle(tester);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('nav-overview')));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
