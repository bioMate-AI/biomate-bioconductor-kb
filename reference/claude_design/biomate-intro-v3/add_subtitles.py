#!/usr/bin/env python3
"""
Burn Chinese subtitles into biomate_intro_v3 frames.
Reads /tmp/biomate_intro_frames/, overlays Chinese text,
re-encodes to biomate_intro_v3_zh.mp4.
"""

import os, json, subprocess, shutil
from PIL import Image, ImageDraw, ImageFont

DIR        = os.path.dirname(os.path.abspath(__file__))
FRAMES_IN  = "/tmp/biomate_intro_frames"
FRAMES_OUT = "/tmp/biomate_intro_frames_zh"
AUDIO_DIR  = os.path.join(DIR, "vo_slides")
COMBINED   = os.path.join(DIR, "biomate_intro_v3_vo.mp3")
OUTPUT     = os.path.join(DIR, "biomate_intro_v3_zh.mp4")
FONT_PATH  = "/System/Library/Fonts/PingFang.ttc"
FONT_SIZE  = 40
GAP_MS     = 800

# (dom_idx, audio_file, chinese_subtitle)
# Subtitle text uses \n for line breaks
SLIDES = [
    (0, "01_title.mp3",
     "BioMate——面向生命科学研究的 AI 原生实验室平台"),

    (1, "02_problem.mp3",
     "新药研发动辄需要十二到十五年\n"
     "大量时间耗费在人工流程——测序数据积压、生信瓶颈\n"
     "外包分析费用高达数十万美元，而这些本可在数分钟内完成"),

    (2, "03_solution.mp3",
     "BioMate 以一个智能平台取代整套繁琐流程\n"
     "只需描述研究目标，它便自动匹配经验证的工作流并直接运行"),

    (3, "04_end_to_end.mp3",
     "从靶点识别到 IND 申报\n"
     "六个阶段的计算生物学工作，在一次对话中自动完成\n"
     "全程有据可查，随时可供审查"),

    (5, "05_inside.mp3",
     "底层集成 2,400 个经过验证的生物信息工作流\n"
     "专家级质控体系与完整审计追踪\n"
     "专为科学审查与监管审核而设计"),

    (6, "06_product.mp3",
     "交互方式就是对话\n"
     "上传数据、描述目标，BioMate 自动匹配合适的分析管线\n"
     "无需编写任何代码"),

    (7, "07_differentiator.mp3",
     "每一个结果都有引用依据，每一个步骤都可追溯\n"
     "BioMate 生成的分析，能经受科学审查与监管双重考验"),

    (4, "09_reg_llm.mp3",
     "BioMate 监管 AI 将研究发现转化为申报语言\n"
     "自动生成符合 FDA、EMA 和 ICH 指南的提交文档"),

    (9, "10_closing.mp3",
     "这就是 BioMate——一个会思考、会解释的虚拟实验室\n"
     "从您的第一个问题，到可以自信递交的结果\n"
     "欢迎免费试用，开启您的第一次分析"),
]


def audio_dur_ms(filename):
    path = os.path.join(AUDIO_DIR, filename)
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        capture_output=True, text=True)
    return int(float(r.stdout.strip()) * 1000)


def compute_windows():
    """Return [(start_ms, end_ms, text), ...] for each slide."""
    windows = []
    cursor = 0
    for i, (_, audio_file, text) in enumerate(SLIDES):
        dur_ms = audio_dur_ms(audio_file)
        gap = 500 if i == len(SLIDES) - 1 else GAP_MS
        hold_ms = dur_ms + gap
        windows.append((cursor, cursor + hold_ms, text))
        cursor += hold_ms
    return windows


def draw_subtitle(img, text, font):
    """Overlay subtitle text with semi-transparent background bar."""
    draw = ImageDraw.Draw(img, "RGBA")
    W, H = img.size

    lines = text.split('\n')
    lh = FONT_SIZE + 10  # line height with padding
    text_h = lh * len(lines)
    pad_v, pad_h = 14, 60

    # Background bar
    bar_y1 = H - text_h - pad_v * 2 - 60
    bar_y2 = H - 50
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ov_draw = ImageDraw.Draw(overlay)
    ov_draw.rectangle([(0, bar_y1), (W, bar_y2)], fill=(0, 0, 0, 160))
    img.paste(Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB"))
    draw = ImageDraw.Draw(img)

    # Draw each line centered
    y = bar_y1 + pad_v
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=font)
        lw = bbox[2] - bbox[0]
        x = (W - lw) // 2
        # Thin black outline
        for dx in (-2, 0, 2):
            for dy in (-2, 0, 2):
                if dx or dy:
                    draw.text((x + dx, y + dy), line, font=font, fill=(0, 0, 0, 255))
        draw.text((x, y), line, font=font, fill=(255, 255, 255, 255))
        y += lh


