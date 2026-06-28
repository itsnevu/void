#!/usr/bin/env python3
"""
MythReach wordmark generator — NON-fantasy, matched to the actual game.

Palette is pulled straight from the live UI theme (theme_horizon.tres /
gradient_button.tres) and the fonts are the ones already bundled with the
project (Kenney pixel + Atkinson Hyperlegible). No fantasy serif (Cinzel).

Outputs (in branding/out/):
  concept_a_horizon_{transparent,dark}.png   -> modern flat "Horizon" wordmark
  concept_b_pixel_{transparent,dark}.png      -> true pixel-art wordmark
  concept_c_emblem_{transparent,dark}.png     -> ascending-peak badge + wordmark
"""

import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(ROOT, "assets", "fonts")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)

F_SANS_BOLD = os.path.join(FONTS, "Atkinson_Hyperlegible", "AtkinsonHyperlegible-Bold.ttf")
F_SANS_REG  = os.path.join(FONTS, "Atkinson_Hyperlegible", "AtkinsonHyperlegible-Regular.ttf")
F_PIXEL     = os.path.join(FONTS, "kenney_mini_square.ttf")

# --- Game palette (from theme_horizon.tres + gradient_button.tres) ----------
NAVY      = (27, 29, 33)      # #1B1D21  panel bg
NAVY_DEEP = (10, 12, 17)      # #0A0C11  deepest bg
SKY       = (148, 209, 250)   # #94D1FA  primary accent (sky blue)
MIDBLUE   = (107, 153, 199)   # #6B99C7  secondary
TEAL      = (63, 107, 116)    # #3F6B74  border / metallic edge
TEAL_HI   = (96, 168, 178)    # brighter teal for highlight
GOLD      = (242, 184, 90)    # #F2B85A  premium warm accent (used sparingly)
WHITE     = (240, 248, 255)

TEXT = "MYTHREACH"


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vertical_gradient(size, top, bottom):
    w, h = size
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        grad.putpixel((0, y), lerp(top, bottom, y / max(1, h - 1)))
    return grad.resize((w, h))


def text_mask(text, font, tracking=0):
    """Render text to an L (alpha) image with optional letter tracking."""
    dummy = Image.new("L", (4, 4))
    d = ImageDraw.Draw(dummy)
    widths, heights = [], []
    for ch in text:
        bb = d.textbbox((0, 0), ch, font=font)
        widths.append(bb[2] - bb[0])
        heights.append(bb[3])
    asc, desc = font.getmetrics()
    th = asc + desc
    total_w = sum(widths) + tracking * (len(text) - 1)
    img = Image.new("L", (total_w + 8, th + 8), 0)
    d = ImageDraw.Draw(img)
    x = 4
    for ch, w in zip(text, widths):
        d.text((x, 4), ch, font=font, fill=255)
        x += w + tracking
    bb = img.getbbox()
    return img.crop(bb)


def fill_with_gradient(mask, top, bottom):
    grad = vertical_gradient(mask.size, top, bottom).convert("RGBA")
    grad.putalpha(mask)
    return grad


def add_glow(layer, color, radius, opacity=1.0):
    """Return an RGBA glow layer (same size) from a colored copy of layer's alpha."""
    alpha = layer.split()[3]
    glow = Image.new("RGBA", layer.size, color + (0,))
    a = alpha.filter(ImageFilter.GaussianBlur(radius))
    a = a.point(lambda p: int(p * opacity))
    glow.putalpha(a)
    return glow


def outline(mask, width):
    """Dilate an alpha mask by `width` px (max filter)."""
    k = width * 2 + 1
    return mask.filter(ImageFilter.MaxFilter(k if k % 2 else k + 1))


def save_pair(name, art, bg_color):
    """art is RGBA, already composed (glow+fill). Save transparent + dark bg."""
    art.save(os.path.join(OUT, f"{name}_transparent.png"))
    bg = Image.new("RGBA", art.size, bg_color + (255,))
    # subtle vignette so the wordmark reads on a flat dark card
    vg = Image.new("L", art.size, 0)
    dv = ImageDraw.Draw(vg)
    w, h = art.size
    dv.ellipse([-w * 0.2, -h * 0.4, w * 1.2, h * 1.4], fill=40)
    vg = vg.filter(ImageFilter.GaussianBlur(120))
    glowbg = Image.new("RGBA", art.size, lerp(bg_color, SKY, 0.15) + (0,))
    glowbg.putalpha(vg)
    bg = Image.alpha_composite(bg, glowbg)
    bg = Image.alpha_composite(bg, art)
    bg.save(os.path.join(OUT, f"{name}_dark.png"))
    print("  ->", name)


