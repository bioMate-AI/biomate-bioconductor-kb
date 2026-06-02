#!/usr/bin/env python3
"""
Generate BioMate Story voiceover using ElevenLabs (Rachel voice).
Produces one combined MP3 with silence padding to match HTML scene timings.
"""

import os, subprocess, json, requests, tempfile, shutil

API_KEY  = "sk_f850eae3cd4b254613c81e3b9a7d448a6924f4789e1233a4"
VOICE_ID = "21m00Tcm4TlvDq8ikWAM"   # Rachel
OUT_DIR  = os.path.dirname(os.path.abspath(__file__))

# (text, scene_dur_ms, speed_override or None)
# Default speed = 0.80; last scene gets 0.72 for extra weight
SCENES = [
    ("Every discovery begins with a question.",                                                                8000,  None),
    ("But in the lab, the answer can take weeks — lost in queues, handoffs, and six-figure CRO invoices.",    9000,  None),
    ("What if the lab could think alongside you?",                                                             9000,  None),
    ("With BioMate, you ask in plain language — and it maps your question to a validated, expert-grade workflow.", 9000, None),
    ("From target discovery to a regulatory submission package — six stages of computational work, handled in one conversation.", 10000, None),
    ("Every result stays traceable. Every number stays citable — built to survive scientific and regulatory review.", 10000, None),
    ("Thousands of validated workflows, quality-controlled at every step. Science you can stand behind.",      9000,  None),
    ("A virtual lab that thinks — and shows its work.",                                                        8000,  None),
    ("BioMate.",                                                                                               7000,  0.72),
    ("From question to defensible result.",                                                                    7000,  0.72),
    ("Start your free trial at biomate dot ai.",                                                               7000,  0.78),
]

DEFAULT_SPEED   = 0.80
TRIM_GAP_MS     = 1400   # silence between scenes in trim mode
LAST_TRAIL_MS   = 5000   # extra silence after the final scene

def audio_duration_ms(path):
    """Return audio duration in milliseconds via ffprobe."""
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "json", path],
        capture_output=True, text=True
    )
    data = json.loads(result.stdout)
    return int(float(data["format"]["duration"]) * 1000)

def generate_clip(text, index, tmpdir, voice_id=VOICE_ID, speed=DEFAULT_SPEED):
    """Call ElevenLabs TTS and save MP3 to tmpdir."""
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
    headers = {
        "xi-api-key": API_KEY,
        "Content-Type": "application/json",
    }
    payload = {
        "text": text,
        "model_id": "eleven_multilingual_v2",
        "voice_settings": {
            "stability": 0.45,
            "similarity_boost": 0.80,
            "style": 0.20,
            "use_speaker_boost": True,
        },
        "speed": speed,
    }
    resp = requests.post(url, headers=headers, json=payload)
    resp.raise_for_status()
    path = os.path.join(tmpdir, f"scene_{index:02d}.mp3")
    with open(path, "wb") as f:
        f.write(resp.content)
    print(f"  Scene {index}: generated ({len(resp.content)//1024}KB)")
    return path

def slow_clip(path, ratio, tmpdir, index):
    """Stretch audio by ratio (e.g. 0.7 = 70% speed) using ffmpeg atempo."""
    out = os.path.join(tmpdir, f"slow_{index:02d}.mp3")
    # atempo range is 0.5–2.0
    subprocess.run([
        "ffmpeg", "-y", "-i", path,
        "-filter:a", f"atempo={ratio:.3f}",
        "-q:a", "2", out,
    ], capture_output=True, check=True)
    return out

def make_silence(duration_ms, index, tmpdir):
    """Generate a silent MP3 of given duration."""
    path = os.path.join(tmpdir, f"silence_{index:02d}.mp3")
    subprocess.run([
        "ffmpeg", "-y", "-f", "lavfi",
        "-i", f"anullsrc=r=44100:cl=mono",
        "-t", str(duration_ms / 1000),
        "-q:a", "2", path
    ], capture_output=True)
    return path

