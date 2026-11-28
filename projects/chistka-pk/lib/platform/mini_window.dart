import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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

/// Действие по клику на значок в трее.
enum TrayClickAction { openMini, focusWindow }

/// Обычное окно видно и не свёрнуто (и это не мини) — просто на передний план;
/// иначе (скрыто в трее / свёрнуто / уже мини) — мини-окно.
TrayClickAction trayClickAction({
  required bool visible,
  required bool minimized,
  required bool miniMode,
}) =>
    visible && !minimized && !miniMode ? TrayClickAction.focusWindow : TrayClickAction.openMini;

/// Границы обычного окна, запомненные перед скрытием / мини-режимом.
class SavedBounds {
  Rect? _r;
  void save(Rect r) => _r = r;

  /// Забирает границы (после этого их нет). Нет сохранённых — null.
  Rect? take() {
    final r = _r;
    _r = null;
    return r;
  }

  Rect? get value => _r;
}

/// Переключает то же окно между обычным видом и мини-режимом.
/// Вызовы идут строго по очереди, параллельно не выполняются.
class MiniWindow {
  MiniWindow({@visibleForTesting this._body});
  final Future<void> Function(bool mini)? _body;

  final bounds = SavedBounds();
  bool _on = false;
  Future<void> _queue = Future<void>.value();

  bool get isOn => _on;

  Future<void> apply(bool mini) {
    final next = _queue.then((_) => _apply(mini));
    _queue = next.catchError((Object _) {});
    return next;
  }

  /// Запомнить границы обычного окна (при каждом его скрытии и перед мини).
  Future<void> saveBounds() async {
    try {
      if (_on) return;
      if (await windowManager.isVisible() && !await windowManager.isMinimized()) {
        bounds.save(await windowManager.getBounds());
      }
    } catch (_) {}
  }

  Future<void> _apply(bool mini) async {
    if (mini == _on) return;
    try {
      await (_body ?? _real)(mini);
      _on = mini; // только после успешного применения
    } catch (_) {}
  }

  Future<void> _real(bool mini) async {
    if (mini) {
      await saveBounds();
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
      final s = bounds.take();
      if (s != null) {
        await windowManager.setBounds(s);
      } else {
        await windowManager.setSize(_normalSize);
        await windowManager.center();
      }
    }
  }
}
