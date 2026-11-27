/// Остатки после удаления программы: нормализация имён, чёрный список,
/// поиск (папки, ярлыки, реестр), безопасное удаление. Доступ к диску и
/// реестру — через передаваемые функции (в тестах подменяются).
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../platform/platform_api.dart';
import 'catalog.dart' show Env;
import 'journal.dart';
import 'models.dart';
import 'target_guard.dart';
import 'whitelist.dart';

final p.Context _win = p.windows;

// ---------- нормализация имён ----------

String _cleanName(String s) {
  var t = s.toLowerCase();
  t = t.replaceAll(
      RegExp(r'\(\s*(?:x64|x86|amd64|64[\s-]?bit|32[\s-]?bit)\s*\)'), ' ');
  t = t.replaceAll(
      RegExp(r'\b(?:x64|x86|amd64|win64|win32|64[\s-]?bit|32[\s-]?bit)\b'), ' ');
  t = t.replaceAll(RegExp(r'\bv?\d+(?:\.\d+)+\b'), ' ');
  t = t.replaceAll(RegExp(r'(?<=\S)\s+v?\d+\s*$'), ' ');
  return t;
}

String _stripSeparators(String s) => s.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// Имя без версий, «x64», «(64-bit)», регистра, пробелов, дефисов и знаков.
/// «7-Zip 23.01 (x64)» → «7zip».
String normalizeName(String s) => _stripSeparators(_cleanName(s));

/// Издатель: то же, плюс без «Inc», «LLC», «Ltd», «ООО» и т.п.
String normalizePublisher(String s) {
  final t = s.toLowerCase().replaceAll(RegExp(r'[,.]'), ' ').replaceAll(
      RegExp(
          r'(?<![\p{L}\p{N}])(?:inc|llc|ltd|corp|corporation|gmbh|co|company|limited|incorporated|ooo|ооо|zao|зао|ао)(?![\p{L}\p{N}])',
          unicode: true),
      ' ');
  return normalizeName(t);
}

/// Нормализованные имя, издатель и первое слово имени.
class NameKey {
  NameKey(String name, String publisher)
      : name = normalizeName(name),
        publisher = normalizePublisher(publisher),
        firstToken = _firstToken(name);

  final String name;
  final String publisher;
  final String firstToken;

  /// Токены короче 3 символов не ищем.
  bool get nameSearchable => name.length >= 3;
  bool get publisherSearchable => publisher.length >= 3;

  static String _firstToken(String name) {
    final parts = _cleanName(name)
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((e) => e.isNotEmpty);
    return parts.isEmpty ? '' : parts.first;
  }
}

enum MatchLevel { none, possible, exact }

// ---------- чёрный список ----------

const _blacklistRaw = <String>[
  'Microsoft', 'Windows', 'Common Files', 'Google', 'Mozilla', 'NVIDIA',
  'NVIDIA Corporation', 'Intel', 'AMD', 'Packages', 'Programs', 'Temp',
  'WindowsApps', 'Microsoft Shared', 'Package Cache', 'Installer', 'Classes',
  'Policies', 'Wow6432Node', 'ChistoDisk', 'ЧистоДиск', 'Internet Explorer',
  'Windows NT', 'WindowsPowerShell', 'ModifiableWindowsApps', 'Uninstall Information',
  'Reference Assemblies', 'dotnet', 'MSBuild', 'Application Data', 'Desktop',
  'Start Menu', 'Startup', 'Accessories', 'Administrative Tools', 'System Tools',
  'Maintenance', 'Microsoft Edge', 'Edge', 'EdgeWebView', 'OneDrive', 'Adobe',
  'Apple', 'Apple Computer', 'Realtek', 'Qualcomm', 'Dell', 'HP', 'Lenovo', 'ASUS',
  'Oracle', 'Java', 'Clients', 'RegisteredApplications', 'ODBC', 'Software',
  'Local', 'LocalLow', 'Roaming', 'Users', 'Default', 'Public', 'Program Files',
  'Program Files (x86)', 'ProgramData', 'AppData', 'CrashDumps', 'D3DSCache',
  'Comms', 'ConnectedDevicesPlatform', 'PeerDistRepub', 'VirtualStore', 'Diagnostics',
  'SystemApps', 'System32', 'SysWOW64', 'Fonts', 'Drivers', 'Cryptography', 'Sun',
];

