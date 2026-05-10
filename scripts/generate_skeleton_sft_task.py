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


def split_into_sentences(text: str) -> list[str]:
    """Crude sentence split — good enough for routing prose into subsections."""
    import re
    # Keep abbreviations like "e.g." intact-ish
    sents = re.split(r"(?<=[.!?])\s+(?=[A-Z])", text.strip())
    return [s.strip() for s in sents if s.strip()]


def route_sentence(sentence: str, kw_map: dict[str, list[str]]) -> str | None:
    s = sentence.lower()
    best, best_hits = None, 0
    for sub, kws in kw_map.items():
        hits = sum(1 for kw in kws if kw in s)
        if hits > best_hits:
            best, best_hits = sub, hits
    return best


def build_skeleton(prose: str, section_id: str) -> str:
    required = REQUIRED_SUBSECTIONS[section_id]
    kw_map = SUBSECTION_KEYWORDS.get(section_id, {})

    buckets: dict[str, list[str]] = {h: [] for h in required}
    sents = split_into_sentences(prose)

    if not sents:
        return ""

    # First sentence → Brief Summary
    buckets["brief summary"].append(sents[0])

    for sent in sents[1:]:
        sub = route_sentence(sent, kw_map)
        if sub is None:
            continue
        buckets[sub].append(sent)

    # Anything still unrouted goes into Discussion
    discussion_key = next((h for h in required if h.startswith("discussion")), None)
    if discussion_key:
        leftover = [s for s in sents[1:] if route_sentence(s, kw_map) is None]
        buckets[discussion_key].extend(leftover[:3])  # cap to keep section tight

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

            skeleton = build_skeleton(prose, sec)
            if not skeleton:
                skipped += 1
                continue

            r = validate_structure(skeleton, sec)
            if not r.passed:
                skipped += 1
                continue

            user_prompt = user_of(row)
            new_user = (
                f"{user_prompt}\n\nReorganize the above source data into the ICH M4S(R2) "
                f"§{sec} subsection structure. Use the required subsection headings in "
                f"order. Mark any subsection without source data as [NO DATA AVAILABLE]."
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
