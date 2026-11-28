import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../models/models.dart';
import '../services/notifications.dart';
import '../services/rate_limit.dart';
import '../services/readme_parser.dart';
import '../state/app_controller.dart';
import 'board_panel.dart';
import 'chat_panel.dart';
import 'studio_rail.dart';
import 'update_banner.dart';
import 'usage_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _Tab _tab = _Tab.overview;
  final _inputFocus = FocusNode();
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.toasts.listen((m) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _inputFocus.dispose();
    super.dispose();
  }

  void _go(_Tab t) {
    setState(() => _tab = t);
    if (t == _Tab.office) widget.controller.openOffice();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): c.refreshBoard,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (c.usageOpen) c.toggleUsage(false);
        },
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _inputFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            _go(_Tab.overview),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            _go(_Tab.chats),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            _go(_Tab.office),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Rubka.bento,
          body: ListenableBuilder(
            listenable: c,
            builder: (context, _) {
              return Column(
                children: [
                  UpdateBanner(controller: c),
                  Expanded(
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            StudioRail(
                                active: _tab.name,
                                onOverview: () => _go(_Tab.overview),
                                onChats: () => _go(_Tab.chats),
                                onOffice: () => _go(_Tab.office),
                                onSetup: c.openSetup),
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(14, 10, 14, 14),
                                child: switch (_tab) {
                                  _Tab.overview => _Overview(
                                      controller: c, inputFocus: _inputFocus),
                                  _Tab.chats => _Chats(
                                      controller: c, inputFocus: _inputFocus),
                                  _Tab.office => _ChatTile(
                                      controller: c,
                                      inputFocus: _inputFocus,
                                      office: true),
                                },
                              ),
                            ),
                          ],
                        ),
                        if (c.usageOpen)
                          Positioned(
                            top: 0,
                            right: 0,
                            bottom: 0,
                            child: UsagePanel(controller: c),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _Tab { overview, chats, office }

/// Плитка чата выбранного проекта (или офиса).
class _ChatTile extends StatelessWidget {
  const _ChatTile(
      {required this.controller,
      required this.inputFocus,
      this.office = false});

  final AppController controller;
  final FocusNode inputFocus;
  final bool office;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final chat = c.chat;
    final project = c.selected;
    final show = chat != null &&
        project != null &&
        (c.activeKey == officeKey) == office;
    return BentoTile(
      padding: EdgeInsets.zero,
      child: show
          ? ChatPanel(
              key: ValueKey(chat.slug),
              app: c,
              chat: chat,
              project: project,
              inputFocus: inputFocus,
            )
          : Center(
              child: Text(office ? 'Открываю офис…' : 'Выбери проект',
                  style: Rubka.body(color: Rubka.ink2))),
    );
  }
}

class _Chats extends StatelessWidget {
  const _Chats({required this.controller, required this.inputFocus});

  final AppController controller;
  final FocusNode inputFocus;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
              width: 270,
              child: BoardPanel(controller: controller, compact: true)),
          const SizedBox(width: 12),
          Expanded(
              child: _ChatTile(controller: controller, inputFocus: inputFocus)),
        ],
      );
}

String _plural(int n, String one, String few, String many) {
  final m100 = n % 100;
  final m10 = n % 10;
  if (m100 >= 11 && m100 <= 14) return many;
  if (m10 == 1) return one;
  if (m10 >= 2 && m10 <= 4) return few;
  return many;
}

String _money(double v) => '\$${v.toStringAsFixed(v < 10 ? 2 : 1)}';

class _Overview extends StatelessWidget {
  const _Overview({required this.controller, required this.inputFocus});

  final AppController controller;
  final FocusNode inputFocus;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final chatW = (box.maxWidth * 0.36).clamp(320.0, 520.0);
      final narrow = box.maxWidth < 1000;
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopLine(controller: controller),
                const SizedBox(height: 10),
                SizedBox(
                    height: narrow ? 124 : 132,
                    child: _Tiles(controller: controller, narrow: narrow)),
                const SizedBox(height: 12),
                Expanded(child: BoardPanel(controller: controller)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
              width: chatW,
              child: _ChatTile(controller: controller, inputFocus: inputFocus)),
        ],
      );
    });
  }
}

/// «Привет, Дамир», «С телефона: N изменений», 🔔.
class _TopLine extends StatelessWidget {
  const _TopLine({required this.controller});

  final AppController controller;

