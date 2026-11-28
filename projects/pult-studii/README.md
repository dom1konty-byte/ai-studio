# Рубка (пульт студии)

Программа Windows (Flutter desktop) · папка `projects/pult-studii/` · ветка `pult-studii`.

Шаг 1: доска проектов (этап, «ждёт да», сборка, «Скачать»), чат одного проекта с директором (Claude Code CLI), кнопки «Да»/«Поправить», сводка «что сделано с телефона», экран «Настройка».
Шаг 2 (потом): несколько проектов сразу (worktree), «Новый проект», «Офис», «Открыть на телефоне».

## Нужно на компьютере
Git, Node.js, Claude Code (`npm install -g @anthropic-ai/claude-code`, один раз ввести `claude` и войти), GitHub CLI `gh` (`gh auth login`), Python. Если чего-то нет, при запуске откроется экран «Настройка» с командами `winget`.

## Запуск
- Первый запуск: в «Настройке» указать папку `ai-studio` (где `.claude/agents` и `projects/README.md`). Путь хранится в `%APPDATA%\pult-studii\state.json`.
- Из исходников (Windows): `flutter create --platforms=windows --org com.aistudio --project-name pult_studii .` (один раз), потом `flutter run -d windows`.
- Сборка: `flutter build windows --release`; в GitHub — Actions → «pult-studii», артефакт `pult-studii-windows`.
- Проверки: `flutter analyze`, `flutter test`.

## Как работает
- Открытие проекта: `git fetch origin`; если есть незакоммиченные правки — предупреждение и ветка не переключается; `git checkout <slug>` (нет локальной — `git checkout -b <slug> origin/<slug>`); `git pull --ff-only`.
- Пока директор работает, другой проект открыть нельзя.
- Чат: `claude -p … --resume <id> --output-format stream-json …`; история — `%APPDATA%\pult-studii\chats\<slug>.jsonl`.
- Клавиши: Enter — отправить, Shift+Enter — перенос, Esc — стоп, Ctrl+K — поле ввода, F5 — обновить.
- «Скачать»: `gh run download <id> -D %USERPROFILE%\Downloads\<slug>\<id>`, затем открывается папка.
