import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_controller.dart';
import '../ui/glass.dart' show windowShown;
import 'mini_window.dart';
import 'window_hide.dart';

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

  final _mini = MiniWindow();
  bool _miniBusy = false;
  bool _hidingMini = false;
  DateTime _miniHiddenAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Клик по значку: мини-окно у часов (двойной щелчок tray_manager не отдаёт,
  /// поэтому работает одиночный левый клик; «Открыть» — в меню).
  Future<void> showMini() async {
    if (_miniBusy) return;
    // Обычное окно уже на экране — только на передний план, без мини.
    try {
      final act = trayClickAction(
        visible: await windowManager.isVisible(),
        minimized: await windowManager.isMinimized(),
        miniMode: controller.miniMode,
      );
      if (act == TrayClickAction.focusWindow) {
        await windowManager.focus();
        return;
      }
    } catch (_) {}
    // Клик по значку сам отнимает фокус и прячет мини-окно — не открываем заново.
    if (DateTime.now().difference(_miniHiddenAt).inMilliseconds < 400) return;
    _miniBusy = true;
    try {
      if (!controller.miniMode) await controller.setMiniMode(true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      windowShown.value = true;
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
    if (!controller.miniMode || _hidingMini) return;
    _hidingMini = true;
    try {
      _miniHiddenAt = DateTime.now();
      try {
        await windowManager.hide();
      } catch (_) {}
      windowShown.value = false;
      controller.pauseComputerPolling();
      await controller.setMiniMode(false);
    } finally {
      _hidingMini = false;
    }
  }

  @override
  void onWindowBlur() {
    if (controller.miniMode && !_miniBusy) hideMini();
  }

  /// Спрятать окно сразу, без анимации: волны и опрос останавливаются,
  /// границы окна запоминаются.
  Future<void> hideAnimated() => hideWindowNow(
        pause: () {
          windowShown.value = false;
          controller.pauseComputerPolling();
        },
        saveBounds: _mini.saveBounds,
        hide: windowManager.hide,
      );

  Future<void> showWindow() async {
    if (controller.miniMode) {
      // Из мини-окна — обратно в обычное, окно остаётся на экране.
      await controller.setMiniMode(false);
      windowShown.value = true;
      await windowManager.show();
      await windowManager.focus();
      return;
    }
    windowShown.value = true;
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
    } catch (_) {}
    await windowManager.show();
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