def video_dur_s(path):
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        capture_output=True, text=True)
    return float(r.stdout.strip())


def run():
    with open(os.path.join(FRAMES_IN, "timestamps.json")) as f:
        timestamps = json.load(f)
    n = len(timestamps)
    t0 = timestamps[0]

    windows = compute_windows()
    print("Subtitle windows:")
    for start, end, text in windows:
        print(f"  {start/1000:.1f}–{end/1000:.1f}s  {text[:50]}")

    font = ImageFont.truetype(FONT_PATH, size=FONT_SIZE)

    if os.path.exists(FRAMES_OUT):
        shutil.rmtree(FRAMES_OUT)
    os.makedirs(FRAMES_OUT)

    print(f"\nRendering subtitles on {n} frames...")
    for i, ts in enumerate(timestamps):
        frame_ms = (ts - t0) * 1000
        fin  = os.path.join(FRAMES_IN,  f"frame_{str(i).zfill(5)}.png")
        fout = os.path.join(FRAMES_OUT, f"frame_{str(i).zfill(5)}.png")

        active = next((text for start, end, text in windows
                       if start <= frame_ms < end), None)

        if active:
            img = Image.open(fin).convert("RGB")
            draw_subtitle(img, active, font)
            img.save(fout, format="PNG", optimize=False)
        else:
            shutil.copy(fin, fout)

        if i % 100 == 0 or i == n - 1:
            print(f"  {i+1}/{n}  ({frame_ms/1000:.1f}s)  {'✓ subtitle' if active else '  (no sub)'}")

    shutil.copy(os.path.join(FRAMES_IN, "timestamps.json"),
                os.path.join(FRAMES_OUT, "timestamps.json"))

    # Stitch
    target_ms = windows[-1][1]
    target_s  = target_ms / 1000
    recorded_s = timestamps[-1] - t0

    concat_path = "/tmp/biomate_intro_zh_concat.txt"
    with open(concat_path, "w") as f:
        for i in range(n):
            img = os.path.join(FRAMES_OUT, f"frame_{str(i).zfill(5)}.png")
            dur = (timestamps[i+1] - timestamps[i]) if i < n - 1 else 1/30
            f.write(f"file '{img}'\nduration {dur:.6f}\n")
        f.write(f"file '{os.path.join(FRAMES_OUT, f'frame_{str(n-1).zfill(5)}.png')}'\n")

    stitched  = "/tmp/biomate_intro_zh_stitched.mp4"
    raw_video = "/tmp/biomate_intro_zh_raw.mp4"

    print("\nStitching frames...")
    r = subprocess.run([
        "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", concat_path,
        "-vf", "scale=1920:1080:flags=lanczos,format=yuv420p",
        "-c:v", "h264_videotoolbox", "-b:v", "10M",
        "-t", f"{recorded_s:.3f}", stitched,
    ], capture_output=True)
    if r.returncode != 0:
        print(r.stderr.decode()[-2000:])
        raise RuntimeError("stitch failed")

    actual_s  = video_dur_s(stitched)
    extend_s  = max(0, target_s - actual_s)
    print(f"  Stitched {actual_s:.1f}s, extending {extend_s:.1f}s")

    if extend_s > 0.1:
        r2 = subprocess.run([
            "ffmpeg", "-y", "-i", stitched,
            "-vf", f"tpad=stop_mode=clone:stop_duration={extend_s:.3f}",
            "-c:v", "h264_videotoolbox", "-b:v", "10M",
            "-pix_fmt", "yuv420p", raw_video,
        ], capture_output=True)
        if r2.returncode != 0:
            print(r2.stderr.decode()[-2000:])
            raise RuntimeError("extend failed")
    else:
        shutil.copy(stitched, raw_video)

    print("Merging audio...")
    subprocess.run([
        "ffmpeg", "-y", "-i", raw_video, "-i", COMBINED,
        "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest",
        OUTPUT,
    ], check=True, capture_output=True)

    size_mb = os.path.getsize(OUTPUT) / (1024 * 1024)
    print(f"\nDone! → {OUTPUT}  ({size_mb:.1f} MB)")


if __name__ == "__main__":
    run()
