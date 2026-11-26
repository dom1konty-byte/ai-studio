#!/usr/bin/env python3
"""Уроки всех проектов: projects/*/docs/lessons.md из main и из веток проектов.
Директор читает это в начале нового проекта.
  python3 scripts/lessons.py"""
import subprocess, sys
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent


def git(*a):
    r = subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout if r.returncode == 0 else ""


git("fetch", "-q", "--prune", "origin")
refs = ["origin/main"] + [f"origin/{b.removeprefix('origin/')}" for b in
                          git("branch", "-r", "--format=%(refname:short)").split()
                          if b != "origin/main" and "/" not in b.removeprefix("origin/")
                          and b.removeprefix("origin/") not in ("HEAD", "ofis")]
found = {}
for ref in refs:
    for path in git("ls-tree", "-r", "--name-only", ref, "projects").splitlines():
        if path.endswith("/docs/lessons.md"):
            slug = path.split("/")[1]
            branch = ref.removeprefix("origin/")
            if slug in found and branch != slug:
                continue  # ветка проекта свежее main
            found[slug] = git("show", f"{ref}:{path}").strip()
if not found:
    print("Уроков пока нет.")
for slug, text in sorted(found.items()):
    print(f"===== {slug}\n{text}\n")
