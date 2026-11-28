import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pasteboard/pasteboard.dart';

import '../app/theme.dart';
import '../models/models.dart';
import '../models/safety.dart';
import '../services/attachments.dart';
import '../services/readme_parser.dart';
import '../state/app_controller.dart';
import '../state/chat_controller.dart';
import 'docs_dialog.dart';
import 'limit_banner.dart';
import 'md_style.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.app,
    required this.chat,
    required this.project,
    required this.inputFocus,
  });

  final AppController app;
  final ChatController chat;
  final Project project;
  final FocusNode inputFocus;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastLen = -1;
  bool _askingStop = false;
  bool _dragging = false;

  ChatController get chat => widget.chat;

  @override
  void initState() {
    super.initState();
    _input.text = widget.chat.draft;
  }

  @override
  void dispose() {
    widget.chat.draft = _input.text;
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit() {
    if (!chat.canSend || chat.limitBlocked) return;
    final t = _input.text.trim();
    if (chat.copying) return;
    if (t.isEmpty && !chat.hasReadyAttachments) return;
    _input.clear();
    chat.send(t, withAttachments: true);
  }

  Future<void> _pickFiles() async {
    try {
      final files = await openFiles();
      if (files.isNotEmpty) {
        unawaited(chat.addFiles([for (final f in files) f.path]));
      }
    } catch (_) {
      widget.app.toast('Не удалось открыть окно выбора файлов.');
    }
  }

  /// Ctrl+V: файлы или картинка из буфера (текст вставляется как обычно).
  Future<void> _pasteAttachments() async {
    try {
      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        unawaited(chat.addFiles(files));
        return;
      }
      final img = await Pasteboard.image;
      if (img != null && img.isNotEmpty) unawaited(chat.addImageBytes(img));
    } catch (_) {}
  }

  void _openDocs() {
    showDialog<void>(
        context: context,
        builder: (_) => DocsDialog(app: widget.app, chat: chat));
  }

  /// Лента у самого низа (≤50 px) — тогда держим её прокрученной вниз.
  bool _nearBottom() {
    if (!_scroll.hasClients) return true;
    final pos = _scroll.position;
    return pos.maxScrollExtent - pos.pixels <= 50;
  }

  /// Esc в чате: спросить и только потом остановить директора.
  Future<void> _escape() async {
    if (!chat.working || _askingStop) return;
    _askingStop = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Остановить директора?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Нет')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Остановить')),
        ],
      ),
    );
    _askingStop = false;
    if (ok == true) await chat.stop();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _confirmNewChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый чат?'),
        content: const Text(
            'Директор забудет этот разговор. Файлы и git не меняются.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Да, новый чат')),
        ],
      ),
    );
    if (ok == true) await chat.newChat();
  }

  /// «Продолжить на телефоне»: копируем стартовый текст; есть незапушенное —
  /// сначала предупреждаем.
  Future<void> _continuePhone() async {
    final w = await widget.app.continueOnPhone(chat);
    if (w == null || !mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Не всё отправлено на GitHub'),
        content: Text('В папке проекта: ${w.describe()}.\n'
            'С телефона этого не будет видно. '
            'Отправить директору «$commitAndPushText»?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'copy'),
              child: const Text('Скопировать всё равно')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'push'),
              child: const Text('Отправить директору')),
        ],
      ),
    );
    if (choice == 'push') {
      await chat.send(commitAndPushText);
    } else if (choice == 'copy') {
      await widget.app.continueOnPhone(chat, force: true);
    }
  }

  /// «Открыть для телефона»: терминал с Remote Control, чат блокируется.
  Future<void> _openRemote() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Открыть для телефона?'),
        content: const Text(
            'Чат в AI Studio будет заблокирован, пока открыт терминал. '
            'Откроется окно терминала с этим же разговором; его видно '
            'в приложении Claude на телефоне. Закончишь — закрой терминал '
            'и нажми «Я закрыл терминал — вернуться».'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Открыть терминал')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await chat.openRemoteControl();
    if (err != null) widget.app.toast(err);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final len = chat.messages.length;
        final lastText = len == 0 ? 0 : chat.messages.last.text.length;
        final sig = len * 100000 + lastText + (chat.working ? 1 : 0);
        if (sig != _lastLen) {
          _lastLen = sig;
          if (_nearBottom()) _scrollDown();
        }
        final showApproval = stageWaitsYes(widget.project.stage) &&
            !chat.approvalHidden &&
            !chat.working &&
            chat.canSend;
        final inputEnabled =
            !chat.preparing && chat.blockedReason == null && !chat.rcOpen;
        final page = Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape &&
                chat.working) {
              _escape();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
          children: [
            _header(),
            const Divider(height: 1, color: Rubka.border),
            Expanded(child: _body()),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LimitBanner(controller: widget.app),
                      if (showApproval) ...[
                        _ApprovalPanel(chat: chat),
                        const SizedBox(height: 8),
                      ],
                      _inputRow(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ));
        if (chat.attachStore == null) return page;
        return DropTarget(
          enable: inputEnabled,
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (d) {
            setState(() => _dragging = false);
            unawaited(chat.addFiles([for (final f in d.files) f.path]));
          },
          child: Stack(
            children: [
              page,
              if (_dragging)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Rubka.primary.withValues(alpha: 0.9),
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text('Отпусти, чтобы прикрепить',
                          style: Rubka.head(20, color: Colors.white)),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _header() {
    final rcWhy = chat.rcDisabledReason;
    final phoneReady = !chat.preparing && chat.blockedReason == null;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text('${widget.project.name} · ${widget.project.stage}',
                  overflow: TextOverflow.ellipsis, style: Rubka.head(16)),
            ),
            Flexible(
              flex: 3,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (!chat.office)
                    OutlinedButton.icon(
                      onPressed: _openDocs,
                      icon: const Icon(Icons.description, size: 18),
                      label: const Text('Документы'),
                    ),
                  OutlinedButton(
                    onPressed: chat.working ? null : _confirmNewChat,
                    child: const Text('Новый чат'),
                  ),
                  Tooltip(
                    message:
                        'Скопировать стартовый текст для новой сессии на телефоне',
                    child: OutlinedButton(
                      onPressed: phoneReady ? _continuePhone : null,
                      child: const Text('Продолжить на телефоне'),
                    ),
                  ),
                  Tooltip(
                    message: rcWhy ??
                        'Открыть этот разговор в терминале (Remote Control) — '
                            'его будет видно в приложении Claude',
                    child: OutlinedButton(
                      onPressed: rcWhy == null ? _openRemote : null,
                      child: const Text('Открыть для телефона'),
                    ),
                  ),
                  if (chat.working)
                    FilledButton(
                      style:
                          FilledButton.styleFrom(backgroundColor: Rubka.error),
                      onPressed: chat.stop,
                      child: const Text('Стоп'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rcBanner() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Rubka.summaryBg, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Чат закрыт: открыт терминал для телефона',
                style: Rubka.head(16, color: Rubka.onAmber)),
            const SizedBox(height: 8),
            Text(
                'Пока терминал открыт, писать директору можно только там или '
                'с телефона. Если в приложении Claude чата не видно — '
                'в терминале введи /remote-control',
                style: Rubka.body(size: 14, color: Rubka.onAmber)),
            const SizedBox(height: 4),
            Text('Если терминал закрыт — нажми «вернуться».',
                style: Rubka.body(size: 14, color: Rubka.onAmber)),
            const SizedBox(height: 8),
            FilledButton(
                onPressed: chat.returnFromRc,
                child: const Text('Я закрыл терминал — вернуться')),
          ],
        ),
      );

  Widget _body() {
    if (chat.preparing && chat.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final msgs = chat.messages;
    final hasSummary = chat.summary.isNotEmpty && !chat.summaryDismissed;
    final top = <Widget>[
      if (chat.preparing)
        _notice('Обновляю ветку проекта…', Rubka.panel, Rubka.text2),
      if (chat.blockedReason != null)
        _blocked(chat.blockedReason!),
      if (chat.rcOpen) _rcBanner(),
      if (chat.warning != null)
        _notice(chat.warning!, Rubka.summaryBg, Rubka.onAmber),
      if (hasSummary) _summaryCard(),
    ];
    if (msgs.isEmpty && !chat.preparing && chat.blockedReason == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ...top,
          const SizedBox(height: 48),
          Center(child: Text(widget.project.name, style: Rubka.head(22))),
          Center(
              child: Text(widget.project.stage,
                  style: Rubka.body(color: Rubka.text2))),
          const SizedBox(height: 16),
          Center(
              child: Text('Напиши, что сделать',
                  style: Rubka.body(color: Rubka.text2))),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                  onPressed: () => chat.send('Что сейчас по проекту?'),
                  child: const Text('Что сейчас по проекту?')),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: () => chat.send('Продолжай'),
                  child: const Text('Продолжай')),
            ],
          ),
        ],
      );
    }
    final total = top.length + msgs.length + (chat.working ? 1 : 0);
    return SelectionArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760 + 48),
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(24),
            itemCount: total,
            itemBuilder: (context, i) {
              if (i < top.length) return top[i];
              final j = i - top.length;
              if (j < msgs.length) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _message(msgs[j]),
                );
              }
              return const _WorkingIndicator();
            },
          ),
        ),
      ),
    );
  }

  Widget _notice(String text, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: Rubka.body(size: 14, color: fg)),
      );

  Widget _blocked(String text) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Rubka.errorBg,
            border: Border.all(color: Rubka.error),
            borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Чат закрыт', style: Rubka.head(16, color: Rubka.error)),
            const SizedBox(height: 8),
            SelectableText(text, style: Rubka.mono()),
            const SizedBox(height: 8),
            OutlinedButton(
                onPressed: chat.open, child: const Text('Проверить снова')),
          ],
        ),
      );

  Widget _summaryCard() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
            color: Rubka.summaryBg, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Пока ПК был выключен, с телефона сделано:',
                      style: Rubka.head(14, color: Rubka.onAmber)),
                  const SizedBox(height: 4),
                  for (final line in chat.summary)
                    Text(line, style: Rubka.mono(color: Rubka.onAmber)),
                ],
              ),
            ),
            IconButton(
                tooltip: 'Закрыть',
                onPressed: chat.dismissSummary,
                icon: const Icon(Icons.close)),
          ],
        ),
      );

  Widget _message(ChatMessage m) {
    switch (m.kind) {
      case MsgKind.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Rubka.primary,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (m.text.isNotEmpty)
                  Text(m.text, style: Rubka.body(color: Colors.white)),
                if (m.attachments.isNotEmpty) ...[
                  if (m.text.isNotEmpty) const SizedBox(height: 8),
                  _attachmentsView(m.attachments),
                ],
              ],
            ),
          ),
        );
      case MsgKind.director:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Rubka.surface,
              border: Border.fromBorderSide(BorderSide(color: Rubka.border)),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: MarkdownBody(
              data: m.text,
              styleSheet: _mdStyle,
              onTapLink: (text, href, title) => widget.app.openLink(href),
            ),
          ),
        );
      case MsgKind.action:
        return Text(m.text, style: Rubka.mono(color: Rubka.text2));
      case MsgKind.note:
        return Center(
            child: Text('— ${m.text} —',
                style: Rubka.body(size: 13, color: Rubka.text2)));
      case MsgKind.error:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Rubka.errorBg,
              border: Border.all(color: Rubka.error),
              borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ошибка', style: Rubka.head(16, color: Rubka.error)),
              const SizedBox(height: 8),
              SelectableText(m.text, style: Rubka.mono()),
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton(
                    onPressed: chat.canSend ? chat.retry : null,
                    child: const Text('Повторить')),
                const SizedBox(width: 8),
                TextButton(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: m.text)),
                    child: const Text('Копировать')),
              ]),
            ],
          ),
        );
      case MsgKind.denial:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Rubka.summaryBg,
              border: Border.all(color: Rubka.amber),
              borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Агенту не дали выполнить:',
                  style: Rubka.head(15, color: Rubka.onAmber)),
              const SizedBox(height: 4),
              for (final d in m.denials)
                SelectableText(d.display, style: Rubka.mono()),
              const SizedBox(height: 8),
              ..._denialActions(m),
            ],
          ),
        );
    }
  }

  List<Widget> _denialActions(ChatMessage m) {
    final decision = decideDenials(m.denials);
    if (!decision.canAllow) {
      return [
        Text(decision.refusal ?? notAllowedText,
            style: Rubka.body(size: 14, color: Rubka.error)),
      ];
    }
    final disabled = m.resolved || !chat.canSend;
    return [
      Text('Будет разрешено ровно это:',
          style: Rubka.body(size: 13, color: Rubka.text2)),
      for (final r in decision.rules) SelectableText(r, style: Rubka.mono()),
      const SizedBox(height: 8),
      if (m.resolved)
        Text('Разрешено', style: Rubka.body(size: 14, color: Rubka.success))
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed:
                  disabled ? null : () => chat.allowAndRetry(m, always: false),
              child: const Text('Разрешить один раз'),
            ),
            OutlinedButton(
              onPressed:
                  disabled ? null : () => chat.allowAndRetry(m, always: true),
              child: const Text('Разрешить всегда'),
            ),
          ],
        ),
    ];
  }

  static final _mdStyle = rubkaMdStyle;

  /// Вложения в ленте: картинки миниатюрами, остальное — строкой.
  Widget _attachmentsView(List<String> paths) => Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          for (final path in paths)
            InkWell(
              onTap: () => widget.app.openAttachment(path),
              child: isImagePath(path)
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(path),
                        width: 200,
                        height: 200,
                        fit: BoxFit.cover,
                        cacheWidth: 400,
                        errorBuilder: (context, error, stack) => _fileLine(path),
                      ),
                    )
                  : _fileLine(path),
            ),
        ],
      );

  Widget _fileLine(String path) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Flexible(
              child: Text(path.split(RegExp(r'[\\/]')).last,
                  overflow: TextOverflow.ellipsis,
                  style: Rubka.body(size: 14, color: Colors.white)),
            ),
          ],
        ),
      );

  Widget _chips() => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final a in chat.pending)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _chip(a),
              ),
          ],
        ),
      );

  Widget _chip(PendingAttachment a) {
    final err = a.state == PendingState.error;
    final f = a.file;
    final Widget avatar;
    if (a.state == PendingState.copying) {
      avatar = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2));
    } else if (err) {
      avatar = const Icon(Icons.error_outline, size: 20, color: Rubka.error);
    } else if (f != null && f.isImage) {
      avatar = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(File(f.path),
            width: 32,
            height: 32,
            fit: BoxFit.cover,
            cacheWidth: 64,
            errorBuilder: (context, error, stack) =>
                const Icon(Icons.insert_drive_file, size: 20)),
      );
    } else {
      avatar = const Icon(Icons.insert_drive_file, size: 20);
    }
    final label = err
        ? '${a.name}: ${a.error}'
        : f == null
            ? a.name
            : '${a.name} · ${formatSize(f.size)}';
    return InputChip(
      avatar: avatar,
      backgroundColor: err ? Rubka.errorBg : null,
      side: err ? const BorderSide(color: Rubka.error) : null,
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Text(label,
            overflow: TextOverflow.ellipsis,
            style: Rubka.body(size: 13, color: err ? Rubka.error : Rubka.text)),
      ),
      onDeleted: () => chat.removePending(a),
    );
  }

  Widget _inputRow() {
    final enabled =
        !chat.preparing && chat.blockedReason == null && !chat.rcOpen;
    final canAttach = chat.attachStore != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chat.pending.isNotEmpty) ...[
          _chips(),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (canAttach)
              IconButton(
                tooltip: 'Прикрепить файл (или перетащи, или Ctrl+V)',
                iconSize: 24,
                constraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: enabled ? _pickFiles : null,
                icon: const Icon(Icons.attach_file),
              ),
            Expanded(
              child: _inputField(enabled, canAttach),
            ),
            const SizedBox(width: 8),
            chat.working
                ? OutlinedButton(
                    onPressed: chat.stop, child: const Text('Стоп'))
                : FilledButton(
                    onPressed: chat.canSend &&
                            !chat.limitBlocked &&
                            !chat.copying
                        ? _submit
                        : null,
                    child: const Text('Отправить')),
          ],
        ),
      ],
    );
  }

  Widget _inputField(bool enabled, bool canAttach) {
    return Focus(
            onKeyEvent: (node, event) {
              if (canAttach &&
                  event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.keyV &&
                  HardwareKeyboard.instance.isControlPressed) {
                unawaited(_pasteAttachments());
                return KeyEventResult.ignored; // текст вставится как обычно
              }
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
                  !HardwareKeyboard.instance.isShiftPressed) {
                _submit();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _input,
              focusNode: widget.inputFocus,
              enabled: enabled,
              minLines: 1,
              maxLines: 6,
              style: Rubka.body(),
              decoration: InputDecoration(
                hintText: 'Напиши директору…',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
    );
  }
}

class _ApprovalPanel extends StatefulWidget {
  const _ApprovalPanel({required this.chat});

  final ChatController chat;

  @override
  State<_ApprovalPanel> createState() => _ApprovalPanelState();
}

class _ApprovalPanelState extends State<_ApprovalPanel> {
  bool _editing = false;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Rubka.surface,
          border: Border.all(color: Rubka.border),
          borderRadius: BorderRadius.circular(12)),
      child: _editing ? _edit() : _buttons(),
    );
  }

  Widget _buttons() => Row(
        children: [
          Text('Директор ждёт ответа:', style: Rubka.body(size: 14)),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Rubka.success),
            onPressed: widget.chat.sendYes,
            child: const Text('Да'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => setState(() => _editing = true),
            child: const Text('Поправить'),
          ),
        ],
      );

  Widget _edit() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                setState(() => _editing = false);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _text,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'Что поправить?',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () => widget.chat.sendFix(_text.text),
                child: const Text('Отправить поправку'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _editing = false),
                child: const Text('Отмена'),
              ),
            ],
          ),
        ],
      );
}

class _WorkingIndicator extends StatefulWidget {
  const _WorkingIndicator();

  @override
  State<_WorkingIndicator> createState() => _WorkingIndicatorState();
}

class _WorkingIndicatorState extends State<_WorkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FadeTransition(
          opacity: Tween<double>(begin: 0.3, end: 1).animate(_ctrl),
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
                color: Rubka.amber, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 8),
        Text('Директор работает…',
            style: Rubka.body(size: 14, color: Rubka.working)),
      ],
    );
  }
}
