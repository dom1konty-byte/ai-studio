/// Один процесс из снимка: время ЦП (ядро + пользователь, в 100 нс) и память.
class RawProc {
  const RawProc({
    required this.pid,
    required this.name,
    this.cpuTime = 0,
    this.memory = 0,
    this.noAccess = false,
  });

  final int pid;

  /// Имя exe, например `chrome.exe`.
  final String name;
  final int cpuTime;

  /// Рабочий набор, байт.
  final int memory;

  /// Не удалось открыть процесс (ЦП и память неизвестны).
  final bool noAccess;
}

/// Снимок системы в момент [wallMs] (миллисекунды по монотонным часам).
class SysSample {
  const SysSample({
    required this.wallMs,
    required this.idle,
    required this.kernel,
    required this.user,
    required this.memLoadPercent,
    required this.totalPhys,
    required this.availPhys,
    required this.procs,
    required this.cores,
  });

  final int wallMs;

  /// Системные времена (100 нс); kernel включает idle.
  final int idle;
  final int kernel;
  final int user;
  final int memLoadPercent;
  final int totalPhys;
  final int availPhys;
  final List<RawProc> procs;
  final int cores;

  int get usedPhys => totalPhys - availPhys;
}

/// ЦП процесса, %: дельта времени процесса / (дельта стены × число ядер).
double procCpuPercent({required int deltaCpu100ns, required int deltaWallMs, required int cores}) {
  if (deltaWallMs <= 0 || cores <= 0 || deltaCpu100ns <= 0) return 0;
  final v = deltaCpu100ns / (deltaWallMs * 10000.0 * cores) * 100;
  return v.clamp(0.0, 100.0);
}

/// Общая загрузка ЦП, % (0–100); null — нет базы для сравнения.
double? totalCpuPercent(SysSample? prev, SysSample cur) {
  if (prev == null) return null;
  final total = (cur.kernel + cur.user) - (prev.kernel + prev.user);
  final idle = cur.idle - prev.idle;
  if (total <= 0) return null;
  return ((total - idle) / total * 100).clamp(0.0, 100.0);
}

/// Процессы, которые нельзя завершать.
const _protectedNames = {
  'system',
  'system idle process',
  'idle',
  'registry',
  'smss',
  'csrss',
  'wininit',
  'winlogon',
  'services',
  'lsass',
  'lsaiso',
  'svchost',
  'fontdrvhost',
  'dwm',
  'explorer',
  'sihost',
  'ctfmon',
  'memory compression',
  'msmpeng',
  'securityhealthservice',
  'spoolsv',
  'audiodg',
  'conhost',
  'runtimebroker',
  'startmenuexperiencehost',
  'shellexperiencehost',
  'searchhost',
  'textinputhost',
  'taskhostw',
  'wudfhost',
  'lsm',
  'dllhost',
  'smartscreen',
  'securityhealthsystray',
  'searchindexer',
  'applicationframehost',
  'sgrmbroker',
  'mssense',
  'nissrv',
  'wlanext',
  'dashost',
  // сама программа
  'chistka_pk',
  'chistodisk',
};

String _stem(String name) {
  final n = name.trim().toLowerCase();
  return n.endsWith('.exe') ? n.substring(0, n.length - 4) : n;
}

/// Можно ли завершать процесс: нельзя системные, PID 0/4, саму программу (по PID и имени).
bool isProtectedProcess(String name, int pid, {int? ownPid, String? ownName}) {
  if (pid == 0 || pid == 4) return true;
  if (ownPid != null && pid == ownPid) return true;
  final s = _stem(name);
  if (_protectedNames.contains(s)) return true;
  if (ownName != null && ownName.isNotEmpty && s == _stem(ownName)) return true;
  return false;
}

/// Процессы с одним именем exe (Chrome — как один).
class ProcGroup {
  const ProcGroup({
    required this.name,
    required this.pids,
    required this.cpu,
    required this.memory,
    required this.isProtected,
  });

  final String name;
  final List<int> pids;
  final double cpu;
  final int memory;
  final bool isProtected;

  int get count => pids.length;
}

/// Группы по имени exe с ЦП (по двум снимкам) и памятью.
List<ProcGroup> buildGroups(SysSample? prev, SysSample cur, {int? ownPid, String? ownName}) {
  final prevCpu = <int, int>{};
  if (prev != null) {
    for (final p in prev.procs) {
      prevCpu[p.pid] = p.cpuTime;
    }
  }
  final dWall = prev == null ? 0 : cur.wallMs - prev.wallMs;
  final byName = <String, List<RawProc>>{};
  for (final p in cur.procs) {
    byName.putIfAbsent(p.name.toLowerCase(), () => []).add(p);
  }
  final res = <ProcGroup>[];
  byName.forEach((_, list) {
    var cpu = 0.0;
    var mem = 0;
    var prot = false;
    for (final p in list) {
      mem += p.memory;
      final before = prevCpu[p.pid];
      if (before != null && !p.noAccess) {
        cpu += procCpuPercent(
            deltaCpu100ns: p.cpuTime - before, deltaWallMs: dWall, cores: cur.cores);
      }
      if (isProtectedProcess(p.name, p.pid, ownPid: ownPid, ownName: ownName)) prot = true;
    }
    res.add(ProcGroup(
      name: list.first.name,
      pids: [for (final p in list) p.pid],
      cpu: cpu,
      memory: mem,
      isProtected: prot,
    ));
  });
  return res;
}

enum ProcSort { cpu, memory }

List<ProcGroup> sortGroups(List<ProcGroup> g, ProcSort by, {bool ascending = false}) {
  final l = [...g];
  l.sort((a, b) {
    final c = by == ProcSort.cpu ? a.cpu.compareTo(b.cpu) : a.memory.compareTo(b.memory);
    final r = c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return ascending ? r : (c != 0 ? -c : r);
  });
  return l;
}

/// Итог завершения одного процесса.
enum KillResult { ok, denied, failed }
