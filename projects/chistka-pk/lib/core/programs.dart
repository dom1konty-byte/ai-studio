/// Список установленных программ (реестр Uninstall): модель, фильтр, разбор
/// строки удаления, поиск и сортировка. Чистые функции — без обращения к системе.
library;

import 'dart:io';

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
List<Program> filterAndSort(List<Program> all, String query, ProgramSort sort) {
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
        final c = b.sizeKb.compareTo(a.sizeKb);
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

/// «Всего программ: 142 · 38,6 ГБ»: число и сумма EstimatedSize показанных программ
/// (размер не пишем, если ни у одной он не указан).
String programsSummary(List<Program> shown) {
  final total = shown.fold<int>(0, (a, p) => a + p.sizeBytes);
  final base = 'Всего программ: ${shown.length}';
  return total > 0 ? '$base · ${formatSize(total)}' : base;
}
