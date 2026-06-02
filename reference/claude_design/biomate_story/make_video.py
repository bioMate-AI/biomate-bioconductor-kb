#!/usr/bin/env python3
"""
Build BioMate Story video:
  1. Patch HTML data-dur values to match Rachel v4 audio
  2. Use Chrome CDP screencast to record the ACTUAL animated HTML playing
  3. Stitch frames with real timestamps → video
  4. Merge with Rachel v4 audio → final MP4
"""

import os, re, subprocess, json, shutil

BASE    = os.path.dirname(os.path.abspath(__file__))
HTML_IN = os.path.join(BASE, "BioMate_Story.html")
HTML_TMP = "/tmp/biomate_story_patched.html"
AUDIO   = os.path.join(BASE, "biomate_story_vo_rachel_v4.mp3")
OUTPUT  = os.path.join(BASE, "biomate_story_final.mp4")

CHROME_PATH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FRAMES_DIR  = "/tmp/biomate_frames"
RAW_VIDEO   = "/tmp/biomate_raw.mp4"
NODE_SCRIPT = "/tmp/biomate_record.js"

# Per-scene durations (ms) matching Rachel v4 audio
SCENE_DURS_MS = [
    2351 + 1400,                    # 3751   scene 1
    7836 + 1400,                    # 9236   scene 2
    2403 + 1400,                    # 3803   scene 3
    7000 + 1400,                    # 8400   scene 4
    7967 + 1400,                    # 9367   scene 5
    7235 + 1400,                    # 8635   scene 6
    7183 + 1400,                    # 8583   scene 7
    3108 + 1400,                    # 4508   scene 8
    1332 + 900 + 3004 + 800 + 2821 + 5000,  # 13857  scene 9 (full closing sequence)
]
TOTAL_MS = sum(SCENE_DURS_MS)
N = len(SCENE_DURS_MS)


# ── Step 1: Patch HTML timing ─────────────────────────────────────────────────

def patch_html():
    with open(HTML_IN, "r", encoding="utf-8") as f:
        html = f.read()

    # 1. Patch data-dur timings
    matches = list(re.finditer(r'data-dur="\d+"', html))
    assert len(matches) >= N
    result, last = [], 0
    for i, m in enumerate(matches[:N]):
        result.append(html[last:m.start()])
        result.append(f'data-dur="{SCENE_DURS_MS[i]}"')
        last = m.end()
    result.append(html[last:])
    html = "".join(result)

    # 2. Fix black-flash bug: replace visibility:hidden with pointer-events:none
    #    so scenes stay composited (just transparent) during cross-fade.
    #    Without this, visibility:hidden fires immediately on scene exit, exposing
    #    the black body background for the full 550ms fade-in of the next scene.
    html = html.replace(
        "opacity:0;visibility:hidden;\n    transition:opacity .55s ease;",
        "opacity:0;pointer-events:none;\n    transition:opacity .55s ease;"
    )
    html = html.replace(
        ".scene.is-active{opacity:1;visibility:visible;}",
        ".scene.is-active{opacity:1;pointer-events:auto;}"
    )

    with open(HTML_TMP, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"  HTML patched: {TOTAL_MS/1000:.1f}s total, black-flash fix applied")


# ── Step 2: Record via CDP screencast ────────────────────────────────────────

def write_recorder():
    script = f"""
const puppeteer = require('/tmp/biomate_video_tool/node_modules/puppeteer-core');
const fs   = require('fs');
const path = require('path');

const CHROME   = {json.dumps(CHROME_PATH)};
const HTML     = {json.dumps('file://' + HTML_TMP)};
const FRAMES   = {json.dumps(FRAMES_DIR)};
const TOTAL_MS = {TOTAL_MS};

(async () => {{
  fs.mkdirSync(FRAMES, {{ recursive: true }});

  const browser = await puppeteer.launch({{
    executablePath: CHROME,
    headless: 'new',
    args: [
      '--no-sandbox', '--disable-setuid-sandbox',
      '--window-size=1920,1080',
      '--force-device-scale-factor=1',
    ],
    defaultViewport: {{ width: 1920, height: 1080 }},
  }});

  const page = await browser.newPage();
  await page.goto(HTML, {{ waitUntil: 'domcontentloaded' }});
  await new Promise(r => setTimeout(r, 1000)); // wait for fonts + SVGs

  // Hide player UI chrome before recording
  await page.evaluate(() => {{
    ['ui', 'hint', 'prog'].forEach(id => {{
      const el = document.getElementById(id);
      if (el) el.style.display = 'none';
    }});
  }});

  const client = await page.createCDPSession();
  const frames = [];

  client.on('Page.screencastFrame', async (e) => {{
    frames.push({{ ts: e.metadata.timestamp, data: e.data }});
    await client.send('Page.screencastFrameAck', {{ sessionId: e.sessionId }});
  }});

  // Start screencast THEN autoplay so we capture from frame 0
  await client.send('Page.startScreencast', {{
    format: 'png',
    maxWidth: 1920,
    maxHeight: 1080,
    everyNthFrame: 1,
  }});

  // Press Space to start the HTML autoplay
  await page.keyboard.press('Space');
  console.log(`Autoplay started — recording ${{TOTAL_MS/1000}}s...`);

  // Wait for full animation + buffer
  await new Promise(r => setTimeout(r, TOTAL_MS + 1500));

  await client.send('Page.stopScreencast');
  await browser.close();

  console.log(`Captured ${{frames.length}} frames`);
  if (frames.length === 0) {{ console.error('No frames!'); process.exit(1); }}

  // Save PNGs + timestamps
  const timestamps = [];
  for (let i = 0; i < frames.length; i++) {{
    const p = path.join(FRAMES, `frame_${{String(i).padStart(5,'0')}}.png`);
    fs.writeFileSync(p, Buffer.from(frames[i].data, 'base64'));
    timestamps.push(frames[i].ts);
  }}
  fs.writeFileSync(path.join(FRAMES, 'timestamps.json'), JSON.stringify(timestamps));

  const dur = timestamps[timestamps.length-1] - timestamps[0];
  console.log(`Duration: ${{dur.toFixed(2)}}s, FPS avg: ${{(frames.length/dur).toFixed(1)}}`);
}})().catch(e => {{ console.error(e); process.exit(1); }});
"""
    with open(NODE_SCRIPT, "w") as f:
        f.write(script)
    pkg = "/tmp/biomate_video_tool/package.json"
    with open(pkg) as f:
        data = json.load(f)
    data.pop("type", None)
    with open(pkg, "w") as f:
        json.dump(data, f)


