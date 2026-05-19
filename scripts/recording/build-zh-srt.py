#!/usr/bin/env python3
"""
Build a Chinese .srt subtitle file by pairing each step in the ZH narration
file with the timing of the corresponding step in the EN timing.json.

The EN timing.json (written by gemini-tts.py) contains, for each step:
  { "step": N, "title": "...", "duration_ms": ms }
Steps are joined in the concatenated audio with SILENCE_MS gaps (default 800ms).

We assume the same step count and step ordering between EN and ZH narration,
which is enforced by Demo Narratives.md ↔ Demo Narratives ZH.md.

Usage:
  python3 build-zh-srt.py \
    --zh-narration path/to/foo.zh.md \
    --timing       recording/audio/foo/timing.json \
    --out          recording/audio/foo/foo.zh.srt
"""
import re, json, pathlib, argparse

import os
SILENCE_MS = int(os.environ.get('SILENCE_MS', '300'))  # must match gemini-tts.py

def parse_zh(path):
    """Parse '## Step N — title\\n\\nbody\\n---' blocks (matches gemini-tts.py format)."""
    text = pathlib.Path(path).read_text()
    blocks = re.split(r'\n---\n', text.strip())
    out = []
    for b in blocks:
        m = re.search(r'##\s+Step\s+(\d+)\s+[—-]\s+(.+?)\n+(.+)', b.strip(), re.DOTALL)
        if m:
            body = m.group(3).strip()
            body = re.sub(r'\*+([^*]+)\*+', r'\1', body)
            body = re.sub(r'`([^`]+)`', r'\1', body)
            out.append({'num': int(m.group(1)), 'text': body})
    return out

def fmt_ts(ms):
    h = ms // 3600000
    m = (ms % 3600000) // 60000
    s = (ms % 60000) // 1000
    ms_rem = ms % 1000
    return f"{h:02d}:{m:02d}:{s:02d},{ms_rem:03d}"

def wrap_chinese(text, max_chars_per_line=28):
    """Hard-wrap by character count (Chinese chars are ~1 unit wide)."""
    lines = []
    cur = ""
    for ch in text:
        cur += ch
        if len(cur) >= max_chars_per_line and ch in '。!?,;、 ':
            lines.append(cur.strip())
            cur = ""
    if cur.strip():
        lines.append(cur.strip())
    return "\n".join(lines)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--zh-narration', required=True)
    ap.add_argument('--timing', required=True)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()

    zh_steps = parse_zh(args.zh_narration)
    timing = json.loads(pathlib.Path(args.timing).read_text())

    if len(zh_steps) != len(timing):
        print(f"WARN: ZH steps={len(zh_steps)} vs timing steps={len(timing)} — using min()")

    n = min(len(zh_steps), len(timing))
    cur_ms = 0
    lines = []
    for i in range(n):
        dur = timing[i]['duration_ms']
        start = cur_ms
        end   = cur_ms + dur
        cur_ms = end + SILENCE_MS
        text = wrap_chinese(zh_steps[i]['text'])
        lines.append(f"{i+1}\n{fmt_ts(start)} --> {fmt_ts(end)}\n{text}\n")

    pathlib.Path(args.out).write_text("\n".join(lines))
    print(f"Wrote {n} subtitle cues to {args.out}  (total {cur_ms}ms)")

if __name__ == "__main__":
    main()
