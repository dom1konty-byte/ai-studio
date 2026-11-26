#!/usr/bin/env python3
"""Сообщение в Telegram от бота студии. Без сервера: вызывается из GitHub Actions.
Нужны TELEGRAM_BOT_TOKEN и TELEGRAM_CHAT_ID (GitHub Secrets). Нет их → тихо пропускает (код 0).
  telegram_notify.py --text "<b>Привет</b>" [--file app.apk] [--photo shot.png] [--silent] [--failed-step]
  Ночью (23:00–08:00, МСК; TELEGRAM_TZ — сдвиг от UTC) сообщения всегда без звука.
  --failed-step: добавить в текст упавший шаг текущего запуска (через gh api, нужен GH_TOKEN)
  --dry-run: только напечатать, что было бы отправлено"""
import argparse, datetime, json, mimetypes, os, subprocess, sys, urllib.request, uuid
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")

LIMIT = 49 * 1024 * 1024  # бот может отправить файл до 50 МБ

p = argparse.ArgumentParser()
p.add_argument("--text", required=True)
p.add_argument("--file")
p.add_argument("--photo", help="картинка (скриншот) — отдельным сообщением перед текстом/файлом")
p.add_argument("--silent", action="store_true", help="без звука")
p.add_argument("--failed-step", action="store_true")
p.add_argument("--dry-run", action="store_true")
a = p.parse_args()

text = a.text.replace("\\n", "\n")  # из workflow приходит буквальное \n
if a.failed_step and os.environ.get("GITHUB_RUN_ID"):
    r = subprocess.run(["gh", "api", f"repos/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}/jobs",
                        "--jq", '[.jobs[].steps[]? | select(.conclusion=="failure") | .name] | join(", ")'],
                       capture_output=True, text=True, encoding="utf-8")
    if r.returncode == 0 and r.stdout.strip():
        text += f"\nШаг: <code>{r.stdout.strip()}</code>"

tz = datetime.timezone(datetime.timedelta(hours=float(os.environ.get("TELEGRAM_TZ") or 3)))
hour = datetime.datetime.now(tz).hour
if hour >= 23 or hour < 8:
    a.silent = True  # ночная тишина

file = Path(a.file) if a.file else None
if file and (not file.exists() or file.stat().st_size > LIMIT):
    reason = "файла нет" if not file.exists() else f"файл {file.stat().st_size // 1024 // 1024} МБ — больше лимита Telegram"
    text += f"\n({reason}, скачай по ссылке)"
    file = None

token, chat = os.environ.get("TELEGRAM_BOT_TOKEN"), os.environ.get("TELEGRAM_CHAT_ID")
if a.dry_run or not (token and chat):
    print(("[dry-run] " if a.dry_run else "Telegram не настроен (нет TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID) — пропускаю.\n")
          + text + (f"\n+ файл {file}" if file else ""))
    sys.exit(0)

base = os.environ.get("TELEGRAM_API", "https://api.telegram.org") + f"/bot{token}/"  # TELEGRAM_API — только для тестов
common = {"chat_id": chat, "parse_mode": "HTML", "disable_notification": "true" if a.silent else "false"}


def multipart(method, fields, field_name, path):
    boundary = uuid.uuid4().hex
    body = b""
    for k, v in fields.items():
        body += (f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n'
                 f'Content-Type: text/plain; charset=utf-8\r\n\r\n{v}\r\n').encode("utf-8")
    ctype = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    body += (f'--{boundary}\r\nContent-Disposition: form-data; name="{field_name}"; filename="{path.name}"\r\n'
             f"Content-Type: {ctype}\r\n\r\n").encode() + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    return urllib.request.Request(base + method, data=body,
                                  headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})


def send(req):
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.load(resp).get("ok")
    except Exception as e:  # уведомление не должно ломать сборку
        print(f"::warning::Telegram: не отправлено ({type(e).__name__}: {str(e).replace(token, '***')[:200]})")
        return False


photo = Path(a.photo) if a.photo else None
if photo and photo.exists() and photo.stat().st_size < 10 * 1024 * 1024:
    # скриншот с текстом-подписью; файл (если есть) — следом, коротко
    send(multipart("sendPhoto", {**common, "caption": text[:1024]}, "photo", photo))
    text = "⬇️ файл для установки"
    common["disable_notification"] = "true"
if file:
    ok = send(multipart("sendDocument", {**common, "caption": text[:1024]}, "document", file))
elif not (photo and photo.exists()):
    req = urllib.request.Request(base + "sendMessage", data=json.dumps(
        {**common, "text": text[:4096], "disable_web_page_preview": "true"}).encode(),
        headers={"Content-Type": "application/json"})
    ok = send(req)
else:
    ok = True
print("Telegram: отправлено" if ok else "::warning::Telegram: не всё отправлено")
