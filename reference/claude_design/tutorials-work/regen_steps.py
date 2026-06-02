#!/usr/bin/env python3
"""
Regenerate only the changed voiceover steps and rebuild combined.mp3 + timings.json.
Run after updating generate_vo.py narration text.
"""

import os, sys, subprocess, json, requests

API_KEY  = "sk_f850eae3cd4b254613c81e3b9a7d448a6924f4789e1233a4"
VOICE_ID = "21m00Tcm4TlvDq8ikWAM"   # Rachel
BASE     = os.path.dirname(os.path.abspath(__file__))
CLIPS    = os.path.join(BASE, "clips")

DEFAULT_SPEED  = 0.80
CLOSING_SPEED  = 0.75
CENTER_GAP_MS  = 1200
SPOT_GAP_MS    = 900

# Only the steps whose text changed:
CHANGED = {
    "cryosparc": {
        7:  ("We're off. Status is running. "
             "Phase A motion correction is processing on Batch GPUs.",
             False, None),
        20: ("Raw movies to a sharpened 3D map in twenty-three steps — "
             "motion correction, picking, 2D classification, 3D reconstruction, and sharpening.",
             True, CLOSING_SPEED),
    },
    "drug_screen": {
        1:  ("Drug screens often need a pilot, fail QC, and recover via auto-loop. "
             "We'll watch the whole sequence inline — pilot, fail, auto-loop, compare, full, findings. "
             "The tour drives every decision for you.",
             True, CLOSING_SPEED),
        12: ("The completion summary lands inline. "
             "Forty-seven BBB-penetrant candidates after all QC gates, "
             "with a link to the full Report.",
             False, None),
    },
    "ind_report": {
        1:  ("Welcome to the BioMate IND Report. "
             "We'll walk through the five-step pipeline that builds an IND-quality "
             "section 2.6 nonclinical dossier, the live document panel on the right, "
             "and the 21 CFR Part 11 sign-and-freeze at the end.",
             True, CLOSING_SPEED),
    },
}


def audio_duration_ms(path):
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "json", path],
        capture_output=True, text=True)
    return int(float(json.loads(r.stdout)["format"]["duration"]) * 1000)


def generate_clip(text, speed, outpath):
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}"
    payload = {
        "text": text,
        "model_id": "eleven_multilingual_v2",
        "voice_settings": {
            "stability": 0.45,
            "similarity_boost": 0.82,
            "style": 0.0,
            "use_speaker_boost": True,
            "speed": speed,
        },
    }
    headers = {"xi-api-key": API_KEY, "Content-Type": "application/json"}
    resp = requests.post(url, json=payload, headers=headers, timeout=60)
    resp.raise_for_status()
    with open(outpath, "wb") as f:
        f.write(resp.content)


def make_silence(ms, outpath):
    subprocess.run([
        "ffmpeg", "-y", "-f", "lavfi",
        "-i", "anullsrc=r=44100:cl=mono",
        "-t", str(ms / 1000), "-q:a", "2", outpath,
    ], capture_output=True, check=True)


def rebuild_combined(key):
    out_dir = os.path.join(CLIPS, key)
    timings_fp = os.path.join(out_dir, "timings.json")
    with open(timings_fp) as f:
        data = json.load(f)

    # Recompute timings for any changed steps
    changed = CHANGED.get(key, {})
    for entry in data["steps"]:
        step_n = entry["step"]
        if step_n in changed:
            clip_path = os.path.join(out_dir, f"step_{step_n:02d}.mp3")
            entry["clip_ms"] = audio_duration_ms(clip_path)
            entry["hold_ms"] = entry["clip_ms"] + entry["gap_ms"]

    data["total_ms"] = sum(e["hold_ms"] for e in data["steps"])

    with open(timings_fp, "w") as f:
        json.dump(data, f, indent=2)

    # Rebuild silence files for changed steps
    for entry in data["steps"]:
        step_n = entry["step"]
        if step_n in changed:
            sil = os.path.join(out_dir, f"sil_{step_n:02d}.mp3")
            make_silence(entry["gap_ms"], sil)

    # Rebuild combined.mp3
    n = len(data["steps"])
    concat_path = os.path.join(out_dir, "concat.txt")
    with open(concat_path, "w") as f:
        for i in range(1, n + 1):
            f.write(f"file '{os.path.join(out_dir, f'step_{i:02d}.mp3')}'\n")
            if i < n:
                f.write(f"file '{os.path.join(out_dir, f'sil_{i:02d}.mp3')}'\n")

    combined = os.path.join(out_dir, "combined.mp3")
    subprocess.run([
        "ffmpeg", "-y", "-f", "concat", "-safe", "0",
        "-i", concat_path,
        "-c:a", "libmp3lame", "-q:a", "2", combined,
    ], check=True, capture_output=True)

    dur_s = audio_duration_ms(combined) / 1000
    print(f"  combined.mp3 rebuilt: {dur_s:.1f}s total, {n} steps")
    print(f"  timings.json updated: total_ms={data['total_ms']}")


def main():
    only = None
    if "--only" in sys.argv:
        idx = sys.argv.index("--only")
        only = sys.argv[idx + 1]

    keys = [only] if only else list(CHANGED.keys())

    for key in keys:
        if key not in CHANGED:
            print(f"No changes for: {key}")
            continue

        out_dir = os.path.join(CLIPS, key)
        changed = CHANGED[key]

        print(f"\n── {key} — regenerating {len(changed)} step(s) ──")
        for step_n, (text, is_center, spd_override) in sorted(changed.items()):
            speed = spd_override if spd_override is not None else DEFAULT_SPEED
            clip_path = os.path.join(out_dir, f"step_{step_n:02d}.mp3")
            short = text[:70].replace("\n", "") + ("…" if len(text) > 70 else "")
            print(f"  Step {step_n:2d}: {short!r}  speed={speed}")
            generate_clip(text, speed, clip_path)
            ms = audio_duration_ms(clip_path)
            print(f"           → {ms}ms")

        rebuild_combined(key)

    print("\nDone!")


if __name__ == "__main__":
    main()
