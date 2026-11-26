// Съёмка скриншотов для Google Play (навык store-screenshots).
// Запуск: flutter test --update-goldens --dart-define=SCREENSHOTS=true test/screenshots_test.dart
// Обычный `flutter test` эти тесты пропускает.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// TODO: импорт своего приложения, например:
// import 'package:<package>/main.dart';

/// Экраны для съёмки: имя файла → виджет. Порядок = порядок в сторе.
final shots = <String, Widget Function()>{
  // '01_main': () => const App(),
};

/// Действия перед снимком (нажать кнопки, ввести данные). Необязательно.
final prepare = <String, Future<void> Function(WidgetTester)>{
  // '01_main': (t) async { await t.tap(find.text('+1')); await t.pump(); },
};

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
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

const _enabled = bool.fromEnvironment('SCREENSHOTS');

void main() {
  setUpAll(_loadFonts);

  for (final entry in shots.entries) {
    testWidgets('screenshot ${entry.key}', skip: !_enabled, (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(entry.value());
      await tester.pumpAndSettle();
      await prepare[entry.key]?.call(tester);
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp).first,
        matchesGoldenFile('../store/raw/${entry.key}.png'),
      );
    });
  }
}
