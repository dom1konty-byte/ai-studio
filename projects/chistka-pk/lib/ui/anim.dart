import 'package:material_ui/material_ui.dart';

/// Длительность анимации; при отключённых анимациях Windows — ноль.
Duration animDuration(BuildContext context, Duration d) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
