"""Real-FDA-label contamination check + v7 corpus pilot (n=20 PoC).

What it does:
  1. Pulls real FDA drug-label nonclinical sections from openFDA.
     These are 21 CFR §201.57 paragraphs — same style as IND §2.6.
  2. Splits each label's `nonclinical_toxicology` into per-subsection
     paragraphs (Carcinogenesis, Mutagenesis, Impairment of Fertility, …).
  3. Uses GPT-5 (RAG-grounded later; raw for the PoC) to reverse-engineer
     the structured input (NOAEL by species, doses, study design) that
     would have produced each paragraph.
  4. Runs GPT-5 + Claude Sonnet 4.6 on the reverse-engineered prompts,
     scores with the cross-judge rubric from checker_suite_v2.
  5. Compares macro_avg distribution to the v6-synthetic eval scores.

Output:
  evaluation/results/fda_pilot_v1/
    real_label_examples.jsonl          — the curated input set
    <model>.jsonl                       — model outputs + judge scores
    summary_real_vs_synthetic.csv       — the contamination delta

Decision logic (after this runs):
  - If real-data scores collapse for v6/base (≥10pp drop): eval contamination
    confirmed. Test set was shaped like training set. Need fresh real-data
    test split.
  - If real-data scores match synthetic-data scores: eval is structurally
    sound. Next step is the full ~10K-example v7 corpus.
  - Either way, this also acts as a pilot for the augmented-GPT5 data
    generation pipeline described in docs/20260603_PARALLEL_LANES_SESSION_WRITEUP.md.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "evaluation" / "runners"))

from adapters.anthropic_adapter import AnthropicAdapter
from adapters.openai_adapter import OpenAIAdapter
from checker_suite_v2 import score_with_judge

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

OUT_DIR = REPO_ROOT / "evaluation" / "results" / "fda_pilot_v1"
OUT_DIR.mkdir(parents=True, exist_ok=True)

DEFAULT_N_LABELS = 20  # PoC scope; full corpus is later

# Map common label subsection headers to our internal section_type taxonomy
# so the judge can apply the right rubric.
SUBSECTION_TO_TYPE = {
    "carcinogenesis": "tox_overview",
    "mutagenesis": "tox_genotox",
    "impairment of fertility": "tox_overview",
    "carcinogenicity": "tox_overview",
    "genotoxicity": "tox_genotox",
    "reproductive toxicology": "tox_overview",
    "cardiac": "tox_cardiac",
    "qt": "tox_cardiac",
    "embryofetal": "tox_overview",
}

OPENFDA_URL = (
    "https://api.fda.gov/drug/label.json"
    "?search=nonclinical_toxicology:*"
    "&limit={limit}&skip={skip}"
)

# ---------------------------------------------------------------------------
# 1) Fetch real FDA labels
# ---------------------------------------------------------------------------

def fetch_labels(n: int, skip: int = 0) -> list[dict]:
    """Pull n drug labels that have a nonclinical_toxicology section.

    openFDA paginates in batches of 100 max; one call is enough at PoC scale.
    """
    url = OPENFDA_URL.format(limit=n, skip=skip)
    with urllib.request.urlopen(url, timeout=30) as r:
        data = json.loads(r.read())
    return data.get("results", [])


# ---------------------------------------------------------------------------
# 2) Split label into per-subsection paragraphs
# ---------------------------------------------------------------------------

_SUBSECTION_HEADERS_RE = re.compile(
    r"\b(Carcinogenesis|Mutagenesis|Impairment of Fertility|Carcinogenicity|"
    r"Genotoxicity|Reproductive Toxicology|Embryofetal Development|"
    r"Animal Toxicology and/or Pharmacology|Cardiac|QT Prolongation)\b",
    re.IGNORECASE,
)


def extract_paragraphs(label: dict) -> list[dict]:
    """Return [{section_type, header, paragraph}, ...] for one label."""
    tox = label.get("nonclinical_toxicology") or []
    if isinstance(tox, list):
        tox = " ".join(tox)
    if not tox:
        return []

    # Strip the boilerplate label numbering ("13 NONCLINICAL TOXICOLOGY 13.1 ...")
    tox = re.sub(r"^\s*13[\.\s]?[^\s]*NONCLINICAL TOXICOLOGY[\s\d\.]+", "", tox).strip()

    # Split on subsection headers. The header itself becomes the marker for the
    # next paragraph.
    pieces = _SUBSECTION_HEADERS_RE.split(tox)
    # pieces is [before_first_header, header1, content1, header2, content2, ...]
    # Pair them up
    out = []
    if len(pieces) < 3:
        # No recognizable subsection markers; treat the whole thing as one
        # tox_overview paragraph (still useful)
        if len(tox) >= 200:
            out.append({
                "section_type": "tox_overview",
                "header": "Nonclinical Toxicology",
                "paragraph": tox.strip(),
            })
        return out

    i = 1
    while i + 1 < len(pieces):
        header = pieces[i].strip()
        content = pieces[i + 1].strip()
        if len(content) >= 200:  # skip tiny stub sections
            section_type = SUBSECTION_TO_TYPE.get(header.lower(), "tox_overview")
            out.append({
                "section_type": section_type,
                "header": header,
                "paragraph": content,
            })
        i += 2
    return out


# ---------------------------------------------------------------------------
# 3) Reverse-engineer the prompt with GPT-5
# ---------------------------------------------------------------------------

REVERSE_SYSTEM = """You are an FDA reviewer. Given a real nonclinical paragraph from an
approved drug label, write the structured input data a sponsor would have
submitted that would produce this paragraph. Output ONLY a JSON object with
the structured input — do not include the paragraph itself.