def main(trim=False, voice_id=VOICE_ID, label=""):
    """
    trim=False → pad each clip to fill its full scene slot (sync with HTML)
    trim=True  → fixed gaps between scenes, no dead air
    """
    tmpdir = tempfile.mkdtemp(prefix="biomate_vo_")
    try:
        segments = []

        # Last three entries are the closing sequence on scene 9
        # SCENES[-3] = "BioMate."
        # SCENES[-2] = "From question to defensible result."
        # SCENES[-1] = "Start your free trial..."
        CLOSING_START_IDX = len(SCENES) - 2   # index of "From question..." (second-to-last)
        CLOSING_PAUSE_MS  = 900               # gap between "BioMate." and "From question..."
        CLOSING_GAP_MS    = 800               # gap between "From question..." and free trial
        CLOSING_SLOW      = 0.72              # additional atempo stretch for "BioMate." + "From question..."

        for i, (text, scene_dur_ms, spd_override) in enumerate(SCENES, start=1):
            short = f"\"{text[:50]}...\"" if len(text) > 50 else f"\"{text}\""
            print(f"\nScene {i}/{len(SCENES)}: {short}")

            speed = spd_override if spd_override is not None else DEFAULT_SPEED
            clip = generate_clip(text, i, tmpdir, voice_id=voice_id, speed=speed)
            clip_ms = audio_duration_ms(clip)
            print(f"  Audio: {clip_ms}ms  |  speed={speed}")

            # Stretch "BioMate." and "From question..." via atempo
            is_biomate_line   = (i == len(SCENES) - 2)   # "BioMate."
            is_fromq_line     = (i == len(SCENES) - 1)   # "From question..."
            is_freetrial_line = (i == len(SCENES))        # "Start your free trial..."
            is_last           = is_freetrial_line

            if is_biomate_line or is_fromq_line:
                clip = slow_clip(clip, CLOSING_SLOW, tmpdir, i)
                clip_ms = audio_duration_ms(clip)
                print(f"  Stretched: {clip_ms}ms after atempo={CLOSING_SLOW}")

            segments.append(clip)

            if trim:
                if is_biomate_line:
                    segments.append(make_silence(CLOSING_PAUSE_MS, i, tmpdir))
                    print(f"  Closing pause: +{CLOSING_PAUSE_MS}ms")
                elif is_fromq_line:
                    segments.append(make_silence(CLOSING_GAP_MS, i, tmpdir))
                    print(f"  Gap before free trial: +{CLOSING_GAP_MS}ms")
                elif is_last:
                    segments.append(make_silence(LAST_TRAIL_MS, i, tmpdir))
                    print(f"  Trailing: +{LAST_TRAIL_MS}ms (end)")
                else:
                    segments.append(make_silence(TRIM_GAP_MS, i, tmpdir))
                    print(f"  Padded: +{TRIM_GAP_MS}ms gap")
            else:
                pad_ms = scene_dur_ms - clip_ms
                if pad_ms > 100:
                    silence = make_silence(pad_ms, i, tmpdir)
                    segments.append(silence)
                    print(f"  Padded: +{pad_ms}ms silence")
                elif pad_ms < -200:
                    print(f"  WARNING: VO runs {-pad_ms}ms over scene slot")

        concat_file = os.path.join(tmpdir, "concat.txt")
        with open(concat_file, "w") as f:
            for seg in segments:
                f.write(f"file '{seg}'\n")

        out_path = os.path.join(OUT_DIR, f"biomate_story_vo_{label}.mp3")
        subprocess.run([
            "ffmpeg", "-y", "-f", "concat", "-safe", "0",
            "-i", concat_file,
            "-c:a", "libmp3lame", "-q:a", "2",
            out_path
        ], check=True, capture_output=True)

        total_ms = audio_duration_ms(out_path)
        print(f"\nDone! → {out_path}")
        print(f"Total duration: {total_ms/1000:.1f}s")

    finally:
        shutil.rmtree(tmpdir)

if __name__ == "__main__":
    import sys
    trim = "--trim" in sys.argv
    voice = "adam" if "--adam" in sys.argv else "rachel"

    VOICES = {
        "rachel": "21m00Tcm4TlvDq8ikWAM",
        "adam":   "pNInz6obpgDQGcFmaJgB",
    }
    main(trim=trim, voice_id=VOICES[voice], label=f"{voice}_v4" if trim else voice)

