import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../models/models.dart';
import '../services/readme_parser.dart';
import '../state/app_controller.dart';
import '../state/chat_controller.dart';

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

  ChatController get chat => widget.chat;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit() {
    if (!chat.canSend) return;
    final t = _input.text.trim();
    if (t.isEmpty) return;
    _input.clear();
    chat.send(t);
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
          _scrollDown();
        }
        final showApproval = stageWaitsYes(widget.project.stage) &&
            !chat.approvalHidden &&
            !chat.working &&
            chat.canSend;
        return Column(
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
        );
      },
    );
  }

  Widget _header() {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Expanded(
              child: Text('${widget.project.name} · ${widget.project.stage}',
                  overflow: TextOverflow.ellipsis, style: Rubka.head(16)),
            ),
            OutlinedButton(
              onPressed: chat.working ? null : _confirmNewChat,
              child: const Text('Новый чат'),
            ),
            if (chat.working) ...[
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Rubka.error),
                onPressed: chat.stop,
                child: const Text('Стоп'),
              ),
            ],
          ],
        ),
      ),
    );
  }

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
            child: Text(m.text, style: Rubka.body(color: Colors.white)),
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
              FilledButton(
                onPressed:
                    m.resolved || !chat.canSend ? null : () => chat.allowAndRetry(m),
                child: Text(m.resolved ? 'Разрешено' : 'Разрешить и повторить'),
              ),
            ],
          ),
        );
    }
  }

  static final _mdStyle = MarkdownStyleSheet(
    p: Rubka.body(),
    h1: Rubka.head(22),
    h2: Rubka.head(19),
    h3: Rubka.head(16),
    code: Rubka.mono().copyWith(backgroundColor: Rubka.codeBg),
    codeblockDecoration: BoxDecoration(
        color: Rubka.codeBg, borderRadius: BorderRadius.circular(8)),
    codeblockPadding: const EdgeInsets.all(12),
    a: Rubka.body(color: Rubka.primary)
        .copyWith(decoration: TextDecoration.underline),
    listBullet: Rubka.body(),
  );

  Widget _inputRow() {
    final enabled = !chat.preparing && chat.blockedReason == null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Focus(
            onKeyEvent: (node, event) {
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
          ),
        ),
        const SizedBox(width: 8),
        chat.working
            ? OutlinedButton(onPressed: chat.stop, child: const Text('Стоп'))
            : FilledButton(
                onPressed: chat.canSend ? _submit : null,
                child: const Text('Отправить')),
      ],
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
