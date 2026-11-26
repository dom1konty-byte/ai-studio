/** Хранилище «ключ → значение». На компьютере — JSON-файл, в Cloudflare — KV. */
export interface Storage {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
}

/** В памяти — для тестов. */
export class MemoryStorage implements Storage {
  private data = new Map<string, string>();
  async get(key: string) {
    return this.data.get(key) ?? null;
  }
  async set(key: string, value: string) {
    this.data.set(key, value);
  }
}
