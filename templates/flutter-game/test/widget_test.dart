import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:{{PACKAGE}}/main.dart';

// Этот файл нужен ещё и затем, чтобы `flutter create` не создал свой тест-заготовку.
void main() {
  testWidgets('приложение открывает экран игры', (tester) async {
    await tester.pumpWidget(const App());
    expect(find.byWidgetPredicate((w) => w is GameWidget), findsOneWidget);
  });
}
