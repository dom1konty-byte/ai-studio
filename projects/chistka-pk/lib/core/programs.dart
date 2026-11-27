/// Список установленных программ (реестр Uninstall): модель, фильтр, разбор
/// строки удаления, поиск и сортировка. Чистые функции — без обращения к системе.
library;

import 'dart:io';

import 'package:path/path.dart' as path_pkg;

import 'format.dart';
import 'whitelist.dart';

/// Запись раздела Uninstall «как есть»: [hive] — `HKCU`, `HKLM` или `HKLM32`
/// (HKLM\WOW6432Node), [keyPath] — полный путь ключа для reg.exe,
/// [values] — значения (DWORD уже переведены в десятичную строку).
class RawUninstall {
  const RawUninstall(this.hive, this.keyPath, this.values);
  final String hive;
  final String keyPath;
  final Map<String, String> values;

  String get keyName => keyPath.split(r'\').last;
}

class Program {
  const Program({
    required this.name,
    required this.publisher,
    required this.sizeKb,
    required this.installDate,
    required this.displayIcon,
    required this.installLocation,
    required this.uninstallString,
    required this.quietUninstallString,
    required this.hive,
    required this.keyPath,
  });

  final String name;
  final String publisher;

  /// EstimatedSize в КБ (0 — не указан).
  final int sizeKb;
  final DateTime? installDate;
  final String displayIcon;
  final String installLocation;
  final String uninstallString;
  final String quietUninstallString;
  final String hive;
  final String keyPath;

