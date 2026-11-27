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
typedef _EnumValN = Int32 Function(IntPtr, Uint32, Pointer<Utf16>, Pointer<Uint32>,
    Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>);
typedef _EnumValD = int Function(int, int, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>,
    Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>);
typedef _CreateN = Int32 Function(IntPtr, Pointer<Utf16>, Uint32, Pointer<Utf16>, Uint32,
    Uint32, Pointer<Void>, Pointer<IntPtr>, Pointer<Uint32>);
typedef _CreateD = int Function(int, Pointer<Utf16>, int, Pointer<Utf16>, int, int,
    Pointer<Void>, Pointer<IntPtr>, Pointer<Uint32>);
typedef _SetValN = Int32 Function(IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<Uint8>, Uint32);
typedef _SetValD = int Function(int, Pointer<Utf16>, int, int, Pointer<Uint8>, int);
typedef _DelValN = Int32 Function(IntPtr, Pointer<Utf16>);
typedef _DelValD = int Function(int, Pointer<Utf16>);

// HKEY — знаковые 32-битные значения, расширенные до размера указателя.
const _hkcu = -2147483647; // 0x80000001
const _hklm = -2147483646; // 0x80000002
const _keyRead = 0x20019;
const _wow64Key64 = 0x100;
const _wow64Key32 = 0x200;
const _errorNoMoreItems = 259;
const _errorMoreData = 234;
const _maxEnum = 200000; // страховка от бесконечного цикла
const _keyCreateSubKey = 0x4;
const _regSz = 1;
const _regExpandSz = 2;
const _regDword = 4;
const _regBinary = 3;
const _keyWrite = 0x20006; // KEY_SET_VALUE | KEY_CREATE_SUB_KEY | READ_CONTROL
const _keySetValue = 0x2;
const _errorFileNotFound = 2;

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

  late final _EnumValD _enumVal = _adv.lookupFunction<_EnumValN, _EnumValD>('RegEnumValueW');
  late final _CreateD _create = _adv.lookupFunction<_CreateN, _CreateD>('RegCreateKeyExW');
  late final _SetValD _setVal = _adv.lookupFunction<_SetValN, _SetValD>('RegSetValueExW');
  late final _DelValD _delVal = _adv.lookupFunction<_DelValN, _DelValD>('RegDeleteValueW');

  int? _openKey(int hive, String sub, int wow, [int access = _keyRead]) {
    final s = sub.toNativeUtf16();
    final out = calloc<IntPtr>();
    try {
      final rc = _open(hive, s, 0, access | wow, out);
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
      for (var i = 0; i < _maxEnum; i++) {
        len.value = cap;
        final rc = _enum(h, i, buf, len, nullptr, nullptr, nullptr, nullptr);
        if (rc == _errorNoMoreItems) break;
        if (rc == _errorMoreData) continue; // слишком длинное имя — пропускаем
        if (rc != 0) break;
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

  // ---------- значения (автозагрузка, настройки) ----------

  /// Все строковые значения ключа: имя → данные (пусто, если ключа нет).
  Map<String, String> stringValues(String key) {
    final k = parseKey(key);
    if (k == null) return const {};
    final h = _openKey(k.hive, k.sub, 0);
    if (h == null) return const {};
    final res = <String, String>{};
    const cap = 16384;
    final buf = calloc<Uint16>(cap).cast<Utf16>();
    final len = calloc<Uint32>();
    try {
      for (var i = 0; i < _maxEnum; i++) {
        len.value = cap;
        final rc = _enumVal(h, i, buf, len, nullptr, nullptr, nullptr, nullptr);
        if (rc == _errorNoMoreItems) break;
        if (rc == _errorMoreData) continue; // слишком длинное имя — пропускаем
        if (rc != 0) break;
        final name = buf.toDartString(length: len.value);
        final v = _value(h, name);
        if (v != null) res[name] = v;
      }
    } finally {
      calloc.free(buf);
      calloc.free(len);
      _close(h);
    }
    return res;
  }

  /// Двоичное значение (null — нет значения или другой тип).
  Uint8List? readBinary(String key, String name) {
    final k = parseKey(key);
    if (k == null) return null;
    final h = _openKey(k.hive, k.sub, 0);
    if (h == null) return null;
    final n = name.toNativeUtf16();
    final type = calloc<Uint32>();
    final size = calloc<Uint32>();
    try {
      if (_query(h, n, nullptr, type, nullptr, size) != 0) return null;
      final bytes = size.value;
      final buf = calloc<Uint8>(bytes + 1);
      try {
        size.value = bytes;
        if (_query(h, n, nullptr, type, buf, size) != 0 || type.value != _regBinary) return null;
        return Uint8List.fromList(buf.asTypedList(size.value));
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(n);
      calloc.free(type);
      calloc.free(size);
      _close(h);
    }
  }

  bool _write(String key, String name, int type, Uint8List data) {
    final k = parseKey(key);
    if (k == null) return false;
    final sub = k.sub.toNativeUtf16();
    final out = calloc<IntPtr>();
    try {
      if (_create(k.hive, sub, 0, nullptr, 0, _keyWrite, nullptr, out, nullptr) != 0) {
        return false;
      }
      final h = out.value;
      final n = name.toNativeUtf16();
      final buf = calloc<Uint8>(data.length + 1);
      try {
        buf.asTypedList(data.length).setAll(0, data);
        return _setVal(h, n, 0, type, buf, data.length) == 0;
      } finally {
        calloc.free(n);
        calloc.free(buf);
        _close(h);
      }
    } finally {
      calloc.free(sub);
      calloc.free(out);
    }
  }

  bool writeBinary(String key, String name, Uint8List data) =>
      _write(key, name, _regBinary, data);

  /// REG_SZ (с завершающим нулём).
  bool writeString(String key, String name, String value) {
    final units = Uint16List(value.length + 1)..setAll(0, value.codeUnits);
    return _write(key, name, _regSz, units.buffer.asUint8List());
  }

  /// Удаляет ТОЛЬКО значение [name]; ключ не трогает. true — значения теперь нет.
  bool deleteValue(String key, String name) {
    final k = parseKey(key);
    if (k == null) return false;
    final h = _openKey(k.hive, k.sub, 0, _keySetValue);
    if (h == null) return false;
    final n = name.toNativeUtf16();
    try {
      final rc = _delVal(h, n);
      return rc == 0 || rc == _errorFileNotFound;
    } finally {
      calloc.free(n);
      _close(h);
    }
  }

  /// Можно ли писать значения в ключ: открываем с KEY_SET_VALUE. Если ключа ещё
  /// нет — проверяем KEY_CREATE_SUB_KEY у ближайшего существующего родителя
  /// (чтобы создать ключ и значение).
  bool canWrite(String key) {
    final k = parseKey(key);
    if (k == null) return false;
    var sub = k.sub;
    var wanted = _keySetValue;
    for (var guard = 0; guard < 64; guard++) {
      final s = sub.toNativeUtf16();
      final out = calloc<IntPtr>();
      try {
        final rc = _open(k.hive, s, 0, wanted, out);
        if (rc == 0) {
          _close(out.value);
          return true;
        }
        if (rc != _errorFileNotFound || sub.isEmpty) return false;
      } finally {
        calloc.free(s);
        calloc.free(out);
      }
      final i = sub.lastIndexOf(r'\');
      sub = i < 0 ? '' : sub.substring(0, i);
      wanted = _keyCreateSubKey; // ключа нет: нужно право создавать подключи у родителя
    }
    return false;
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

/// Ждать процесс удаления не дольше 10 минут.
const uninstallWaitMs = 10 * 60 * 1000;

/// Закрывает дескриптор процесса.
void closeHandleSync(int handle) {
  try {
    final k = DynamicLibrary.open('kernel32.dll');
    final close = k.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
    close(handle);
  } catch (_) {}
}

/// Ждёт завершения процесса по дескриптору (до [timeoutMs]) и возвращает код
/// выхода. Никогда не бросает исключений; дескриптор закрывается всегда.
({int? code, bool timedOut}) waitForProcessSync(int handle, int timeoutMs) {
  try {
    final k = DynamicLibrary.open('kernel32.dll');
    final wait = k.lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>(
        'WaitForSingleObject');
    final getCode = k.lookupFunction<Int32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)>('GetExitCodeProcess');
    final code = calloc<Uint32>();
    try {
      final w = wait(handle, timeoutMs);
      if (w == 0x102) return (code: null, timedOut: true); // WAIT_TIMEOUT
      final ok = getCode(handle, code);
      return (code: ok != 0 ? code.value : null, timedOut: false);
    } finally {
      calloc.free(code);
    }
  } catch (_) {
    return (code: null, timedOut: false);
  } finally {
    closeHandleSync(handle);
  }
}
