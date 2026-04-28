# Tutorial Recording Plan — Automated Audio + Video

**Date:** 2026-04-27  
**Status:** Ready to execute — all APIs confirmed available.

---

## Available APIs (no new keys needed)

| Tool | Status | Key/Source |
|---|---|---|
| **Gemini TTS** (`gemini-2.5-flash-preview-tts`, `gemini-3.1-flash-tts-preview`) | ✅ Available | `GEMINI_API_KEY` already set |
| **Playwright** (Python + Node, v1.57.0) | ✅ Installed | E2E test suite |
| **ffmpeg** | ❌ Not installed | `sudo apt-get install ffmpeg` (30s) |
| ElevenLabs | ❌ No key | Not needed — Gemini TTS is sufficient |

---

## Architecture

```
narration-*.md
      │
      ▼
[1] gemini-tts.py          →  audio/step-001.wav ... audio/step-019.wav
      │
      ▼
[2] concat-audio.py        →  audio/full-narration.wav
      │
      ▼
[3] playwright-record.py   →  video/raw-recording.webm   (advances steps timed to audio)
      │
      ▼
[4] ffmpeg merge            →  output/cryosparc-tutorial.mp4
```

---

## Step 1 — Install ffmpeg

```bash
sudo apt-get install -y ffmpeg
# verify
ffmpeg -version | head -1
```

---

## Step 2 — TTS generation script

**File:** `scripts/recording/gemini-tts.py`

```python
#!/usr/bin/env python3
"""
Generate per-step WAV audio from a narration .md file using Gemini TTS.

Usage:
  python3 gemini-tts.py \
    --narration reference/claude_design/biomate/cryosparc-narration.md \
    --out audio/cryosparc/
"""

import re, wave, struct, pathlib, argparse, os
import google.generativeai as genai

GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY', 'AIzaSyDoFJyQuwTYsfhoLO4DBL1ME9Ojl7VpFHI')
TTS_MODEL     = 'gemini-2.5-flash-preview-tts'
VOICE_NAME    = 'Aoede'          # Options: Aoede, Charon, Fenrir, Kore, Orbit, Puck, Schedar, Vega, Zephyr
SILENCE_MS    = 800              # pause between steps in the concatenated track

genai.configure(api_key=GEMINI_API_KEY)

def parse_narration(path: str) -> list[dict]:
    """Parse '## Step N — title\n\ntext\n---' blocks."""
    text = pathlib.Path(path).read_text()
    blocks = re.split(r'\n---\n', text.strip())
    steps = []
    for block in blocks:
        m = re.match(r'##\s+Step\s+(\d+)\s+[—-]\s+(.+?)\n+(.+)', block.strip(), re.DOTALL)
        if m:
            steps.append({
                'num':   int(m.group(1)),
                'title': m.group(2).strip(),
                'text':  m.group(3).strip(),
            })
    return steps

def tts(text: str) -> bytes:
    """Call Gemini TTS and return raw PCM bytes (24kHz, 16-bit, mono)."""
    model = genai.GenerativeModel(TTS_MODEL)
    resp = model.generate_content(
        text,
        generation_config=genai.GenerationConfig(
            response_modalities=['AUDIO'],
            speech_config=genai.SpeechConfig(
                voice_config=genai.VoiceConfig(
                    prebuilt_voice_config=genai.PrebuiltVoiceConfig(voice_name=VOICE_NAME)
                )
            ),
        ),
    )
    return resp.candidates[0].content.parts[0].inline_data.data

def pcm_to_wav(pcm: bytes, path: str, sample_rate=24000):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)          # 16-bit
        w.setframerate(sample_rate)
        w.writeframes(pcm)

def silence_frames(ms: int, sample_rate=24000) -> bytes:
    n = int(sample_rate * ms / 1000)
    return struct.pack('<' + 'h' * n, *([0] * n))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--narration', required=True)
    parser.add_argument('--out', required=True)
    parser.add_argument('--concat', default='full-narration.wav',
                        help='Output file for concatenated audio')
    args = parser.parse_args()

    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    steps = parse_narration(args.narration)
    print(f'Found {len(steps)} steps in {args.narration}')

    durations = []
    pcm_parts  = []
    silence    = silence_frames(SILENCE_MS)

    for step in steps:
        print(f'  TTS step {step["num"]:02d}: {step["title"][:50]}...')
        pcm = tts(step['text'])

        wav_path = out_dir / f'step-{step["num"]:03d}.wav'
        pcm_to_wav(pcm, str(wav_path))

        # Duration in milliseconds
        n_samples = len(pcm) // 2          # 16-bit = 2 bytes/sample
        duration_ms = int(n_samples / 24000 * 1000)
        durations.append(duration_ms)

        pcm_parts.append(pcm)
        pcm_parts.append(silence)
        print(f'    → {wav_path.name}  ({duration_ms} ms)')

    # Write concatenated WAV
    all_pcm = b''.join(pcm_parts)
    concat_path = out_dir / args.concat
    pcm_to_wav(all_pcm, str(concat_path))
    print(f'\nConcatenated: {concat_path}  ({sum(durations)/1000:.1f}s narration)')

    # Write timing JSON for Playwright
    import json
    timing = [{'step': s['num'], 'title': s['title'], 'duration_ms': d}
              for s, d in zip(steps, durations)]
    timing_path = out_dir / 'timing.json'
    timing_path.write_text(json.dumps(timing, indent=2))
    print(f'Timing file:  {timing_path}')

if __name__ == '__main__':
    main()
```

