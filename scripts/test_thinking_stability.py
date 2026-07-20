#!/usr/bin/env python3
"""
Thinking-mode stability test for LLM comparison blog (T01–T05).

Runs each of the 5 drug-design queries N times with thinking mode enabled,
extracts the key decision from each response, and reports consistency.

Usage:
  # Claude extended thinking:
  ANTHROPIC_API_KEY=sk-... python3 test_thinking_stability.py --model claude --runs 5

  # Gemini with thinking budget:
  GOOGLE_API_KEY=... python3 test_thinking_stability.py --model gemini --runs 5

  # OpenAI extended reasoning:
  OPENAI_API_KEY=sk-... python3 test_thinking_stability.py --model gpt --runs 5

Output: results/thinking_stability_<model>_<date>.json + console summary table.
"""

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

# ── Queries ────────────────────────────────────────────────────────────────

QUERIES = {
    "T01": {
        "question": (
            "Design a PD-1 × VEGF bispecific antibody for NSCLC. "
            "Score the main formats — CrossMab, IgG-scFv, BiTE, DART, KiH — "
            "across CMC, immunogenicity, half-life, tumor penetration, ADCC, "
            "manufacturability. Give a ranked recommendation."
        ),
        "gold_standard": "Tetravalent IgG-scFv #1 (cooperative avidity on dimeric VEGF)",
        # Extract the top-ranked format name
        "extract_re": [
            (r"tetravalent", "Tetravalent / IgG-scFv"),
            (r"IgG-scFv|igG scFv|scfv.*tetrav|tetrav.*scfv", "Tetravalent / IgG-scFv"),
            (r"crossmab|cross-mab|cross mab", "CrossMab"),
            (r"\bKiH\b|knobs.into.holes", "KiH"),
            (r"\bBiTE\b|bite ", "BiTE"),
            (r"\bDART\b", "DART"),
        ],
    },
    "T02": {
        "question": (
            "Design an in vivo CAR-T for CD19+ B-cell lymphoma using LNP delivery. "
            "Check fratricide risk. Recommend the LNP targeting moiety "
            "(anti-CD8, anti-CD3, anti-CD5, anti-CD7) and give the CAR construct "
            "domain architecture."
        ),
        "gold_standard": "anti-CD8 LNP (Capstan CPTX2309)",
        "extract_re": [
            (r"anti-CD8|anti CD8|αCD8|α-CD8", "anti-CD8"),
            (r"anti-CD3|anti CD3|αCD3|α-CD3", "anti-CD3"),
            (r"anti-CD5|anti CD5|αCD5|α-CD5", "anti-CD5"),
            (r"anti-CD7|anti CD7|αCD7|α-CD7", "anti-CD7"),
        ],
    },
    "T03": {
        "question": (
            "Design an in vivo base editing strategy for PCSK9 loss-of-function. "
            "Recommend editor class (CBE or ABE), guide RNA target site, and LNP "
            "delivery. Compare VERVE-101 vs VERVE-102."
        ),
        "gold_standard": "ABE8.8 + exon1/intron1 splice-donor gRNA (Musunuru et al., Nature 2021)",
        "extract_re": [
            (r"ABE8\.8|ABE 8\.8|abe8", "ABE8.8"),
            (r"\bABE\b(?!8\.8)", "ABE (unspecified)"),
            (r"\bCBE\b|cytosine base", "CBE"),
            (r"W8|TGG.*TAG|nonsense.*codon", "CBE/W8 nonsense"),
            (r"splice.donor|splice donor|exon.1.*intron|intron.*exon.1", "splice-donor"),
        ],
    },
    "T04": {
        "question": (
            "Compare GLP-1 modalities for MASH. Use GLP1R, GIPR, GCGR receptor "
            "expression profiles to rank candidates: semaglutide, tirzepatide, "
            "retatrutide, orforglipron. Which is best for MASH?"
        ),
        "gold_standard": "Retatrutide #1 for MASH (GCGR hepatocyte-dominance)",
        "extract_re": [
            (r"retatrutide|LY3437943", "Retatrutide"),
            (r"tirzepatide|mounjaro|LY3298176", "Tirzepatide"),
            (r"semaglutide|ozempic|wegovy", "Semaglutide"),
            (r"orforglipron|LY3502970", "Orforglipron"),
        ],
    },
    "T05": {
        "question": (
            "Which therapeutic modality is best for BCMA in multiple myeloma? "
            "Rank CAR-T, bispecific, ADC, naked mAb, PROTAC, ASO, small molecule "
            "based on target biology."
        ),
        "gold_standard": "CAR-T #1 (Abecma / Carvykti; plasma-cell restricted expression)",
        "extract_re": [
            (r"CAR-T|CAR T\b|car-t", "CAR-T"),
            (r"bispecific|bi-specific", "Bispecific"),
            (r"\bADC\b|antibody.drug conjugate", "ADC"),
            (r"naked mAb|mAb\b|monoclonal antibody", "mAb"),
        ],
    },
}

