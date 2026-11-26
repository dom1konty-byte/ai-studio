import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schetchik/counter_store.dart';
import 'package:schetchik/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _shown(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('value'))).data!;

Future<void> _start(WidgetTester tester) async {
  await tester.pumpWidget(const App());
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(Key(key))).enabled;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('старт: 0, -1 и Сброс неактивны', (tester) async {
    await _start(tester);
    expect(_shown(tester), '0');
    expect(_enabled(tester, 'minus'), isFalse);
    expect(_enabled(tester, 'reset'), isFalse);
    expect(_enabled(tester, 'plus'), isTrue);
  });

  testWidgets('+1 увеличивает, -1 уменьшает не ниже 0', (tester) async {
    await _start(tester);
    await tester.tap(find.byKey(const Key('plus')));
    await tester.tap(find.byKey(const Key('plus')));
    await tester.pump();
    expect(_shown(tester), '2');
    await tester.tap(find.byKey(const Key('minus')));
    await tester.tap(find.byKey(const Key('minus')));
    await tester.pump();
    expect(_shown(tester), '0');
    expect(_enabled(tester, 'minus'), isFalse);
  });

  testWidgets('Сброс обнуляет', (tester) async {
    await _start(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('plus')));
    }
    await tester.pump();
    expect(_shown(tester), '3');
    await tester.tap(find.byKey(const Key('reset')));
    await tester.pump();
    expect(_shown(tester), '0');
  });

  testWidgets('число сохраняется между запусками', (tester) async {
    await _start(tester);
    await tester.tap(find.byKey(const Key('plus')));
    await tester.tap(find.byKey(const Key('plus')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await _start(tester);
    expect(_shown(tester), '2');
  });

  testWidgets('сохранённое значение читается при старте', (tester) async {
    SharedPreferences.setMockInitialValues({'counter': 7});
    await _start(tester);
    expect(_shown(tester), '7');
  });

  test('CounterController: не ниже 0', () async {
    final c = CounterController(CounterStore());
    await c.load();
    c.decrement();
    expect(c.value, 0);
    c.increment();
    c.reset();
    expect(c.value, 0);
  });
}
