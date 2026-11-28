import 'package:chistka_pk/core/async_pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AsyncPool: не более limit одновременно, все задачи выполняются', () async {
    final pool = AsyncPool(3);
    final results = await Future.wait([
      for (var i = 0; i < 10; i++)
        pool.run(() async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return i;
        })
    ]);
    expect(results, [for (var i = 0; i < 10; i++) i]);
    expect(pool.maxRunning, 3);
  });

  test('AsyncPool: ошибка задачи не останавливает очередь', () async {
    final pool = AsyncPool(1);
    final bad = pool.run<int>(() async => throw StateError('x'));
    final good = pool.run(() async => 7);
    await expectLater(bad, throwsStateError);
    expect(await good, 7);
  });
}
