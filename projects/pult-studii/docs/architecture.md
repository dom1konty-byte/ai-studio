# Архитектура — Пульт студии

**Коротко для Дамира.** Программа сама ничего не «умеет». Она запускает на компьютере уже установленные Claude Code, git и gh и показывает их ответы в удобном окне. У каждого проекта своя отдельная копия папки (worktree), поэтому чаты разных проектов друг другу не мешают. Всё, что сделали агенты, уходит в git и push. Поэтому с телефона можно продолжать там же.

## 1. Стек
- **Flutter desktop Windows** — подтверждаю: шаблон и CI (`.github/workflows/pult-studii.yml`) уже есть, язык тот же, что во всей студии.
- Состояние: встроенные `ChangeNotifier` + `ListenableBuilder`, без Riverpod/Bloc, потому что экранов мало.
- Пакеты: `path_provider` (папка `%APPDATA%`), `url_launcher` (ссылки), `flutter_markdown_plus` (ответы директора в markdown; старый `flutter_markdown` больше не поддерживается). Больше пакетов не берём.
- Отвергнуто: Electron/Tauri (новый язык для студии), Agent SDK на Node (ещё один процесс, который надо держать запущенным), прямой GitHub API с токеном (токен пришлось бы хранить в программе).

## 2. Запуск Claude Code
Одно сообщение — один запуск (`Process.start`, cwd = worktree проекта):
```
claude -p "<текст>" --resume <session_id> --output-format stream-json --verbose --include-partial-messages
       --permission-mode acceptEdits --disallowedTools AskUserQuestion "Bash(rm *)" "Bash(curl *)" ... (полный список — ClaudeRunner.disallowedTools)
       --allowedTools "Bash(git *)" "Bash(gh *)" "Bash(python *)" "Bash(python3 *)" "Bash(flutter *)" "Bash(dart *)" "Bash(npm *)" "Bash(node *)"
```
- Для первого сообщения `--resume` не передаём. `session_id` берём из первого события `system/init` или из итогового `result`.
- Поток читаем построчно (одна строка = один JSON), декодируем как UTF-8. `assistant` и частичные события — это текст, который печатается на экране. `tool_use` — строка вида «агент запускает: git push». `result` — конец ответа, стоимость (`total_cost_usd`, пригодится в v2), `permission_denials`.
- **Вопрос агента.** `AskUserQuestion` выключаем. Тогда директор задаёт вопрос обычным текстом и заканчивает ход. Ответ Дамира уходит следующим запуском `-p "<ответ>" --resume <id>`. Двусторонний stdin-протокол не нужен.
- **Разрешения.** Правки файлов разрешены (`acceptEdits`), команды — только из списка выше. Если в `result.permission_denials` что-то есть, показываем «Агенту не дали выполнить: …» и кнопку «Разрешить и повторить». Она повторяет запуск с этим инструментом в `--allowedTools`. `--dangerously-skip-permissions` не используем.
- **Вложения (v1.1).** Если в чате есть вложения, добавляем `--add-dir <папка вложений чата>` (флаг `--add-dir` есть в CLI: дополнительные папки, к которым у инструментов есть доступ). Путь проверяется `isSafeAddDir`. `Read` не в `--disallowedTools`, поэтому директор открывает файлы сам; пути лежат в блоке «Вложения (открой инструментом Read)» в тексте запроса.
- «Стоп» — `taskkill /T /F /PID`. Сессия сохраняется до последнего законченного хода.
- Где лежат id: `%APPDATA%\pult-studii\state.json` → `{slug: {sessionId, worktree, lastSeenSha}}`, плюс копия чата `chats\<slug>.jsonl` для показа истории. В git это не кладём: сессия Claude привязана к папке, в которой её запустили, и на другом ПК всё равно не нужна. Кнопка «Новый чат» удаляет `sessionId`.

## 3. Параллельные проекты: git worktree
- Основная папка `ai-studio` всегда стоит на ветке `ai-office` — там идёт вкладка «Офис».
- У каждого проекта отдельная папка: `git worktree add ..\ai-studio-wt\<slug> <slug>`. Ветки ещё нет на ПК → `git worktree add -b <slug> ..\ai-studio-wt\<slug> origin/<slug>`. Одна ветка может быть только в одной папке, и это как раз то, что нужно.
- Внутри worktree директор работает по `CLAUDE.md` как обычно: `git fetch`, `pull`, `merge origin/main`, push в `<slug>`. Команда `git checkout <slug>` там ничего не меняет и не мешает. Папки `.claude/` и `scripts/` у каждой ветки свои, после `merge origin/main` они свежие.
- Перед каждым сообщением программа делает `git -C <wt> fetch` и `pull --ff-only`, если в папке нет незакоммиченных правок. Если правки есть, пишет директору первой строкой: «в папке есть незакоммиченные правки».

