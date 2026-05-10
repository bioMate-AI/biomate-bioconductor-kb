"""
Generate synthetic MRSD-computation SFT task examples (v6 task #2).

Every generated example is verified to pass mrsd_verifier.py by construction.
Output: JSONL of {messages, meta} compatible with existing SFT pipeline.

Usage:
    python scripts/generate_mrsd_sft_task.py --n 500 --out data/regulatory_training/tasks/task5_mrsd_computation.jsonl
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.drug_discovery.mrsd_verifier import (
    BSA_DIVISOR, DEFAULT_SAFETY_FACTOR, verify_mrsd,
)

SPECIES_FOR_NOAEL = ["mouse", "rat", "dog", "monkey", "rabbit", "minipig"]
NOAEL_VALUES = [0.5, 1, 2, 5, 10, 25, 50, 100, 200, 300, 500, 1000, 1500, 2000]
SAFETY_FACTORS = [10.0, 10.0, 10.0, 10.0, 50.0, 100.0]  # 10× is default; biologic/oncology vary

INDICATIONS = [
    "advanced solid tumors", "rheumatoid arthritis", "type 2 diabetes",
    "atopic dermatitis", "chronic hepatitis B", "Alzheimer's disease",
    "moderate-to-severe ulcerative colitis", "primary hyperoxaluria",
    "chronic obstructive pulmonary disease", "schizophrenia",
]

STUDY_DESIGNS = [
    "28-day repeat-dose toxicity study", "13-week GLP toxicity study",
    "4-week pivotal toxicity study", "single-dose escalation toxicity study",
    "pivotal 26-week chronic toxicity study",
]

SYSTEM_PROMPT = (
    "You are a computational pharmacologist preparing ICH M4 CTD Module 2.6 "
    "nonclinical summaries for IND applications. When given nonclinical data, "
    "compute the Human Equivalent Dose (HED) and Maximum Recommended Starting "
    "Dose (MRSD) per FDA 2005 guidance: HED (mg/kg) = animal NOAEL (mg/kg) ÷ "
    "BSA conversion factor; MRSD = HED ÷ safety factor. Show the arithmetic."
)


def build_user_prompt(species: str, noael: float, study: str, indication: str) -> str:
    return (
        f"In a {study} for an investigational therapeutic targeting {indication}, "
        f"the most sensitive species was the {species}, with a NOAEL of {noael} mg/kg/day. "
        f"Compute the Human Equivalent Dose and propose the Maximum Recommended Starting Dose "
        f"for first-in-human Phase I dosing in healthy adult volunteers. "
        f"Cite ICH M3(R2) and FDA 2005 MRSD guidance."
    )


def build_assistant(species: str, noael: float, safety_factor: float) -> str:
    divisor = BSA_DIVISOR[species]
    hed = noael / divisor
    mrsd = hed / safety_factor

    sf_rationale = (
        "A 10× default safety factor is applied per FDA 2005 guidance to account "
        "for interspecies and intraspecies variability."
        if safety_factor == 10.0
        else f"A safety factor of {int(safety_factor)} is applied due to elevated "
             "clinical risk (steep dose-response, novel mechanism, or limited reversibility)."
    )

    return (
        f"In the most sensitive species, the {species}, the NOAEL of {noael} mg/kg/day "
        f"establishes the basis for human starting-dose derivation per ICH M3(R2) and "
        f"FDA 2005 guidance on Estimating the Maximum Safe Starting Dose. "
        f"Applying the body-surface-area conversion factor for the {species} ({divisor}), "
        f"the HED of {hed:.2f} mg/kg is calculated. "
        f"{sf_rationale} "
        f"With a safety factor of {int(safety_factor) if safety_factor.is_integer() else safety_factor}, "
        f"the MRSD of {mrsd:.3f} mg/kg is recommended for the proposed first-in-human "
        f"single-ascending-dose study."
    )


def make_example(rng: random.Random) -> dict:
    species = rng.choice(SPECIES_FOR_NOAEL)
    noael = rng.choice(NOAEL_VALUES)
    safety_factor = rng.choice(SAFETY_FACTORS)
    study = rng.choice(STUDY_DESIGNS)
    indication = rng.choice(INDICATIONS)

    user = build_user_prompt(species, noael, study, indication)
    assistant = build_assistant(species, noael, safety_factor)

    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user},
            {"role": "assistant", "content": assistant},
        ],
        "meta": {
            "task": "mrsd_computation",
            "section_type": "tox_overview",
            "species": species,
            "noael_mg_per_kg": noael,
            "safety_factor": safety_factor,
        },
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=500)
    ap.add_argument("--out", type=Path, default=ROOT / "data" / "regulatory_training" / "tasks" / "task5_mrsd_computation.jsonl")
    ap.add_argument("--seed", type=int, default=20260509)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    args.out.parent.mkdir(parents=True, exist_ok=True)

    written = 0
    failed = 0
    with args.out.open("w") as f:
        while written < args.n:
            ex = make_example(rng)
            assistant = ex["messages"][-1]["content"]
            r = verify_mrsd(assistant)
            if not (r.grounded and r.passed):
                failed += 1
                continue
            f.write(json.dumps(ex) + "\n")
            written += 1

    print(f"Wrote {written} MRSD-computation examples to {args.out}")
    print(f"Rejected {failed} that failed self-verification (should be 0)")


if __name__ == "__main__":
    main()
