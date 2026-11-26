import { Bot, type BotConfig, type Context, InlineKeyboard } from "grammy";
import type { Storage } from "./storage.js";

/**
 * Логика бота — одна для обоих вариантов (компьютер Windows и Cloudflare).
 * Пример: /start, /help и кнопка-счётчик нажатий (хранится в Storage).
 * Замените на свою логику, структура остаётся.
 */
export function createBot(token: string, storage: Storage, botInfo?: BotConfig<Context>["botInfo"]) {
  const bot = new Bot(token, botInfo ? { botInfo } : undefined);

  const counterKeyboard = (n: number) => new InlineKeyboard().text(`Нажато: ${n}`, "press");

  bot.command("start", async (ctx) => {
    const n = Number((await storage.get(`count:${ctx.chat.id}`)) ?? 0);
    await ctx.reply("Привет! Я бот «{{NAME}}». Нажми кнопку:", {
      reply_markup: counterKeyboard(n),
    });
  });

  bot.command("help", (ctx) => ctx.reply("Команды:\n/start — начать\n/help — помощь"));

  bot.callbackQuery("press", async (ctx) => {
    const chatId = ctx.chat?.id ?? ctx.from.id;
    const n = Number((await storage.get(`count:${chatId}`)) ?? 0) + 1;
    await storage.set(`count:${chatId}`, String(n));
    await ctx.editMessageReplyMarkup({ reply_markup: counterKeyboard(n) });
    await ctx.answerCallbackQuery();
  });

  bot.on("message:text", (ctx) => ctx.reply("Не понял. Напиши /help"));

  bot.catch((err) => console.error("Ошибка бота:", err.error));
  return bot;
}
