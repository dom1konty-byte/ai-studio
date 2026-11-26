#!/usr/bin/env python3
"""Статус проектов: строки projects/README.md из main И из всех веток проектов (1 проект = 1 ветка).
Этап берётся из ветки проекта (там он свежее), иначе из main.
  python3 scripts/status.py [--ref <ветка>]   # --ref: добавить ещё ветку (для проверки)"""
import subprocess
import sys
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")  # Windows-консоль: кириллица

ROOT = Path(__file__).resolve().parent.parent
SKIP = {"main", "ai-office", "HEAD"}


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


def collect(extra_refs=()):
    """→ список dict: name, slug, type, stage, branch, branch_exists, in_main, last."""
    git("fetch", "-q", "--prune", "origin")
    branches = [b.removeprefix("origin/") for b in git("branch", "-r", "--format=%(refname:short)").splitlines()]
    branches = [b for b in branches if b and b not in SKIP and not b.startswith("claude/") and "/" not in b]
    main_text = git("show", "origin/main:projects/README.md") or (ROOT / "projects/README.md").read_text(encoding="utf-8")
    sources = [("main", main_text)]
    sources += [(b, git("show", f"origin/{b}:projects/README.md")) for b in branches]
    sources += [(f"extra:{r}", git("show", f"origin/{r}:projects/README.md")) for r in extra_refs if r]
    projects = {}
    for src, text in sources:
        for name, folder, typ, stage, branch, *_ in rows_of(text):
            slug = folder.split("`")[1] if "`" in folder else folder
            if src == "main" and slug in projects:
                continue
            if not src.startswith(("main", "extra:")) and slug != src:
                continue  # в ветке проекта верим только строке этого проекта
            if src.startswith("extra:") and slug in projects:
                continue
            projects[slug] = dict(name=name, slug=slug, type=typ, stage=stage, branch=branch.strip("`"),
                                  ref=src.removeprefix("extra:") if src.startswith("extra:") else None)
    remote = set(branches)
    out = []
    for slug, p in projects.items():
        p["branch_exists"] = p["branch"] in remote
        p["in_main"] = subprocess.run(["git", "cat-file", "-e", f"origin/main:projects/{slug}/README.md"],
                                      cwd=ROOT, capture_output=True).returncode == 0
        ref = f"origin/{p['ref'] or p['branch']}" if (p["ref"] or p["branch_exists"]) else "origin/main"
        p["last"] = git("log", ref, "-1", "--format=%cs %s", "--", f"projects/{slug}") or "—"
        out.append(p)
    return out


if __name__ == "__main__":
    extra = sys.argv[sys.argv.index("--ref") + 1:sys.argv.index("--ref") + 2] if "--ref" in sys.argv else []
    items = collect(extra)
    if not items:
        print("Проектов пока нет. Создай: /new-project")
        raise SystemExit
    print(f"{'Имя':<20} {'Тип':<20} {'Этап':<22} {'Ветка':<16} {'В main':<7} Последний коммит")
    for p in items:
        b = p["branch"] + ("" if p["branch_exists"] else " (нет)")
        print(f"{p['name']:<20} {p['type']:<20} {p['stage']:<22} {b:<16} {'да' if p['in_main'] else 'нет':<7} {p['last'][:55]}")
