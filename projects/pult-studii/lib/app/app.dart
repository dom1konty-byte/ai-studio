import 'package:material_ui/material_ui.dart';

import '../state/app_controller.dart';
import '../ui/home_screen.dart';
import '../ui/motion.dart';
import '../ui/setup_screen.dart';
import 'theme.dart';

class RubkaApp extends StatelessWidget {
  const RubkaApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Studio',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (controller.starting) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return Density(
            compact: controller.compact,
            child: controller.showSetup
                ? FadeSlideIn(
                    key: const ValueKey('screen-setup'),
                    dy: 0,
                    child: SetupScreen(controller: controller))
                : FadeSlideIn(
                    key: const ValueKey('screen-home'),
                    dy: 0,
                    child: HomeScreen(controller: controller)),
          );
        },
      ),
    );
  }
}
