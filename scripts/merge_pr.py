#!/usr/bin/env python3
"""Слияние ветки в main через PR — ТОЛЬКО после «да» Дамира (навык merge-to-main).
Находит/создаёт PR текущей ветки, ждёт проверки GitHub Actions, сливает merge-коммитом (ветка проекта остаётся).
  python3 scripts/merge_pr.py --title "..." [--dry-run]"""
import argparse, json, re, subprocess, sys, time
for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")  # Windows-консоль: кириллица


def sh(*a, check=True):
    r = subprocess.run(a, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if check and r.returncode:
        sys.exit(f"Ошибка: {' '.join(a[:4])}…\n{r.stderr.strip() or r.stdout.strip()}")
    return r.stdout.strip()


def api(path, *args):
    out = sh("gh", "api", path, *args)
    return json.loads(out) if out else {}


p = argparse.ArgumentParser()
p.add_argument("--title", default="")
p.add_argument("--body", default="")
p.add_argument("--dry-run", action="store_true", help="только проверить, не сливать")
p.add_argument("--timeout", type=int, default=1500, help="ждать проверки, секунд")
a = p.parse_args()

m = re.search(r"github\.com[/:]([^/]+)/([^/.]+?)(?:\.git)?$", sh("git", "remote", "get-url", "origin"))
if not m:
    sys.exit("Ошибка: не понял owner/repo из git remote.")
repo = f"{m.group(1)}/{m.group(2)}"
branch = sh("git", "branch", "--show-current")
if branch in ("main", ""):
    sys.exit("Ошибка: нужна рабочая ветка, не main.")
if not a.dry_run:
    if sh("git", "status", "--porcelain"):
        sys.exit("Ошибка: есть незакоммиченные изменения. Сначала коммит.")
    sh("git", "push", "-q", "-u", "origin", branch)

prs = api(f"repos/{repo}/pulls?head={m.group(1)}:{branch}&state=open")
if prs:
    pr = prs[0]
else:
    if a.dry_run:
        sys.exit(f"PR для {branch} нет (dry-run: не создаю).")
    pr = api(f"repos/{repo}/pulls", "-f", f"title={a.title or branch}", "-f", f"head={branch}",
             "-f", "base=main", "-f", f"body={a.body or 'Слито после одобрения Дамира.'}")
num, sha = pr["number"], pr["head"]["sha"]
print(f"PR #{num}: {pr['html_url']}")

start = time.time()
deadline = start + a.timeout
while True:
    runs = api(f"repos/{repo}/commits/{sha}/check-runs?per_page=100").get("check_runs", [])
    pending = [r["name"] for r in runs if r["status"] != "completed"]
    failed = [r["name"] for r in runs if r["status"] == "completed"
              and r["conclusion"] not in ("success", "skipped", "neutral")]
    if failed:
        sys.exit(f"НЕ СЛИТО: проверки упали: {', '.join(failed)}. Чинить → снова одобрение не нужно, повторить скрипт.")
    if not runs and time.time() < start + 120:
        time.sleep(15)  # проверки стартуют не сразу после push
        continue
    if not pending:
        break
    if time.time() > deadline:
        sys.exit(f"НЕ СЛИТО: проверки идут слишком долго: {', '.join(pending)}")
    time.sleep(20)
print(f"Проверки: {len(runs)} зелёных" if runs else "Проверок нет")

if a.dry_run:
    print("dry-run: всё готово к слиянию, не сливаю.")
    sys.exit()
res = api(f"repos/{repo}/pulls/{num}/merge", "-X", "PUT", "-f", "merge_method=merge")
if not res.get("merged"):
    sys.exit(f"НЕ СЛИТО: {res.get('message')}")
print(f"СЛИТО в main: PR #{num} ({res.get('sha', '')[:7]})")
