import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'platform/single_instance.dart';
import 'platform/tray_service.dart';
import 'platform/windows_platform.dart';
import 'state/app_controller.dart';
import 'ui/app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final trayOnly = args.contains('--tray');
  final controller = AppController(platform: WindowsPlatform());
  if (Platform.isWindows) {
    // Второй запуск: показать уже открытое окно и выйти.
    if (!SingleInstance.acquire()) {
      SingleInstance.showExisting();
      exit(0);
    }
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title: 'ЧистоДиск',
      size: Size(1000, 680),
      minimumSize: Size(900, 600),
      center: true,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (trayOnly) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });
    await controller.init();
    try {
      await TrayService(controller).init();
    } catch (_) {
      // Нет значка в трее — окно остаётся обычным.
      if (trayOnly) await windowManager.show();
    }
  }
  runApp(ChistoApp(controller: controller));
}