# ---------------------------------------------------------------------------
# CONCEPT A — "Horizon": modern flat wordmark + glowing horizon line
# ---------------------------------------------------------------------------
def concept_a():
    W, H = 1920, 760
    SS = 2  # supersample
    cw, ch = W * SS, H * SS
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))

    font = ImageFont.truetype(F_SANS_BOLD, 240 * SS)
    mask = text_mask(TEXT, font, tracking=14 * SS)
    # scale to fit width
    maxw = int(cw * 0.82)
    if mask.width > maxw:
        s = maxw / mask.width
        mask = mask.resize((int(mask.width * s), int(mask.height * s)))
    tx = (cw - mask.width) // 2
    ty = int(ch * 0.30) - mask.height // 2

    full = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    fill = fill_with_gradient(mask, SKY, MIDBLUE)
    full.paste(fill, (tx, ty), mask)

    # glow
    glow = add_glow(full, SKY, 26 * SS, 0.8)
    glow2 = add_glow(full, TEAL_HI, 60 * SS, 0.5)

    # horizon line through the lower third of the wordmark
    line = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    dl = ImageDraw.Draw(line)
    ly = ty + int(mask.height * 0.74)
    margin = int(cw * 0.12)
    # rising "sun"/peak disc behind center
    cxp = cw // 2
    r = int(mask.height * 0.42)
    sun = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    ds = ImageDraw.Draw(sun)
    ds.ellipse([cxp - r, ly - r, cxp + r, ly + r], fill=SKY + (70,))
    sun = sun.filter(ImageFilter.GaussianBlur(8 * SS))
    dl.line([(margin, ly), (cw - margin, ly)], fill=SKY + (220,), width=3 * SS)
    # gold center node (premium accent)
    dl.line([(cxp - 60 * SS, ly), (cxp + 60 * SS, ly)], fill=GOLD + (235,), width=3 * SS)

    out = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    out = Image.alpha_composite(out, glow2)
    out = Image.alpha_composite(out, glow)
    out = Image.alpha_composite(out, sun)
    out = Image.alpha_composite(out, line)
    out = Image.alpha_composite(out, full)

    # tagline
    tfont = ImageFont.truetype(F_SANS_REG, 50 * SS)
    tag = "REACH BEYOND THE HORIZON"
    tm = text_mask(tag, tfont, tracking=10 * SS)
    tmw = int(cw * 0.5)
    if tm.width > tmw:
        s = tmw / tm.width
        tm = tm.resize((int(tm.width * s), int(tm.height * s)))
    tfill = Image.new("RGBA", tm.size, MIDBLUE + (220,))
    out.paste(tfill, ((cw - tm.width) // 2, ly + int(mask.height * 0.22)), tm)

    out = out.resize((W, H), Image.LANCZOS)
    save_pair("concept_a_horizon", out, NAVY)


# ---------------------------------------------------------------------------
# CONCEPT B — "Pixel": true pixel-art wordmark (Kenney font, crisp blocks)
# ---------------------------------------------------------------------------
def concept_b():
    PX = 9          # size of one logical pixel in final image
    base_fs = 64    # render font small, then upscale NEAREST for crisp pixels
    font = ImageFont.truetype(F_PIXEL, base_fs)
    mask = text_mask(TEXT, font, tracking=8)
    # threshold to kill antialias -> pure pixels
    mask = mask.point(lambda p: 255 if p > 110 else 0)
    bb = mask.getbbox()
    mask = mask.crop(bb)

    mw, mh = mask.size
    pad = 6
    shadow_off = 2
    cw = (mw + pad * 2 + shadow_off)
    ch = (mh + pad * 2 + shadow_off + 4)  # room for shadow + tagline strip
    small = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))

    ox, oy = pad, pad
    # 1) dark outline (dilate by 1 logical px)
    out_mask = outline(mask, 1)
    ol = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    ol.paste(Image.new("RGBA", mask.size, NAVY_DEEP + (255,)), (ox, oy), out_mask)
    # 2) hard pixel drop shadow (teal-dark), offset down-right
    sh = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", mask.size, (18, 38, 42, 255)), (ox + shadow_off, oy + shadow_off), out_mask)
    # 3) two-tone gradient body (sky top -> teal bottom)
    body = fill_with_gradient(mask, SKY, TEAL_HI)
    bl = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    bl.paste(body, (ox, oy), mask)
    # 4) top highlight row (lighter sky) — read top 22% of glyphs
    hi_mask = mask.point(lambda p: 0)
    hpix = hi_mask.load()
    src = mask.load()
    for x in range(mw):
        cnt = 0
        for y in range(mh):
            if src[x, y] > 0:
                if cnt < max(1, mh // 9):
                    hpix[x, y] = 255
                cnt += 1
    hl = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    hl.paste(Image.new("RGBA", mask.size, WHITE + (255,)), (ox, oy), hi_mask)

    small = Image.alpha_composite(small, sh)
    small = Image.alpha_composite(small, ol)
    small = Image.alpha_composite(small, bl)
    small = Image.alpha_composite(small, hl)

    big = small.resize((cw * PX, ch * PX), Image.NEAREST)

    # soft outer glow added AFTER upscale (not pixelated) for premium pop
    glow = add_glow(big, SKY, 22, 0.55)
    final = Image.new("RGBA", big.size, (0, 0, 0, 0))
    final = Image.alpha_composite(final, glow)
    final = Image.alpha_composite(final, big)

    save_pair("concept_b_pixel", final, NAVY)


# ---------------------------------------------------------------------------
# CONCEPT C — "Ascend Emblem": ascending-peak badge + wordmark below
# ---------------------------------------------------------------------------
def concept_c():
    SS = 2
    W, H = 1400, 1500
    cw, ch = W * SS, H * SS
    out = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))

    cx = cw // 2
    badge_cy = int(ch * 0.34)
    R = int(cw * 0.30)

    # --- hex badge (rounded) ---
    import math
    def hexpts(r, rot=math.pi / 2):
        return [(cx + r * math.cos(rot + i * math.pi / 3),
                 badge_cy + r * math.sin(rot + i * math.pi / 3)) for i in range(6)]

    badge = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    db = ImageDraw.Draw(badge)
    # outer metallic teal ring
    db.polygon(hexpts(R), fill=None, outline=TEAL + (255,))
    grad = vertical_gradient((cw, ch), lerp(NAVY, TEAL, 0.25), NAVY_DEEP).convert("RGBA")
    pmask = Image.new("L", (cw, ch), 0)
    ImageDraw.Draw(pmask).polygon(hexpts(int(R * 0.93)), fill=255)
    badge.paste(grad, (0, 0), pmask)
    # ring strokes
    for rr, col, wdt in [(R, TEAL_HI, 10), (int(R * 0.93), SKY, 4), (int(R * 0.80), TEAL, 3)]:
        db.line(hexpts(rr) + [hexpts(rr)[0]], fill=col + (235,), width=wdt * SS)

    # --- ascending peaks / chevrons (the "Reach") ---
    pk = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    dp = ImageDraw.Draw(pk)
    base_y = badge_cy + int(R * 0.34)
    for i, (scale, col, alpha) in enumerate([(1.0, MIDBLUE, 235), (0.62, SKY, 255)]):
        pw = int(R * 0.74 * scale)
        ph = int(R * 0.82 * scale)
        apex = (cx, base_y - ph)
        left = (cx - pw, base_y)
        right = (cx + pw, base_y)
        dp.polygon([left, apex, right], fill=col + (alpha,))
        # cut a V to make it a chevron
        inner = int(pw * 0.42)
        ih = int(ph * 0.46)
        dp.polygon([(cx - inner, base_y), (cx, base_y - ih), (cx + inner, base_y)],
                   fill=(0, 0, 0, 0))
    # gold apex spark
    dp.ellipse([cx - 9 * SS, base_y - int(R * 0.82) - 9 * SS,
                cx + 9 * SS, base_y - int(R * 0.82) + 9 * SS], fill=GOLD + (255,))

    badge = Image.alpha_composite(badge, pk)
    bglow = add_glow(badge, SKY, 34 * SS, 0.6)
    out = Image.alpha_composite(out, bglow)
    out = Image.alpha_composite(out, badge)

    # --- wordmark below ---
    font = ImageFont.truetype(F_SANS_BOLD, 180 * SS)
    mask = text_mask(TEXT, font, tracking=12 * SS)
    maxw = int(cw * 0.86)
    if mask.width > maxw:
        s = maxw / mask.width
        mask = mask.resize((int(mask.width * s), int(mask.height * s)))
    wtx = (cw - mask.width) // 2
    wty = int(ch * 0.70)
    wm = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    wm.paste(fill_with_gradient(mask, SKY, MIDBLUE), (wtx, wty), mask)
    out = Image.alpha_composite(out, add_glow(wm, SKY, 22 * SS, 0.7))
    out = Image.alpha_composite(out, wm)

    # tagline
    tfont = ImageFont.truetype(F_SANS_REG, 46 * SS)
    tm = text_mask("AN ONLINE PIXEL WORLD", tfont, tracking=12 * SS)
    out.paste(Image.new("RGBA", tm.size, MIDBLUE + (220,)),
              ((cw - tm.width) // 2, wty + mask.height + 24 * SS), tm)

    out = out.resize((W, H), Image.LANCZOS)
    save_pair("concept_c_emblem", out, NAVY)


if __name__ == "__main__":
    print("Generating MythReach wordmarks ->", OUT)
    concept_a()
    concept_b()
    concept_c()
    print("Done.")
