# Чистка ПК

Программа Windows (заготовка) · папка `projects/chistka-pk/` · ветка `chistka-pk`

программа для Windows: очистка ненужного — временные файлы (%TEMP%, Windows\Temp), кэш браузеров (Chrome, Edge, Firefox, Яндекс), корзина, кэш миниатюр, логи; сначала Анализ (категории с размером, галочки) → Очистить → итог «освобождено X ГБ». Безопасность: удалять только известные папки кэша, никогда личные файлы; занятые файлы пропускать; перед очисткой браузера попросить его закрыть; журнал удалённого. Своё название и дизайн (не копировать чужие программы). v2: очистка по расписанию, значок в трее, папки Windows Update/Prefetch с правами администратора

- Создать платформу: `flutter create --platforms=windows --org com.aistudio --project-name chistka_pk .`
- Запуск (на Windows): `flutter run -d windows`. Сборка: `flutter build windows --release`.
- CI: Actions → «chistka-pk» → Run workflow → артефакт `chistka-pk-windows`.
