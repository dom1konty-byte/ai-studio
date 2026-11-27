# ai-studio — ИИ-студия разработки

Студия для Claude Code: директор + 19 сотрудников-агентов, навыки и команды. Делает **Android-приложения (Flutter)**, **сайты и лендинги**, **Telegram-ботов**, позже — **программы для Windows**. Все проекты лежат здесь, каждый в своей папке `projects/<имя>/`.

**1 сессия = 1 проект.** В начале сессии директор спрашивает: новый проект, какой из существующих или «Офис студии» (правки самой студии). После `/new-project` он выдаёт текст для старта новой сессии этого проекта.

Работает одинаково в облаке (claude.ai/code, приложение) и на компьютере (Claude Code CLI / Desktop): студия в папке `.claude/` и загружается сама. Ставить ничего не надо.

## Как пользоваться
1. Открой этот репозиторий в Claude Code.
2. Напиши `/new-project` → назови проект и тип (приложение / сайт / бот / программа).
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

## Telegram-бот студии
Бот сам пишет тебе (без сервера — сообщения отправляет GitHub):
- ⏳ проект ждёт твоего «да» (ТЗ, Дизайн, Выпуск);
- ✅ новая сборка — **скриншот главного экрана** и **APK-файл прямо в чат** (без звука): нажал → установил; для сайта — скриншот страницы;
- ❌ сборка упала (студия чинит сама, это для сведения);
- 🚀 выпуск слит в main, 📲 ушёл в Google Play, 🌐 сайт опубликован;
- ☀️ каждое утро в 08:43 (МСК) — сводка по проектам;
- 📊 по воскресеньям в 19:13 — отчёт за неделю;
- 🔕 с 23:00 до 08:00 (МСК) всё приходит без звука.

Подключение (5 минут): @BotFather → `/newbot` → токен; открыть своего бота → Start; @userinfobot → твой Id. GitHub → Settings → Secrets and variables → Actions → секреты `TELEGRAM_BOT_TOKEN` и `TELEGRAM_CHAT_ID`.
Выключить: GitHub → Settings → Variables → `TELEGRAM_BUILDS` = `off` (сообщения о каждой сборке), `TELEGRAM_MORNING` = `off` (утренняя сводка) или `TELEGRAM_WEEKLY` = `off` (недельный отчёт). Другой часовой пояс — переменная `TELEGRAM_TZ` (сдвиг от UTC, например `5`).

## Telegram-боты (проекты)
`/new-project Мой бот bot`. Где работает — выбираешь на ТЗ:
- **на компьютере** — бесплатно, стартует сам при включении Windows; один раз двойной клик `projects\<бот>\windows\setup.cmd` (нужен Node.js LTS с nodejs.org);
- **круглосуточно в Cloudflare** — бесплатно, публикуется сам после «да» на Выпуске (секреты `CLOUDFLARE_*` и `BOT_TOKEN_<ИМЯ>`).

## iPhone (только для себя)
Приложение можно собрать и для айфона — без App Store, для себя. Директор включает iOS в проекте, GitHub собирает `.ipa` и присылает в Telegram. Ставится на айфон бесплатно через AltStore с компьютера (подпись продлевается сама раз в неделю). Шаги — `.claude/skills/flutter-ios-personal/SKILL.md`.

## Автоматизация студии
- **Удаление проекта:** скажи в офисе «удали проект X» → студия спросит «да» и удалит всё; ветку на GitHub удаляет сам GitHub.
- **Автообновления:** по понедельникам GitHub проверяет новые версии пакетов и шагов сборок и сам готовит PR, в Telegram — 🔄. Скажи в офисе «проверь обновления» → студия проверит и спросит «да».
- **Версия и «Что нового»:** при каждом выпуске номер версии растёт сам, а список изменений простыми словами уходит в Google Play и в Telegram.

## Табло студии (с телефона)
GitHub (приложение или сайт) → репозиторий → **Issues** → закреплённый «Табло студии». Там все проекты: тип, этап, ветка, есть ли в `main`, ссылка на последнюю сборку (APK). Обновляется само: после каждой сборки, при изменениях проектов и раз в час. Видят только те, у кого есть доступ к репозиторию.

## Сами проверяют за агентами
- После каждой правки файла проекта: `.dart` → `dart format` + `dart analyze`, `.html` → `html-validate`, `.css` → `csstree-validator` (`.claude/hooks/after_edit.py`). Ошибки агент чинит сразу.
- После выпуска директор пишет уроки в `docs/lessons.md`; в начале нового проекта читает уроки всех проектов.

## Автовыпуск в Google Play
После твоего «да» на Выпуске приложение само уходит во внутреннее тестирование Google Play. Один раз нужно настроить Play Console — по шагам в `.claude/skills/flutter-android-release/SKILL.md`, раздел 8.

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
| Мобильный | flutter-developer | Sonnet |
| Боты | bot-developer (Telegram, на компьютере или в Cloudflare) | Sonnet |
| Веб | web-developer, backend-architect, seo-specialist | Sonnet, Sonnet, Haiku |
| Windows | windows-developer (заготовка) | Sonnet |
| Качество | test-engineer, code-reviewer, security-auditor | Sonnet |
| Отладка | debugger (только непонятные ошибки) | Opus |
| Выпуск | release-engineer, status-reporter | Sonnet, Haiku |
| Рост | growth-analyst (статистика после выпуска) | Sonnet |

## Навыки
Свои: `new-project`, `approval-gate`, `merge-to-main`, `fiverr-order`, `monetization`, `privacy-policy`, `store-screenshots`, `telegram-bot`, `flutter-android-release`, `landing-page`, `windows-desktop`, `kratko` (короткие ответы).
Взятые: `brainstorming`, `writing-plans`, `test-driven-development`, `systematic-debugging`, `verification-before-completion` (obra/superpowers), `frontend-design`, `webapp-testing`, `skill-creator` (anthropics/skills), `shadcn` (shadcn/ui), 13 навыков Flutter/Dart (flutter/agent-plugins, dart-lang/skills), `app-store-optimization` (alirezarezvani), `aso`, `copywriting`, `copy-editing`, `cro`, `competitor-profiling`, `customer-research`, `churn-prevention` (coreyhaines31). Подробно — `CREDITS.md`.

## Структура
```
.claude/agents/     директор + отделы (product, design, mobile, web, desktop, qa, ops)
.claude/skills/     навыки
.claude/commands/   /new-project, /status, /release, /econ
templates/          шаблоны: flutter-app, web-landing, telegram-bot, windows-app, workflows/
projects/           все проекты; список — projects/README.md
scripts/            new_project.py, status.py, dashboard.py, lessons.py, telegram_notify.py, notify_approvals.py, econ.py, check_studio.py, ci_status.py, merge_pr.py, android_signing.py
.github/workflows/  сборка каждого проекта отдельно, проверка студии и шаблонов, табло
.claude/hooks/      проверки после правок
```

## Ветки
- 1 проект = 1 ветка с его именем: `moy-sait`, `schetchik`. Без `/` и без веток под каждую задачу. Офис — ветка `ai-office`.
- `main` — общая рабочая версия. Попадает туда только через Pull Request. После твоего «да» на Выпуске или на правках офиса студия сама сливает PR (когда проверки зелёные). Без «да» — ничего.

## Секреты (ключ подписи и т.п.)
Никогда не клади в репозиторий. Только GitHub → Settings → Secrets and variables → Actions. Как сделать ключ для Google Play — `.claude/skills/flutter-android-release/SKILL.md`, шаг 4.
