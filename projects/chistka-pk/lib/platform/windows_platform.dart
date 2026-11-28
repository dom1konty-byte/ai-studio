import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../core/browsers.dart';
import '../core/procs.dart';
import '../core/programs.dart';
import '../core/whitelist.dart';
import 'elevation.dart';
import '../core/async_pool.dart';
import 'icon_extract.dart';
import 'proc_ffi.dart';
import 'platform_api.dart';
import 'single_instance.dart';
import 'win_registry.dart';

// Win32 через dart:ffi напрямую (shell32 / kernel32): без зависимости от версии пакета win32.

final class _ShFileOpStruct extends Struct {
  @IntPtr()
  external int hwnd;
  @Uint32()
  external int wFunc;
  external Pointer<Utf16> pFrom;
  external Pointer<Utf16> pTo;
  @Uint16()
  external int fFlags;
  @Int32()
  external int fAnyOperationsAborted;
  external Pointer<Void> hNameMappings;
  external Pointer<Utf16> lpszProgressTitle;
}

final class _ShellExecInfo extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int fMask;
  @IntPtr()
  external int hwnd;
  external Pointer<Utf16> lpVerb;
  external Pointer<Utf16> lpFile;
  external Pointer<Utf16> lpParameters;
  external Pointer<Utf16> lpDirectory;
  @Int32()
  external int nShow;
  @IntPtr()
  external int hInstApp;
  external Pointer<Void> lpIDList;
  external Pointer<Utf16> lpClass;
  @IntPtr()
  external int hkeyClass;
  @Uint32()
  external int dwHotKey;
  @IntPtr()
  external int hMonitor;
  @IntPtr()
  external int hProcess;
}

