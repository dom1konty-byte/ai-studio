// Окна «Задачи на ночь»: запланировать и список запланированных.
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../models/scheduled_task.dart';
import '../services/rate_limit.dart';
import '../state/night_tasks.dart';

/// Подсказка в окне.
const nightHint =
    'Компьютер должен быть включён, AI Studio открыта (можно свернуть)';

/// Что выбрал Дамир в окне «Отправить позже».
class NightRequest {
  const NightRequest(this.text, this.when, this.keepAwake);

  final String text;
  final DateTime when;
  final bool keepAwake;
}

Future<NightRequest?> showNightDialog(BuildContext context,
    {required String initialText, required DateTime Function() clock}) {
  return showDialog<NightRequest>(
      context: context,
      builder: (_) => NightDialog(initialText: initialText, clock: clock));
}

class NightDialog extends StatefulWidget {
  const NightDialog({super.key, required this.initialText, required this.clock});

  final String initialText;
  final DateTime Function() clock;

  @override
  State<NightDialog> createState() => _NightDialogState();
}

class _NightDialogState extends State<NightDialog> {
  late final TextEditingController _text;
  final _hour = TextEditingController(text: '02');
  final _minute = TextEditingController(text: '00');
  bool _keepAwake = true;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _text.dispose();
    _hour.dispose();
    _minute.dispose();
    super.dispose();
  }

  int? get _h {
    final v = int.tryParse(_hour.text);
    return v != null && v >= 0 && v <= 23 ? v : null;
  }

  int? get _m {
    final v = int.tryParse(_minute.text);
    return v != null && v >= 0 && v <= 59 ? v : null;
  }

  bool get _valid => _text.text.trim().isNotEmpty && _h != null && _m != null;

  DateTime? get _when {
    final h = _h;
    final m = _m;
    return h == null || m == null ? null : nextOccurrence(widget.clock(), h, m);
  }

  void _setTime(int h, int m) {
    setState(() {
      _hour.text = h.toString().padLeft(2, '0');
      _minute.text = m.toString().padLeft(2, '0');
    });
  }

  String _dayLabel(DateTime when) {
    final now = widget.clock();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(when.year, when.month, when.day);
    return day == today ? 'сегодня' : 'завтра';
  }

  Widget _timeField(String key, TextEditingController c, String label) =>
      SizedBox(
        width: 72,
        child: TextField(
          key: Key(key),
          controller: c,
          maxLength: 2,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label, counterText: ''),
        ),
      );

  Widget _quick(String label, VoidCallback onTap) => ActionChip(
        key: Key('night-quick-$label'),
        label: Text(label, style: Rubka.body(size: 13)),
        onPressed: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final when = _when;
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Отправить позже'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('night-text'),
                controller: _text,
                minLines: 2,
                maxLines: 5,
                maxLength: 4000,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Что сказать директору',
                    alignLabelWithHint: true),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _timeField('night-hour', _hour, 'Часы'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
                    child: Text(':', style: Rubka.head(20)),
                  ),
                  _timeField('night-minute', _minute, 'Минуты'),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Text(
                          when == null
                              ? 'Время: 00:00–23:59'
                              : '${_dayLabel(when)} в ${hhmm(when)}',
                          key: const Key('night-when'),
                          overflow: TextOverflow.ellipsis,
                          style: Rubka.body(size: 14, color: Rubka.ink2)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _quick('через 1 ч', () {
                    final t = widget.clock().add(const Duration(hours: 1));
                    _setTime(t.hour, t.minute);
                  }),
                  _quick('в 02:00', () => _setTime(2, 0)),
                  _quick('в 07:00', () => _setTime(7, 0)),
                ],
              ),
              CheckboxListTile(
                key: const Key('night-awake'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _keepAwake,
                onChanged: (v) => setState(() => _keepAwake = v ?? false),
                title: Text('Не давать компьютеру уснуть до выполнения',
                    style: Rubka.body(size: 14)),
              ),
              Text(nightHint, style: Rubka.body(size: 13, color: Rubka.mute)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
          key: const Key('night-submit'),
          style: accentButtonStyle,
          onPressed: _valid && when != null
              ? () => Navigator.pop(
                  context, NightRequest(_text.text.trim(), when, _keepAwake))
              : null,
          child: const Text('Запланировать'),
        ),
      ],
    );
  }
}

/// Список запланированных задач чата: «Отменить» и «Выполнить сейчас».
class NightListDialog extends StatelessWidget {
  const NightListDialog({super.key, required this.night, required this.chatKey});

  final NightTasks night;
  final String chatKey;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: night,
      builder: (context, _) {
        final list = night.waitingFor(chatKey);
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Запланированные'),
          content: SizedBox(
            width: 460,
            child: list.isEmpty
                ? Text('Пока ничего нет', style: Rubka.body())
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [for (final t in list) _row(t)],
                    ),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть')),
          ],
        );
      },
    );
  }

  Widget _row(ScheduledTask t) {
    final isMissed = night.missed.contains(t.id);
    return Container(
      key: Key('night-task-${t.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Rubka.bubble, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isMissed ? 'Пропущена: ${hhmm(t.when)}' : 'В ${hhmm(t.when)}',
              style: Rubka.body(size: 13, color: Rubka.mute)),
          const SizedBox(height: 2),
          Text(t.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Rubka.body(size: 14)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                  key: Key('night-cancel-${t.id}'),
                  onPressed: () => night.cancel(t.id),
                  child: const Text('Отменить')),
              TextButton(
                  key: Key('night-now-${t.id}'),
                  onPressed: () => night.runNow(t.id),
                  child: const Text('Выполнить сейчас')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Плашки «Пропущена задача на 02:00 — Выполнить сейчас / Отменить».
class NightBanner extends StatelessWidget {
  const NightBanner({super.key, required this.night, required this.nameFor});

  final NightTasks night;
  final String Function(String key) nameFor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: night,
      builder: (context, _) {
        final list = night.missedTasks;
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in list)
              Container(
                key: Key('night-missed-${t.id}'),
                constraints: const BoxConstraints(minHeight: 40),
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                decoration: const BoxDecoration(
                  color: Rubka.summaryBg,
                  border: Border(bottom: BorderSide(color: Rubka.amber)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.alarm, size: 16, color: Rubka.onAmber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'Пропущена задача на ${hhmm(t.when)} (${nameFor(t.key)})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Rubka.body(size: 13, color: Rubka.onAmber)),
                    ),
                    TextButton(
                        key: Key('night-missed-now-${t.id}'),
                        onPressed: () => night.runNow(t.id),
                        child: const Text('Выполнить сейчас')),
                    TextButton(
                        key: Key('night-missed-cancel-${t.id}'),
                        onPressed: () => night.cancel(t.id),
                        child: const Text('Отменить')),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
