import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'services/app_storage.dart';
import 'services/real_process_runner.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title: 'Рубка',
      size: Size(1200, 760),
      minimumSize: Size(960, 600),
      center: true,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  final env = Platform.environment;
  final appData = env['APPDATA'] ?? env['HOME'] ?? '.';
  final home = env['USERPROFILE'] ?? env['HOME'] ?? '.';
  final controller = AppController(
    proc: RealProcessRunner(),
    storage: FileStorage(p.join(appData, 'pult-studii')),
    downloadsDir: p.join(home, 'Downloads'),
  );
  runApp(RubkaApp(controller: controller));
  controller.init();
}
