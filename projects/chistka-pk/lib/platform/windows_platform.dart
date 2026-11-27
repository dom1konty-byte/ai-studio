import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../core/browsers.dart';
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
typedef _DiskNative = Int32 Function(
    Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _DiskDart = int Function(
    Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);

const _foDelete = 3;
const _fofSilent = 0x0004;
const _fofNoConfirmation = 0x0010;
const _fofAllowUndo = 0x0040;
const _fofNoErrorUi = 0x0400;
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
  late final _DiskDart _disk =
      _kernel32.lookupFunction<_DiskNative, _DiskDart>('GetDiskFreeSpaceExW');

  @override
  Future<bool> moveToRecycleBin(String path) async {
    // pFrom — строка с двумя нулями в конце
    final units = path.codeUnits;
    final buf = calloc<Uint16>(units.length + 2);
    final op = calloc<_ShFileOpStruct>();
    try {
      buf.asTypedList(units.length + 2).setAll(0, units);
      op.ref
        ..hwnd = 0
        ..wFunc = _foDelete
        ..pFrom = buf.cast<Utf16>()
        ..pTo = nullptr
        ..fFlags = _fofAllowUndo | _fofNoConfirmation | _fofSilent | _fofNoErrorUi
        ..fAnyOperationsAborted = 0
        ..hNameMappings = nullptr
        ..lpszProgressTitle = nullptr;
      final r = _shFileOp(op);
      return r == 0 && op.ref.fAnyOperationsAborted == 0;
    } catch (_) {
      return false;
    } finally {
      calloc.free(buf);
      calloc.free(op);
    }
  }

  @override
  Future<({int bytes, int items})?> recycleBinInfo() async {
    final buf = calloc<Uint8>(32);
    try {
      // SHQUERYRBINFO в SDK упакована по 1 байту (20 байт); на всякий случай пробуем и 24.
      for (final layout in const [(20, 4, 12), (24, 8, 16)]) {
        final list = buf.asTypedList(32);
        list.fillRange(0, 32, 0);
        final bd = ByteData.sublistView(list);
        bd.setUint32(0, layout.$1, Endian.little);
        final hr = _queryBin(nullptr, buf);
        if (hr == 0) {
          return (
            bytes: bd.getInt64(layout.$2, Endian.little),
            items: bd.getInt64(layout.$3, Endian.little),
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      calloc.free(buf);
    }
  }

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
        'tasklist',
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
      final r = await Process.run('reg', [
        'query',
        r'HKCU\Software\Valve\Steam',
        '/v',
        'SteamPath',
      ]);
      final m = RegExp(r'SteamPath\s+REG_SZ\s+(.+)').firstMatch(r.stdout.toString());
      final v = m?.group(1)?.trim();
      if (v == null || v.isEmpty) return null;
      return v.replaceAll('/', r'\');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> openFile(String path) async {
    try {
      await Process.start('notepad.exe', [path], mode: ProcessStartMode.detached);
    } catch (_) {
      try {
        await Process.start('explorer.exe', [path], mode: ProcessStartMode.detached);
      } catch (_) {}
    }
  }
}
