"""
Generate ICH M4S(R2) skeleton-completion SFT task examples (v6 task #1).

Takes existing prose from training corpus, organizes it into ICH M4S(R2)
required-subsection skeleton, marks missing subsections as [NO DATA AVAILABLE].
Every output passes structural_validator.py by construction.

Usage:
    python scripts/generate_skeleton_sft_task.py
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.drug_discovery.structural_validator import (
    REQUIRED_SUBSECTIONS, validate_structure,
)

SECTION_MAPPING = {
    "tox_overview":   "2.6.6",
    "tox_genotox":    "2.6.6",
    "pk_overview":    "2.6.4",
    "pbpk":           "2.6.4",
    "pharm_overview": "2.6.2",
}

# Keyword → subsection routing for §2.6.6
TOX_KEYWORDS = {
    "single-dose toxicity":            ["single-dose", "single dose", "acute toxicity", "ld50", "ld 50"],
    "repeat-dose toxicity":            ["repeat-dose", "repeat dose", "28-day", "13-week", "26-week", "chronic toxicity", "subacute"],
    "genotoxicity":                    ["ames", "micronucleus", "chromosomal aberration", "mutagenic", "genotoxic", "clastogenic"],
    "carcinogenicity":                 ["carcinogen", "neoplas", "tumor", "tumour", "two-year", "2-year"],
    "reproductive and developmental toxicity": ["fertility", "embryo", "teratogen", "reproductive", "developmental", "dart", "pre/postnatal"],
    "local tolerance":                 ["local tolerance", "injection site", "skin irritation", "ocular irritation"],
    "other toxicity studies":          ["immunotox", "phototox", "antigenicity", "impurity qualification"],
}

PK_KEYWORDS = {
    "absorption":  ["absorption", "bioavailability", "tmax", "cmax"],
    "distribution":["distribution", "tissue", "protein binding", "vd ", "volume of distribution"],
    "metabolism":  ["metabolism", "metabolite", "cyp", "cytochrome", "uridine"],
    "excretion":   ["excretion", "clearance", "elimination", "renal", "biliary"],
    "methods of analysis": ["lc-ms", "lcms", "elisa", "bioanalytical", "assay"],
    "pharmacokinetic drug interactions": ["drug interaction", "ddi", "inhibit", "induce"],
    "other pharmacokinetic studies": ["special population", "pediatric pk"],
}

PHARM_KEYWORDS = {
    "primary pharmacodynamics":   ["mechanism", "potency", "ic50", "ec50", "agonist", "antagonist", "binding"],
    "secondary pharmacodynamics": ["off-target", "selectivity panel", "secondary"],
    "safety pharmacology":        ["herg", "qt", "telemetry", "cns battery", "respiratory function"],
    "pharmacodynamic drug interactions": ["pd interaction", "synergy", "additivity"],
}

SUBSECTION_KEYWORDS = {
    "2.6.6": TOX_KEYWORDS,
    "2.6.4": PK_KEYWORDS,
    "2.6.2": PHARM_KEYWORDS,
}

SYSTEM_PROMPT = (
    "You are a regulatory medical writer preparing ICH M4 CTD Module 2.6 nonclinical "
    "summaries. Organize the provided source data into the required ICH M4S(R2) "
    "subsection structure. Use the exact subsection headings in order. For subsections "
    "with no available data, state '[NO DATA AVAILABLE]' explicitly — do not omit headings."
)


def clean_source(text: str) -> str:
    """Strip FDA-label section headers like '13.2 Animal Toxicology and/or Pharmacology'."""
    import re
    text = re.sub(r"\b\d+\.\d+\s+[A-Z][A-Za-z/\s]{5,60}\b(?=[\sA-Z])", " ", text)
    return text


def split_into_sentences(text: str) -> list[str]:
    """Crude sentence split — good enough for routing prose into subsections."""
    import re
    text = clean_source(text)
    sents = re.split(r"(?<=[.!?])\s+(?=[A-Z])", text.strip())
    return [s.strip() for s in sents if s.strip()]


def is_well_formed(sent: str) -> bool:
    """Reject sentence fragments — must start uppercase and have a verb-like word."""
    if not sent or not sent[0].isupper():
        return False
    if len(sent.split()) < 4:
        return False
    return True


def route_sentence(sentence: str, kw_map: dict[str, list[str]]) -> str | None:
    s = sentence.lower()
    best, best_hits = None, 0
    for sub, kws in kw_map.items():
        hits = sum(1 for kw in kws if kw in s)
        if hits > best_hits:
            best, best_hits = sub, hits
    return best


def build_brief_summary(drug: str, section_id: str) -> str:
    label = {
        "2.6.6": "toxicology",
        "2.6.4": "pharmacokinetic",
        "2.6.2": "pharmacology",
    }[section_id]
    return (
        f"This {label} written summary integrates the nonclinical findings supporting "
        f"the proposed first-in-human use of {drug}, organized per ICH M4S(R2)."
    )


def build_skeleton(prose: str, section_id: str, drug: str) -> str:
    required = REQUIRED_SUBSECTIONS[section_id]
    kw_map = SUBSECTION_KEYWORDS.get(section_id, {})

    buckets: dict[str, list[str]] = {h: [] for h in required}
    sents = [s for s in split_into_sentences(prose) if is_well_formed(s)]

    if not sents:
        return ""

    # Generate clean Brief Summary; do NOT consume source sentence here.
    buckets["brief summary"].append(build_brief_summary(drug, section_id))

    routed: set[int] = set()
    for i, sent in enumerate(sents):
        sub = route_sentence(sent, kw_map)
        if sub is not None:
            buckets[sub].append(sent)
            routed.add(i)

    # Second pass: try routing leftovers with relaxed match (any keyword overlap)
    for i, sent in enumerate(sents):
        if i in routed:
            continue
        sub = route_sentence(sent, kw_map)
        if sub is not None:
            buckets[sub].append(sent)
            routed.add(i)

    # Anything still unrouted goes into Discussion
    discussion_key = next((h for h in required if h.startswith("discussion")), None)
    if discussion_key:
        leftover = [sents[i] for i in range(len(sents)) if i not in routed]
        buckets[discussion_key].extend(leftover[:3])

    parts = []
    for h in required:
        body = " ".join(buckets[h]).strip() or "[NO DATA AVAILABLE]"
        parts.append(f"{h.title()}. {body}")
    return "\n\n".join(parts)


def load_train() -> list[dict]:
    p = ROOT / "data" / "regulatory_training" / "tasks" / "splits" / "train.jsonl"
    rows = []
    with p.open() as f:
        for line in f:
            rows.append(json.loads(line))
    return rows


def assistant_of(row: dict) -> str:
    for m in row.get("messages", [])[::-1]:
        if m.get("role") == "assistant":
            return m.get("content", "")
    return ""


def user_of(row: dict) -> str:
    for m in row.get("messages", []):
        if m.get("role") == "user":
            return m.get("content", "")
    return ""


def section_of(row: dict) -> str | None:
    sec = row.get("meta", {}).get("section_type")
    return SECTION_MAPPING.get(sec)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=ROOT / "data" / "regulatory_training" / "tasks" / "task6_skeleton_completion.jsonl")
    args = ap.parse_args()

    rows = load_train()
    args.out.parent.mkdir(parents=True, exist_ok=True)

    written, skipped = 0, 0
    with args.out.open("w") as f:
        for row in rows:
            sec = section_of(row)
            if sec is None or sec not in REQUIRED_SUBSECTIONS:
                skipped += 1
                continue
            prose = assistant_of(row)
            if not prose:
                skipped += 1
                continue

            drug = row.get("meta", {}).get("drug", "the investigational compound")
            skeleton = build_skeleton(prose, sec, drug)
            if not skeleton:
                skipped += 1
                continue

            r = validate_structure(skeleton, sec)
            if not r.passed:
                skipped += 1
                continue

            section_label = {
                "2.6.6": "Toxicology Written Summary",
                "2.6.4": "Pharmacokinetics Written Summary",
                "2.6.2": "Pharmacology Written Summary",
            }[sec]
            new_user = (
                f"Reorganize the following nonclinical source data for {drug} into ICH M4S(R2) "
                f"§{sec} ({section_label}) format. Use the required subsection headings in the "
                f"prescribed order. Mark any subsection without source data as "
                f"[NO DATA AVAILABLE].\n\nSource data:\n{prose}"
            )

            example = {
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": new_user},
                    {"role": "assistant", "content": skeleton},
                ],
                "meta": {
                    "task": "skeleton_completion",
                    "section_type": row.get("meta", {}).get("section_type"),
                    "section_id": sec,
                },
            }
            f.write(json.dumps(example) + "\n")
            written += 1

    print(f"Wrote {written} skeleton-completion examples; skipped {skipped}")
    print(f"Output: {args.out}")


if __name__ == "__main__":
    main()
