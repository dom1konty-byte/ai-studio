import 'package:flutter_test/flutter_test.dart';
import 'package:pult_studii/services/git_service.dart';
import 'package:pult_studii/services/process_runner.dart';

import 'fakes.dart';

/// [branch] — текущая ветка, [local] — есть ли локальная alpha,
/// [dirty] — есть ли правки, [fetchOk]/[pullOk] — исход git fetch/pull.
(GitService, FakeProc) _make({
  String branch = 'main',
  bool local = false,
  bool dirty = false,
  bool fetchOk = true,
  bool pullOk = true,
}) {
  final proc = FakeProc((exe, args, cwd) {
    final k = args.join(' ');
    if (k == 'fetch origin') {
      return fetchOk ? const ProcResult(0) : const ProcResult(1, '', 'нет сети');
    }
    if (k == 'status --porcelain') {
      return ProcResult(0, dirty ? ' M file.txt\n' : '');
    }
    if (k == 'branch --show-current') return ProcResult(0, '$branch\n');
    if (k == 'rev-parse --verify --quiet refs/heads/alpha') {
      return ProcResult(local ? 0 : 1, local ? 'aaa\n' : '');
    }
    if (k == 'rev-parse --verify --quiet origin/alpha') {
      return const ProcResult(0, 'fff0000\n');
    }
    if (k == 'pull --ff-only') {
      return pullOk ? const ProcResult(0) : const ProcResult(1, '', 'diverged');
    }
    return const ProcResult(0);
  });
  final git = GitService(proc, MemoryStorage())..repoPath = 'C:\\ai';
  return (git, proc);
}

void main() {
  test('нет локальной ветки: создаём из origin (switch -c)', () async {
    final (git, proc) = _make();
    final r = await git.prepareMain('alpha');
    expect(r.blockedReason, isNull);
    expect(proc.calls, contains('git switch -c alpha origin/alpha'));
    expect(proc.calls, contains('git pull --ff-only'));
    expect(r.originSha, 'fff0000');
    expect(r.fetchOk, isTrue);
    expect(r.pulled, isTrue);
  });

  test('локальная ветка есть: обычный switch', () async {
    final (git, proc) = _make(local: true);
    await git.prepareMain('alpha');
    expect(proc.calls, contains('git switch alpha'));
  });

  test('есть правки в чужой ветке: не переключаем', () async {
    final (git, proc) = _make(dirty: true);
    final r = await git.prepareMain('alpha');
    expect(r.blockedReason, contains('незакоммиченные'));
    expect(proc.calls.where((c) => c.contains('switch')), isEmpty);
  });

  test('правки в нужной ветке: pull пропущен, помечено', () async {
    final (git, proc) = _make(branch: 'alpha', dirty: true);
    final r = await git.prepareMain('alpha');
    expect(r.blockedReason, isNull);
    expect(r.pulled, isFalse);
    expect(proc.calls, isNot(contains('git pull --ff-only')));
  });

  test('fetch упал: чат работает, fetchOk=false', () async {
    final (git, _) = _make(branch: 'alpha', fetchOk: false);
    final r = await git.prepareMain('alpha', lastSeenSha: 'abc1234');
    expect(r.blockedReason, isNull);
    expect(r.fetchOk, isFalse);
    expect(r.warning, contains('Не удалось обновить'));
  });

  test('pull упал: pulled=false и предупреждение', () async {
    final (git, _) = _make(branch: 'alpha', pullOk: false);
    final r = await git.prepareMain('alpha');
    expect(r.pulled, isFalse);
    expect(r.warning, contains('ещё не подтянуты'));
  });

  test('небезопасное имя ветки отклоняется', () async {
    final (git, proc) = _make();
    final r = await git.prepareMain('--upload-pack=x');
    expect(r.blockedReason, isNotNull);
    expect(proc.calls, isEmpty);
  });

  test('git-операции идут по очереди', () async {
    final (git, proc) = _make(branch: 'alpha');
    final order = <String>[];
    final a = git.prepareMain('alpha').then((_) => order.add('prepare'));
    final b = git.setRepoPath('C:\\other').then((_) => order.add('path'));
    await Future.wait([a, b]);
    expect(order, ['prepare', 'path']);
    expect(git.repoPath, 'C:\\other');
    expect(proc.calls, isNotEmpty);
  });
}
