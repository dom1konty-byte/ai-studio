/**
 * Запуск в Cloudflare Workers (круглосуточно, бесплатно): Telegram сам присылает сообщения (webhook).
 * Включается, если в bot.config.json "hosting": "cloudflare". Публикует GitHub после «да» на Выпуске.
 */
import { webhookCallback } from "grammy";
import { createBot } from "./bot.js";
import type { Storage } from "./storage.js";

interface Env {
  BOT_TOKEN: string;
  WEBHOOK_SECRET: string;
  DATA: KVNamespace;
}

class KvStorage implements Storage {
  constructor(private kv: KVNamespace) {}
  get(key: string) {
    return this.kv.get(key);
  }
  set(key: string, value: string) {
    return this.kv.put(key, value);
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "POST") return new Response("Бот {{NAME}} работает.");
    const bot = createBot(env.BOT_TOKEN, new KvStorage(env.DATA));
    return webhookCallback(bot, "cloudflare-mod", { secretToken: env.WEBHOOK_SECRET })(request);
  },
};
