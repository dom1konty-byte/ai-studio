#!/usr/bin/env python3
"""Создаёт проект студии: папку из шаблона, workflow, строку в projects/README.md, ветку."""
import argparse, datetime, re, shutil, subprocess, sys
from pathlib import Path
for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")  # Windows-консоль: кириллица

ROOT = Path(__file__).resolve().parent.parent
TYPES = {
    "app": ("flutter-app", "Android-приложение", "flutter-android.yml"),
    "site": ("web-landing", "Сайт", "web.yml"),
    "windows": ("windows-app", "Программа Windows", "flutter-windows.yml"),
    "bot": ("telegram-bot", "Telegram-бот", "bot.yml"),
}
TR = {"а":"a","б":"b","в":"v","г":"g","д":"d","е":"e","ё":"e","ж":"zh","з":"z","и":"i","й":"y",
      "к":"k","л":"l","м":"m","н":"n","о":"o","п":"p","р":"r","с":"s","т":"t","у":"u","ф":"f",
      "х":"kh","ц":"ts","ч":"ch","ш":"sh","щ":"shch","ъ":"","ы":"y","ь":"","э":"e","ю":"yu","я":"ya"}
TEXT_EXT = {".md", ".yaml", ".yml", ".dart", ".html", ".css", ".js", ".json", ".txt", ".xml",
            ".ts", ".toml", ".ps1", ".cmd"}


def slugify(name: str) -> str:
    low = name.lower()
    # й в конце слова → y («мой» → moy), внутри → i («сайт» → sait)
    s = "".join("y" if c == "й" and not low[i + 1:i + 2].isalpha() else "i" if c == "й"
                else TR.get(c, c) for i, c in enumerate(low))
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s


def run(*cmd):
    subprocess.run(cmd, cwd=ROOT, check=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("name", help="Имя проекта, как хочет владелец")
    p.add_argument("type", choices=TYPES)
    p.add_argument("--about", default="", help="О чём проект, 1 строка")
    p.add_argument("--no-branch", action="store_true", help="Без ветки и коммита")
    a = p.parse_args()

    slug = slugify(a.name)
    if not slug:
        sys.exit("Ошибка: из имени не получился slug. Используй буквы или цифры.")
    package = re.sub(r"^(\d)", r"app_\1", slug.replace("-", "_"))
    tpl, type_ru, wf = TYPES[a.type]
    dest = ROOT / "projects" / slug
    if dest.exists():
        sys.exit(f"Ошибка: папка projects/{slug} уже существует. Выбери другое имя.")
    branch = slug
    today = datetime.date.today().isoformat()

    if not a.no_branch:
        run("git", "fetch", "-q", "origin", "main")
        run("git", "checkout", "--no-track", "-b", branch, "origin/main")

    shutil.copytree(ROOT / "templates" / tpl, dest)
    subs = {"{{NAME}}": a.name, "{{SLUG}}": slug, "{{PACKAGE}}": package,
            "{{TYPE}}": type_ru, "{{ABOUT}}": a.about or "—", "{{DATE}}": today,
            "{{SECRET}}": slug.upper().replace("-", "_")}
    files = [f for f in dest.rglob("*") if f.is_file()]
    wf_src = ROOT / "templates" / "workflows" / wf
    wf_dst = ROOT / ".github" / "workflows" / f"{slug}.yml"
    wf_dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(wf_src, wf_dst)
    for f in files + [wf_dst]:
        if f.suffix in TEXT_EXT:
            t = f.read_bytes().decode("utf-8")  # байты: сохраняем BOM и CRLF (.ps1/.cmd для Windows)
            for k, v in subs.items():
                t = t.replace(k, v)
            f.write_bytes(t.encode("utf-8"))

    readme = ROOT / "projects" / "README.md"
    row = f"| {a.name} | [`{slug}`]({slug}/) | {type_ru} | Бриф | `{branch}` | {today} |\n"
    t = readme.read_text(encoding="utf-8")
    if not t.endswith("\n"):
        t += "\n"
    readme.write_text(t + row, encoding="utf-8")

    if not a.no_branch:
        run("git", "add", f"projects/{slug}", "projects/README.md", str(wf_dst.relative_to(ROOT)))
        run("git", "commit", "-q", "-m", f"{slug}: создан проект «{a.name}» ({type_ru})")

    print(f"Готово: projects/{slug}/ ({type_ru})")
    print(f"Ветка: {branch if not a.no_branch else '— (без ветки)'}")
    print(f"Сборка: .github/workflows/{slug}.yml")
    print("\nСтартовый текст для новой сессии:")
    print(f"Проект: {a.name} ({slug}). Ветка: {slug}. Тип: {type_ru}.\n"
          f"Начни с этапа Бриф: задай мне 1–2 вопроса. О проекте: {a.about or '—'}")


if __name__ == "__main__":
    main()
