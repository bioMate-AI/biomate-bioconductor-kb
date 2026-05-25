#!/usr/bin/env python3
"""
Split the combined EN / ZH narrative docs into per-demo narration files
in gemini-tts format (## Step N — title  +  body  +  ---).

Reads:
  reference/claude_design/research_agents/Demo Narratives.md     (EN, 4 sections)
  reference/claude_design/research_agents/Demo Narratives ZH.md  (ZH, 4 sections)

Writes (8 files):
  reference/claude_design/research_agents/narration/ra-cryo.en.md
  reference/claude_design/research_agents/narration/ra-cryo.zh.md
  reference/claude_design/research_agents/narration/ra-afterrun.en.md
  reference/claude_design/research_agents/narration/ra-afterrun.zh.md
  reference/claude_design/research_agents/narration/ra-drugscreen.en.md
  reference/claude_design/research_agents/narration/ra-drugscreen.zh.md
  reference/claude_design/research_agents/narration/ind.en.md
  reference/claude_design/research_agents/narration/ind.zh.md
"""
import re, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC_DIR = ROOT / "reference/claude_design/research_agents"
OUT_DIR = SRC_DIR / "narration"
OUT_DIR.mkdir(exist_ok=True)

DEMOS = [
    # (section_index, demo_id)
    (1, "ra-cryo"),
    (2, "ra-afterrun"),
    (3, "ra-drugscreen"),
    (4, "ind"),
]

def split_sections(text: str) -> dict[int, str]:
    """Return {section_num: section_body}. Sections delimited by '^## N · ...' or '^## N · ...'."""
    parts = re.split(r'\n(?=## \d+\s*[·\.]\s)', text)
    out = {}
    for p in parts:
        m = re.match(r'## (\d+)\s*[·\.]\s', p)
        if m:
            out[int(m.group(1))] = p
    return out

def extract_steps(section_text: str) -> list[tuple[int, str, str]]:
    """
    Extract step blocks. Source format uses lines like:
      **[Step N — Title]** *(optional stage direction)*
      "Body text..."
    Returns list of (n, title, body).
    """
    steps = []
    # Match: **[Step N — Title]** optional-suffix\n\n"body"
    pattern = re.compile(
        r'\*\*\[\s*(?:Step|步骤|第)\s*(\d+)\s*(?:步)?\s*[—\-]\s*([^\]]+)\]\*\*'
        r'[^\n]*\n+'                # rest of header line (stage directions, scrolls...)
        r'((?:[^\n]+\n?)+?)'        # body (one or more lines)
        r'(?=\n\*\*\[|\n## |\n---|\Z)',
        re.MULTILINE
    )
    for m in pattern.finditer(section_text):
        num = int(m.group(1))
        title = m.group(2).strip()
        body = m.group(3).strip()
        # Strip leading/trailing quotes
        body = re.sub(r'^["“”]+', '', body)
        body = re.sub(r'["“”]+$', '', body)
        # Collapse internal newlines into spaces
        body = re.sub(r'\s+', ' ', body).strip()
        steps.append((num, title, body))
    return steps

def to_tts_md(steps: list[tuple[int, str, str]], demo_id: str, lang: str) -> str:
    out = [f"# {demo_id} narration ({lang})", ""]
    for n, title, body in steps:
        out.append(f"## Step {n} — {title}")
        out.append("")
        out.append(body)
        out.append("")
        out.append("---")
        out.append("")
    return "\n".join(out).rstrip() + "\n"

def main():
    en_text = (SRC_DIR / "Demo Narratives.md").read_text()
    zh_text = (SRC_DIR / "Demo Narratives ZH.md").read_text()
    en_secs = split_sections(en_text)
    zh_secs = split_sections(zh_text)

    summary = []
    for idx, demo_id in DEMOS:
        en_steps = extract_steps(en_secs.get(idx, ""))
        zh_steps = extract_steps(zh_secs.get(idx, ""))
        if not en_steps:
            print(f"WARN: no EN steps for section {idx} ({demo_id})", file=sys.stderr)
        if not zh_steps:
            print(f"WARN: no ZH steps for section {idx} ({demo_id})", file=sys.stderr)
        en_path = OUT_DIR / f"{demo_id}.en.md"
        zh_path = OUT_DIR / f"{demo_id}.zh.md"
        en_path.write_text(to_tts_md(en_steps, demo_id, "EN"))
        zh_path.write_text(to_tts_md(zh_steps, demo_id, "ZH"))
        summary.append((demo_id, len(en_steps), len(zh_steps)))

    print(f"{'demo_id':<18}  EN  ZH")
    for d, e, z in summary:
        print(f"{d:<18}  {e:>2}  {z:>2}")
    print(f"\nWrote {len(summary)*2} files to {OUT_DIR}")

if __name__ == "__main__":
    main()
