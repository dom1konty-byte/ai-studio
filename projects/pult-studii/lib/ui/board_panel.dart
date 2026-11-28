import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../services/readme_parser.dart';

/// Цвет точки проекта: янтарь — ждёт «да», красный — сборка упала,
/// зелёный — сборка ок, серый — в работе или сборки нет.
Color projectDotColor(Project p, BuildRun build) {
  if (stageWaitsYes(p.stage)) return Rubka.amber;
  switch (build.state) {
    case BuildState.failed:
      return Rubka.error;
    case BuildState.success:
      return Rubka.success;
    case BuildState.loading:
    case BuildState.running:
    case BuildState.unknown:
    case BuildState.none:
      return Rubka.dotGray;
  }
}

String _dotHint(Color c) {
  if (c == Rubka.amber) {
    return 'Жёлтая точка — проект ждёт твоего «да». Нажми, чтобы ответить.';
  }
  if (c == Rubka.error) return 'Красная точка — последняя сборка упала.';
  if (c == Rubka.success) return 'Зелёная точка — последняя сборка прошла.';
  return 'Серая точка — проект в работе или сборки ещё нет.';
}

class BoardPanel extends StatelessWidget {
  const BoardPanel({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      color: Rubka.side,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OfficeTile(controller: c),
          const _Sep(),
          if (c.boardError != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
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
          Expanded(child: _list(c)),
          const _Sep(),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('new-project'),
              style: TextButton.styleFrom(
                foregroundColor: Rubka.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onPressed: () => _newProject(context),
              child: Text('＋ Новый проект',
                  style: Rubka.head(15, color: Rubka.primary)),
            ),
          ),
          const _Legend(),
          Row(
            children: [
              IconButton(
                key: const Key('btn-setup'),
                tooltip: 'Настройка: проверка Git, Node, Claude Code и папки',
                onPressed: c.openSetup,
                icon: const Icon(Icons.settings, size: 24),
              ),
              IconButton(
                key: const Key('btn-usage'),
                tooltip: 'Расходы: сколько потрачено на директора',
                onPressed: c.toggleUsage,
                icon: const Icon(Icons.payments, size: 24),
              ),
              const Spacer(),
              IconButton(
                key: const Key('btn-refresh'),
                tooltip: 'Обновить список (F5)',
                onPressed: c.boardLoading ? null : c.refreshBoard,
                icon: c.boardLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 24),
              ),
            ],
          ),
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
              height: 44,
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                  color: Rubka.disabledBg,
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        );
      }
      return Padding(
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
      );
    }
    return ListView(
      children: [
        for (final p in c.projects) _ProjectTile(controller: c, project: p),
      ],
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        color: Rubka.line,
      );
}

class _Dot extends StatelessWidget {
  const _Dot({super.key, required this.color, required this.message});

  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: message,
        child: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(t, style: Rubka.body(size: 12, color: Rubka.mute)),
          ],
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          item(Rubka.amber, 'ждёт тебя'),
          item(Rubka.success, 'всё ок'),
          item(Rubka.error, 'сборка упала'),
          item(Rubka.dotGray, 'в работе'),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const Tooltip(
        message: 'Директор работает',
        child: SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Rubka.working)),
      );
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.controller, required this.project});

  final AppController controller;
  final Project project;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = project;
    final selected = c.activeKey == p.slug;
    final build = c.builds[p.slug] ?? BuildRun.loading;
    final color = projectDotColor(p, build);
    final fresh = (c.newCounts[p.slug] ?? 0) > 0;
    return Material(
        color: selected ? Rubka.sideSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: Key('project-${p.slug}'),
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            final msg = c.select(p);
            if (msg != null) c.toast(msg);
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _Dot(
                    key: Key('dot-${p.slug}'),
                    color: color,
                    message: '${_dotHint(color)}\nЭтап: ${p.stage}'),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(p.name,
                      overflow: TextOverflow.ellipsis,
                      style: Rubka.body(
                          weight: selected || fresh
                              ? FontWeight.w700
                              : FontWeight.w400)),
                ),
                if (fresh)
                  Tooltip(
                    message: 'Есть коммиты с телефона',
                    child: Container(
                      key: Key('new-${p.slug}'),
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          color: Rubka.primary, shape: BoxShape.circle),
                    ),
                  ),
                if (c.isWorking(p.slug)) ...[
                  const SizedBox(width: 8),
                  const _Spinner(),
                ],
              ],
            ),
          ),
        ),
    );
  }
}

/// «Офис» над списком проектов.
class _OfficeTile extends StatelessWidget {
  const _OfficeTile({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final selected = c.activeKey == officeKey;
    final fresh = (c.newCounts[officeKey] ?? 0) > 0;
    return Tooltip(
      message: 'Офис студии: общие вопросы, новые проекты',
      child: Material(
        color: selected ? Rubka.sideSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: const Key('office-tile'),
          borderRadius: BorderRadius.circular(10),
          onTap: c.openOffice,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.apartment, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Офис',
                      style: Rubka.body(
                          weight: selected || fresh
                              ? FontWeight.w700
                              : FontWeight.w400)),
                ),
                if (c.isWorking(officeKey)) const _Spinner(),
              ],
            ),
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
