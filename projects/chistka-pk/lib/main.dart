import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'platform/glass.dart';
import 'platform/show_guard.dart';
import 'platform/single_instance.dart';
import 'platform/tray_service.dart';
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
    await controller.loadSettings(); // только settings.json
    await windowManager.waitUntilReadyToShow(options, () async {
      if (trayOnly) {
        await windowManager.hide();
      }
      // Обычный запуск: окно показываем плавно после первого кадра (см. ниже),
      // чтобы не было белой вспышки.
    });
    // Тяжёлое (стекло, реестр, значок в трее, обновления) — после первого кадра + 300 мс (см. ChistoApp).
    if (!trayOnly) {
      controller.holdHeavy();
      // Страховка: если первый кадр не пришёл — стартуем через 4 с.
      Timer(const Duration(seconds: 4), controller.releaseHeavy);
    }
    unawaited(controller.heavyReleased.then((_) async {
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
    }));
  }
  ShowGuard? guard;
  if (Platform.isWindows && !trayOnly) {
    guard = ShowGuard(onTimeout: () async {
      try {
        await windowManager.show();
        await windowManager.setOpacity(1);
      } catch (_) {}
    })
      ..start();
  }
  runApp(ChistoApp(controller: controller, onboarding: !trayOnly));
  if (Platform.isWindows && !trayOnly) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Первый кадр главного экрана уже нарисован: показываем окно сразу, непрозрачным,
      // без анимации прозрачности (каждый вызов — канал платформы).
      await windowManager.show();
      guard?.markShown();
      await windowManager.focus();
    });
  }
}
