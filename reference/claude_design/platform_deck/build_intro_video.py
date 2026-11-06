#!/usr/bin/env python3
"""
build_intro_video.py — BioMate PLATFORM intro video (EN + CN): narrated deck
(12 scenes) + a multi-domain E2E demo (RNA-seq hero), 1920x1080, macOS `say`
TTS + ffmpeg. Modeled on scripts/make_tutorial_video.py. No external API.

Deck scenes are pre-captured to video_scenes/<lang>/scene_NN.png (correct
counters). Demo beats reuse real product screenshots from docs/user-manual/
assets. Output: docs/user-manual/videos/biomate-intro.<lang>.mp4.

Usage: python3 build_intro_video.py        # builds both en + zh
"""
import os, subprocess, tempfile, shutil

BASE = "/Users/kky/biomate-review"
DECK = os.path.join(BASE, "reference/claude_design/platform_deck")
ASSETS = os.path.join(BASE, "docs/user-manual/assets")
OUT_DIR = os.path.join(BASE, "docs/user-manual/videos")
FFMPEG = "/Users/kky/opt/anaconda3/bin/ffmpeg"
VOICE = {"en": "Samantha", "zh": "Tingting"}
RATE = {"en": "178", "zh": "205"}

def scene(lang, i): return os.path.join(DECK, f"video_scenes/{lang}/scene_{i:02d}.png")
def asset(name): return os.path.join(ASSETS, name)

DECK_NARRATION = {
  "en": [
    "BioMate — the AI bioinformatics platform. From any instrument and dataset to a reproducible, decision-ready result. Search, run, verify, learn.",
    "Bioinformatics today is fragmented: tools scattered per domain, instruments as islands, expert workflows uncaptured, results that never accumulate, and real data-security pressure.",
    "One platform across every domain, in your own environment — with instrument connectivity, built-in search, unified execution, and private, auditable runs.",
    "Breadth: four thousand two hundred workflows across forty-two domains — transcriptomics, genomics, variants, epigenomics, single-cell, proteomics, cryo-E-M, and more. Drug discovery is just one of them.",
    "From the bench instrument to the analysis in one flow — flow cytometers, plate readers, L-C-M-S, sequencers, cryo-E-M, liquid handlers, and your E-L-N — all with real connectors.",
    "Describe your goal in plain language and BioMate finds the right method — routing across thousands of workflows, resolving accessions, and grounding answers in cited literature.",
    "A project-centric workspace: your chats, data, workflows and runs together — with the workflow panel from parameters, to live phases, to one merged Results report.",
    "Run in the cloud or on-prem, with quality gates that never silently pass a failed result, an auto-loop that remediates and re-runs, and one merged Results report across every domain.",
    "Private deployment by default: data stays in your environment, execution is deterministic, every run is versioned and auditable, and it integrates with your E-L-N and L-I-M-S.",
    "One platform replaces many single-point tools, gets you from data to insight faster, unifies instruments and domains, and turns every run into a reusable, auditable asset.",
    "The deliverable is a reproducible result — findings, every output previewed, a full reproducibility record, and a next step — for any domain.",
    "Getting started is simple: survey your domains and instruments, connect your data, run with quality control, verify against your method, and deploy in your environment.",
  ],
  "zh": [
    "BioMate —— AI 生物信息平台。从任意仪器与数据，到可复现、可决策的结果。检索、运行、验证、学习。",
    "当下的生物信息分析是割裂的：工具按领域分散，仪器成为孤岛，专家工作流难以沉淀，结果不积累，还有真实的数据安全压力。",
    "一个平台，覆盖全领域，部署在你自己的环境——带仪器连接、内置检索、统一执行，以及私域、可审计的运行。",
    "广度：42 个领域、4,210 个工作流——转录组、基因组、变异、表观、单细胞、蛋白质组、冷冻电镜等等。药物发现只是其中之一。",
    "从实验台仪器到分析，一气呵成——流式细胞仪、酶标仪、液质联用、测序仪、冷冻电镜、移液机器人和你的 ELN，都有真实连接器。",
    "用大白话描述目标，BioMate 就能找到正确的方法——在数千个工作流中路由、解析编号，并以带引用的文献为答案提供依据。",
    "以项目为中心的工作台：对话、数据、工作流与运行集中在一起；工作流面板从参数、到实时阶段、再到一份合并的结果报告。",
    "在云端或本地运行，质控门绝不默默放过失败结果，自动循环会调整参数重跑——所有领域共用同一份合并结果报告。",
    "默认私有化部署：数据不出域，执行确定可复现，每次运行都版本化、可审计，并与你的 ELN 和 LIMS 打通。",
    "一个平台替代多套单点软件，从数据到洞见更快，统一仪器与领域，并把每次运行变成可复用、可审计的资产。",
    "交付的是可复现的结果——发现、每个输出的预览、完整的可复现记录，以及下一步建议——适用于任意领域。",
    "开始很简单：调研你的领域与仪器，接入数据，带质控运行，与你的方法对比验证，然后在你的环境中部署。",
  ],
}

