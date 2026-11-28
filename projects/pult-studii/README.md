# Рубка (пульт студии)

Программа Windows (Flutter desktop) · папка `projects/pult-studii/` · ветка `pult-studii`.

Шаг 1: доска проектов (этап, «ждёт да», сборка, «Скачать»), чат одного проекта с директором (Claude Code CLI), кнопки «Да»/«Поправить», сводка «что сделано с телефона», экран «Настройка».
Шаг 2 (потом): несколько проектов сразу (worktree), «Новый проект», «Офис», «Открыть на телефоне».

## Как поставить (для Дамира)
1. На GitHub: вкладка Actions → запуск «pult-studii» (последний зелёный) → внизу Artifacts → скачать `Rubka-setup` (zip), распаковать, внутри `Rubka-setup.exe`.
2. Запустить `Rubka-setup.exe`. Windows SmartScreen скажет «Система Windows защитила ваш компьютер» — нажми «Подробнее» → «Выполнить в любом случае» (программа без платной подписи, это нормально).
3. Права администратора не нужны: Рубка ставится в `%LOCALAPPDATA%\Programs\Rubka`. В конце оставь галочки «Ярлык на рабочем столе» и «Запустить Рубку».
4. При первом запуске откроется «Мастер первого запуска»: сам ставит Git, Node.js, GitHub CLI, Claude Code (и Python), помогает войти в GitHub и Claude и скачивает папку студии (`%USERPROFILE%\ai-studio`). Нужен интернет и аккаунты GitHub и Claude. Когда всё готово, мастер закрывается. Открыть снова: «Настройка» внизу списка проектов.
5. Удалить: Параметры Windows → Приложения → Рубка.

Microsoft Store не нужен: если winget нет или он не сработал, мастер сам скачивает Git, GitHub CLI, Node.js, Python и Claude Code с официальных сайтов (подпись файла проверяется перед запуском; Windows может спросить разрешение — нажми «Да»).

Ручная установка программ, если мастер не справился: `winget install --id Git.Git -e`, `OpenJS.NodeJS.LTS`, `GitHub.cli`, `Python.Python.3.12`, `Anthropic.ClaudeCode` (или `npm install -g @anthropic-ai/claude-code`); входы: `gh auth login`, `claude`.

## Запуск
- Первый запуск: мастер сам скачивает студию; свою папку можно указать в шаге «Папка студии» → «Указать папку вручную» (нужны `.claude/agents` и `projects/README.md`). Путь хранится в `%APPDATA%\pult-studii\state.json`.
- Из исходников (Windows): `flutter create --platforms=windows --org com.aistudio --project-name pult_studii .` (один раз), потом `flutter run -d windows`.
- Сборка: `flutter build windows --release`; в GitHub — Actions → «pult-studii»: артефакт `Rubka-setup` (установщик) и `pult-studii-windows` (папка с программой).
- Установщик локально (Windows, Inno Setup 6): `iscc /DMyAppVersion=1.0.0 installer\setup.iss` → `installer\output\Rubka-setup.exe`. Версия берётся из `pubspec.yaml`.
- Проверки: `flutter analyze`, `flutter test`.

## Как работает
- Открытие проекта: `git fetch origin`; если есть незакоммиченные правки — предупреждение и ветка не переключается; `git checkout <slug>` (нет локальной — `git checkout -b <slug> origin/<slug>`); `git pull --ff-only`.
- Пока директор работает, другой проект открыть нельзя.
- Чат: `claude -p … --resume <id> --output-format stream-json …`; история — `%APPDATA%\pult-studii\chats\<slug>.jsonl`.
- Клавиши: Enter — отправить, Shift+Enter — перенос, Esc — стоп, Ctrl+K — поле ввода, F5 — обновить.
- «Скачать»: `gh run download <id> -D %USERPROFILE%\Downloads\<slug>\<id>`, затем открывается папка.
