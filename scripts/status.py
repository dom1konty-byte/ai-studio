#!/usr/bin/env python3
"""Статус проектов: строки projects/README.md из main И из всех веток проектов (1 проект = 1 ветка).
Этап берётся из ветки проекта (там он свежее), иначе из main."""
import subprocess
from pathlib import Path
import sys
for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")  # Windows-консоль: кириллица

ROOT = Path(__file__).resolve().parent.parent
SKIP = {"main", "ofis", "HEAD"}


def git(*a):
    r = subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout.strip() if r.returncode == 0 else ""


def rows_of(text):
    out = []
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if line.startswith("|") and len(cells) >= 5 and not set(cells[0]) <= set("-: ") and cells[0] != "Имя":
            out.append(cells)
    return out


git("fetch", "-q", "--prune", "origin")
branches = [b.removeprefix("origin/") for b in git("branch", "-r", "--format=%(refname:short)").splitlines()]
branches = [b for b in branches if b and b not in SKIP and not b.startswith("claude/") and "/" not in b]

projects = {}  # slug -> (name, type, stage, branch)
sources = [("main", git("show", "origin/main:projects/README.md") or (ROOT / "projects/README.md").read_text(encoding="utf-8"))]
sources += [(b, git("show", f"origin/{b}:projects/README.md")) for b in branches]
for src, text in sources:
    for name, folder, typ, stage, branch, *_ in rows_of(text):
        slug = folder.split("`")[1] if "`" in folder else folder
        if src == "main" and slug in projects:
            continue
        if src != "main" and slug != src:
            continue  # в ветке проекта верим только строке этого проекта
        projects[slug] = (name, typ, stage, branch.strip("`"))

if not projects:
    print("Проектов пока нет. Создай: /new-project")
    raise SystemExit

remote = set(branches)
print(f"{'Имя':<20} {'Тип':<20} {'Этап':<22} {'Ветка':<16} {'В main':<7} Последний коммит")
for slug, (name, typ, stage, b) in projects.items():
    in_main = "да" if subprocess.run(["git", "cat-file", "-e", f"origin/main:projects/{slug}/README.md"],
                                     cwd=ROOT, capture_output=True).returncode == 0 else "нет"
    ref = f"origin/{b}" if b in remote else "origin/main"
    last = git("log", ref, "-1", "--format=%cs %s", "--", f"projects/{slug}") or "—"
    mark = "" if b in remote else " (нет)"
    print(f"{name:<20} {typ:<20} {stage:<22} {b + mark:<16} {in_main:<7} {last[:55]}")
