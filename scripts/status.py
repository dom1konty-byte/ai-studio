#!/usr/bin/env python3
"""Статус проектов: таблица из projects/README.md + последний коммит по папке проекта."""
import re, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def git(*a):
    r = subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True)
    return r.stdout.strip()


rows = []
for line in (ROOT / "projects" / "README.md").read_text(encoding="utf-8").splitlines():
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) >= 5 and line.startswith("|") and not set(cells[0]) <= set("-: ") and cells[0] != "Имя":
        rows.append(cells)

if not rows:
    print("Проектов пока нет. Создай: /new-project")
    raise SystemExit

branches = git("branch", "-a", "--format=%(refname:short)").splitlines()
print(f"{'Имя':<20} {'Тип':<20} {'Этап':<22} {'Ветка':<28} Последний коммит")
for name, folder, typ, stage, branch, *_ in rows:
    slug = re.sub(r".*`([^`]+)`.*", r"\1", folder)
    b = branch.strip("`")
    exists = any(x.endswith(b) for x in branches)
    last = git("log", "--all", "-1", "--format=%cs %s", "--", f"projects/{slug}") or "—"
    print(f"{name:<20} {typ:<20} {stage:<22} {b + ('' if exists else ' (нет)'):<28} {last[:60]}")
