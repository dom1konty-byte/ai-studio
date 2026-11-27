import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'platform/windows_platform.dart';
import 'state/app_controller.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title: 'ЧистоДиск',
      size: Size(1000, 680),
      minimumSize: Size(900, 600),
      center: true,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  final controller = AppController(platform: WindowsPlatform());
  runApp(ChistoApp(controller: controller));
}
