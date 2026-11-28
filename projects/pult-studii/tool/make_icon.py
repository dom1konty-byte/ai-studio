"""Рисует иконку Рубки (штурвал) через Pillow: assets/icon/app_icon.png (1024) и app_icon.ico.
Запуск из папки проекта: python tool/make_icon.py  (нужен: pip install pillow)
Фигуры те же, что в assets/icon/app_icon.svg (сетка 256)."""
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"
TEAL, AMBER, PAPER = "#0F5C63", "#F2B33D", "#F6F1E7"
SS = 4  # суперсэмплинг для гладких краёв


def draw(size: int) -> Image.Image:
    s = size * SS / 256.0
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def p(v):
        return v * s

    d.rounded_rectangle([0, 0, size * SS - 1, size * SS - 1], radius=p(56), fill=TEAL)
    import math
    # 8 спиц с ручками на концах (штурвал)
    for k in range(8):
        a = math.pi / 4 * k
        cx, cy = 128 + 98 * math.cos(a), 128 + 98 * math.sin(a)
        d.line([p(128), p(128), p(cx), p(cy)], fill=AMBER, width=int(p(14)))
        d.ellipse([p(cx - 14), p(cy - 14), p(cx + 14), p(cy + 14)], fill=AMBER)
    # кольцо
    d.ellipse([p(128 - 72), p(128 - 72), p(128 + 72), p(128 + 72)], fill=AMBER)
    d.ellipse([p(128 - 52), p(128 - 52), p(128 + 52), p(128 + 52)], fill=TEAL)
    for k in range(8):
        a = math.pi / 4 * k
        x2, y2 = 128 + 56 * math.cos(a), 128 + 56 * math.sin(a)
        d.line([p(128), p(128), p(x2), p(y2)], fill=AMBER, width=int(p(14)))
    # втулка
    d.ellipse([p(104), p(104), p(152), p(152)], fill=PAPER)
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
