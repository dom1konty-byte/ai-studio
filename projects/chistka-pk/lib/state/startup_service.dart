import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/startup.dart';
import '../core/catalog.dart' show Env;
import '../platform/platform_api.dart';

/// Имена файлов в папке (не папки). В тестах подменяется.
typedef FolderLister = Future<List<String>> Function(String dir);

Future<List<String>> listFilesReal(String dir) async {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  final res = <String>[];
  await for (final e in d.list(followLinks: false)) {
    if (e is File) res.add(p.basename(e.path));
  }
  return res;
}

/// Чтение и переключение автозагрузки. Записи Run и ярлыки НЕ удаляются и не
/// меняются: меняется только отметка StartupApproved (как в Диспетчере задач).
class StartupService {
  StartupService(this.platform, this.env, {FolderLister? lister, DateTime Function()? now})
      : _lister = lister ?? listFilesReal,
        _now = now ?? DateTime.now;

  final PlatformApi platform;
  final Env env;
  final FolderLister _lister;
  final DateTime Function() _now;

  String? folderOf(StartupSource s) {
    if (s == StartupSource.userFolder) {
      final a = env['APPDATA'];
      return a == null ? null : '$a\\Microsoft\\Windows\\Start Menu\\Programs\\Startup';
    }
    final p = env['ProgramData'];
    return p == null ? null : '$p\\Microsoft\\Windows\\Start Menu\\Programs\\StartUp';
  }

  Future<List<StartupItem>> load() async {
    final items = <StartupItem>[];
    for (final src in StartupSource.values) {
      final canChange = src.needsAdmin ? await platform.regCanWrite(src.approvedKey) : true;
      final found = <String, String>{}; // имя → путь/команда
      if (src.isRegistry) {
        found.addAll(await platform.regStringValues(src.runKey!));
      } else {
        final dir = folderOf(src);
        if (dir != null) {
          for (final f in await _lister(dir)) {
            if (f.toLowerCase() == 'desktop.ini') continue;
            found[f] = '$dir\\$f';
          }
        }
      }
      for (final e in found.entries) {
        final enabled = parseApproved(await platform.regReadBinary(src.approvedKey, e.key));
        items.add(StartupItem(
          name: src.isRegistry ? e.key : _stripExt(e.key),
          path: e.value,
          source: src,
          enabled: enabled,
          canChange: canChange,
        ));
      }
    }
    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return items;
  }

  /// Для папок ключ StartupApproved — полное имя файла, а в списке показываем без расширения.
  String _valueName(StartupItem it) {
    if (it.source.isRegistry) return it.name;
    final p = it.path;
    return p.substring(p.lastIndexOf(r'\') + 1);
  }

  /// true — записано. Без прав / не удалось — false, ничего не меняется.
  Future<bool> setEnabled(StartupItem item, bool on) async {
    if (!item.canChange) return false;
    return platform.regWriteBinary(
        item.source.approvedKey, _valueName(item), buildApproved(on, _now()));
  }

  static String _stripExt(String n) {
    final i = n.lastIndexOf('.');
    return i > 0 ? n.substring(0, i) : n;
  }
}
