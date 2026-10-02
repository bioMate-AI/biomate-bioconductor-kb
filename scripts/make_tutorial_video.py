#!/usr/bin/env python3
"""
make_tutorial_video.py — build a narrated walkthrough video for a BioMate layman
tutorial from REAL screenshots + macOS `say` TTS + ffmpeg.

No external API / key: uses the built-in `say` voice (Samantha for EN, Tingting
for ZH). Each beat = (screenshot, narration). Each beat becomes a video segment
that holds the screenshot for the length of its narration; segments are
concatenated into one MP4 at 1920x1080 on a white canvas.

Usage:
  python3 scripts/make_tutorial_video.py T3 en
  python3 scripts/make_tutorial_video.py T3 zh
"""
import os, sys, subprocess, tempfile, shutil

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(BASE, "docs/user-manual/assets")
OUT_DIR = os.path.join(BASE, "docs/user-manual/videos")
VOICE = {"en": "Samantha", "zh": "Tingting"}
RATE = {"en": "180", "zh": "210"}

# Beats per tutorial per language: (screenshot filename, narration text)
BEATS = {
  "T3": {
    "en": [
      ("t3-1-workflow-panel.png",
       "Most real analysis is not one step, but a pipeline. A workflow in BioMate is one of these "
       "pipelines, already tested and connected for you. Here is a completed run: an in-vivo CAR-T co-design."),
      ("t3-1-workflow-panel.png",
       "You describe your goal in plain English. BioMate picks the right validated workflow, shows you "
       "the settings before anything runs, and then runs the whole pipeline on cloud computers."),
      ("t3-3-after-run-outputs.png",
       "When it finishes, the Outputs tab lists every file the run produced, grouped by the step that "
       "made it. Here, eleven files across four phases. You can view, download, or open any of them."),
      ("t3-4-after-run-reproducibility.png",
       "The reproducibility record is the complete, downloadable account of the run: its parameters, "
       "software versions, and every output with a checksum. This is what makes a result defensible."),
      ("t3-2-after-run-summary.png",
       "And when BioMate cannot read the output files, it withholds the findings and says so, rather "
       "than inventing a summary. That honesty is the point."),
      ("t3-1-workflow-panel.png",
       "That is the everyday loop: describe a goal, review the settings, run, and read a result you can "
       "trust and reproduce."),
    ],
    "zh": [
      ("t3-1-workflow-panel.png",
       "大多数真实的分析都不是一步，而是一条流程。BioMate 里的工作流就是这样一条已经测试并连接好的流程。"
       "这是一次已完成的运行：一次体内 CAR-T 共同设计。"),
      ("t3-1-workflow-panel.png",
       "你用大白话描述目标，BioMate 选出正确的、经过验证的工作流，在运行前把设置展示给你，然后在云端计算机上运行整条流程。"),
      ("t3-3-after-run-outputs.png",
       "运行结束后，输出标签页按产生文件的步骤列出每一个文件 —— 这里是四个阶段共十一个文件。你可以查看、下载或打开其中任何一个。"),
      ("t3-4-after-run-reproducibility.png",
       "可复现记录是对这次运行的完整、可下载的说明：参数、软件版本，以及每个带校验和的输出。正是这一点让结果站得住脚。"),
      ("t3-2-after-run-summary.png",
       "而当 BioMate 读不到输出文件时，它会把发现按下不表并如实说明，而不是编造一段摘要。这份如实正是关键。"),
      ("t3-1-workflow-panel.png",
       "这就是日常的循环：描述目标、审阅设置、运行，然后读到一个你可以信任、也可以复现的结果。"),
    ],
  },
  "T2": {
    "en": [
      ("i10-1-models.png",
       "The Models area is where BioMate learns from your results. A model turns data into a prediction. "
       "Here are the models in your workspace."),
      ("i10-2-registry.png",
       "Every model is listed in the registry, with where it is used, so you always know which model "
       "produced which result."),
      ("i10-3-model-object.png",
       "Open a model and you see what it was trained on, how it did on held-out data it never saw, and "
       "whether it applies to your molecule."),
      ("i10-4-rounds.png",
       "This is the closed loop: design candidates, test them, feed the results back, and the next round "
       "improves. Each round is recorded, and nothing is overwritten."),
    ],
    "zh": [
      ("i10-1-models.png",
       "模型区是 BioMate 从你的结果中学习的地方。模型把数据变成预测。这里是你工作区里的模型。"),
      ("i10-2-registry.png",
       "每个模型都登记在注册表里，并标明它被用在哪里，于是你始终知道是哪个模型产生了哪个结果。"),
      ("i10-3-model-object.png",
       "打开一个模型，你能看到它用什么训练、在它从未见过的留出数据上表现如何，以及它是否适用于你的分子。"),
      ("i10-4-rounds.png",
       "这就是闭环：设计候选、测试它们、把结果反馈回来，下一轮就更好。每一轮都有记录，且什么都不会被覆盖。"),
    ],
  },
  "T4": {
    "en": [
      ("i05-0-data-hub.png",
       "BioMate treats your data as the centre everything connects to. The Data hub is where your files "
       "live, each opened as a dataset object."),
      ("i05-1-file-tree.png",
       "Bring a file in and it appears under inputs, with a small quality dot: green, amber, red, or grey "
       "for a type that is not profiled."),
      ("i05-2-dataset-header.png",
       "Click a file and it opens as a dataset object: its type, size, a quality verdict, and a version "
       "count, all in one place."),
      ("i05-3-quality-tab.png",
       "The quality tab shows what BioMate actually read in your data. Here a FASTQ flagged watch, with "
       "its read quality and a plain note on what to do."),
    ],
    "zh": [
      ("i05-0-data-hub.png",
       "BioMate 把你的数据当作一切围绕的中心。数据中心是你的文件所在之处，每个文件都作为一个数据集对象打开。"),
      ("i05-1-file-tree.png",
       "把一个文件带进来，它会出现在 inputs 下，带一个小小的质量圆点：绿、黄、红，或表示未剖析类型的灰色。"),
      ("i05-2-dataset-header.png",
       "点开一个文件，它会作为数据集对象打开：类型、大小、质量判定和版本计数，都集中在一处。"),
      ("i05-3-quality-tab.png",
       "质量标签页显示 BioMate 真正读到了你数据里的什么。这里是一个被标为留意的 FASTQ，附带它的读段质量和一条该怎么做的朴素提示。"),
    ],
  },
}

