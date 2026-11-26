#!/usr/bin/env python3
"""Хук после правки файла агентом (PostToolUse: Edit/Write/MultiEdit).
Только для файлов в projects/<slug>/:
  .dart → dart format + dart analyze
  .html → html-validate, .css → csstree-validator
Ошибки → код 2 и текст в stderr: Claude видит их и чинит сразу.
Нет dart / npx → проверка пропускается (не мешает работе)."""
import json, shutil, subprocess, sys
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")


def run(cmd, cwd):
    exe = shutil.which(cmd[0])
    if not exe:
        return None
    r = subprocess.run([exe, *cmd[1:]], cwd=cwd, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=180)
    noise = ("Woah!", "superuser privileges", "📎")
    out = "\n".join(l for l in (r.stdout + r.stderr).splitlines()
                    if not any(n in l for n in noise) and l.strip() not in ("/", ""))
    return r.returncode, out


try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
fp = (data.get("tool_input") or {}).get("file_path") or ""
if not fp:
    sys.exit(0)
root = Path(data.get("cwd") or ".").resolve()
path = Path(fp) if Path(fp).is_absolute() else root / fp
path = path.resolve()
parts = path.parts
if "projects" not in parts or not path.exists():
    sys.exit(0)
i = parts.index("projects")
if len(parts) < i + 3:
    sys.exit(0)
project = Path(*parts[: i + 2])
if any(p in ("build", ".dart_tool", "node_modules") for p in parts[i + 2:]):
    sys.exit(0)

problems = []
ext = path.suffix.lower()
if ext == ".dart":
    run(["dart", "format", str(path)], project)
    res = run(["dart", "analyze", "--fatal-infos", str(path)], project)
    if res and res[0] != 0:
        problems.append(f"dart analyze {path.name}:\n{res[1]}")
elif ext in (".html", ".htm"):
    res = run(["npx", "--yes", "html-validate@9", str(path)], project)
    if res and res[0] != 0:
        problems.append(f"html-validate {path.name}:\n{res[1]}")
elif ext == ".css":
    res = run(["npx", "--yes", "csstree-validator@4", str(path)], project)
    if res and res[0] != 0:
        problems.append(f"csstree-validator {path.name}:\n{res[1]}")

if problems:
    print("Проверка после правки нашла ошибки — исправь их сейчас:\n\n" + "\n\n".join(problems), file=sys.stderr)
    sys.exit(2)
