---
name: store-screenshots
description: Скриншоты для Google Play без эмулятора — Flutter golden-тест снимает экраны 1080×1920 с настоящими шрифтами, скрипт добавляет фон и подпись; плюс feature graphic 1024×500. Работает локально и в GitHub Actions. Использовать на этапе Выпуск или при обновлении страницы в сторе.
---
# Скриншоты для Google Play

Работать в `projects/<slug>/`. Результат: `store/screenshots/*.png` (1080×1920), `store/feature-graphic.png` (1024×500).

## 1. Тест-съёмщик `test/screenshots_test.dart`
Скопируй `.claude/skills/store-screenshots/templates/screenshots_test.dart` в `test/`, поправь список экранов (`shots`). Он:
- загружает шрифт Roboto из SDK Flutter (иначе вместо букв квадраты) и иконки Material;
- ставит размер телефона 1080×1920 (dpr 2.625 → 411×731 dp);
- для каждого экрана делает `matchesGoldenFile('../store/raw/<имя>.png')`.

Съёмка:
```bash
flutter test --update-goldens --dart-define=SCREENSHOTS=true test/screenshots_test.dart
```
Обычный `flutter test` эти тесты пропускает (флаг `SCREENSHOTS` не задан) — goldens не нужны в git, папку `store/raw/` можно не коммитить.

## 2. Рамка и подписи
```bash
python3 -I ../../.claude/skills/store-screenshots/scripts/frame.py store/raw store/screenshots \
  --captions store/captions.txt --bg "#3F51B5"
```
`store/captions.txt`: одна строка на скриншот по алфавиту файлов (≤30 знаков, выгода, не описание кнопки). Нужен Pillow: `pip install pillow`.
Без подписей — флаг не указывать (останется чистый 1080×1920).

## 3. Feature graphic 1024×500
```bash
python3 -I ../../.claude/skills/store-screenshots/scripts/frame.py --feature store/feature-graphic.png \
  --title "<Название>" --subtitle "<выгода ≤40 знаков>" --bg "#3F51B5" --icon assets/icon/icon.png
```

## Правила Google Play
- 2–8 скриншотов телефона, PNG/JPEG, сторона 320–3840 px, соотношение ≤2:1. 1080×1920 подходит.
- Без «№1», «лучший», цен и призывов «скачай сейчас» на картинке; без чужих логотипов.
- Реальные экраны приложения, с правдоподобными данными (не «Lorem ipsum»).

## CI
Шаг в workflow проекта (по желанию, после `flutter test`):
```yaml
- run: flutter test --update-goldens --dart-define=SCREENSHOTS=true test/screenshots_test.dart
- uses: actions/upload-artifact@v4
  with: { name: <slug>-screenshots, path: projects/<slug>/store/raw }
```