**Как сделано в шаге 2.** `GitService.prepareProject` (fetch → worktree → pull) и `prepareOffice`. Мьютекс git — на папку: ключ основной папки общий для fetch, `worktree add/prune` и переключения веток, у worktree свой ключ. `state.json` хранит `worktree` (папка разговора): при смене папки `sessionId` сбрасывается. Стартовый текст добавляется к первому сообщению, если `sessionId` нет. Remote Control: `RemoteControl.build` (фиксированные аргументы, `isSafeLaunchPath`, `isValidSessionId`), флаг `rcOpen` хранится в `state.json`. «Новый проект»: `AppController.startNewProject`.

## 4. Доска
- Ветки и этапы берём через локальный git, без API (так же работает `scripts/status.py`, переносим его логику в Dart): `git fetch --prune`, затем `git show origin/<ветка>:projects/README.md`. Из строки проекта берём этап.
- Сборки — через gh, он уже вошёл в GitHub, поэтому токен в программе не хранится: `gh api repos/{o}/{r}/actions/workflows/<slug>.yml/runs?branch=<slug>&per_page=1`. Если есть успешный run → `gh api .../actions/runs/<id>/artifacts`. Кнопка «Скачать» → `gh run download <id> -n <artifact> -D %USERPROFILE%\Downloads\<slug>` и открыть папку. Артефакты хранятся 30 дней, потом кнопка неактивна.
- Обновление: при открытии программы, кнопкой и раз в 3 минуты, пока окно активно. Запросов мало, лимит API не задеваем.

## 5. «Что сделано с телефона»
У каждой ветки есть `lastSeenSha` — последний коммит, который Дамир видел. После `git fetch` выполняем `git log --format="%h %cs %s" <lastSeenSha>..origin/<slug>`. Если там есть коммиты, на доске значок «новое», а в чате плашка «Пока ПК был выключен: …» со списком. Когда Дамир открывает чат, `lastSeenSha` = `origin/<slug>`. Переписка облачной сессии на ПК не видна, видны только коммиты. Поэтому первым сообщением после такого перерыва программа сама передаёт директору: «С телефона сделаны коммиты …, продолжи с учётом их».

## 6. Remote Control — частично
- Remote Control работает только с **интерактивной** сессией: `claude --remote-control` / `--rc` или `/remote-control` внутри открытой сессии. Ещё есть серверный режим `claude remote-control` (`--spawn worktree`, `--capacity`). Нужна версия v2.1.51 или новее, вход через claude.ai (подписка Pro/Max), ПК должен быть включён. Для режима `-p`, на котором построен чат пульта, это не работает. Значит, чат пульта сам на телефоне не появится.
- В v1: в чате проекта кнопка «Открыть на телефоне (Remote Control)». Она закрывает свой `-p`-процесс и открывает окно Windows Terminal в worktree с `claude --resume <id> --remote-control`. Получается та же сессия с той же историей, и её видно в приложении Claude → Code. Пока это окно открыто, чат пульта заблокирован, иначе два процесса будут писать в одну сессию. Кнопка «Продолжить на телефоне» (облако, ПК выключен) остаётся: она копирует `Проект: <Имя> (<slug>). Ветка: <slug>. Задача: …`.

## 7. Кнопки «Да» / «Поправить»
- Директор ждёт ответа, если в строке проекта в `projects/README.md` есть `ждёт «да»`. Читаем строку из worktree (там свежее), а если worktree ещё нет — из `origin/<slug>`. Проверяем после каждого `result` и при обновлении доски.
- «Да» отправляет `да`. «Поправить» открывает поле, отправляет `Поправить: <текст>`. Отправка идёт обычным сообщением в чат (`-p … --resume`), агент со своим навыком `approval-gate` сам продолжает работу. Для «Офиса» так же: ветка `ai-office`, основная папка.
- «Новый проект» — это форма «имя, тип, идея». Она отправляет в чат Офиса текст «Новый проект: …», и Офис запускает `/new-project`. После появления ветки программа создаёт worktree и открывает чат проекта со стартовым текстом.

