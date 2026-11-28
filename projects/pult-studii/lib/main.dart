import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'services/app_storage.dart';
import 'services/attachments.dart';
import 'services/phone_share.dart';
import 'services/real_process_runner.dart';
import 'services/windows_sleep_guard.dart';
import 'services/updater.dart';
import 'services/windows_voice.dart';
import 'services/windows_notifier.dart';
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
      title: 'AI Studio',
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
  final proc = RealProcessRunner();
  final win = Platform.isWindows;
  final attachments =
      FileAttachmentStore(p.join(appData, 'pult-studii', 'attachments'));
  // уборка остатков прошлых запусков (ошибки внутри глушатся)
  unawaited(attachments.purgeOld());
  unawaited(UpdateService.cleanOld());
  unawaited(cleanOldApkDirs());
  final controller = AppController(
    proc: proc,
    storage: FileStorage(p.join(appData, 'pult-studii')),
    downloadsDir: p.join(home, 'Downloads'),
    homeDir: home,
    attachments: attachments,
    updater: win ? UpdateService(proc) : null,
    notifier: win ? WindowsNotifier() : null,
    voice: win ? WindowsVoiceInput() : null,
    sleepGuard: win ? WindowsSleepGuard() : null,
    isWindowFocused: win ? windowManager.isFocused : null,
    showWindow: win
        ? () async {
            if (await windowManager.isMinimized()) {
              await windowManager.restore();
            }
            await windowManager.show();
            await windowManager.focus();
          }
        : null,
    // закрыть программу после запуска установщика (процессы уже остановлены)
    quitApp: win ? windowManager.destroy : null,
  );
  if (Platform.isWindows) {
    windowManager.addListener(_CloseHandler(controller));
  }
  runApp(RubkaApp(controller: controller));
  unawaited(controller.init().catchError((Object _) {}));
}
