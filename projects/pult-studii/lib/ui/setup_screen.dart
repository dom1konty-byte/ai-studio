import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../app/theme.dart';
import '../services/setup_service.dart';
import '../state/app_controller.dart';
import '../state/wizard_controller.dart';

/// «Настройка» = мастер первого запуска.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final WizardController _w;
  late final TextEditingController _folder;
  late final TextEditingController _repo;

  static const _titles = [
    'Программы',
    'Вход в GitHub',
    'Вход в Claude',
    'Папка студии',
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _w = WizardController(
      service: SetupService(c.proc, c.storage),
      defaultFolder: p.join(c.homeDir, 'ai-studio'),
      initialFolder: c.repoPath,
      onFinish: (folder) async {
        await c.setRepoPath(folder);
        if (c.setupOk) {
          c.closeSetup();
          return true;
        }
        return false;
      },
    );
    _folder = TextEditingController(text: _w.folder);
    _repo = TextEditingController(text: _w.repoSlug);
    _w.refresh(pickStep: true);
  }

  @override
  void dispose() {
    _w.dispose();
    _folder.dispose();
    _repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _w,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Мастер первого запуска', style: Rubka.head(24)),
                  const SizedBox(height: 4),
                  Text(
                      'Рубка сама поставит всё нужное. Иди по шагам слева направо.',
                      style: Rubka.body(color: Rubka.text2)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 220, child: _nav()),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SingleChildScrollView(
                            child: _content(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Rubka.border),
                  _footer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _nav() {
    final done = _w.stepsDone;
    return Column(
      children: [
        for (var i = 0; i < _titles.length; i++)
          Material(
            color: i == _w.step ? Rubka.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: ListTile(
              dense: true,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              leading: Icon(done[i] ? Icons.check_circle : Icons.circle_outlined,
                  color: done[i] ? Rubka.success : Rubka.text2),
              title: Text('${i + 1}. ${_titles[i]}', style: Rubka.body(size: 14)),
              onTap: () => _w.goTo(i),
            ),
          ),
      ],
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          if (_w.step > 0)
            OutlinedButton(
                onPressed: () => _w.goTo(_w.step - 1), child: const Text('Назад')),
          if (_w.step > 0) const SizedBox(width: 8),
          if (_w.step < 3)
            OutlinedButton(
                onPressed: () => _w.goTo(_w.step + 1), child: const Text('Далее')),
          const SizedBox(width: 12),
          if (_w.checking)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
          if (_w.finishMessage.isNotEmpty)
            Expanded(
                child: Text(_w.finishMessage,
                    style: Rubka.body(size: 13, color: Rubka.error)))
          else
            const Spacer(),
          FilledButton(
            onPressed: _w.allDone && !_w.busy ? _w.finish : null,
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    switch (_w.step) {
      case 0:
        return _programs();
      case 1:
        return _login(
          title: 'Вход в GitHub',
          text: 'GitHub — сайт, где хранится студия. Нужно один раз войти '
              'в свой аккаунт.',
          done: _w.ghDone,
          message: _w.ghMessage,
          startLabel: 'Войти в GitHub',
          onStart: _w.launchGhLogin,
          onCheck: _w.checkGh,
        );
      case 2:
        return _login(
          title: 'Вход в Claude',
          text: 'Claude — помощник, который работает в студии. '
              'Нужно один раз войти в свой аккаунт.',
          done: _w.claudeDone,
          message: _w.claudeMessage,
          startLabel: 'Войти в Claude',
          onStart: _w.launchClaudeLogin,
          onCheck: _w.checkClaude,
        );
      default:
        return _studio();
    }
  }

  Widget _statusLine(bool ok, String text) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ok ? Icons.check_circle : Icons.info_outline,
                color: ok ? Rubka.success : Rubka.text2, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text, style: Rubka.body(size: 14, color: Rubka.text))),
          ],
        ),
      );

  // ---------- Шаг 1 ----------

  Widget _programs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Программы', style: Rubka.head(20)),
        const SizedBox(height: 4),
        Text(
            'Уже стоящие отмечены галочкой и не трогаются. Для остальных '
            'нажми «Установить выбранное».',
            style: Rubka.body(color: Rubka.text2)),
        if (!_w.wingetOk)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Rubka.summaryBg, borderRadius: BorderRadius.circular(8)),
            child: Text(
                'Установщика winget нет — это нормально. Рубка скачает '
                'программы с официальных сайтов сама. Microsoft Store не нужен.',
                style: Rubka.body(size: 14)),
          ),
        const SizedBox(height: 8),
        for (final t in _w.tools) _toolRow(t),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton(
              onPressed: _w.hasSelection && !_w.busy
                  ? _w.installSelected
                  : null,
              child: const Text('Установить выбранное'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _w.busy || _w.checking ? null : _w.refresh,
              child: const Text('Проверить снова'),
            ),
          ],
        ),
        if (_w.installMessage.isNotEmpty)
          _statusLine(_w.programsDone, _w.installMessage),
        const SizedBox(height: 8),
        Text(
            'Поставил, а Рубка не видит? Закрой и снова открой Рубку — она '
            'подхватит новые настройки Windows.',
            style: Rubka.body(size: 13, color: Rubka.text2)),
      ],
    );
  }

  Widget _toolRow(ToolItem t) {
    final Widget lead;
    if (t.run == InstallRun.running) {
      lead = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (t.installed) {
      lead = const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.check_circle, color: Rubka.success),
      );
    } else {
      lead = Checkbox(
        value: t.selected,
        onChanged: _w.busy ? null : (v) => _w.toggle(t.spec.id, v ?? false),
      );
    }
    final sub = t.installed
        ? 'уже установлено'
        : (t.run == InstallRun.failed
            ? 'не получилось'
            : (t.run == InstallRun.running && t.status.isNotEmpty
                ? t.statusText
                : t.spec.hint));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 48, height: 48, child: Center(child: lead)),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.spec.title, style: Rubka.head(16)),
                  Text(sub,
                      style: Rubka.body(
                          size: 13,
                          color: t.run == InstallRun.failed
                              ? Rubka.error
                              : Rubka.text2)),
                  if (t.log.isNotEmpty && !t.installed)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Rubka.codeBg,
                          borderRadius: BorderRadius.circular(8)),
                      child: SelectableText(t.log, style: Rubka.mono(size: 12)),
                    ),
                  if (t.run == InstallRun.failed && !t.installed)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: OutlinedButton(
                        onPressed: _w.busy ? null : () => _w.retry(t.spec.id),
                        child: const Text('Повторить'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Шаги 2 и 3 ----------

  Widget _login({
    required String title,
    required String text,
    required bool done,
    required String message,
    required String startLabel,
    required VoidCallback onStart,
    required VoidCallback onCheck,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Rubka.head(20)),
        const SizedBox(height: 4),
        Text(text, style: Rubka.body(color: Rubka.text2)),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton(
                onPressed: _w.busy ? null : onStart, child: Text(startLabel)),
            const SizedBox(width: 8),
            OutlinedButton(
                onPressed: _w.busy ? null : onCheck,
                child: const Text('Проверить')),
          ],
        ),
        if (done) _statusLine(true, 'Готово: вход выполнен.'),
        if (message.isNotEmpty) _statusLine(false, message),
      ],
    );
  }

  // ---------- Шаг 4 ----------

  Widget _studio() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Папка студии', style: Rubka.head(20)),
        const SizedBox(height: 4),
        Text(
            'Здесь на компьютере будут лежать файлы студии. Рубка скачает их '
            'сама, если их ещё нет.',
            style: Rubka.body(color: Rubka.text2)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Rubka.codeBg, borderRadius: BorderRadius.circular(8)),
          child: SelectableText(_w.folder, style: Rubka.mono()),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (_w.folderState == FolderState.needsClone)
              FilledButton(
                  onPressed: _w.busy ? null : _w.downloadStudio,
                  child: const Text('Скачать студию')),
            if (_w.folderState == FolderState.needsClone)
              const SizedBox(width: 8),
            OutlinedButton(
                onPressed: _w.busy ? null : _w.checkFolder,
                child: const Text('Проверить')),
          ],
        ),
        if (_w.folderDone) _statusLine(true, 'Готово: ${_w.folderMessage}'),
        if (!_w.folderDone && _w.folderMessage.isNotEmpty)
          _statusLine(false, _w.folderMessage),
        const SizedBox(height: 12),
        ExpansionTile(
          title: const Text('Указать папку вручную'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            TextField(
              controller: _folder,
              decoration: _dec('Папка', r'C:\Users\...\ai-studio'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _repo,
              onChanged: (_) => setState(() {}),
              decoration: _dec('Откуда скачать (владелец/название)', defaultRepoSlug),
            ),
            if (_repo.text.trim().isNotEmpty && !isValidRepoSlug(_repo.text))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Нужно вида владелец/название, без пробелов.',
                    style: Rubka.body(size: 13, color: Rubka.error)),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _w.busy
                    ? null
                    : () {
                        _w.setRepoSlug(_repo.text);
                        _w.setFolder(_folder.text);
                      },
                child: const Text('Применить'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _dec(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}
