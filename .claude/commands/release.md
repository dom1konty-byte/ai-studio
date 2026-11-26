---
description: Выпуск проекта — сборка APK/AAB, сайта или программы
argument-hint: "<slug проекта>"
---
Проект: $ARGUMENTS (нет — спроси slug, список в `projects/README.md`).
1. Определи тип проекта по `projects/README.md`.
2. Передай `release-engineer`: app → навык `flutter-android-release`, site → `landing-page` (раздел «Деплой»), windows → `windows-desktop`.
3. Перед сборкой: `test-engineer` и `code-reviewer` — должно быть чисто.
4. Перед публикацией — навык `approval-gate`. Без «да» ничего не публиковать и не мержить в main.
5. После «да» — навык `merge-to-main`: PR → зелёные проверки → слияние в main. Отчёт со ссылкой.
