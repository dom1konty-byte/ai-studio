import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pult_studii/app/app.dart';
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
        '{"workflow_runs":[{"id":7,"status":"completed","conclusion":"success","updated_at":"2999-01-01T00:00:00Z"}]}');
  }
  if (k.startsWith('api ')) return const ProcResult(1, '', 'gh: Not Found (HTTP 404)');
  return const ProcResult(0);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
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

    expect(find.text('Рубка'), findsOneWidget);
    expect(find.text('Альфа'), findsOneWidget);
    expect(find.text('Бета'), findsOneWidget);
    expect(find.text('ждёт да'), findsOneWidget);
    expect(find.text('Выбери проект слева'), findsOneWidget);
    expect(find.text('Скачать'), findsOneWidget); // у Альфы сборка успешна
    expect(find.text('сборка: нет сборки'), findsOneWidget); // у Беты нет

    await tester.tap(find.text('Альфа'));
    await _settle(tester);

    expect(find.text('Напиши, что сделать'), findsOneWidget);
    expect(find.text('Да'), findsOneWidget);
    expect(find.text('Поправить'), findsOneWidget);

    proc.queue.add(FakeRunning(const [
      '{"type":"system","subtype":"init","session_id":"s1"}',
      '{"type":"assistant","message":{"content":[{"type":"text","text":"Принято"}]}}',
      '{"type":"result","subtype":"success","is_error":false,"result":"Принято","session_id":"s1"}',
    ]));
    await tester.tap(find.text('Да'));
    await _settle(tester);

    expect(proc.started.single, contains(endsWith('Задача: да')));
    expect(find.textContaining('Принято', findRichText: true), findsWidgets);
    expect(find.text('да'), findsOneWidget); // сообщение Дамира в ленте
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
}
