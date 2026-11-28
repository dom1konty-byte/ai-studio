import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../services/readme_parser.dart';
import 'phone_share_dialog.dart';

class BoardPanel extends StatelessWidget {
  const BoardPanel({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      color: Rubka.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Image.asset('assets/icon/app_icon.png',
                    width: 24,
                    height: 24,
                    filterQuality: FilterQuality.medium,
                    semanticLabel: 'AI Studio'),
                const SizedBox(width: 8),
                Expanded(child: Text('AI Studio', style: Rubka.head(22))),
                IconButton(
                  tooltip: 'Обновить (F5)',
                  onPressed: c.boardLoading ? null : c.refreshBoard,
                  icon: c.boardLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          _OfficeTile(controller: c),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: OutlinedButton.icon(
              onPressed: () => _newProject(context),
              icon: const Icon(Icons.add),
              label: const Text('Новый проект'),
            ),
          ),
          if (c.boardError != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
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
          const Divider(height: 1, color: Rubka.border),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: c.openSetup,
                    icon: const Icon(Icons.settings),
                    label: const Text('Настройка'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: c.toggleUsage,
                    icon: const Icon(Icons.payments),
                    label: const Text('Расходы'),
                  ),
                ),
              ],
            ),
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
          padding: const EdgeInsets.all(8),
          children: List.generate(
            3,
            (_) => Container(
              height: 72,
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                  color: Rubka.disabledBg,
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(16),
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
        for (final p in c.projects) _ProjectCard(controller: c, project: p),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.controller, required this.project});

  final AppController controller;
  final Project project;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = project;
    final selected = c.activeKey == p.slug;
    final waits = stageWaitsYes(p.stage);
    final build = c.builds[p.slug] ?? BuildRun.loading;
    return Material(
      color: selected ? Rubka.selected : Colors.transparent,
      child: InkWell(
        onTap: () {
          final msg = c.select(p);
          if (msg != null) c.toast(msg);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                  color: selected ? Rubka.primary : Colors.transparent,
                  width: 4),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(p.name,
                        overflow: TextOverflow.ellipsis,
                        style: Rubka.head(16)),
                  ),
                  if ((c.newCounts[p.slug] ?? 0) > 0)
                    _NewBadge(c.newCounts[p.slug]!),
                  if (waits)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: Rubka.amber,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('ждёт да',
                          style: Rubka.head(12, color: Rubka.onAmber)),
                    ),
                ],
              ),
              Text(p.stage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Rubka.body(size: 13, color: Rubka.text2)),
              if (c.isWorking(p.slug)) const _WorkingLine(),
              Row(
                children: [
                  Expanded(child: _BuildLine(build)),
                  if (build.state == BuildState.success && build.id != null)
                    _downloadButton(build),
                ],
              ),
              if (isAppType(p.type) &&
                  build.state == BuildState.success &&
                  build.id != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: _phoneButton(context, build),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phoneButton(BuildContext context, BuildRun build) {
    final expired = build.isExpired(DateTime.now());
    final button = FilledButton.tonal(
      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
      onPressed: expired
          ? null
          : () {
              final share = controller.startPhoneShare(project);
              if (share == null) return;
              showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => PhoneShareDialog(share: share));
            },
      child: const Text('На телефон'),
    );
    return expired
        ? Tooltip(message: 'Артефакт старше 30 дней', child: button)
        : button;
  }

  Widget _downloadButton(BuildRun build) {
    final c = controller;
    final busy = c.downloading.contains(project.slug);
    final expired = build.isExpired(DateTime.now());
    final button = TextButton(
      onPressed: busy || expired ? null : () => c.download(project),
      child: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Text('Скачать'),
    );
    return expired
        ? Tooltip(message: 'Артефакт старше 30 дней', child: button)
        : button;
  }
}

class _BuildLine extends StatelessWidget {
  const _BuildLine(this.run);

  final BuildRun run;

  @override
  Widget build(BuildContext context) {
    final Widget icon;
    final String word;
    final Color color;
    switch (run.state) {
      case BuildState.loading:
        icon = const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2));
        word = 'проверяю';
        color = Rubka.text2;
      case BuildState.running:
        icon = const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Rubka.working));
        word = 'идёт';
        color = Rubka.working;
      case BuildState.success:
        icon = const Icon(Icons.check, size: 14, color: Rubka.success);
        word = 'успех';
        color = Rubka.success;
      case BuildState.failed:
        icon = const Icon(Icons.close, size: 14, color: Rubka.error);
        word = 'ошибка';
        color = Rubka.error;
      case BuildState.unknown:
        icon = const Icon(Icons.help_outline, size: 14, color: Rubka.text2);
        word = 'нет данных';
        color = Rubka.text2;
      case BuildState.none:
        icon = const Icon(Icons.remove, size: 14, color: Rubka.text2);
        word = 'нет сборки';
        color = Rubka.text2;
    }
    return Row(
      children: [
        icon,
        const SizedBox(width: 6),
        Flexible(
          child: Text('сборка: $word',
              overflow: TextOverflow.ellipsis,
              style: Rubka.body(size: 13, color: color)),
        ),
      ],
    );
  }
}

/// Значок «новое N»: коммиты с телефона.
class _NewBadge extends StatelessWidget {
  const _NewBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Есть коммиты с телефона',
        child: Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: Rubka.primary, borderRadius: BorderRadius.circular(8)),
          child: Text('новое $count',
              style: Rubka.head(12, color: Colors.white)),
        ),
      );
}

/// «Директор работает» на карточке.
class _WorkingLine extends StatelessWidget {
  const _WorkingLine();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Rubka.working)),
          const SizedBox(width: 6),
          Text('директор работает',
              style: Rubka.body(size: 13, color: Rubka.working)),
        ],
      );
}

/// Вкладка «Офис» над списком проектов.
class _OfficeTile extends StatelessWidget {
  const _OfficeTile({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final selected = c.activeKey == officeKey;
    final n = c.newCounts[officeKey] ?? 0;
    return Material(
      color: selected ? Rubka.selected : Colors.transparent,
      child: InkWell(
        onTap: c.openOffice,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                  color: selected ? Rubka.primary : Colors.transparent,
                  width: 4),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  const Icon(Icons.apartment, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Офис', style: Rubka.head(16))),
                  if (n > 0) _NewBadge(n),
                ],
              ),
              if (c.isWorking(officeKey)) const _WorkingLine(),
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