Required fields:
  drug_name: str  (best guess from the paragraph)
  section_type: str  (from the provided context)
  study_design: short paragraph describing the study type, species, duration
  doses_mg_per_kg_per_day: list of numbers
  noael_mg_per_kg_per_day: number or null  (per most-sensitive species)
  most_sensitive_species: str or null
  endpoints: list[str]  (e.g., ["hERG IC50", "DILI", "Ames"] — what was measured)
  reference_clinical_dose_mg: number or null  (the MRHD if mentioned)

Return ONLY the JSON object. No prose. No markdown fence.
"""


def reverse_engineer_prompt(paragraph: str, section_type: str, drug_hint: str) -> Optional[dict]:
    """Use GPT-5 to extract the structured input that would have produced this
    paragraph. Returns the parsed dict, or None on parse failure."""
    adapter = OpenAIAdapter(model="gpt-5")
    user = (
        f"section_type: {section_type}\n"
        f"drug_hint: {drug_hint}\n\n"
        f"REAL PARAGRAPH:\n{paragraph}\n\n"
        f"Return the JSON object only."
    )
    try:
        raw = adapter.generate(REVERSE_SYSTEM, user, max_new_tokens=600)
        # Strip any accidental code-fence wrapping
        raw = re.sub(r"^```(?:json)?\s*", "", raw.strip())
        raw = re.sub(r"\s*```$", "", raw)
        return json.loads(raw)
    except Exception as exc:
        print(f"  [reverse_engineer] failed: {exc}", file=sys.stderr)
        return None


# ---------------------------------------------------------------------------
# 4) Run candidate models against the reverse-engineered prompts
# ---------------------------------------------------------------------------

GENERATE_SYSTEM = """You are an FDA/ICH-trained regulatory writer. Produce a single
§2.6 nonclinical paragraph from the structured input. Strict requirements:

- ICH M4 paragraph shape: present-tense framing, past-tense findings, citation in parens
- Cite the correct guideline for this section_type:
    tox_overview/overview  -> ICH M3(R2) and/or FDA 2005 MRSD
    tox_genotox            -> ICH S2(R1)
    tox_cardiac            -> ICH S7B
    pbpk                   -> EMA/CHMP/EWP/37498/2011
    admet                  -> ICH M4S
