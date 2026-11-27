import 'dart:io';
import 'dart:ui';

import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_controller.dart';
import '../ui/window_fx.dart';

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

  bool _animating = false;
  bool _hiding = false;
  bool _pendingShow = false;

  bool get _noAnimations => PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  /// Окно прозрачным сделать нельзя (рамка и заголовок системные), поэтому после
  /// анимации содержимого окно гаснет за несколько шагов прозрачности.
  Future<void> _fadeWindow({required bool toHidden}) async {
    const steps = [0.75, 0.5, 0.25];
    for (final o in toHidden ? steps : steps.reversed) {
      await windowManager.setOpacity(o);
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  /// Плавно спрятать окно: содержимое уменьшается к правому нижнему углу и
  /// затухает (220 мс, внутри Flutter), затем 3 шага прозрачности и hide.
  Future<void> hideAnimated() async {
    if (_animating) return;
    _animating = true; // синхронно, до первого await
    _hiding = true;
    try {
      if (!_noAnimations) {
        try {
          await windowFx.playHide();
          await _fadeWindow(toHidden: true);
        } catch (_) {}
      }
      await windowManager.hide();
    } finally {
      windowFx.reset();
      try {
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
    try {
      if (!_noAnimations) {
        try {
          if (!await windowManager.isVisible()) {
            windowFx.prepareShow();
            await windowManager.setOpacity(0.25);
            await windowManager.show();
            await _fadeWindow(toHidden: false);
            await windowManager.setOpacity(1);
            await windowFx.playShow();
          }
        } catch (_) {
          try {
            await windowManager.setOpacity(1);
          } catch (_) {}
        }
      }
    } finally {
      windowFx.reset();
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
