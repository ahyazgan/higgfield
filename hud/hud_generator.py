#!/usr/bin/env python3
"""hud_generator.py — Reels 9:16 (1080x1920) için şeffaf GTA-tarzı HUD overlay üretir.

Sadece Pillow gerektirir, başka bağımlılık yok. Sistem fontu yoksa
ImageFont.load_default() ile devam eder (çökmez).

Kullanım:
  python3 hud/hud_generator.py --mission "Mission 01 — Keşif" --character "JAY" \
      --money "$2,450" --output hud/overlay.png
"""
import argparse
import os

try:
    from PIL import Image, ImageDraw, ImageFont
except Exception:  # pragma: no cover
    raise SystemExit("Pillow gerekli: pip install pillow")

W, H = 1080, 1920

GREEN   = (46, 204, 64, 255)
WHITE   = (255, 255, 255, 255)
BLUE    = (52, 152, 219, 255)
YELLOW  = (244, 206, 20, 255)    # #F4CE14
BLACK80 = (0, 0, 0, 204)         # %80 opak
WHITE20 = (255, 255, 255, 51)    # %20 opak


def load_font(size, bold=True):
    """Sistem fontunu dene; bulunamazsa load_default() (çökme)."""
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold
        else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/seguisb.ttf",
        "C:/Windows/Fonts/segoeui.ttf",
    ]
    for p in candidates:
        try:
            if os.path.exists(p):
                return ImageFont.truetype(p, size)
        except Exception:
            pass
    try:
        return ImageFont.load_default()
    except Exception:
        return ImageFont.load_default()


def _text_w(d, s, font):
    try:
        return d.textlength(s, font=font)
    except Exception:
        try:
            return font.getbbox(s)[2]
        except Exception:
            return len(s) * (getattr(font, "size", 16) * 0.6)


def draw_text(d, xy, s, font, fill, anchor=None):
    """anchor destekli/destek­siz Pillow için güvenli metin çizimi."""
    if anchor:
        try:
            d.text(xy, s, font=font, fill=fill, anchor=anchor)
            return
        except TypeError:
            pass
        x, y = xy
        w = _text_w(d, s, font)
        if anchor in ("mm", "ma", "mt"):
            x -= w / 2
        elif anchor in ("ra", "rt", "rm"):
            x -= w
        if anchor in ("mm", "rm"):
            y -= getattr(font, "size", 16) / 2
        d.text((x, y), s, font=font, fill=fill)
    else:
        d.text(xy, s, font=font, fill=fill)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mission", default="Mission")
    ap.add_argument("--character", default="JAY")
    ap.add_argument("--money", default="$0")
    ap.add_argument("--output", default="hud/overlay.png")
    a = ap.parse_args()

    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f28, f24, f36, f32 = load_font(28), load_font(24), load_font(36), load_font(32)

    # --- Minimap: sol alt (x:40, y:1700), 120px çaplı daire ---
    mx, my, dia = 40, 1700, 120
    cx, cy = mx + dia // 2, my + dia // 2
    d.ellipse([mx, my, mx + dia, my + dia], fill=BLACK80)
    step = dia // 4
    for gx in range(mx, mx + dia + 1, step):           # dikey grid çizgileri %20 opak
        d.line([gx, my, gx, my + dia], fill=WHITE20, width=1)
    for gy in range(my, my + dia + 1, step):           # yatay grid çizgileri %20 opak
        d.line([mx, gy, mx + dia, gy], fill=WHITE20, width=1)
    r = 8                                              # yeşil nokta (karakter) ortada
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GREEN)

    # --- Minimap üstü: "● JAY" (x:40, y:1660) — yeşil nokta + beyaz bold ---
    draw_text(d, (40, 1660), "● " + a.character, f28, WHITE)
    draw_text(d, (40, 1660), "●", f28, GREEN)     # noktayı yeşile boya

    # --- Can barı: sağ alt (x:860, y:1820) — yeşil ---
    draw_text(d, (860, 1820), "♥ [████████] 100", f24, GREEN)
    # --- Zırh barı: sağ alt (x:860, y:1850) — mavi ---
    draw_text(d, (860, 1850), "\U0001F6E1 [████████] 100", f24, BLUE)

    # --- Mission ismi: üst orta (x:540, y:80), ortalı, beyaz bold ---
    draw_text(d, (540, 80), a.mission, f36, WHITE, anchor="mm")

    # --- Para: sağ üst (x:1020, y:60), sağa yaslı, sarı bold ---
    draw_text(d, (1020, 60), a.money, f32, YELLOW, anchor="ra")

    out_dir = os.path.dirname(a.output)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    img.save(a.output)
    print(f"HUD overlay yazildi: {a.output} ({W}x{H})")


if __name__ == "__main__":
    main()
