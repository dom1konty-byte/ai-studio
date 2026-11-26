import 'package:flutter_test/flutter_test.dart';
import 'package:schetchik/counter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('CounterStore', () {
    test('load: пусто -> 0', () async {
      expect(await CounterStore().load(), 0);
    });

    test('save затем load возвращает то же', () async {
      final store = CounterStore();
      await store.save(42);
      expect(await store.load(), 42);
    });

    test('save пишет в ключ counter', () async {
      await CounterStore().save(5);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('counter'), 5);
    });

    test('save 0 сохраняет 0', () async {
      final store = CounterStore();
      await store.save(9);
      await store.save(0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(CounterStore.key), 0);
      expect(await store.load(), 0);
    });

    test('load: отрицательное значение -> 0', () async {
      SharedPreferences.setMockInitialValues({'counter': -3});
      expect(await CounterStore().load(), 0);
    });

    test('load: большое значение читается', () async {
      SharedPreferences.setMockInitialValues({'counter': 2147483647});
      expect(await CounterStore().load(), 2147483647);
    });

    test('load: значение другого типа (ошибка чтения) -> 0', () async {
      SharedPreferences.setMockInitialValues({'counter': 'abc'});
      expect(await CounterStore().load(), 0);
    });
  });

  group('CounterController', () {
    test('старт: 0, loaded=false до load', () async {
      final c = CounterController(CounterStore());
      expect(c.value, 0);
      expect(c.loaded, isFalse);
      await c.load();
      expect(c.loaded, isTrue);
      expect(c.value, 0);
    });

    test('load подхватывает сохранённое', () async {
      SharedPreferences.setMockInitialValues({'counter': 11});
      final c = CounterController(CounterStore());
      await c.load();
      expect(c.value, 11);
    });

    test('increment много раз', () async {
      final c = CounterController(CounterStore());
      await c.load();
      for (var i = 0; i < 1000; i++) {
        c.increment();
      }
      expect(c.value, 1000);
    });

    test('decrement при 0 остаётся 0 и не уведомляет и не пишет', () async {
      final c = CounterController(CounterStore());
      await c.load();
      var notified = 0;
      c.addListener(() => notified++);
      c.decrement();
      expect(c.value, 0);
      expect(notified, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(CounterStore.key), isFalse);
    });

    test('decrement: 1 -> 0, не уходит ниже', () async {
      final c = CounterController(CounterStore());
      await c.load();
      c.increment();
      c.decrement();
      c.decrement();
      expect(c.value, 0);
    });

    test('reset ставит 0 и сохраняет 0', () async {
      final c = CounterController(CounterStore());
      await c.load();
      for (var i = 0; i < 5; i++) {
        c.increment();
      }
      c.reset();
      expect(c.value, 0);
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(CounterStore.key), 0);
    });

    test('каждое действие сохраняется', () async {
      final c = CounterController(CounterStore());
      await c.load();
      final prefs = await SharedPreferences.getInstance();
      c.increment();
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getInt(CounterStore.key), 1);
      c.increment();
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getInt(CounterStore.key), 2);
      c.decrement();
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getInt(CounterStore.key), 1);
    });

    test('новый контроллер видит сохранённое (новый запуск)', () async {
      final a = CounterController(CounterStore());
      await a.load();
      a.increment();
      a.increment();
      a.increment();
      await Future<void>.delayed(Duration.zero);
      final b = CounterController(CounterStore());
      await b.load();
      expect(b.value, 3);
    });

    test('уведомляет слушателей при изменении', () async {
      final c = CounterController(CounterStore());
      await c.load();
      var notified = 0;
      c.addListener(() => notified++);
      c.increment();
      c.decrement();
      expect(notified, 2);
    });

    test('dispose до окончания load — без исключения', () async {
      final c = CounterController(CounterStore());
      final f = c.load();
      c.dispose();
      await f;
    });
  });
}