final Set<String> _blacklist = {for (final n in _blacklistRaw) _stripSeparators(n.toLowerCase())};

/// Имя папки/ключа, которое НИКОГДА не предлагается к удалению.
/// Включает всё, что начинается с «Windows» или «Microsoft».
bool isBlacklistedName(String name) {
  final n = _stripSeparators(name.toLowerCase());
  if (n.isEmpty) return true;
  if (_blacklist.contains(n)) return true;
  return n.startsWith('windows') ||
      n.startsWith('microsoft') ||
      n.startsWith('chistodisk') ||
      n.startsWith('чистодиск');
}

bool _isContainerName(String name) => _stripSeparators(name.toLowerCase()) == 'programs';

// ---------- сопоставление ----------

/// Насколько имя [candidate] (папки, ярлыка без расширения, ключа) подходит
/// под имя программы. Имя из чёрного списка и короткое имя (<3) → none.
MatchLevel matchName(String candidate, NameKey k) {
  if (isBlacklistedName(candidate)) return MatchLevel.none;
  final n = normalizeName(candidate);
  if (n.length < 3 || !k.nameSearchable) return MatchLevel.none;
  if (n == k.name) return MatchLevel.exact;
  if (k.firstToken.length >= 4 && n == _stripSeparators(k.firstToken)) {
    return MatchLevel.possible;
  }
  if (n.length > k.name.length && n.contains(k.name)) return MatchLevel.possible;
  if (n.length >= 5 && n.length < k.name.length && k.name.contains(n)) {
    return MatchLevel.possible;
  }
  return MatchLevel.none;
}

/// Совпадает ли имя папки с издателем целиком.
bool matchesPublisher(String candidate, NameKey k) {
  if (!k.publisherSearchable || isBlacklistedName(candidate)) return false;
  return normalizePublisher(candidate) == k.publisher;
}

// ---------- модели ----------

enum LeftoverKind { folder, shortcut, registry }

class Leftover {
  Leftover({
    required this.kind,
    required this.path,
    required this.exact,
    this.isDir = false,
    this.bytes = 0,
    this.deletable = true,
    this.isUninstallEntry = false,
    this.note,
    this.preselect = true,
  });

  final LeftoverKind kind;

  /// Путь на диске или полный путь ключа реестра (`HKCU\Software\X`).
  final String path;
  final bool exact;
  final bool isDir;
  int bytes;

  /// false — только показ (HKLM).
  final bool deletable;

  /// Запись самой программы в списке Uninstall (принудительное удаление).
  final bool isUninstallEntry;

  /// Пометка в списке (например, «Общая папка издателя»).
  String? note;

  /// false — не отмечать автоматически (общая папка, может быть чужой).
  bool preselect;

