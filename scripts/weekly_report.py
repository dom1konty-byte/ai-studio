#!/usr/bin/env python3
"""Недельный отчёт студии для Telegram: что изменилось по каждому проекту за 7 дней.
  python3 scripts/weekly_report.py   → текст (HTML для Telegram)"""
import html, json, re, subprocess, sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from status import collect, git  # noqa: E402

for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")

since = datetime.now(timezone.utc) - timedelta(days=7)
m = re.search(r"github\.com[/:]([^/]+)/([^/.]+?)(?:\.git)?$", git("remote", "get-url", "origin"))
repo = f"{m.group(1)}/{m.group(2)}"


def runs(slug):
    r = subprocess.run(["gh", "api", f"repos/{repo}/actions/workflows/{slug}.yml/runs?per_page=100&created=>={since:%Y-%m-%d}"],
                       capture_output=True, text=True, encoding="utf-8")
    if r.returncode:
        return None
    data = json.loads(r.stdout).get("workflow_runs", [])
    ok = sum(1 for x in data if x["conclusion"] == "success")
    bad = sum(1 for x in data if x["conclusion"] == "failure")
    return ok, bad


items = collect()
out = [f"📊 <b>Неделя студии</b> ({since:%d.%m} — {datetime.now(timezone.utc):%d.%m})"]
if not items:
    out.append("Проектов нет. Самое время начать новый 🙂")
total_releases = 0
for p in items:
    ref = f"origin/{p['branch']}" if p["branch_exists"] else "origin/main"
    commits = git("log", ref, f"--since={since:%Y-%m-%d}", "--format=%s", "--", f"projects/{p['slug']}").splitlines()
    releases = [c for c in git("log", "origin/main", f"--since={since:%Y-%m-%d}", "--merges", "--format=%s").splitlines()
                if f"/{p['branch']}" in c or c.endswith(f" {p['branch']}")]
    total_releases += len(releases)
    r = runs(p["slug"])
    line = f"• <b>{html.escape(p['name'])}</b> — {html.escape(p['stage'])}"
    if not commits and not releases:
        line += "\n   без изменений за неделю"
    else:
        line += f"\n   изменений: {len(commits)}"
        if releases:
            line += f", выпусков: {len(releases)} 🚀"
        if r:
            line += f", сборок: {r[0]} ✅" + (f" / {r[1]} ❌" if r[1] else "")
    out.append(line)
office = git("log", "origin/main", f"--since={since:%Y-%m-%d}", "--format=%s", "--", ".claude", "scripts", "templates").splitlines()
if office:
    out.append(f"🏢 Офис: изменений — {len(office)}")
waiting = [p["name"] for p in items if "ждёт" in p["stage"] or "✅" in p["stage"]]
if waiting:
    out.append("⏳ Ждут твоего «да»: " + ", ".join(html.escape(w) for w in waiting))
print("\n".join(out))
