// Скриншот главного экрана для сообщения в Telegram (сборка на GitHub).
// Запуск: flutter test --update-goldens --dart-define=SCREENSHOTS=true test/screenshot_test.dart
// Обычный `flutter test` его пропускает. Картинка: build/telegram/screenshot.png
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zametki/main.dart';

const _enabled = bool.fromEnvironment('SCREENSHOTS');

Future<void> _loadFonts() async {
  final dir = Directory('${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  Future<void> load(String family, Iterable<File> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await loader.load();
  }

  final files = dir.listSync().whereType<File>();
  await load('Roboto', files.where((f) => f.path.contains('Roboto-')));
  await load('MaterialIcons', files.where((f) => f.path.endsWith('MaterialIcons-Regular.otf')));
}

void main() {
  testWidgets('скриншот главного экрана', skip: !_enabled, (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('../build/telegram/screenshot.png'));
  });
}
