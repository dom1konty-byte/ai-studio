import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:material_ui/material_ui.dart';

import 'components/target.dart';

/// Пример игры: по экрану летает цель, нажатие по ней даёт +1 очко.
/// Замените на свою игру — структура остаётся: игра → компоненты → HUD.
class MyGame extends FlameGame {
  MyGame({Random? random}) : random = random ?? Random();

  final Random random;
  int score = 0;
  late final TextComponent scoreText;

  @override
  Color backgroundColor() => const Color(0xFF1E1B2E);

  @override
  Future<void> onLoad() async {
    scoreText = TextComponent(
      text: 'Очки: 0',
      position: Vector2(16, 16),
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.white, fontSize: 24),
      ),
    );
    await addAll([Target(), scoreText]);
  }

  void addPoint() {
    score++;
    scoreText.text = 'Очки: $score';
  }
}
