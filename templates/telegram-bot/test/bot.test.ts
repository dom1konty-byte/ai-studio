import { describe, expect, it } from "vitest";
import type { Update } from "grammy/types";
import { createBot } from "../src/bot.js";
import { MemoryStorage } from "../src/storage.js";

const botInfo = {
  id: 1, is_bot: true, first_name: "Test", username: "test_bot",
  can_join_groups: true, can_read_all_group_messages: false, supports_inline_queries: false,
  can_connect_to_business: false, has_main_web_app: false,
} as const;

/** Бот без интернета: исходящие запросы к Telegram записываются в calls. */
function setup() {
  const storage = new MemoryStorage();
  const bot = createBot("123:test", storage, botInfo as never);
  const calls: { method: string; payload: any }[] = [];
  bot.api.config.use(async (_prev, method, payload) => {
    calls.push({ method, payload });
    return { ok: true, result: true } as never;
  });
  return { bot, storage, calls };
}

const chat = { id: 42, type: "private" as const, first_name: "Дамир" };
const from = { id: 42, is_bot: false, first_name: "Дамир" };
const message = (text: string): Update => ({
  update_id: 1,
  message: {
    message_id: 1, date: 0, chat, from, text,
    ...(text.startsWith("/") ? { entities: [{ type: "bot_command", offset: 0, length: text.length }] } : {}),
  },
});

describe("бот", () => {
  it("/start отвечает приветствием с кнопкой", async () => {
    const { bot, calls } = setup();
    await bot.handleUpdate(message("/start"));
    expect(calls[0].method).toBe("sendMessage");
    expect(calls[0].payload.text).toContain("Привет");
    expect(calls[0].payload.reply_markup.inline_keyboard[0][0].text).toBe("Нажато: 0");
  });

  it("кнопка увеличивает счётчик и сохраняет его", async () => {
    const { bot, storage, calls } = setup();
    const press: Update = {
      update_id: 2,
      callback_query: {
        id: "c1", from, chat_instance: "x", data: "press",
        message: { message_id: 5, date: 0, chat, text: "Привет" },
      },
    };
    await bot.handleUpdate(press);
    await bot.handleUpdate({ ...press, update_id: 3 });
    expect(await storage.get("count:42")).toBe("2");
    const edit = calls.filter((c) => c.method === "editMessageReplyMarkup").at(-1)!;
    expect(edit.payload.reply_markup.inline_keyboard[0][0].text).toBe("Нажато: 2");
  });

  it("непонятный текст → подсказка /help", async () => {
    const { bot, calls } = setup();
    await bot.handleUpdate(message("привет"));
    expect(calls[0].payload.text).toContain("/help");
  });
});
