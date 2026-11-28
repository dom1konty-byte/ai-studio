import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'services/app_storage.dart';
import 'services/real_process_runner.dart';
import 'state/app_controller.dart';

/// Закрытие окна во время хода: сначала остановить директора.
class _CloseHandler with WindowListener {
  _CloseHandler(this.controller);

  final AppController controller;

  @override
  void onWindowClose() async {
    try {
      await controller.stopAll();
    } catch (_) {}
    await windowManager.destroy();
  }
}

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
    await windowManager.setPreventClose(true);
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
    homeDir: home,
  );
  if (Platform.isWindows) {
    windowManager.addListener(_CloseHandler(controller));
  }
  runApp(RubkaApp(controller: controller));
  unawaited(controller.init().catchError((Object _) {}));
}
