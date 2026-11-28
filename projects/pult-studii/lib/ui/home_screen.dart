import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../state/app_controller.dart';
import 'board_panel.dart';
import 'chat_panel.dart';
import 'update_banner.dart';
import 'usage_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: ListenableBuilder(
            listenable: c,
            builder: (context, _) {
              final chat = c.chat;
              final project = c.selected;
              return Column(
                children: [
                  UpdateBanner(controller: c),
                  Expanded(
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            SizedBox(
                                width: 240, child: BoardPanel(controller: c)),
                            const VerticalDivider(
                                width: 1, color: Rubka.line),
                            Expanded(
                              child: chat == null || project == null
                                  ? Center(
                                      child: Text('Выбери проект слева',
                                          style: Rubka.body(
                                              color: Rubka.text2)))
                                  : ChatPanel(
                                      key: ValueKey(chat.slug),
                                      app: c,
                                      chat: chat,
                                      project: project,
                                      inputFocus: _inputFocus,
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
