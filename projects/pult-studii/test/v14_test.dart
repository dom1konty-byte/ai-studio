import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pult_studii/app/app.dart';
import 'package:pult_studii/services/app_storage.dart';
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
  if (k.startsWith('api ')) {
    return const ProcResult(1, '', 'gh: Not Found (HTTP 404)');
  }
  return const ProcResult(0);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<(AppController, MemoryStorage)> _start(
  WidgetTester tester,
  Size size, {
  Map<String, dynamic>? extra,
  bool offer = false,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = MemoryStorage(
      state: {'repoPath': 'C:\\ai-studio', ...?extra}, readme: _alphaReadme);
  final controller = AppController(
      proc: FakeProc(_handler),
      storage: storage,
      downloadsDir: 'C:\\Downloads',
      autoRefresh: null,
      offerCompact: offer);
  await tester.pumpWidget(RubkaApp(controller: controller));
  controller.init();
  if (settle) {
    await _settle(tester);
  } else {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }
  return (controller, storage);
}

double _tileHeight(WidgetTester t) =>
    t.getSize(find.byKey(const Key('tile-waits'))).height;

void main() {
  testWidgets('компактный режим меняет высоту плиток и сохраняется',
      (tester) async {
    final (c, storage) = await _start(tester, const Size(1200, 760));
    expect(_tileHeight(tester), 132);

    await c.setCompact(true);
    await _settle(tester);
    expect(_tileHeight(tester), 100);
    expect(storage.state['compact'], true);

    final repo = StateRepo(storage);
    await repo.load();
    expect(repo.compact, isTrue);

    await c.setCompact(false);
    await _settle(tester);
    expect(_tileHeight(tester), 132);
    expect(storage.state['compact'], false);
  });

  testWidgets('переключатель в Настройке («Вид и уведомления»)',
      (tester) async {
    final (c, _) = await _start(tester, const Size(960, 600));
    await tester.tap(find.byKey(const Key('btn-setup')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('step-4')));
    await _settle(tester);
    expect(find.text('Компактный режим'), findsOneWidget);
    await tester.tap(find.byKey(const Key('switch-compact')));
    await _settle(tester);
    expect(c.compact, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('компактный режим: нет переполнения на 960x600', (tester) async {
    final (c, _) =
        await _start(tester, const Size(960, 600), extra: {'compact': true});
    expect(tester.takeException(), isNull);
    expect(_tileHeight(tester), 100);

    await tester.tap(find.byKey(const Key('project-alpha')));
    await _settle(tester);
    expect(tester.takeException(), isNull);

    for (final k in ['nav-chats', 'office-tile', 'nav-overview']) {
      await tester.tap(find.byKey(Key(k)));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: k);
    }
    await tester.tap(find.byKey(const Key('btn-setup')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(c.compact, isTrue);
  });

  testWidgets('с disableAnimations всё рисуется сразу', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _start(tester, const Size(1200, 760), settle: false);
    final fade = tester.widget<FadeTransition>(find
        .ancestor(
            of: find.byKey(const Key('btn-usage')),
            matching: find.byType(FadeTransition))
        .first);
    expect(fade.opacity.value, 1);
    expect(tester.widget<Text>(find.byKey(const Key('waits-count'))).data, '1');
    expect(find.text('Альфа'), findsOneWidget);
  });

  testWidgets('первый запуск в маленьком окне: тост «Включить»',
      (tester) async {
    final (c, storage) =
        await _start(tester, const Size(960, 600), offer: true);
    expect(find.text('Включить'), findsOneWidget);
    expect(storage.state['compactAsked'], true);
    await tester.tap(find.text('Включить'));
    await _settle(tester);
    expect(c.compact, isTrue);
  });
}
