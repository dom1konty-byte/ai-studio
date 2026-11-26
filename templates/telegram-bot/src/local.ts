/**
 * Запуск на компьютере (Windows): бот сам спрашивает Telegram о новых сообщениях (long polling).
 * Работает, пока включён компьютер. Токен — в файле .env рядом (BOT_TOKEN=...), не в git.
 * Запуск: npm start. Автозагрузка: windows\setup.cmd
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { createBot } from "./bot.js";
import type { Storage } from "./storage.js";

class FileStorage implements Storage {
  private data: Record<string, string>;
  constructor(private path: string) {
    this.data = existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : {};
  }
  async get(key: string) {
    return this.data[key] ?? null;
  }
  async set(key: string, value: string) {
    this.data[key] = value;
    writeFileSync(this.path, JSON.stringify(this.data, null, 2));
  }
}

const envFile = resolve(".env");
if (existsSync(envFile)) {
  for (const line of readFileSync(envFile, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
  }
}
const token = process.env.BOT_TOKEN;
if (!token) {
  console.error("Нет BOT_TOKEN. Запусти windows\\setup.cmd или создай файл .env: BOT_TOKEN=...");
  process.exit(1);
}

writeFileSync("bot.pid", String(process.pid));
const bot = createBot(token, new FileStorage(resolve("data.json")));
await bot.api.deleteWebhook(); // на случай, если раньше бот работал через Cloudflare
console.log(new Date().toISOString(), "Бот запущен (компьютер).");
await bot.start({ onStart: (me) => console.log("Бот:", "@" + me.username) });
