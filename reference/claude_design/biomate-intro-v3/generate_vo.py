#!/usr/bin/env python3
"""
Generate BioMate Intro v3 voiceover using ElevenLabs (Rachel voice).
Slide order matches the HTML deck exactly.
Slide 08 (Benchmarks) has no VO per direction notes.
Produces per-slide MP3s + one combined file (800ms gap between slides).
"""

import os
import subprocess
import json
import tempfile
import shutil
import requests

API_KEY = "sk_f850eae3cd4b254613c81e3b9a7d448a6924f4789e1233a4"
VOICE_ID = "21m00Tcm4TlvDq8ikWAM"  # Rachel
OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))
SLIDES_DIR = os.path.join(OUTPUT_DIR, "vo_slides")
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "biomate_intro_v3_vo.mp3")
GAP_MS = 800  # inter-slide silence in combined file

# Order matches HTML deck (data-deck-slide 0–9).
# Slide 08 Benchmarks intentionally omitted per direction notes.
SLIDES = [
    ("01_title",
     "Hi, I'm Yaoyun Zhang, founder of BioMate — "
     "an AI platform for pharma, biotech, and life sciences. "
     "A virtual lab that thinks, and shows its work."),

    ("02_problem",
     "Computational work is the bottleneck at every drug development stage. "
     "A single analysis takes days. ADMET profiling takes weeks through a CRO. "
     "And general-purpose AI doesn't help — it hallucinates configurations, skips QC standards, "
     "and leaves no audit trail. Slow cycles. Six-figure overhead. Indefensible results."),

    ("03_solution",
     "With BioMate, you describe your objective in plain language. "
     "It maps it to a validated workflow — you review and approve before anything runs — "
     "then delivers an audit-ready result. Minutes, not days."),

    ("04_end_to_end",
     "Take drug discovery as an example. All six stages — from target identification to the IND narrative — "
     "inside one conversation. Automated and fully traceable, "
     "with every step written to a complete audit trail. "
     "And that same end-to-end capability applies across any domain BioMate supports."),

    ("05_inside",
     "Inside the product: one workspace from first query to final report. "
     "Planning, research agent, reports, and audit log — all in the same conversation. "
     "Continuous session, end-to-end citations, tamper-evident ledger."),

    ("06_product",
     "BioMate covers the full biomedical computation stack — "
     "drug discovery is one example, but the platform spans genomics and multi-omics, "
     "structural biology, and regulatory output as well. "
     "Thousands of validated workflows across dozens of domains. One platform."),

    ("07_differentiator",
     "Every QC decision is citable. "
     "Three named, sourced evidence tiers — Gold, Silver, and Bronze. "
     "Every threshold traceable to a paper or consensus standard. "
     "So when a reviewer asks why a number passed, "
     "you have an answer that survives scrutiny."),

    # Slide 08 Benchmarks: no VO

    ("09_reg_llm",
     "BioMate includes a proprietary regulatory writer that improves with use. "
     "It drafts your IND sections, your experts redline them, "
     "and every correction becomes training signal. "
     "Fewer edits per section over time — and a faster path to a signed packet."),

    ("10_closing",
     "That's BioMate — a virtual lab that thinks, and shows its work. "
     "From your first question to a result you can defend. "
     "We'd love to show you what it can do for your team."),
]


def audio_duration_ms(path: str) -> int:
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", path],
        capture_output=True, text=True
    )
    return int(float(json.loads(result.stdout)["format"]["duration"]) * 1000)


def generate_slide_audio(text: str, out_path: str) -> int:
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}"
    headers = {"xi-api-key": API_KEY, "Content-Type": "application/json", "Accept": "audio/mpeg"}
    payload = {
        "text": text,
        "model_id": "eleven_multilingual_v2",
        "voice_settings": {
            "stability": 0.30,
            "similarity_boost": 0.75,
            "style": 0.40,
            "use_speaker_boost": True,
        },
    }
    resp = requests.post(url, json=payload, headers=headers, timeout=60)
    resp.raise_for_status()
    with open(out_path, "wb") as f:
        f.write(resp.content)
    return audio_duration_ms(out_path)


def make_silence(duration_ms: int, out_path: str) -> None:
    subprocess.run(
        ["ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
         "-t", str(duration_ms / 1000), "-acodec", "libmp3lame", "-q:a", "4", out_path],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def main():
    os.makedirs(SLIDES_DIR, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="biomate_vo_")

    try:
        silence_path = os.path.join(tmp, "silence.mp3")
        make_silence(GAP_MS, silence_path)

        slide_files = []
        print(f"Generating {len(SLIDES)} slides...\n")
        for name, text in SLIDES:
            # Save per-slide file directly to SLIDES_DIR
            out = os.path.join(SLIDES_DIR, f"{name}.mp3")
            dur_ms = generate_slide_audio(text, out)
            print(f"  {name}: {dur_ms/1000:.1f}s")
            slide_files.append(out)

        # Combined file
        filelist = os.path.join(tmp, "filelist.txt")
        with open(filelist, "w") as f:
            for i, sf in enumerate(slide_files):
                f.write(f"file '{sf}'\n")
                if i < len(slide_files) - 1:
                    f.write(f"file '{silence_path}'\n")

        subprocess.run(
            ["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", filelist,
             "-acodec", "libmp3lame", "-q:a", "4", OUTPUT_FILE],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

        total_ms = audio_duration_ms(OUTPUT_FILE)
        print(f"\nDone!")
        print(f"  Per-slide files → {SLIDES_DIR}/")
        print(f"  Combined file   → {OUTPUT_FILE}")
        print(f"  Total duration  : {total_ms/1000:.1f}s  ({total_ms//60000}m {(total_ms%60000)//1000}s)")

    finally:
        shutil.rmtree(tmp)


if __name__ == "__main__":
    main()
