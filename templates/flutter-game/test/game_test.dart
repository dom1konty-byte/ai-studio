import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:{{PACKAGE}}/game/components/target.dart';
import 'package:{{PACKAGE}}/game/my_game.dart';

void main() {
  final withGame = FlameTester(() => MyGame(random: Random(1)));

  withGame.testGameWidget(
    'игра загружается: цель и счёт на экране',
    verify: (game, tester) async {
      expect(game.children.whereType<Target>().length, 1);
      expect(game.scoreText.text, 'Очки: 0');
    },
  );

  withGame.testGameWidget(
    'нажатие по цели даёт очко',
    verify: (game, tester) async {
      final target = game.children.whereType<Target>().first;
      await tester.tapAt(target.absolutePosition.toOffset());
      // pump с паузой: ждём таймеры распознавания жестов, иначе «Timer is still pending»
      await tester.pump(const Duration(milliseconds: 500));
      expect(game.score, 1);
      expect(game.scoreText.text, 'Очки: 1');
    },
  );

  testWithGame<MyGame>(
    'цель не вылетает за экран',
    () => MyGame(random: Random(1)),
    (game) async {
      final target = game.children.whereType<Target>().first;
      for (var i = 0; i < 600; i++) {
        game.update(1 / 60);
      }
      expect(
        target.position.x,
        inInclusiveRange(target.radius, game.size.x - target.radius),
      );
      expect(
        target.position.y,
        inInclusiveRange(target.radius, game.size.y - target.radius),
      );
    },
  );
}
