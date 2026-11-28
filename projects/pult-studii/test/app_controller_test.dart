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

void main() {
  test('переключение проектов не блокируется, чаты живут рядом', () async {
    final proc = FakeProc((exe, args, cwd) {
      final k = args.join(' ');
      if (k == 'branch --show-current') return const ProcResult(0, 'ai-office\n');
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
    expect(app.select(_beta), isNull); // даже пока ветка готовится
    expect(app.chat!.slug, 'beta');
    expect(app.chats.keys, containsAll(['alpha', 'beta']));

    await app.chats['alpha']!.ready();
    await app.chats['beta']!.ready();
    expect(app.select(_alpha), isNull);
    expect(app.chat!.slug, 'alpha');
    expect(app.chats, hasLength(2)); // второй чат не создаётся заново
    app.dispose();
  });
}
