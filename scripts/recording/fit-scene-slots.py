#!/usr/bin/env python3
"""Rewrite a walkthrough HTML's per-scene data-seconds to fit the narration.
Sets each scene slot = max(EN@dir, ZH@dir) duration + PAD, so both language
mux tracks fit with no drift/truncation. Usage:
  fit-scene-slots.py <html> <en-audio-dir> <zh-audio-dir> [pad]
"""
import re, sys, wave, glob, pathlib, math
html_path, en_dir, zh_dir = sys.argv[1], sys.argv[2], sys.argv[3]
pad = float(sys.argv[4]) if len(sys.argv) > 4 else 1.5
def durs(d):
    out=[]
    for f in sorted(glob.glob(f'{d}/step-*.wav')):
        with wave.open(f) as w: out.append(w.getnframes()/w.getframerate())
    return out
en, zh = durs(en_dir), durs(zh_dir)
html = pathlib.Path(html_path).read_text()
slots = re.findall(r'data-seconds="([0-9.]+)"', html)
n = len(slots)
assert len(en)==n and len(zh)==n, f"beat mismatch: scenes={n} en={len(en)} zh={len(zh)}"
new = [math.ceil(max(e,z)+pad) for e,z in zip(en,zh)]
# replace in order
it = iter(new)
html2 = re.sub(r'data-seconds="[0-9.]+"', lambda m: f'data-seconds="{next(it)}.0"', html)
pathlib.Path(html_path).write_text(html2)
print(f"{pathlib.Path(html_path).name}: slots -> {new}  (total {sum(new)}s)")
