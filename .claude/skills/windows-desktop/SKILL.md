---
name: windows-desktop
description: (Заготовка) Программа для Windows на Flutter desktop — создание платформы, сборка .exe, упаковка. Использовать для проектов типа «программа для Windows».
---
# Windows (Flutter desktop) — минимум

Работать в `projects/<slug>/`.

1. Платформа: `flutter create --platforms=windows --org com.aistudio --project-name <package> .`
2. Запуск локально (только на Windows): `flutter run -d windows`.
3. Сборка: `flutter build windows --release` → `build/windows/x64/runner/Release/` (вся папка = программа, `.exe` + dll + data).
4. CI: workflow проекта на `windows-latest`, артефакт `<slug>-windows` (zip папки Release).
5. Требования на компьютере: Visual Studio 2022 с «Desktop development with C++».

Позже (не сейчас): установщик MSIX (`msix` пакет), подпись сертификатом, автообновление.
