// Окно «На телефон»: QR-код и адрес для скачивания APK.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/theme.dart';
import '../services/phone_share.dart';
import '../state/phone_share_controller.dart';

class PhoneShareDialog extends StatefulWidget {
  const PhoneShareDialog({super.key, required this.share});

  final PhoneShareController share;

  @override
  State<PhoneShareDialog> createState() => _PhoneShareDialogState();
}

class _PhoneShareDialogState extends State<PhoneShareDialog> {
  @override
  void dispose() {
    // Закрытие окна выключает раздачу и убирает временную папку.
    final s = widget.share;
    s.stop().whenComplete(s.dispose);
    super.dispose();
  }

  String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = widget.share;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => AlertDialog(
        title: const Text('Скачай APK на телефон'),
        content: SizedBox(width: 360, child: _body(s)),
        actions: [
          if (s.step == ShareStep.serving)
            FilledButton(onPressed: s.stop, child: const Text('Остановить'))
          else
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть')),
        ],
      ),
    );
  }

  Widget _body(PhoneShareController s) {
    switch (s.step) {
      case ShareStep.downloading:
        return Row(children: [
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text('Качаю APK…', style: Rubka.body()),
        ]);
      case ShareStep.error:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Rubka.errorBg,
              border: Border.all(color: Rubka.error),
              borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(s.error ?? 'Ошибка',
                  style: Rubka.body(size: 14, color: Rubka.error)),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: s.start, child: const Text('Повторить')),
            ],
          ),
        );
      case ShareStep.stopped:
        return Text('Раздача выключена', style: Rubka.body());
      case ShareStep.serving:
        final url = s.url ?? '';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Rubka.line),
                    borderRadius: BorderRadius.circular(18)),
                padding: const EdgeInsets.all(16),
                child: QrImageView(data: url, size: 240),
              ),
            ),
            const SizedBox(height: 12),
            if (s.ips.length > 1)
              DropdownButton<LanAddress>(
                isExpanded: true,
                value: s.selected,
                items: [
                  for (final a in s.ips)
                    DropdownMenuItem(
                        value: a, child: Text('${a.ip} (${a.name})')),
                ],
                onChanged: (a) {
                  if (a != null) unawaited(s.select(a));
                },
              ),
            Row(
              children: [
                Expanded(
                    child: SelectableText(url, style: Rubka.mono(size: 13))),
                IconButton(
                  tooltip: 'Копировать адрес',
                  onPressed: () => Clipboard.setData(ClipboardData(text: url)),
                  icon: const Icon(Icons.copy, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Телефон должен быть в той же Wi-Fi',
                style: Rubka.body(size: 14)),
            const SizedBox(height: 4),
            Text('Раздача выключится через ${_clock(s.remaining)}',
                style: Rubka.body(size: 14, color: Rubka.ink2)),
            const SizedBox(height: 8),
            Text(
                'Если телефон не открывает — Windows могла спросить про '
                'брандмауэр: разреши для частных сетей.',
                style: Rubka.body(size: 13, color: Rubka.text2)),
          ],
        );
    }
  }
}
