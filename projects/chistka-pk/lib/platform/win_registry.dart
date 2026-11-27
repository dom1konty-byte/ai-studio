import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../core/programs.dart';

// Чтение реестра через advapi32 (юникод, без reg.exe: кириллица в именах читается).

typedef _OpenN = Int32 Function(IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<IntPtr>);
typedef _OpenD = int Function(int, Pointer<Utf16>, int, int, Pointer<IntPtr>);
typedef _EnumN = Int32 Function(IntPtr, Uint32, Pointer<Utf16>, Pointer<Uint32>,
    Pointer<Uint32>, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint64>);
typedef _EnumD = int Function(int, int, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>,
    Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint64>);
typedef _QueryN = Int32 Function(
    IntPtr, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>);
typedef _QueryD = int Function(
    int, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>);
typedef _CloseN = Int32 Function(IntPtr);
typedef _CloseD = int Function(int);

// HKEY — знаковые 32-битные значения, расширенные до размера указателя.
const _hkcu = -2147483647; // 0x80000001
const _hklm = -2147483646; // 0x80000002
const _keyRead = 0x20019;
const _wow64Key64 = 0x100;
const _wow64Key32 = 0x200;
const _errorNoMoreItems = 259;
const _regSz = 1;
const _regExpandSz = 2;
const _regDword = 4;

const uninstallSubPath = r'Software\Microsoft\Windows\CurrentVersion\Uninstall';

const _valueNames = [
  'DisplayName',
  'Publisher',
  'EstimatedSize',
  'InstallDate',
  'DisplayIcon',
  'InstallLocation',
  'UninstallString',
  'QuietUninstallString',
  'SystemComponent',
  'ParentKeyName',
  'ReleaseType',
];

class WinRegistry {
  WinRegistry._();
  static final WinRegistry instance = WinRegistry._();

  final DynamicLibrary _adv = DynamicLibrary.open('advapi32.dll');
  late final _OpenD _open = _adv.lookupFunction<_OpenN, _OpenD>('RegOpenKeyExW');
  late final _EnumD _enum = _adv.lookupFunction<_EnumN, _EnumD>('RegEnumKeyExW');
  late final _QueryD _query = _adv.lookupFunction<_QueryN, _QueryD>('RegQueryValueExW');
  late final _CloseD _close = _adv.lookupFunction<_CloseN, _CloseD>('RegCloseKey');

  int? _openKey(int hive, String sub, int wow) {
    final s = sub.toNativeUtf16();
    final out = calloc<IntPtr>();
    try {
      final rc = _open(hive, s, 0, _keyRead | wow, out);
      return rc == 0 ? out.value : null;
    } finally {
      calloc.free(s);
      calloc.free(out);
    }
  }

  List<String> _subKeys(int h) {
    final res = <String>[];
    const cap = 512;
    final buf = calloc<Uint16>(cap).cast<Utf16>();
    final len = calloc<Uint32>();
    try {
      for (var i = 0;; i++) {
        len.value = cap;
        final rc = _enum(h, i, buf, len, nullptr, nullptr, nullptr, nullptr);
        if (rc == _errorNoMoreItems) break;
        if (rc != 0) continue;
        res.add(buf.toDartString(length: len.value));
      }
    } finally {
      calloc.free(buf);
      calloc.free(len);
    }
    return res;
  }

  String? _value(int h, String name) {
    final n = name.toNativeUtf16();
    final type = calloc<Uint32>();
    final size = calloc<Uint32>();
    try {
      if (_query(h, n, nullptr, type, nullptr, size) != 0) return null;
      final bytes = size.value;
      final buf = calloc<Uint8>(bytes + 4);
      try {
        size.value = bytes;
        if (_query(h, n, nullptr, type, buf, size) != 0) return null;
        final t = type.value;
        if (t == _regSz || t == _regExpandSz) {
          final units = buf.cast<Uint16>().asTypedList(size.value ~/ 2);
          return String.fromCharCodes(units.takeWhile((c) => c != 0));
        }
        if (t == _regDword && size.value >= 4) {
          return ByteData.sublistView(buf.asTypedList(4)).getUint32(0, Endian.little).toString();
        }
        return null;
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(n);
      calloc.free(type);
      calloc.free(size);
    }
  }

  static ({int hive, String sub})? parseKey(String key) {
    final i = key.indexOf(r'\');
    final head = (i < 0 ? key : key.substring(0, i)).toUpperCase();
    final sub = i < 0 ? '' : key.substring(i + 1);
    if (head == 'HKCU') return (hive: _hkcu, sub: sub);
    if (head == 'HKLM') return (hive: _hklm, sub: sub);
    return null;
  }

  /// Имена подключей ключа `HKCU\…` или `HKLM\…`.
  List<String> subKeysOf(String key) {
    final k = parseKey(key);
    if (k == null) return const [];
    final h = _openKey(k.hive, k.sub, 0);
    if (h == null) return const [];
    try {
      return _subKeys(h);
    } finally {
      _close(h);
    }
  }

  void _collect(List<RawUninstall> out, int hive, int wow, String tag, String pathForReg) {
    final root = _openKey(hive, uninstallSubPath, wow);
    if (root == null) return;
    try {
      for (final name in _subKeys(root)) {
        final h = _openKey(hive, '$uninstallSubPath\\$name', wow);
        if (h == null) continue;
        try {
          final values = <String, String>{};
          for (final v in _valueNames) {
            final s = _value(h, v);
            if (s != null) values[v] = s;
          }
          out.add(RawUninstall(tag, '$pathForReg\\$name', values));
        } finally {
          _close(h);
        }
      }
    } finally {
      _close(root);
    }
  }

  /// HKCU, HKLM и HKLM\WOW6432Node.
  List<RawUninstall> readUninstall() {
    final out = <RawUninstall>[];
    _collect(out, _hkcu, 0, 'HKCU', 'HKCU\\$uninstallSubPath');
    _collect(out, _hklm, _wow64Key64, 'HKLM', 'HKLM\\$uninstallSubPath');
    _collect(out, _hklm, _wow64Key32, 'HKLM32',
        r'HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall');
    return out;
  }
}

/// Для Isolate.run.
List<RawUninstall> readUninstallSync() => WinRegistry.instance.readUninstall();

/// Ждёт завершения процесса по дескриптору и возвращает код выхода (null — не удалось).
int? waitForProcessSync(int handle) {
  final k = DynamicLibrary.open('kernel32.dll');
  final wait = k.lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>(
      'WaitForSingleObject');
  final getCode = k.lookupFunction<Int32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)>('GetExitCodeProcess');
  final close = k.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
  final code = calloc<Uint32>();
  try {
    wait(handle, 0xFFFFFFFF);
    final ok = getCode(handle, code);
    return ok != 0 ? code.value : null;
  } finally {
    calloc.free(code);
    close(handle);
  }
}
