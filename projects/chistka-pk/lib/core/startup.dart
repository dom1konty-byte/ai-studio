import 'dart:typed_data';

/// Источники автозагрузки.
enum StartupSource {
  hkcuRun,
  hklmRun,
  hklmRun32,
  userFolder,
  commonFolder;

  bool get isRegistry => this == hkcuRun || this == hklmRun || this == hklmRun32;

  /// Источники HKLM и общая папка меняются только с правами администратора.
  bool get needsAdmin => this != hkcuRun && this != userFolder;

  /// Чип источника в списке.
  String get chip => isRegistry ? 'Реестр' : 'Папка';

  /// Ключ с самими записями Run (для папок — null).
  String? get runKey => switch (this) {
        hkcuRun => r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        hklmRun => r'HKLM\Software\Microsoft\Windows\CurrentVersion\Run',
        hklmRun32 => r'HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        _ => null,
      };

  /// Ключ StartupApproved, где Диспетчер задач хранит состояние.
  String get approvedKey {
    final hive = needsAdmin ? 'HKLM' : 'HKCU';
    final leaf = switch (this) {
      hkcuRun || hklmRun => 'Run',
      hklmRun32 => 'Run32',
      _ => 'StartupFolder',
    };
    return '$hive\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\$leaf';
  }
}

class StartupItem {
  const StartupItem({
    required this.name,
    required this.path,
    required this.source,
    required this.enabled,
    required this.canChange,
  });
  final String name;
  final String path;
  final StartupSource source;
  final bool enabled;

  /// false — нужны права администратора, выключатель неактивен.
  final bool canChange;

  StartupItem copyWith({bool? enabled}) => StartupItem(
        name: name,
        path: path,
        source: source,
        enabled: enabled ?? this.enabled,
        canChange: canChange,
      );
}

/// Разбор значения StartupApproved: нет значения или пусто = включено;
/// первый байт чётный (02/06) = включено, нечётный (03/07) = выключено.
bool parseApproved(Uint8List? data) {
  if (data == null || data.isEmpty) return true;
  return data[0].isEven;
}

const _filetimeEpochOffsetMs = 11644473600000; // 1601-01-01 .. 1970-01-01

/// FILETIME (100-нс интервалы с 1601 года) для момента [t].
int filetimeOf(DateTime t) =>
    (t.toUtc().millisecondsSinceEpoch + _filetimeEpochOffsetMs) * 10000;

/// 12 байт: выключено = 03 00 00 00 + FILETIME (8 байт, little-endian);
/// включено = 02 + 11 нулей.
Uint8List buildApproved(bool enabled, DateTime now) {
  final out = Uint8List(12);
  if (enabled) {
    out[0] = 2;
    return out;
  }
  out[0] = 3;
  final bd = ByteData.sublistView(out);
  final ft = filetimeOf(now);
  bd.setUint32(4, ft & 0xFFFFFFFF, Endian.little);
  bd.setUint32(8, (ft >> 32) & 0xFFFFFFFF, Endian.little);
  return out;
}

/// Обрезает длинный путь для списка.
String shortenPath(String s, [int max = 70]) =>
    s.length <= max ? s : '${s.substring(0, max - 1)}…';
