#!/usr/bin/env python3
"""ai-studio store-screenshots: фон + подпись для скриншотов Google Play и feature graphic 1024×500.
  frame.py <raw_dir> <out_dir> [--captions file.txt] [--bg "#3F51B5"]
  frame.py --feature out.png --title "..." [--subtitle "..."] [--bg ...] [--icon icon.png]
Нужен Pillow (pip install pillow)."""
import argparse, glob, os, sys
from pathlib import Path
try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("Нужен Pillow: pip install pillow")

W, H = 1080, 1920


def font(size, bold=True):
    root = os.environ.get("FLUTTER_ROOT", "")
    cands = [f"{root}/bin/cache/artifacts/material_fonts/Roboto-{'Bold' if bold else 'Regular'}.ttf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "C:/Windows/Fonts/arialbd.ttf",
             "/System/Library/Fonts/Supplemental/Arial Bold.ttf"]
    cands += glob.glob(os.path.expanduser("~/**/material_fonts/Roboto-Bold.ttf"), recursive=True)[:1]
    for c in cands:
        if c and Path(c).exists():
            return ImageFont.truetype(c, size)
    return ImageFont.load_default(size)


def wrap(draw, text, f, maxw):
    lines, cur = [], ""
    for w in text.split():
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=f) <= maxw:
            cur = t
        else:
            lines.append(cur); cur = w
    return lines + [cur] if cur else lines


def centered(draw, lines, f, y, width, fill="white", gap=1.2):
    for ln in lines:
        draw.text(((width - draw.textlength(ln, font=f)) / 2, y), ln, font=f, fill=fill)
        y += int(f.size * gap)
    return y


def frame(raw, out, captions, bg):
    files = sorted(Path(raw).glob("*.png"))
    if not files:
        sys.exit(f"Нет PNG в {raw}")
    caps = Path(captions).read_text(encoding="utf-8").splitlines() if captions else []
    Path(out).mkdir(parents=True, exist_ok=True)
    for i, f in enumerate(files):
        shot = Image.open(f).convert("RGB")
        cap = caps[i].strip() if i < len(caps) else ""
        if not cap:
            shot.resize((W, H)).save(Path(out) / f.name); print("→", f.name); continue
        canvas = Image.new("RGB", (W, H), bg)
        d = ImageDraw.Draw(canvas)
        fnt = font(78)
        y = centered(d, wrap(d, cap, fnt, W - 140), fnt, 90, W)
        top = max(y + 50, 330)
        scale = (H - top - 60) / shot.height
        s = shot.resize((int(shot.width * scale), int(shot.height * scale)))
        x = (W - s.width) // 2
        mask = Image.new("L", s.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, *s.size), radius=40, fill=255)
        d.rounded_rectangle((x - 12, top - 12, x + s.width + 12, top + s.height + 12), radius=50, fill="#111111")
        canvas.paste(s, (x, top), mask)
        canvas.save(Path(out) / f.name); print("→", f.name, "|", cap)


def feature(out, title, subtitle, bg, icon):
    fw, fh = 1024, 500
    c = Image.new("RGB", (fw, fh), bg)
    d = ImageDraw.Draw(c)
    left = 70
    if icon and Path(icon).exists():
        ic = Image.open(icon).convert("RGBA").resize((260, 260))
        c.paste(ic, (fw - 260 - 80, (fh - 260) // 2), ic); maxw = fw - 260 - 80 - left - 40
    else:
        maxw = fw - 2 * left
    ft, fs = font(84), font(40, bold=False)
    lines = wrap(d, title, ft, maxw)
    sub = wrap(d, subtitle, fs, maxw) if subtitle else []
    hgt = len(lines) * int(84 * 1.15) + (20 + len(sub) * 52 if sub else 0)
    y = (fh - hgt) // 2
    for ln in lines:
        d.text((left, y), ln, font=ft, fill="white"); y += int(84 * 1.15)
    y += 20
    for ln in sub:
        d.text((left, y), ln, font=fs, fill="#E8EAF6"); y += 52
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    c.save(out); print("→", out, f"{fw}×{fh}")


p = argparse.ArgumentParser()
p.add_argument("raw", nargs="?"); p.add_argument("out", nargs="?")
p.add_argument("--captions"); p.add_argument("--bg", default="#3F51B5")
p.add_argument("--feature"); p.add_argument("--title", default=""); p.add_argument("--subtitle", default="")
p.add_argument("--icon")
a = p.parse_args()
if a.feature:
    feature(a.feature, a.title or "App", a.subtitle, a.bg, a.icon)
elif a.raw and a.out:
    frame(a.raw, a.out, a.captions, a.bg)
else:
    p.error("укажи raw_dir out_dir или --feature")