typedef _ShellExecNative = Int32 Function(Pointer<_ShellExecInfo>);
typedef _ShellExecDart = int Function(Pointer<_ShellExecInfo>);
typedef _LastErrNative = Uint32 Function();
typedef _LastErrDart = int Function();
typedef _ShFileOpNative = Int32 Function(Pointer<_ShFileOpStruct>);
typedef _ShFileOpDart = int Function(Pointer<_ShFileOpStruct>);
typedef _QueryBinNative = Int32 Function(Pointer<Utf16>, Pointer<Uint8>);
typedef _QueryBinDart = int Function(Pointer<Utf16>, Pointer<Uint8>);
typedef _EmptyBinNative = Int32 Function(IntPtr, Pointer<Utf16>, Uint32);
typedef _EmptyBinDart = int Function(int, Pointer<Utf16>, int);
typedef _DriveTypeNative = Uint32 Function(Pointer<Utf16>);
typedef _DriveTypeDart = int Function(Pointer<Utf16>);
typedef _DiskNative = Int32 Function(
    Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _DiskDart = int Function(
    Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);

const _seeMaskNoCloseProcess = 0x40;
const _seeMaskNoAsync = 0x100;
const _errorCancelled = 1223;
const _foDelete = 3;
const _fofAllowUndo = 0x0040;
const _fofNoConfirmMkdir = 0x0200;
const _fofWantNukeWarnings = 0x4000;
const _driveFixed = 3;
const _sherbNoConfirmation = 0x1;
const _sherbNoProgressUi = 0x2;
const _sherbNoSound = 0x4;

/// reg.exe export/delete: только HKCU\… и HKLM\SOFTWARE\… (без прав HKLM не удалится).
bool _regKeyAllowed(String key) {
  final u = key.toUpperCase();
  return u.startsWith(r'HKCU\') || u.startsWith(r'HKLM\SOFTWARE\');
}

class WindowsPlatform implements PlatformApi {
  late final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');
  late final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  late final _ShFileOpDart _shFileOp =
      _shell32.lookupFunction<_ShFileOpNative, _ShFileOpDart>('SHFileOperationW');
  late final _QueryBinDart _queryBin =
      _shell32.lookupFunction<_QueryBinNative, _QueryBinDart>('SHQueryRecycleBinW');
  late final _EmptyBinDart _emptyBin =
      _shell32.lookupFunction<_EmptyBinNative, _EmptyBinDart>('SHEmptyRecycleBinW');
  late final _ShellExecDart _shellExec =
      _shell32.lookupFunction<_ShellExecNative, _ShellExecDart>('ShellExecuteExW');
  late final _LastErrDart _lastError =
      _kernel32.lookupFunction<_LastErrNative, _LastErrDart>('GetLastError');
  late final _DriveTypeDart _driveType =
      _kernel32.lookupFunction<_DriveTypeNative, _DriveTypeDart>('GetDriveTypeW');
  late final _DiskDart _disk =
      _kernel32.lookupFunction<_DiskNative, _DiskDart>('GetDiskFreeSpaceExW');

  /// Папка Windows из окружения (для полных путей к системным программам).
  static String get _sysRoot {
    final v = Platform.environment['SystemRoot'] ?? Platform.environment['WINDIR'];
    return (v == null || v.isEmpty) ? r'C:\Windows' : v;
  }

  /// Причина пропуска по диску файла (не локальный фиксированный / нет Корзины) или null.
  String? _driveSkipReason(String path, Map<String, String?> cache) {
    final root = '${path.substring(0, 1).toUpperCase()}:\\';
    if (cache.containsKey(root)) return cache[root];
    String? reason;
    final r = root.toNativeUtf16();
    try {
      if (_driveType(r) != _driveFixed) {
        reason = 'диск не локальный фиксированный';
      } else if (_queryBinRoot(r) == null) {
        reason = 'для диска нет Корзины (файл удалился бы насовсем)';
      }
    } catch (_) {
      reason = 'не удалось проверить диск';
    } finally {
      calloc.free(r);
    }
    cache[root] = reason;
    return reason;
  }

  @override
  Future<Map<String, String?>> moveToRecycleBin(List<String> paths) async {
    final result = <String, String?>{};
    final toMove = <String>[];
    final cache = <String, String?>{};
    for (final p in paths) {
      final reason = recycleSkipReason(p) ?? _driveSkipReason(p, cache);
      if (reason != null) {
        result[p] = reason;
      } else {
        toMove.add(p);
      }
    }
    if (toMove.isEmpty) return result;

    final units = buildDoubleNullList(toMove);
    final buf = calloc<Uint16>(units.length);
    final op = calloc<_ShFileOpStruct>();
    try {
      buf.asTypedList(units.length).setAll(0, units);
      op.ref
        ..hwnd = 0
        ..wFunc = _foDelete
        ..pFrom = buf.cast<Utf16>()
        ..pTo = nullptr
        // без FOF_NOCONFIRMATION и FOF_SILENT: если файл не влезает в Корзину,
        // Windows сама спросит «удалить насовсем?»
        ..fFlags = _fofAllowUndo | _fofWantNukeWarnings | _fofNoConfirmMkdir
        ..fAnyOperationsAborted = 0
        ..hNameMappings = nullptr
        ..lpszProgressTitle = nullptr;
      _shFileOp(op);
    } catch (_) {
      // итог определяем проверкой наличия файла ниже
    } finally {
      calloc.free(buf);
      calloc.free(op);
    }
    for (final p in toMove) {
      var exists = true;
      try {
        exists = FileSystemEntity.typeSync(p, followLinks: false) !=
            FileSystemEntityType.notFound;
      } catch (_) {}
      result[p] = exists ? 'Windows не удалила файл (отмена или ошибка)' : null;
    }
    return result;
  }

  /// SHQueryRecycleBinW для [root] (nullptr — все диски). null — ошибка.
  ({int bytes, int items})? _queryBinRoot(Pointer<Utf16> root) {
    final buf = calloc<Uint8>(32);
    try {
      // x64: SHQUERYRBINFO = 24 байта (cbSize@0, i64Size@8, i64NumItems@16).
      // 20 байт (4/12) — только для 32-битного процесса.
      final is32 = sizeOf<IntPtr>() == 4;
      final cb = is32 ? 20 : 24;
      final sizeOff = is32 ? 4 : 8;
      final itemsOff = is32 ? 12 : 16;
      final list = buf.asTypedList(32);
      list.fillRange(0, 32, 0);
      final bd = ByteData.sublistView(list);
      bd.setUint32(0, cb, Endian.little);
      final hr = _queryBin(root, buf);
      if (hr != 0) return null;
      return (
        bytes: bd.getInt64(sizeOff, Endian.little),
        items: bd.getInt64(itemsOff, Endian.little),
      );
    } catch (_) {
      return null;
    } finally {
      calloc.free(buf);
    }
  }

  @override
  Future<({int bytes, int items})?> recycleBinInfo() async => _queryBinRoot(nullptr);

  @override
  Future<bool> emptyRecycleBin() async {
    try {
      final r = _emptyBin(
        0,
        nullptr,
        _sherbNoConfirmation | _sherbNoProgressUi | _sherbNoSound,
      );
      return r == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<({int free, int total})?> diskSpace(String root) async {
    final path = root.toNativeUtf16();
    final free = calloc<Uint64>();
    final total = calloc<Uint64>();
    final totalFree = calloc<Uint64>();
    try {
      final ok = _disk(path, free, total, totalFree);
      if (ok == 0) return null;
      return (free: free.value, total: total.value);
    } catch (_) {
      return null;
    } finally {
      calloc.free(path);
      calloc.free(free);
      calloc.free(total);
      calloc.free(totalFree);
    }
  }

  @override
  Future<List<String>> runningBrowsers() async {
    try {
      final r = await Process.run(
        '$_sysRoot\\System32\\tasklist.exe',
        ['/fo', 'csv', '/nh'],
        stdoutEncoding: systemEncoding,
      );
      return parseRunningBrowsers(r.stdout.toString());
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<String?> steamPath() async {
    try {
      final r = await Process.run('$_sysRoot\\System32\\reg.exe', [
        'query',
        r'HKCU\Software\Valve\Steam',
        '/v',
        'SteamPath',
      ]);
      final m = RegExp(r'SteamPath\s+REG_SZ\s+(.+)').firstMatch(r.stdout.toString());
      final v = m?.group(1)?.trim();
      if (v == null || v.isEmpty) return null;
      final p = v.replaceAll('/', r'\');
      // только абсолютный X:\… (UNC и прочее отбрасываем); полная проверка — в каталоге
      return RegExp(r'^[A-Za-z]:\\').hasMatch(p) ? p : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> openFile(String path) async {
    try {
      await Process.start('$_sysRoot\\System32\\notepad.exe', [path], mode: ProcessStartMode.detached);
    } catch (_) {
      try {
        await Process.start('$_sysRoot\\explorer.exe', [path], mode: ProcessStartMode.detached);
      } catch (_) {}
    }
  }

  @override
  Future<void> openFolder(String path) async {
    try {
      // Только существующая папка: иначе Проводник мог бы запустить файл.
      if (!Directory(path).existsSync()) return;
      await Process.start('$_sysRoot\\explorer.exe', [path], mode: ProcessStartMode.detached);
    } catch (_) {}
  }

  @override
  Future<List<RawUninstall>> readUninstallEntries() async {
    try {
      return await Isolate.run(readUninstallSync);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<String>> regSubKeys(String key) async {
    try {
      return WinRegistry.instance.subKeysOf(key);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<UninstallRun> runUninstaller(String exe, String args) async {
    // Повторная проверка: только X:\…\*.exe, который существует (msiexec/rundll32 — из System32).
    final okExe = RegExp(r'^[A-Za-z]:\\').hasMatch(exe) &&
        exe.toLowerCase().endsWith('.exe') &&
        File(exe).existsSync();
    if (!okExe) {
      return const UninstallRun(started: false, error: 'Программа удаления не найдена');
    }
    final file = exe.toNativeUtf16();
    final verb = 'open'.toNativeUtf16();
    final params = args.isEmpty ? nullptr : args.toNativeUtf16();
    final dirText = RegExp(r'^[A-Za-z]:\\').hasMatch(exe) && exe.contains(r'\')
        ? exe.substring(0, exe.lastIndexOf(r'\'))
        : null;
    final dir = dirText == null ? nullptr : dirText.toNativeUtf16();
    final info = calloc<_ShellExecInfo>();
    var handle = 0;
    try {
      info.ref
        ..cbSize = sizeOf<_ShellExecInfo>()
        ..fMask = _seeMaskNoCloseProcess | _seeMaskNoAsync
        ..hwnd = 0
        ..lpVerb = verb
        ..lpFile = file
        ..lpParameters = params.cast<Utf16>()
        ..lpDirectory = dir.cast<Utf16>()
        ..nShow = 1;
      final ok = _shellExec(info);
      if (ok == 0) {
        final err = _lastError();
        return UninstallRun(
          started: false,
          cancelled: err == _errorCancelled,
          error: 'ShellExecuteEx: код $err',
        );
      }
      handle = info.ref.hProcess;
    } catch (e) {
      return UninstallRun(started: false, error: '$e');
    } finally {
      calloc.free(file);
      calloc.free(verb);
      if (params != nullptr) calloc.free(params);
      if (dir != nullptr) calloc.free(dir);
      calloc.free(info);
    }
    if (handle == 0) {
      // процесса нет (передача другой программе): ждать нечего
      return const UninstallRun(started: true);
    }
    // Ждём до 10 минут. Дескриптор закрывает сама waitForProcessSync (в Isolate);
    // если Isolate не удалось запустить — закрываем здесь.
    ({int? code, bool timedOut}) res;
    try {
      res = await Isolate.run(() => waitForProcessSync(handle, uninstallWaitMs));
    } catch (_) {
      closeHandleSync(handle);
      res = (code: null, timedOut: false);
    }
    return UninstallRun(started: true, exitCode: res.code, timedOut: res.timedOut);
  }

  @override
  Future<bool> exportRegKey(String key, String file) async {
    if (!_regKeyAllowed(key)) return false;
    try {
      final r = await Process.run('$_sysRoot\\System32\\reg.exe', ['export', key, file, '/y']);
      if (r.exitCode != 0) return false;
      final f = File(file);
      return f.existsSync() && f.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> deleteRegKey(String key) async {
    if (!_regKeyAllowed(key)) return false;
    try {
      final r = await Process.run('$_sysRoot\\System32\\reg.exe', ['delete', key, '/f']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, String>> regStringValues(String key) async {
    try {
      return WinRegistry.instance.stringValues(key);
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<Uint8List?> regReadBinary(String key, String name) async {
    try {
      return WinRegistry.instance.readBinary(key, name);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> regWriteBinary(String key, String name, Uint8List data) async {
    try {
      return WinRegistry.instance.writeBinary(key, name, data);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> regWriteString(String key, String name, String value) async {
    try {
      return WinRegistry.instance.writeString(key, name, value);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> regDeleteValue(String key, String name) async {
    try {
      return WinRegistry.instance.deleteValue(key, name);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> regCanWrite(String key) async {
    try {
      return WinRegistry.instance.canWrite(key);
    } catch (_) {
      return false;
    }
  }

  static Pointer<Utf16>? _soundPath;

  @override
  Future<void> playDropSound(String assetPath, String dataDir) async {
    if (!Platform.isWindows) return;
    try {
      final target = File('$dataDir\\drop.wav');
      if (!target.existsSync()) {
        final src = File(assetPath);
        if (!src.existsSync()) return;
        await target.parent.create(recursive: true);
        await src.copy(target.path);
      }
      // Память под путь живёт до конца процесса: звук играет асинхронно.
      final path = _soundPath ??= target.path.toNativeUtf16();
      final playSound = DynamicLibrary.open('winmm.dll').lookupFunction<
          Int32 Function(Pointer<Utf16>, IntPtr, Uint32),
          int Function(Pointer<Utf16>, int, int)>('PlaySoundW');
      const sndAsync = 0x1, sndNoDefault = 0x2, sndFilename = 0x20000;
      playSound(path, 0, sndFilename | sndAsync | sndNoDefault);
    } catch (_) {}
  }

  @override
  Future<void> notify(String title, String text) async {
    // Всплывающая подсказка трея через PowerShell (без сторонних пакетов);
    // тексты передаются через переменные окружения, не через командную строку.
    const script = r'''
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$n = New-Object System.Windows.Forms.NotifyIcon
try { $n.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($env:CD_EXE) } catch { $n.Icon = [System.Drawing.SystemIcons]::Information }
$n.Visible = $true
$n.ShowBalloonTip(6000, $env:CD_TITLE, $env:CD_TEXT, [System.Windows.Forms.ToolTipIcon]::None)
Start-Sleep -Seconds 7
$n.Dispose()
''';
    try {
      await Process.start(
        '$_sysRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
        ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command', script],
        environment: {
          'CD_TITLE': title,
          'CD_TEXT': text,
          'CD_EXE': Platform.resolvedExecutable,
        },
      );
    } catch (_) {}
  }

  // --- режим администратора ---

  @override
  Future<bool> isElevated() async => isProcessElevated();

  @override
  Future<RelaunchResult> relaunch({required bool elevated}) async {
    final exe = Platform.resolvedExecutable;
    final held = SingleInstance.handle != 0;
    SingleInstance.release(); // иначе новый процесс увидит «уже запущено» и выйдет
    var result = RelaunchResult.failed;
    try {
      if (elevated) {
        // ShellExecuteExW ждёт ответа UAC — в отдельном Isolate, чтобы окно не «не отвечало».
        result = RelaunchResult.values[await Isolate.run(() => _runElevatedSync(exe))];
      } else {
        // Из повышенного процесса обычный запуск — через Проводник (стандартный приём).
        await Process.start('$_sysRoot\\explorer.exe', [exe], mode: ProcessStartMode.detached);
        result = RelaunchResult.started;
      }
    } catch (_) {
      result = RelaunchResult.failed;
    } finally {
      if (result != RelaunchResult.started && held) {
        try {
          SingleInstance.acquire();
        } catch (_) {}
      }
    }
    return result;
  }

  @override
  Future<int?> runTool(String exe, List<String> args) async {
    try {
      final r = await Process.run(exe, args, stdoutEncoding: null, stderrEncoding: null);
      return r.exitCode;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> runToolOutput(String exe, List<String> args) async {
    try {
      final r = await Process.run(exe, args, stdoutEncoding: const SystemEncoding());
      return r.stdout as String;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> runToolUtf8(String exe, List<String> args, {required Duration timeout}) async {
    Process? p;
    try {
      p = await Process.start(exe, args);
      final out = p.stdout.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      unawaited(p.stderr.drain<void>());
      final code = await p.exitCode.timeout(timeout);
      final bytes = await out;
      if (code != 0 && bytes.isEmpty) return null;
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      p?.kill();
      return null;
    }
  }

  @override
  Future<SysSample?> systemSample() async {
    try {
      return await sampleInWorker();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<KillResult> killProcess(int pid) async => terminateProcessByPid(pid);

  // --- значки программ ---

  /// Не более 3 одновременных извлечений значков (каждое — свой Isolate).
  final _iconPool = AsyncPool(3);

  @override
  Future<Uint8List?> programIcon(String path, int index) async {
    try {
      return await _iconPool.run(() => Isolate.run(() => extractIconPngSync(path, index)));
    } catch (_) {
      return null;
    }
  }
}

/// Запуск exe от администратора (UAC). Вызывается в отдельном Isolate;
/// возвращает индекс [RelaunchResult].
int _runElevatedSync(String exe) {
  final shell = DynamicLibrary.open('shell32.dll');
  final kernel = DynamicLibrary.open('kernel32.dll');
  final shellExec = shell.lookupFunction<_ShellExecNative, _ShellExecDart>('ShellExecuteExW');
  final lastError = kernel.lookupFunction<_LastErrNative, _LastErrDart>('GetLastError');
  final file = exe.toNativeUtf16();
  final verb = 'runas'.toNativeUtf16();
  final params = '--admin-restart'.toNativeUtf16();
  final info = calloc<_ShellExecInfo>();
  try {
    info.ref
      ..cbSize = sizeOf<_ShellExecInfo>()
      ..fMask = _seeMaskNoAsync
      ..hwnd = 0
      ..lpVerb = verb
      ..lpFile = file
      ..lpParameters = params
      ..lpDirectory = nullptr
      ..nShow = 1;
    if (shellExec(info) != 0) return RelaunchResult.started.index;
    return (lastError() == _errorCancelled ? RelaunchResult.cancelled : RelaunchResult.failed).index;
  } finally {
    calloc.free(file);
    calloc.free(verb);
    calloc.free(params);
    calloc.free(info);
  }
}
