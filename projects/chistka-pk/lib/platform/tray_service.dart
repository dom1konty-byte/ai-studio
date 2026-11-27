import 'dart:io';
import 'dart:ui';

import 'package:flutter/animation.dart';

import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_controller.dart';
import 'work_area.dart';

/// Значок у часов, меню и «крестик сворачивает в трей».
class TrayService with TrayListener, WindowListener {
  TrayService(this.controller);
  final AppController controller;

  static const _open = 'open';
  static const _quick = 'quick';
  static const _exit = 'exit';

  Future<void> init() async {
    final icon = p.join(p.dirname(Platform.resolvedExecutable), 'data', 'flutter_assets',
        'assets', 'icon', 'app_icon.ico');
    await trayManager.setIcon(icon);
    await trayManager.setToolTip('ЧистоДиск');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: _open, label: 'Открыть'),
      MenuItem(key: _quick, label: 'Быстрая очистка'),
      MenuItem.separator(),
      MenuItem(key: _exit, label: 'Выход'),
    ]));
    trayManager.addListener(this);
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
  }

  static const _animMs = 300;
  static const _minSize = Size(900, 600);
  bool _animating = false;

  bool get _noAnimations => PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  /// Кадры от одного состояния окна к другому. [from]/[to] null — размер не меняем.
  Future<void> _play({
    Rect? from,
    Rect? to,
    required double o0,
    required double o1,
    required Curve curve,
    required int ms,
  }) async {
    final sw = Stopwatch()..start();
    while (true) {
      final t = (sw.elapsedMilliseconds / ms).clamp(0.0, 1.0);
      final k = curve.transform(t);
      if (from != null && to != null) {
        await windowManager.setBounds(Rect.lerp(from, to, k));
      }
      await windowManager.setOpacity(o0 + (o1 - o0) * k);
      if (t >= 1) break;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  /// Окно, с которого начинается/которым заканчивается «джинн»: 10 % размера
  /// у правого нижнего угла рабочей области. Рабочая область приходит в физических
  /// пикселях, а bounds окна — в логических: делим на devicePixelRatio.
  Rect? _cornerRect(Rect normal) {
    final area = primaryWorkArea();
    if (area == null) return null;
    final views = PlatformDispatcher.instance.views;
    final dpr = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    final right = area.right / dpr, bottom = area.bottom / dpr;
    final w = normal.width * 0.1, h = normal.height * 0.1;
    return Rect.fromLTWH(right - w, bottom - h, w, h);
  }

  bool _hiding = false;
  bool _pendingShow = false;

  /// Плавно спрятать окно (уменьшение к углу + затухание), затем hide.
  /// Не поддерживается что-то — только затухание. Исходные bounds/opacity возвращаются.
  Future<void> hideAnimated() async {
    if (_animating) return;
    _animating = true; // синхронно, до первого await
    _hiding = true;
    Rect? normal;
    var resized = false;
    try {
      if (!_noAnimations) {
        try {
          normal = await windowManager.getBounds();
          final canResize = !(await windowManager.isMaximized()) &&
              !(await windowManager.isFullScreen());
          final corner = canResize ? _cornerRect(normal) : null;
          if (corner != null) {
            resized = true;
            await windowManager.setMinimumSize(const Size(1, 1));
            await _play(
                from: normal, to: corner, o0: 1, o1: 0, curve: Curves.easeInCubic, ms: _animMs);
          } else {
            await _play(o0: 1, o1: 0, curve: Curves.easeInCubic, ms: 200);
          }
        } catch (_) {}
      }
      await windowManager.hide();
    } finally {
      try {
        if (resized && normal != null) await windowManager.setBounds(normal);
        await windowManager.setMinimumSize(_minSize);
        await windowManager.setOpacity(1);
      } catch (_) {}
      _animating = false;
      _hiding = false;
    }
    if (_pendingShow) {
      _pendingShow = false;
      await showWindow();
    }
  }

  Future<void> showWindow() async {
    if (_animating) {
      // «Открыть» во время сворачивания — выполним после hideAnimated.
      if (_hiding) _pendingShow = true;
      return;
    }
    _animating = true; // синхронно, до первого await
    Rect? normal;
    try {
      if (!_noAnimations) {
        try {
          if (!await windowManager.isVisible()) {
            normal = await windowManager.getBounds();
            final corner = (await windowManager.isMaximized()) ? null : _cornerRect(normal);
            await windowManager.setOpacity(0);
            if (corner != null) {
              await windowManager.setMinimumSize(const Size(1, 1));
              await windowManager.setBounds(corner);
            }
            await windowManager.show();
            await _play(
                from: corner,
                to: corner != null ? normal : null,
                o0: 0,
                o1: 1,
                curve: Curves.easeOutCubic,
                ms: corner != null ? _animMs : 200);
            if (corner != null) {
              await windowManager.setBounds(normal);
            }
            await windowManager.setMinimumSize(_minSize);
            await windowManager.setOpacity(1);
          }
        } catch (_) {
          try {
            if (normal != null) await windowManager.setBounds(normal);
            await windowManager.setMinimumSize(_minSize);
            await windowManager.setOpacity(1);
          } catch (_) {}
        }
      }
    } finally {
      _animating = false;
    }
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  Future<void> quit() async {
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() async {
    if (!controller.settings.minimizeToTray) {
      await quit();
      return;
    }
    await hideAnimated();
    if (!controller.settings.trayHintShown) {
      await controller.markTrayHintShown();
      await controller.platform
          .notify('ЧистоДиск', 'ЧистоДиск работает у часов. Выход — через меню значка.');
    }
  }

  Future<void> _quickClean() async {
    await controller.quickClean().catchError((Object _) => null);
  }

  // Значок после перезапуска Проводника (TaskbarCreated) не восстанавливается:
  // tray_manager не отдаёт оконные сообщения Windows, поэтому перехватить его нельзя.

  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _open:
        showWindow();
      case _quick:
        _quickClean();
      case _exit:
        quit();
    }
  }
}
