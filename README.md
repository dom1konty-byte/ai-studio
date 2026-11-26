# ai-studio — ИИ-студия разработки

Студия для Claude Code: директор + 15 сотрудников-агентов, навыки и команды. Делает **Android-приложения (Flutter)**, **сайты и лендинги**, позже — **программы для Windows**. Все проекты лежат здесь, каждый в своей папке `projects/<имя>/`.

**1 сессия = 1 проект.** В начале сессии директор спрашивает: новый проект, какой из существующих или «Офис студии» (правки самой студии). После `/new-project` он выдаёт текст для старта новой сессии этого проекта.

Работает одинаково в облаке (claude.ai/code, приложение) и на компьютере (Claude Code CLI / Desktop): студия в папке `.claude/` и загружается сама. Ставить ничего не надо.

## Как пользоваться
1. Открой этот репозиторий в Claude Code.
2. Напиши `/new-project` → назови проект и тип (приложение / сайт / программа).
3. Директор проведёт по этапам. Остановится 3 раза и спросит «да?»:
   - **ТЗ** — что делаем;
   - **Дизайн** — как выглядит;
   - **Выпуск** — перед публикацией.
4. Между этими точками студия работает сама. После каждого этапа — короткий отчёт.
5. Есть идея правки — просто напиши: «Счётчик: сделай кнопку сброса». Директор сам создаст ветку `schetchik/reset-button`.

## Команды
| Команда | Что делает |
|---|---|
| `/new-project` | новый проект: папка, ветка, сборка, строка в списке |
| `/status` | все проекты: тип, этап, ветка |
| `/release <проект>` | сборка APK/AAB или сайта, с одобрением перед публикацией |
| `/econ` | сколько токенов ушло за сессию |

## Где скачать APK с телефона
GitHub → репозиторий → **Actions** → workflow с именем проекта → последний зелёный запуск → внизу **Artifacts** → `<проект>-apk`. Скачается zip, внутри `app-release.apk`.

## Сотрудники
| Отдел | Агент | Модель |
|---|---|---|
| Директор | studio-director (главный агент сессии) | Sonnet |
| Архитектура | architect (только сложные решения) | Opus |
| Продукт | product-manager, copywriter | Sonnet, Haiku |
| Дизайн | ui-designer | Sonnet |
| Мобильный | flutter-developer | Sonnet |
| Веб | web-developer, backend-architect, seo-specialist | Sonnet, Sonnet, Haiku |
| Windows | windows-developer (заготовка) | Sonnet |
| Качество | test-engineer, code-reviewer, security-auditor | Sonnet |
| Отладка | debugger (только непонятные ошибки) | Opus |
| Выпуск | release-engineer, status-reporter | Sonnet, Haiku |

## Навыки
Свои: `new-project`, `approval-gate`, `merge-to-main`, `fiverr-order`, `monetization`, `privacy-policy`, `store-screenshots`, `flutter-android-release`, `landing-page`, `windows-desktop`, `kratko` (короткие ответы).
Взятые: `brainstorming`, `writing-plans`, `test-driven-development`, `systematic-debugging`, `verification-before-completion` (obra/superpowers), `frontend-design`, `webapp-testing`, `skill-creator` (anthropics/skills), `shadcn` (shadcn/ui), 13 навыков Flutter/Dart (flutter/agent-plugins, dart-lang/skills), `app-store-optimization` (alirezarezvani), `aso`, `copywriting`, `copy-editing`, `cro` (coreyhaines31). Подробно — `CREDITS.md`.

## Структура
```
.claude/agents/     директор + отделы (product, design, mobile, web, desktop, qa, ops)
.claude/skills/     навыки
.claude/commands/   /new-project, /status, /release, /econ
templates/          шаблоны: flutter-app, web-landing, windows-app, workflows/
projects/           все проекты; список — projects/README.md
scripts/            new_project.py, status.py, econ.py, check_studio.py, ci_status.py, merge_pr.py
.github/workflows/  сборка каждого проекта отдельно + проверка студии
```

## Ветки
- `<проект>/<задача>`: `schetchik/start`, `schetchik/fix-button`.
- `main` — общая рабочая версия. Попадает туда только через Pull Request. После твоего «да» на Выпуске или на правках офиса студия сама сливает PR (когда проверки зелёные). Без «да» — ничего.

## Секреты (ключ подписи и т.п.)
Никогда не клади в репозиторий. Только GitHub → Settings → Secrets and variables → Actions. Как сделать ключ для Google Play — `.claude/skills/flutter-android-release/SKILL.md`, шаг 4.

## Хостинг сайтов
Пока не выбран. Сайт — обычная папка `site/`, подходит для любого хостинга. Шаг деплоя в workflow сайта закомментирован и ждёт выбора.
