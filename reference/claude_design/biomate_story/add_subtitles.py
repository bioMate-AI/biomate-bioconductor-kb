#!/usr/bin/env python3
"""
Burn Chinese subtitles into BioMate Story video using PIL overlays + ffmpeg.
Also generates a Chinese-audio version via ElevenLabs.
"""

import os, subprocess, requests, tempfile, shutil
from PIL import Image, ImageDraw, ImageFont

BASE   = os.path.dirname(os.path.abspath(__file__))
INPUT  = os.path.join(BASE, "biomate_story_final.mp4")
OUT_ZH_SUB  = os.path.join(BASE, "biomate_story_zh_subtitles.mp4")
OUT_ZH_AUDIO = os.path.join(BASE, "biomate_story_zh_audio.mp4")

FONT_PATH = "/System/Library/Fonts/PingFang.ttc"
API_KEY   = "sk_f850eae3cd4b254613c81e3b9a7d448a6924f4789e1233a4"
VOICE_ID  = "21m00Tcm4TlvDq8ikWAM"   # Rachel (multilingual — handles Chinese)

W, H = 1920, 1080

# Scene durations (ms)
SCENE_DURS_MS = [
    2351 + 1400, 7836 + 1400, 2403 + 1400, 7000 + 1400,
    7967 + 1400, 7235 + 1400, 7183 + 1400, 3108 + 1400,
    1384 + 900 + 3004 + 5000,
]
CLIP_MS = [2351, 7836, 2403, 7000, 7967, 7235, 7183, 3108]

starts = [0]
for d in SCENE_DURS_MS[:-1]:
    starts.append(starts[-1] + d)

S9_START  = starts[8]
S9B_START = S9_START + 1384 + 900

# Subtitle events: (start_ms, end_ms, text, dark_bg)
# dark_bg=True → white text; False → dark navy text (cream scenes)
EVENTS = [
    (starts[0], starts[0]+CLIP_MS[0], "每一个发现，都始于一个问题。",               True),
    (starts[1], starts[1]+CLIP_MS[1], "但在实验室里，答案可能需要数周\n——淹没在排队、交接和高额外包费用中。", True),
    (starts[2], starts[2]+CLIP_MS[2], "如果实验室能与你并肩思考呢？",               True),
    (starts[3], starts[3]+CLIP_MS[3], "有了 BioMate，你用自然语言提问\n它为你匹配经过验证的专家级工作流。", False),
    (starts[4], starts[4]+CLIP_MS[4], "从靶点发现到法规申报\n六个计算阶段，在一次对话中全部完成。",    True),
    (starts[5], starts[5]+CLIP_MS[5], "每一个结果都可追溯，每一个数字都可引用\n经得起科学与法规的双重审查。", True),
    (starts[6], starts[6]+CLIP_MS[6], "数千个经过验证的工作流\n每一步都有质量把关。科学，值得信赖。",   False),
    (starts[7], starts[7]+CLIP_MS[7], "一个会思考的虚拟实验室——并展示它的工作过程。",           False),
    (S9_START,  S9_START+1384,        "BioMate。",                           False),
    (S9B_START, S9B_START+3004,       "从问题，到可验证的结果。",                     False),
]

CHINESE_NARRATION = [
    "每一个发现，都始于一个问题。",
    "但在实验室里，答案可能需要数周——淹没在排队、交接和高额外包费用中。",
    "如果实验室能与你并肩思考呢？",
    "有了 BioMate，你用自然语言提问——它为你匹配经过验证的专家级工作流。",
    "从靶点发现到法规申报——六个计算阶段，在一次对话中全部完成。",
    "每一个结果都可追溯，每一个数字都可引用——经得起科学与法规的双重审查。",
    "数千个经过验证的工作流，每一步都有质量把关。科学，值得信赖。",
    "一个会思考的虚拟实验室——并展示它的工作过程。",
    "BioMate。",
    "从问题，到可验证的结果。",
]


# ── Part 1: Subtitle overlay video ───────────────────────────────────────────

