import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../core/browsers.dart';
import '../core/whitelist.dart';
import 'platform_api.dart';

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

const _foDelete = 3;
const _fofAllowUndo = 0x0040;
const _fofNoConfirmMkdir = 0x0200;
const _fofWantNukeWarnings = 0x4000;
const _driveFixed = 3;
const _sherbNoConfirmation = 0x1;
const _sherbNoProgressUi = 0x2;
const _sherbNoSound = 0x4;

class WindowsPlatform implements PlatformApi {
  late final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');
  late final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  late final _ShFileOpDart _shFileOp =
      _shell32.lookupFunction<_ShFileOpNative, _ShFileOpDart>('SHFileOperationW');
  late final _QueryBinDart _queryBin =
      _shell32.lookupFunction<_QueryBinNative, _QueryBinDart>('SHQueryRecycleBinW');
  late final _EmptyBinDart _emptyBin =
      _shell32.lookupFunction<_EmptyBinNative, _EmptyBinDart>('SHEmptyRecycleBinW');
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
}
