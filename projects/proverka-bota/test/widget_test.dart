import 'package:flutter_test/flutter_test.dart';
import 'package:proverka_bota/main.dart';

void main() {
  testWidgets('приложение запускается', (tester) async {
    await tester.pumpWidget(const App());
    expect(find.text('Проверка бота'), findsOneWidget);
  });
}
