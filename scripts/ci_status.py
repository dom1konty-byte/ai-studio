#!/usr/bin/env python3
"""Результат проверок GitHub Actions для ветки: ждёт окончания, печатает итог, ссылки и артефакты (APK).
  python3 scripts/ci_status.py                    # текущая ветка, ждать до 25 мин
  python3 scripts/ci_status.py --branch <slug> --no-wait
Код выхода: 0 — всё зелёное, 1 — упало, 2 — нет проверок/не дождались, 3 — нет gh."""
import argparse, json, re, shutil, subprocess, sys, time
for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")  # Windows-консоль: кириллица


def sh(*a):
    r = subprocess.run(a, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def api(path):
    code, out, err = sh("gh", "api", path)
    if code:
        sys.exit(f"Ошибка gh api {path}: {err}")
    return json.loads(out)


p = argparse.ArgumentParser()
p.add_argument("--branch")
p.add_argument("--no-wait", action="store_true")
p.add_argument("--timeout", type=int, default=1500)
a = p.parse_args()

_, url, _ = sh("git", "remote", "get-url", "origin")
m = re.search(r"github\.com[/:]([^/]+)/([^/.]+?)(?:\.git)?$", url)
if not m:
    sys.exit("Ошибка: не понял owner/repo из git remote.")
repo = f"{m.group(1)}/{m.group(2)}"
branch = a.branch or sh("git", "branch", "--show-current")[1]
actions = f"https://github.com/{repo}/actions?query=branch%3A{branch.replace('/', '%2F')}"

if not shutil.which("gh"):
    print(f"gh (GitHub CLI) не установлен — проверь сам: {actions}")
    sys.exit(3)

code, out, _ = sh("git", "ls-remote", "origin", f"refs/heads/{branch}")
if not out:
    print(f"Ветки {branch} нет на GitHub — сначала git push -u origin {branch}")
    sys.exit(2)
sha = out.split()[0]
_, local, _ = sh("git", "rev-parse", "HEAD")
if not a.branch and local and local != sha:
    print(f"Внимание: локальный коммит {local[:7]} не отправлен, на GitHub — {sha[:7]}. Сделай git push.")

deadline = time.time() + a.timeout
while True:
    runs = api(f"repos/{repo}/actions/runs?head_sha={sha}&per_page=50")["workflow_runs"]
    pending = [r for r in runs if r["status"] != "completed"]
    if runs and not pending:
        break
    if a.no_wait or time.time() > deadline:
        if not runs:
            print(f"Проверок для {sha[:7]} нет (папка проекта не менялась или они ещё не стартовали). {actions}")
        else:
            print("Ещё идут: " + ", ".join(r["name"] for r in pending) + f" — {actions}")
        sys.exit(2)
    if not runs and time.time() > deadline - a.timeout + 120:
        print(f"За 2 минуты проверки не стартовали для {sha[:7]}. {actions}")
        sys.exit(2)
    time.sleep(20)

ok = True
print(f"Ветка {branch}, коммит {sha[:7]}:")
for r in runs:
    good = r["conclusion"] in ("success", "skipped", "neutral")
    ok &= good
    print(f"  {'OK ' if good else 'УПАЛО'} {r['name']}: {r['conclusion']} — {r['html_url']}")
    if not good:
        jobs = api(f"repos/{repo}/actions/runs/{r['id']}/jobs")["jobs"]
        for j in jobs:
            for s in j.get("steps", []):
                if s["conclusion"] == "failure":
                    print(f"     шаг: {s['name']}")
        print(f"     лог: gh run view {r['id']} --log-failed  (или по ссылке)")
    for art in api(f"repos/{repo}/actions/runs/{r['id']}/artifacts")["artifacts"]:
        print(f"     файл: {art['name']} — {r['html_url']}#artifacts")
sys.exit(0 if ok else 1)
