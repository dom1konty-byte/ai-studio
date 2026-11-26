import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:material_ui/material_ui.dart';

import '../my_game.dart';

/// Цель: летает и отскакивает от краёв. Нажатие → очко и прыжок в случайное место.
class Target extends CircleComponent
    with TapCallbacks, HasGameReference<MyGame> {
  Target()
    : super(
        radius: 40,
        anchor: Anchor.center,
        paint: Paint()..color = Colors.amber,
      );

  final Vector2 velocity = Vector2(160, 120);

  @override
  void onMount() {
    super.onMount();
    position = game.size / 2;
  }

  @override
  void update(double dt) {
    super.update(dt);
    position += velocity * dt;
    if (position.x < radius || position.x > game.size.x - radius) {
      velocity.x = -velocity.x;
      position.x = position.x.clamp(radius, game.size.x - radius);
    }
    if (position.y < radius || position.y > game.size.y - radius) {
      velocity.y = -velocity.y;
      position.y = position.y.clamp(radius, game.size.y - radius);
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    game.addPoint();
    position = Vector2(
      radius + game.random.nextDouble() * (game.size.x - 2 * radius),
      radius + game.random.nextDouble() * (game.size.y - 2 * radius),
    );
  }
}