- Use the numbers in the input verbatim or correctly derived (NOAEL → HED → MRSD with right BSA factor)
- No tutorial framing, no markdown headers, no bullet lists, no LaTeX
- 2-4 sentences max, one paragraph
- Past-tense for adverse findings, no overclaims ("safe", "no toxicity")
"""


def run_candidate(model_label: str, prompt_input: dict, section_type: str) -> dict:
    """Run one candidate model on the reverse-engineered input. Returns
    {output, elapsed_s, error?}."""
    if model_label == "gpt_5":
        adapter = OpenAIAdapter(model="gpt-5")
    elif model_label == "claude_sonnet_4_6":
        adapter = AnthropicAdapter(model="claude-sonnet-4-6")
    else:
        return {"output": "", "elapsed_s": 0, "error": f"unknown model {model_label}"}

    user = (
        f"section_type: {section_type}\n"
        f"structured_input:\n{json.dumps(prompt_input, indent=2)}\n\n"
        f"Write the §2.6 paragraph now."
    )
    t0 = time.time()
    try:
        out = adapter.generate(GENERATE_SYSTEM, user, max_new_tokens=400)
        return {"output": out, "elapsed_s": round(time.time() - t0, 2), "error": None}
    except Exception as exc:
        return {"output": "", "elapsed_s": round(time.time() - t0, 2), "error": str(exc)}


# ---------------------------------------------------------------------------
# 5) Orchestrate
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--n-labels", type=int, default=DEFAULT_N_LABELS)
    parser.add_argument("--target-examples", type=int, default=20,
                        help="Stop after this many reverse-engineered examples")
    parser.add_argument("--models", nargs="+", default=["gpt_5", "claude_sonnet_4_6"])
    args = parser.parse_args()

    print(f"[1] Fetching {args.n_labels} FDA labels from openFDA...")
    labels = fetch_labels(args.n_labels)
    print(f"    pulled {len(labels)} labels")

    print(f"[2] Extracting paragraphs + reverse-engineering prompts...")
    examples: list[dict] = []
    for i, label in enumerate(labels):
        if len(examples) >= args.target_examples:
            break
        brand_list = label.get("openfda", {}).get("brand_name", [])
        brand = brand_list[0] if brand_list else "?"
        paragraphs = extract_paragraphs(label)
        for p in paragraphs:
            if len(examples) >= args.target_examples:
                break
            print(f"  [{len(examples)+1}/{args.target_examples}] {brand}::{p['header']} ...")
            inp = reverse_engineer_prompt(
                p["paragraph"], p["section_type"], brand,
            )
            if inp is None:
                continue
            examples.append({
                "example_id": f"fda_{len(examples):04d}",
                "drug_brand": brand,
                "section_type": p["section_type"],
                "header": p["header"],
                "real_paragraph": p["paragraph"],
                "structured_input": inp,
            })

    examples_path = OUT_DIR / "real_label_examples.jsonl"
    with examples_path.open("w") as f:
        for e in examples:
            f.write(json.dumps(e) + "\n")
    print(f"    saved {len(examples)} examples to {examples_path}")

    if not examples:
        print("No examples — exiting", file=sys.stderr)
        return 1

    print(f"\n[3] Running candidates + judge on each example...")
    summary = {m: {"scores": [], "errors": 0} for m in args.models}

    for model in args.models:
        model_path = OUT_DIR / f"{model}.jsonl"
        with model_path.open("w") as out_f:
            for ex in examples:
                cand = run_candidate(model, ex["structured_input"], ex["section_type"])
                if cand.get("error") or not cand.get("output"):
                    out_f.write(json.dumps({
                        "example_id": ex["example_id"],
                        "model": model,
                        "output": cand.get("output", ""),
                        "error": cand.get("error"),
                        "macro": 0.0,
                    }) + "\n")
                    summary[model]["errors"] += 1
                    continue

                # Build a prompt-shaped object the judge expects
                prompt_for_judge = (
                    f"section_type: {ex['section_type']}\n"
                    f"structured_input: {json.dumps(ex['structured_input'])}\n"
                    f"real_label_reference (for grading): {ex['real_paragraph'][:600]}"
                )
                judge_result = score_with_judge(
                    section_type=ex["section_type"],
                    prompt=prompt_for_judge,
                    candidate=cand["output"],
                )
                row = {
                    "example_id": ex["example_id"],
                    "model": model,
                    "section_type": ex["section_type"],
                    "drug_brand": ex["drug_brand"],
                    "header": ex["header"],
                    "output": cand["output"],
                    "elapsed_s": cand["elapsed_s"],
                    "rubric_scores": judge_result.rubric_scores,
                    "macro": judge_result.macro,
                    "rationale": judge_result.rationale,
                }
                out_f.write(json.dumps(row) + "\n")
                summary[model]["scores"].append(judge_result.macro)
                print(f"  [{model}] {ex['example_id']} ({ex['header'][:25]}): "
                      f"macro={judge_result.macro:.2f}")
        print(f"    wrote {model_path}")

    print(f"\n[4] Summary (real FDA labels, n={len(examples)}):")
    print(f"{'model':<22} {'mean macro':<12} {'errors':<8}")
    for m in args.models:
        scores = summary[m]["scores"]
        mean = sum(scores) / len(scores) if scores else 0.0
        print(f"{m:<22} {mean:<12.3f} {summary[m]['errors']:<8}")

    # Save summary as CSV for the contamination comparison
    csv_path = OUT_DIR / "summary_real_vs_synthetic.csv"
    with csv_path.open("w") as f:
        w = csv.writer(f)
        w.writerow(["model", "real_fda_mean_macro", "n_examples_scored", "errors"])
        for m in args.models:
            scores = summary[m]["scores"]
            mean = sum(scores) / len(scores) if scores else 0.0
            w.writerow([m, f"{mean:.3f}", len(scores), summary[m]["errors"]])
    print(f"    wrote {csv_path}")
    print("\nDone.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
