#!/usr/bin/env python3
"""Табло студии: таблица проектов + ссылка на последний APK → тело Issue «Табло студии».
  python3 scripts/dashboard.py              # напечатать markdown
  python3 scripts/dashboard.py --publish    # обновить/создать Issue (нужен gh с правом issues:write)
  [--ref <ветка>]                           # добавить ветку (для проверки)"""
import datetime, json, re, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from status import collect, git  # noqa: E402

for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")

TITLE = "Табло студии"
LABEL = "tablo"


def gh(*a, input=None):
    r = subprocess.run(["gh", *a], capture_output=True, text=True, encoding="utf-8", errors="replace", input=input)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def api(path, *a):
    code, out, err = gh("api", path, *a)
    return json.loads(out) if code == 0 and out else None


m = re.search(r"github\.com[/:]([^/]+)/([^/.]+?)(?:\.git)?$", git("remote", "get-url", "origin"))
repo = f"{m.group(1)}/{m.group(2)}"


def last_apk(slug):
    runs = api(f"repos/{repo}/actions/workflows/{slug}.yml/runs?status=success&per_page=15")
    for r in (runs or {}).get("workflow_runs", []):
        arts = api(f"repos/{repo}/actions/runs/{r['id']}/artifacts") or {}
        for a in arts.get("artifacts", []):
            if a["name"].endswith(("-apk", "-site", "-windows")) and not a["expired"]:
                when = (datetime.datetime.fromisoformat(r["updated_at"].replace("Z", "+00:00"))
                        + datetime.timedelta(hours=3)).strftime("%d.%m %H:%M")
                return f"[{a['name']}]({r['html_url']}#artifacts) · {r['head_branch']} · {when}"
    return "—"


extra = sys.argv[sys.argv.index("--ref") + 1:sys.argv.index("--ref") + 2] if "--ref" in sys.argv else []
items = collect(extra)
now = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=3)
lines = [f"_Обновлено автоматически: {now:%d.%m.%Y %H:%M} (МСК). Не редактировать вручную._", ""]
if not items:
    lines.append("Проектов пока нет. Создай: `/new-project`")
else:
    waiting = [p["name"] for p in items if "✅" in p["stage"] or "одобр" in p["stage"].lower()]
    if waiting:
        lines += [f"**Ждут твоего «да»:** {', '.join(waiting)}", ""]
    lines += ["| Проект | Тип | Этап | Ветка | В main | Последняя сборка |", "|---|---|---|---|---|---|"]
    for p in items:
        branch = f"[`{p['branch']}`](https://github.com/{repo}/tree/{p['branch']})" if p["branch_exists"] else f"`{p['branch']}` (нет)"
        lines.append(f"| **{p['name']}** | {p['type']} | {p['stage']} | {branch} | {'✔' if p['in_main'] else '—'} | {last_apk(p['slug'])} |")
    lines += ["", "APK: открой ссылку → внизу страницы **Artifacts** → скачать zip → внутри `app-release.apk`."]
body = "\n".join(lines) + "\n"

if "--publish" not in sys.argv:
    print(body)
    sys.exit()

issues = api(f"repos/{repo}/issues?state=all&labels={LABEL}&per_page=5") or []
if issues:
    num = issues[0]["number"]
    code, _, err = gh("api", "-X", "PATCH", f"repos/{repo}/issues/{num}", "-f", f"body={body}", "-f", "state=open")
else:
    gh("api", "-X", "POST", f"repos/{repo}/labels", "-f", f"name={LABEL}", "-f", "color=5319e7",
       "-f", "description=Табло студии (обновляется автоматически)")
    code, out, err = gh("api", "-X", "POST", f"repos/{repo}/issues", "-f", f"title={TITLE}", "-f", f"body={body}",
                        "-f", f"labels[]={LABEL}")
    num = json.loads(out)["number"] if code == 0 else None
    if num:  # закрепить (best effort)
        node = (api(f"repos/{repo}/issues/{num}") or {}).get("node_id")
        if node:
            gh("api", "graphql", "-f", f'query=mutation{{pinIssue(input:{{issueId:"{node}"}}){{issue{{number}}}}}}')
if code != 0:
    sys.exit(f"Не удалось обновить Issue: {err}")
print(f"Табло обновлено: https://github.com/{repo}/issues/{num}")