DEMO = {
  "en": [
    (asset("i01-1-cold-start.png"), "Here's the platform in action. You describe a goal in plain language, and BioMate routes it to the right workflow."),
    (asset("r2-running.png"),       "Confirm, and it runs on cloud compute — phases and quality gates live, nothing hidden. The same panel works for RNA-seq, variants, proteomics, or an instrument readout."),
    (asset("rnaseq-results.png"),   "When it completes, you get one merged Results report. Here, an RNA-seq differential-expression run on myasthenia-gravis patient cells: twenty-seven differentially expressed genes, each finding traced to its output file."),
    (scene("en", 0),                "The same flow works across every domain and instrument. BioMate: search, run, verify, learn."),
  ],
  "zh": [
    (asset("i01-1-cold-start.png"), "来看平台的实际运行。你用大白话描述目标，BioMate 就把它路由到正确的工作流。"),
    (asset("r2-running.png"),       "确认后，它在云端计算上运行——阶段与质控门实时可见，没有任何隐藏。同一个面板适用于 RNA-seq、变异、蛋白质组，或仪器读出。"),
    (asset("rnaseq-results.png"),   "运行完成，你得到一份合并的结果报告。这里是一次重症肌无力患者细胞的 RNA-seq 差异表达分析：27 个差异表达基因，每个发现都溯源到它的输出文件。"),
    (scene("zh", 0),                "同样的流程适用于每一个领域和仪器。BioMate：检索、运行、验证、学习。"),
  ],
}

def run(cmd): subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def build(lang):
    beats = [(scene(lang, i), DECK_NARRATION[lang][i]) for i in range(12)] + DEMO[lang]
    os.makedirs(OUT_DIR, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="bmintro_")
    segs = []
    try:
        for i, (img, text) in enumerate(beats):
            if not os.path.exists(img):
                raise SystemExit(f"MISSING asset: {img}")
            aiff = os.path.join(tmp, f"b{i}.aiff"); m4a = os.path.join(tmp, f"b{i}.m4a"); seg = os.path.join(tmp, f"seg{i}.mp4")
            run(["say", "-v", VOICE[lang], "-r", RATE[lang], "-o", aiff, text])
            run([FFMPEG, "-y", "-i", aiff, "-c:a", "aac", "-b:a", "160k", m4a])
            vf = ("scale=1920:1080:force_original_aspect_ratio=decrease,"
                  "pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=white,setsar=1,format=yuv420p")
            run([FFMPEG, "-y", "-loop", "1", "-i", img, "-i", m4a, "-c:v", "libopenh264", "-b:v", "3M",
                 "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-vf", vf, "-shortest", seg])
            segs.append(seg); print(f"  [{lang}] beat {i+1}/{len(beats)} ok", flush=True)
        listf = os.path.join(tmp, "list.txt")
        with open(listf, "w") as f:
            for s in segs: f.write(f"file '{s}'\n")
        out = os.path.join(OUT_DIR, f"biomate-intro.{lang}.mp4")
        run([FFMPEG, "-y", "-f", "concat", "-safe", "0", "-i", listf, "-c:v", "libopenh264",
             "-b:v", "3M", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", out])
        print(f"DONE -> {out} ({os.path.getsize(out)/1e6:.1f} MB)", flush=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if __name__ == "__main__":
    for lang in ("en", "zh"):
        build(lang)
