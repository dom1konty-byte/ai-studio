import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:window_manager/window_manager.dart';

const miniSize = Size(360, 480);
const _normalSize = Size(1000, 680);
const _normalMin = Size(900, 600);
const _margin = 12.0;

/// Позиция мини-окна (логические px): правый нижний угол рабочей области
/// (над часами) с отступом. [area] — рабочая область в физических px,
/// [dpr] — devicePixelRatio.
Offset miniPosition(Rect area, double dpr) {
  final d = dpr <= 0 ? 1.0 : dpr;
  return Offset(
    area.right / d - miniSize.width - _margin,
    area.bottom / d - miniSize.height - _margin,
  );
}

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

/// Рабочая область основного монитора (без панели задач), физические px.
Rect? workArea() {
  if (!Platform.isWindows) return null;
  final r = calloc<_Rect>();
  try {
    final spi = DynamicLibrary.open('user32.dll').lookupFunction<
        Int32 Function(Uint32, Uint32, Pointer<_Rect>, Uint32),
        int Function(int, int, Pointer<_Rect>, int)>('SystemParametersInfoW');
    const spiGetWorkArea = 0x30;
    if (spi(spiGetWorkArea, 0, r, 0) == 0) return null;
    return Rect.fromLTRB(
        r.ref.left.toDouble(), r.ref.top.toDouble(), r.ref.right.toDouble(), r.ref.bottom.toDouble());
  } catch (_) {
    return null;
  } finally {
    calloc.free(r);
  }
}

/// Переключает то же окно между обычным видом и мини-режимом.
class MiniWindow {
  Rect? _saved;
  bool _on = false;

  Future<void> apply(bool mini) async {
    if (mini == _on) return;
    _on = mini;
    try {
      if (mini) {
        if (await windowManager.isVisible() && !await windowManager.isMinimized()) {
          _saved = await windowManager.getBounds();
        }
        final view = PlatformDispatcher.instance.views.firstOrNull;
        final dpr = view?.devicePixelRatio ?? 1.0;
        final area = workArea() ??
            Rect.fromLTWH(0, 0, (view?.display.size.width ?? 1920),
                (view?.display.size.height ?? 1080) - 48 * dpr);
        final pos = miniPosition(area, dpr);
        await windowManager.setMinimumSize(miniSize);
        await windowManager.setResizable(false);
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
        await windowManager.setSkipTaskbar(true);
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setBounds(pos & miniSize);
      } else {
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setSkipTaskbar(false);
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        await windowManager.setResizable(true);
        await windowManager.setMinimumSize(_normalMin);
        final s = _saved;
        if (s != null) {
          await windowManager.setBounds(s);
        } else {
          await windowManager.setSize(_normalSize);
          await windowManager.center();
        }
      }
    } catch (_) {}
  }
}
