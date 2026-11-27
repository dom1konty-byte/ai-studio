import 'package:material_ui/material_ui.dart';

import '../state/app_controller.dart';
import 'shell.dart';

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

class ChistoApp extends StatefulWidget {
  const ChistoApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<ChistoApp> createState() => _ChistoAppState();
}

class _ChistoAppState extends State<ChistoApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.init();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ЧистоДиск',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: Shell(controller: widget.controller),
    );
  }
}
