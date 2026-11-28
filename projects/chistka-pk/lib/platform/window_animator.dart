import 'dart:async';
import 'dart:ui';

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';

import '../ui/glass.dart' show windowShown;
import '../ui/window_fx.dart';

/// Прозрачность окна в момент [t] (0..1) анимации: показ — easeOutCubic, 0 → 1;
/// скрытие — easeInCubic, 1 → 0.
double fadeOpacity(double t, {required bool show}) {
  final k = t.clamp(0.0, 1.0);
  return show ? Curves.easeOutCubic.transform(k) : 1 - Curves.easeInCubic.transform(k);
}

/// Плавный показ и скрытие окна: прозрачность окна по кадрам (Ticker)
/// + масштаб содержимого. AnimateWindow не используется (чёрный контент Flutter).
class WindowAnimator {
  bool get noAnimations => PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  /// Показать окно плавно (окно сейчас скрыто).
  Future<void> show() async {
    windowShown.value = true;
    if (noAnimations) {
      await windowManager.show();
      return;
    }
    windowFx.prepareShow();
    final fx = windowFx.playShow();
    try {
      await windowManager.setOpacity(0);
      await windowManager.show();
      await _fade(show: true, ms: windowFxShowDuration.inMilliseconds);
    } finally {
      await _opaque();
    }
    await fx;
  }

  /// Спрятать окно плавно.
  Future<void> hide() async {
    if (!noAnimations) {
      final fx = windowFx.playHide();
      try {
        await _fade(show: false, ms: windowFxHideDuration.inMilliseconds);
      } catch (_) {}
      await fx;
    }
    await windowManager.hide();
    windowShown.value = false;
    windowFx.reset();
    await _opaque();
  }

  Future<void> _opaque() async {
    try {
      await windowManager.setOpacity(1);
    } catch (_) {}
  }

  /// Прозрачность окна по кадрам: один вызов setOpacity за кадр, без ожидания.
  Future<void> _fade({required bool show, required int ms}) {
    final done = Completer<void>();
    late final Ticker ticker;
    ticker = Ticker((elapsed) {
      final t = (elapsed.inMicroseconds / (ms * 1000)).clamp(0.0, 1.0);
      unawaited(windowManager.setOpacity(fadeOpacity(t, show: show)).catchError((Object _) {}));
      if (t >= 1 && !done.isCompleted) {
        ticker.stop();
        done.complete();
      }
    });
    ticker.start();
    return done.future.whenComplete(ticker.dispose);
  }
}