def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def main():
    if len(sys.argv) < 3:
        print("usage: make_tutorial_video.py <KEY> <en|zh>"); sys.exit(1)
    key, lang = sys.argv[1], sys.argv[2]
    beats = BEATS.get(key, {}).get(lang)
    if not beats:
        print(f"no beats defined for {key}/{lang}"); sys.exit(1)
    os.makedirs(OUT_DIR, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="bmvid_")
    segs = []
    try:
        for i, (img, text) in enumerate(beats):
            img_path = os.path.join(ASSETS, img)
            if not os.path.exists(img_path):
                print(f"MISSING asset: {img_path}"); sys.exit(1)
            aiff = os.path.join(tmp, f"b{i}.aiff")
            m4a = os.path.join(tmp, f"b{i}.m4a")
            seg = os.path.join(tmp, f"seg{i}.mp4")
            run(["say", "-v", VOICE[lang], "-r", RATE[lang], "-o", aiff, text])
            run(["ffmpeg", "-y", "-i", aiff, "-c:a", "aac", "-b:a", "160k", m4a])
            vf = ("scale=1920:1080:force_original_aspect_ratio=decrease,"
                  "pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=white,setsar=1,format=yuv420p")
            run(["ffmpeg", "-y", "-loop", "1", "-i", img_path, "-i", m4a,
                 "-c:v", "libopenh264", "-b:v", "3M", "-pix_fmt", "yuv420p",
                 "-c:a", "aac", "-b:a", "160k", "-vf", vf, "-shortest", seg])
            segs.append(seg)
            print(f"  beat {i+1}/{len(beats)} ok")
        listf = os.path.join(tmp, "list.txt")
        with open(listf, "w") as f:
            for s in segs:
                f.write(f"file '{s}'\n")
        out = os.path.join(OUT_DIR, f"{key}-tutorial.{lang}.mp4")
        run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", listf,
             "-c:v", "libopenh264", "-b:v", "3M", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", out])
        size = os.path.getsize(out) / 1e6
        print(f"DONE -> {out} ({size:.1f} MB)")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if __name__ == "__main__":
    main()
