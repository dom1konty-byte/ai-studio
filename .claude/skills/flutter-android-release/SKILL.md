---
name: flutter-android-release
description: Выпуск Android-приложения на Flutter — версия, иконка, подпись ключом через GitHub Secrets, сборка APK (для теста) и AAB (для Google Play), описание и скриншоты для стора. Использовать на этапе Выпуск или по /release для приложения.
---
# Выпуск Android (Flutter)

Работать в `projects/<slug>/`. Публикация — только после ✅ (`approval-gate`).

## 1. Платформа
Нет `android/` → `flutter create --platforms=android --org com.aistudio --project-name <package> .` (существующие файлы не перезаписываются). Закоммить `android/`.

## 2. Версия
Делает `python3 scripts/release_notes.py <slug>` перед выпуском (patch по умолчанию, `--minor`/`--major`), заодно «Что нового». Вручную менять не нужно.
`pubspec.yaml`: `version: 1.2.0+5` → `1.2.0` видит пользователь (менять при выпуске). versionCode (`+5`) в CI подменяется номером запуска workflow (`--build-number`) — растёт сам.

## 3. Иконка
- Положить `assets/icon/icon.png` (1024×1024, без прозрачности для Play).
- `dev_dependencies: flutter_launcher_icons`, в `pubspec.yaml`:
  ```yaml
  flutter_launcher_icons:
    android: true
    image_path: assets/icon/icon.png
    adaptive_icon_background: "#FFFFFF"
    adaptive_icon_foreground: assets/icon/icon.png
  ```
- `dart run flutter_launcher_icons`.
- Название под иконкой: `android/app/src/main/AndroidManifest.xml` → `android:label`.

## 4. Ключ подписи (один раз, на компьютере Дамира — НЕ в репозитории)
```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -w0 upload-keystore.jks > keystore.b64   # Windows: certutil -encode upload-keystore.jks keystore.b64
```
GitHub → Settings → Secrets and variables → Actions → добавить:
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (= upload), `ANDROID_KEY_PASSWORD`.
Потерять ключ = нельзя обновлять приложение. Хранить копию в надёжном месте.

## 5. Подпись в Gradle
Делается автоматически: workflow проекта запускает `python3 ../../scripts/android_signing.py android/app/build.gradle.kts` (подключает `key.properties`, повторный запуск безопасен). Локально — та же команда из `projects/<slug>/`.
Секреты заданы → APK/AAB подписаны ключом (годится для Google Play). Нет секретов → отладочный ключ (только для установки на телефон), в логе notice.

## 6. Сборка
- Локально: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`; `flutter build appbundle` → `build/app/outputs/bundle/release/app-release.aab`.
- CI: пуш в ветку проекта → Actions → запуск → Artifacts → `<slug>-apk` (скачать с телефона, распаковать zip, установить).
- Ручной запуск с AAB: Actions → workflow проекта → Run workflow → `aab: true`.

## 7. Google Play (папка `store/`)
- `store/listing.md`: название ≤30, краткое ≤80, полное ≤4000 (агент `copywriter`).
- Скриншоты телефона 2–8 шт., 1080×1920, и feature graphic 1024×500 — навык `store-screenshots`; иконка 512×512.
- Проверка лимитов текста: `python3 -I .claude/skills/app-store-optimization/scripts/check_listing.py projects/<slug>/store/listing.md`.
- Политика конфиденциальности и Data safety — навык `privacy-policy`.
- Загрузка — автоматически после ✅ (раздел 8).

## 8. Автовыпуск в Google Play (internal testing)
Push в `main` (= слияние после «да» на Выпуске) → workflow проекта собирает подписанный AAB и загружает во **внутреннее тестирование** (`r0adkll/upload-google-play`). Нет секретов → загрузка пропускается с notice, AAB остаётся в артефактах.

Один раз на приложение (Дамир, по шагам):
1. **Аккаунт разработчика:** play.google.com/console → регистрация ($25 один раз), подтверждение личности.
2. **Ключ подписи:** шаг 4 выше → 4 секрета `ANDROID_*` в GitHub.
3. **Создать приложение:** Play Console → «Создать приложение» → название, язык, «Приложение/Игра», «Бесплатное» → создать.
4. **Пакет:** имя пакета будет `com.aistudio.<package>` (как в `projects/<slug>/android/app/build.gradle.kts` → `applicationId`).
5. **Первая сборка — вручную** (Google не даёт загрузить первую через API):
   - GitHub → Actions → workflow проекта → Run workflow → ветка `<slug>`, галочка «Собрать AAB» → скачать артефакт `<slug>-aab` (zip → `app-release.aab`).
   - Play Console → Тестирование → **Внутреннее тестирование** → Создать выпуск → Play App Signing «Продолжить» (Google хранит ключ приложения, наш — ключ загрузки) → загрузить `app-release.aab` → Сохранить → Проверить → Начать развёртывание.
   - Вкладка «Тестировщики» → создать список (свои почты) → скопировать ссылку для тестировщиков.
6. **Сервисный аккаунт (робот для загрузки):**
   - console.cloud.google.com → создать проект (любое имя) → «APIs & Services» → Library → **Google Play Android Developer API** → Enable.
   - IAM & Admin → Service Accounts → Create → имя `play-upload` → Done (роли не нужны) → открыть его → Keys → Add key → JSON → скачается файл.
   - Play Console → **Пользователи и разрешения** → Пригласить пользователя → почта сервисного аккаунта (`…@…iam.gserviceaccount.com`) → вкладка «Приложения» → добавить своё → разрешения: «Выпуск в тестовые треки» (и «Просмотр информации о приложении») → Пригласить.
   - GitHub → Settings → Secrets and variables → Actions → New secret `PLAY_SERVICE_ACCOUNT_JSON` = всё содержимое JSON-файла. Файл потом удалить с компьютера.
7. Дальше всё само: «да» на Выпуске → слияние → через ~10 мин сборка у тестировщиков.

Ошибки:
- «Only releases with status draft may be created on draft app» → приложение ещё черновик: GitHub → Settings → Variables → `PLAY_RELEASE_STATUS` = `draft` (выпуск появится черновиком — развернуть вручную), после первого выпуска переменную удалить.
- «version code … has already been used» → в Play уже есть номер больше: GitHub → Settings → Variables → `BUILD_OFFSET` = (тот номер), следующие сборки будут больше.
- 403 / «caller does not have permission» → разрешения шага 6 ещё не применились (до суток) или не выбрано приложение.

## Проверка перед ✅
`flutter analyze` чисто, `flutter test` зелёные, APK устанавливается и запускается, версия увеличена.
