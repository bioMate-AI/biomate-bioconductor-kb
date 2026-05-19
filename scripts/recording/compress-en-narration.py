#!/usr/bin/env python3
"""
Compress each EN narration step so the full TTS output lands ~3:00.

Inputs and outputs preserve the gemini-tts.py format
('## Step N — title\\n\\nbody\\n---').

Per-step target seconds is computed from total step count:
  total budget = 180 - (steps - 1) * SILENCE_S
  per_step     = budget / steps

At ~140 wpm Aoede pace, 7s ≈ 16 words, 10s ≈ 23 words, 13s ≈ 30 words.
"""
import re, os, sys, pathlib, argparse, time, json

GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY', 'AIzaSyDoFJyQuwTYsfhoLO4DBL1ME9Ojl7VpFHI')
MODEL = 'gemini-2.5-flash'

WORDS_PER_SEC = 2.3   # Aoede pace estimate

PROMPT_TMPL = """You are an EN tutorial-narration compressor. Rewrite the step below into a tight version that, when spoken aloud at ~140 wpm, lasts about {target_s:.1f} seconds (≈ {target_words} words).

Hard rules:
1. Preserve technical terms verbatim: CryoSPARC, MotionCor2, CTFFIND4, Topaz, AWS Batch, hERG, DILI, Ames, PPBR, Caco-2, BBB, CYPs, P-gp, PBPK, ADMET, GP, EHVI, Morgan fingerprints, DOCX, FDA, EMA, NMPA, PMDA, §2.6.1, 21 CFR Part 11, EMPIAR-10025, GSFSC, TOTP, SHA-256, Cmax, AUC.
2. Keep concrete COUNTS (3.21 Å resolution, 41 endpoints, 5 phases, 23 steps).
3. Drop scenario framing / pep-talk language. No "let me show you", "welcome", "we'll walk through".
4. **Remove every time-related estimate, duration, or countdown reference.** Do NOT mention seconds, minutes, hours, "thirty seconds", "two minutes", "a ten-second countdown", "30s pilot", "About a minute and a half", "in 30s", etc. Costs and durations are estimates; the user has asked to strip them entirely. Drop sentences that exist only to state a duration.
5. **For cryo Phase B / Phase C / Phase D / Phase E beats (the four reconstruction phases), describe each phase in ONE high-level sentence about what the phase accomplishes — do NOT enumerate the tools or steps inside the phase (don't list Topaz, ab-initio, FSC, B-factor sharpening, etc.).**
6. Each sentence ≤ 14 words; total ≤ {hard_cap_words} words. Output a polished paragraph that reads naturally.
7. Output ONLY the new narration body. No preamble, no quotes, no labels.

Original:
{body}
"""

def parse(path):
    text = pathlib.Path(path).read_text()
    blocks = re.split(r'\n---\n', text.strip())
    steps = []
    for b in blocks:
        m = re.search(r'##\s+Step\s+(\d+)\s+[—-]\s+(.+?)\n+(.+)', b.strip(), re.DOTALL)
        if m:
            body = re.sub(r'\s+', ' ', m.group(3).strip())
            steps.append({'num': int(m.group(1)), 'title': m.group(2).strip(), 'body': body})
    return steps

def compress_one(body: str, target_s: float) -> str:
    from google import genai
    target_words = int(round(target_s * WORDS_PER_SEC))
    hard_cap_words = int(round(target_words * 1.2))
    prompt = PROMPT_TMPL.format(target_s=target_s, target_words=target_words,
                                hard_cap_words=hard_cap_words, body=body)
    client = genai.Client(api_key=GEMINI_API_KEY)
    resp = client.models.generate_content(model=MODEL, contents=prompt)
    out = (resp.text or '').strip()
    out = re.sub(r'^["“”\']+|["“”\']+$', '', out)
    out = re.sub(r'\s+', ' ', out).strip()
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in',  dest='inp', required=True)
    ap.add_argument('--out',                required=True)
    ap.add_argument('--total-seconds', type=float, default=180.0,
                    help='Target total spoken duration in seconds (default 180=3:00)')
    ap.add_argument('--silence-seconds', type=float, default=0.3,
                    help='Inter-step silence in seconds (must match gemini-tts.py SILENCE_MS)')
    ap.add_argument('--per-step-seconds', default=None,
                    help='JSON file with [s0, s1, ...] target seconds per step. '
                         'Overrides --total-seconds. Use this to match tour autoAdvance.')
    args = ap.parse_args()

    steps = parse(args.inp)
    n = len(steps)
    per_step_list = None
    if args.per_step_seconds:
        import pathlib as _p
        per_step_list = json.loads(_p.Path(args.per_step_seconds).read_text())
        if len(per_step_list) != n:
            print(f"WARN: --per-step-seconds has {len(per_step_list)} entries but {n} steps")
        # Tighter: narration target = beat × 0.7 (gives 30% margin so audio fits)
        per_step_list = [max(2.0, float(v) * 0.7) if i < len(per_step_list) else 5.0
                         for i, v in enumerate(per_step_list)]
        budget = sum(per_step_list)
        per_step = budget / n
        print(f"{args.inp}: {n} steps; per-step targets from {args.per_step_seconds}; "
              f"sum {budget:.1f}s")
    else:
        budget = args.total_seconds - (n - 1) * args.silence_seconds
        per_step = budget / n
        print(f"{args.inp}: {n} steps, budget {budget:.1f}s → per-step {per_step:.1f}s "
              f"(~{int(round(per_step * WORDS_PER_SEC))} words)")

    out_lines = [f"# {pathlib.Path(args.inp).stem} (compressed for 3:00)", ""]
    for idx, s in enumerate(steps):
        target_s = per_step_list[idx] if per_step_list and idx < len(per_step_list) else per_step
        try:
            new = compress_one(s['body'], target_s)
        except Exception as e:
            print(f"  step {s['num']}: ERROR {e}", file=sys.stderr)
            new = s['body']
        w = len(new.split())
        print(f"  step {s['num']:>2}: {w:>2}w (target {target_s:.1f}s)  {new[:60]}")
        out_lines.append(f"## Step {s['num']} — {s['title']}")
        out_lines.append("")
        out_lines.append(new)
        out_lines.append("")
        out_lines.append("---")
        out_lines.append("")
        time.sleep(0.2)

    pathlib.Path(args.out).write_text("\n".join(out_lines).rstrip() + "\n")
    print(f"Wrote {args.out}")

if __name__ == "__main__":
    main()
