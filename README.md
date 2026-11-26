# ai-studio — ИИ-студия разработки

Студия для Claude Code: директор + 19 сотрудников-агентов, навыки и команды. Делает **Android-приложения и игры (Flutter, Flame)**, **сайты и лендинги**, позже — **программы для Windows**. Все проекты лежат здесь, каждый в своей папке `projects/<имя>/`.

**1 сессия = 1 проект.** В начале сессии директор спрашивает: новый проект, какой из существующих или «Офис студии» (правки самой студии). После `/new-project` он выдаёт текст для старта новой сессии этого проекта.

Работает одинаково в облаке (claude.ai/code, приложение) и на компьютере (Claude Code CLI / Desktop): студия в папке `.claude/` и загружается сама. Ставить ничего не надо.

## Как пользоваться
1. Открой этот репозиторий в Claude Code.
2. Напиши `/new-project` → назови проект и тип (приложение / игра / сайт / программа).
3. Директор проведёт по этапам. Остановится 3 раза и спросит «да?»:
   - **ТЗ** — что делаем;
   - **Дизайн** — как выглядит;
   - **Выпуск** — перед публикацией.
4. Между этими точками студия работает сама. После каждого этапа — короткий отчёт.
5. Есть идея правки — просто напиши: «Счётчик: сделай кнопку сброса». Директор сделает её в ветке проекта `schetchik`.

## Работа с компьютера (Windows)
Один раз поставить:
1. **Git** — https://git-scm.com/download/win (всё по умолчанию).
2. **Flutter** — https://docs.flutter.dev/get-started/install/windows: распаковать в `C:\flutter`, добавить `C:\flutter\bin` в PATH. Для Android — Android Studio (ставит Android SDK). Для программ Windows — Visual Studio 2022 с «Desktop development with C++».
3. **GitHub CLI** — https://cli.github.com, затем в терминале `gh auth login`. Нужен, чтобы студия сама видела проверки GitHub и сливала PR.
4. **Claude Code** — https://claude.com/claude-code (приложение Desktop или CLI).
5. **Python 3** — https://www.python.org/downloads/ (галочка «Add to PATH»). На нём работают скрипты студии.

Открыть студию:
```
git clone https://github.com/dom1konty-byte/ai-studio.git
cd ai-studio
claude
```
Проверка, что всё стоит: `flutter doctor`, `gh auth status`, `python --version`.

## Облако: Flutter в каждой сессии
Чтобы в облачных сессиях был Flutter (тесты за секунды, без ожидания GitHub), один раз добавь скрипт установки в настройки среды: claude.ai/code → выбор среды (environment) → Edit → **Setup script** → вставить:
```bash
if [ ! -x /opt/flutter/bin/flutter ]; then git clone -q --depth 1 -b 3.50.1 https://github.com/flutter/flutter.git /opt/flutter; fi
ln -sf /opt/flutter/bin/flutter /usr/local/bin/flutter
ln -sf /opt/flutter/bin/dart /usr/local/bin/dart
git config --global --add safe.directory /opt/flutter
flutter --disable-analytics >/dev/null 2>&1 || true
flutter --version
```
Сессия будет стартовать примерно на минуту дольше. Без скрипта всё тоже работает: проверки делает GitHub (`scripts/ci_status.py`).

## Хостинг сайтов
Cloudflare Pages (бесплатно, адрес `<проект>.pages.dev`, свой домен — тоже бесплатно). Сайт публикуется сам при слиянии в `main`, то есть после твоего «да» на Выпуске. Один раз нужно добавить в GitHub Secrets `CLOUDFLARE_API_TOKEN` и `CLOUDFLARE_ACCOUNT_ID` — как их получить, в `.claude/skills/landing-page/SKILL.md`, раздел «Деплой».

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
| Рынок и клиенты | market-researcher (стоит ли делать), client-manager (письма клиентам Fiverr) | Sonnet, Haiku |
| Дизайн | ui-designer | Sonnet |
| Мобильный | flutter-developer, game-developer (игры на Flame) | Sonnet |
| Веб | web-developer, backend-architect, seo-specialist | Sonnet, Sonnet, Haiku |
| Windows | windows-developer (заготовка) | Sonnet |
| Качество | test-engineer, code-reviewer, security-auditor | Sonnet |
| Отладка | debugger (только непонятные ошибки) | Opus |
| Выпуск | release-engineer, status-reporter | Sonnet, Haiku |
| Рост | growth-analyst (статистика после выпуска) | Sonnet |

## Навыки
Свои: `new-project`, `approval-gate`, `merge-to-main`, `fiverr-order`, `monetization`, `privacy-policy`, `store-screenshots`, `flame-game`, `flutter-android-release`, `landing-page`, `windows-desktop`, `kratko` (короткие ответы).
Взятые: `brainstorming`, `writing-plans`, `test-driven-development`, `systematic-debugging`, `verification-before-completion` (obra/superpowers), `frontend-design`, `webapp-testing`, `skill-creator` (anthropics/skills), `shadcn` (shadcn/ui), 13 навыков Flutter/Dart (flutter/agent-plugins, dart-lang/skills), `app-store-optimization` (alirezarezvani), `aso`, `copywriting`, `copy-editing`, `cro`, `competitor-profiling`, `customer-research`, `churn-prevention` (coreyhaines31). Подробно — `CREDITS.md`.

## Структура
```
.claude/agents/     директор + отделы (product, design, mobile, web, desktop, qa, ops)
.claude/skills/     навыки
.claude/commands/   /new-project, /status, /release, /econ
templates/          шаблоны: flutter-app, flutter-game, web-landing, windows-app, workflows/
projects/           все проекты; список — projects/README.md
scripts/            new_project.py, status.py, econ.py, check_studio.py, ci_status.py, merge_pr.py
.github/workflows/  сборка каждого проекта отдельно + проверка студии
```

## Ветки
- 1 проект = 1 ветка с его именем: `moy-sait`, `schetchik`. Без `/` и без веток под каждую задачу. Офис — ветка `ofis`.
- `main` — общая рабочая версия. Попадает туда только через Pull Request. После твоего «да» на Выпуске или на правках офиса студия сама сливает PR (когда проверки зелёные). Без «да» — ничего.

## Секреты (ключ подписи и т.п.)
Никогда не клади в репозиторий. Только GitHub → Settings → Secrets and variables → Actions. Как сделать ключ для Google Play — `.claude/skills/flutter-android-release/SKILL.md`, шаг 4.
