import 'package:flutter_test/flutter_test.dart';
import 'package:test_skrinshota/main.dart';

void main() {
  testWidgets('приложение запускается', (tester) async {
    await tester.pumpWidget(const App());
    expect(find.text('Тест скриншота'), findsOneWidget);
  });
}
