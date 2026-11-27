#!/usr/bin/env python3
"""Перед выпуском (в ветке проекта, до «да»): поднять версию и собрать черновик «Что нового».
  python3 scripts/release_notes.py <slug> [--minor|--major]
- Flutter: pubspec.yaml version 1.2.3+N → 1.2.4 (или 1.3.0 / 2.0.0); бот: package.json "version".
- Черновик изменений — из коммитов ветки после прошлого выпуска (то, чего нет в main).
- Пишет: projects/<slug>/docs/changelog.md (вверх новая версия) и
         projects/<slug>/store/whatsnew/whatsnew-ru-RU (≤500 знаков, для Google Play и Telegram).
Черновик технический → copywriter переписывает простыми словами, потом коммит."""
import json, re, subprocess, sys
from datetime import date
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent


def git(*a):
    r = subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout.strip() if r.returncode == 0 else ""


args = [a for a in sys.argv[1:] if not a.startswith("--")]
if len(args) != 1:
    sys.exit(__doc__)
slug = args[0]
part = "major" if "--major" in sys.argv else "minor" if "--minor" in sys.argv else "patch"
proj = ROOT / "projects" / slug
if not proj.is_dir():
    sys.exit(f"Нет папки projects/{slug}")


def bump(v):
    ma, mi, pa = (list(map(int, v.split("."))) + [0, 0, 0])[:3]
    return {"major": f"{ma + 1}.0.0", "minor": f"{ma}.{mi + 1}.0", "patch": f"{ma}.{mi}.{pa + 1}"}[part]


old = new = None
pub, pkg = proj / "pubspec.yaml", proj / "package.json"
if pub.exists():
    t = pub.read_text(encoding="utf-8")
    m = re.search(r"^version:\s*([0-9.]+)(\+\d+)?", t, re.M)
    if m:
        old = m.group(1)
        new = bump(old)
        pub.write_text(t[:m.start()] + f"version: {new}{m.group(2) or '+1'}" + t[m.end():], encoding="utf-8")
elif pkg.exists():
    d = json.loads(pkg.read_text(encoding="utf-8"))
    old = d.get("version", "0.0.0")
    new = bump(old)
    d["version"] = new
    pkg.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
first = subprocess.run(["git", "cat-file", "-e", f"origin/main:projects/{slug}"],
                       cwd=ROOT, capture_output=True).returncode != 0  # проекта ещё нет в main
if first and old:  # первый выпуск — версию не поднимаем
    new = old
    if pub.exists():
        pub.write_text(re.sub(r"^version:\s*[0-9.]+", f"version: {old}", pub.read_text(encoding="utf-8"), count=1, flags=re.M), encoding="utf-8")
    else:
        d = json.loads(pkg.read_text(encoding="utf-8")); d["version"] = old
        pkg.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
version = new or date.today().isoformat()

skip = re.compile(r"(ждёт|ждет|одобр|этап|выпуск|Merge|merge|слияние|ВРЕМЕННО|бриф|ТЗ|дизайн|создан проект)", re.I)
subjects = git("log", "origin/main..HEAD", "--no-merges", "--format=%s", "--", f"projects/{slug}").splitlines()
items = []
for s in subjects:
    s = re.sub(rf"^{re.escape(slug)}:\s*", "", s).strip()
    if s and not skip.search(s) and s not in items:
        items.append(s)
items = items[:10] or (["Первый выпуск"] if first else ["Небольшие улучшения"])

(proj / "docs").mkdir(exist_ok=True)
cl = proj / "docs" / "changelog.md"
head = f"## {version} — {date.today():%d.%m.%Y}\n" + "".join(f"- {i}\n" for i in items) + "\n"
old_cl = cl.read_text(encoding="utf-8") if cl.exists() else "# Что нового\n\n"
title, _, rest = old_cl.partition("\n\n")
cl.write_text(f"{title}\n\n{head}{rest}", encoding="utf-8")

wn = proj / "store" / "whatsnew"
wn.mkdir(parents=True, exist_ok=True)
text = "\n".join(f"• {i}" for i in items)
(wn / "whatsnew-ru-RU").write_text(text[:500], encoding="utf-8")
print(f"Версия: {old or '—'} → {version}" + (" (первый выпуск, без повышения)" if first else ""))
print("Черновик «Что нового» (переписать простыми словами — copywriter, ≤500 знаков):")
print(text)
