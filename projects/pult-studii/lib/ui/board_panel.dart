import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../services/readme_parser.dart';

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
                Expanded(child: Text('Рубка', style: Rubka.head(22))),
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
            child: TextButton.icon(
              onPressed: c.openSetup,
              icon: const Icon(Icons.settings),
              label: const Text('Настройка'),
            ),
          ),
        ],
      ),
    );
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
    final selected = c.chat?.slug == p.slug;
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
                  if (c.newMarks.contains(p.slug))
                    Tooltip(
                      message: 'Есть коммиты с телефона',
                      child: Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(left: 6),
                        decoration: const BoxDecoration(
                            color: Rubka.primary, shape: BoxShape.circle),
                      ),
                    ),
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
              Row(
                children: [
                  Expanded(child: _BuildLine(build)),
                  if (build.state == BuildState.success && build.id != null)
                    _downloadButton(build),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
