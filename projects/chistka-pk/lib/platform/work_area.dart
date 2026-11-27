import 'dart:ffi';
import 'dart:ui';

import 'package:ffi/ffi.dart';

typedef _SpiN = Int32 Function(Uint32, Uint32, Pointer<Void>, Uint32);
typedef _SpiD = int Function(int, int, Pointer<Void>, int);

/// Рабочая область основного монитора (без панели задач), в пикселях Windows.
/// null — получить не удалось.
Rect? primaryWorkArea() {
  try {
    final u = DynamicLibrary.open('user32.dll');
    final spi = u.lookupFunction<_SpiN, _SpiD>('SystemParametersInfoW');
    final rect = calloc<Int32>(4);
    try {
      const spiGetWorkArea = 0x0030;
      if (spi(spiGetWorkArea, 0, rect.cast<Void>(), 0) == 0) return null;
      return Rect.fromLTRB(
          rect[0].toDouble(), rect[1].toDouble(), rect[2].toDouble(), rect[3].toDouble());
    } finally {
      calloc.free(rect);
    }
  } catch (_) {
    return null;
  }
}
