import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../app/theme.dart';
import '../models/models.dart';
import '../services/setup_service.dart';
import '../state/app_controller.dart';
import '../state/wizard_controller.dart';
import 'board_panel.dart';
import 'studio_rail.dart';

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
    'Вид и уведомления',
  ];

  /// Пятый шаг «Уведомления» живёт только в окне (мастер знает 4 шага).
  bool _notify = false;

  int get _cur => _notify ? 4 : _w.step;

  void _go(int i) {
    if (i < 0 || i >= _titles.length) return;
    if (i == 4) {
      setState(() => _notify = true);
    } else {
      setState(() => _notify = false);
      _w.goTo(i);
    }
  }

  void _leave() => widget.controller.closeSetup();

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _w = WizardController(
      service: SetupService(c.proc, c.storage),
      defaultFolder: p.join(c.homeDir, 'ai-studio'),
      initialFolder: c.repoPath,
      copyText: (t) => Clipboard.setData(ClipboardData(text: t)),
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
    c.cancelLogin = _w.cancelGhLogin;
    _w.refresh(pickStep: true);
  }

  @override
  void dispose() {
    widget.controller.cancelLogin = null;
    _w.dispose();
    _folder.dispose();
    _repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Rubka.bento,
      body: ListenableBuilder(
        listenable: _w,
        builder: (context, _) => Row(
          children: [
            StudioRail(
                active: 'setup',
                onOverview: _leave,
                onChats: _leave,
                onOffice: _leave,
                onSetup: () {}),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Мастер первого запуска',
                        overflow: TextOverflow.ellipsis,
                        style: Rubka.head(26, weight: FontWeight.w700)),
                    Text(
                        'Программа сама поставит всё нужное. Иди по шагам.',
                        overflow: TextOverflow.ellipsis,
                        style: Rubka.body(color: Rubka.ink2)),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 240, child: _nav()),
                          const SizedBox(width: 14),
                          Expanded(
                            child: BentoTile(
                              padding: EdgeInsets.zero,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(22),
                                child: _content(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _footer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nav() {
    final done = _w.stepsDone;
    return BentoTile(
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        child: Column(
          children: [
            for (var i = 0; i < _titles.length; i++)
              _navItem(i, i < done.length && done[i]),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int i, bool done) {
    final cur = i == _cur;
    final Color circle = done ? Rubka.yes : (cur ? Rubka.ink : Rubka.bento);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: cur ? Rubka.bento : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key('step-$i'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => _go(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: circle, shape: BoxShape.circle),
                  child: done
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text('${i + 1}',
                          style: Rubka.body(
                              size: 13,
                              weight: FontWeight.w700,
                              color: cur ? Colors.white : Rubka.ink2)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_titles[i],
                      overflow: TextOverflow.ellipsis,
                      style: Rubka.body(
                          size: 14,
                          weight: cur ? FontWeight.w700 : FontWeight.w500)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    return Row(
      children: [
        if (_w.checking)
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
        if (_w.checking) const SizedBox(width: 8),
        Expanded(
          child: _w.finishMessage.isNotEmpty
              ? Text(_w.finishMessage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Rubka.body(size: 13, color: Rubka.error))
              : const SizedBox.shrink(),
        ),
        if (_cur > 0)
          OutlinedButton(
              onPressed: () => _go(_cur - 1), child: const Text('Назад')),
        if (_cur > 0) const SizedBox(width: 8),
        if (_cur < _titles.length - 1)
          FilledButton(
              onPressed: () => _go(_cur + 1), child: const Text('Далее')),
        if (_cur < _titles.length - 1) const SizedBox(width: 8),
        FilledButton(
          onPressed: _w.allDone && !_w.busy ? _w.finish : null,
          child: const Text('Готово'),
        ),
      ],
    );
  }

  Widget _h(String title, String text) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Rubka.head(26, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(text, style: Rubka.body(color: Rubka.ink2)),
        ],
      );

  Widget _content() {
    if (_notify) return _notifications();
    switch (_w.step) {
      case 0:
        return _programs();
      case 1:
        return _github();
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
                color: ok ? Rubka.yes : Rubka.ink2, size: 20),
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
        _h('Программы',
            'Уже стоящие отмечены и не трогаются. Для остальных нажми '
                '«Установить выбранное».'),
        if (!_w.wingetOk)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Rubka.tagWaitBg, borderRadius: BorderRadius.circular(16)),
            child: Text(
                'Установщика winget нет — это нормально. AI Studio скачает '
                'программы с официальных сайтов сама. Microsoft Store не нужен.',
                style: Rubka.body(size: 14)),
          ),
        const SizedBox(height: 12),
        for (final t in _w.tools) _toolRow(t),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _w.hasSelection && !_w.busy
                  ? _w.installSelected
                  : null,
              child: const Text('Установить выбранное'),
            ),
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
            'Поставил, а AI Studio не видит? Закрой и снова открой AI Studio — он '
            'подхватит новые настройки Windows.',
            style: Rubka.body(size: 13, color: Rubka.ink2)),
      ],
    );
  }

  /// Переключатели уведомлений Windows (хранятся в state.json).
  Widget _notifications() {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _h('Вид и уведомления',
              'Плотность интерфейса и то, о чём Windows будет сообщать, '
              'пока AI Studio работает.'),
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            decoration: BoxDecoration(
                color: Rubka.bento, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Expanded(
                    child: Text('Компактный режим',
                        style: Rubka.body(size: 14, weight: FontWeight.w500))),
                Switch(
                  key: const Key('switch-compact'),
                  value: c.compact,
                  onChanged: c.setCompact,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final k in NotifyKind.values)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              decoration: BoxDecoration(
                  color: Rubka.bento, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Expanded(
                      child: Text(notifyKindLabel(k),
                          style: Rubka.body(size: 14, weight: FontWeight.w500))),
                  Switch(
                    value: c.state.notifyEnabled(k),
                    onChanged: (v) => c.setNotifyEnabled(k, v),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Rubka.body(size: 12, weight: FontWeight.w600, color: fg)),
      );

  Widget _toolRow(ToolItem t) {
    final Widget lead;
    if (t.run == InstallRun.running) {
      lead = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2));
    } else if (t.installed) {
      lead = const Icon(Icons.check_circle, color: Rubka.yes);
    } else {
      lead = Checkbox(
        value: t.selected,
        onChanged: _w.busy ? null : (v) => _w.toggle(t.spec.id, v ?? false),
      );
    }
    final Widget tag;
    if (t.installed) {
      tag = _tag('уже есть', Rubka.tagOkBg, Rubka.tagOkFg);
    } else if (t.run == InstallRun.failed) {
      tag = _tag('ошибка', Rubka.tagBadBg, Rubka.tagBadFg);
    } else if (t.run == InstallRun.running) {
      tag = _tag(
          t.status.isNotEmpty ? t.statusText : 'ставлю…',
          Rubka.tagWaitBg,
          Rubka.tagWaitFg);
    } else {
      tag = const SizedBox.shrink();
    }
    final sub = t.installed
        ? 'уже установлено'
        : (t.run == InstallRun.failed
            ? 'не получилось'
            : (t.run == InstallRun.running && t.status.isNotEmpty
                ? t.statusText
                : t.spec.hint));
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 10),
      decoration: BoxDecoration(
          color: Rubka.bento, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 44, height: 44, child: Center(child: lead)),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                          child: Text(t.spec.title,
                              overflow: TextOverflow.ellipsis,
                              style: Rubka.head(16, weight: FontWeight.w700))),
                      const SizedBox(width: 8),
                      Flexible(child: tag),
                    ],
                  ),
                  Text(sub,
                      style: Rubka.body(
                          size: 13,
                          color: t.run == InstallRun.failed
                              ? Rubka.error
                              : Rubka.ink2)),
                  if (t.run == InstallRun.running)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: t.percent == null ? null : t.percent! / 100,
                          minHeight: 4,
                          color: Rubka.send,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                  if (t.log.isNotEmpty && !t.installed)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12)),
                      child: SelectableText(t.log, style: Rubka.mono(size: 12)),
                    ),
                  if (t.run == InstallRun.failed && !t.installed)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
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

  // ---------- Шаг 2 ----------

  Widget _github() {
    final code = _w.ghCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _h('Вход в GitHub',
            'GitHub — сайт, где хранится студия. Нужно один раз войти '
                'в свой аккаунт.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
                onPressed: _w.busy ? null : _w.startGhLogin,
                child: Text(_w.ghError.isEmpty
                    ? 'Войти в GitHub'
                    : 'Попробовать снова')),
            if (_w.ghLoginRunning)
              OutlinedButton(
                  onPressed: _w.cancelGhLogin, child: const Text('Отмена')),
          ],
        ),
        if (code.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Rubka.tagWaitBg, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(code,
                    style: Rubka.mono(size: 40).copyWith(
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                    '1. Код уже скопирован.\n'
                    '2. На открывшейся странице GitHub войди в аккаунт и '
                    'вставь код (Ctrl+V).\n'
                    '3. Нажми Authorize. Программа сама увидит вход.',
                    style: Rubka.body(size: 14)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                        onPressed: _w.copyGhCode,
                        child: const Text('Скопировать код')),
                    OutlinedButton(
                        onPressed: _w.openGhDevicePage,
                        child: const Text('Открыть страницу GitHub')),
                  ],
                ),
              ],
            ),
          ),
        if (_w.ghLoginRunning && code.isEmpty)
          _statusLine(false, 'Жду код от GitHub…'),
        if (_w.ghDone) _statusLine(true, 'Готово: вход выполнен.'),
        if (_w.ghMessage.isNotEmpty) _statusLine(false, _w.ghMessage),
        if (_w.ghError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_w.ghError,
                style: Rubka.body(size: 14, color: Rubka.error)),
          ),
        const SizedBox(height: 12),
        Text(
            'Если GitHub при входе просит код из письма — он приходит на '
            'почту аккаунта GitHub; проверь «Спам»/«Промоакции».',
            style: Rubka.body(size: 12, color: Rubka.ink2)),
      ],
    );
  }

  // ---------- Шаг 3 ----------

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
        _h(title, text),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
                onPressed: _w.busy ? null : onStart, child: Text(startLabel)),
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
        _h('Папка студии',
            'Здесь на компьютере будут лежать файлы студии. Программа скачает их '
                'сама, если их ещё нет.'),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Rubka.bento, borderRadius: BorderRadius.circular(14)),
          child: SelectableText(_w.folder, style: Rubka.mono()),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_w.folderState == FolderState.needsClone)
              FilledButton(
                  onPressed: _w.busy ? null : _w.downloadStudio,
                  child: const Text('Скачать студию')),
            OutlinedButton(
                onPressed: _w.busy ? null : _w.checkFolder,
                child: const Text('Проверить')),
          ],
        ),
        if (_w.folderDone) _statusLine(true, 'Готово: ${_w.folderMessage}'),
        if (!_w.folderDone && _w.folderMessage.isNotEmpty)
          _statusLine(false, _w.folderMessage),
        const SizedBox(height: 12),
        Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
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
        ),
      ],
    );
  }

  InputDecoration _dec(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Rubka.bento,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
      );
}