## 8. Проверка при старте
Проверяем `git --version`, `node --version`, `claude --version` (не ниже 2.1.51, иначе только предупреждение про Remote Control), `gh --version` + `gh auth status`, `python --version` (на нём работают скрипты студии). Ещё проверяем, что папка ai-studio выбрана, в ней есть `.claude/agents` и `git remote` указывает на `ai-studio`. Если чего-то нет, экран «Настройка»: что именно не так, одна команда установки (`winget install Git.Git` / `OpenJS.NodeJS.LTS` / `GitHub.cli` / `Python.Python.3.12`, Claude Code — команда с code.claude.com) и кнопка «Проверить снова». Если Claude Code не вошёл в аккаунт (ошибка в `result` или в stderr со словами login / auth), показываем «Открой терминал и введи `claude`, войди аккаунтом». Ошибку любого процесса показываем целиком, без сокращений.

## 9. Модули `lib/`
```
lib/main.dart
lib/app/            тема, окно, навигация (Чат | Доска | Офис | Новый проект | Настройка)
lib/features/chat/  экран чата, пузыри, кнопки Да/Поправить/Стоп/RC
lib/features/board/ карточки проектов, «новое», «Скачать»
lib/features/setup/ проверки при старте
lib/services/       claude_runner.dart (запуск+разбор stream-json), git_service.dart (worktree, fetch, show, log),
                    gh_service.dart (runs, artifacts, download), tools_check.dart, local_store.dart (state.json, chats)
lib/models/         project.dart, chat_message.dart, build_run.dart
```
Порядок слоёв: экраны → контроллеры (`ChangeNotifier`) → services → внешние процессы. Чистую логику (разбор README, stream-json, `permission_denials`) покрываем `flutter test` на примерах строк.

## Риски
1. Формат `stream-json` и флаги CLI меняются между версиями. Весь разбор держим в `claude_runner.dart`, неизвестные события пропускаем, при старте записываем версию CLI.
2. Разрешения: директору может понадобиться команда не из списка, и тогда ход остановится. Лечится кнопкой «Разрешить и повторить» и расширением списка.
3. Одна сессия открыта в двух местах (пульт и RC-терминал, или облако и ПК в одной ветке). Пульт блокирует себя сам. Облако и ПК одновременно — договорённость: перед работой на ПК — `pull`, и сообщение директору о коммитах с телефона (п. 5).
4. Деньги и лимиты: каждый ход тратит лимит подписки Claude, а у длинных сессий большой контекст. Показываем `total_cost_usd` и кнопку «Новый чат». Подробный учёт — в v2.
5. Windows: `claude` может быть `claude.cmd` (npm) или `claude.exe` (установщик). Ищем через `where claude`, кодировку задаём UTF-8. Пути worktree делаем короткими (лимит длины пути Windows).
6. Принятый риск: установщик Claude Code запускается как `irm https://claude.ai/install.ps1 | iex` (без `-ExecutionPolicy Bypass`, это не файл скрипта); целостность обеспечивает только HTTPS-адрес claude.ai.

## Задачи разработчикам (по порядку)
1. `tools_check` + экран «Настройка» + выбор папки ai-studio.
2. `git_service`: worktree на проект, fetch, чтение README веток (порт `status.py`), `lastSeenSha`.
3. `claude_runner`: запуск `-p`, разбор stream-json, session id в `state.json`, Стоп, `permission_denials`. Тесты на записанных примерах потока.
4. Экран чата (первый экран) + вкладка Офис + кнопки Да/Поправить.
5. Доска: этапы, «новое», сборки и «Скачать» через gh.
6. «Новый проект» через Офис, кнопки «Продолжить на телефоне» и «Remote Control».
7. Сборка в CI, ручная проверка на Windows 11.

## Источники
- Headless / `-p`, stream-json, `--resume`: https://code.claude.com/docs/en/headless
- Флаги CLI (`--permission-mode`, `--allowedTools`, `--include-partial-messages`, `--permission-prompt-tool`): https://code.claude.com/docs/en/cli-reference
- AskUserQuestion / `canUseTool`: https://code.claude.com/docs/en/agent-sdk/user-input
- Remote Control: https://code.claude.com/docs/en/remote-control