# ── Model callers ───────────────────────────────────────────────────────────

def call_claude(prompt: str, budget_tokens: int = 8000) -> tuple[str, dict]:
    """Call Claude with extended thinking. Returns (text, metadata)."""
    import anthropic
    client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    resp = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=16000,
        thinking={"type": "enabled", "budget_tokens": budget_tokens},
        messages=[{"role": "user", "content": prompt}],
    )
    text = ""
    thinking_tokens = 0
    for block in resp.content:
        if block.type == "thinking":
            thinking_tokens = len(block.thinking.split())
        elif block.type == "text":
            text += block.text
    return text, {
        "input_tokens": resp.usage.input_tokens,
        "output_tokens": resp.usage.output_tokens,
        "thinking_word_count": thinking_tokens,
    }


def call_gemini(prompt: str, thinking_budget: int = 8000) -> tuple[str, dict]:
    """Call Gemini with thinking budget."""
    import google.generativeai as genai
    genai.configure(api_key=os.environ["GOOGLE_API_KEY"])
    model = genai.GenerativeModel(
        "gemini-3.1-pro-preview",
        generation_config={"thinking_budget": thinking_budget},
    )
    resp = model.generate_content(prompt)
    text = resp.text
    meta = {}
    if hasattr(resp, "usage_metadata"):
        meta = {
            "prompt_tokens": resp.usage_metadata.prompt_token_count,
            "candidates_tokens": resp.usage_metadata.candidates_token_count,
        }
    return text, meta


def call_gpt(prompt: str) -> tuple[str, dict]:
    """Call GPT-5.5 with extended reasoning."""
    from openai import OpenAI
    client = OpenAI(api_key=os.environ["OPENAI_API_KEY"])
    resp = client.chat.completions.create(
        model="gpt-5.5-2026-04-23",
        reasoning_effort="high",
        messages=[{"role": "user", "content": prompt}],
    )
    text = resp.choices[0].message.content or ""
    meta = {
        "prompt_tokens": resp.usage.prompt_tokens,
        "completion_tokens": resp.usage.completion_tokens,
        "reasoning_tokens": getattr(resp.usage, "reasoning_tokens", None),
    }
    return text, meta


MODEL_CALLERS = {
    "claude": call_claude,
    "gemini": call_gemini,
    "gpt": call_gpt,
}

# ── Extractor ───────────────────────────────────────────────────────────────

def extract_answer(query_id: str, text: str) -> str:
    """Return the first matching label from the response text (case-insensitive)."""
    patterns = QUERIES[query_id]["extract_re"]
    text_lower = text.lower()
    for pattern, label in patterns:
        if re.search(pattern, text_lower, re.IGNORECASE):
            return label
    return "UNMATCHED"


# ── Main ────────────────────────────────────────────────────────────────────

