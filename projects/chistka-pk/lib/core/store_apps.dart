/// Приложения Microsoft Store: разбор JSON от PowerShell, неудаляемые,
/// проверка PackageFullName, имя ярлыка, фильтр переключателя. Чистые функции.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path_pkg;

import 'programs.dart';

/// Какой набор показывать на экране «Программы».
enum ProgramKind { regular, store, all }

/// Набор для переключателя: обычные / из Store / все (сначала обычные).
List<Program> programsOfKind(List<Program> regular, List<Program> store, ProgramKind kind) {
  switch (kind) {
    case ProgramKind.regular:
      return regular;
    case ProgramKind.store:
      return store;
    case ProgramKind.all:
      return [...regular, ...store];
  }
}

/// Имена пакетов, которые нельзя удалять (в конце `*` — любое окончание).
const lockedStoreNames = <String>[
  'Microsoft.WindowsStore',
  'Microsoft.Windows.ShellExperienceHost',
  'Microsoft.Windows.StartMenuExperienceHost',
  'Microsoft.SecHealthUI',
  'windows.immersivecontrolpanel',
  'Microsoft.DesktopAppInstaller',
  'Microsoft.VCLibs*',
  'Microsoft.NET*',
  'Microsoft.UI.Xaml*',
  'Microsoft.WindowsAppRuntime*',
  'Microsoft.AAD.BrokerPlugin',
  'Microsoft.AccountsControl',
  'Microsoft.Windows.CloudExperienceHost',
  'Microsoft.Windows.ContentDeliveryManager',
  'MicrosoftWindows.Client.*',
  'Microsoft.Windows.Search',
  'Microsoft.LockApp',
];

/// Часть Windows: NonRemovable, подпись System или имя из списка.
bool isLockedStoreApp(String name, {bool nonRemovable = false, String signatureKind = ''}) {
  if (nonRemovable) return true;
  if (signatureKind.trim().toLowerCase() == 'system') return true;
  final n = name.toLowerCase();
  for (final pat in lockedStoreNames) {
    final p = pat.toLowerCase();
    if (p.endsWith('*')) {
      if (n.startsWith(p.substring(0, p.length - 1))) return true;
    } else if (n == p) {
      return true;
    }
  }
  return false;
}

final RegExp _pkgFullName = RegExp(r'^[A-Za-z0-9._~-]+$');

/// PackageFullName безопасен для передачи в команду.
bool isValidPackageFullName(String s) => s.isNotEmpty && s.length <= 256 && _pkgFullName.hasMatch(s);

/// Отображаемое имя: «ms-resource:…» или пусто → Name без префикса издателя
/// (`Microsoft.WindowsCalculator` → `WindowsCalculator`).
String storeDisplayName(String displayName, String name) {
  final d = displayName.trim();
  if (d.isNotEmpty && !d.toLowerCase().startsWith('ms-resource:')) return d;
  final i = name.indexOf('.');
  final rest = i >= 0 && i < name.length - 1 ? name.substring(i + 1) : name;
  return rest.isEmpty ? name : rest;
}

DateTime? _parseStoreDate(Object? v) {
  if (v == null) return null;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  final s = v.toString().trim();
  final ms = RegExp(r'Date\((-?\d+)').firstMatch(s);
  if (ms != null) return DateTime.fromMillisecondsSinceEpoch(int.parse(ms.group(1)!));
  final d = DateTime.tryParse(s);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

bool _asBool(Object? v) => v == true || v.toString().toLowerCase() == 'true';

String _sigName(Object? v) {
  if (v is int) {
    const names = ['None', 'Developer', 'Enterprise', 'Store', 'System'];
    return v >= 0 && v < names.length ? names[v] : '';
  }
  return (v ?? '').toString();
}

/// Разбор JSON от PowerShell (массив или один объект). Мусор → пустой список.
List<Program> parseStoreApps(String json) {
  Object? data;
  try {
    var t = json.trim();
    if (t.startsWith('﻿')) t = t.substring(1);
    if (t.isEmpty) return const [];
    data = jsonDecode(t);
  } catch (_) {
    return const [];
  }
  final items = data is List ? data : [data];
  final seen = <String>{};
  final res = <Program>[];
  for (final it in items) {
    if (it is! Map) continue;
    String s(String k) => (it[k] ?? '').toString().trim();
    final name = s('Name');
    final full = s('PackageFullName');
    if (name.isEmpty || !isValidPackageFullName(full) || !seen.add(full)) continue;
    final bytes = it['SizeBytes'];
    final sizeBytes = bytes is num ? bytes.toInt() : 0;
    final shown = storeDisplayName(s('DisplayName'), name);
    res.add(Program(
      name: shown,
      publisher: s('Publisher'),
      sizeKb: sizeBytes > 0 ? (sizeBytes + 1023) ~/ 1024 : 0,
      installDate: _parseStoreDate(it['InstallDate']),
      displayIcon: '',
      installLocation: s('InstallLocation'),
      uninstallString: '',
      quietUninstallString: '',
      hive: 'STORE',
      keyPath: 'store:$full',
      storeFullName: full,
      storeFamily: s('PackageFamilyName'),
      storeAppId: s('AppId'),
      locked: isLockedStoreApp(name,
          nonRemovable: _asBool(it['NonRemovable']), signatureKind: _sigName(it['SignatureKind'])),
      iconFile: s('LogoFile'),
    ));
  }
  return res;
}

/// Имя файла ярлыка: без `\/:*?"<>|` и управляющих символов, без точек/пробелов по краям.
String shortcutFileName(String name) {
  var s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '').replaceAll(RegExp(r'\s+'), ' ');
  s = s.replaceAll(RegExp(r'^[\s.]+|[\s.]+$'), '');
  if (s.length > 120) s = s.substring(0, 120).trimRight();
  return s.isEmpty ? 'Программа' : s;
}

