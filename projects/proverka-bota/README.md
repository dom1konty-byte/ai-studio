# Проверка бота

Android-приложение · папка `projects/proverka-bota/` · ветка `proverka-bota`

—

- Документы: `docs/` (бриф, ТЗ, дизайн, журнал).
- Сборка APK: GitHub → Actions → «proverka-bota» → последний запуск → Artifacts → `proverka-bota-apk`.
- Локально: `flutter pub get && flutter run`.
- Папка `android/` создаётся командой `flutter create --platforms=android --org com.aistudio --project-name proverka_bota .` (CI делает это сам).
