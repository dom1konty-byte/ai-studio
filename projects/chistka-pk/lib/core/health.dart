import 'dart:convert';

/// Путь к Windows PowerShell (передаётся каталог Windows).
String powershellExe(String systemRoot) =>
    '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';

/// Аргументы запуска PowerShell со скриптом [diskHealthScript] (скрипт — константа,
/// никакие данные в него не подставляются).
const diskHealthArgs = [
  '-NoProfile',
  '-NonInteractive',
  '-WindowStyle',
  'Hidden',
  '-Command',
  diskHealthScript,
];

/// Константный скрипт: физические диски + счётчики надёжности → JSON (UTF-8).
const diskHealthScript = r"$ErrorActionPreference='SilentlyContinue';"
    r'[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;'
    r"$sys=(Get-Partition -DriveLetter ($env:SystemDrive.Substring(0,1))).DiskNumber;"
    r'$r=@(Get-PhysicalDisk | ForEach-Object {'
    r'$d=$_;$c=$d | Get-StorageReliabilityCounter;'
    r'[pscustomobject]@{FriendlyName=[string]$d.FriendlyName;MediaType=[string]$d.MediaType;'
    r'HealthStatus=[string]$d.HealthStatus;OperationalStatus=[string]$d.OperationalStatus;'
    r'Size=$d.Size;DeviceId=[string]$d.DeviceId;IsSystem=([string]$d.DeviceId -eq [string]$sys);'
    r'Temperature=$c.Temperature;Wear=$c.Wear;PowerOnHours=$c.PowerOnHours;'
    r'ReadErrorsTotal=$c.ReadErrorsTotal}});'
    r'ConvertTo-Json -Compress -InputObject $r';

/// Таймаут запроса состояния дисков.
const diskHealthTimeout = Duration(seconds: 20);

enum DiskState { healthy, warning, unhealthy }

extension DiskStateText on DiskState {
  String get label => switch (this) {
        DiskState.healthy => 'Исправен',
        DiskState.warning => 'Внимание',
        DiskState.unhealthy => 'Неисправен',
      };
}

class DiskHealth {
  const DiskHealth({
    required this.name,
    required this.mediaType,
    required this.state,
    this.size,
    this.deviceId = '',
    this.temperature,
    this.wear,
    this.powerOnHours,
    this.readErrors,
    this.isSystem = false,
  });

  final String name;

  /// «SSD», «HDD» или пусто (тип не определён).
  final String mediaType;
  final DiskState state;
  final int? size;
  final String deviceId;

  /// °C; null — нет данных.
  final int? temperature;

  /// Износ в процентах (0–100); null — нет данных.
  final int? wear;
  final int? powerOnHours;
  final int? readErrors;
  final bool isSystem;

  /// Температура и износ недоступны — обычно нужен режим администратора.
  bool get needsAdmin => temperature == null && wear == null;
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

DiskState _state(Object? v) {
  final s = (v is String ? v : '').trim().toLowerCase();
  if (s == 'healthy') return DiskState.healthy;
  if (s == 'unhealthy') return DiskState.unhealthy;
  if (s == 'warning') return DiskState.warning;
  // Неизвестное состояние не выдаём за исправное.
  return DiskState.warning;
}

/// Разбор JSON от PowerShell: один объект или массив. null — вывод не разобрать.
List<DiskHealth>? parseDiskHealth(String? output) {
  if (output == null) return null;
  var text = output.trim();
  if (text.startsWith('﻿')) text = text.substring(1).trim();
  if (text.isEmpty) return const [];
  Object? data;
  try {
    data = jsonDecode(text);
  } catch (_) {
    return null;
  }
  final items = data is List ? data : (data is Map ? [data] : null);
  if (items == null) return null;
  final res = <DiskHealth>[];
  for (final e in items) {
    if (e is! Map) continue;
    final media = (e['MediaType'] is String ? e['MediaType'] as String : '').trim().toUpperCase();
    final temp = _int(e['Temperature']);
    final wear = _int(e['Wear']);
    final name = e['FriendlyName'] is String ? (e['FriendlyName'] as String).trim() : '';
    res.add(DiskHealth(
      name: name.isEmpty ? 'Диск' : name,
      mediaType: (media == 'SSD' || media == 'HDD') ? media : '',
      state: _state(e['HealthStatus']),
      size: _int(e['Size']),
      deviceId: e['DeviceId']?.toString() ?? '',
      temperature: (temp == null || temp <= 0 || temp > 150) ? null : temp,
      wear: (wear == null || wear < 0) ? null : wear.clamp(0, 100),
      powerOnHours: _int(e['PowerOnHours']),
      readErrors: _int(e['ReadErrorsTotal']),
      isSystem: e['IsSystem'] == true,
    ));
  }
  return res;
}

/// Системный диск или первый в списке (null — списка нет).
DiskHealth? pickSystemDisk(List<DiskHealth> disks) {
  if (disks.isEmpty) return null;
  for (final d in disks) {
    if (d.isSystem) return d;
  }
  return disks.first;
}

/// Строка плитки: «SSD · Исправен · 38°».
String diskTileText(DiskHealth d) {
  final parts = <String>[
    if (d.mediaType.isNotEmpty) d.mediaType,
    d.state.label,
    if (d.temperature != null) '${d.temperature}°',
  ];
  return parts.join(' · ');
}
