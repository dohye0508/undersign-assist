"""웹 아이콘(favicon, PWA)을 만든다. 로고 그림은 app/lib/widgets/app_logo.dart 와 같다 (64 x 64 안의 도형).

사용법: python scripts/make_icons.py
만드는 것: app/web/favicon.png, app/web/icons/Icon-192.png, Icon-512.png, Icon-maskable-192.png, Icon-maskable-512.png
- 일반 아이콘은 검은 둥근 바탕(모서리는 투명), maskable은 가장자리까지 검은 바탕 + 그림을 안쪽 60%로 줄인다
  (안드로이드가 원·둥근 사각형으로 잘라도 그림이 잘리지 않는 안전 영역)
- 지우개 없이 8배로 그린 뒤 줄여서 가장자리를 부드럽게 한다
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1] / "app" / "web"
INK = (0, 0, 0, 255)
WHITE = (255, 255, 255, 255)
SS = 8  # 확대해서 그린 뒤 줄이는 배율


def glyph(draw: ImageDraw.ImageDraw, ox: float, oy: float, u: float) -> None:
    """헤드폰 + 문서 + 줄 셋. (ox, oy)는 64 x 64 칸의 왼쪽 위, u는 한 칸의 픽셀 수"""

    def p(x: float, y: float) -> tuple[float, float]:
        return ox + x * u, oy + y * u

    band_w = 4.6 * u
    # 머리띠: 반원(중심 32,32 반지름 20)과 양쪽 세로 선. 선 굵기는 안쪽으로 그려지므로 바깥 반지름을 쓴다
    r_out = 20 + 4.6 / 2
    draw.arc([*p(32 - r_out, 32 - r_out), *p(32 + r_out, 32 + r_out)], 180, 360, fill=WHITE, width=round(band_w))
    for x in (12, 52):
        draw.line([p(x, 32), p(x, 38)], fill=WHITE, width=round(band_w))
        cx, cy = p(x, 38)
        draw.ellipse([cx - band_w / 2, cy - band_w / 2, cx + band_w / 2, cy + band_w / 2], fill=WHITE)
    # 귀덮개
    for x in (7, 47):
        draw.rounded_rectangle([*p(x, 35), *p(x + 10, 52)], radius=5 * u, fill=WHITE)
    # 문서와 줄
    draw.rounded_rectangle([*p(22, 28), *p(42, 54)], radius=3.5 * u, fill=WHITE)
    for y, w in ((35, 12), (41, 12), (47, 7)):
        draw.rounded_rectangle([*p(26, y), *p(26 + w, y + 2.8)], radius=1.4 * u, fill=INK)


def render(size: int, maskable: bool) -> Image.Image:
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if maskable:
        d.rectangle([0, 0, big, big], fill=INK)
        scale = 0.6
    else:
        d.rounded_rectangle([0, 0, big - 1, big - 1], radius=big * 14 / 64, fill=INK)
        scale = 1.0
    u = big * scale / 64
    off = (big - big * scale) / 2
    glyph(d, off, off, u)
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    (ROOT / "icons").mkdir(parents=True, exist_ok=True)
    for size in (192, 512):
        render(size, False).save(ROOT / "icons" / f"Icon-{size}.png")
        render(size, True).save(ROOT / "icons" / f"Icon-maskable-{size}.png")
    render(64, False).save(ROOT / "favicon.png")
    print("ok")


if __name__ == "__main__":
    main()
