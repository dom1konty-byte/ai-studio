"""Иконка AI Studio через Pillow: assets/icon/app_icon.png (1024) и app_icon.ico.
Знак: большая янтарная «искра» (4-лучевая звезда) и малая бумажная искра на бирюзовом квадрате.
Запуск из папки проекта: python tool/make_icon.py  (нужен: pip install pillow)
Фигуры те же, что в assets/icon/app_icon.svg (сетка 256)."""
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"
TEAL, AMBER, PAPER = "#0F5C63", "#F2B33D", "#F6F1E7"
SS = 4  # суперсэмплинг для гладких краёв


def sparkle(cx, cy, r, k=0.22, n=24):
    """4-лучевая звезда с вогнутыми сторонами: точки по кривой Безье между лучами."""
    pts = []
    tips = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    for i in range(4):
        a, b = tips[i], tips[(i + 1) % 4]
        c = (cx + (a[0] + b[0] - 2 * cx) * k, cy + (a[1] + b[1] - 2 * cy) * k)
        for j in range(n):
            t = j / n
            x = (1 - t) ** 2 * a[0] + 2 * (1 - t) * t * c[0] + t * t * b[0]
            y = (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * c[1] + t * t * b[1]
            pts.append((x, y))
    return pts


def draw(size: int) -> Image.Image:
    s = size * SS / 256.0
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, size * SS - 1, size * SS - 1], radius=56 * s, fill=TEAL)
    d.polygon([(x * s, y * s) for x, y in sparkle(112, 140, 84)], fill=AMBER)
    d.polygon([(x * s, y * s) for x, y in sparkle(192, 64, 34)], fill=PAPER)
    return img.resize((size, size), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    draw(1024).save(OUT / "app_icon.png")
    sizes = [16, 24, 32, 48, 64, 128, 256]
    frames = [draw(n) for n in sizes]
    frames[-1].save(OUT / "app_icon.ico", format="ICO", sizes=[(n, n) for n in sizes], append_images=frames[:-1])
    print("OK:", OUT)


if __name__ == "__main__":
    main()
