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
import '../models/quick_replies.dart';
import '../services/attachments.dart';
import '../services/rate_limit.dart';
import '../services/readme_parser.dart';
import '../state/app_controller.dart';
import '../state/chat_controller.dart';
import 'docs_dialog.dart';
import 'limit_banner.dart';
import 'md_style.dart';
import 'night_dialog.dart';
import 'phone_share_dialog.dart';

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
        final showApproval = stageWaitsYes(widget.project.stage) &&
            !chat.approvalHidden &&
            !chat.working &&
            chat.canSend;
        final sig = len * 100000 +
            lastText +
            (chat.working ? 1 : 0) +
            (showApproval ? 2 : 0);
        if (sig != _lastLen) {
          _lastLen = sig;
          if (_nearBottom()) _scrollDown();
        }
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
              LimitBanner(controller: widget.app),
              _header(),
              Expanded(child: _body(showApproval)),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 728),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    child: _inputRow(),
                  ),
                ),
              ),
            ],
          ),
        );
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
    final p = widget.project;
    final waits = stageWaitsYes(p.stage);
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(p.name,
                        key: const Key('chat-title'),
                        overflow: TextOverflow.ellipsis,
                        style: Rubka.head(18, weight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Container(
                      key: const Key('stage-pill'),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          color: waits ? Rubka.tagWaitBg : Rubka.tagIdleBg,
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(p.stage,
                          overflow: TextOverflow.ellipsis,
                          style: Rubka.body(
                              size: 13,
                              color: waits ? Rubka.tagWaitFg : Rubka.tagIdleFg)),
                    ),
                  ),
                ],
              ),
            ),
            _menu(),
          ],
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _builtAt(DateTime? t, DateTime now) {
    if (t == null) return 'сборка готова';
    final l = t.toLocal();
    final same = l.year == now.year && l.month == now.month && l.day == now.day;
    return same
        ? 'готова сегодня в ${hhmm(l)}'
        : 'готова ${_two(l.day)}.${_two(l.month)} в ${hhmm(l)}';
  }

  static String _money(double v) => '\$${v.toStringAsFixed(v < 10 ? 2 : 1)}';

  PopupMenuItem<String> _item(
      String value, IconData icon, String title, String sub, String tip,
      {bool enabled = true}) {
    return PopupMenuItem<String>(
      key: Key('mi-$value'),
      value: value,
      enabled: enabled,
      height: 56,
      child: Tooltip(
        message: tip,
        child: Row(
          children: [
            Icon(icon,
                size: 20, color: enabled ? Rubka.text2 : Rubka.disabledFg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      overflow: TextOverflow.ellipsis,
                      style: Rubka.body(
                          size: 14,
                          color: enabled ? Rubka.text : Rubka.disabledFg)),
                  Text(sub,
                      overflow: TextOverflow.ellipsis,
                      style: Rubka.body(size: 12, color: Rubka.mute)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu() {
    final p = widget.project;
    final app = widget.app;
    final now = DateTime.now();
    final build = app.builds[p.slug] ?? BuildRun.loading;
    final hasBuild = build.state == BuildState.success && build.id != null;
    final expired = hasBuild && build.isExpired(now);
    final busy = app.downloading.contains(p.slug);
    final String? dlWhy;
    if (!hasBuild) {
      dlWhy = build.state == BuildState.running
          ? 'сборка ещё идёт'
          : build.state == BuildState.failed
              ? 'последняя сборка упала'
              : 'сборки пока нет';
    } else if (expired) {
      dlWhy = 'артефакт старше 30 дней';
    } else if (busy) {
      dlWhy = 'скачиваю…';
    } else {
      dlWhy = null;
    }
    final phoneReady = !chat.preparing && chat.blockedReason == null;
    final rcWhy = chat.rcDisabledReason;
    final today = app.usageSummary.total.today.cost;
    final office = chat.office;
    return PopupMenuButton<String>(
      key: const Key('chat-menu'),
      tooltip: 'Меню: документы, сборка, телефон, расходы',
      offset: const Offset(0, 44),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 340),
      onSelected: _onMenu,
      itemBuilder: (_) => [
        if (!office)
          _item('docs', Icons.description, 'Документы',
              'ТЗ, дизайн, отчёт проекта', 'Открыть документы проекта'),
        if (!office)
          _item(
              'download',
              Icons.download,
              'Скачать сборку',
              dlWhy ?? _builtAt(build.updatedAt, now),
              dlWhy == null
                  ? 'Скачать последнюю сборку в папку «Загрузки»'
                  : 'Недоступно: $dlWhy',
              enabled: dlWhy == null),
        if (!office && isSiteType(p.type))
          _item(
              'site',
              Icons.public,
              'Открыть сайт',
              'адрес из README или просмотр с компьютера',
              'Открыть опубликованный сайт или посмотреть его локально'),
        if (!office && isAppType(p.type))
          _item(
              'qr',
              Icons.qr_code_2,
              'На телефон',
              expired
                  ? 'артефакт старше 30 дней'
                  : hasBuild
                      ? 'QR-код: поставить APK по Wi-Fi'
                      : 'нужна успешная сборка',
              'Показать QR-код, чтобы поставить APK на телефон по Wi-Fi',
              enabled: hasBuild && !expired),
        _item(
            'continue',
            Icons.phone_android,
            'Продолжить на телефоне',
            phoneReady ? 'скопирует текст для Claude' : 'чат ещё не готов',
            'Скопировать стартовый текст для новой сессии на телефоне',
            enabled: phoneReady),
        _item(
            'remote',
            Icons.cast_connected,
            'Открыть для телефона',
            rcWhy ?? 'терминал с Remote Control',
            rcWhy ??
                'Открыть этот разговор в терминале (Remote Control) — '
                    'его будет видно в приложении Claude',
            enabled: rcWhy == null),
        _item(
            'night',
            Icons.alarm,
            'Запланированные (${widget.app.night.waitingFor(chat.slug).length})',
            'сообщения директору по расписанию',
            'Список задач на ночь: отменить или выполнить сейчас'),
        _item('usage', Icons.payments, 'Расходы', 'сегодня ${_money(today)}',
            'Открыть панель расходов'),
        _item(
            'newchat',
            Icons.cleaning_services,
            'Новый чат',
            chat.working
                ? 'директор ещё работает'
                : 'директор начнёт с чистого листа',
            chat.working
                ? 'Недоступно: директор ещё работает'
                : 'Директор забудет разговор; файлы и git не меняются',
            enabled: !chat.working),
      ],
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: Rubka.field, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.more_horiz, color: Rubka.text2),
      ),
    );
  }

  void _onMenu(String v) {
    switch (v) {
      case 'docs':
        _openDocs();
      case 'download':
        unawaited(widget.app.download(widget.project));
      case 'site':
        unawaited(widget.app.openSite(chat));
      case 'qr':
        _phoneShare();
      case 'continue':
        unawaited(_continuePhone());
      case 'remote':
        unawaited(_openRemote());
      case 'night':
        showDialog<void>(
            context: context,
            builder: (_) => NightListDialog(
                night: widget.app.night, chatKey: chat.slug));
      case 'usage':
        widget.app.toggleUsage();
      case 'newchat':
        unawaited(_confirmNewChat());
    }
  }

  void _phoneShare() {
    final share = widget.app.startPhoneShare(widget.project);
    if (share == null) return;
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PhoneShareDialog(share: share));
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

  /// Вопрос в карточке решения: последняя строка директора или этап.
  String _question() {
    final msgs = chat.messages;
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].kind != MsgKind.director) continue;
      final lines = msgs[i]
          .text
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'[*_`#>]'), '').trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        final t = lines.last;
        return t.length > 300 ? '${t.substring(0, 300)}…' : t;
      }
    }
    return widget.project.stage;
  }

  Widget _body(bool showApproval) {
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
      if (hasSummary)
        _SummaryLine(
            key: const Key('summary-line'),
            lines: chat.summary,
            onDismiss: chat.dismissSummary),
    ];
    final approval = showApproval
        ? _ApprovalCard(
            key: const Key('approval-card'),
            chat: chat,
            question: _question())
        : null;
    if (msgs.isEmpty && !chat.preparing && chat.blockedReason == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ...top,
          // решение — сверху, чтобы было видно и в маленьком окне
          if (approval != null) ...[
            Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: approval)),
            const SizedBox(height: 16),
          ],
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
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                  onPressed: () => chat.send('Что сейчас по проекту?'),
                  child: const Text('Что сейчас по проекту?')),
              OutlinedButton(
                  onPressed: () => chat.send('Продолжай'),
                  child: const Text('Продолжай')),
            ],
          ),
        ],
      );
    }
    // Подряд идущие действия агента сворачиваем в одну строку.
    final items = <Widget>[...top];
    var i = 0;
    while (i < msgs.length) {
      if (msgs[i].kind == MsgKind.action) {
        final start = i;
        final group = <ChatMessage>[];
        while (i < msgs.length && msgs[i].kind == MsgKind.action) {
          group.add(msgs[i]);
          i++;
        }
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _ActionsGroup(
              key: ValueKey('actions-$start'),
              actions: [for (final m in group) m.text]),
        ));
      } else {
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _message(msgs[i]),
        ));
        i++;
      }
    }
    if (chat.working) items.add(const _WorkingIndicator());
    if (approval != null) items.add(approval);
    return SelectionArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680 + 32),
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: items.length,
            itemBuilder: (context, idx) => items[idx],
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

  Widget _message(ChatMessage m) {
    switch (m.kind) {
      case MsgKind.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: const BoxDecoration(
              color: Rubka.ink,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
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
                if (m.scheduled != null) ...[
                  const SizedBox(height: 4),
                  Text('⏰ отправлено по расписанию ${m.scheduled}',
                      style: Rubka.body(size: 12, color: Rubka.mute)),
                ],
              ],
            ),
          ),
        );
      case MsgKind.director:
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: const BoxDecoration(
                color: Rubka.bubble,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Директор',
                      style: Rubka.body(size: 12, color: Rubka.mute)),
                  const SizedBox(height: 2),
                  MarkdownBody(
                    data: m.text,
                    styleSheet: _mdStyle,
                    onTapLink: (text, href, title) =>
                        widget.app.openLink(href),
                  ),
                ],
              ),
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
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton(
                    onPressed: chat.canSend ? chat.retry : null,
                    child: const Text('Повторить')),
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

  Future<void> _night() async {
    final req = await showNightDialog(context,
        initialText: _input.text, clock: widget.app.clockNow);
    if (req == null || !mounted) return;
    widget.app.night.add(
        key: chat.slug,
        text: req.text,
        when: req.when,
        keepAwake: req.keepAwake);
    _input.clear();
    widget.app.toast('Запланировано на ${hhmm(req.when)}');
  }

  void _voice() {
    widget.inputFocus.requestFocus();
    unawaited(widget.app.startVoice());
  }

  /// Быстрые кнопки: текст уходит директору сразу.
  Widget _quickReplies(bool active) {
    final items = quickRepliesFor(office: chat.office);
    return SingleChildScrollView(
      key: const Key('quick-replies'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final t in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: Rubka.bubble,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  key: Key('quick-$t'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: active ? () => unawaited(chat.send(t)) : null,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(t,
                        maxLines: 1,
                        style: Rubka.body(
                            size: 12,
                            color: active ? Rubka.ink2 : Rubka.disabledFg)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _inputRow() {
    final enabled =
        !chat.preparing && chat.blockedReason == null && !chat.rcOpen;
    final canAttach = chat.attachStore != null;
    final canSend = chat.canSend && !chat.limitBlocked && !chat.copying;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!chat.working) ...[
          _quickReplies(enabled && canSend),
          const SizedBox(height: 8),
        ],
        if (chat.pending.isNotEmpty) ...[
          _chips(),
          const SizedBox(height: 8),
        ],
        Container(
          key: const Key('input-box'),
          padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
          decoration: BoxDecoration(
              color: Rubka.bubble, borderRadius: BorderRadius.circular(16)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (canAttach)
                IconButton(
                  key: const Key('attach-button'),
                  tooltip: 'Прикрепить файл (или перетащи, или Ctrl+V)',
                  iconSize: 22,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  onPressed: enabled ? _pickFiles : null,
                  icon: const Icon(Icons.attach_file),
                )
              else
                const SizedBox(width: 10),
              IconButton(
                key: const Key('voice-button'),
                tooltip: 'Голосовой ввод Windows — говори, текст появится в поле',
                iconSize: 22,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: enabled ? _voice : null,
                icon: const Icon(Icons.mic),
              ),
              IconButton(
                key: const Key('night-button'),
                tooltip: 'Отправить позже',
                iconSize: 22,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: enabled ? _night : null,
                icon: const Icon(Icons.alarm),
              ),
              Expanded(child: _inputField(enabled, canAttach)),
              const SizedBox(width: 8),
              if (chat.working)
                IconButton.filled(
                  key: const Key('stop-button'),
                  tooltip: 'Стоп (Esc): остановить директора',
                  style: IconButton.styleFrom(
                    backgroundColor: Rubka.error,
                    foregroundColor: Colors.white,
                    fixedSize: const Size(36, 36),
                    minimumSize: const Size(36, 36),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: chat.stop,
                  icon: const Icon(Icons.stop, size: 20),
                )
              else
                IconButton.filled(
                  key: const Key('send-button'),
                  tooltip: 'Отправить (Enter)',
                  style: IconButton.styleFrom(
                    backgroundColor: Rubka.send,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Rubka.disabledBg,
                    disabledForegroundColor: Rubka.disabledFg,
                    fixedSize: const Size(36, 36),
                    minimumSize: const Size(36, 36),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: canSend ? _submit : null,
                  icon: const Icon(Icons.arrow_upward, size: 20),
                ),
            ],
          ),
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
              decoration: const InputDecoration(
                hintText: 'Напиши директору…',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
    );
  }
}

class _ApprovalCard extends StatefulWidget {
  const _ApprovalCard({super.key, required this.chat, required this.question});

  final ChatController chat;
  final String question;

  @override
  State<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<_ApprovalCard> {
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
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
          color: Rubka.askBg,
          border: Border.all(color: Rubka.amber, width: 1.5),
          borderRadius: BorderRadius.circular(16)),
      child: _editing ? _edit() : _buttons(),
    );
  }

  Widget _buttons() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Нужно твоё решение',
              style: Rubka.head(13, color: Rubka.working)),
          const SizedBox(height: 4),
          Text(widget.question, style: Rubka.body()),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const Key('approve-yes'),
                style: FilledButton.styleFrom(
                    backgroundColor: Rubka.yes,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: widget.chat.sendYes,
                child: const Text('Да'),
              ),
              OutlinedButton(
                key: const Key('approve-fix'),
                style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () => setState(() => _editing = true),
                child: const Text('Поправить'),
              ),
            ],
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
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton(
                onPressed: () => widget.chat.sendFix(_text.text),
                child: const Text('Отправить поправку'),
              ),
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
        Flexible(
          child: Text('Директор работает…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Rubka.body(size: 14, color: Rubka.working)),
        ),
      ],
    );
  }
}

