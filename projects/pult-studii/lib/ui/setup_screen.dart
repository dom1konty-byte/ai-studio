import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../services/tools_check.dart';
import '../state/app_controller.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final TextEditingController _path;

  @override
  void initState() {
    super.initState();
    _path = TextEditingController(text: widget.controller.repoPath ?? '');
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Нужно поставить, чтобы Рубка работала',
                    style: Rubka.head(22)),
                const SizedBox(height: 16),
                for (final t in c.setupItems) _ToolRow(t),
                const SizedBox(height: 16),
                Text('Папка ai-studio (где лежат .claude и projects)',
                    style: Rubka.body(size: 13, color: Rubka.text2)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _path,
                        decoration: InputDecoration(
                          hintText: r'C:\Users\...\ai-studio',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onSubmitted: (v) => c.setRepoPath(v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: c.checking ? null : () => c.setRepoPath(_path.text),
                      child: const Text('Применить'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    FilledButton(
                      onPressed: c.checking ? null : c.recheck,
                      child: c.checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Проверить снова'),
                    ),
                    const SizedBox(width: 8),
                    if (c.setupOk)
                      OutlinedButton(
                          onPressed: c.closeSetup, child: const Text('Закрыть')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow(this.t);

  final ToolStatus t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(t.ok ? Icons.check_circle : Icons.cancel,
                  color: t.ok ? Rubka.success : Rubka.error),
              const SizedBox(width: 12),
              Text(t.title, style: Rubka.head(16)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(t.ok ? t.detail : 'не готово: ${t.detail}',
                    style: Rubka.body(size: 13, color: Rubka.text2)),
              ),
            ],
          ),
          if (!t.ok && t.installCommand != null)
            Container(
              margin: const EdgeInsets.only(left: 36, top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Rubka.codeBg, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(t.installCommand!,
                        style: Rubka.mono()),
                  ),
                  TextButton(
                    onPressed: () => Clipboard.setData(
                        ClipboardData(text: t.installCommand!)),
                    child: const Text('Копировать'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
