# {{NAME}}

{{TYPE}} · папка `projects/{{SLUG}}/` · ветка `{{SLUG}}`

{{ABOUT}}

- Игра: Flutter + Flame. Код игры — `lib/game/` (игра `my_game.dart`, объекты — `components/`). Навык `flame-game`.
- Документы: `docs/` (бриф, ТЗ, дизайн, журнал).
- Сборка APK: GitHub → Actions → «{{SLUG}}» → последний запуск → Artifacts → `{{SLUG}}-apk`.
- Локально: `flutter pub get && flutter run`.
- Папка `android/` создаётся командой `flutter create --platforms=android --org com.aistudio --project-name {{PACKAGE}} .` (CI делает это сам).
