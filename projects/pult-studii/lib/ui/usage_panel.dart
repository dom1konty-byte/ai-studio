import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../models/models.dart';
import '../services/usage.dart';
import '../state/app_controller.dart';
import 'limit_banner.dart';

String _money(double v) => '\$${v.toStringAsFixed(v < 10 ? 2 : 1)}';

String _tokens(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)} млн ток.';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)} тыс. ток.';
  return '$n ток.';
}

/// Боковая панель «Расходы» (400 px справа поверх чата).
class UsagePanel extends StatelessWidget {
  const UsagePanel({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final summary = c.usageSummary;
    final names = {
      for (final p in c.projects) p.slug: p.name,
      officeKey: 'Офис',
    };
    final keys = summary.rows.keys.where((k) => k != officeKey).toList()
      ..sort((a, b) => (names[a] ?? a).compareTo(names[b] ?? b));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            c.toggleUsage(false),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: Rubka.bg,
          elevation: 8,
          child: SizedBox(
            width: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(child: Text('Расходы', style: Rubka.head(20))),
                      IconButton(
                          tooltip: 'Закрыть (Esc)',
                          onPressed: () => c.toggleUsage(false),
                          icon: const Icon(Icons.close)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: LimitBanner(controller: c),
                ),
                Expanded(
                  child: summary.isEmpty
                      ? Center(
                          child: Text('Пока нет ходов',
                              style: Rubka.body(color: Rubka.text2)))
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final k in keys)
                              _rowCard(names[k] ?? k, summary.rows[k]!),
                            if (summary.rows.containsKey(officeKey))
                              _rowCard('Офис', summary.rows[officeKey]!),
                            const Divider(),
                            _rowCard('Итого', summary.total, bold: true),
                            const SizedBox(height: 8),
                            Text(
                                'Условная стоимость по данным Claude Code: '
                                'при подписке она не списывается.',
                                style: Rubka.body(
                                    size: 13, color: Rubka.text2)),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowCard(String name, UsageRow r, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              overflow: TextOverflow.ellipsis,
              style: Rubka.head(bold ? 17 : 15)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cell('Сегодня', r.today),
              _cell('7 дней', r.week),
              _cell('Всего', r.all),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(String title, UsageTotals t) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Rubka.body(size: 12, color: Rubka.text2)),
            Text(_money(t.cost), style: Rubka.body(size: 15)),
            Text(_tokens(t.tokens),
                style: Rubka.body(size: 13, color: Rubka.text2)),
          ],
        ),
      );
}
