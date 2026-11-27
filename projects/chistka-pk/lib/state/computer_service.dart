import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/battery.dart';
import '../core/catalog.dart';
import '../core/health.dart';
import '../core/procs.dart';
import '../platform/platform_api.dart';

enum ComputerLoad { idle, loading, done, error }

/// Данные экрана «Компьютер»: здоровье дисков, нагрузка и процессы, батарея.
class ComputerService extends ChangeNotifier {
  ComputerService(
    this.platform,
    this.env, {
    int? ownPid,
    String? ownName,
    this.interval = const Duration(seconds: 2),
  })  : ownPid = ownPid ?? pid,
        ownName = ownName ?? _exeName(Platform.resolvedExecutable);

  final PlatformApi platform;
  final Env env;
  final int ownPid;
  final String ownName;
  final Duration interval;

  static String _exeName(String path) => path.split(RegExp(r'[\\/]')).last;

  String get _systemRoot => env['SystemRoot'] ?? env['WINDIR'] ?? r'C:\Windows';

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---------- здоровье диска ----------

  ComputerLoad healthLoad = ComputerLoad.idle;
  List<DiskHealth> disks = const [];

  Future<void> loadHealth() async {
    if (healthLoad == ComputerLoad.loading) return;
    healthLoad = ComputerLoad.loading;
    _notify();
    List<DiskHealth>? res;
    try {
      final out = await platform.runToolUtf8(powershellExe(_systemRoot), diskHealthArgs,
          timeout: diskHealthTimeout);
      res = parseDiskHealth(out);
    } catch (_) {
      res = null;
    }
    if (res == null || res.isEmpty) {
      healthLoad = ComputerLoad.error;
      disks = const [];
    } else {
      healthLoad = ComputerLoad.done;
      disks = res;
    }
    _notify();
  }

  DiskHealth? get mainDisk => pickSystemDisk(disks);

  // ---------- батарея ----------

  ComputerLoad batteryLoad = ComputerLoad.idle;
  BatteryInfo? battery;

  /// Папка для отчёта: %LOCALAPPDATA%\ChistoDisk\tmp (null — негде писать).
  String? get _tmpDir {
    final local = env['LOCALAPPDATA'];
    if (local == null) return null;
    return '$local${Platform.pathSeparator}ChistoDisk${Platform.pathSeparator}tmp';
  }

  Future<void> loadBattery() async {
    if (batteryLoad == ComputerLoad.loading) return;
    batteryLoad = ComputerLoad.loading;
    _notify();
    BatteryInfo? info;
    final dir = _tmpDir;
    if (dir != null) {
      final file = File('$dir${Platform.pathSeparator}battery.xml');
      try {
        await Directory(dir).create(recursive: true);
        if (await file.exists()) await file.delete();
        await platform.runToolUtf8('$_systemRoot\\System32\\powercfg.exe', batteryReportArgs(file.path),
            timeout: const Duration(seconds: 30));
        if (await file.exists()) {
          info = parseBatteryReport(await file.readAsString());
        }
      } catch (_) {
        info = null;
      } finally {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
    battery = info;
    batteryLoad = ComputerLoad.done;
    _notify();
  }

  // ---------- процессы ----------

  SysSample? _prev;
  double? cpuPercent;
  int memPercent = 0;
  int memUsed = 0;
  int memTotal = 0;
  List<ProcGroup> groups = const [];
  bool sampleFailed = false;
  ProcSort sort = ProcSort.cpu;
  bool sortAscending = false;
  Timer? _timer;
  bool _busy = false;

  bool get polling => _timer != null;

  void startPolling() {
    if (_timer != null || _disposed) return;
    _timer = Timer.periodic(interval, (_) => tick());
    tick();
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> tick() async {
    if (_busy || _disposed) return;
    _busy = true;
    try {
      final s = await platform.systemSample();
      if (_disposed) return;
      if (s == null) {
        sampleFailed = true;
      } else {
        sampleFailed = false;
        final cpu = totalCpuPercent(_prev, s);
        if (cpu != null) cpuPercent = cpu;
        groups = buildGroups(_prev, s, ownPid: ownPid, ownName: ownName);
        memPercent = s.memLoadPercent;
        memUsed = s.usedPhys;
        memTotal = s.totalPhys;
        _prev = s;
      }
      _notify();
    } catch (_) {
      sampleFailed = true;
      _notify();
    } finally {
      _busy = false;
    }
  }

  /// Курсор над таблицей процессов: порядок строк не меняется (иначе кнопка
  /// «Завершить» уезжает из-под курсора).
  bool hoverFreeze = false;
  List<String> _shownOrder = const [];

  List<ProcGroup> get sortedGroups {
    final fresh = sortGroups(groups, sort, ascending: sortAscending);
    if (!hoverFreeze || _shownOrder.isEmpty) {
      _shownOrder = [for (final g in fresh) g.name.toLowerCase()];
      return fresh;
    }
    final idx = {for (var i = 0; i < _shownOrder.length; i++) _shownOrder[i]: i};
    final out = [...fresh];
    final big = _shownOrder.length + 1;
    // sort в Dart не стабилен: при равенстве (новые имена) держим порядок свежего списка
    final pos = {for (var i = 0; i < fresh.length; i++) fresh[i]: i};
    out.sort((a, b) {
      final c = (idx[a.name.toLowerCase()] ?? big).compareTo(idx[b.name.toLowerCase()] ?? big);
      return c != 0 ? c : pos[a]!.compareTo(pos[b]!);
    });
    return out;
  }

  void setHoverFreeze(bool on) {
    if (hoverFreeze == on) return;
    hoverFreeze = on;
    if (!on) _shownOrder = const [];
  }

  void setSort(ProcSort by, {bool? ascending}) {
    _shownOrder = const [];
    if (ascending != null) {
      sort = by;
      sortAscending = ascending;
    } else if (sort == by) {
      sortAscending = !sortAscending;
    } else {
      sort = by;
      sortAscending = false;
    }
    _notify();
  }

  /// Завершает все процессы группы. Системные не трогает; перед убийством PID
  /// сверяется со свежим снимком (имя не поменялось). [KillResult.denied] — нужны права.
  Future<KillResult> terminateGroup(ProcGroup g) async {
    if (g.isProtected) return KillResult.failed;
    final fresh = await platform.systemSample();
    if (fresh == null) return KillResult.failed;
    final pids = <int>[
      for (final p in fresh.procs)
        if (p.name.toLowerCase() == g.name.toLowerCase() &&
            !isProtectedProcess(p.name, p.pid, ownPid: ownPid, ownName: ownName))
          p.pid,
    ];
    if (pids.isEmpty) return KillResult.ok;
    var worst = KillResult.ok;
    for (final pid in pids) {
      final r = await platform.killProcess(pid);
      if (r == KillResult.denied) {
        worst = KillResult.denied;
      } else if (r == KillResult.failed && worst == KillResult.ok) {
        worst = KillResult.failed;
      }
    }
    unawaited(tick());
    return worst;
  }
}
