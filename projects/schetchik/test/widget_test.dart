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

Future<void> _tap(WidgetTester tester, String key, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<int?> _saved(WidgetTester tester) async {
  final prefs = await tester.runAsync(SharedPreferences.getInstance);
  return prefs!.getInt(CounterStore.key);
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('старт', () {
    testWidgets('первый запуск: 0, -1 и Сброс неактивны, +1 активна',
        (tester) async {
      await _start(tester);
      expect(_shown(tester), '0');
      expect(_enabled(tester, 'minus'), isFalse);
      expect(_enabled(tester, 'reset'), isFalse);
      expect(_enabled(tester, 'plus'), isTrue);
    });

    testWidgets('до загрузки: индикатор вместо числа, все кнопки неактивны',
        (tester) async {
      await tester.pumpWidget(const App());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('value')), findsNothing);
      expect(_enabled(tester, 'plus'), isFalse);
      expect(_enabled(tester, 'minus'), isFalse);
      expect(_enabled(tester, 'reset'), isFalse);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_shown(tester), '0');
    });

    testWidgets('сохранённое значение читается при старте', (tester) async {
      SharedPreferences.setMockInitialValues({'counter': 7});
      await _start(tester);
      expect(_shown(tester), '7');
      expect(_enabled(tester, 'minus'), isTrue);
      expect(_enabled(tester, 'reset'), isTrue);
    });

    testWidgets('отрицательное сохранённое значение показывается как 0',
        (tester) async {
      SharedPreferences.setMockInitialValues({'counter': -5});
      await _start(tester);
      expect(_shown(tester), '0');
      expect(_enabled(tester, 'minus'), isFalse);
    });
  });

  group('кнопки', () {
    testWidgets('+1 много раз: каждое нажатие даёт +1', (tester) async {
      await _start(tester);
      for (var i = 1; i <= 25; i++) {
        await _tap(tester, 'plus');
        expect(_shown(tester), '$i');
      }
      expect(_enabled(tester, 'minus'), isTrue);
      expect(_enabled(tester, 'reset'), isTrue);
    });

    testWidgets('-1 уменьшает на 1', (tester) async {
      await _start(tester);
      await _tap(tester, 'plus', 3);
      await _tap(tester, 'minus');
      expect(_shown(tester), '2');
    });

    testWidgets('-1 при 0: остаётся 0, кнопка неактивна, ничего не пишется',
        (tester) async {
      await _start(tester);
      await _tap(tester, 'plus');
      await _tap(tester, 'minus');
      expect(_shown(tester), '0');
      expect(_enabled(tester, 'minus'), isFalse);
      // Нажатие на неактивную кнопку не меняет число.
      await tester.tap(find.byKey(const Key('minus')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_shown(tester), '0');
      expect(await _saved(tester), 0);
    });

    testWidgets('Сброс неактивен при 0', (tester) async {
      await _start(tester);
      expect(_enabled(tester, 'reset'), isFalse);
      await tester.tap(find.byKey(const Key('reset')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_shown(tester), '0');
    });

    testWidgets('Сброс: после нажатия 0, кнопки неактивны, сохранено 0',
        (tester) async {
      await _start(tester);
      await _tap(tester, 'plus', 3);
      expect(_shown(tester), '3');
      await _tap(tester, 'reset');
      expect(_shown(tester), '0');
      expect(_enabled(tester, 'reset'), isFalse);
      expect(_enabled(tester, 'minus'), isFalse);
      expect(await _saved(tester), 0);
    });
  });

  group('сохранение', () {
    testWidgets('значение пишется в SharedPreferences после каждого действия',
        (tester) async {
      await _start(tester);
      await _tap(tester, 'plus');
      expect(await _saved(tester), 1);
      await _tap(tester, 'plus');
      expect(await _saved(tester), 2);
      await _tap(tester, 'plus');
      expect(await _saved(tester), 3);
      await _tap(tester, 'minus');
      expect(await _saved(tester), 2);
      await _tap(tester, 'reset');
      expect(await _saved(tester), 0);
    });

    testWidgets('число восстанавливается при новом запуске', (tester) async {
      await _start(tester);
      await _tap(tester, 'plus', 5);
      await _tap(tester, 'minus');
      expect(_shown(tester), '4');

      await tester.pumpWidget(const SizedBox());
      await _start(tester);
      expect(_shown(tester), '4');
    });

    testWidgets('после Сброс новый запуск показывает 0', (tester) async {
      await _start(tester);
      await _tap(tester, 'plus', 2);
      await _tap(tester, 'reset');

      await tester.pumpWidget(const SizedBox());
      await _start(tester);
      expect(_shown(tester), '0');
    });
  });

  group('тема', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: приложение строится, число видно',
          (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _start(tester);

        final context = tester.element(find.byKey(const Key('value')));
        expect(Theme.of(context).brightness, brightness);
        expect(find.byKey(const Key('value')), findsOneWidget);
        expect(_shown(tester), '0');

        // Цвет числа отличается от фона: текст читаем.
        final style = tester.widget<Text>(find.byKey(const Key('value'))).style!;
        final bg = Theme.of(context).scaffoldBackgroundColor;
        expect(style.color, isNotNull);
        expect(style.color, isNot(bg));
        final contrast = (style.color!.computeLuminance() + 0.05) /
            (bg.computeLuminance() + 0.05);
        final ratio = contrast > 1 ? contrast : 1 / contrast;
        expect(ratio, greaterThanOrEqualTo(4.5));
      });
    }

    testWidgets('тема меняется вместе с системной', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _start(tester);
      var context = tester.element(find.byKey(const Key('value')));
      expect(Theme.of(context).brightness, Brightness.light);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      context = tester.element(find.byKey(const Key('value')));
      expect(Theme.of(context).brightness, Brightness.dark);
    });
  });

  group('экран 360dp', () {
    testWidgets('360x640: нет переполнения, число по центру, кнопки >= 48dp',
        (tester) async {
      _setSize(tester, const Size(360, 640));
      await _start(tester);
      expect(tester.takeException(), isNull);

      final center = tester.getCenter(find.byKey(const Key('value')));
      expect(center.dx, closeTo(180, 1));

      for (final k in ['plus', 'minus', 'reset']) {
        final size = tester.getSize(find.byKey(Key(k)));
        expect(size.height, greaterThanOrEqualTo(48), reason: k);
        expect(size.width, greaterThanOrEqualTo(48), reason: k);
      }
      final plus = tester.getRect(find.byKey(const Key('plus')));
      expect(plus.left, greaterThanOrEqualTo(0));
      expect(plus.right, lessThanOrEqualTo(360));
    });

    testWidgets('360dp: большое число (7 цифр) без переполнения',
        (tester) async {
      _setSize(tester, const Size(360, 640));
      SharedPreferences.setMockInitialValues({'counter': 1234567});
      await _start(tester);
      expect(tester.takeException(), isNull);
      expect(_shown(tester), '1234567');
      final r = tester.getRect(find.byKey(const Key('value')));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(360));
    });

    testWidgets('360x480 (низкий экран) без переполнения', (tester) async {
      _setSize(tester, const Size(360, 480));
      await _start(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1280x800: без переполнения', (tester) async {
      _setSize(tester, const Size(1280, 800));
      await _start(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('доступность', () {
    testWidgets('Semantics-метка числа «Счёт: N» обновляется', (tester) async {
      final handle = tester.ensureSemantics();
      await _start(tester);
      expect(find.bySemanticsLabel('Счёт: 0'), findsOneWidget);
      await _tap(tester, 'plus', 2);
      expect(find.bySemanticsLabel('Счёт: 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Счёт: 0'), findsNothing);
      handle.dispose();
    });

    testWidgets('число — liveRegion', (tester) async {
      final handle = tester.ensureSemantics();
      await _start(tester);
      final node = tester.getSemantics(find.bySemanticsLabel('Счёт: 0'));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('подсказки кнопок', (tester) async {
      await _start(tester);
      expect(find.byTooltip('Прибавить один'), findsOneWidget);
      expect(find.byTooltip('Убавить один'), findsOneWidget);
      expect(find.byTooltip('Сбросить счёт'), findsOneWidget);
    });
  });
}
