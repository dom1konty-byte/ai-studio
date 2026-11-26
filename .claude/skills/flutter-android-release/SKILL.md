---
name: flutter-android-release
description: Выпуск Android-приложения на Flutter — версия, иконка, подпись ключом через GitHub Secrets, сборка APK (для теста) и AAB (для Google Play), описание и скриншоты для стора. Использовать на этапе Выпуск или по /release для приложения.
---
# Выпуск Android (Flutter)

Работать в `projects/<slug>/`. Публикация — только после ✅ (`approval-gate`).

## 1. Платформа
Нет `android/` → `flutter create --platforms=android --org com.aistudio --project-name <package> .` (существующие файлы не перезаписываются). Закоммить `android/`.

## 2. Версия
`pubspec.yaml`: `version: 1.2.0+5` → `1.2.0` видит пользователь, `+5` (versionCode) — каждый выпуск +1.

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

## 5. Подпись в Gradle (`android/app/build.gradle.kts`)
```kotlin
import java.util.Properties
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(f.inputStream())
}
android {
    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }
    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isNotEmpty())
                signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}
```
Без этого шага ключ из секретов не применяется (workflow предупредит). Workflow проекта сам создаёт `android/key.properties` из секретов (если они заданы). Без секретов — сборка подписывается отладочным ключом (годится для установки на телефон, не для Play).

## 6. Сборка
- Локально: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`; `flutter build appbundle` → `build/app/outputs/bundle/release/app-release.aab`.
- CI: пуш в ветку проекта → Actions → запуск → Artifacts → `<slug>-apk` (скачать с телефона, распаковать zip, установить).
- Ручной запуск с AAB: Actions → workflow проекта → Run workflow → `aab: true`.

## 7. Google Play (папка `store/`)
- `store/listing.md`: название ≤30, краткое ≤80, полное ≤4000 (агент `copywriter`).
- Скриншоты телефона 2–8 шт., 1080×1920, и feature graphic 1024×500 — навык `store-screenshots`; иконка 512×512.
- Проверка лимитов текста: `python3 -I .claude/skills/app-store-optimization/scripts/check_listing.py projects/<slug>/store/listing.md`.
- Политика конфиденциальности и Data safety — навык `privacy-policy`.
- Загрузка в Play Console — Дамир вручную (аккаунт разработчика $25), после ✅.

## Проверка перед ✅
`flutter analyze` чисто, `flutter test` зелёные, APK устанавливается и запускается, версия увеличена.
