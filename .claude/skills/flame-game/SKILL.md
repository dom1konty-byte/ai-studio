---
name: flame-game
description: Игры на Flutter + Flame (2D, Android) — структура игры, компоненты, игровой цикл, столкновения, управление (касания, джойстик), спрайты и анимации, звук, камера, сохранение рекорда, тесты flame_test, производительность. Использовать для проектов типа «игра».
---
# Игры на Flame

Шаблон: `templates/flutter-game` (`/new-project <Имя> game`). Работать в `projects/<slug>/`. Flame ^1.38, flame_test ^2.3.

## Структура
```
lib/main.dart                 MaterialApp → GameScreen → GameWidget(game: MyGame())
lib/game/my_game.dart         FlameGame: onLoad (добавить компоненты), счёт, правила, конец игры
lib/game/components/*.dart    объекты: игрок, враги, пули, бонусы (PositionComponent / SpriteComponent)
lib/game/hud/*.dart           счёт, жизни, кнопки (TextComponent или overlays — Flutter-виджеты)
assets/images, assets/audio   ресурсы (объявить в pubspec.yaml → flutter: assets:)
```
- Экраны меню / пауза / конец игры — `overlayBuilderMap` у `GameWidget` (обычные Flutter-виджеты), переключение `game.overlays.add('pause')`.
- Игровая логика — в компонентах (`update(dt)` — всё движение умножать на `dt`!), игра — только правила и счёт.
- Доступ к игре из компонента: миксин `HasGameReference<MyGame>` → `game`.

## Частое
| Задача | Как |
|---|---|
| Касание объекта | `with TapCallbacks` → `onTapDown` |
| Касание экрана / свайп | у игры `with TapCallbacks` / `DragCallbacks` |
| Джойстик | `JoystickComponent` (knob + background), читать `joystick.relativeDelta` |
| Столкновения | игре `with HasCollisionDetection`; компоненту `with CollisionCallbacks` + `add(CircleHitbox())` / `RectangleHitbox()`; `onCollisionStart` |
| Спрайт | `SpriteComponent(sprite: await game.loadSprite('player.png'))` |
| Анимация | `SpriteAnimationComponent` + `game.loadSpriteAnimation('run.png', SpriteAnimationData.sequenced(amount: 6, stepTime: .1, textureSize: Vector2(32,32)))` |
| Таймер / спавн врагов | `TimerComponent(period: 1.5, repeat: true, onTick: spawn)` или `SpawnComponent` |
| Эффекты | `MoveEffect`, `ScaleEffect`, `OpacityEffect`, `RemoveEffect` с `EffectController(duration: .3)` |
| Камера, мир больше экрана | `world` + `camera.follow(player)`; фиксированное разрешение: `CameraComponent.withFixedResolution(width: 720, height: 1280)` |
| Звук | пакет `flame_audio`: `FlameAudio.play('hit.wav')`, музыка `FlameAudio.bgm.play('music.mp3')`; предзагрузка в `onLoad` |
| Рекорд | `shared_preferences` в сервисе, читать при старте, писать в конце игры |
| Пауза | `game.pauseEngine()` / `resumeEngine()`, при сворачивании приложения — тоже пауза |

## Производительность
- Не создавать объекты в `update` (переиспользовать `Vector2`), удалять улетевшие за экран (`removeFromParent()`).
- Много одинаковых спрайтов → один `SpriteSheet`/атлас. Тяжёлое — в `onLoad`, не в `update`.
- Цель — 60 FPS на среднем телефоне; для отладки `debugMode = true` (рамки хитбоксов) и `FpsTextComponent`.

## Тесты (flame_test)
```dart
final withGame = FlameTester(MyGame.new);
withGame.testGameWidget('нажатие даёт очко', verify: (game, tester) async {
  await tester.tapAt(target.absolutePosition.toOffset());
  await tester.pump(const Duration(milliseconds: 500)); // иначе «Timer is still pending»
  expect(game.score, 1);
});
testWithGame<MyGame>('логика без экрана', MyGame.new, (game) async {
  game.update(1 / 60); // прогнать кадры
});
```
- Случайность — через `Random` в конструкторе игры (в тестах `Random(1)`), иначе тесты «плавают».
- Тестировать правила: счёт, конец игры, столкновения, границы экрана.

## Ресурсы
- Свои или с лицензией CC0 / с правом коммерческого использования (Kenney.nl, OpenGameArt с CC0). Автора и лицензию — в `projects/<slug>/assets/CREDITS.md`.
- Не использовать персонажей, музыку, названия чужих игр.

## Перед выпуском
`flutter analyze`, `flutter test` чисто; игра на паузе при сворачивании; звук можно выключить; рекорд сохраняется; реклама (если есть) — только между раундами (навык `monetization`).
