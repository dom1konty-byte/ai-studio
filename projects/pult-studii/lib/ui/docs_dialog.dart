// Окно «Документы»: docs/*.md проекта, только чтение.
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../services/project_docs.dart';
import '../state/app_controller.dart';
import '../state/chat_controller.dart';
import 'md_style.dart';

class DocsDialog extends StatefulWidget {
  const DocsDialog({super.key, required this.app, required this.chat});

  final AppController app;
  final ChatController chat;

  @override
  State<DocsDialog> createState() => _DocsDialogState();
}

class _DocsDialogState extends State<DocsDialog> {
  List<DocEntry>? _docs;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<DocEntry> docs;
    try {
      docs = await widget.app.loadDocs(widget.chat);
    } catch (_) {
      docs = [for (final s in projectDocSpecs) DocEntry(s, null)];
    }
    if (!mounted) return;
    final first = docs.indexWhere((d) => d.exists);
    setState(() {
      _docs = docs;
      _selected = first < 0 ? 0 : first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final docs = _docs;
    return Dialog(
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 640),
        child: docs == null ? _skeleton() : _content(docs),
      ),
    );
  }

  Widget _skeleton() => Row(
        children: [
          Container(
            width: 220,
            color: Rubka.bento,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: List.generate(
                6,
                (_) => Container(
                  height: 40,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                      color: Rubka.disabledBg,
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );

  Widget _content(List<DocEntry> docs) {
    final any = docs.any((d) => d.exists);
    final cur = docs[_selected];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 220,
          color: Rubka.bento,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < docs.length; i++) _item(docs, i),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(cur.spec.title,
                            overflow: TextOverflow.ellipsis,
                            style: Rubka.head(22, weight: FontWeight.w700))),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Закрыть (Esc)'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Rubka.line),
              Expanded(
                child: !any
                    ? Center(
                        child: Text('В проекте пока нет документов',
                            style: Rubka.body(color: Rubka.text2)))
                    : !cur.exists
                        ? Center(
                            child: Text('Этого документа ещё нет',
                                style: Rubka.body(color: Rubka.text2)))
                        : _markdown(cur.text!),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _markdown(String text) => SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: MarkdownBody(
                data: text,
                styleSheet: rubkaMdStyle,
                onTapLink: (t, href, title) => widget.app.openLink(href),
              ),
            ),
          ),
        ),
      );

  Widget _item(List<DocEntry> docs, int i) {
    final d = docs[i];
    final sel = i == _selected;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: sel ? Rubka.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: d.exists ? () => setState(() => _selected = i) : null,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            child: Text(d.spec.title,
                overflow: TextOverflow.ellipsis,
                style: Rubka.body(
                    size: 14,
                    color: sel
                        ? Colors.white
                        : (d.exists ? Rubka.text : Rubka.disabledFg))),
          ),
        ),
      ),
    );
  }
}
