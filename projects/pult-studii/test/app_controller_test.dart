import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pult_studii/models/models.dart';
import 'package:pult_studii/services/process_runner.dart';
import 'package:pult_studii/state/app_controller.dart';

import 'fakes.dart';

const _alpha = Project(
    name: 'Альфа',
    slug: 'alpha',
    type: 'Сайт',
    stage: 'Разработка',
    branch: 'alpha',
    branchExists: true);
const _beta = Project(
    name: 'Бета',
    slug: 'beta',
    type: 'Сайт',
    stage: 'Разработка',
    branch: 'beta',
    branchExists: true);

Future<void> _untilReady(AppController app) async {
  while (app.chat!.preparing) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('переключение проекта блокируется при preparing и working', () async {
    final proc = FakeProc((exe, args, cwd) {
      final k = args.join(' ');
      if (k == 'branch --show-current') return const ProcResult(0, 'alpha\n');
      if (k.startsWith('rev-parse --verify --quiet origin/')) {
        return const ProcResult(0, 'fff0000\n');
      }
      return const ProcResult(0);
    });
    final app = AppController(
        proc: proc,
        storage: MemoryStorage(state: {'repoPath': 'C:\\ai'}),
        downloadsDir: 'C:\\d',
        autoRefresh: null);
    await app.state.load();
    await app.git.setRepoPath('C:\\ai');

    expect(app.select(_alpha), isNull);
    expect(app.chat!.preparing, isTrue);
    expect(app.select(_beta), isNotNull); // идёт переключение ветки
    expect(app.chat!.slug, 'alpha');

    await _untilReady(app);
    final run = FakeRunning(const [], stream: StreamController<String>());
    proc.queue.add(run);
    final f = app.chat!.send('долго');
    await Future<void>.delayed(Duration.zero);
    expect(app.chat!.working, isTrue);
    expect(app.select(_beta), isNotNull); // директор работает
    await app.chat!.stop();
    await f;

    expect(app.select(_beta), isNull);
    expect(app.chat!.slug, 'beta');
    await _untilReady(app);
    app.dispose();
  });
}
