import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Проверка «скрытый или системный» по пути.
typedef HiddenCheck = bool Function(String path);

const _attrHidden = 0x2;
const _attrSystem = 0x4;

typedef _GetAttrC = Uint32 Function(Pointer<Utf16>);
typedef _GetAttrDart = int Function(Pointer<Utf16>);

_GetAttrDart? _getAttr;

/// Атрибуты файла Windows (GetFileAttributesW); null — не Windows или ошибка.
int? fileAttributes(String path) {
  if (!Platform.isWindows) return null;
  try {
    _getAttr ??= DynamicLibrary.open('kernel32.dll')
        .lookupFunction<_GetAttrC, _GetAttrDart>('GetFileAttributesW');
    final p = path.toNativeUtf16();
    try {
      final r = _getAttr!(p);
      return r == 0xFFFFFFFF ? null : r;
    } finally {
      calloc.free(p);
    }
  } catch (_) {
    return null;
  }
}

String _baseName(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? path : path.substring(i + 1);
}

/// Скрытое по имени: начинается с точки, desktop.ini, thumbs.db.
bool isHiddenName(String path) {
  final n = _baseName(path).toLowerCase();
  return n.startsWith('.') || n == 'desktop.ini' || n == 'thumbs.db';
}

/// Скрытый/системный файл или папка: по имени или по атрибутам Windows.
bool isHiddenOrSystem(String path) {
  if (isHiddenName(path)) return true;
  final a = fileAttributes(path);
  return a != null && (a & (_attrHidden | _attrSystem)) != 0;
}

const _attrOffline = 0x1000;
const _attrRecallOnOpen = 0x40000;
const _attrRecallOnDataAccess = 0x400000;

/// Файл только в облаке (OneDrive и др.): чтение содержимого скачало бы его.
bool isCloudAttributes(int attrs) =>
    (attrs & (_attrOffline | _attrRecallOnOpen | _attrRecallOnDataAccess)) != 0;

/// По пути: true, если у файла облачные атрибуты (не Windows или ошибка — false).
bool isCloudOnly(String path) {
  final a = fileAttributes(path);
  return a != null && isCloudAttributes(a);
}
