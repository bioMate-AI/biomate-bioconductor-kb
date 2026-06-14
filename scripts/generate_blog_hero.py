#!/usr/bin/env python3
"""
Generate a photorealistic blog hero image via Google's image API, matching the BioMate blog set
(cinematic, warm-lit, 1408x768). Saves to webpage_design_v2/images/<slug>-hero.png.

Usage:
  GEMINI_API_KEY=... python3 scripts/generate_blog_hero.py <slug> "<prompt>"

Tries Imagen 4 first (imagen-4.0-generate-001:predict), falls back to Gemini image generation.
"""
import sys, os, base64, json, io, urllib.request
from pathlib import Path
from PIL import Image

KEY = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
IMG_DIR = Path("/home/yzhang/biomate/reference/claude_design/webpage_design_v2/images")
SIZE = (1408, 768)

STYLE = (" Cinematic photorealistic editorial photograph, 35mm, shallow depth of field, soft bokeh, "
         "moody warm amber and cool teal lighting, modern office at dusk, high detail, no text overlays, "
         "no logos, no watermarks.")


def _post(url, body):
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def via_imagen(prompt):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/imagen-4.0-generate-001:predict?key={KEY}"
    body = {"instances": [{"prompt": prompt}],
            "parameters": {"sampleCount": 1, "aspectRatio": "16:9"}}
    d = _post(url, body)
    return base64.b64decode(d["predictions"][0]["bytesBase64Encoded"])


def via_gemini(prompt):
    url = (f"https://generativelanguage.googleapis.com/v1beta/models/"
           f"gemini-2.5-flash-image:generateContent?key={KEY}")
    body = {"contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"responseModalities": ["IMAGE", "TEXT"]}}
    d = _post(url, body)
    for part in d["candidates"][0]["content"]["parts"]:
        if "inlineData" in part:
            return base64.b64decode(part["inlineData"]["data"])
    raise RuntimeError("no image in gemini response")


def main():
    if not KEY:
        print("ERROR: set GEMINI_API_KEY"); return 1
    slug = sys.argv[1]
    prompt = (sys.argv[2] if len(sys.argv) > 2 else "") + STYLE
    raw = None
    for name, fn in (("imagen", via_imagen), ("gemini", via_gemini)):
        try:
            raw = fn(prompt); print(f"[hero] generated via {name}"); break
        except Exception as e:
            print(f"[hero] {name} failed: {str(e)[:160]}")
    if not raw:
        print("ERROR: all image backends failed"); return 2
    im = Image.open(io.BytesIO(raw)).convert("RGB")
    tw, th = SIZE
    sw, sh = im.size
    scale = max(tw / sw, th / sh)
    im = im.resize((round(sw * scale), round(sh * scale)), Image.LANCZOS)
    sw, sh = im.size
    im = im.crop(((sw - tw) // 2, (sh - th) // 2, (sw - tw) // 2 + tw, (sh - th) // 2 + th))
    out = IMG_DIR / f"{slug}-hero.png"
    im.save(out, "PNG")
    print(f"[hero] saved {out} {im.size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
