import 'package:material_ui/material_ui.dart';

/// Длительность анимации; при отключённых анимациях Windows — ноль.
Duration animDuration(BuildContext context, Duration d) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;

/// Заголовок экрана (версия 1.4): 36 px.
const screenTitleStyle = TextStyle(fontSize: 36, fontWeight: FontWeight.w600);

/// Отступ между блоками и радиус карточек (версия 1.4).
const blockGap = 24.0;
const cardRadius = 24.0;
