import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'platform/glass.dart';
import 'platform/single_instance.dart';
import 'platform/tray_service.dart';
import 'platform/window_animator.dart';
import 'platform/windows_platform.dart';
import 'state/app_controller.dart';
import 'ui/app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final trayOnly = args.contains('--tray');
  // Перезапуск с другими правами: старый процесс ещё закрывается, мьютекс он уже отпустил.
  final adminRestart = args.contains('--admin-restart');
  final controller = AppController(platform: WindowsPlatform());
  if (Platform.isWindows) {
    // Второй запуск: показать уже открытое окно и выйти (при --tray — просто выйти).
    var first = SingleInstance.acquire();
    for (var i = 0; !first && adminRestart && i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      first = SingleInstance.acquire();
    }
    if (!first) {
      if (!trayOnly) SingleInstance.showExisting();
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
      }
      // Обычный запуск: окно показываем плавно после первого кадра (см. ниже),
      // чтобы не было белой вспышки.
    });
    await initGlass(dark: PlatformDispatcher.instance.platformBrightness == Brightness.dark);
    await controller.init();
    try {
      final tray = TrayService(controller);
      controller.exitApp = () async {
        await tray.quit();
        exit(0);
      };
      await tray.init();
    } catch (_) {
      // Нет значка в трее — окно остаётся обычным.
      if (trayOnly) await windowManager.show();
    }
    // Проверка обновлений: при запуске в трее — через минуту.
    unawaited(controller.autoCheckUpdates(
        delay: trayOnly ? const Duration(minutes: 1) : const Duration(seconds: 3)));
  }
  runApp(ChistoApp(controller: controller, splash: !trayOnly));
  if (Platform.isWindows && !trayOnly) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Даём движку нарисовать первый кадр заставки в скрытом окне.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      try {
        await WindowAnimator().show();
      } catch (_) {
        await windowManager.show();
      }
      await windowManager.focus();
    });
  }
}
