#!/usr/bin/env python3
"""/econ — токены текущей сессии Claude Code (по журналу ~/.claude/projects/*.jsonl).
Идея: caveman-stats (JuliusBrussee/caveman, Apache-2.0). Считает только записанное; «экономию» не выдумывает."""
import json, re, subprocess, sys
from collections import defaultdict
from pathlib import Path
for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")  # Windows-консоль: кириллица

base = Path.home() / ".claude" / "projects"
top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.strip() or str(Path.cwd())
enc = re.sub(r"[^A-Za-z0-9]", "-", top)
cands = sorted((base / enc).glob("*.jsonl"), key=lambda p: p.stat().st_mtime) if (base / enc).exists() else []
if not cands:
    cands = sorted(base.glob("*/*.jsonl"), key=lambda p: p.stat().st_mtime) if base.exists() else []
if not cands:
    sys.exit("Журнал сессии не найден. В Claude Code используй встроенную /cost или /context.")
files = cands if "--all" in sys.argv else cands[-1:]

seen, tot, by_model = set(), defaultdict(int), defaultdict(lambda: defaultdict(int))
replies = 0
for f in files:
    for line in f.open(encoding="utf-8", errors="ignore"):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        m = e.get("message") or {}
        u = m.get("usage") if isinstance(m, dict) else None
        if not u:
            continue
        key = m.get("id") or e.get("uuid")
        if key in seen:
            continue
        seen.add(key)
        replies += 1
        for k in ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"):
            v = u.get(k) or 0
            tot[k] += v
            by_model[m.get("model", "?")][k] += v

L = {"input_tokens": "Вход (новый)", "output_tokens": "Выход (ответы)",
     "cache_creation_input_tokens": "Запись в кэш", "cache_read_input_tokens": "Чтение из кэша"}
print(f"Сессий: {len(files)} | ответов модели: {replies}")
for k, n in L.items():
    print(f"{n:<16} {tot[k]:>12,}".replace(",", " "))
print(f"{'Всего':<16} {sum(tot.values()):>12,}".replace(",", " "))
if len(by_model) > 1:
    print("По моделям (выход):")
    for mod, d in sorted(by_model.items(), key=lambda x: -x[1]["output_tokens"]):
        print(f"  {mod:<28} {d['output_tokens']:>10,}".replace(",", " "))
print("Чтение из кэша дешевле ~10×. Точная цена — встроенная /cost.")
