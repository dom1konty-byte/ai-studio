import 'package:material_ui/material_ui.dart';

import '../core/startup.dart';
import '../state/app_controller.dart';

/// Экран «Автозагрузка»: что запускается с Windows, с выключателем.
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (c.startupState == LoadState.idle) c.loadStartup();
    });
  }

  Future<void> _toggle(StartupItem it, bool on) async {
    final ok = await c.toggleStartup(it, on);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось изменить. Попробуйте ещё раз.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final Widget body;
        if (c.startupState == LoadState.loading || c.startupState == LoadState.idle) {
          body = const Center(child: CircularProgressIndicator());
        } else if (c.startupState == LoadState.error) {
          body = Center(
            child: FilledButton(onPressed: c.loadStartup, child: const Text('Повторить')),
          );
        } else if (c.startupItems.isEmpty) {
          body = const Center(child: Text('Ничего не запускается с Windows'));
        } else {
          body = ListView.separated(
            itemCount: c.startupItems.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final it = c.startupItems[i];
              return ListTile(
                title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  it.canChange
                      ? shortenPath(it.path)
                      : '${shortenPath(it.path, 55)}\nНужны права администратора',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                isThreeLine: !it.canChange,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(label: Text(it.source.chip)),
                    const SizedBox(width: 12),
                    Switch(
                      value: it.enabled,
                      onChanged: it.canChange ? (v) => _toggle(it, v) : null,
                    ),
                  ],
                ),
              );
            },
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Автозагрузка',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Выключенное не удаляется — можно включить обратно.',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            Expanded(child: body),
          ],
        );
      },
    );
  }
}