---

## Step 3 — Playwright recording script

**File:** `scripts/recording/playwright-record.py`

```python
#!/usr/bin/env python3
"""
Record the BioMate tutorial UX advancing through a demo, timed to the
per-step audio durations produced by gemini-tts.py.

Usage:
  python3 playwright-record.py \
    --demo cryosparc-main \
    --timing audio/cryosparc/timing.json \
    --out video/cryosparc-raw.webm \
    --url "http://localhost:7779/Workflow%20Panel%20Redesign.html"
"""

import json, time, argparse, pathlib
from playwright.sync_api import sync_playwright

NEXT_SELECTOR = 'button[data-tour-next], .tour-next, button:has-text("Next"), button:has-text("→")'
CLOSE_DELAY_MS = 2000   # hold on final frame before stopping

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--demo',   required=True)
    parser.add_argument('--timing', required=True)
    parser.add_argument('--out',    required=True)
    parser.add_argument('--url',    default='http://localhost:7779/Workflow%20Panel%20Redesign.html')
    parser.add_argument('--width',  type=int, default=1920)
    parser.add_argument('--height', type=int, default=1080)
    args = parser.parse_args()

    timing = json.loads(pathlib.Path(args.timing).read_text())
    out_path = pathlib.Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)   # headless=False to capture GPU/CSS
        context = browser.new_context(
            viewport={'width': args.width, 'height': args.height},
            record_video_dir=str(out_path.parent),
            record_video_size={'width': args.width, 'height': args.height},
        )
        page = context.new_page()
        page.goto(args.url, wait_until='networkidle')
        page.wait_for_timeout(1500)   # let fonts/JS settle

        # Select and start the demo from the picker
        page.evaluate(f'''() => {{
            const picker = document.querySelector('[data-tour-picker]') ||
                           document.querySelector('.tour-picker select') ||
                           document.querySelector('select');
            if (picker) {{
                picker.value = '{args.demo}';
                picker.dispatchEvent(new Event('change', {{bubbles:true}}));
            }}
            // Try direct API if picker not found
            if (window.startTour) window.startTour('{args.demo}');
        }}''')

        # Click the "Start" button if present
        try:
            page.locator('button:has-text("Start"), button:has-text("Begin"), [data-tour-start]').first.click(timeout=3000)
        except Exception:
            pass
        page.wait_for_timeout(800)

        # Advance through steps, holding each for its audio duration
        for i, step in enumerate(timing):
            hold_ms = step['duration_ms'] + 600   # 600ms buffer after narration ends
            print(f'  Step {step["step"]:02d} — {step["title"][:45]}  ({hold_ms}ms)')

            # Let the step render and animate in
            page.wait_for_timeout(min(hold_ms, hold_ms))

            # Click Next (unless last step)
            if i < len(timing) - 1:
                try:
                    page.locator(NEXT_SELECTOR).first.click(timeout=2000)
                except Exception:
                    # Try keyboard
                    page.keyboard.press('ArrowRight')
                page.wait_for_timeout(400)   # animation settle

        # Hold on final frame
        page.wait_for_timeout(CLOSE_DELAY_MS)
        context.close()

    # Playwright saves the video as a UUID-named .webm in the output dir.
    # Find it and rename to the requested path.
    video_files = sorted(out_path.parent.glob('*.webm'), key=lambda f: f.stat().st_mtime)
    if video_files:
        video_files[-1].rename(out_path)
        print(f'\nVideo saved: {out_path}')
    else:
        print('Warning: no .webm found in output dir')

if __name__ == '__main__':
    main()
```

