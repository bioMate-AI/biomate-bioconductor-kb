#!/usr/bin/env python3
"""
Condense the verbose ZH narration into brief, informative subtitles using Gemini.

Rules baked into the prompt:
  - One line, ≤ 20 Chinese characters per cue (subtitles must be readable in ~3s)
  - May break into 2 lines (≤ 16 chars each) for long technical content
  - Preserve proper nouns (CryoSPARC, hERG, FDA, §2.6.1, 21 CFR Part 11, EMPIAR-10025, etc.)
  - Drop filler ("让我们", "现在", "你可以看到") — keep the technical content only
  - Each step ⇒ one cue with the same step number

Reads:  reference/claude_design/research_agents/narration/<demo>.zh.md  (literal voiceover)
Writes: reference/claude_design/research_agents/narration/<demo>.zh.subs.md
        (same structure: '## Step N — title' + condensed one/two-line body)
"""
import re, os, sys, pathlib, argparse, time

GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY', 'AIzaSyDoFJyQuwTYsfhoLO4DBL1ME9Ojl7VpFHI')
MODEL = 'gemini-2.5-flash'   # fast condenser

PROMPT = """你是中文字幕压缩助手。把下列中文旁白压缩成 1-2 行字幕。严格规则:

1. 总字数 ≤ 28 个汉字(英文/数字按 1 字计)
2. 最多 2 行,每行 ≤ 16 字;若一句话能讲清就只用 1 行
3. 必须保留专有名词原样:CryoSPARC、hERG、FDA、EMA、NMPA、PMDA、§2.6.1、21 CFR Part 11、EMPIAR-10025、AWS Batch、MotionCor2、CTFFIND4、Topaz、PBPK、ADMET、GP、EHVI、DOCX、SHA-256、TOTP、AUC、Cmax、Ames、DILI 等
4. 提炼"这一步最重要的信息"(技术动作 / 关键数字 / 输出),不要照搬原句
5. 删除一切口语化填充与寒暄:"你好"、"让我们"、"我们一起"、"现在"、"你可以看到"、"接下来"、"注意"、"看这里"
6. 不要句号结尾;两行之间用真实换行,不要写 \\n
7. 只输出字幕文字本身,无引号、无说明、无 Markdown 标记

示例输入:你好。让我们一起完成一次完整的 cryo-EM 单颗粒分析。不需要 CryoSPARC 经验 —— BioMate 会自动配置参数。
示例输出:完整 cryo-EM 单颗粒分析
BioMate 自动配参,零经验

原文:
"""

def parse_narration(path):
    text = pathlib.Path(path).read_text()
    blocks = re.split(r'\n---\n', text.strip())
    out = []
    for b in blocks:
        m = re.search(r'##\s+Step\s+(\d+)\s+[—-]\s+(.+?)\n+(.+)', b.strip(), re.DOTALL)
        if m:
            body = re.sub(r'\s+', ' ', m.group(3).strip())
            out.append({'num': int(m.group(1)), 'title': m.group(2).strip(), 'text': body})
    return out

def condense_one(text: str) -> str:
    from google import genai
    client = genai.Client(api_key=GEMINI_API_KEY)
    resp = client.models.generate_content(
        model=MODEL,
        contents=PROMPT + text,
    )
    out = (resp.text or "").strip()
    # Strip outer quotes if model added them
    out = re.sub(r'^["“”\']+|["“”\']+$', '', out)
    # Replace literal "\n" with newline
    out = out.replace('\\n', '\n')
    # Soft cap: keep up to 2 lines × 18 chars (preserve content; truncate only if grossly over)
    lines = [l.strip() for l in out.split('\n') if l.strip()][:2]
    lines = [l[:18] if len(l) > 18 else l for l in lines]
    return '\n'.join(lines)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in',  dest='inp', required=True)
    ap.add_argument('--out',                required=True)
    args = ap.parse_args()

    steps = parse_narration(args.inp)
    print(f"Parsed {len(steps)} steps from {args.inp}", flush=True)

    out_lines = [f"# {pathlib.Path(args.inp).stem} (subs)", ""]
    for s in steps:
        try:
            brief = condense_one(s['text'])
        except Exception as e:
            print(f"  step {s['num']}: ERROR {e}", file=sys.stderr)
            brief = s['text'][:20]
        ch_count = len(brief.replace('\n', ''))
        print(f"  step {s['num']:>2}: {ch_count:>2}ch  {brief[:40]}")
        out_lines.append(f"## Step {s['num']} — {s['title']}")
        out_lines.append("")
        out_lines.append(brief)
        out_lines.append("")
        out_lines.append("---")
        out_lines.append("")
        time.sleep(0.3)   # gentle pacing

    pathlib.Path(args.out).write_text("\n".join(out_lines).rstrip() + "\n")
    print(f"\nWrote {args.out}")

if __name__ == "__main__":
    main()
