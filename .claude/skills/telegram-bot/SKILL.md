---
name: telegram-bot
description: Telegram-боты на TypeScript + grammY — создание бота в BotFather, команды, кнопки, меню, диалоги, хранение данных, оплата Telegram Stars, тесты без интернета; два варианта работы — компьютер Windows с автозагрузкой или Cloudflare Workers круглосуточно. Использовать для проектов типа «Telegram-бот».
---
# Telegram-боты (grammY)

Шаблон: `templates/telegram-bot` (`/new-project <Имя> bot`). Работать в `projects/<slug>/`. grammY ^1.48, TypeScript, тесты vitest.

## Где работает бот — `bot.config.json` → `"hosting"`
| | `windows` (по умолчанию) | `cloudflare` |
|---|---|---|
| Как | long polling, `src/local.ts`, автозагрузка | webhook, `src/worker.ts` |
| Когда работает | пока включён компьютер | всегда |
| Цена | бесплатно | бесплатно до 100 000 запросов/день |
| Данные | `data.json` рядом | Cloudflare KV |
| Установка | Дамир: `windows\setup.cmd` (токен → автозагрузка) | сама после «да» на Выпуске |
| Секреты | токен в `.env` на компьютере | `BOT_TOKEN_<SLUG>` + `CLOUDFLARE_*` в GitHub |
Выбор — на этапе ТЗ: спросить Дамира «бот нужен только когда включён компьютер или круглосуточно?». Логика одна (`src/bot.ts`), меняется только запуск.

## Структура
```
src/bot.ts       createBot(token, storage) — ВСЯ логика: команды, кнопки, ответы
src/storage.ts   Storage (get/set строк): MemoryStorage для тестов
src/local.ts     запуск на компьютере (FileStorage → data.json)
src/worker.ts    запуск в Cloudflare (KvStorage)
test/*.test.ts   тесты без интернета
windows/*.cmd    setup / start / stop / update / uninstall
```
- Хранить только через `Storage` (строки; объекты — `JSON.stringify`). Ключи вида `user:<id>:...`.
- Никаких глобальных переменных для данных пользователей: в Cloudflare каждый запрос — новый запуск.
- Секреты (токен, ключи API) — только из `.env` / `env`, не в коде.

## Частое
| Задача | Как |
|---|---|
| Команда | `bot.command("start", ctx => ctx.reply(...))`; список команд в меню — `bot.api.setMyCommands([...])` (в `local.ts` при старте) |
| Кнопки под сообщением | `new InlineKeyboard().text("Да", "yes").row().url("Сайт", "https://…")` + `bot.callbackQuery("yes", …)`; всегда `ctx.answerCallbackQuery()` |
| Кнопки вместо клавиатуры | `new Keyboard().text("Меню").resized()` |
| Диалог из шагов (анкета) | хранить шаг в Storage: `user:<id>:step`, в `bot.on("message:text")` смотреть шаг |
| Фото / файлы | `ctx.replyWithPhoto(new InputFile(...))`, входящие — `bot.on("message:photo")` |
| Рассылка | цикл по сохранённым chat id, пауза ≥ 40 мс между сообщениями, ловить 403 (пользователь заблокировал бота) — удалить из списка |
| Оплата | Telegram Stars: `ctx.replyWithInvoice(title, desc, payload, "XTR", [{label, amount}])`, `bot.on("pre_checkout_query", ctx => ctx.answerPreCheckoutQuery(true))`, `bot.on("message:successful_payment")`. Цифровые товары — только Stars |
| Админ-команды | проверять `ctx.from.id` по списку id из `.env` (`ADMIN_IDS`) |
| Время, напоминания | на компьютере — `setInterval`; в Cloudflare — Cron Triggers (`[triggers] crons` в wrangler.toml + `scheduled()` в worker) |

## Тесты (обязательно)
- Бот без интернета: `createBot(token, new MemoryStorage(), botInfo)` + `bot.api.config.use(...)` записывает исходящие вызовы (см. `test/bot.test.ts`).
- `bot.handleUpdate(<update>)` → проверить `calls` (метод, текст, кнопки) и Storage.
- Тест на каждую команду и кнопку, на неожиданный ввод.

## BotFather (Дамир, 2 минуты)
`/newbot` → имя → адрес `…bot` → токен. Дальше по желанию: `/setdescription`, `/setuserpic`, `/setcommands`. Токен — только в `windows\setup.cmd` или в GitHub Secrets, не в чат.

## Правила Telegram
- Не писать людям первым (только тем, кто нажал Start), без спама и массовых рассылок незнакомым.
- Хранить минимум данных; если собираем личные — политика конфиденциальности (навык `privacy-policy`).

## Готово, когда
`npm run check` и `npm test` чисто; бот отвечает на /start и /help; на непонятное — подсказка; ошибки не роняют бота (`bot.catch`).
