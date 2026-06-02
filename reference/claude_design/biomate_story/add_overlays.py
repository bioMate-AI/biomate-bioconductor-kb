#!/usr/bin/env python3
"""
Add persistent branding overlays to BioMate Story videos:
  - "BioMate AI"       → top center, full duration
  - "www.biomate.ai"   → bottom right, full duration
  - Free Trial CTA     → bottom center, last scene only (scene 9)

Processes both English and Chinese subtitle versions.
"""

import os, subprocess
from PIL import Image, ImageDraw, ImageFont

BASE = os.path.dirname(os.path.abspath(__file__))

INPUTS = [
    (os.path.join(BASE, "biomate_story_final.mp4"),
     os.path.join(BASE, "biomate_story_en_branded.mp4")),
    (os.path.join(BASE, "biomate_story_zh_subtitles.mp4"),
     os.path.join(BASE, "biomate_story_zh_branded.mp4")),
]

FONT_SANS  = "/System/Library/Fonts/HelveticaNeue.ttc"
FONT_PING  = "/System/Library/Fonts/PingFang.ttc"

W, H = 1920, 1080

# Last scene starts at this timestamp (seconds)
# sum of first 8 scene durations from make_video.py
SCENE_DURS_MS = [3751, 9236, 3803, 8400, 9367, 8635, 8583, 4508]
S9_START_S = sum(SCENE_DURS_MS) / 1000   # ≈ 56.28s

REGISTER_URL = "www.biomate.ai/register"
TOTAL_S = 66.6


def draw_pill(draw, x, y, w, h, fill, radius=18):
    """Draw a rounded rectangle."""
    draw.rounded_rectangle([x, y, x+w, y+h], radius=radius, fill=fill)


def make_overlay_persistent():
    """Full-duration overlay: BioMate AI (top) + www.biomate.ai (bottom right)."""
    img  = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    WHITE  = (255, 250, 238, 255)
    GOLD   = (192, 138, 78,  255)
    NAVY   = (20,  40,  58,  200)

    font_brand = ImageFont.truetype(FONT_SANS, 46)
    font_url   = ImageFont.truetype(FONT_SANS, 34)

    # ── BioMate AI — top center ──
    brand = "BioMate AI"
    bb = draw.textbbox((0,0), brand, font=font_brand)
    bw, bh = bb[2]-bb[0], bb[3]-bb[1]
    pad_x, pad_y = 36, 16
    pill_w = bw + pad_x*2
    pill_h = bh + pad_y*2
    pill_x = (W - pill_w) // 2
    pill_y = 30
    draw_pill(draw, pill_x, pill_y, pill_w, pill_h, NAVY)
    draw.text((pill_x + pad_x - bb[0], pill_y + pad_y - bb[1]),
              brand, font=font_brand, fill=WHITE)

    # ── www.biomate.ai — bottom right ──
    url = "www.biomate.ai"
    ub = draw.textbbox((0,0), url, font=font_url)
    uw, uh = ub[2]-ub[0], ub[3]-ub[1]
    margin = 50
    up_x, up_y = 28, 12
    url_pill_w = uw + up_x*2
    url_pill_h = uh + up_y*2
    url_x = W - margin - url_pill_w
    url_y = H - margin - url_pill_h
    draw_pill(draw, url_x, url_y, url_pill_w, url_pill_h, NAVY)
    draw.text((url_x + up_x - ub[0], url_y + up_y - ub[1]),
              url, font=font_url, fill=GOLD)

    path = "/tmp/overlay_persistent.png"
    img.save(path, "PNG")
    return path


def make_overlay_cta():
    """Last-scene overlay: Free Trial CTA — bottom center."""
    img  = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    CREAM    = (246, 239, 222, 255)   # --cream bg on scene 9
    NAVY     = (20,  40,  58,  255)
    GOLD     = (192, 138, 78,  255)
    NAVY_BG  = (20,  40,  58,  230)

    font_cta  = ImageFont.truetype(FONT_SANS, 42)
    font_link = ImageFont.truetype(FONT_SANS, 36)

    line1 = "Start Your Free Trial"
    line2 = f"→  {REGISTER_URL}"

    bb1 = draw.textbbox((0,0), line1, font=font_cta)
    bb2 = draw.textbbox((0,0), line2, font=font_link)

    w1, h1 = bb1[2]-bb1[0], bb1[3]-bb1[1]
    w2, h2 = bb2[2]-bb2[0], bb2[3]-bb2[1]

    pad_x, pad_y, gap = 48, 20, 10
    pill_w = max(w1, w2) + pad_x*2
    pill_h = h1 + gap + h2 + pad_y*2
    pill_x = (W - pill_w) // 2
    pill_y = H - 170 - pill_h

    draw_pill(draw, pill_x, pill_y, pill_w, pill_h, NAVY_BG, radius=22)

    # line1 — white
    x1 = pill_x + (pill_w - w1)//2
    y1 = pill_y + pad_y
    draw.text((x1 - bb1[0], y1 - bb1[1]), line1, font=font_cta,  fill=CREAM)

    # line2 — gold
    x2 = pill_x + (pill_w - w2)//2
    y2 = y1 + h1 + gap
    draw.text((x2 - bb2[0], y2 - bb2[1]), line2, font=font_link, fill=GOLD)

    path = "/tmp/overlay_cta.png"
    img.save(path, "PNG")
    return path


def apply_overlays(input_path, output_path, p_overlay, cta_overlay):
    cmd = [
        "ffmpeg", "-y",
        "-i", input_path,
        "-i", p_overlay,
        "-i", cta_overlay,
        "-filter_complex",
        # 1. Persistent branding — always on
        f"[0:v][1:v]overlay=0:0[v1];"
        # 2. CTA — last scene only
        f"[v1][2:v]overlay=0:0:enable='gte(t,{S9_START_S:.3f})'[vout]",
        "-map", "[vout]",
        "-map", "0:a",
        "-c:v", "h264_videotoolbox", "-b:v", "10M",
        "-c:a", "copy",
        output_path,
    ]
    result = subprocess.run(cmd, capture_output=True)
    if result.returncode != 0:
        print(result.stderr.decode()[-2000:])
        raise RuntimeError(f"ffmpeg failed for {output_path}")
    size_mb = os.path.getsize(output_path) / (1024*1024)
    print(f"  → {os.path.basename(output_path)}  ({size_mb:.1f} MB)")


def run():
    print("── Building overlay PNGs ──")
    p_overlay  = make_overlay_persistent()
    cta_overlay = make_overlay_cta()
    print(f"  Persistent overlay: {p_overlay}")
    print(f"  CTA overlay:        {cta_overlay}  (from {S9_START_S:.1f}s)")

    print("\n── Applying to videos ──")
    for inp, out in INPUTS:
        if not os.path.exists(inp):
            print(f"  SKIP (not found): {inp}")
            continue
        print(f"  Processing: {os.path.basename(inp)}")
        apply_overlays(inp, out, p_overlay, cta_overlay)

    print("\nDone!")

if __name__ == "__main__":
    run()
