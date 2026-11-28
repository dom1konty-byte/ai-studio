import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'process_runner.dart';

const _utf8 = Utf8Codec(allowMalformed: true);

/// Разбор вывода `reg query ... /v Path`.
String? parseRegPath(String out) {
  final m = RegExp(r'^\s*Path\s+REG_(?:EXPAND_)?SZ\s+(.*)$',
          multiLine: true, caseSensitive: false)
      .firstMatch(out);
  final v = m?.group(1)?.trim();
  return v == null || v.isEmpty ? null : v;
}

/// Подставляет `%VAR%` из [env] (имена без учёта регистра).
String expandEnv(String text, Map<String, String> env) {
  final upper = {for (final e in env.entries) e.key.toUpperCase(): e.value};
  return text.replaceAllMapped(RegExp(r'%([^%]+)%'),
      (m) => upper[m.group(1)!.toUpperCase()] ?? m.group(0)!);
}

/// Найти программу в списке папок PATH: сначала .exe, потом .cmd/.bat.
String? findInPath(String name, List<String> dirs, bool Function(String) exists) {
  for (final ext in const ['.exe', '.cmd', '.bat']) {
    for (final d in dirs) {
      final sep = d.endsWith('\\') ? '' : '\\';
      final f = '$d$sep$name$ext';
      if (exists(f)) return f;
    }
  }
  return null;
}

class RealProcessRunner implements ProcessRunner {
  final _cache = <String, String>{};

  /// PATH, перечитанный из реестра (null — берём из окружения процесса).
  String? _path;

  String get _currentPath => _path ?? Platform.environment['PATH'] ?? '';

  Map<String, String> _env() => {
        'NoDefaultCurrentDirectoryInExePath': '1',
        'GIT_TERMINAL_PROMPT': '0',
        'GCM_INTERACTIVE': 'never',
        if (_path != null) 'PATH': _path!,
      };

  String get _sysRoot => Platform.environment['SystemRoot'] ?? r'C:\Windows';

  Future<String?> _regPath(String key) async {
    try {
      final r = await Process.run(
          '$_sysRoot\\System32\\reg.exe', ['query', key, '/v', 'Path'],
          stdoutEncoding: _utf8, stderrEncoding: _utf8);
      return r.exitCode == 0 ? parseRegPath('${r.stdout}') : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> refreshEnvironment() async {
    _cache.clear();
    if (!Platform.isWindows) return;
    final machine = await _regPath(
        r'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment');
    final user = await _regPath(r'HKCU\Environment');
    if (machine == null && user == null) return;
    final env = Platform.environment;
    final seen = <String>{};
    final out = <String>[];
    for (final src in [
      if (machine != null) expandEnv(machine, env),
      if (user != null) expandEnv(user, env),
      env['PATH'] ?? '',
    ]) {
      for (final d in src.split(';')) {
        final t = d.trim();
        if (t.isNotEmpty && seen.add(t.toLowerCase())) out.add(t);
      }
    }
    _path = out.join(';');
  }

  @override
  Future<String?> resolveExecutable(String name) async {
    if (!Platform.isWindows) return name;
    // Полный путь (скачанный установщик): запускаем, если файл есть.
    if (name.contains('\\') || name.contains('/')) {
      return File(name).existsSync() ? name : null;
    }
    final cached = _cache[name];
    if (cached != null) return cached;
    final dirs = _currentPath
        .split(';')
        .map((d) => d.trim())
        .where((d) => d.isNotEmpty)
        .toList();
    final found = findInPath(name, dirs, (f) => File(f).existsSync());
    if (found != null) _cache[name] = found;
    return found;
  }

  /// Для .cmd/.bat — через оболочку, но с полным путём.
  bool _shell(String exe) => Platform.isWindows && isShellScript(exe);

  @override
  Future<ProcResult> run(String exe, List<String> args,
      {String? cwd, Duration timeout = const Duration(seconds: 120)}) async {
    final path = await resolveExecutable(exe);
    if (path == null) return ProcResult(-1, '', 'Не найдено: $exe');
    try {
      final p = await Process.start(path, args,
          workingDirectory: cwd,
          runInShell: _shell(path),
          environment: _env());
      try {
        await p.stdin.close();
      } catch (_) {}
      final out = p.stdout.transform(_utf8.decoder).join();
      final err = p.stderr.transform(_utf8.decoder).join();
      try {
        final code = await p.exitCode.timeout(timeout);
        return ProcResult(code, await out, await err);
      } on TimeoutException {
        await _killTree(p);
        return ProcResult(124, '',
            'Превышено время ожидания (${timeout.inSeconds} с): $exe');
      }
    } on ProcessException catch (e) {
      return ProcResult(-1, '', 'Не найдено: $exe (${e.message})');
    }
  }

  @override
  Future<RunningProcess> start(String exe, List<String> args,
      {String? cwd, String? stdin}) async {
    final path = await resolveExecutable(exe);
    if (path == null) throw ToolNotFound(exe);
    final p = await Process.start(path, args,
        workingDirectory: cwd,
        runInShell: _shell(path),
        environment: _env());
    try {
      if (stdin != null) p.stdin.add(utf8.encode(stdin));
      await p.stdin.close();
    } catch (_) {
      // процесс мог уже завершиться
    }
    return _RealRunning(p);
  }
}

/// Убить процесс с дочерними: taskkill по полному пути, иначе обычный kill.
Future<void> _killTree(Process p) async {
  if (!Platform.isWindows) {
    p.kill();
    return;
  }
  final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  try {
    final r = await Process.run(
        '$root\\System32\\taskkill.exe', ['/T', '/F', '/PID', '${p.pid}']);
    if (r.exitCode != 0) p.kill();
  } catch (_) {
    p.kill();
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
  Future<void> kill() => _killTree(_p);
}
