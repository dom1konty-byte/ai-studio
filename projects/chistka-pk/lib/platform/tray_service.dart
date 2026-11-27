import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_controller.dart';

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

  Future<void> showWindow() async {
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
    await windowManager.hide();
    if (!controller.settings.trayHintShown) {
      await controller.markTrayHintShown();
      await controller.platform
          .notify('ЧистоДиск', 'ЧистоДиск работает у часов. Выход — через меню значка.');
    }
  }

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
        controller.quickClean();
      case _exit:
        quit();
    }
  }
}
