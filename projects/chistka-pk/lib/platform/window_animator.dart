import 'dart:async';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import '../ui/glass.dart' show windowShown;
import '../ui/window_fx.dart';

/// Прозрачность окна на время анимации: ставится один раз, не покадрово.
const windowMidOpacity = 0.6;

/// Плавный показ и скрытие окна. Главное — анимация содержимого внутри Flutter
/// (масштаб + затухание, [WindowFx]). Прозрачность самого окна меняется
/// двумя вызовами за анимацию (середина и конец), а не каждый кадр:
/// вызовы через канал платформы асинхронны и давали дёрганье.
class WindowAnimator {
  bool get noAnimations => PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  /// Показать окно плавно (окно сейчас скрыто). Волны фона включит вызывающий после показа.
  Future<void> show() async {
    if (noAnimations) {
      windowShown.value = true;
      await windowManager.show();
      return;
    }
    windowFx.prepareShow();
    final fx = windowFx.playShow();
    try {
      await windowManager.setOpacity(windowMidOpacity);
      await windowManager.show();
      // Середина анимации — окно становится непрозрачным (один вызов).
      unawaited(Future<void>.delayed(windowFxShowDuration ~/ 2).then((_) => _opacity(1)));
      await fx;
    } finally {
      await _opacity(1);
    }
    windowShown.value = true;
  }

  /// Спрятать окно плавно. Волны и опрос останавливаются сразу.
  Future<void> hide() async {
    windowShown.value = false;
    if (!noAnimations) {
      final fx = windowFx.playHide();
      // Вторая половина: окно слегка прозрачное (один вызов).
      unawaited(Future<void>.delayed(windowFxHideDuration ~/ 2)
          .then((_) => _opacity(windowMidOpacity)));
      try {
        await fx;
      } catch (_) {}
    }
    await windowManager.hide();
    windowFx.reset();
    await _opacity(1);
  }

  Future<void> _opacity(double v) async {
    try {
      await windowManager.setOpacity(v);
    } catch (_) {}
  }
}
