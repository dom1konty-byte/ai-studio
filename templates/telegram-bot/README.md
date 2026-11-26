# {{NAME}}

{{TYPE}} · папка `projects/{{SLUG}}/` · ветка `{{SLUG}}`

{{ABOUT}}

Где работает бот — `bot.config.json` → `"hosting"`:
- **`windows`** (по умолчанию) — на твоём компьютере, стартует сам при включении. Бесплатно, но бот спит, когда компьютер выключен.
- **`cloudflare`** — круглосуточно в Cloudflare Workers (бесплатный тариф). Публикуется сам после «да» на Выпуске.

## На компьютере (Windows)
1. Один раз: Node.js LTS — https://nodejs.org
2. Двойной клик `windows\setup.cmd` → вставить токен бота (от @BotFather) → бот запущен и в автозагрузке.
3. Остальное: `windows\stop.cmd` — остановить, `windows\start.cmd` — запустить, `windows\update.cmd` — обновить после выпуска, `windows\uninstall.cmd` — убрать из автозагрузки.
- Журнал: `bot.log`. Данные бота: `data.json`. Токен: `.env` (не попадает в git).

## Cloudflare (круглосуточно)
GitHub Secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` (как для сайтов) и `BOT_TOKEN_{{SECRET}}` — токен этого бота.

## Для разработки
`npm install`, `npm test`, `npm run check`, `npm start` (нужен `.env`).
