import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_controller.dart';
import '../ui/window_fx.dart';
import 'mini_window.dart';
import 'window_animator.dart';

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
    controller.miniWindowHook = _mini.apply;
    controller.hideMiniHook = hideMini;
    trayManager.addListener(this);
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
  }

  final animator = WindowAnimator();
  final _mini = MiniWindow();
  bool _miniBusy = false;
  DateTime _miniHiddenAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Клик по значку: мини-окно у часов (двойной щелчок tray_manager не отдаёт,
  /// поэтому работает одиночный левый клик; «Открыть» — в меню).
  Future<void> showMini() async {
    if (_miniBusy) return;
    // Клик по значку сам отнимает фокус и прячет мини-окно — не открываем заново.
    if (DateTime.now().difference(_miniHiddenAt).inMilliseconds < 400) return;
    _miniBusy = true;
    try {
      if (_animating) return;
      if (!controller.miniMode) await controller.setMiniMode(true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await windowManager.show();
      await windowManager.focus();
      controller.resumeComputerPolling();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    } catch (_) {
    } finally {
      _miniBusy = false;
    }
  }

  /// Спрятать мини-окно и вернуть обычный вид (пока окно скрыто).
  Future<void> hideMini() async {
    if (!controller.miniMode) return;
    _miniHiddenAt = DateTime.now();
    try {
      await windowManager.hide();
    } catch (_) {}
    controller.pauseComputerPolling();
    await controller.setMiniMode(false);
  }

  @override
  void onWindowBlur() {
    if (controller.miniMode && !_miniBusy) hideMini();
  }

  bool _animating = false;
  bool _hiding = false;
  bool _pendingShow = false;

  /// Плавно спрятать окно: AnimateWindow (AW_BLEND, 280 мс) + масштаб содержимого.
  Future<void> hideAnimated() async {
    if (_animating) return;
    _animating = true; // синхронно, до первого await
    _hiding = true;
    controller.pauseComputerPolling();
    try {
      await animator.hide();
    } catch (_) {
      try {
        await windowManager.hide();
      } catch (_) {}
    } finally {
      windowFx.reset();
      _animating = false;
      _hiding = false;
    }
    if (_pendingShow) {
      _pendingShow = false;
      await showWindow();
    }
  }

  Future<void> showWindow() async {
    if (controller.miniMode) {
      // Из мини-окна — обратно в обычное, окно остаётся на экране.
      await controller.setMiniMode(false);
      await windowManager.show();
      await windowManager.focus();
      return;
    }
    if (_animating) {
      // «Открыть» во время сворачивания — выполним после hideAnimated.
      if (_hiding) _pendingShow = true;
      return;
    }
    _animating = true; // синхронно, до первого await
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      if (!await windowManager.isVisible()) await animator.show();
    } catch (_) {
      try {
        await windowManager.setOpacity(1);
      } catch (_) {}
    } finally {
      windowFx.reset();
      _animating = false;
    }
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
    controller.resumeComputerPolling();
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
  void onTrayIconMouseDown() => showMini();

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
