import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../core/procs.dart';

// Процессы и загрузка системы через kernel32 (dart:ffi).

final class _ProcessEntry extends Struct {
  @Uint32()
  external int dwSize;
  @Uint32()
  external int cntUsage;
  @Uint32()
  external int pid;
  @IntPtr()
  external int heapId;
  @Uint32()
  external int moduleId;
  @Uint32()
  external int threads;
  @Uint32()
  external int parentPid;
  @Int32()
  external int priClass;
  @Uint32()
  external int flags;
  @Array(260)
  external Array<Uint16> exeFile;
}

typedef _SnapN = IntPtr Function(Uint32, Uint32);
typedef _SnapD = int Function(int, int);
typedef _FirstN = Int32 Function(IntPtr, Pointer<_ProcessEntry>);
typedef _FirstD = int Function(int, Pointer<_ProcessEntry>);
typedef _OpenN = IntPtr Function(Uint32, Int32, Uint32);
typedef _OpenD = int Function(int, int, int);
typedef _CloseN = Int32 Function(IntPtr);
typedef _CloseD = int Function(int);
typedef _TimesN = Int32 Function(IntPtr, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _TimesD = int Function(int, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _MemInfoN = Int32 Function(IntPtr, Pointer<IntPtr>, Uint32);
typedef _MemInfoD = int Function(int, Pointer<IntPtr>, int);
typedef _SysTimesN = Int32 Function(Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _SysTimesD = int Function(Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _MemStatusN = Int32 Function(Pointer<Uint64>);
typedef _MemStatusD = int Function(Pointer<Uint64>);
typedef _TermN = Int32 Function(IntPtr, Uint32);
typedef _TermD = int Function(int, int);
typedef _LastErrN = Uint32 Function();
typedef _LastErrD = int Function();

const _th32csSnapProcess = 0x2;
const _processQueryLimited = 0x1000;
const _processTerminate = 0x1;
const _errorAccessDenied = 5;
final _stopwatch = Stopwatch()..start();

/// Снимок процессов и системы. Бросает исключение при сбое — вызывающий ловит.
SysSample takeSystemSample() {
  final k = DynamicLibrary.open('kernel32.dll');
  final snapshot = k.lookupFunction<_SnapN, _SnapD>('CreateToolhelp32Snapshot');
  final first = k.lookupFunction<_FirstN, _FirstD>('Process32FirstW');
  final next = k.lookupFunction<_FirstN, _FirstD>('Process32NextW');
  final open = k.lookupFunction<_OpenN, _OpenD>('OpenProcess');
  final close = k.lookupFunction<_CloseN, _CloseD>('CloseHandle');
  final times = k.lookupFunction<_TimesN, _TimesD>('GetProcessTimes');
  final memInfo = k.lookupFunction<_MemInfoN, _MemInfoD>('K32GetProcessMemoryInfo');
  final sysTimes = k.lookupFunction<_SysTimesN, _SysTimesD>('GetSystemTimes');
  final memStatus = k.lookupFunction<_MemStatusN, _MemStatusD>('GlobalMemoryStatusEx');

  final t = calloc<Uint64>(4);
  final pmc = calloc<IntPtr>(9); // PROCESS_MEMORY_COUNTERS: 72 байта
  final st = calloc<Uint64>(3);
  final ms = calloc<Uint64>(8); // MEMORYSTATUSEX: 64 байта
  final entry = calloc<_ProcessEntry>();
  final procs = <RawProc>[];
  int snap = -1;
  try {
    snap = snapshot(_th32csSnapProcess, 0);
    if (snap == -1 || snap == 0) throw StateError('snapshot');
    entry.ref.dwSize = sizeOf<_ProcessEntry>();
    var ok = first(snap, entry);
    while (ok != 0) {
      final chars = <int>[];
      for (var i = 0; i < 260; i++) {
        final c = entry.ref.exeFile[i];
        if (c == 0) break;
        chars.add(c);
      }
      final pid = entry.ref.pid;
      final name = String.fromCharCodes(chars);
      var cpu = 0;
      var mem = 0;
      var denied = true;
      if (pid != 0) {
        final h = open(_processQueryLimited, 0, pid);
        if (h != 0) {
          try {
            if (times(h, t, t + 1, t + 2, t + 3) != 0) {
              cpu = t[2] + t[3];
              denied = false;
            }
            (pmc + 0).cast<Uint32>().value = 72;
            if (memInfo(h, pmc, 72) != 0) mem = pmc[2];
          } finally {
            close(h);
          }
        }
      }
      procs.add(RawProc(pid: pid, name: name, cpuTime: cpu, memory: mem, noAccess: denied));
      ok = next(snap, entry);
    }
    if (sysTimes(st, st + 1, st + 2) == 0) throw StateError('times');
    ms.cast<Uint32>().value = 64;
    if (memStatus(ms) == 0) throw StateError('memory');
    return SysSample(
      wallMs: _stopwatch.elapsedMilliseconds,
      idle: st[0],
      kernel: st[1],
      user: st[2],
      memLoadPercent: (ms.cast<Uint32>() + 1).value,
      totalPhys: ms[1],
      availPhys: ms[2],
      procs: procs,
      cores: Platform.numberOfProcessors,
    );
  } finally {
    if (snap != -1 && snap != 0) close(snap);
    calloc.free(t);
    calloc.free(pmc);
    calloc.free(st);
    calloc.free(ms);
    calloc.free(entry);
  }
}

/// TerminateProcess по PID.
KillResult terminateProcessByPid(int pid) {
  try {
    final k = DynamicLibrary.open('kernel32.dll');
    final open = k.lookupFunction<_OpenN, _OpenD>('OpenProcess');
    final close = k.lookupFunction<_CloseN, _CloseD>('CloseHandle');
    final term = k.lookupFunction<_TermN, _TermD>('TerminateProcess');
    final lastErr = k.lookupFunction<_LastErrN, _LastErrD>('GetLastError');
    final h = open(_processTerminate, 0, pid);
    if (h == 0) return lastErr() == _errorAccessDenied ? KillResult.denied : KillResult.failed;
    try {
      if (term(h, 1) != 0) return KillResult.ok;
      return lastErr() == _errorAccessDenied ? KillResult.denied : KillResult.failed;
    } finally {
      close(h);
    }
  } catch (_) {
    return KillResult.failed;
  }
}
