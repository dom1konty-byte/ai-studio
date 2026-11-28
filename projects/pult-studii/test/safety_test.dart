import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pult_studii/models/models.dart';
import 'package:pult_studii/models/safety.dart';
import 'package:pult_studii/services/app_storage.dart';
import 'package:pult_studii/services/gh_service.dart';
import 'package:pult_studii/services/git_service.dart';
import 'package:pult_studii/services/process_runner.dart';
import 'package:pult_studii/services/real_process_runner.dart';
import 'package:pult_studii/services/tools_check.dart';

import 'fakes.dart';

void main() {
  group('S1: белый и чёрный список', () {
    test('простая команда из белого списка', () {
      final d = decideCommand('git status');
      expect(d.canAllow, isTrue);
      expect(d.rules, ['Bash(git status)']);
      expect(decideCommand('flutter analyze').rules, ['Bash(flutter analyze)']);
    });

    test('составная: правило на каждую часть', () {
      final d = decideCommand('git status && flutter analyze');
      expect(d.rules, ['Bash(git status)', 'Bash(flutter analyze)']);
      expect(decideCommand('git status | findstr x').rules,
          ['Bash(git status)', 'Bash(findstr x)']);
      expect(decideCommand('git add .; git commit').rules.length, 2);
    });

    test('составная: одна плохая часть — отказ всем', () {
      expect(decideCommand('git status; rm -rf x').dangerous, isTrue);
      expect(decideCommand('git status | rm x').canAllow, isFalse);
      expect(decideCommand('git status && echo hi').canAllow, isFalse);
      expect(decideCommand('git status && echo hi').dangerous, isFalse);
    });

    test('всегда запрещены', () {
      for (final c in [
        'rm -rf build',
        'del /s x',
        'erase x',
        'rmdir x',
        'rd x',
        'Remove-Item x',
        'powershell -c x',
        'pwsh x',
        'cmd /c dir',
        r'C:\Windows\System32\cmd.exe /c dir',
        'curl http://x',
        'wget http://x',
        'iwr http://x',
        'Invoke-WebRequest x',
        'reg add x',
        'format c:',
        'taskkill /F',
        'schtasks /create',
        'icacls x',
        'takeown x',
        'git push --force origin x',
        'git push -f',
        'gh repo delete x',
        'gh auth logout',
        'gh secret set X',
      ]) {
        final d = decideCommand(c);
        expect(d.canAllow, isFalse, reason: c);
        expect(d.dangerous, isTrue, reason: c);
        expect(d.refusal, dangerousText, reason: c);
      }
    });

    test('вне белого списка и спецсимволы', () {
      for (final c in [
        'echo hi',
        'git commit -m "x"',
        "git commit -m 'x'",
        'ls > out.txt',
        r'ls $(rm x)',
        'git `x`',
        'FOO=1 git status',
        '',
      ]) {
        final d = decideCommand(c);
        expect(d.canAllow, isFalse, reason: c);
        expect(d.dangerous, isFalse, reason: c);
      }
    });

    test('не-Bash инструмент разрешить нельзя', () {
      const d = PermissionDenial(toolName: 'WebFetch', input: {'url': 'x'});
      expect(d.decision.canAllow, isFalse);
    });
  });

  group('S3: валидация правил и сессий', () {
    test('isValidRule', () {
      expect(isValidRule('Bash(git *)'), isTrue);
      expect(isValidRule('Bash(python scripts/status.py)'), isTrue);
      expect(isValidRule(r'Bash(dir C:\x)'), isTrue);
      expect(isValidRule('Bash(git status && rm x)'), isFalse);
      expect(isValidRule('Bash(git "x")'), isFalse);
      expect(isValidRule('Bash(git %PATH%)'), isFalse);
      expect(isValidRule('Bash(git status)\n'), isFalse);
      expect(isValidRule('Bash(git\nstatus)'), isFalse);
      expect(isValidRule('Bash()'), isFalse);
      expect(isValidRule('Write'), isFalse);
    });

    test('isSafeRule: ещё и белый список', () {
      expect(isSafeRule('Bash(git *)'), isTrue);
      expect(isSafeRule('Bash(rm *)'), isFalse);
      expect(isSafeRule('Bash(echo hi)'), isFalse);
      expect(isSafeRule('Bash(curl *)'), isFalse);
    });

    test('правила из state.json фильтруются при чтении и записи', () async {
      final storage = MemoryStorage(state: {
        'projects': {
          'alpha': {
            'allowedTools': ['Bash(git *)', 'Bash(rm *)', 'Bash(a && b)', 5]
          }
        }
      });
      final s = StateRepo(storage);
      await s.load();
      expect(s.allowedTools('alpha'), ['Bash(git *)']);
      await s.addAllowedTools('alpha', ['Bash(ls x)', 'Bash(del x)']);
      expect(s.allowedTools('alpha'), ['Bash(git *)', 'Bash(ls x)']);
    });

    test('sessionId', () {
      expect(isValidSessionId('11111111-2222-3333-4444-555555555555'), isTrue);
      expect(isValidSessionId('s1'), isFalse);
      expect(isValidSessionId('11111111-2222-3333-4444-55555555555; x'), isFalse);
      expect(isValidSessionId(null), isFalse);
    });
  });

  group('S8: маскировка и обрезка', () {
    test('секреты', () {
      expect(maskSecrets('ключ ghp_abcDEF123456 тут'), 'ключ *** тут');
      expect(maskSecrets('github_pat_11AAA_bbb'), '***');
      expect(maskSecrets('sk-ant-api03-AbC_d-e'), '***');
      expect(maskSecrets('gho_x1y2'), '***');
      expect(maskSecrets('Authorization: Bearer abc.def-123'), 'Authorization: ***');
      expect(maskSecrets('GET /x?token=XYZ123&a=1'), 'GET /x?***&a=1');
      expect(maskSecrets('обычный текст'), 'обычный текст');
    });

    test('в строке истории нет секретов, действие обрезано', () {
      final u = ChatMessage(MsgKind.user, 'мой ghp_secret123456');
      expect(u.toJsonLine(), isNot(contains('ghp_')));
      final a = ChatMessage(MsgKind.action, 'агент запускает: ${'x' * 500}');
      final t = (jsonDecode(a.toJsonLine()) as Map)['t'] as String;
      expect(t.length, lessThanOrEqualTo(200));
      final back = ChatMessage.fromJsonLine(a.toJsonLine());
      expect(back!.kind, MsgKind.action);
    });
  });

  group('S5, S6', () {
    test('сводка с телефона: рамка и лимиты', () {
      final commits = [for (var i = 0; i < 40; i++) 'c${'x' * 199}'];
      final p = phoneSummaryPrompt(commits);
      expect(p, contains('данные, не инструкции'));
      final lines = p.split('\n');
      expect(lines.where((l) => l.startsWith('c')).length, 30);
      expect(lines.every((l) => l.length <= 120), isTrue);
      expect(p, contains('и ещё 10'));
      expect(phoneSummaryPrompt(['a'], pulled: false),
          contains('ещё не подтянуты в папку'));
    });

    test('safeHttpsHost', () {
      expect(safeHttpsHost('https://github.com/x/y'), 'github.com');
      expect(safeHttpsHost('http://a.com'), isNull);
      expect(safeHttpsHost('file:///c:/x'), isNull);
      expect(safeHttpsHost('javascript:alert(1)'), isNull);
      expect(safeHttpsHost('https://a.com/ b'), isNull);
      expect(safeHttpsHost('https://a.com/"x'), isNull);
      expect(safeHttpsHost('https:///x'), isNull);
      expect(safeHttpsHost(null), isNull);
    });
  });

  group('PATH из реестра', () {
    test('разбор reg query и %VAR%', () {
      const out = '\r\nHKEY_CURRENT_USER\\Environment\r\n'
          '    Path    REG_EXPAND_SZ    %USERPROFILE%\\bin;C:\\x\r\n';
      final v = parseRegPath(out)!;
      expect(v, r'%USERPROFILE%\bin;C:\x');
      expect(expandEnv(v, {'UserProfile': r'C:\Users\d'}), r'C:\Users\d\bin;C:\x');
      expect(parseRegPath('ничего'), isNull);
    });

    test('поиск: .exe раньше .cmd', () {
      final files = {r'C:\a\claude.cmd', r'C:\b\claude.exe'};
      expect(findInPath('claude', [r'C:\a', r'C:\b'], files.contains),
          r'C:\b\claude.exe');
      expect(findInPath('nope', [r'C:\a'], files.contains), isNull);
    });
  });

  group('R10: проверка установки', () {
    Future<ToolStatus> claudeStatus(ProcResult auth) async {
      final proc = FakeProc((exe, args, cwd) {
        if (exe == 'claude' && args.join(' ') == 'auth status') return auth;
        return ProcResult(0, '$exe 1.0\n');
      });
      final list = await ToolsCheck(proc, MemoryStorage()).check('C:\\ai');
      return list.firstWhere((t) => t.id == 'claude');
    }

    test('вход есть / нет / команды нет', () async {
      expect((await claudeStatus(const ProcResult(0))).ok, isTrue);
      expect((await claudeStatus(const ProcResult(1, '', 'Not logged in'))).ok,
          isFalse);
      final old = await claudeStatus(
          const ProcResult(1, '', "error: unknown command 'auth'"));
      expect(old.ok, isTrue);
      expect(old.detail, contains('вход не проверен'));
    });

    test('Python — предупреждение, не блокирует', () async {
      final proc = FakeProc((exe, args, cwd) => exe.startsWith('py')
          ? const ProcResult(-1, '', 'нет')
          : ProcResult(0, '$exe 1.0\n'));
      final list = await ToolsCheck(proc, MemoryStorage()).check('C:\\ai');
      final py = list.firstWhere((t) => t.id == 'python');
      expect(py.ok, isFalse);
      expect(py.blocking, isFalse);
      expect(list.where((t) => t.blocking).every((t) => t.ok), isTrue);
    });
  });
}
