# Счётчик

Android-приложение · папка `projects/schetchik/` · ветки `schetchik/...`

простой счётчик нажатий

- Документы: `docs/` (бриф, ТЗ, дизайн, журнал).
- Сборка APK: GitHub → Actions → «schetchik» → последний запуск → Artifacts → `schetchik-apk`.
- Локально: `flutter pub get && flutter run`.
- Папка `android/` создаётся командой `flutter create --platforms=android --org com.aistudio --project-name schetchik .` (CI делает это сам).

## Как получить APK
- GitHub → Actions → «schetchik» → последний запуск → Artifacts → `schetchik-apk` (скачать и распаковать zip).
- Подпись отладочная: годится для установки на телефон, не для Google Play.
