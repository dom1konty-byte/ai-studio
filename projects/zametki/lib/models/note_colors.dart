import 'package:material_ui/material_ui.dart';

/// Цвета заметок (индекс 0–7 хранится в базе, цвет берётся по теме).
class NoteColors {
  static const count = 8;

  static const names = [
    'Без цвета',
    'Красный',
    'Оранжевый',
    'Жёлтый',
    'Зелёный',
    'Бирюзовый',
    'Синий',
    'Фиолетовый',
  ];

  static const _light = [
    Color(0xFFEDF2EE),
    Color(0xFFFFD9D6),
    Color(0xFFFFE0B8),
    Color(0xFFFFF2B3),
    Color(0xFFD3F0C8),
    Color(0xFFC4F0EA),
    Color(0xFFD2E4FF),
    Color(0xFFE8DCFF),
  ];

  static const _dark = [
    Color(0xFF232A26),
    Color(0xFF5C2B29),
    Color(0xFF5A3A12),
    Color(0xFF54480F),
    Color(0xFF26492A),
    Color(0xFF1E4A46),
    Color(0xFF263F63),
    Color(0xFF43326A),
  ];

  static Color background(int index, Brightness brightness) {
    final i = index.clamp(0, count - 1);
    return brightness == Brightness.dark ? _dark[i] : _light[i];
  }

  static Color text(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFFE6E1E5) : const Color(0xFF1C1B1F);
}
