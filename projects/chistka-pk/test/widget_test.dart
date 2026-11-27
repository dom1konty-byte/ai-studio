import 'package:flutter_test/flutter_test.dart';
import 'package:chistka_pk/main.dart';

void main() {
  testWidgets('приложение запускается', (tester) async {
    await tester.pumpWidget(const App());
    expect(find.text('Чистка ПК'), findsOneWidget);
  });
}
