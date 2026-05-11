"""
Generate ICH M4S(R2) §2.6.7 tabulated-summary SFT task examples (v6 task #8).

Given §2.6.6 narrative inputs, emit the corresponding §2.6.7.x markdown table
with required columns per ICH template. Every example self-verifies against
tabulated_summary.verify_table.

Usage:
    python scripts/generate_tabulated_sft_task.py --n 300
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.drug_discovery.tabulated_summary import (
    TEMPLATE_COLUMNS, TEMPLATE_NAMES, verify_table,
)

SYSTEM_PROMPT = (
    "You are a regulatory medical writer preparing ICH M4S(R2) §2.6.7 tabulated "
    "summary tables. Given the source nonclinical findings, emit the corresponding "
    "§2.6.7.x table as a markdown table with ALL required columns in the prescribed "
    "ICH template order. Each row corresponds to one study."
)

# Sampler pools
SPECIES_RODENT = ["Sprague-Dawley rat", "Wistar rat", "CD-1 mouse", "C57BL/6 mouse"]
SPECIES_NONRODENT = ["beagle dog", "cynomolgus monkey", "Göttingen minipig", "New Zealand white rabbit"]
ROUTES = ["oral gavage", "intravenous bolus", "subcutaneous", "intravenous infusion", "oral (dietary)"]

DURATIONS_REPEAT = ["14 days", "28 days", "90 days", "26 weeks", "39 weeks"]
DURATIONS_CARC = ["104 weeks", "26 weeks"]

REPEAT_FINDINGS = [
    "mild hepatic enzyme elevation at the high dose",
    "transient body-weight loss at the high dose",
    "salivation observed peri-dose at all dose levels (non-adverse)",
    "no test-article-related findings",
    "minimal renal tubular vacuolation at the high dose (non-adverse)",
    "emesis at the high dose (procedural, non-adverse)",
]
TUMOR_FINDINGS = [
    "no test-article-related neoplastic findings",
    "increased incidence of pituitary adenomas at the high dose",
    "no neoplastic findings considered test-article-related",
    "hepatocellular adenoma trend not statistically significant",
]
DEV_FINDINGS = [
    "no maternal or developmental toxicity at any dose",
    "reduced fetal body weight at the high dose",
    "skeletal variations at the high dose; no malformations",
    "embryolethality at the high dose",
]
INVITRO_SYSTEMS = [
    "Salmonella typhimurium TA98/TA100/TA1535/TA1537/TA102",
    "L5178Y mouse lymphoma cells",
    "Chinese hamster ovary (CHO) cells",
    "human peripheral blood lymphocytes",
]
INVITRO_RESULTS = ["negative", "negative", "negative", "equivocal", "positive at top concentration"]
INVIVO_GENOTOX_RESULTS = ["negative", "negative", "negative", "negative", "equivocal"]


def doses(rng: random.Random, scale: int = 100) -> str:
    base = rng.choice([1, 3, 10, 30])
    return f"0, {base*scale//10}, {base*scale//3}, {base*scale}"


def build_repeat_dose(rng: random.Random) -> tuple[str, str]:
    rodent_sp = rng.choice(SPECIES_RODENT)
    nonrodent_sp = rng.choice(SPECIES_NONRODENT)
    route = rng.choice(ROUTES)
    dur = rng.choice(DURATIONS_REPEAT)
    rod_doses = doses(rng, scale=100)
    nr_doses = doses(rng, scale=30)
    rod_noael = rod_doses.split(", ")[-2]
    nr_noael = nr_doses.split(", ")[-2]
    rod_find = rng.choice(REPEAT_FINDINGS)
    nr_find = rng.choice(REPEAT_FINDINGS)

    src = (
        f"A {dur} repeat-dose toxicity study was conducted in {rodent_sp} via "
        f"{route} at doses of {rod_doses} mg/kg/day. Findings: {rod_find}. "
        f"NOAEL was identified as {rod_noael} mg/kg/day. A parallel {dur} study "
        f"in {nonrodent_sp} via {route} at doses of {nr_doses} mg/kg/day showed "
        f"{nr_find}; NOAEL {nr_noael} mg/kg/day."
    )
    table = (
        "| Study | Species | Method of Administration | Duration | Doses (mg/kg/day) | NOAEL (mg/kg/day) | Findings |\n"
        "|-------|---------|--------------------------|----------|-------------------|-------------------|----------|\n"
        f"| repeat-dose tox (rodent) | {rodent_sp} | {route} | {dur} | {rod_doses} | {rod_noael} | {rod_find} |\n"
        f"| repeat-dose tox (non-rodent) | {nonrodent_sp} | {route} | {dur} | {nr_doses} | {nr_noael} | {nr_find} |\n"
    )
    return src, table


def _label_for_system(system: str) -> str:
    s = system.lower()
    if "salmonella" in s:
        return "bacterial reverse mutation (Ames)"
    if "lymphoma" in s:
        return "mouse lymphoma gene mutation"
    if "cho" in s or "chinese hamster" in s:
        return "chromosomal aberration"
    if "lymphocyte" in s:
        return "human lymphocyte chromosomal aberration"
    return "in vitro mammalian assay"


def build_invitro_genotox(rng: random.Random) -> tuple[str, str]:
    # Always include one Salmonella (Ames) system + one mammalian system,
    # per ICH S2(R1) standard battery.
    salmonella = [s for s in INVITRO_SYSTEMS if "Salmonella" in s][0]
    mammalian_pool = [s for s in INVITRO_SYSTEMS if "Salmonella" not in s]
    sys1 = salmonella
    sys2 = rng.choice(mammalian_pool)
    res1 = rng.choice(INVITRO_RESULTS)
    res2 = rng.choice(INVITRO_RESULTS)
    src = (
        f"In vitro genotoxicity was evaluated in the {sys1} (result: {res1}) and "
        f"{sys2} (result: {res2}), both with and without S9 metabolic activation, "
        f"per ICH S2(R1)."
    )
    table = (
        "| Study | Test System | Concentration (µg/mL) | Metabolic Activation | Result |\n"
        "|-------|-------------|-----------------------|----------------------|--------|\n"
        f"| {_label_for_system(sys1)} | {sys1} | 0–5000 | ± S9 | {res1} |\n"
        f"| {_label_for_system(sys2)} | {sys2} | 0–500 | ± S9 | {res2} |\n"
    )
    return src, table


def build_invivo_genotox(rng: random.Random) -> tuple[str, str]:
    sp = rng.choice(["CD-1 mouse", "Sprague-Dawley rat"])
    route = rng.choice(ROUTES)
    d = doses(rng, scale=100)
    res = rng.choice(INVIVO_GENOTOX_RESULTS)
    src = (
        f"An in vivo micronucleus assay was conducted in {sp} via {route} at "
        f"doses of {d} mg/kg. Result: {res} per ICH S2(R1)."
    )
    table = (
        "| Study | Species | Method of Administration | Doses (mg/kg) | Result |\n"
        "|-------|---------|--------------------------|---------------|--------|\n"
        f"| in vivo micronucleus | {sp} | {route} | {d} | {res} |\n"
    )
    return src, table


def build_carcinogenicity(rng: random.Random) -> tuple[str, str]:
    rodent_sp = rng.choice(["Sprague-Dawley rat", "CD-1 mouse"])
    second_sp = "Tg.rasH2 mouse" if "rat" in rodent_sp else "Sprague-Dawley rat"
    route = "oral (dietary)"
    dur1 = "104 weeks"
    dur2 = "26 weeks" if "Tg.rasH2" in second_sp else "104 weeks"
    d1 = doses(rng, scale=100)
    d2 = doses(rng, scale=100)
    noael1 = d1.split(", ")[-2]
    noael2 = d2.split(", ")[-2]
    t1 = rng.choice(TUMOR_FINDINGS)
    t2 = rng.choice(TUMOR_FINDINGS)
    src = (
        f"Long-term carcinogenicity studies per ICH S1A: {dur1} in {rodent_sp} at "
        f"doses {d1} mg/kg/day ({t1}; NOAEL {noael1}). {dur2} in {second_sp} at "
        f"doses {d2} mg/kg/day ({t2}; NOAEL {noael2})."
    )
    table = (
        "| Study | Species | Method of Administration | Duration | Doses (mg/kg/day) | Tumor Findings | NOAEL (mg/kg/day) |\n"
        "|-------|---------|--------------------------|----------|-------------------|----------------|-------------------|\n"
        f"| 2-year carcinogenicity | {rodent_sp} | {route} | {dur1} | {d1} | {t1} | {noael1} |\n"
        f"| alternate-model carcinogenicity | {second_sp} | {route} | {dur2} | {d2} | {t2} | {noael2} |\n"
    )
    return src, table


def build_reproductive(rng: random.Random) -> tuple[str, str]:
    sp1 = rng.choice(["Sprague-Dawley rat", "Wistar rat"])
    sp2 = "New Zealand white rabbit"
    route = "oral gavage"
    d1 = doses(rng, scale=100)
    d2 = doses(rng, scale=30)
    noael1 = d1.split(", ")[-2]
    noael2 = d2.split(", ")[-2]
    f1 = rng.choice(DEV_FINDINGS)
    f2 = rng.choice(DEV_FINDINGS)
    src = (
        f"Embryo-fetal development studies per ICH S5(R3): {sp1} at doses {d1} "
        f"mg/kg/day ({f1}; NOAEL {noael1}). {sp2} at doses {d2} mg/kg/day "
        f"({f2}; NOAEL {noael2})."
    )
    table = (
        "| Study | Species | Method of Administration | Doses (mg/kg/day) | NOAEL (mg/kg/day) | Developmental Findings |\n"
        "|-------|---------|--------------------------|-------------------|-------------------|------------------------|\n"
        f"| embryo-fetal development (rodent) | {sp1} | {route} | {d1} | {noael1} | {f1} |\n"
        f"| embryo-fetal development (non-rodent) | {sp2} | {route} | {d2} | {noael2} | {f2} |\n"
    )
    return src, table


BUILDERS = {
    "2.6.7.7":  build_repeat_dose,
    "2.6.7.8":  build_invitro_genotox,
    "2.6.7.9":  build_invivo_genotox,
    "2.6.7.10": build_carcinogenicity,
    "2.6.7.11": build_reproductive,
}


def make_example(rng: random.Random, template_id: str) -> dict:
    src, table = BUILDERS[template_id](rng)
    template_name = TEMPLATE_NAMES[template_id]
    user = (
        f"Generate the §{template_id} ({template_name}) tabulated summary per "
        f"ICH M4S(R2). Use the prescribed required columns in order; one row per "
        f"study.\n\nSource findings:\n{src}"
    )
    assistant = (
        f"§{template_id} {template_name} — tabulated summary:\n\n{table}"
    )
    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user},
            {"role": "assistant", "content": assistant},
        ],
        "meta": {
            "task": "tabulated_summary",
            "section_type": "tox_overview",
            "template_id": template_id,
        },
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=300)
    ap.add_argument("--out", type=Path,
                    default=ROOT / "data/regulatory_training/tasks/task8_tabulated_summary.jsonl")
    ap.add_argument("--seed", type=int, default=20260510)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    args.out.parent.mkdir(parents=True, exist_ok=True)

    written = 0
    failed = 0
    template_ids = list(BUILDERS.keys())
    with args.out.open("w") as f:
        while written < args.n:
            tid = template_ids[written % len(template_ids)]
            ex = make_example(rng, tid)
            r = verify_table(ex["messages"][-1]["content"], tid)
            if not r.passed:
                failed += 1
                if failed > args.n * 2:
                    raise RuntimeError("too many self-verification failures")
                continue
            f.write(json.dumps(ex) + "\n")
            written += 1

    print(f"Wrote {written} tabulated-summary examples to {args.out}")
    print(f"Rejected {failed} (should be 0)")


if __name__ == "__main__":
    main()
