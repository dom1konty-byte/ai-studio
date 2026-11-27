import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';
import 'target_guard.dart';
import 'whitelist.dart';

/// Переменные окружения (подменяются в тестах).
class Env {
  const Env(this.vars);
  factory Env.system() => Env(Platform.environment);
  final Map<String, String> vars;

  String? operator [](String key) {
    final v = vars[key] ?? vars[key.toUpperCase()];
    return (v == null || v.isEmpty) ? null : v;
  }
}

String _join(String a, String b) => a.endsWith(r'\') ? '$a$b' : '$a\\$b';

List<String> _subdirs(String dir, bool Function(String name) test) {
  try {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    final res = <String>[];
    for (final e in d.listSync(followLinks: false)) {
      if (e is Directory) {
        final name = e.path.split(RegExp(r'[\\/]')).last;
        if (test(name)) res.add(e.path);
      }
    }
    return res;
  } catch (_) {
    return const [];
  }
}

bool _exists(String dir) {
  try {
    return Directory(dir).existsSync();
  } catch (_) {
    return false;
  }
}


/// Папки, которые нельзя чистить целиком и предком которых цель быть не может.
List<String> protectedPathsOf(Env env) {
  final res = <String>[];
  final profile = env['USERPROFILE'];
  if (profile != null) {
    res.add(profile);
    for (final d in const ['Documents', 'Desktop', 'Downloads', 'Pictures']) {
      res.add(_join(profile, d));
    }
  }
  for (final k in const ['OneDrive', 'OneDriveConsumer', 'OneDriveCommercial']) {
    final od = env[k];
    if (od != null) {
      res.add(od);
      for (final d in const ['Documents', 'Desktop', 'Downloads', 'Pictures']) {
        res.add(_join(od, d));
      }
    }
  }
  for (final k in const ['SystemRoot', 'WINDIR', 'ProgramFiles', 'ProgramFiles(x86)', 'ProgramW6432']) {
    final v = env[k];
    if (v != null) res.add(v);
  }
  return res;
}

/// Корень диска системы (из SystemRoot), например `C:\`.
String systemDriveRoot(Env env) {
  final sr = env['SystemRoot'] ?? env['WINDIR'];
  final m = sr == null ? null : RegExp(r'^([A-Za-z]):').firstMatch(sr);
  if (m != null) return '${m.group(1)!.toUpperCase()}:\\';
  final sd = env['SystemDrive'];
  final m2 = sd == null ? null : RegExp(r'^([A-Za-z]):').firstMatch(sd);
  if (m2 != null) return '${m2.group(1)!.toUpperCase()}:\\';
  return r'C:\';
}

/// Папка Temp пользователя: TEMP принимается, только если это %LOCALAPPDATA%\Temp
/// (или подпапка) либо папка с именем Temp внутри %USERPROFILE%\AppData\Local.
/// Иначе — %LOCALAPPDATA%\Temp. Нет подходящего — null.
({String dir, String base})? resolveUserTemp(Env env) {
  final local = env['LOCALAPPDATA'];
  final profile = env['USERPROFILE'];
  final temp = env['TEMP'];
  final localTemp = local == null ? null : _join(local, 'Temp');
  final profLocal = profile == null ? null : _join(profile, r'AppData\Local');
  if (temp != null) {
    final n = normalizeWinPath(temp);
    if (n != null) {
      final w = p.windows;
      if (local != null && localTemp != null) {
        final nl = normalizeWinPath(localTemp);
        if (nl != null && (w.equals(nl, n) || w.isWithin(nl, n))) {
          return (dir: temp, base: local);
        }
      }
      if (profLocal != null) {
        final npl = normalizeWinPath(profLocal);
        if (npl != null &&
            w.basename(n).toLowerCase() == 'temp' &&
            w.isWithin(npl, n)) {
          return (dir: temp, base: profLocal);
        }
      }
    }
  }
  if (local != null && localTemp != null) return (dir: localTemp, base: local);
  return null;
}

/// SteamPath из реестра: только абсолютный `X:\…`, не UNC, существующая папка
/// с steam.exe, проходит защиту целей. Иначе null.
String? validSteamPath(
  String? raw,
  List<String> protectedPaths, {
  bool Function(String dir)? dirExists,
  bool Function(String file)? fileExists,
}) {
  if (raw == null) return null;
  final v = raw.trim().replaceAll('/', r'\');
  if (!RegExp(r'^[A-Za-z]:\\').hasMatch(v)) return null;
  if (!isSafeCleanTarget(v, protectedPaths: protectedPaths, minSegments: 2)) return null;
  final n = normalizeWinPath(v);
  if (n == null) return null;
  final dExists = dirExists ?? _exists;
  final fExists = fileExists ?? (f) => File(f).existsSync();
  try {
    if (!dExists(n) || !fExists(_join(n, 'steam.exe'))) return null;
  } catch (_) {
    return null;
  }
  return n;
}

List<CleanTarget> _chromium(String userData, CleanTarget Function(String dir) mk) {
  final res = <CleanTarget>[];
  final profiles = _subdirs(
    userData,
    (n) => n == 'Default' || n.startsWith('Profile '),
  );
  for (final prof in profiles) {
    for (final c in const ['Cache', 'Code Cache', 'GPUCache']) {
      res.add(mk(_join(prof, c)));
    }
  }
  return res;
}

/// Собирает список категорий по существующим папкам.
/// Основные 5 категорий есть всегда; «Программы» — только если папка найдена.
List<Category> buildCatalog(Env env, {String? steamPath}) {
  final prot = protectedPathsOf(env);
  String? safeBase(String? b) =>
      b != null && isSafeCleanTarget(b, protectedPaths: prot, minSegments: 3) ? b : null;
  final local = safeBase(env['LOCALAPPDATA']);
  final roaming = safeBase(env['APPDATA']);
  final sysRootRaw = env['SystemRoot'] ?? env['WINDIR'];
  final sysRoot = sysRootRaw != null &&
          isSafeCleanTarget(sysRootRaw, protectedPaths: const [], minSegments: 2) &&
          _exists(_join(sysRootRaw, 'System32'))
      ? sysRootRaw
      : null;
  final steam = validSteamPath(steamPath, prot);

  CleanTarget mk(String dir, String? base, {int min = 4, RegExp? pattern}) => CleanTarget(
        dir,
        filePattern: pattern,
        base: base,
        minSegments: min,
        protectedPaths: prot,
      );

  /// Оставляет существующие цели, прошедшие защиту.
  List<CleanTarget> only(Iterable<CleanTarget> all) =>
      all.where((t) => _exists(t.dir) && targetRejectReason(t) == null).toList();

  final userTemp = resolveUserTemp(env);
  final tempT = <CleanTarget>[
    if (userTemp != null) mk(userTemp.dir, userTemp.base),
    // системный Temp — ровно эта папка (в ней 3 сегмента: диск, Windows, Temp)
    if (sysRoot != null) mk(_join(sysRoot, 'Temp'), sysRoot, min: 3),
  ];

  final browsers = <CleanTarget>[];
  if (local != null) {
    CleanTarget lm(String d) => mk(d, local);
    browsers
      ..addAll(_chromium(_join(local, r'Google\Chrome\User Data'), lm))
      ..addAll(_chromium(_join(local, r'Microsoft\Edge\User Data'), lm))
      ..addAll(_chromium(_join(local, r'Yandex\YandexBrowser\User Data'), lm));
    for (final prof in _subdirs(_join(local, r'Mozilla\Firefox\Profiles'), (_) => true)) {
      browsers.add(mk(_join(prof, 'cache2'), local));
    }
  }

  final thumbs = <CleanTarget>[
    if (local != null)
      mk(
        _join(local, r'Microsoft\Windows\Explorer'),
        local,
        pattern: RegExp(r'^(thumbcache|iconcache)_.*\.db$', caseSensitive: false),
      ),
  ];

  final logs = <CleanTarget>[
    if (local != null) ...[
      mk(_join(local, 'CrashDumps'), local),
      mk(_join(local, r'Microsoft\Windows\WER\ReportArchive'), local),
      mk(_join(local, r'Microsoft\Windows\WER\ReportQueue'), local),
    ],
    if (sysRoot != null)
      mk(
        _join(sysRoot, r'Logs\CBS'),
        sysRoot,
        pattern: RegExp(r'\.log$', caseSensitive: false),
      ),
  ];

  final cats = <Category>[
    Category(
      id: CategoryId.temp,
      title: 'Временные файлы',
      hint: 'Папки Temp пользователя и Windows',
      targets: only(tempT),
    ),
    Category(
      id: CategoryId.browsers,
      title: 'Кэш браузеров',
      hint: 'Chrome, Edge, Firefox, Яндекс. Пароли и история не трогаются',
      targets: only(browsers),
    ),
    const Category(
      id: CategoryId.recycle,
      title: 'Корзина',
      hint: 'Всё, что лежит в Корзине',
      targets: [],
    ),
    Category(
      id: CategoryId.thumbs,
      title: 'Кэш миниатюр',
      hint: 'Миниатюры и значки Проводника',
      targets: only(thumbs),
    ),
    Category(
      id: CategoryId.logs,
      title: 'Логи',
      hint: 'Отчёты об ошибках, дампы, журналы Windows',
      targets: only(logs),
    ),
  ];

  final programs = <Category>[
    Category(
      id: CategoryId.telegram,
      title: 'Telegram',
      hint: 'Кэш Telegram Desktop',
      isProgram: true,
      targets: only([
        if (roaming != null) ...[
          mk(_join(roaming, r'Telegram Desktop\tdata\user_data\cache'), roaming),
          mk(_join(roaming, r'Telegram Desktop\tdata\user_data\media_cache'), roaming),
        ],
      ]),
    ),
    Category(
      id: CategoryId.discord,
      title: 'Discord',
      hint: 'Кэш Discord',
      isProgram: true,
      targets: only([
        if (roaming != null)
          for (final c in const ['Cache', 'Code Cache', 'GPUCache'])
            mk(_join(roaming, 'discord\\$c'), roaming),
      ]),
    ),
    Category(
      id: CategoryId.steam,
      title: 'Steam',
      hint: 'Кэш шейдеров и логи (нужны права на папку Steam)',
      isProgram: true,
      targets: only([
        if (steam != null) ...[
          mk(_join(steam, r'steamapps\shadercache'), steam, min: 3),
          mk(_join(steam, 'logs'), steam, min: 3),
        ],
      ]),
    ),
    Category(
      id: CategoryId.spotify,
      title: 'Spotify',
      hint: 'Кэш Spotify',
      isProgram: true,
      targets: only([
        if (local != null) mk(_join(local, r'Spotify\Data'), local),
      ]),
    ),
    Category(
      id: CategoryId.vscode,
      title: 'VS Code',
      hint: 'Кэш редактора',
      isProgram: true,
      targets: only([
        if (roaming != null)
          for (final c in const ['Cache', 'CachedData', 'Code Cache', 'GPUCache'])
            mk(_join(roaming, 'Code\\$c'), roaming),
      ]),
    ),
    Category(
      id: CategoryId.gpu,
      title: 'Видеокарта',
      hint: 'Кэш шейдеров NVIDIA / AMD',
      isProgram: true,
      targets: only([
        if (local != null) ...[
          mk(_join(local, r'NVIDIA\DXCache'), local),
          mk(_join(local, r'NVIDIA\GLCache'), local),
          mk(_join(local, r'AMD\DxCache'), local),
          mk(_join(local, r'AMD\DxcCache'), local),
          mk(_join(local, r'AMD\GLCache'), local),
        ],
      ]),
    ),
  ];

  return [...cats, ...programs.where((c) => c.targets.isNotEmpty)];
}
