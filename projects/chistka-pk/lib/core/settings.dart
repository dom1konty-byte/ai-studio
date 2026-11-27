import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Имя значения автозапуска ЧистоДиск в HKCU\…\Run. Удаляем только его.
const autostartValueName = 'ChistoDisk';
const autostartRunKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

/// Настройки в %LOCALAPPDATA%\ChistoDisk\settings.json.
class AppSettings {
  const AppSettings({
    this.autostart = false,
    this.minimizeToTray = true,
    this.trayHintShown = false,
    this.quickCategories = const [],
  });

  final bool autostart;
  final bool minimizeToTray;
  final bool trayHintShown;

  /// Категории, отмеченные при последней очистке (имена CategoryId).
  final List<String> quickCategories;

  AppSettings copyWith({
    bool? autostart,
    bool? minimizeToTray,
    bool? trayHintShown,
    List<String>? quickCategories,
  }) =>
      AppSettings(
        autostart: autostart ?? this.autostart,
        minimizeToTray: minimizeToTray ?? this.minimizeToTray,
        trayHintShown: trayHintShown ?? this.trayHintShown,
        quickCategories: quickCategories ?? this.quickCategories,
      );

  Map<String, Object?> toJson() => {
        'autostart': autostart,
        'minimizeToTray': minimizeToTray,
        'trayHintShown': trayHintShown,
        'quickCategories': quickCategories,
      };

  static AppSettings fromJson(Object? m) {
    if (m is! Map) return const AppSettings();
    bool b(String k, bool d) => m[k] is bool ? m[k] as bool : d;
    final q = m['quickCategories'];
    return AppSettings(
      autostart: b('autostart', false),
      minimizeToTray: b('minimizeToTray', true),
      trayHintShown: b('trayHintShown', false),
      quickCategories: q is List ? q.whereType<String>().toList() : const [],
    );
  }
}

class SettingsStore {
  SettingsStore(this.file);
  final File file;

  Future<AppSettings> load() async {
    try {
      if (!file.existsSync()) return const AppSettings();
      return AppSettings.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(s.toJson()), flush: true);
    } catch (_) {}
  }
}

/// Выбор категорий для быстрой очистки из сохранённых: только известные
/// категории (Загрузки и Большие файлы — не категории, их тут быть не может);
/// кэш браузеров пропускается, если браузер запущен.
({List<CategoryId> ids, bool skippedBrowsers}) pickQuickCategories(
  Iterable<String> saved, {
  required bool browserRunning,
}) {
  final byName = {for (final c in CategoryId.values) c.name: c};
  final ids = <CategoryId>[];
  var skipped = false;
  for (final n in saved) {
    final id = byName[n];
    if (id == null || ids.contains(id)) continue;
    if (id == CategoryId.browsers && browserRunning) {
      skipped = true;
      continue;
    }
    ids.add(id);
  }
  return (ids: ids, skippedBrowsers: skipped);
}

/// Строка автозапуска: путь к exe в кавычках + --tray.
String autostartCommand(String exePath) => '"$exePath" --tray';
