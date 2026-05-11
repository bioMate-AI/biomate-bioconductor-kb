"""
Generate ICH-compliant adversity-language SFT task examples (v6 task #9).

Given a raw study finding statement, restate using ICH-compliant adversity
phrasing without semantic shift. Every example self-verifies via
adversity_language.detect_adversity returning the intended category.

Usage:
    python scripts/generate_adversity_sft_task.py --n 300
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.drug_discovery.adversity_language import (
    AdversityCategory, detect_adversity,
)

SYSTEM_PROMPT = (
    "You are a regulatory writer. Restate the provided nonclinical study finding "
    "using ICH-compliant adversity phrasing. Preserve the semantic content. Use "
    "the exact regulatory vocabulary: 'no findings' / 'non-adverse' / 'no test-"
    "article-related findings' / 'NOAEL of X mg/kg/day' / 'NOAEL was not established'."
)

RAW_FINDINGS: dict[AdversityCategory, list[str]] = {
    "no_findings": [
        "Nothing unusual was seen in any animal at any dose.",
        "The animals all looked fine throughout the study.",
        "Examination didn't show anything notable in any group.",
    ],
    "non_adverse_findings": [
        "Mild salivation was seen at dosing, but the investigators didn't think it was problematic.",
        "There was some hair loss but it was minor and probably from grooming.",
        "Slight body weight changes were noted but considered within normal range.",
    ],
    "no_test_article_related": [
        "A couple of animals had skin lesions but these were probably from cage-mate fighting.",
        "Some background lesions were found, but they didn't seem related to the drug.",
        "The histopath changes were typical of this strain and not related to treatment.",
    ],
    "adverse_findings": [
        "At the top dose, liver enzyme increases were considered adverse, so the middle dose became the NOAEL of 100 mg/kg/day.",
        "Renal tubular degeneration was clear at 300 mg/kg/day. The NOAEL was 100 mg/kg/day.",
        "Body weight loss exceeded 20% at the high dose; NOAEL identified at 30 mg/kg/day.",
    ],
    "noael_not_established": [
        "Liver toxicity was seen at every dose tested, including the lowest one.",
        "Even at the lowest dose tested, animals showed adverse renal effects.",
        "Adverse findings occurred at all doses, so we couldn't pick a no-effect dose.",
    ],
}

ICH_RESTATEMENTS: dict[AdversityCategory, list[str]] = {
    "no_findings": [
        "No findings were observed at any dose level in either sex.",
        "No findings were identified in any treatment group.",
        "No test-article-related observations were noted; no findings in any cohort.",
    ],
    "non_adverse_findings": [
        "Findings observed during dosing were considered non-adverse and did not affect animal welfare or study endpoints.",
        "The observed findings were not considered adverse and did not warrant identification of a lower NOAEL.",
        "Non-adverse findings were noted; the NOAEL was identified at the high dose level.",
    ],
    "no_test_article_related": [
        "No test-article-related findings were identified; observations were attributable to background pathology or husbandry.",
        "No treatment-related findings were observed; findings were considered unrelated to test article.",
        "No test-article-related findings were noted; incidental observations were unrelated to test article.",
    ],
    "adverse_findings": [
        "Adverse findings were identified at the high dose; the NOAEL of 100 mg/kg/day was established at the mid dose.",
        "Adverse findings identified at the high dose; NOAEL of 100 mg/kg/day at the mid dose.",
        "Adverse findings were identified at the high dose level; NOAEL of 30 mg/kg/day.",
    ],
    "noael_not_established": [
        "Adverse findings were observed at all dose levels; the NOAEL was not established.",
        "Adverse effects at all dose levels; NOAEL could not be established.",
        "Adverse findings at all dose levels; the NOAEL was not established in this study.",
    ],
}


def make_example(rng: random.Random, category: AdversityCategory) -> dict:
    raw = rng.choice(RAW_FINDINGS[category])
    ich = rng.choice(ICH_RESTATEMENTS[category])
    user = (
        f"Restate the following study finding using ICH-compliant adversity "
        f"phrasing:\n\n{raw}"
    )
    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user},
            {"role": "assistant", "content": ich},
        ],
        "meta": {
            "task": "adversity_language",
            "section_type": "tox_overview",
            "adversity_category": category,
        },
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=300)
    ap.add_argument("--out", type=Path,
                    default=ROOT / "data/regulatory_training/tasks/task9_adversity_language.jsonl")
    ap.add_argument("--seed", type=int, default=20260510)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    args.out.parent.mkdir(parents=True, exist_ok=True)

    categories = list(RAW_FINDINGS.keys())
    written = failed = 0
    with args.out.open("w") as f:
        while written < args.n:
            cat = categories[written % len(categories)]
            ex = make_example(rng, cat)
            r = detect_adversity(ex["messages"][-1]["content"])
            if r.detected != cat:
                failed += 1
                if failed > args.n * 2:
                    raise RuntimeError("too many self-verification failures")
                continue
            f.write(json.dumps(ex) + "\n")
            written += 1

    print(f"Wrote {written} adversity-language examples to {args.out}")
    print(f"Rejected {failed}")


if __name__ == "__main__":
    main()
