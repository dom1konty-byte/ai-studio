import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../state/app_controller.dart';
import '../platform/glass.dart';
import 'glass.dart';
import 'mini_view.dart';
import 'onboarding.dart';
import 'shell.dart';
import 'window_fx.dart';

const brandTeal = Color(0xFF0F9D9A);
const brandTealDark = Color(0xFF0B7C7A);
const warningColor = Color(0xFFB26A00);
const successColor = Color(0xFF2E7D32);

ThemeData _theme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: brandTeal, brightness: b);
  final light = b == Brightness.light;
  return ThemeData(
    useMaterial3: true,
    colorScheme: light
        ? scheme.copyWith(primary: brandTealDark, surface: Colors.white)
        : scheme,
    scaffoldBackgroundColor: light ? const Color(0xFFF4FAFA) : null,
    fontFamily: 'Segoe UI',
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(120, 48),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(120, 48),
        shape: const StadiumBorder(),
      ),
    ),
  );
}

/// Пауза после первого кадра перед тяжёлой инициализацией.
const heavyDelay = Duration(milliseconds: 300);

class ChistoApp extends StatefulWidget {
  const ChistoApp(
      {super.key, required this.controller, this.onboarding = false});
  final AppController controller;

  /// Подсказки первого запуска (в тестах — нет, если не включены).
  final bool onboarding;

  @override
  State<ChistoApp> createState() => _ChistoAppState();
}

class _ChistoAppState extends State<ChistoApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.init();
    // Тяжёлая инициализация — после первого кадра + 300 мс, чтобы окно открылось мгновенно.
    if (widget.controller.heavyHeld) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _heavyTimer = Timer(heavyDelay, widget.controller.releaseHeavy);
      });
    }
  }

  Timer? _heavyTimer;

  @override
  void dispose() {
    _heavyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ЧистоДиск',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) => ListenableBuilder(
        listenable: Listenable.merge([widget.controller, glassAvailable]),
        builder: (context, _) => GlassScope(
          on: widget.controller.settings.transparentPanel && glassAvailable.value,
          child: WindowFxHost(
            child: Onboarding(
              controller: widget.controller,
              enabled: widget.onboarding,
              child: child ?? const SizedBox(),
            ),
          ),
        ),
      ),
      home: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => widget.controller.miniMode
            ? MiniView(controller: widget.controller)
            : Shell(controller: widget.controller),
      ),
    );
  }
}
