import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import 'motion.dart';

/// Чёрная полоса значков 64 px. [active]: overview / chats / office / setup.
class StudioRail extends StatelessWidget {
  const StudioRail({
    super.key,
    required this.active,
    required this.onOverview,
    required this.onChats,
    required this.onOffice,
    required this.onSetup,
  });

  final String active;
  final VoidCallback onOverview;
  final VoidCallback onChats;
  final VoidCallback onOffice;
  final VoidCallback onSetup;

  Widget _item(Key key, IconData icon, String tip, bool on, VoidCallback tap) =>
      Tooltip(
        message: tip,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(14),
          onTap: tap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: on ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon,
                size: 20, color: on ? Rubka.ink : const Color(0xFF9AA0A6)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final compact = Density.compactOf(context);
    return Container(
      width: compact ? 56 : 64,
      decoration: const BoxDecoration(
        color: Rubka.ink,
        borderRadius: BorderRadius.only(
            topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      padding: EdgeInsets.symmetric(vertical: compact ? 10 : 16),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration:
                const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Text('AI',
                style: Rubka.head(13, weight: FontWeight.w700, color: Rubka.ink)),
          ),
          const SizedBox(height: 14),
          _item(const Key('nav-overview'), Icons.home_outlined,
              'Обзор (Ctrl+1)', active == 'overview', onOverview),
          const SizedBox(height: 14),
          _item(const Key('nav-chats'), Icons.chat_bubble_outline,
              'Чаты (Ctrl+2)', active == 'chats', onChats),
          const SizedBox(height: 14),
          _item(const Key('office-tile'), Icons.apartment,
              'Офис студии: общие вопросы, новые проекты (Ctrl+3)',
              active == 'office', onOffice),
          const Spacer(),
          _item(const Key('btn-setup'), Icons.settings_outlined,
              'Настройка: проверка Git, Node, Claude Code и папки',
              active == 'setup', onSetup),
        ],
      ),
    );
  }
}