def make_subtitle_png(text, dark_bg, index, tmpdir):
    """Render Chinese subtitle text as transparent PNG."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT_PATH, 54)

    color     = (255, 250, 238, 255) if dark_bg else (20, 40, 58, 255)
    outline   = (20,  40,  58, 180) if dark_bg else (255, 255, 255, 180)

    lines = text.split("\n")
    line_h = 70
    total_h = len(lines) * line_h
    y_base  = H - 110 - total_h

    for li, line in enumerate(lines):
        bb = draw.textbbox((0, 0), line, font=font)
        tw = bb[2] - bb[0]
        x  = (W - tw) // 2
        y  = y_base + li * line_h
        # Outline
        for dx, dy in [(-2,-2),(-2,2),(2,-2),(2,2),(-2,0),(2,0),(0,-2),(0,2)]:
            draw.text((x+dx, y+dy), line, font=font, fill=outline)
        draw.text((x, y), line, font=font, fill=color)

    path = os.path.join(tmpdir, f"sub_{index:02d}.png")
    img.save(path, "PNG")
    return path

def build_subtitle_video(tmpdir):
    print("  Generating subtitle PNGs...")
    pngs = [make_subtitle_png(t, d, i, tmpdir) for i,(s,e,t,d) in enumerate(EVENTS)]

    # Build ffmpeg filter_complex: chain overlays with time enable
    inputs = ["-i", INPUT]
    for p in pngs:
        inputs += ["-i", p]

    fc_parts = []
    prev = "[0:v]"
    for i, ((start_ms, end_ms, _, __), png) in enumerate(zip(EVENTS, pngs)):
        s = start_ms / 1000
        e = end_ms   / 1000
        out = f"[v{i+1}]" if i < len(EVENTS)-1 else "[vout]"
        fc_parts.append(f"{prev}[{i+1}:v]overlay=0:0:enable='between(t,{s:.3f},{e:.3f})'{out}")
        prev = out

    fc = ";".join(fc_parts)
    cmd = [
        "ffmpeg", "-y",
        *inputs,
        "-filter_complex", fc,
        "-map", "[vout]", "-map", "0:a",
        "-c:v", "h264_videotoolbox", "-b:v", "10M",
        "-c:a", "copy",
        OUT_ZH_SUB,
    ]
    result = subprocess.run(cmd, capture_output=True)
    if result.returncode != 0:
        print(result.stderr.decode()[-2000:])
        raise RuntimeError("subtitle burn failed")
    print(f"  → {OUT_ZH_SUB}  ({os.path.getsize(OUT_ZH_SUB)//1024//1024} MB)")


# ── Part 2: Chinese audio video ──────────────────────────────────────────────

def generate_zh_audio(tmpdir):
    print("  Generating Chinese audio clips...")
    clips, silences = [], []

    GAPS    = [1400]*8 + [900]   # gap after each line except last
    TRAILS  = [0]*9 + [5000]     # trail after last line

    def tts(text, idx, speed=0.80):
        url = f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}"
        resp = requests.post(url,
            headers={"xi-api-key": API_KEY, "Content-Type": "application/json"},
            json={"text": text, "model_id": "eleven_multilingual_v2",
                  "voice_settings": {"stability":0.45,"similarity_boost":0.80,
                                     "style":0.20,"use_speaker_boost":True},
                  "speed": speed})
        resp.raise_for_status()
        p = os.path.join(tmpdir, f"zh_{idx:02d}.mp3")
        with open(p, "wb") as f: f.write(resp.content)
        return p

    def silence(ms, idx):
        p = os.path.join(tmpdir, f"sil_{idx:02d}.mp3")
        subprocess.run(["ffmpeg","-y","-f","lavfi","-i","anullsrc=r=44100:cl=mono",
                        "-t",str(ms/1000),"-q:a","2",p], capture_output=True)
        return p

    segments = []
    for i, text in enumerate(CHINESE_NARRATION):
        spd = 0.72 if i >= 8 else 0.80
        clip = tts(text, i, speed=spd)
        segments.append(clip)
        print(f"    Line {i+1}/{len(CHINESE_NARRATION)}: done")

        # Stretch closing lines
        if i >= 8:
            stretched = os.path.join(tmpdir, f"zh_slow_{i:02d}.mp3")
            subprocess.run(["ffmpeg","-y","-i",clip,"-filter:a","atempo=0.72",
                            "-q:a","2",stretched], capture_output=True, check=True)
            segments[-1] = stretched

        gap = GAPS[i] if i < len(GAPS) else 0
        trail = TRAILS[i] if i < len(TRAILS) else 0
        if gap:   segments.append(silence(gap, i*10+1))
        if trail: segments.append(silence(trail, i*10+2))

    # Concat
    concat = os.path.join(tmpdir, "zh_concat.txt")
    with open(concat, "w") as f:
        for s in segments:
            f.write(f"file '{s}'\n")
    audio_out = os.path.join(tmpdir, "zh_audio.mp3")
    subprocess.run(["ffmpeg","-y","-f","concat","-safe","0","-i",concat,
                    "-c:a","libmp3lame","-q:a","2",audio_out],
                   check=True, capture_output=True)
    return audio_out

def build_zh_audio_video(audio_path):
    subprocess.run([
        "ffmpeg", "-y",
        "-i", INPUT,
        "-i", audio_path,
        "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
        "-map", "0:v", "-map", "1:a",
        "-shortest",
        OUT_ZH_AUDIO,
    ], check=True, capture_output=True)
    print(f"  → {OUT_ZH_AUDIO}  ({os.path.getsize(OUT_ZH_AUDIO)//1024//1024} MB)")


# ── Main ─────────────────────────────────────────────────────────────────────

def run():
    tmpdir = tempfile.mkdtemp(prefix="biomate_zh_")
    try:
        print("══ Part 1: Chinese subtitles ══")
        build_subtitle_video(tmpdir)

        print("\n══ Part 2: Chinese audio ══")
        audio = generate_zh_audio(tmpdir)
        build_zh_audio_video(audio)

        print("\nAll done!")
    finally:
        shutil.rmtree(tmpdir)

if __name__ == "__main__":
    run()
