#!/usr/bin/env python3
"""ai-studio: проверка store/listing.md по лимитам Google Play (офлайн).
Формат listing.md: разделы '## Название', '## Краткое описание', '## Полное описание'.
  python3 -I check_listing.py projects/<slug>/store/listing.md"""
import re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from metadata_optimizer import MetadataOptimizer  # noqa: E402

FIELDS = {"название": "title", "краткое описание": "short_description", "полное описание": "full_description"}
text = Path(sys.argv[1]).read_text(encoding="utf-8")
meta = {}
for head, body in re.findall(r"^##\s+(.+?)\s*\n(.*?)(?=^##\s|\Z)", text, re.S | re.M):
    key = FIELDS.get(head.strip().lower())
    if key:
        meta[key] = body.strip()
missing = [k for k, v in FIELDS.items() if v not in meta]
if missing:
    sys.exit("Нет разделов: " + ", ".join(missing))
r = MetadataOptimizer("google").validate_character_limits(meta)
for k, s in r["field_status"].items():
    print(f"{'OK ' if s['is_valid'] else 'ПЕРЕБОР'} {k}: {s['length']}/{s['limit']}")
for e in r["errors"]:
    print("Ошибка:", e)
sys.exit(0 if r["is_valid"] else 1)