  int get sizeBytes => sizeKb * 1024;
  bool get isUserHive => hive == 'HKCU';
}

final RegExp _kbName = RegExp(r'^KB\d+$', caseSensitive: false);
final RegExp _kbInName = RegExp(r'\(KB\d+\)', caseSensitive: false);

/// Скрывать ли запись: без имени, системный компонент, дочерний компонент,
/// обновление/исправление, имя вида KB1234567.
bool isHiddenEntry(Map<String, String> v, String keyName) {
  final name = (v['DisplayName'] ?? '').trim();
  if (name.isEmpty) return true;
  if ((v['SystemComponent'] ?? '').trim() == '1') return true;
  if ((v['ParentKeyName'] ?? '').trim().isNotEmpty) return true;
  final rt = (v['ReleaseType'] ?? '').toLowerCase();
  if (rt.contains('update') || rt.contains('hotfix')) return true;
  if (_kbName.hasMatch(name) || _kbName.hasMatch(keyName) || _kbInName.hasMatch(name)) {
    return true;
  }
  return false;
}

/// yyyymmdd → дата (null, если не разобралась).
DateTime? parseInstallDate(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (y < 1990 || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d);
}

/// Из сырых записей — список программ для показа. Системные скрыты,
/// повторы (одно имя + издатель в разных ветках) схлопнуты.
List<Program> buildPrograms(List<RawUninstall> raw) {
  final seen = <String>{};
  final res = <Program>[];
  for (final r in raw) {
    final v = r.values;
    if (isHiddenEntry(v, r.keyName)) continue;
    final name = v['DisplayName']!.trim();
    final publisher = (v['Publisher'] ?? '').trim();
    final key = '${name.toLowerCase()}\u0000${publisher.toLowerCase()}';
    if (!seen.add(key)) continue;
    res.add(Program(
      name: name,
      publisher: publisher,
      sizeKb: int.tryParse((v['EstimatedSize'] ?? '').trim()) ?? 0,
      installDate: parseInstallDate(v['InstallDate']),
      displayIcon: (v['DisplayIcon'] ?? '').trim(),
      installLocation: (v['InstallLocation'] ?? '').trim(),
      uninstallString: (v['UninstallString'] ?? '').trim(),
      quietUninstallString: (v['QuietUninstallString'] ?? '').trim(),
      hive: r.hive,
      keyPath: r.keyPath,
    ));
  }
  return res;
}

enum ProgramSort { size, date, name }

/// Поиск по имени и издателю (без учёта регистра) и сортировка.
/// Размер/дата — по убыванию (без значения — в конец), имя — по алфавиту.
List<Program> filterAndSort(List<Program> all, String query, ProgramSort sort,
    [Map<String, int> approx = const {}]) {
  final q = query.trim().toLowerCase();
  final res = q.isEmpty
      ? [...all]
      : all
          .where((p) =>
              p.name.toLowerCase().contains(q) || p.publisher.toLowerCase().contains(q))
          .toList();
  int byName(Program a, Program b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
  res.sort((a, b) {
    switch (sort) {
      case ProgramSort.size:
        final c = programBytes(b, approx).compareTo(programBytes(a, approx));
        return c != 0 ? c : byName(a, b);
      case ProgramSort.date:
        final da = a.installDate, db = b.installDate;
        if (da == null && db == null) return byName(a, b);
        if (da == null) return 1;
        if (db == null) return -1;
        final c = db.compareTo(da);
        return c != 0 ? c : byName(a, b);
      case ProgramSort.name:
        return byName(a, b);
    }
  });
  return res;
}

/// Команда запуска: программа и строка аргументов.
class UninstallCommand {
  const UninstallCommand(this.exe, this.args);
  final String exe;
  final String args;

  @override
  String toString() => '$exe $args';
}

String _expandEnv(String s, Map<String, String> env) {
  final lower = {for (final e in env.entries) e.key.toLowerCase(): e.value};
  return s.replaceAllMapped(RegExp(r'%([^%]+)%'), (m) => lower[m.group(1)!.toLowerCase()] ?? m.group(0)!);
}

final RegExp _absPath = RegExp(r'^[A-Za-z]:\\');

bool _defaultFileExists(String path) {
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

String _sysDir(Map<String, String> env) {
  final root = env['SystemRoot'] ?? env['SYSTEMROOT'] ?? env['windir'] ?? r'C:\Windows';
  return '$root\\System32';
}

/// «msiexec»/«rundll32» (с .exe или без) → полный системный путь, иначе null.
String? _systemTool(String exe, Map<String, String> env) {
  final base = exe.split(RegExp(r'[\\/]')).last.toLowerCase();
  if (base == 'msiexec.exe' || base == 'msiexec') return '${_sysDir(env)}\\msiexec.exe';
  if (base == 'rundll32.exe' || base == 'rundll32') return '${_sysDir(env)}\\rundll32.exe';
  return null;
}

bool _isRealExe(String path, bool Function(String) exists) =>
    _absPath.hasMatch(path) && path.toLowerCase().endsWith('.exe') && exists(path);

/// Разбирает UninstallString на exe и аргументы. Годится только:
/// абсолютный путь `X:\…\*.exe`, который существует; либо msiexec.exe /
/// rundll32.exe (запускаются из System32). `MsiExec.exe /I{GUID}` → `/X{GUID}`.
/// Путь без кавычек с пробелами: берётся самый короткий префикс (по пробелам),
/// который является существующим .exe. Иначе — null («программа удаления не найдена»).
UninstallCommand? parseUninstallString(String raw,
    {Map<String, String> env = const {}, bool Function(String path)? fileExists}) {
  final exists = fileExists ?? _defaultFileExists;
  final s = _expandEnv(raw.trim(), env);
  if (s.isEmpty || RegExp(r'[\x00-\x1f]').hasMatch(s)) return null;
  String? exe;
  String args = '';
  if (s.startsWith('"')) {
    final end = s.indexOf('"', 1);
    if (end < 0) return null;
    final cand = s.substring(1, end).trim();
    final rest = s.substring(end + 1).trim();
    final sys = _systemTool(cand, env);
    if (sys != null) {
      exe = sys;
      args = rest;
    } else if (_isRealExe(cand, exists)) {
      exe = cand;
      args = rest;
    }
  } else {
    final first = s.split(RegExp(r'\s'))[0];
    final sys = _systemTool(first, env);
    if (sys != null && !RegExp(r'[\\/]').hasMatch(first)) {
      exe = sys;
      args = s.substring(first.length).trim();
    } else {
      // самый короткий существующий .exe среди префиксов по границам пробелов
      final cuts = <int>[
        for (final m in RegExp(r'\s').allMatches(s)) m.start,
        s.length,
      ];
      for (final cut in cuts) {
        final cand = s.substring(0, cut).trim();
        if (cand.isEmpty) continue;
        final sysTool = _systemTool(cand, env);
        if (sysTool != null && RegExp(r'[\\/]').hasMatch(cand) && _absPath.hasMatch(cand)) {
          exe = sysTool;
          args = s.substring(cut).trim();
          break;
        }
        if (_isRealExe(cand, exists)) {
          exe = cand;
          args = s.substring(cut).trim();
          break;
        }
      }
    }
  }
  if (exe == null) return null;
  final base = exe.split(RegExp(r'[\\/]')).last.toLowerCase();
  if (base == 'msiexec.exe') {
    args = args.replaceAllMapped(
      RegExp(r'/[iI]\s*(\{[0-9A-Fa-f-]+\})'),
      (m) => '/X${m.group(1)}',
    );
  }
  return UninstallCommand(exe, args);
}

// ---------- значок, папка установки, итог ----------

/// Источник значка: файл (exe/dll/ico) и номер значка в нём.
class IconSource {
  const IconSource(this.path, this.index);
  final String path;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is IconSource && other.path.toLowerCase() == path.toLowerCase() && other.index == index;

  @override
  int get hashCode => Object.hash(path.toLowerCase(), index);
}

/// Разбирает DisplayIcon: `"C:\a b\x.exe",0`, `C:\x.dll,-101`, `C:\x.ico`.
/// %VAR% раскрываются. Годится только абсолютный путь `X:\…` к .exe/.dll/.ico.
IconSource? parseDisplayIcon(String raw, {Map<String, String> env = const {}}) {
  final s = _expandEnv(raw.trim(), env);
  if (s.isEmpty || RegExp(r'[\x00-\x1f]').hasMatch(s)) return null;
  String path;
  var index = 0;
  if (s.startsWith('"')) {
    final end = s.indexOf('"', 1);
    if (end < 0) return null;
    path = s.substring(1, end).trim();
    final rest = s.substring(end + 1).trim();
    if (rest.isNotEmpty) {
      final m = RegExp(r'^,\s*(-?\d+)$').firstMatch(rest);
      if (m == null) return null;
      index = int.parse(m.group(1)!);
    }
  } else {
    final m = RegExp(r'^(.*?)(?:\s*,\s*(-?\d+))?$').firstMatch(s)!;
    path = m.group(1)!.trim();
    if (m.group(2) != null) index = int.parse(m.group(2)!);
  }
  if (!_absPath.hasMatch(path)) return null;
  final ext = path.toLowerCase();
  if (!(ext.endsWith('.exe') || ext.endsWith('.dll') || ext.endsWith('.ico'))) return null;
  return IconSource(path, index);
}

/// Откуда брать значок: DisplayIcon, иначе exe программы удаления (не msiexec и
/// не rundll32). Файл должен существовать. Нет источника — null (общая иконка).
IconSource? iconSourceOf(Program p,
    {Map<String, String> env = const {}, bool Function(String path)? fileExists}) {
  final exists = fileExists ?? _defaultFileExists;
  final di = parseDisplayIcon(p.displayIcon, env: env);
  if (di != null && exists(di.path)) return di;
  final cmd = parseUninstallString(p.uninstallString, env: env, fileExists: exists);
  if (cmd != null) {
    final base = cmd.exe.split(RegExp(r'[\\/]')).last.toLowerCase();
    if (base != 'msiexec.exe' && base != 'rundll32.exe' && exists(cmd.exe)) {
      return IconSource(cmd.exe, 0);
    }
  }
  return null;
}

/// Папка установки для ссылки: InstallLocation; иначе папка программы удаления,
/// если она строго внутри Program Files или AppData. Папка должна существовать.
String? installFolderOf(Program p,
    {Map<String, String> env = const {}, bool Function(String dir)? dirExists, bool Function(String file)? fileExists}) {
  final exists = dirExists ?? _defaultDirExists;
  final il = _expandEnv(p.installLocation.trim().replaceAll('"', ''), env);
  if (il.isNotEmpty) {
    final n = normalizeWinPath(il);
    if (n != null && exists(n)) return n;
  }
  final cmd = parseUninstallString(p.uninstallString, env: env, fileExists: fileExists);
  if (cmd == null) return null;
  final dir = normalizeWinPath(cmd.exe.substring(0, cmd.exe.lastIndexOf(r'\')));
  if (dir == null) return null;
  final lower = {for (final e in env.entries) e.key.toLowerCase(): e.value};
  final roots = [
    for (final k in ['programfiles', 'programfiles(x86)', 'programw6432', 'localappdata', 'appdata'])
      if (lower[k] != null) lower[k]!,
  ];
  if (!isInsideAllowedRoot(dir, roots)) return null;
  return exists(dir) ? dir : null;
}

bool _defaultDirExists(String path) {
  try {
    return Directory(path).existsSync();
  } catch (_) {
    return false;
  }
}

/// Размер программы для списка и сортировки: EstimatedSize, иначе посчитанный
/// по папке ([approx] по keyPath), иначе 0.
int programBytes(Program p, Map<String, int> approx) =>
    p.sizeKb > 0 ? p.sizeBytes : (approx[p.keyPath] ?? 0);

/// «Всего программ: 142 · 38,6 ГБ»: число и сумма размеров показанных программ
/// (EstimatedSize + посчитанные по папке; если есть посчитанные — «≈ 38,6 ГБ»).
/// Размер не пишем, если ни у одной он не известен.
String programsSummary(List<Program> shown, [Map<String, int> approx = const {}]) {
  var total = 0;
  var hasApprox = false;
  for (final p in shown) {
    total += programBytes(p, approx);
    if (p.sizeKb <= 0 && (approx[p.keyPath] ?? 0) > 0) hasApprox = true;
  }
  final base = 'Всего программ: ${shown.length}';
  if (total <= 0) return base;
  return '$base · ${hasApprox ? '≈ ' : ''}${formatSize(total)}';
}

final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}]', unicode: true);

/// Папки, размер которых считать нельзя: они общие для многих программ.
const _sharedFolderNames = {
  'common files', 'windowsapps', 'system32', 'syswow64', 'winsxs', 'windows',
  'program files', 'program files (x86)', 'programdata', 'appdata', 'local', 'roaming',
  'locallow', 'programs', 'microsoft', 'users', 'temp', 'desktop', 'documents', 'downloads',
};

/// Можно ли считать размер папки [dir] как размер программы [name]:
/// строго внутри Program Files / Program Files (x86) / LOCALAPPDATA / APPDATA /
/// ProgramData; либо (на другом диске) имя самой папки содержит имя программы.
/// Никогда: корень диска, Windows/System32, общие папки (Common Files и т.п.).
bool isSizeableProgramFolder(String dir, String name, Map<String, String> env) {
  final n = normalizeWinPath(dir);
  if (n == null) return false;
  final w = path_pkg.windows;
  if (w.dirname(n) == n) return false; // корень диска
  final parts = w.split(n).skip(1).map((e) => e.toLowerCase()).toList();
  if (parts.isEmpty) return false;
  final lower = {for (final e in env.entries) e.key.toLowerCase(): e.value};
  final winDir = normalizeWinPath(lower['systemroot'] ?? lower['windir'] ?? r'C:\Windows');
  if (winDir != null && (w.equals(winDir, n) || w.isWithin(winDir, n))) return false;
  if (parts.contains('system32') ||
      parts.contains('syswow64') ||
      parts.contains('common files') ||
      parts.contains('windowsapps') ||
      parts.first == 'windows') {
    return false;
  }
  if (_sharedFolderNames.contains(parts.last)) return false;
  final roots = [
    for (final k in ['programfiles', 'programfiles(x86)', 'programw6432', 'localappdata', 'appdata', 'programdata'])
      if (lower[k] != null) lower[k]!,
  ];
  if (isInsideAllowedRoot(n, roots)) return true;
  final nm = name.toLowerCase().replaceAll(_nonWord, '');
  if (nm.length < 3) return false;
  return parts.last.replaceAll(_nonWord, '').contains(nm);
}

/// Кандидаты папок для подсчёта размера: (папка, запасной ли вариант).
/// InstallLocation → папка программы удаления → папка DisplayIcon.
List<({String dir, bool fallback})> _sizeCandidates(Program p,
    {Map<String, String> env = const {}, bool Function(String file)? fileExists}) {
  String? parent(String file) {
    final i = file.lastIndexOf(r'\');
    return i <= 0 ? null : file.substring(0, i);
  }

  final raw = <String?>[
    _expandEnv(p.installLocation.trim().replaceAll('"', ''), env),
    parseUninstallString(p.uninstallString, env: env, fileExists: fileExists)?.exe,
    parseDisplayIcon(p.displayIcon, env: env)?.path,
  ];
  final out = <({String dir, bool fallback})>[];
  for (var i = 0; i < raw.length; i++) {
    var c = raw[i];
    if (c == null || c.isEmpty) continue;
    if (i > 0) c = parent(c);
    if (c == null) continue;
    final n = normalizeWinPath(c);
    if (n == null) continue;
    out.add((dir: n, fallback: i > 0));
  }
  return out;
}

/// Папка для подсчёта размера программы без EstimatedSize: InstallLocation →
/// папка программы удаления → папка DisplayIcon; первая существующая и допустимая
/// ([isSizeableProgramFolder]). Нет подходящей — null (в списке «—»).
String? sizeFolderOf(Program p,
    {Map<String, String> env = const {},
    bool Function(String dir)? dirExists,
    bool Function(String file)? fileExists}) {
  final exists = dirExists ?? _defaultDirExists;
  for (final c in _sizeCandidates(p, env: env, fileExists: fileExists)) {
    if (!isSizeableProgramFolder(c.dir, p.name, env)) continue;
    if (exists(c.dir)) return c.dir;
  }
  return null;
}

String _key(String path) => path_pkg.windows.normalize(path).toLowerCase();

/// Папка, которую нельзя считать размером программы: кэш установщиков
/// (ProgramData\Package Cache) и папка Steam целиком.
bool isForbiddenSizeFolder(String dir, Map<String, String> env, String? steamPath) {
  final w = path_pkg.windows;
  final n = normalizeWinPath(dir);
  if (n == null) return true;
  final lower = {for (final e in env.entries) e.key.toLowerCase(): e.value};
  final pd = normalizeWinPath(lower['programdata'] ?? r'C:\ProgramData');
  if (pd != null) {
    final cache = w.join(pd, 'Package Cache');
    if (w.equals(cache, n) || w.isWithin(cache, n)) return true;
  }
  final parts = w.split(n).map((e) => e.toLowerCase()).toList();
  for (var i = 0; i + 1 < parts.length; i++) {
    if (parts[i] == 'programdata' && parts[i + 1] == 'package cache') return true;
  }
  final steam = steamPath == null ? null : normalizeWinPath(steamPath);
  if (steam != null && w.equals(steam, n)) return true;
  return false;
}

/// План подсчёта размеров: keyPath программы → папка. Правила:
/// запасные варианты (папка программы удаления, DisplayIcon) берутся, только если
/// эту папку не использует больше одной программы списка; никогда — Package Cache,
/// папка Steam целиком и папка, внутри которой лежит InstallLocation другой программы.
Map<String, String> planProgramSizeFolders(
  List<Program> all, {
  Map<String, String> env = const {},
  String? steamPath,
  bool Function(String dir)? dirExists,
  bool Function(String file)? fileExists,
}) {
  final exists = dirExists ?? _defaultDirExists;
  final w = path_pkg.windows;
  final cands = {
    for (final p in all) p.keyPath: _sizeCandidates(p, env: env, fileExists: fileExists)
  };
  // сколько программ используют папку (любым способом)
  final users = <String, Set<String>>{};
  for (final e in cands.entries) {
    for (final c in e.value) {
      (users[_key(c.dir)] ??= {}).add(e.key);
    }
  }
  final installs = <(String, String)>[]; // (keyPath, installLocation normalized)
  for (final p in all) {
    final n = normalizeWinPath(_expandEnv(p.installLocation.trim().replaceAll('"', ''), env));
    if (n != null) installs.add((p.keyPath, n));
  }
  final out = <String, String>{};
  for (final p in all) {
    if (p.sizeKb > 0) continue;
    for (final c in cands[p.keyPath]!) {
      if (!isSizeableProgramFolder(c.dir, p.name, env)) continue;
      if (isForbiddenSizeFolder(c.dir, env, steamPath)) continue;
      if (c.fallback && (users[_key(c.dir)]?.length ?? 0) > 1) continue;
      final holdsOther =
          installs.any((i) => i.$1 != p.keyPath && w.isWithin(c.dir, i.$2));
      if (holdsOther) continue;
      if (!exists(c.dir)) continue;
      out[p.keyPath] = c.dir;
      break;
    }
  }
  return out;
}
