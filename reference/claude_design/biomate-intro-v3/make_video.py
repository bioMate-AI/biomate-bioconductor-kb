#!/usr/bin/env python3
"""
Build BioMate Intro v3 video via CDP screencast.
Navigates each slide with goTo(), records live animations, merges with VO audio.
"""

import os, subprocess, json, shutil

DIR       = os.path.dirname(os.path.abspath(__file__))
HTML_IN   = os.path.join(DIR, "BioMate Intro v3.html")
HTML_TMP  = os.path.join(DIR, "biomate_intro_patched.html")
AUDIO_DIR = os.path.join(DIR, "vo_slides")
COMBINED  = os.path.join(DIR, "biomate_intro_v3_vo.mp3")
OUTPUT    = os.path.join(DIR, "biomate_intro_v3_final.mp4")

CHROME_PATH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FRAMES_DIR  = "/tmp/biomate_intro_frames"
RAW_VIDEO   = "/tmp/biomate_intro_raw.mp4"
NODE_SCRIPT = "/tmp/biomate_intro_record.js"

GAP_MS = 800  # silence between slides (ms)

# (DOM position passed to goTo(), audio filename)
# deck-stage._collectSlides() assigns indices by DOM order, not by the
# data-deck-slide attribute values in the source HTML. The DOM order is:
#   0=Title  1=Problem  2=Solution  3=End-to-End  4=Reg-LLM  5=Inside
#   6=Product  7=Differentiator  8=Benchmarks(skip)  9=Closing
# The combined audio (biomate_intro_v3_vo.mp3) was generated in the order:
#   title, problem, solution, end-to-end, inside, product, differentiator,
#   reg_llm, closing — so we navigate slides in that matching sequence.
SLIDES = [
    (0, "01_title.mp3"),           # DOM 0 = Title
    (1, "02_problem.mp3"),         # DOM 1 = Problem
    (2, "03_solution.mp3"),        # DOM 2 = Solution
    (3, "04_end_to_end.mp3"),      # DOM 3 = End-to-End
    (5, "05_inside.mp3"),          # DOM 5 = Inside
    (6, "06_product.mp3"),         # DOM 6 = Product
    (7, "07_differentiator.mp3"),  # DOM 7 = Differentiator
    (4, "09_reg_llm.mp3"),         # DOM 4 = Reg-LLM
    (9, "10_closing.mp3"),         # DOM 9 = Closing
]

def audio_dur_ms(filename):
    path = os.path.join(AUDIO_DIR, filename)
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        capture_output=True, text=True)
    return int(float(r.stdout.strip()) * 1000)

def video_dur_s(path):
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        capture_output=True, text=True)
    return float(r.stdout.strip())

def patch_html():
    """Remove visibility:hidden flash bug (same fix as biomate_story)."""
    with open(HTML_IN, "r", encoding="utf-8") as f:
        html = f.read()
    html = html.replace(
        "opacity:0;visibility:hidden;\n    transition:opacity .55s ease;",
        "opacity:0;pointer-events:none;\n    transition:opacity .55s ease;"
    ).replace(
        ".scene.is-active{opacity:1;visibility:visible;}",
        ".scene.is-active{opacity:1;pointer-events:auto;}"
    )
    with open(HTML_TMP, "w", encoding="utf-8") as f:
        f.write(html)

def write_recorder(slide_timings):
    """
    slide_timings: list of (html_idx, hold_ms) for each non-skipped slide.
    Takes explicit screenshots at fixed intervals so every slide is captured,
    even when Chrome's compositor stops sending CDP screencast frames on static slides.
    First 800ms of each slide uses fast 30ms intervals to capture entry animations;
    remaining hold time uses 150ms intervals for efficiency.
    """
    timings_json = json.dumps([{"idx": idx, "holdMs": h} for idx, h in slide_timings])

    script = f"""
const puppeteer = require('{DIR}/node_modules/puppeteer-core');
const fs   = require('fs');
const path = require('path');

const CHROME   = {json.dumps(CHROME_PATH)};
const HTML     = {json.dumps('file://' + HTML_TMP)};
const FRAMES   = {json.dumps(FRAMES_DIR)};
const TIMINGS  = {timings_json};
const ANIM_MS  = 900;   // capture fast during slide entry animation
const FAST_MS  = 30;    // ms between screenshots during animation
const IDLE_MS  = 150;   // ms between screenshots during static hold

(async () => {{
  fs.mkdirSync(FRAMES, {{ recursive: true }});

  const browser = await puppeteer.launch({{
    executablePath: CHROME,
    headless: 'new',
    args: ['--no-sandbox','--disable-setuid-sandbox',
           '--window-size=1920,1080',
           '--force-device-scale-factor=1'],
    defaultViewport: {{ width: 1920, height: 1080 }},
  }});

  const page = await browser.newPage();
  await page.goto(HTML, {{ waitUntil: 'networkidle0' }});
  await new Promise(r => setTimeout(r, 2000)); // fonts + web component init

  // Hide navigation bar and slide counters
  await page.evaluate(() => {{
    const style = document.createElement('style');
    style.textContent = '.pageno {{ display: none !important; }}';
    document.head.appendChild(style);

    const stage = document.querySelector('deck-stage');
    if (stage) {{
      stage.setAttribute('no-rail', '');
      const root = stage.shadowRoot;
      if (root) {{
        ['overlay','rail','rail-resize'].forEach(cls => {{
          const el = root.querySelector('.' + cls);
          if (el) el.style.display = 'none';
        }});
      }}
    }}
  }});

  await new Promise(r => setTimeout(r, 500));

  let frameIdx = 0;
  const timestamps = [];

  async function snap(wallMs) {{
    const p = path.join(FRAMES, `frame_${{String(frameIdx).padStart(5,'0')}}.png`);
    await page.screenshot({{ path: p, type: 'png' }});
    timestamps.push(wallMs / 1000);
    frameIdx++;
  }}

  const t0 = Date.now();

  for (const {{ idx, holdMs }} of TIMINGS) {{
    const slideStart = Date.now() - t0;
    await page.evaluate((i) => {{
      const stage = document.querySelector('deck-stage');
      if (stage && typeof stage.goTo === 'function') stage.goTo(i);
    }}, idx);
    console.log(`  Slide ${{idx + 1}}: hold ${{holdMs}}ms`);

    // Fast capture during entry animation
    const animEnd = slideStart + Math.min(ANIM_MS, holdMs);
    while ((Date.now() - t0) < animEnd) {{
      await snap(Date.now() - t0);
      await new Promise(r => setTimeout(r, FAST_MS));
    }}

    // Slower capture for the rest of the hold
    const holdEnd = slideStart + holdMs;
    while ((Date.now() - t0) < holdEnd) {{
      await snap(Date.now() - t0);
      await new Promise(r => setTimeout(r, IDLE_MS));
    }}
  }}

  // One final frame
  await snap(Date.now() - t0);

  await browser.close();

  fs.writeFileSync(path.join(FRAMES, 'timestamps.json'), JSON.stringify(timestamps));
  const dur = timestamps[timestamps.length-1] - timestamps[0];
  console.log(`Captured ${{frameIdx}} frames, duration ${{dur.toFixed(2)}}s`);
}})().catch(e => {{ console.error(e); process.exit(1); }});
"""
    with open(NODE_SCRIPT, "w") as f:
        f.write(script)