  List<(String, String)> _notes() {
    final c = controller;
    final out = <(String, String)>[];
    for (final p in c.projects) {
      if (stageWaitsYes(p.stage)) {
        out.add((p.slug, '${p.name} ждёт «да» — ${stageName(p.stage)}'));
      }
      if ((c.builds[p.slug]?.state) == BuildState.failed) {
        out.add((p.slug, '${p.name}: сборка упала'));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final byProject = <Project>[
      for (final p in c.projects)
        if ((c.newCounts[p.slug] ?? 0) > 0) p,
    ];
    final office = c.newCounts[officeKey] ?? 0;
    final total = c.newCounts.values.fold<int>(0, (a, b) => a + b);
    final notes = _notes();
    void open(String key) {
      if (key == officeKey) {
        c.openOffice();
        return;
      }
      for (final p in c.projects) {
        if (p.slug == key) {
          final msg = c.select(p);
          if (msg != null) c.toast(msg);
        }
      }
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Привет, Дамир 👋',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Rubka.head(22, weight: FontWeight.w700)),
              PopupMenuButton<String>(
                key: const Key('phone-changes'),
                tooltip: 'Что пришло с телефона',
                padding: EdgeInsets.zero,
                color: Colors.white,
                surfaceTintColor: Colors.transparent,
                onSelected: open,
                itemBuilder: (_) => [
                  if (total == 0)
                    const PopupMenuItem<String>(
                        enabled: false, child: Text('С телефона пока ничего')),
                  for (final p in byProject)
                    PopupMenuItem<String>(
                        value: p.slug,
                        child: Text(
                            '${p.name}: ${c.newCounts[p.slug]} '
                            '${_plural(c.newCounts[p.slug] ?? 0, 'изменение', 'изменения', 'изменений')}')),
                  if (office > 0)
                    PopupMenuItem<String>(
                        value: officeKey,
                        child: Text('Офис: $office '
                            '${_plural(office, 'изменение', 'изменения', 'изменений')}')),
                ],
                child: Text(
                    total == 0
                        ? 'С телефона: без изменений'
                        : 'С телефона: $total ${_plural(total, 'изменение', 'изменения', 'изменений')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Rubka.body(size: 13, color: Rubka.ink2)),
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          key: const Key('bell'),
          tooltip: 'Уведомления',
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          onSelected: open,
          itemBuilder: (_) => [
            if (notes.isEmpty)
              const PopupMenuItem<String>(
                  enabled: false, child: Text('Новых уведомлений нет')),
            for (final n in notes)
              PopupMenuItem<String>(value: n.$1, child: Text(n.$2)),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Text(notes.isEmpty ? '🔔' : '🔔 ${notes.length}',
                style: Rubka.body(size: 13, color: const Color(0xFF555555))),
          ),
        ),
      ],
    );
  }
}

/// Три верхние плитки; при нехватке места числа сжимаются.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.controller, required this.narrow});

  final AppController controller;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final now = DateTime.now();
    final waiting = [
      for (final p in c.projects)
        if (stageWaitsYes(p.stage)) p,
    ];
    var today = 0;
    var ok = 0;
    String? failed;
    for (final p in c.projects) {
      final b = c.builds[p.slug];
      final t = b?.updatedAt?.toLocal();
      if (b == null || t == null) continue;
      if (t.year != now.year || t.month != now.month || t.day != now.day) {
        continue;
      }
      if (b.state == BuildState.success) {
        today++;
        ok++;
      } else if (b.state == BuildState.failed) {
        today++;
        failed ??= p.name;
      } else if (b.state == BuildState.running) {
        today++;
      }
    }
    final spent = c.usageSummary.total.today.cost;
    final until = c.activeLimit;
    final pad = narrow
        ? const EdgeInsets.fromLTRB(12, 12, 12, 10)
        : const EdgeInsets.fromLTRB(18, 16, 18, 14);
    Widget big(String t, Key key, Color color) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(t,
              key: key,
              style: Rubka.head(34, weight: FontWeight.w700, color: color)
                  .copyWith(height: 1.15)),
        );
    Widget small(String t, Color color) => Text(t,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Rubka.body(size: 12, color: color));
    return Row(
      children: [
        Expanded(
          child: InkWell(
            key: const Key('tile-waits'),
            borderRadius: BorderRadius.circular(22),
            onTap: waiting.isEmpty
                ? null
                : () {
                    final msg = c.select(waiting.first);
                    if (msg != null) c.toast(msg);
                  },
            child: BentoTile(
              padding: pad,
              gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Rubka.orange1, Rubka.orange2]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  small('Ждут твоего «да»', Colors.white),
                  big('${waiting.length}', const Key('waits-count'),
                      Colors.white),
                  small(
                      waiting.isEmpty
                          ? 'ничего не ждёт'
                          : '${waiting.first.name} · ${stageName(waiting.first.stage)}',
                      Colors.white),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: BentoTile(
            padding: pad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                small('Сборки сегодня', Rubka.ink2),
                big('$ok / $today', const Key('builds-count'), Rubka.text),
                small(failed == null ? 'без падений' : '1 упала — «$failed»',
                    Rubka.ink2),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            key: const Key('btn-usage'),
            borderRadius: BorderRadius.circular(22),
            onTap: c.toggleUsage,
            child: BentoTile(
              padding: pad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  small('Потрачено сегодня', Rubka.ink2),
                  big(_money(spent), const Key('spent-count'), Rubka.text),
                  small(
                      until == null
                          ? 'лимит в норме'
                          : 'лимит до ${hhmm(until)}',
                      Rubka.ink2),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
