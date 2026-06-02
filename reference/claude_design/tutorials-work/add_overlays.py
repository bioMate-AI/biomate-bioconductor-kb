#!/usr/bin/env python3
"""
Add persistent branding overlays to all BioMate tutorial videos:
  - "BioMate AI"     → top center, full duration
  - "www.biomate.ai" → bottom right, full duration

Usage:
  python3 add_overlays.py                  # all tutorials
  python3 add_overlays.py --only cryosparc
"""

import os, sys, subprocess
from PIL import Image, ImageDraw, ImageFont

BASE      = os.path.dirname(os.path.abspath(__file__))
FONT_SANS = "/System/Library/Fonts/HelveticaNeue.ttc"
W, H      = 1920, 1080

TUTORIALS = ["cryosparc", "outputs_report", "drug_screen", "ind_report"]


def draw_pill(draw, x, y, w, h, fill, radius=18):
    draw.rounded_rectangle([x, y, x+w, y+h], radius=radius, fill=fill)


def make_overlay():
    img  = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    WHITE = (255, 250, 238, 255)
    GOLD  = (192, 138, 78, 255)
    NAVY  = (20, 40, 58, 200)

    font_brand = ImageFont.truetype(FONT_SANS, 46)
    font_url   = ImageFont.truetype(FONT_SANS, 34)

    # BioMate AI — top center
    brand = "BioMate AI"
    bb = draw.textbbox((0, 0), brand, font=font_brand)
    bw, bh = bb[2]-bb[0], bb[3]-bb[1]
    px, py = 36, 16
    pw = bw + px*2
    ph = bh + py*2
    pill_x = (W - pw) // 2
    pill_y = 30
    draw_pill(draw, pill_x, pill_y, pw, ph, NAVY)
    draw.text((pill_x + px - bb[0], pill_y + py - bb[1]), brand,
              font=font_brand, fill=WHITE)

    # www.biomate.ai — bottom right
    url = "www.biomate.ai"
    ub = draw.textbbox((0, 0), url, font=font_url)
    uw, uh = ub[2]-ub[0], ub[3]-ub[1]
    margin = 50
    upx, upy = 28, 12
    url_pw = uw + upx*2
    url_ph = uh + upy*2
    url_x = W - margin - url_pw
    url_y = H - margin - url_ph
    draw_pill(draw, url_x, url_y, url_pw, url_ph, NAVY)
    draw.text((url_x + upx - ub[0], url_y + upy - ub[1]), url,
              font=font_url, fill=GOLD)

    path = "/tmp/tutorial_overlay.png"
    img.save(path, "PNG")
    return path


def apply_overlay(inp, out, overlay_png):
    cmd = [
        "ffmpeg", "-y",
        "-i", inp, "-i", overlay_png,
        "-filter_complex", "[0:v][1:v]overlay=0:0[vout]",
        "-map", "[vout]", "-map", "0:a",
        "-c:v", "h264_videotoolbox", "-b:v", "10M",
        "-c:a", "copy", out,
    ]
    r = subprocess.run(cmd, capture_output=True)
    if r.returncode != 0:
        print(r.stderr.decode()[-2000:])
        raise RuntimeError(f"overlay failed for {out}")
    size_mb = os.path.getsize(out) / (1024*1024)
    print(f"  → {os.path.basename(out)}  ({size_mb:.1f} MB)")


def main():
    only = None
    if "--only" in sys.argv:
        idx = sys.argv.index("--only")
        only = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else None

    keys = [only] if only else TUTORIALS

    print("── Building overlay PNG ──")
    overlay = make_overlay()
    print(f"  {overlay}")

    print("\n── Applying to tutorials ──")
    for key in keys:
        inp = os.path.join(BASE, f"{key}_tutorial.mp4")
        out = os.path.join(BASE, f"{key}_tutorial_branded.mp4")
        if not os.path.exists(inp):
            print(f"  SKIP (not found): {inp}")
            continue
        print(f"  {key}")
        apply_overlay(inp, out, overlay)

    print("\nDone!")

if __name__ == "__main__":
    main()
