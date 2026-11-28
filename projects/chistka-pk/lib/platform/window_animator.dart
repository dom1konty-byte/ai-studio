import 'dart:async';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';

import '../ui/window_fx.dart';
import 'window_blend.dart';

const windowBlendMs = 280;

/// Плавный показ и скрытие окна: AnimateWindow (AW_BLEND) + масштаб содержимого.
/// Нет AnimateWindow — запасной вариант: прозрачность окна кадрами (Ticker).
class WindowAnimator {
  WindowAnimator({WindowBlend? blend}) : _blend = blend ?? Win32WindowBlend();
  final WindowBlend _blend;

  bool get noAnimations => PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  /// Показать окно плавно (окно сейчас скрыто).
  Future<void> show() async {
    if (noAnimations) {
      await windowManager.show();
      return;
    }
    windowFx.prepareShow();
    final fx = windowFx.playShow();
    var ok = false;
    try {
      ok = await _blend.show(windowBlendMs);
    } catch (_) {}
    if (!ok) {
      try {
        await windowManager.setOpacity(0);
        await windowManager.show();
        await _fade(0, 1);
      } finally {
        await _opaque();
      }
    }
    await fx;
  }

  /// Спрятать окно плавно.
  Future<void> hide() async {
    if (!noAnimations) {
      final fx = windowFx.playHide();
      var ok = false;
      try {
        ok = await _blend.hide(windowBlendMs);
      } catch (_) {}
      if (!ok) {
        try {
          await _fade(1, 0);
        } catch (_) {}
      }
      await fx;
    }
    await windowManager.hide();
    windowFx.reset();
    await _opaque();
  }

  Future<void> _opaque() async {
    try {
      await windowManager.setOpacity(1);
    } catch (_) {}
  }

  /// Прозрачность окна по кадрам, [windowBlendMs] мс.
  Future<void> _fade(double from, double to) {
    final done = Completer<void>();
    var busy = false;
    late final Ticker ticker;
    ticker = Ticker((elapsed) {
      final t = (elapsed.inMicroseconds / (windowBlendMs * 1000)).clamp(0.0, 1.0);
      final o = from + (to - from) * t;
      if (!busy) {
        busy = true;
        windowManager.setOpacity(o).whenComplete(() => busy = false);
      }
      if (t >= 1 && !done.isCompleted) {
        ticker.stop();
        done.complete();
      }
    });
    ticker.start();
    return done.future.whenComplete(ticker.dispose);
  }
}
