import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../core/png.dart';

final class _IconInfo extends Struct {
  @Int32()
  external int fIcon;
  @Uint32()
  external int xHotspot;
  @Uint32()
  external int yHotspot;
  @IntPtr()
  external int hbmMask;
  @IntPtr()
  external int hbmColor;
}

final class _Bitmap extends Struct {
  @Int32()
  external int bmType;
  @Int32()
  external int bmWidth;
  @Int32()
  external int bmHeight;
  @Int32()
  external int bmWidthBytes;
  @Uint16()
  external int bmPlanes;
  @Uint16()
  external int bmBitsPixel;
  external Pointer<Void> bmBits;
}

final class _BitmapInfoHeader extends Struct {
  @Uint32()
  external int biSize;
  @Int32()
  external int biWidth;
  @Int32()
  external int biHeight;
  @Uint16()
  external int biPlanes;
  @Uint16()
  external int biBitCount;
  @Uint32()
  external int biCompression;
  @Uint32()
  external int biSizeImage;
  @Int32()
  external int biXPelsPerMeter;
  @Int32()
  external int biYPelsPerMeter;
  @Uint32()
  external int biClrUsed;
  @Uint32()
  external int biClrImportant;
}

typedef _ExtractN = Uint32 Function(Pointer<Utf16>, Int32, Pointer<IntPtr>, Pointer<IntPtr>, Uint32);
typedef _ExtractD = int Function(Pointer<Utf16>, int, Pointer<IntPtr>, Pointer<IntPtr>, int);
typedef _GetIconInfoN = Int32 Function(IntPtr, Pointer<_IconInfo>);
typedef _GetIconInfoD = int Function(int, Pointer<_IconInfo>);
typedef _HandleN = Int32 Function(IntPtr);
typedef _HandleD = int Function(int);
typedef _GetObjectN = Int32 Function(IntPtr, Int32, Pointer<Void>);
typedef _GetObjectD = int Function(int, int, Pointer<Void>);
typedef _GetDcN = IntPtr Function(IntPtr);
typedef _GetDcD = int Function(int);
typedef _ReleaseDcN = Int32 Function(IntPtr, IntPtr);
typedef _ReleaseDcD = int Function(int, int);
typedef _GetDiBitsN = Int32 Function(
    IntPtr, IntPtr, Uint32, Uint32, Pointer<Void>, Pointer<_BitmapInfoHeader>, Uint32);
typedef _GetDiBitsD = int Function(
    int, int, int, int, Pointer<Void>, Pointer<_BitmapInfoHeader>, int);

/// Читает bitmap как 32-битные BGRA-пиксели сверху вниз (null — не вышло).
Uint8List? _readBgra(int hdc, int hbm, int w, int h, _GetDiBitsD getDiBits) {
  // BITMAPINFO для 32 бит: заголовок без таблицы цветов (запас — на всякий случай).
  final raw = calloc<Uint8>(sizeOf<_BitmapInfoHeader>() + 16);
  final bits = calloc<Uint8>(w * h * 4);
  try {
    final bi = raw.cast<_BitmapInfoHeader>();
    bi.ref
      ..biSize = sizeOf<_BitmapInfoHeader>()
      ..biWidth = w
      ..biHeight = -h // сверху вниз
      ..biPlanes = 1
      ..biBitCount = 32
      ..biCompression = 0; // BI_RGB
    final lines = getDiBits(hdc, hbm, 0, h, bits.cast<Void>(), bi, 0);
    if (lines != h) return null;
    return Uint8List.fromList(bits.asTypedList(w * h * 4));
  } finally {
    calloc.free(raw);
    calloc.free(bits);
  }
}

/// Извлекает значок (путь, номер как в DisplayIcon) и кодирует в PNG.
/// Синхронная: вызывать в отдельном Isolate. Любая ошибка → null.
Uint8List? extractIconPngSync(String path, int index) {
  final shell = DynamicLibrary.open('shell32.dll');
  final user = DynamicLibrary.open('user32.dll');
  final gdi = DynamicLibrary.open('gdi32.dll');
  final extract = shell.lookupFunction<_ExtractN, _ExtractD>('ExtractIconExW');
  final getIconInfo = user.lookupFunction<_GetIconInfoN, _GetIconInfoD>('GetIconInfo');
  final destroyIcon = user.lookupFunction<_HandleN, _HandleD>('DestroyIcon');
  final getDc = user.lookupFunction<_GetDcN, _GetDcD>('GetDC');
  final releaseDc = user.lookupFunction<_ReleaseDcN, _ReleaseDcD>('ReleaseDC');
  final deleteObject = gdi.lookupFunction<_HandleN, _HandleD>('DeleteObject');
  final getObject = gdi.lookupFunction<_GetObjectN, _GetObjectD>('GetObjectW');
  final getDiBits = gdi.lookupFunction<_GetDiBitsN, _GetDiBitsD>('GetDIBits');

  final file = path.toNativeUtf16();
  final large = calloc<IntPtr>();
  final small = calloc<IntPtr>();
  final info = calloc<_IconInfo>();
  final bmp = calloc<_Bitmap>();
  var hdc = 0;
  try {
    final n = extract(file, index, large, small, 1);
    if (n == 0 || large.value == 0) return null;
    try {
      if (getIconInfo(large.value, info) == 0) return null;
      final hColor = info.ref.hbmColor;
      final hMask = info.ref.hbmMask;
      try {
        if (hColor == 0) return null; // чёрно-белый значок — не показываем
        if (getObject(hColor, sizeOf<_Bitmap>(), bmp.cast<Void>()) == 0) return null;
        final w = bmp.ref.bmWidth;
        final h = bmp.ref.bmHeight;
        if (w <= 0 || h <= 0 || w > 256 || h > 256) return null;
        hdc = getDc(0);
        if (hdc == 0) return null;
        final color = _readBgra(hdc, hColor, w, h, getDiBits);
        if (color == null) return null;
        var hasAlpha = false;
        for (var i = 3; i < color.length; i += 4) {
          if (color[i] != 0) {
            hasAlpha = true;
            break;
          }
        }
        Uint8List? mask;
        if (!hasAlpha && hMask != 0) mask = _readBgra(hdc, hMask, w, h, getDiBits);
        final rgba = Uint8List(w * h * 4);
        for (var i = 0; i < w * h; i++) {
          final o = i * 4;
          rgba[o] = color[o + 2];
          rgba[o + 1] = color[o + 1];
          rgba[o + 2] = color[o];
          rgba[o + 3] = hasAlpha
              ? color[o + 3]
              : (mask != null ? (mask[o] == 0 ? 255 : 0) : 255); // маска: чёрный — виден
        }
        return encodePngRgba(w, h, rgba);
      } finally {
        if (hColor != 0) deleteObject(hColor);
        if (hMask != 0) deleteObject(hMask);
      }
    } finally {
      destroyIcon(large.value);
      if (small.value != 0) destroyIcon(small.value);
    }
  } catch (_) {
    return null;
  } finally {
    if (hdc != 0) releaseDc(0, hdc);
    calloc.free(file);
    calloc.free(large);
    calloc.free(small);
    calloc.free(info);
    calloc.free(bmp);
  }
}