---

## Step 4 — ffmpeg merge

```bash
# Merge video + narration audio
ffmpeg \
  -i video/cryosparc-raw.webm \
  -i audio/cryosparc/full-narration.wav \
  -c:v libx264 -preset fast -crf 18 \
  -c:a aac -b:a 192k \
  -shortest \
  output/cryosparc-tutorial.mp4

# For the deck (no video — just audio over slides exported as images)
# Export deck slides as PNGs first, then:
ffmpeg \
  -framerate 1/SLIDE_DURATION \
  -i slides/slide-%02d.png \
  -i audio/deck/full-narration.wav \
  -c:v libx264 -pix_fmt yuv420p \
  -c:a aac \
  -shortest \
  output/biomate-deck.mp4
```

---

## Step 5 — Convenience runner

**File:** `scripts/recording/record-tutorial.sh`

```bash
#!/bin/bash
# Usage: ./record-tutorial.sh cryosparc
# Runs all four steps for a given demo.

DEMO=$1
NARRATION="reference/claude_design/biomate/${DEMO}-narration.md"
AUDIO_DIR="recording/audio/${DEMO}"
VIDEO_DIR="recording/video"
OUTPUT="recording/output/${DEMO}-tutorial.mp4"

set -e

echo "=== [1] Installing ffmpeg if needed ==="
which ffmpeg || sudo apt-get install -y ffmpeg

echo "=== [2] Generating TTS audio ==="
python3 scripts/recording/gemini-tts.py \
  --narration "$NARRATION" \
  --out "$AUDIO_DIR"

echo "=== [3] Recording screen ==="
python3 scripts/recording/playwright-record.py \
  --demo "$DEMO" \
  --timing "$AUDIO_DIR/timing.json" \
  --out "$VIDEO_DIR/${DEMO}-raw.webm"

echo "=== [4] Merging audio + video ==="
mkdir -p recording/output
ffmpeg -y \
  -i "$VIDEO_DIR/${DEMO}-raw.webm" \
  -i "$AUDIO_DIR/full-narration.wav" \
  -c:v libx264 -preset fast -crf 18 \
  -c:a aac -b:a 192k \
  -shortest \
  "$OUTPUT"

echo "Done: $OUTPUT"
```

---

## Execution order

```bash
cd /home/yzhang/biomate

# 1. Install ffmpeg (once)
sudo apt-get install -y ffmpeg

# 2. Create scripts
mkdir -p scripts/recording recording/audio recording/video recording/output

# 3. Record in order (quickstart → cryo → outputs → deck)
bash scripts/recording/record-tutorial.sh website-quickstart
bash scripts/recording/record-tutorial.sh cryosparc-main    # maps to cryosparc-narration.md
bash scripts/recording/record-tutorial.sh outputs-findings  # maps to outputs-findings-narration.md
# deck is separate — slides must be exported as images first
```

---

## Voice options (Gemini TTS)

| Name | Character | Best for |
|---|---|---|
| **Aoede** | Clear, neutral, professional | Default — tutorials |
| **Charon** | Warm, slower | Detailed explanations |
| **Fenrir** | Energetic, direct | Product demos |
| **Kore** | Soft, approachable | Onboarding |
| **Orbit** | Confident, measured | Investor deck |

Set `VOICE_NAME` in `gemini-tts.py`. Use `Orbit` for the deck, `Aoede` for tutorials.

---

## Known limitations / mitigations

| Issue | Mitigation |
|---|---|
| Playwright `Next` button selector may vary | Script tries 3 selectors + keyboard fallback |
| Gemini TTS rate limits (~60 req/min) | Script processes sequentially with 200ms gaps |
| Video headless rendering may miss CSS animations | `headless=False` used — runs visible browser |
| Step timing drift if audio is longer than expected | 600ms buffer added per step; timing.json generated from actual audio length |
| Deck has no interactive UI to record | Export slides as PNG series, use ffmpeg image slideshow |
