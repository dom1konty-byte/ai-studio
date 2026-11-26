import 'package:flutter_test/flutter_test.dart';
import 'package:{{PACKAGE}}/main.dart';

void main() {
  testWidgets('приложение запускается', (tester) async {
    await tester.pumpWidget(const App());
    expect(find.text('{{NAME}}'), findsOneWidget);
  });
}
