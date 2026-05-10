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

# Excludes oncology — ICH S9 specifies STD10/HNSTD path, not NOAEL/MRSD.
INDICATIONS = [
    "rheumatoid arthritis", "type 2 diabetes", "atopic dermatitis",
    "chronic hepatitis B", "Alzheimer's disease",
    "moderate-to-severe ulcerative colitis", "primary hyperoxaluria",
    "chronic obstructive pulmonary disease", "schizophrenia",
    "major depressive disorder", "psoriasis",
    "iron-deficiency anemia", "essential hypertension",
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


def pick_most_sensitive(rng: random.Random) -> list[tuple[str, float]]:
    """Generate 2-3 species NOAELs, return sorted by HED (most sensitive first)."""
    n_species = rng.choice([2, 3])
    species_pool = rng.sample(SPECIES_FOR_NOAEL, n_species)
    out = []
    for sp in species_pool:
        noael = rng.choice(NOAEL_VALUES)
        out.append((sp, float(noael)))
    # Most sensitive = lowest HED = lowest (NOAEL / divisor)
    out.sort(key=lambda x: x[1] / BSA_DIVISOR[x[0]])
    return out


def build_user_prompt(species_noaels: list[tuple[str, float]], study: str, indication: str) -> str:
    species_list = ", ".join(f"{sp} {n} mg/kg/day" for sp, n in species_noaels)
    return (
        f"In a {study} for an investigational small-molecule therapeutic targeting "
        f"{indication}, NOAELs were established as follows: {species_list}. "
        f"Identify the most sensitive species, compute the Human Equivalent Dose, "
        f"and propose the Maximum Recommended Starting Dose for first-in-human Phase I "
        f"dosing in healthy adult volunteers. Cite ICH M3(R2) and FDA 2005 MRSD guidance."
    )


# Three prose variants (chosen randomly per example) to break template memorization.
ASSISTANT_VARIANTS = [
    # Variant A — explanatory
    "Selection of the most sensitive species is based on the lowest derived HED. Among "
    "the species evaluated, the {species} (NOAEL {noael} mg/kg/day) yielded the lowest HED "
    "of {hed:.2f} mg/kg using the FDA 2005 body-surface-area conversion factor of {divisor}. "
    "{sf_rationale} Applying a safety factor of {sf_str}, an MRSD of {mrsd:.3f} mg/kg is "
    "recommended for the first-in-human single-ascending-dose study, consistent with "
    "ICH M3(R2) phase-appropriate nonclinical support.",
    # Variant B — methodological
    "Per FDA 2005 guidance on Estimating the Maximum Safe Starting Dose, HED was derived "
    "for each tested species by dividing the NOAEL by the body-surface-area conversion "
    "factor. The {species} was identified as the most sensitive species with a NOAEL of "
    "{noael} mg/kg/day, yielding an HED of {hed:.2f} mg/kg (BSA factor {divisor}). "
    "{sf_rationale} The MRSD of {mrsd:.3f} mg/kg, calculated using a safety factor of "
    "{sf_str}, is proposed in accordance with ICH M3(R2).",
    # Variant C — concise
    "The {species} was the most sensitive species (NOAEL {noael} mg/kg/day). The HED of "
    "{hed:.2f} mg/kg was calculated using the BSA conversion factor of {divisor} per FDA "
    "2005 guidance. {sf_rationale} An MRSD of {mrsd:.3f} mg/kg is proposed using a safety "
    "factor of {sf_str}, supporting Phase I per ICH M3(R2).",
]


def build_assistant(species: str, noael: float, safety_factor: float, rng: random.Random) -> str:
    divisor = BSA_DIVISOR[species]
    hed = noael / divisor
    mrsd = hed / safety_factor

    sf_rationale = (
        "The default 10-fold safety factor accounts for interspecies and intraspecies variability."
        if safety_factor == 10.0
        else f"A safety factor of {int(safety_factor)} is applied due to elevated clinical "
             "risk: steep dose-response slope, limited reversibility, or novel target mechanism."
    )
    sf_str = str(int(safety_factor)) if safety_factor.is_integer() else str(safety_factor)

    template = rng.choice(ASSISTANT_VARIANTS)
    return template.format(
        species=species, noael=noael, hed=hed, divisor=divisor,
        mrsd=mrsd, sf_rationale=sf_rationale, sf_str=sf_str,
    )


def make_example(rng: random.Random) -> dict:
    species_noaels = pick_most_sensitive(rng)
    species, noael = species_noaels[0]  # most sensitive
    safety_factor = rng.choice(SAFETY_FACTORS)
    study = rng.choice(STUDY_DESIGNS)
    indication = rng.choice(INDICATIONS)

    user = build_user_prompt(species_noaels, study, indication)
    assistant = build_assistant(species, noael, safety_factor, rng)

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
