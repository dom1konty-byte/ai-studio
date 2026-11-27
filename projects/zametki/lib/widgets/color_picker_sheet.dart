import 'package:material_ui/material_ui.dart';

import '../models/note_colors.dart';

/// Выбор цвета заметки. Возвращает индекс 0–7 или null.
Future<int?> showColorPicker(BuildContext context, {required int selected}) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < NoteColors.count; i++)
                Semantics(
                  button: true,
                  selected: i == selected,
                  label: NoteColors.names[i],
                  child: InkWell(
                    key: Key('color_$i'),
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.pop(context, i),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: NoteColors.background(i, theme.brightness),
                        border: Border.all(
                          color: i == selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: i == selected ? 2 : 1,
                        ),
                      ),
                      child: i == selected
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
