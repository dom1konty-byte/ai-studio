#!/usr/bin/env python3
"""Проверка студии: у агентов, навыков и команд корректный frontmatter, модели по правилам."""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
C = ROOT / ".claude"
errors, ok = [], 0


def front(p):
    t = p.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n", t, re.S)
    if not m:
        return None
    d = {}
    for line in m.group(1).splitlines():
        k, _, v = line.partition(":")
        if k and not k.startswith(" ") and v:
            d[k.strip()] = v.strip().strip('"')
    return d


names = set()
for p in sorted((C / "agents").rglob("*.md")):
    f = front(p)
    rel = p.relative_to(ROOT)
    if not f or not f.get("name") or not f.get("description"):
        errors.append(f"{rel}: нет name/description"); continue
    if f.get("model") not in {"haiku", "sonnet", "opus"}:
        errors.append(f"{rel}: model должен быть haiku/sonnet/opus")
    if f.get("model") == "opus" and f["name"] not in {"architect", "debugger"}:
        errors.append(f"{rel}: Opus только у architect и debugger")
    if f["name"] in names:
        errors.append(f"{rel}: повтор имени {f['name']}")
    names.add(f["name"]); ok += 1
agents = ok
for p in sorted((C / "skills").glob("*/SKILL.md")):
    f = front(p)
    if not f or f.get("name") != p.parent.name or not f.get("description"):
        errors.append(f"{p.relative_to(ROOT)}: name должен совпадать с папкой, нужен description")
    ok += 1
skills = ok - agents
for p in sorted((C / "commands").glob("*.md")):
    f = front(p)
    if not f or not f.get("description"):
        errors.append(f"{p.relative_to(ROOT)}: нет description")
    ok += 1
cmds = ok - agents - skills
# ссылки агентов на навыки и агентов
skill_names = {p.parent.name for p in (C / "skills").glob("*/SKILL.md")}
for p in (C / "agents").rglob("*.md"):
    txt = p.read_text(encoding="utf-8")
    refs = re.findall(r"навык[а-я]* `([a-z0-9-]+)`", txt)
    for line in re.findall(r"^- Навыки: (.*)$", txt, re.M):
        refs += re.findall(r"`([a-z0-9-]+)`", line)
    for s in refs:
        if s not in skill_names:
            errors.append(f"{p.relative_to(ROOT)}: ссылка на несуществующий навык {s}")
print(f"Агентов: {agents}, навыков: {skills}, команд: {cmds}")
if errors:
    print("ОШИБКИ:\n- " + "\n- ".join(errors)); sys.exit(1)
print("OK: всё загружается корректно")