# ── Step 3: Build video from timestamped frames ───────────────────────────────

def build_video():
    ts_path = os.path.join(FRAMES_DIR, "timestamps.json")
    with open(ts_path) as f:
        timestamps = json.load(f)

    n = len(timestamps)
    t0 = timestamps[0]

    # Build ffmpeg concat file with per-frame duration
    concat_path = "/tmp/biomate_concat.txt"
    with open(concat_path, "w") as f:
        for i in range(n):
            img = os.path.join(FRAMES_DIR, f"frame_{str(i).zfill(5)}.png")
            if i < n - 1:
                dur = timestamps[i+1] - timestamps[i]
            else:
                dur = 1.0 / 30  # last frame
            f.write(f"file '{img}'\n")
            f.write(f"duration {dur:.6f}\n")
        # Repeat last frame (ffmpeg requirement)
        last = os.path.join(FRAMES_DIR, f"frame_{str(n-1).zfill(5)}.png")
        f.write(f"file '{last}'\n")

    total_s = timestamps[-1] - t0
    target_s = TOTAL_MS / 1000
    extend_s = max(0, target_s - total_s)
    print(f"  Stitching {n} frames → {total_s:.1f}s video (target {target_s:.1f}s, extending {extend_s:.1f}s)")

    # Stitch frames
    stitched = "/tmp/biomate_stitched.mp4"
    result = subprocess.run([
        "ffmpeg", "-y",
        "-f", "concat", "-safe", "0", "-i", concat_path,
        "-vf", "scale=1920:1080:flags=lanczos,format=yuv420p",
        "-c:v", "h264_videotoolbox", "-b:v", "10M",
        "-t", f"{total_s:.3f}",
        stitched,
    ], capture_output=True)
    if result.returncode != 0:
        print(result.stderr.decode()[-2000:])
        raise RuntimeError("ffmpeg stitch failed")

    # Extend last frame to cover trailing silence
    if extend_s > 0.1:
        result2 = subprocess.run([
            "ffmpeg", "-y", "-i", stitched,
            "-vf", f"tpad=stop_mode=clone:stop_duration={extend_s:.3f}",
            "-c:v", "h264_videotoolbox", "-b:v", "10M",
            "-pix_fmt", "yuv420p",
            RAW_VIDEO,
        ], capture_output=True)
        if result2.returncode != 0:
            print(result2.stderr.decode()[-2000:])
            raise RuntimeError("ffmpeg extend failed")
    else:
        import shutil as _sh
        _sh.copy(stitched, RAW_VIDEO)


# ── Step 4: Merge with audio ──────────────────────────────────────────────────

def merge_audio():
    subprocess.run([
        "ffmpeg", "-y",
        "-i", RAW_VIDEO,
        "-i", AUDIO,
        "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
        "-shortest",
        OUTPUT,
    ], check=True, capture_output=True)


# ── Main ──────────────────────────────────────────────────────────────────────

def run():
    if os.path.exists(FRAMES_DIR):
        shutil.rmtree(FRAMES_DIR)
    os.makedirs(FRAMES_DIR)

    print("── Step 1: Patch HTML ──")
    patch_html()

    print("\n── Step 2: Write recorder ──")
    write_recorder()

    print("\n── Step 3: Record animation via CDP screencast ──")
    subprocess.run(["node", NODE_SCRIPT], check=True)

    print("\n── Step 4: Build video from frames ──")
    build_video()

    print("\n── Step 5: Merge with Rachel audio ──")
    merge_audio()

    size_mb = os.path.getsize(OUTPUT) / (1024 * 1024)
    print(f"\nDone! → {OUTPUT}  ({size_mb:.1f} MB)")

if __name__ == "__main__":
    run()