def build_video(target_ms):
    with open(os.path.join(FRAMES_DIR, "timestamps.json")) as f:
        timestamps = json.load(f)

    n = len(timestamps)
    t0 = timestamps[0]
    recorded_s = timestamps[-1] - t0
    target_s = target_ms / 1000
    print(f"  {n} frames, {recorded_s:.1f}s timestamp span, target {target_s:.1f}s")

    concat_path = "/tmp/biomate_intro_concat.txt"
    with open(concat_path, "w") as f:
        for i in range(n):
            img = os.path.join(FRAMES_DIR, f"frame_{str(i).zfill(5)}.png")
            dur = (timestamps[i+1] - timestamps[i]) if i < n-1 else 1/30
            f.write(f"file '{img}'\nduration {dur:.6f}\n")
        f.write(f"file '{os.path.join(FRAMES_DIR, f'frame_{str(n-1).zfill(5)}.png')}'\n")

    stitched = "/tmp/biomate_intro_stitched.mp4"
    r = subprocess.run([
        "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", concat_path,
        "-vf", "scale=1920:1080:flags=lanczos,format=yuv420p",
        "-c:v", "h264_videotoolbox", "-b:v", "10M",
        "-t", f"{recorded_s:.3f}", stitched,
    ], capture_output=True)
    if r.returncode != 0:
        print(r.stderr.decode()[-2000:])
        raise RuntimeError("stitch failed")

    # Measure actual stitched duration (may differ from timestamp span)
    actual_s = video_dur_s(stitched)
    extend_s = max(0, target_s - actual_s)
    print(f"  Stitched: {actual_s:.1f}s actual, extending {extend_s:.1f}s")

    if extend_s > 0.1:
        r2 = subprocess.run([
            "ffmpeg", "-y", "-i", stitched,
            "-vf", f"tpad=stop_mode=clone:stop_duration={extend_s:.3f}",
            "-c:v", "h264_videotoolbox", "-b:v", "10M",
            "-pix_fmt", "yuv420p", RAW_VIDEO,
        ], capture_output=True)
        if r2.returncode != 0:
            print(r2.stderr.decode()[-2000:])
            raise RuntimeError("extend failed")
    else:
        shutil.copy(stitched, RAW_VIDEO)

def merge_audio():
    subprocess.run([
        "ffmpeg", "-y", "-i", RAW_VIDEO, "-i", COMBINED,
        "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest",
        OUTPUT,
    ], check=True, capture_output=True)

def run():
    # Calculate slide timings
    slide_timings = []
    for i, (html_idx, audio_file) in enumerate(SLIDES):
        if audio_file is None:
            continue
        dur_ms = audio_dur_ms(audio_file)
        is_last = all(af is None for _, af in SLIDES[i+1:])
        gap = 500 if is_last else GAP_MS
        hold_ms = dur_ms + gap
        slide_timings.append((html_idx, hold_ms))
        print(f"  Slide {html_idx+1}: {audio_file} → {dur_ms}ms + {gap}ms gap = {hold_ms}ms")

    total_ms = sum(h for _, h in slide_timings)
    print(f"\nTotal: {total_ms/1000:.1f}s\n")

    if os.path.exists(FRAMES_DIR):
        shutil.rmtree(FRAMES_DIR)
    os.makedirs(FRAMES_DIR)

    print("── Step 1: Patch HTML ──")
    patch_html()

    print("\n── Step 2: Write recorder ──")
    write_recorder(slide_timings)

    print("\n── Step 3: Record via CDP screencast ──")
    subprocess.run(["node", NODE_SCRIPT], check=True)

    print("\n── Step 4: Build video ──")
    build_video(total_ms)

    print("\n── Step 5: Merge with VO audio ──")
    merge_audio()

    size_mb = os.path.getsize(OUTPUT) / (1024*1024)
    print(f"\nDone! → {OUTPUT}  ({size_mb:.1f} MB)")

if __name__ == "__main__":
    run()
