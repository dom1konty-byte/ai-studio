import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'process_runner.dart';

const _utf8 = Utf8Codec(allowMalformed: true);

class RealProcessRunner implements ProcessRunner {
  final _cache = <String, String>{};

  @override
  Future<String> resolveExecutable(String name) async {
    if (!Platform.isWindows) return name;
    final cached = _cache[name];
    if (cached != null) return cached;
    final dirs = (Platform.environment['PATH'] ?? '')
        .split(';')
        .map((d) => d.trim())
        .where((d) => d.isNotEmpty)
        .toList();
    // Сначала .exe по всему PATH, потом .cmd/.bat.
    for (final ext in const ['.exe', '.cmd', '.bat']) {
      for (final d in dirs) {
        final sep = d.endsWith('\\') ? '' : '\\';
        final f = File('$d$sep$name$ext');
        if (f.existsSync()) return _cache[name] = f.path;
      }
    }
    return name;
  }

  /// Для .cmd/.bat — голое имя и runInShell (так надёжнее с пробелами в пути).
  (String, bool) _prepare(String exe) {
    if (Platform.isWindows && isShellScript(exe)) {
      final base = exe.split(RegExp(r'[\\/]')).last;
      final dot = base.lastIndexOf('.');
      return (dot > 0 ? base.substring(0, dot) : base, true);
    }
    return (exe, false);
  }

  @override
  Future<ProcResult> run(String exe, List<String> args, {String? cwd}) async {
    final path = await resolveExecutable(exe);
    final (cmd, shell) = _prepare(path);
    try {
      final r = await Process.run(cmd, args,
          workingDirectory: cwd,
          runInShell: shell,
          stdoutEncoding: _utf8,
          stderrEncoding: _utf8);
      return ProcResult(r.exitCode, '${r.stdout}', '${r.stderr}');
    } on ProcessException catch (e) {
      return ProcResult(-1, '', 'Не найдено: $exe (${e.message})');
    }
  }

  @override
  Future<RunningProcess> start(String exe, List<String> args,
      {String? cwd, String? stdin}) async {
    final (cmd, shell) = _prepare(exe);
    final p = await Process.start(cmd, args,
        workingDirectory: cwd, runInShell: shell);
    try {
      if (stdin != null) p.stdin.add(utf8.encode(stdin));
      await p.stdin.close();
    } catch (_) {
      // процесс мог уже завершиться
    }
    return _RealRunning(p);
  }
}

class _RealRunning implements RunningProcess {
  _RealRunning(this._p)
      : stderrText = _p.stderr.transform(_utf8.decoder).join();

  final Process _p;

  @override
  final Future<String> stderrText;

  @override
  Stream<String> get stdoutLines =>
      _p.stdout.transform(_utf8.decoder).transform(const LineSplitter());

  @override
  Future<int> get exitCode => _p.exitCode;

  @override
  void kill() {
    if (Platform.isWindows) {
      Process.run('taskkill', ['/T', '/F', '/PID', '${_p.pid}']);
    } else {
      _p.kill();
    }
  }
}
