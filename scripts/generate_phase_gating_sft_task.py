"""
Generate ICH M3(R2) phase-gating SFT task examples (v6 task #7).

Given a proposed clinical trial design (phase, duration, population), output
the required nonclinical study list. Every example self-verifies against
phase_gating.verify_phase_gating.

Usage:
    python scripts/generate_phase_gating_sft_task.py --n 300
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.drug_discovery.phase_gating import (
    PhaseGatingRequirements, required_studies, verify_phase_gating,
)

PHASE_DURATIONS: dict[str, list[int]] = {
    "I":   [7, 14, 28],
    "II":  [30, 60, 90, 180],
    "III": [180, 270, 365, 730],
}
POPULATIONS = ["healthy_adult", "patient", "wocbp"]
INDICATIONS = [
    "moderate-to-severe psoriasis", "type 2 diabetes mellitus",
    "rheumatoid arthritis", "chronic kidney disease",
    "Alzheimer's disease", "ulcerative colitis", "atopic dermatitis",
    "essential hypertension", "major depressive disorder",
    "primary biliary cholangitis", "iron-deficiency anemia",
    "schizophrenia", "chronic obstructive pulmonary disease",
]

SYSTEM_PROMPT = (
    "You are a regulatory affairs scientist preparing nonclinical justification "
    "for an IND submission. Given a proposed clinical trial design, enumerate the "
    "nonclinical studies required to support that trial per ICH M3(R2), citing the "
    "applicable ICH guideline for each."
)

PROSE_OPENERS = [
    "The following nonclinical studies are required to support the proposed "
    "Phase {phase} clinical trial of up to {days} days in {pop_label}, per "
    "ICH M3(R2) and related ICH safety guidelines:",
    "To support the proposed Phase {phase} {pop_label} study with maximum "
    "treatment duration of {days} days, the following nonclinical package is "
    "required:",
    "Per ICH M3(R2), the nonclinical safety package supporting a Phase {phase} "
    "trial of up to {days} days in {pop_label} comprises:",
]

POP_LABELS = {
    "healthy_adult": "healthy adult volunteers",
    "patient":       "adult patients",
    "wocbp":         "women of childbearing potential",
    "pediatric":     "pediatric patients",
}


def make_user_prompt(phase: str, days: int, population: str, indication: str) -> str:
    return (
        f"Propose a Phase {phase} clinical trial in {POP_LABELS[population]} with "
        f"{indication} at maximum treatment duration of {days} days. Enumerate the "
        f"nonclinical studies required to support this trial per ICH M3(R2). Cite "
        f"the applicable ICH guideline for each study (ICH M3(R2) Table 1, ICH "
        f"S2(R1), ICH S7A, ICH S7B, ICH S5(R3), ICH S1A as applicable)."
    )


def make_assistant(req: PhaseGatingRequirements, rng: random.Random) -> str:
    opener = rng.choice(PROSE_OPENERS).format(
        phase=req.phase, days=req.trial_duration_days,
        pop_label=POP_LABELS[req.population],
    )
    bullets = []
    for s in req.required:
        bullets.append(f"- {s.name} ({s.citation}) — {s.rationale}.")
    return opener + "\n" + "\n".join(bullets)


def make_example(rng: random.Random) -> dict:
    phase = rng.choice(list(PHASE_DURATIONS.keys()))
    days = rng.choice(PHASE_DURATIONS[phase])
    population = rng.choice(POPULATIONS)
    indication = rng.choice(INDICATIONS)

    req = required_studies(phase, days, population)
    user = make_user_prompt(phase, days, population, indication)
    assistant = make_assistant(req, rng)

    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user},
            {"role": "assistant", "content": assistant},
        ],
        "meta": {
            "task": "phase_gating",
            "section_type": "tox_overview",
            "phase": phase,
            "trial_duration_days": days,
            "population": population,
        },
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=300)
    ap.add_argument("--out", type=Path,
                    default=ROOT / "data/regulatory_training/tasks/task7_phase_gating.jsonl")
    ap.add_argument("--seed", type=int, default=20260510)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    args.out.parent.mkdir(parents=True, exist_ok=True)

    written = 0
    failed = 0
    with args.out.open("w") as f:
        while written < args.n:
            ex = make_example(rng)
            assistant_text = ex["messages"][-1]["content"]
            req = required_studies(
                ex["meta"]["phase"], ex["meta"]["trial_duration_days"],
                ex["meta"]["population"],
            )
            r = verify_phase_gating(assistant_text, req)
            if not r.passed:
                failed += 1
                continue
            f.write(json.dumps(ex) + "\n")
            written += 1

    print(f"Wrote {written} phase-gating examples to {args.out}")
    print(f"Rejected {failed} that failed self-verification")


if __name__ == "__main__":
    main()
