#!/usr/bin/env python3
"""Удалить проект целиком — ТОЛЬКО после явного «да» Дамира (навык delete-project).
В ветке проекта убирает папку, workflow и строку в projects/README.md, коммит с меткой [delete-project], push.
Дальше GitHub (studio-cleanup.yml) сам удаляет ветку:
  - проекта нет в main → сразу после этого push;
  - проект есть в main → после слияния PR с удалением (python3 scripts/merge_pr.py после «да»).
  python3 scripts/delete_project.py <slug>"""
import subprocess, sys
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent


def git(*a, check=True):
    r = subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if check and r.returncode:
        sys.exit(f"Ошибка git {' '.join(a)}: {r.stderr.strip()}")
    return r.stdout.strip()


if len(sys.argv) != 2:
    sys.exit(__doc__)
slug = sys.argv[1].strip().strip("/")
if slug in ("main", "ai-office") or "/" in slug or not slug:
    sys.exit("Ошибка: это не проект.")
if git("status", "--porcelain"):
    sys.exit("Ошибка: есть незакоммиченные изменения.")
git("fetch", "-q", "--prune", "origin")
if not git("ls-remote", "origin", f"refs/heads/{slug}"):
    sys.exit(f"Ветки {slug} нет на GitHub — проект уже удалён или имя неверное (python3 scripts/status.py).")
in_main = subprocess.run(["git", "cat-file", "-e", f"origin/main:projects/{slug}"], cwd=ROOT, capture_output=True).returncode == 0

git("checkout", "-q", "-B", slug, f"origin/{slug}")
# свежий офис в ветке (в нём workflow studio-cleanup, который удалит ветку)
if subprocess.run(["git", "merge", "-q", "--no-edit", "origin/main"], cwd=ROOT, capture_output=True).returncode:
    git("merge", "--abort", check=False)
    sys.exit("Ошибка: не удалось влить свежий main в ветку проекта (конфликт). Разобраться вручную.")
paths = [p for p in (f"projects/{slug}", f".github/workflows/{slug}.yml") if (ROOT / p).exists()]
if paths:
    git("rm", "-rq", *paths)
readme = ROOT / "projects" / "README.md"
lines = readme.read_text(encoding="utf-8").splitlines(keepends=True)
kept = [l for l in lines if f"[`{slug}`]" not in l]
if kept != lines:
    readme.write_text("".join(kept), encoding="utf-8")
    git("add", "projects/README.md")
git("commit", "-q", "-m", f"{slug}: удалить проект [delete-project]")
git("push", "-q", "origin", slug)
print(f"Проект {slug} удалён в своей ветке.")
if in_main:
    print("Он есть в main → нужен PR с удалением: python3 scripts/merge_pr.py "
          f"--title \"{slug}: удалить проект\" (после «да» Дамира). После слияния GitHub сам удалит ветку.")
else:
    print("В main его не было → GitHub удалит ветку сам в течение минуты (studio-cleanup).")
