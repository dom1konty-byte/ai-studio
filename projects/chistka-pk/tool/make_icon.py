"""Генерация assets/icon/app_icon.ico (16/32/48/256). Запуск: python3 tool/make_icon.py"""
import os
from PIL import Image, ImageDraw

S = 1024  # рисуем крупно, потом уменьшаем


def draw_master() -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.22), fill="#F4FAFA")
    teal = "#0F9D9A"
    cx = S // 2
    # капля: круг снизу + треугольник сверху
    r = int(S * 0.30)
    cy = int(S * 0.60)
    top = int(S * 0.10)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=teal)
    d.polygon([(cx, top), (cx - int(r * 0.93), cy - int(r * 0.35)),
               (cx + int(r * 0.93), cy - int(r * 0.35))], fill=teal)
    # белый диск
    dr = int(S * 0.19)
    d.ellipse((cx - dr, cy - dr, cx + dr, cy + dr), fill="white")
    hole = int(S * 0.035)
    # галочка бирюзовая
    w = int(S * 0.038)
    pts = [(cx - dr * 0.50, cy + dr * 0.02), (cx - dr * 0.12, cy + dr * 0.42), (cx + dr * 0.55, cy - dr * 0.36)]
    d.line(pts, fill=teal, width=w, joint="curve")
    for x, y in (pts[0], pts[2]):
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=teal)
    del hole
    return img


def main() -> None:
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "icon")
    os.makedirs(out, exist_ok=True)
    master = draw_master()
    sizes = [(16, 16), (32, 32), (48, 48), (256, 256)]
    master.save(os.path.join(out, "app_icon.ico"), format="ICO", sizes=sizes)
    master.resize((256, 256), Image.LANCZOS).save(os.path.join(out, "app_icon.png"))
    print("готово")


if __name__ == "__main__":
    main()