final RegExp _idPart = RegExp(r'^[A-Za-z0-9._-]+$');

/// Аргумент explorer.exe для ярлыка Store-приложения (null — данные не годятся).
String? storeShortcutArgs(Program p) {
  if (!p.isStore || !_idPart.hasMatch(p.storeFamily) || !_idPart.hasMatch(p.storeAppId)) {
    return null;
  }
  return r'shell:AppsFolder\' '${p.storeFamily}!${p.storeAppId}';
}

bool _defaultExists(String p) => File(p).existsSync();

List<String> _defaultExesIn(String dir) {
  try {
    return Directory(dir)
        .listSync(followLinks: false)
        .whereType<File>()
        .map((f) => f.path)
        .where((f) => f.toLowerCase().endsWith('.exe'))
        .toList();
  } catch (_) {
    return const [];
  }
}

/// exe для ярлыка обычной программы: DisplayIcon (.exe), иначе единственный
/// подходящий exe в InstallLocation (не удаление/установка). Нет — null.
String? shortcutTargetOf(Program p,
    {Map<String, String> env = const {},
    bool Function(String)? fileExists,
    List<String> Function(String dir)? exesIn}) {
  final exists = fileExists ?? _defaultExists;
  final di = parseDisplayIcon(p.displayIcon, env: env);
  if (di != null && di.path.toLowerCase().endsWith('.exe') && exists(di.path)) return di.path;
  final dir = p.installLocation.trim();
  if (dir.isEmpty) return null;
  final all = (exesIn ?? _defaultExesIn)(dir).where((f) {
    final b = path_pkg.windows.basename(f).toLowerCase();
    return !b.startsWith('unins') && !b.contains('uninstall') && !b.contains('setup');
  }).toList();
  if (all.length == 1) return all.first;
  String norm(String x) => x.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  final n = norm(p.name);
  for (final f in all) {
    if (norm(path_pkg.windows.basenameWithoutExtension(f)) == n) return f;
  }
  return null;
}

// ---- Константные скрипты PowerShell (данные передаются только через окружение) ----

/// Список Store-приложений текущего пользователя, JSON в UTF-8.
const storeListScript = r'''
$ErrorActionPreference='SilentlyContinue'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$sw=[Diagnostics.Stopwatch]::StartNew()
$out=@()
foreach($p in (Get-AppxPackage | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage })){
  $dn='';$pub='';$aid='';$logo=''
  try{
    $m=Get-AppxPackageManifest -Package $p.PackageFullName
    $pr=$m.Package.Properties
    $dn=[string]$pr.DisplayName; $pub=[string]$pr.PublisherDisplayName
    $aid=[string](@($m.Package.Applications.Application)[0].Id)
    $lg=[string]$pr.Logo
    $loc=[string]$p.InstallLocation
    if($lg -and $loc){
      $base=Join-Path $loc $lg
      $dir=Split-Path $base; $stem=[IO.Path]::GetFileNameWithoutExtension($base); $ext=[IO.Path]::GetExtension($base)
      foreach($sc in @('.scale-200','.scale-100','.scale-400','.scale-150','.scale-125','')){
        $f=Join-Path $dir ($stem+$sc+$ext)
        if(Test-Path -LiteralPath $f){ $logo=$f; break }
      }
      if(-not $logo){
        $c=Get-ChildItem -LiteralPath $dir -Filter ($stem+'*'+$ext) -File | Sort-Object Length -Descending | Select-Object -First 1
        if($c){ $logo=$c.FullName }
      }
    }
  }catch{}
  $loc=[string]$p.InstallLocation
  $date=''
  try{
    if($p.InstallDate){ $date=([datetime]$p.InstallDate).ToString('yyyy-MM-dd') }
    elseif($loc -and (Test-Path -LiteralPath $loc)){ $date=(Get-Item -LiteralPath $loc).CreationTime.ToString('yyyy-MM-dd') }
  }catch{}
  $size=$null
  if($loc -and $sw.Elapsed.TotalSeconds -lt 15 -and (Test-Path -LiteralPath $loc)){
    try{
      $s=(Get-ChildItem -LiteralPath $loc -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
      if($s){ $size=[int64]$s }
    }catch{}
  }
  $out+=[pscustomobject]@{
    Name=[string]$p.Name; PackageFullName=[string]$p.PackageFullName; PackageFamilyName=[string]$p.PackageFamilyName
    DisplayName=$dn; Publisher=$pub; LogoFile=$logo; AppId=$aid; InstallLocation=$loc; InstallDate=$date
    NonRemovable=[bool]$p.NonRemovable; SignatureKind=[string]$p.SignatureKind; SizeBytes=$size
  }
}
ConvertTo-Json -Compress -Depth 3 -InputObject @($out)
''';

/// Удаление пакета: имя в переменной окружения CD_PKG.
const storeRemoveScript = r'''
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
try{ Remove-AppxPackage -Package $env:CD_PKG }catch{ [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
''';

/// Ярлык на рабочем столе: CD_NAME, CD_TARGET, CD_ARGS, CD_ICON — из окружения.
const shortcutScript = r'''
$ErrorActionPreference='Stop'
try{
  $d=[Environment]::GetFolderPath('Desktop')
  $s=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $d ($env:CD_NAME+'.lnk')))
  $s.TargetPath=$env:CD_TARGET
  if($env:CD_ARGS){ $s.Arguments=$env:CD_ARGS }
  if($env:CD_ICON){ $s.IconLocation=$env:CD_ICON }
  $s.Save()
}catch{ [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
''';
