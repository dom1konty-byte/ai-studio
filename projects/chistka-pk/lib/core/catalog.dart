import 'dart:io';

import 'models.dart';

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

List<CleanTarget> _chromium(String userData) {
  final res = <CleanTarget>[];
  final profiles = _subdirs(
    userData,
    (n) => n == 'Default' || n.startsWith('Profile '),
  );
  for (final prof in profiles) {
    for (final c in const ['Cache', 'Code Cache', 'GPUCache']) {
      res.add(CleanTarget(_join(prof, c)));
    }
  }
  return res;
}

/// Собирает список категорий по существующим папкам.
/// Основные 5 категорий есть всегда; «Программы» — только если папка найдена.
List<Category> buildCatalog(Env env, {String? steamPath}) {
  final local = env['LOCALAPPDATA'];
  final roaming = env['APPDATA'];
  final temp = env['TEMP'];
  final sysRoot = env['SystemRoot'] ?? env['WINDIR'];

  List<CleanTarget> only(Iterable<CleanTarget> all) =>
      all.where((t) => _exists(t.dir)).toList();

  final tempT = <CleanTarget>[
    if (temp != null) CleanTarget(temp),
    if (sysRoot != null) CleanTarget(_join(sysRoot, 'Temp')),
  ];

  final browsers = <CleanTarget>[];
  if (local != null) {
    browsers
      ..addAll(_chromium(_join(local, r'Google\Chrome\User Data')))
      ..addAll(_chromium(_join(local, r'Microsoft\Edge\User Data')))
      ..addAll(_chromium(_join(local, r'Yandex\YandexBrowser\User Data')));
    for (final prof in _subdirs(_join(local, r'Mozilla\Firefox\Profiles'), (_) => true)) {
      browsers.add(CleanTarget(_join(prof, 'cache2')));
    }
  }

  final thumbs = <CleanTarget>[
    if (local != null)
      CleanTarget(
        _join(local, r'Microsoft\Windows\Explorer'),
        filePattern: RegExp(r'^(thumbcache|iconcache)_.*\.db$', caseSensitive: false),
      ),
  ];

  final logs = <CleanTarget>[
    if (local != null) ...[
      CleanTarget(_join(local, 'CrashDumps')),
      CleanTarget(_join(local, r'Microsoft\Windows\WER\ReportArchive')),
      CleanTarget(_join(local, r'Microsoft\Windows\WER\ReportQueue')),
    ],
    if (sysRoot != null)
      CleanTarget(
        _join(sysRoot, r'Logs\CBS'),
        filePattern: RegExp(r'\.log$', caseSensitive: false),
      ),
  ];

  final steam = steamPath ?? r'C:\Program Files (x86)\Steam';

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
          CleanTarget(_join(roaming, r'Telegram Desktop\tdata\user_data\cache')),
          CleanTarget(_join(roaming, r'Telegram Desktop\tdata\user_data\media_cache')),
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
            CleanTarget(_join(roaming, 'discord\\$c')),
      ]),
    ),
    Category(
      id: CategoryId.steam,
      title: 'Steam',
      hint: 'Кэш шейдеров и логи (нужны права на папку Steam)',
      isProgram: true,
      targets: only([
        CleanTarget(_join(steam, r'steamapps\shadercache')),
        CleanTarget(_join(steam, 'logs')),
      ]),
    ),
    Category(
      id: CategoryId.spotify,
      title: 'Spotify',
      hint: 'Кэш Spotify',
      isProgram: true,
      targets: only([
        if (local != null) CleanTarget(_join(local, r'Spotify\Data')),
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
            CleanTarget(_join(roaming, 'Code\\$c')),
      ]),
    ),
    Category(
      id: CategoryId.gpu,
      title: 'Видеокарта',
      hint: 'Кэш шейдеров NVIDIA / AMD',
      isProgram: true,
      targets: only([
        if (local != null) ...[
          CleanTarget(_join(local, r'NVIDIA\DXCache')),
          CleanTarget(_join(local, r'NVIDIA\GLCache')),
          CleanTarget(_join(local, r'AMD\DxCache')),
          CleanTarget(_join(local, r'AMD\DxcCache')),
          CleanTarget(_join(local, r'AMD\GLCache')),
        ],
      ]),
    ),
  ];

  return [...cats, ...programs.where((c) => c.targets.isNotEmpty)];
}
