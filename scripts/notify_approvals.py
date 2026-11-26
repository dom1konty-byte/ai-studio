#!/usr/bin/env python3
"""Telegram: «проект ждёт твоего „да“». Сравнивает этапы в projects/README.md до и после push.
Срабатывает, когда этап проекта сменился на «… ✅ ждёт «да»».
  python3 scripts/notify_approvals.py <before_sha> <after_sha> <branch>"""
import html, os, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from status import git, rows_of  # noqa: E402

for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")

before, after, branch = sys.argv[1:4]


def stages(sha):
    text = git("show", f"{sha}:projects/README.md") if sha and set(sha) != {"0"} else ""
    out = {}
    for name, folder, typ, stage, *_ in rows_of(text):
        slug = folder.split("`")[1] if "`" in folder else folder
        out[slug] = (name, stage)
    return out


old, new = stages(before), stages(after)
repo = os.environ.get("GITHUB_REPOSITORY", "")
for slug, (name, stage) in new.items():
    waiting = "ждёт" in stage or "ждет" in stage or "✅" in stage
    if not waiting or old.get(slug, (None, None))[1] == stage:
        continue
    link = f"https://github.com/{repo}/tree/{branch}/projects/{slug}/docs"
    text = (f"⏳ <b>{html.escape(name)}</b> ждёт твоего «да»: {html.escape(stage)}\n"
            f"Ответь в сессии проекта «да» или напиши, что поменять.\n<a href=\"{link}\">документы проекта</a>")
    subprocess.run([sys.executable, str(Path(__file__).parent / "telegram_notify.py"), "--text", text], check=False)
    print(f"уведомление: {slug} — {stage}")
