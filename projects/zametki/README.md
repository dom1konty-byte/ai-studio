# Заметки

Android-приложение · папка `projects/zametki/` · ветка `zametki`

приложение для себя на Android и iPhone (без магазинов): быстрые заметки, виджет с заметками на главном экране Android (iPhone — второй версией), быстрая заметка с ярлыка/виджета; заметки хранятся на телефоне. iOS включить сразу (навык flutter-ios-personal), виджет — навык flutter-home-widget

- Документы: `docs/` (бриф, ТЗ, дизайн, журнал).
- Сборка APK: GitHub → Actions → «zametki» → последний запуск → Artifacts → `zametki-apk`.
- Локально: `flutter pub get && flutter run`.
- Папка `android/` создаётся командой `flutter create --platforms=android --org com.aistudio --project-name zametki .` (CI делает это сам).