String _plural(int n, String one, String few, String many) {
  final m100 = n % 100;
  final m10 = n % 10;
  if (m100 >= 11 && m100 <= 14) return many;
  if (m10 == 1) return one;
  if (m10 >= 2 && m10 <= 4) return few;
  return many;
}

/// «С телефона сделано N изменений · показать» (раскрывается).
class _SummaryLine extends StatefulWidget {
  const _SummaryLine({super.key, required this.lines, required this.onDismiss});

  final List<String> lines;
  final VoidCallback onDismiss;

  @override
  State<_SummaryLine> createState() => _SummaryLineState();
}

class _SummaryLineState extends State<_SummaryLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.lines.length;
    final small = Rubka.body(size: 13, color: Rubka.mute);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Tooltip(
            message: 'Коммиты, сделанные с телефона, пока ПК был выключен',
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text.rich(
                  TextSpan(
                    style: small,
                    children: [
                      TextSpan(
                          text: 'С телефона сделано $n '
                              '${_plural(n, 'изменение', 'изменения', 'изменений')}'
                              ' · '),
                      TextSpan(
                          text: _open ? 'скрыть' : 'показать',
                          style: const TextStyle(
                              decoration: TextDecoration.underline)),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          if (_open) ...[
            for (final line in widget.lines)
              Text(line, style: Rubka.mono(size: 12, color: Rubka.text2)),
            TextButton(
                onPressed: widget.onDismiss, child: const Text('Закрыть')),
          ],
        ],
      ),
    );
  }
}

/// «⚙ N действий» — действия агента одной свёрнутой строкой.
class _ActionsGroup extends StatefulWidget {
  const _ActionsGroup({super.key, required this.actions});

  final List<String> actions;

  @override
  State<_ActionsGroup> createState() => _ActionsGroupState();
}

class _ActionsGroupState extends State<_ActionsGroup> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.actions.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: 'Что делал агент: файлы и команды. Нажми, чтобы раскрыть',
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings, size: 14, color: Rubka.mute),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                        '$n ${_plural(n, 'действие', 'действия', 'действий')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Rubka.body(size: 13, color: Rubka.mute)),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open)
          for (final a in widget.actions)
            Text(a, style: Rubka.mono(size: 12, color: Rubka.text2)),
      ],
    );
  }
}
