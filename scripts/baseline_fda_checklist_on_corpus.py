"""
Baseline FDA reviewer checklist v2 checkers against the gold training corpus.

Runs MRSD verifier (C1) and structural validator (A) on the training pairs.
Tells us what the upper bound looks like — if real FDA text fails these
checkers often, the checkers are too strict; if it passes, the checkers are
calibrated and we can use them as eval metrics for v4 generations.

Usage:
    python scripts/baseline_fda_checklist_on_corpus.py
"""
from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.drug_discovery.mrsd_verifier import verify_mrsd
from galaxy.ai.drug_discovery.structural_validator import (
    REQUIRED_SUBSECTIONS, validate_structure,
)

TEST_PATH = ROOT / "data" / "regulatory_training" / "tasks" / "splits" / "test.jsonl"


def load_test() -> list[dict]:
    rows = []
    with TEST_PATH.open() as f:
        for line in f:
            rows.append(json.loads(line))
    return rows


def text_of(row: dict) -> str:
    # Training pairs are typically {"messages": [...]} with last assistant msg as target
    if "messages" in row:
        for m in row["messages"][::-1]:
            if m.get("role") == "assistant":
                return m.get("content", "")
    return row.get("output", row.get("target", ""))


def section_of(row: dict) -> str | None:
    sec = (row.get("section_type")
           or row.get("metadata", {}).get("section_type")
           or row.get("meta", {}).get("section_type"))
    mapping = {
        "tox_overview":   "2.6.6",
        "tox_genotox":    "2.6.6",
        "pk_overview":    "2.6.4",
        "pbpk":           "2.6.4",
        "pharm_overview": "2.6.2",
    }
    return mapping.get(sec)


def main():
    rows = load_test()
    print(f"Loaded {len(rows)} test examples from {TEST_PATH}")

    mrsd_grounded = 0
    mrsd_passed = 0
    mrsd_issues: Counter = Counter()

    structural_attempted = 0
    structural_passed = 0
    structural_missing_count: Counter = Counter()

    for row in rows:
        text = text_of(row)
        if not text:
            continue

        m = verify_mrsd(text)
        if m.grounded:
            mrsd_grounded += 1
            if m.passed:
                mrsd_passed += 1
            for issue in m.issues:
                mrsd_issues[issue.split(":")[0]] += 1

        sec = section_of(row)
        if sec and sec in REQUIRED_SUBSECTIONS:
            structural_attempted += 1
            r = validate_structure(text, sec)
            if r.passed:
                structural_passed += 1
            for h in r.missing:
                structural_missing_count[f"{sec}:{h}"] += 1

    print()
    print("=== MRSD verifier (C1) ===")
    print(f"  grounded (had NOAEL+species): {mrsd_grounded} / {len(rows)} "
          f"({100*mrsd_grounded/max(len(rows),1):.1f}%)")
    if mrsd_grounded:
        print(f"  passed (no arithmetic errors): {mrsd_passed} / {mrsd_grounded} "
              f"({100*mrsd_passed/mrsd_grounded:.1f}%)")
        print(f"  top issues: {dict(mrsd_issues.most_common(5))}")

    print()
    print("=== Structural validator (A) ===")
    print(f"  attempted (mappable section): {structural_attempted} / {len(rows)}")
    if structural_attempted:
        print(f"  passed (all subsections + order): {structural_passed} / {structural_attempted} "
              f"({100*structural_passed/structural_attempted:.1f}%)")
        print(f"  top missing: {dict(structural_missing_count.most_common(8))}")


if __name__ == "__main__":
    main()