def run_stability_test(model: str, n_runs: int, query_ids: list[str], delay: float):
    caller = MODEL_CALLERS[model]
    results = {}  # query_id -> list of (answer, meta)

    for qid in query_ids:
        q = QUERIES[qid]
        print(f"\n{'─'*60}")
        print(f"  Query {qid}  ({n_runs} runs)  [{model}]")
        print(f"  Gold: {q['gold_standard']}")
        print(f"{'─'*60}")

        runs = []
        for i in range(n_runs):
            print(f"  Run {i+1}/{n_runs} ... ", end="", flush=True)
            t0 = time.time()
            try:
                text, meta = caller(q["question"])
                elapsed = time.time() - t0
                answer = extract_answer(qid, text)
                runs.append({"run": i + 1, "answer": answer, "elapsed_s": round(elapsed, 1), "meta": meta})
                print(f"{answer}  ({elapsed:.0f}s)")
            except Exception as e:
                print(f"ERROR: {e}")
                runs.append({"run": i + 1, "answer": "ERROR", "elapsed_s": None, "meta": {"error": str(e)}})

            if i < n_runs - 1:
                time.sleep(delay)

        results[qid] = runs

    return results


def print_summary(model: str, results: dict):
    print(f"\n{'═'*70}")
    print(f"  STABILITY SUMMARY — {model.upper()} — {datetime.now().strftime('%Y-%m-%d')}")
    print(f"{'═'*70}")
    print(f"  {'Query':<6} {'Gold standard answer':<30} {'Runs':<5} {'Consistent?':<12} {'Answers'}")
    print(f"  {'─'*6} {'─'*30} {'─'*5} {'─'*12} {'─'*30}")

    overall_stable = True
    for qid, runs in results.items():
        gold = QUERIES[qid]["gold_standard"].split("(")[0].strip()
        answers = [r["answer"] for r in runs if r["answer"] != "ERROR"]
        if not answers:
            print(f"  {qid:<6} {gold:<30} {len(runs):<5} {'ALL ERRORS':<12}")
            continue
        unique = set(answers)
        pct = answers.count(answers[0]) / len(answers) * 100 if answers else 0
        stable = len(unique) == 1
        if not stable:
            overall_stable = False
        flag = "✓ stable" if stable else f"✗ {pct:.0f}% agree"
        counts = ", ".join(f"{a}×{answers.count(a)}" for a in sorted(unique))
        print(f"  {qid:<6} {gold[:30]:<30} {len(runs):<5} {flag:<12} {counts}")

    print(f"\n  Overall stable: {'YES' if overall_stable else 'NO — thinking outputs vary across runs'}")
    print(f"{'═'*70}\n")


def save_results(model: str, results: dict, out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = out_dir / f"thinking_stability_{model}_{ts}.json"
    payload = {
        "model": model,
        "timestamp": ts,
        "queries": {qid: {"gold_standard": QUERIES[qid]["gold_standard"], "runs": runs}
                    for qid, runs in results.items()},
    }
    path.write_text(json.dumps(payload, indent=2))
    print(f"  Saved → {path}")
    return path


# ── CLI ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Test LLM thinking-mode stability across repeated runs.")
    parser.add_argument("--model", choices=["claude", "gemini", "gpt"], required=True,
                        help="Which model to test")
    parser.add_argument("--runs", type=int, default=5,
                        help="Number of runs per query (default: 5)")
    parser.add_argument("--queries", nargs="+", default=list(QUERIES.keys()),
                        choices=list(QUERIES.keys()),
                        help="Subset of queries to test (default: all T01–T05)")
    parser.add_argument("--delay", type=float, default=2.0,
                        help="Seconds between runs to avoid rate limits (default: 2)")
    parser.add_argument("--out-dir", default="results/thinking_stability",
                        help="Output directory for JSON results")
    args = parser.parse_args()

    # Check API key
    key_map = {"claude": "ANTHROPIC_API_KEY", "gemini": "GOOGLE_API_KEY", "gpt": "OPENAI_API_KEY"}
    key_var = key_map[args.model]
    if not os.environ.get(key_var):
        print(f"ERROR: {key_var} not set.", file=sys.stderr)
        sys.exit(1)

    print(f"\nThinking-mode stability test")
    print(f"  Model : {args.model}")
    print(f"  Runs  : {args.runs} per query")
    print(f"  Queries: {', '.join(args.queries)}")

    results = run_stability_test(args.model, args.runs, args.queries, args.delay)
    print_summary(args.model, results)
    save_results(args.model, results, Path(args.out_dir))
