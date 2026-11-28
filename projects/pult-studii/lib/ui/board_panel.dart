import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../models/models.dart';
import '../services/notifications.dart';
import '../services/readme_parser.dart';
import '../state/app_controller.dart';

/// Цветная метка проекта: текст, фон и цвет текста.
typedef ProjectTag = ({String label, Color bg, Color fg});

/// Метка: ждёт «да», сборка ок, сборка упала, в работе.
ProjectTag projectTag(Project p, BuildRun build) {
  if (stageWaitsYes(p.stage)) {
    return (label: 'ждёт «да»', bg: Rubka.tagWaitBg, fg: Rubka.tagWaitFg);
  }
  switch (build.state) {
    case BuildState.failed:
      return (
        label: 'сборка упала',
        bg: Rubka.tagBadBg,
        fg: Rubka.tagBadFg
      );
    case BuildState.success:
      return (label: 'сборка ок', bg: Rubka.tagOkBg, fg: Rubka.tagOkFg);
    case BuildState.loading:
    case BuildState.running:
    case BuildState.unknown:
    case BuildState.none:
      return (label: 'в работе', bg: Rubka.tagIdleBg, fg: Rubka.tagIdleFg);
  }
}

/// Белая плитка со скруглением 22.
class BentoTile extends StatelessWidget {
  const BentoTile({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 16),
    this.color = Colors.white,
    this.gradient,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: gradient == null ? color : null,
            gradient: gradient,
            borderRadius: BorderRadius.circular(22)),
        child: child,
      );
}

/// Плитка «Проекты»: список с метками, «＋ Новый», обновление.
/// [compact] — узкая колонка (без этапа в строке).
class BoardPanel extends StatelessWidget {
  const BoardPanel({super.key, required this.controller, this.compact = false});

  final AppController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return BentoTile(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Проекты',
                    style: Rubka.head(16, weight: FontWeight.w700)),
              ),
              IconButton(
                key: const Key('btn-refresh'),
                tooltip: 'Обновить список (F5)',
                visualDensity: VisualDensity.compact,
                onPressed: c.boardLoading ? null : c.refreshBoard,
                icon: c.boardLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 20),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Новый проект',
                child: InkWell(
                  key: const Key('new-project'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _newProject(context),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                        color: Rubka.ink,
                        borderRadius: BorderRadius.circular(16)),
                    child: Text('＋ Новый',
                        style: Rubka.body(
                            size: 12,
                            color: Colors.white,
                            weight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
          if (c.boardError != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Rubka.errorBg, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(c.boardError!,
                      style: Rubka.mono(size: 12, color: Rubka.error)),
                  TextButton(
                      onPressed: c.refreshBoard, child: const Text('Повторить')),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Expanded(child: _list(c)),
        ],
      ),
    );
  }

  Future<void> _newProject(BuildContext context) async {
    final res = await showDialog<_NewProject>(
        context: context, builder: (_) => const _NewProjectDialog());
    if (res == null) return;
    final err = await controller.startNewProject(
        name: res.name, type: res.type, idea: res.idea);
    if (err != null) controller.toast(err);
  }

  Widget _list(AppController c) {
    if (c.projects.isEmpty) {
      if (c.boardLoading) {
        return ListView(
          children: List.generate(
            3,
            (_) => Container(
              height: 40,
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                  color: Rubka.disabledBg,
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        );
      }
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Проектов пока нет. Проверь, что выбрана папка ai-studio.',
                  style: Rubka.body(color: Rubka.text2)),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: c.openSetup, child: const Text('Выбрать папку')),
            ],
          ),
        ),
      );
    }
    return ListView(
      children: [
        for (final p in c.projects)
          _ProjectRow(controller: c, project: p, compact: compact),
      ],
    );
  }
}

/// Пульсирующая точка «директор работает».
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Директор работает',
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.25, end: 1).animate(_ctl),
          child: Container(
            key: const Key('working-dot'),
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
                color: Rubka.orange2, shape: BoxShape.circle),
          ),
        ),
      );
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow(
      {required this.controller, required this.project, required this.compact});

  final AppController controller;
  final Project project;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = project;
    final selected = c.activeKey == p.slug;
    final build = c.builds[p.slug] ?? BuildRun.loading;
    final tag = projectTag(p, build);
    final fresh = (c.newCounts[p.slug] ?? 0) > 0;
    return Material(
      color: selected ? Rubka.bubble : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: Key('project-${p.slug}'),
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          final msg = c.select(p);
          if (msg != null) c.toast(msg);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              if (c.isWorking(p.slug)) ...[
                const _PulseDot(),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 3,
                child: Text(p.name,
                    overflow: TextOverflow.ellipsis,
                    style: Rubka.body(
                        size: 13,
                        weight: selected || fresh
                            ? FontWeight.w700
                            : FontWeight.w600)),
              ),
              if (!compact)
                Expanded(
                  flex: 3,
                  child: Text(stageName(p.stage),
                      overflow: TextOverflow.ellipsis,
                      style: Rubka.body(size: 13, color: Rubka.ink2)),
                ),
              if (fresh)
                Tooltip(
                  message: 'Есть коммиты с телефона',
                  child: Container(
                    key: Key('new-${p.slug}'),
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: const BoxDecoration(
                        color: Rubka.send, shape: BoxShape.circle),
                  ),
                ),
              Flexible(
                flex: 2,
                child: Tooltip(
                message: 'Этап: ${p.stage}',
                child: Container(
                  key: Key('tag-${p.slug}'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                      color: tag.bg, borderRadius: BorderRadius.circular(10)),
                  child: Text(tag.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Rubka.body(
                          size: 11,
                          color: tag.fg,
                          weight: FontWeight.w600)),
                ),
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewProject {
  const _NewProject(this.name, this.type, this.idea);

  final String name;
  final String type;
  final String idea;
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _name = TextEditingController();
  final _idea = TextEditingController();
  String _type = newProjectTypes.keys.first;

  @override
  void dispose() {
    _name.dispose();
    _idea.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && _idea.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый проект'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 80,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Имя проекта'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Тип'),
              items: [
                for (final e in newProjectTypes.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _idea,
              minLines: 3,
              maxLines: 8,
              maxLength: 2000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Идея', alignLabelWithHint: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(
                  context,
                  _NewProject(_name.text.trim(), _type, _idea.text.trim()))
              : null,
          child: const Text('Создать'),
        ),
      ],
    );
  }
}
