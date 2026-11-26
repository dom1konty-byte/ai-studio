# Проверка табло

Игра Android · папка `projects/proverka-tablo/` · ветка `proverka-tablo`

—

- Игра: Flutter + Flame. Код игры — `lib/game/` (игра `my_game.dart`, объекты — `components/`). Навык `flame-game`.
- Документы: `docs/` (бриф, ТЗ, дизайн, журнал).
- Сборка APK: GitHub → Actions → «proverka-tablo» → последний запуск → Artifacts → `proverka-tablo-apk`.
- Локально: `flutter pub get && flutter run`.
- Папка `android/` создаётся командой `flutter create --platforms=android --org com.aistudio --project-name proverka_tablo .` (CI делает это сам).