  String get name => path.split(r'\').last;
}

class FsEntry {
  const FsEntry(this.name, {required this.isDir, this.isLink = false});
  final String name;
  final bool isDir;
  final bool isLink;
}

/// Другая установленная программа (для защиты от удаления чужих папок).
class OtherProgram {
  const OtherProgram(this.name, this.installLocation);
  final String name;
  final String installLocation;
}

typedef DirLister = Future<List<FsEntry>> Function(String dir);
typedef RegSubKeys = Future<List<String>> Function(String key);
typedef SizeOf = Future<int> Function(String path, bool isDir);

/// Реальный просмотр папки: ссылки помечаются, ошибки доступа → пусто.
Future<List<FsEntry>> listDirReal(String dir) async {
  final res = <FsEntry>[];
  try {
    await for (final e in Directory(dir).list(followLinks: false)) {
      final name = e.path.split(RegExp(r'[\\/]')).last;
      res.add(FsEntry(name, isDir: e is Directory, isLink: e is Link));
    }
  } catch (_) {}
  return res;
}

String _join(String a, String b) => a.endsWith(r'\') ? '$a$b' : '$a\\$b';

/// Корни поиска остатков по окружению (только безопасные пути).
class LeftoverRoots {
  LeftoverRoots(Env env) {
    List<String> pick(List<String> keys, {int minSegments = 2}) => [
          for (final k in keys)
            if (env[k] != null && isSafeCleanTarget(env[k]!, minSegments: minSegments))
              _win.normalize(env[k]!),
        ];
    folders = pick(['APPDATA', 'LOCALAPPDATA', 'ProgramData', 'ProgramFiles', 'ProgramFiles(x86)']);
    final appdata = env['APPDATA'];
    final pdata = env['ProgramData'];
    final profile = env['USERPROFILE'];
    final pub = env['PUBLIC'];
    final od = env['OneDrive'];
    startMenus = [
      if (appdata != null) _join(appdata, r'Microsoft\Windows\Start Menu\Programs'),
      if (pdata != null) _join(pdata, r'Microsoft\Windows\Start Menu\Programs'),
    ].where((e) => isSafeCleanTarget(e, minSegments: 3)).map(_win.normalize).toList();
    desktops = [
      if (profile != null) _join(profile, 'Desktop'),
      if (pub != null) _join(pub, 'Desktop'),
      if (od != null) _join(od, 'Desktop'),
    ].where((e) => isSafeCleanTarget(e, minSegments: 3)).map(_win.normalize).toList();
    userProfile = profile != null && isSafeCleanTarget(profile, minSegments: 3)
        ? _win.normalize(profile)
        : null;
  }

  late final List<String> folders;
  late final List<String> startMenus;
  late final List<String> desktops;
  late final String? userProfile;

  /// Каталоги, внутри которых можно удалять (строго внутри).
  List<String> get allowed => [...folders, ...startMenus, ...desktops];

  /// Эти пути и их родители не удаляются никогда.
  List<String> get protected => [...allowed, ?userProfile];

  /// Корни, где для удаления обычно нужны права администратора.
  List<String> adminRoots(Env env) => [
        for (final k in ['ProgramFiles', 'ProgramFiles(x86)', 'ProgramData'])
          if (env[k] != null) _win.normalize(env[k]!),
        if (env['PUBLIC'] != null) _win.normalize(env['PUBLIC']!),
      ];
}

/// Путь можно предлагать: строго внутри корня, не корень и не родитель корня,
/// последнее имя не в чёрном списке.
bool isOfferablePath(String path, LeftoverRoots roots) {
  final n = normalizeWinPath(path);
  if (n == null) return false;
  if (!isInsideAllowedRoot(n, roots.allowed)) return false;
  for (final pr in roots.protected) {
    final np = normalizeWinPath(pr);
    if (np == null) continue;
    if (_win.equals(np, n) || _win.isWithin(n, np)) return false;
  }
  if (isBlacklistedName(_win.basename(n))) return false;
  return true;
}

// ---------- поиск ----------

/// Ищет остатки программы. [name]/[publisher]/[installLocation] — из списка программ.
Future<List<Leftover>> findLeftovers({
  required String name,
  required String publisher,
  required String installLocation,
  required Env env,
  required DirLister listDir,
  required RegSubKeys regSubKeys,
  required SizeOf sizeOf,
  List<OtherProgram> otherPrograms = const [],
}) async {
  final k = NameKey(name, publisher);
  final roots = LeftoverRoots(env);
  final found = <String, Leftover>{};

  void add(Leftover l) {
    final key = l.path.toLowerCase();
    final old = found[key];
    if (old == null || (!old.exact && l.exact)) found[key] = l;
  }

  if (!k.nameSearchable && !k.publisherSearchable) return [];

  // Папки: 1–2 уровень вложенности.
  for (final root in roots.folders) {
    for (final e1 in await listDir(root)) {
      if (!e1.isDir || e1.isLink) continue;
      final path1 = _join(root, e1.name);
      final black = isBlacklistedName(e1.name);
      if (!black) {
        final m = matchName(e1.name, k);
        if (m != MatchLevel.none) {
          add(Leftover(
              kind: LeftoverKind.folder,
              path: path1,
              isDir: true,
              exact: m == MatchLevel.exact));
        } else if (matchesPublisher(e1.name, k)) {
          add(Leftover(
              kind: LeftoverKind.folder,
              path: path1,
              isDir: true,
              exact: false,
              note: sharedPublisherNote,
              preselect: false));
        }
      }
      if (black && !_isContainerName(e1.name)) continue; // в Microsoft, Common Files и т.п. не заходим
      for (final e2 in await listDir(path1)) {
        if (!e2.isDir || e2.isLink) continue;
        final m = matchName(e2.name, k);
        if (m != MatchLevel.none) {
          add(Leftover(
              kind: LeftoverKind.folder,
              path: _join(path1, e2.name),
              isDir: true,
              exact: m == MatchLevel.exact));
        }
      }
    }
  }

  // InstallLocation, если он внутри корней: точное совпадение.
  final il = installLocation.trim().replaceAll('"', '');
  if (il.isNotEmpty) {
    final n = normalizeWinPath(il);
    if (n != null && _insideAny(n, roots.folders) && isOfferablePath(n, roots)) {
      final parent = _win.dirname(n);
      final base = _win.basename(n);
      final list = await listDir(parent);
      final hit = list.where((e) => e.name.toLowerCase() == base.toLowerCase()).toList();
      if (hit.isNotEmpty && hit.first.isDir && !hit.first.isLink) {
        add(Leftover(kind: LeftoverKind.folder, path: n, isDir: true, exact: true));
      }
    }
  }

  // Ярлыки: меню Пуск (1–2 уровень) и рабочие столы (1 уровень).
  for (final root in roots.startMenus) {
    for (final e1 in await listDir(root)) {
      if (e1.isLink) continue;
      final path1 = _join(root, e1.name);
      if (e1.isDir) {
        final m = matchName(e1.name, k);
        if (m != MatchLevel.none) {
          add(Leftover(
              kind: LeftoverKind.shortcut,
              path: path1,
              isDir: true,
              exact: m == MatchLevel.exact));
          continue; // внутри уже найденной папки не ищем
        }
        if (isBlacklistedName(e1.name)) continue;
        for (final e2 in await listDir(path1)) {
          if (e2.isLink || e2.isDir) continue;
          _addLnk(add, k, path1, e2.name);
        }
      } else {
        _addLnk(add, k, root, e1.name);
      }
    }
  }
  for (final root in roots.desktops) {
    for (final e in await listDir(root)) {
      if (e.isLink || e.isDir) continue;
      _addLnk(add, k, root, e.name);
    }
  }

  // Реестр: Software\<Имя>, Software\<Издатель>\<Имя>.
  Future<void> regScan(String root, bool deletable) async {
    List<String> top;
    try {
      top = await regSubKeys(root);
    } catch (_) {
      return;
    }
    for (final t in top) {
      if (isBlacklistedName(t)) continue;
      final m = matchName(t, k);
      final key1 = '$root\\$t';
      if (m != MatchLevel.none) {
        add(Leftover(
            kind: LeftoverKind.registry,
            path: key1,
            exact: m == MatchLevel.exact,
            deletable: deletable,
            note: deletable ? null : 'Нужны права администратора'));
      } else if (matchesPublisher(t, k)) {
        List<String> sub;
        try {
          sub = await regSubKeys(key1);
        } catch (_) {
          continue;
        }
        for (final s in sub) {
          final m2 = matchName(s, k);
          if (m2 == MatchLevel.none) continue;
          add(Leftover(
              kind: LeftoverKind.registry,
              path: '$key1\\$s',
              exact: m2 == MatchLevel.exact,
              deletable: deletable,
              note: deletable ? null : 'Нужны права администратора'));
        }
      }
    }
  }

  if (k.nameSearchable || k.publisherSearchable) {
    await regScan(r'HKCU\Software', true);
    await regScan(r'HKLM\SOFTWARE', false);
    await regScan(r'HKLM\SOFTWARE\WOW6432Node', false);
  }

  final res = found.values.toList();
  markShared(res, k, otherPrograms);
  for (final l in res) {
    if (l.kind != LeftoverKind.registry) {
      try {
        l.bytes = await sizeOf(l.path, l.isDir);
      } catch (_) {}
    }
  }
  // Только то, что проходит проверки предложения (корни, чёрный список).
  final ok = res
      .where((l) => l.kind == LeftoverKind.registry
          ? isSafeRegistryPath(l.path)
          : isOfferablePath(l.path, roots))
      .toList()
    ..sort((a, b) {
      if (a.exact != b.exact) return a.exact ? -1 : 1;
      final c = a.kind.index.compareTo(b.kind.index);
      return c != 0 ? c : a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
  return ok;
}

const sharedPublisherNote = 'Общая папка издателя';

/// Пометка «может принадлежать другой программе»: в списке есть другая программа
/// с тем же нормализованным именем, либо её InstallLocation совпадает с найденным
/// путём, лежит внутри него или найденный путь лежит внутри InstallLocation.
/// Такие находки не отмечаются заранее. Пометка издателя не затирается.
void markShared(List<Leftover> items, NameKey k, List<OtherProgram> others) {
  if (others.isEmpty) return;
  OtherProgram? sameName;
  for (final o in others) {
    final n = normalizeName(o.name);
    if (n.isNotEmpty && n == k.name) {
      sameName = o;
      break;
    }
  }
  final locs = <(OtherProgram, String)>[];
  for (final o in others) {
    final il = normalizeWinPath(o.installLocation.trim().replaceAll('"', ''));
    if (il != null) locs.add((o, il));
  }
  for (final l in items) {
    OtherProgram? owner = sameName;
    if (owner == null && l.kind != LeftoverKind.registry) {
      final np = normalizeWinPath(l.path);
      if (np != null) {
        for (final (o, il) in locs) {
          if (_win.equals(np, il) || _win.isWithin(np, il) || _win.isWithin(il, np)) {
            owner = o;
            break;
          }
        }
      }
    }
    if (owner == null) continue;
    l.preselect = false;
    if (l.note != sharedPublisherNote) {
      l.note = 'Может принадлежать другой программе: ${owner.name}';
    }
  }
}

bool _insideAny(String path, List<String> roots) => isInsideAllowedRoot(path, roots);

void _addLnk(void Function(Leftover) add, NameKey k, String dir, String fileName) {
  if (!fileName.toLowerCase().endsWith('.lnk')) return;
  final base = fileName.substring(0, fileName.length - 4);
  final m = matchName(base, k);
  if (m == MatchLevel.none) return;
  add(Leftover(
      kind: LeftoverKind.shortcut,
      path: _join(dir, fileName),
      exact: m == MatchLevel.exact));
}

// ---------- реестр: проверки ----------

/// Только показ: корректный путь HKCU\… / HKLM\… без служебных символов.
bool isSafeRegistryPath(String key) {
  if (RegExp(r'[*?"<>|\x00-\x1f]').hasMatch(key)) return false;
  final segs = key.split(r'\');
  if (segs.length < 3) return false;
  if (segs.any((s) => s.isEmpty || s == '.' || s == '..')) return false;
  final hive = segs.first.toUpperCase();
  if (hive != 'HKCU' && hive != 'HKLM') return false;
  return !isBlacklistedName(segs[2]) || (segs[2].toLowerCase() == 'wow6432node' && segs.length >= 4 && !isBlacklistedName(segs[3]));
}

const _uninstallPrefix = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall';

/// Можно ли удалять ключ. Только HKCU\Software\… (глубина ≥ 3, имя не из чёрного
/// списка); запись Uninstall — только `HKCU\…\Uninstall\<имя>` ровно на один уровень.
bool isSafeRegDeleteKey(String key, {bool uninstallEntry = false}) {
  if (RegExp(r'[*?"<>|\x00-\x1f]').hasMatch(key)) return false;
  final segs = key.split(r'\');
  if (segs.any((s) => s.isEmpty || s == '.' || s == '..')) return false;
  if (uninstallEntry) {
    final pre = _uninstallPrefix.split(r'\');
    if (segs.length != pre.length + 1) return false;
    for (var i = 0; i < pre.length; i++) {
      if (segs[i].toLowerCase() != pre[i].toLowerCase()) return false;
    }
    return true;
  }
  if (segs.length < 3) return false;
  if (segs[0].toUpperCase() != 'HKCU' || segs[1].toLowerCase() != 'software') return false;
  if (isBlacklistedName(segs[2]) || isBlacklistedName(segs.last)) return false;
  return true;
}

// ---------- удаление ----------

class LeftoverOutcome {
  const LeftoverOutcome(this.item, this.ok, this.message);
  final Leftover item;
  final bool ok;
  final String message;
}

/// Проверка пути перед отправкой в Корзину (null — можно). Реальная реализация:
/// не ссылка, файл или папка без ссылок внутри, цепочка от корня без ссылок.
typedef PathGuard = FutureOr<String?> Function(String path, String root, bool isDir);

/// Та же проверка, но обход папки идёт в отдельном Isolate (окно не зависает).
Future<String?> realPathGuardAsync(String path, String root, bool isDir) async {
  try {
    return await Isolate.run(() => realPathGuard(path, root, isDir));
  } catch (_) {
    return 'не удалось проверить';
  }
}

String? realPathGuard(String path, String root, bool isDir) {
  try {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.link) return 'это ссылка';
    if (type == FileSystemEntityType.notFound) return 'уже нет';
    if (isDir) {
      if (type != FileSystemEntityType.directory) return 'не папка';
      final r = targetRejectReason(CleanTarget(path, base: root, minSegments: 3));
      if (r != null) return r;
      for (final e in Directory(path).listSync(recursive: true, followLinks: false)) {
        if (e is Link) return 'внутри есть ссылка';
      }
    } else {
      if (type != FileSystemEntityType.file) return 'не файл';
      final r = targetRejectReason(
          CleanTarget(_win.dirname(path), base: root, minSegments: 2));
      if (r != null) return r;
    }
  } catch (_) {
    return 'не удалось проверить';
  }
  return null;
}

/// Удаляет остатки: файлы и папки — только в Корзину, реестр HKCU — только
/// после успешного экспорта .reg. Всё пишется в журнал.
class LeftoverCleaner {
  LeftoverCleaner({
    required this.platform,
    required this.log,
    required this.env,
    required this.backupDir,
    PathGuard? guard,
    DateTime Function()? now,
  })  : guard = guard ?? realPathGuardAsync,
        now = now ?? DateTime.now;

  final PlatformApi platform;
  final CleanLog log;
  final Env env;
  final String backupDir;
  final PathGuard guard;
  final DateTime Function() now;

  static const category = 'Остатки программ';

  String backupFileName(String key) {
    final segs = key.split(r'\');
    final tail = segs.skip(segs.length > 2 ? segs.length - 2 : 0).join('_');
    var safe = tail.replaceAll(RegExp(r'[^\p{L}\p{N}._-]', unicode: true), '_');
    if (safe.length > 60) safe = safe.substring(0, 60);
    final d = now();
    String t(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${t(d.month)}${t(d.day)}-${t(d.hour)}${t(d.minute)}${t(d.second)}_$safe.reg';
  }

  Future<List<LeftoverOutcome>> run(List<Leftover> items,
      {void Function(String text)? onProgress}) async {
    final roots = LeftoverRoots(env);
    final admin = roots.adminRoots(env);
    final out = <LeftoverOutcome>[];
    final fsOk = <Leftover>[];

    Future<void> fail(Leftover l, String msg) async {
      out.add(LeftoverOutcome(l, false, msg));
      await log.add(category, l.path, l.bytes, msg);
    }

    final fsItems = items.where((l) => l.kind != LeftoverKind.registry).toList();
    // вложенное внутри другого выбранного отдельно не отправляем: заберёт верхний
    Leftover? coveringParent(Leftover l) {
      Leftover? best;
      for (final o in fsItems) {
        if (identical(o, l)) continue;
        if (_win.isWithin(_win.normalize(o.path), _win.normalize(l.path)) &&
            (best == null || o.path.length < best.path.length)) {
          best = o;
        }
      }
      return best;
    }

    final nested = <Leftover, Leftover>{};
    for (final l in fsItems) {
      final parent = coveringParent(l);
      if (parent != null) {
        nested[l] = parent;
        continue;
      }
      if (!isOfferablePath(l.path, roots)) {
        await fail(l, 'пропущено (путь не разрешён)');
        continue;
      }
      if (!isSafeCleanTarget(l.path, minSegments: 3)) {
        await fail(l, 'пропущено (небезопасный путь)');
        continue;
      }
      final root = roots.allowed.firstWhere(
        (r) => isInsideAllowedRoot(l.path, [r]),
        orElse: () => '',
      );
      onProgress?.call('Проверяю: ${l.name}');
      final reason = await guard(l.path, root, l.isDir);
      if (reason != null) {
        await fail(l, 'пропущено ($reason)');
        continue;
      }
      fsOk.add(l);
    }
    // По одной папке, между ними — await: окно успевает перерисоваться.
    var done = 0;
    for (final l in fsOk) {
      onProgress?.call('Удаляю остатки… ${++done} из ${fsOk.length}');
      Map<String, String?> res;
      try {
        res = await platform.moveToRecycleBin([l.path]);
      } catch (_) {
        res = {l.path: 'ошибка вызова Windows'};
      }
      if (res.containsKey(l.path) && res[l.path] == null) {
        out.add(LeftoverOutcome(l, true, 'в Корзину'));
        await log.add(category, l.path, l.bytes, 'в Корзину');
      } else {
        final needAdmin = admin.any((a) => isInsideAllowedRoot(l.path, [a]));
        final msg = needAdmin
            ? 'пропущено (нужны права администратора)'
            : 'пропущено: ${res[l.path] ?? 'нет ответа'}';
        await fail(l, msg);
      }
      await Future<void>.delayed(Duration.zero);
    }
    for (final e in nested.entries) {
      final parentOk = out.any((o) => o.ok && identical(o.item, e.value));
      out.add(LeftoverOutcome(
          e.key,
          parentOk,
          parentOk ? 'в Корзину (вместе с папкой выше)' : 'пропущено (папка выше не удалена)'));
    }

    for (final l in items.where((l) => l.kind == LeftoverKind.registry)) {
      if (!l.deletable) {
        await fail(l, 'пропущено (нужны права администратора)');
        continue;
      }
      if (!isSafeRegDeleteKey(l.path, uninstallEntry: l.isUninstallEntry)) {
        await fail(l, 'пропущено (ключ не разрешён)');
        continue;
      }
      final file = p.join(backupDir, backupFileName(l.path));
      bool exported;
      try {
        await Directory(backupDir).create(recursive: true);
        exported = await platform.exportRegKey(l.path, file);
      } catch (_) {
        exported = false;
      }
      if (!exported) {
        await fail(l, 'не удалено: резервная копия не создана');
        continue;
      }
      bool deleted;
      try {
        deleted = await platform.deleteRegKey(l.path);
      } catch (_) {
        deleted = false;
      }
      if (deleted) {
        out.add(LeftoverOutcome(l, true, 'удалено (копия: $file)'));
        await log.add(category, l.path, 0, 'реестр удалён, копия: $file');
      } else {
        await fail(l, 'не удалено (ошибка reg.exe), копия: $file');
      }
    }
    await log.flush();
    return out;
  }
}
