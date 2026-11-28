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
        child: Container(
          width: 420,
          margin: const EdgeInsets.fromLTRB(0, 10, 14, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 6)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 10, 0),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text('Расходы',
                              overflow: TextOverflow.ellipsis,
                              style: Rubka.head(24, weight: FontWeight.w700))),
                      IconButton(
                          tooltip: 'Закрыть (Esc)',
                          onPressed: () => c.toggleUsage(false),
                          icon: const Icon(Icons.close)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: LimitBanner(controller: c),
                ),
                Expanded(
                  child: summary.isEmpty
                      ? Center(
                          child: Text('Пока нет ходов',
                              style: Rubka.body(color: Rubka.ink2)))
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _big('Сегодня', summary.total.today),
                                const SizedBox(width: 8),
                                _big('7 дней', summary.total.week),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _bigWide('Всего', summary.total.all),
                            const SizedBox(height: 16),
                            Text('По проектам',
                                style: Rubka.head(16, weight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            for (final k in keys)
                              _rowCard(names[k] ?? k, summary.rows[k]!),
                            if (summary.rows.containsKey(officeKey))
                              _rowCard('Офис', summary.rows[officeKey]!),
                            const SizedBox(height: 8),
                            Text(
                                'Условная стоимость по данным Claude Code: '
                                'при подписке она не списывается.',
                                style: Rubka.body(
                                    size: 13, color: Rubka.ink2)),
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

  Widget _big(String title, UsageTotals t) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Rubka.bento, borderRadius: BorderRadius.circular(18)),
          child: _bigBody(title, t),
        ),
      );

  Widget _bigWide(String title, UsageTotals t) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Rubka.ink, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                overflow: TextOverflow.ellipsis,
                style: Rubka.body(size: 13, color: const Color(0xFF9AA0A6))),
            Text(_money(t.cost),
                overflow: TextOverflow.ellipsis,
                style: Rubka.head(34, weight: FontWeight.w700, color: Colors.white)),
            Text(_tokens(t.tokens),
                overflow: TextOverflow.ellipsis,
                style: Rubka.body(size: 13, color: const Color(0xFF9AA0A6))),
          ],
        ),
      );

  Widget _bigBody(String title, UsageTotals t) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              overflow: TextOverflow.ellipsis,
              style: Rubka.body(size: 13, color: Rubka.ink2)),
          Text(_money(t.cost),
              overflow: TextOverflow.ellipsis,
              style: Rubka.head(28, weight: FontWeight.w700)),
          Text(_tokens(t.tokens),
              overflow: TextOverflow.ellipsis,
              style: Rubka.body(size: 13, color: Rubka.ink2)),
        ],
      );

  /// Строка таблицы по проектам.
  Widget _rowCard(String name, UsageRow r) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Rubka.bento, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              overflow: TextOverflow.ellipsis,
              style: Rubka.head(15, weight: FontWeight.w700)),
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
            Text(title,
                overflow: TextOverflow.ellipsis,
                style: Rubka.body(size: 12, color: Rubka.ink2)),
            Text(_money(t.cost),
                overflow: TextOverflow.ellipsis, style: Rubka.body(size: 15)),
            Text(_tokens(t.tokens),
                overflow: TextOverflow.ellipsis,
                style: Rubka.body(size: 12, color: Rubka.ink2)),
          ],
        ),
      );
}
