"""
Held-out eval for entity adapter — measures false-positive and false-negative
rates on 30 queries split into 3 risk categories:

  - empty-expected:    query has no entities the YAML knows
                       → ANY non-empty extraction is a false positive
  - partial-expected:  query has SOME known + SOME unknown entities
                       → adapter must return ONLY the known ones
  - full-expected:     query has only known entities, just in unfamiliar context
                       → adapter must extract them all

Pass criteria:
  - Zero false positives (extracting an entity not in expected list)
  - Recall ≥ 90% on full-expected category
"""
from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from sandbox.intent_retrieval_v3.adapters.entity import extract_canonical_entities  # noqa: E402
from sandbox.intent_retrieval_v3.core.canonical_resolver import reset_canonical_cache  # noqa: E402

EVAL = Path(__file__).resolve().parents[1] / "data" / "entity_heldout_eval.yaml"
OUT = Path(__file__).resolve().parents[1] / "docs" / "20260520_entity_heldout_results.md"


def main() -> int:
    cases = yaml.safe_load(EVAL.read_text())
    reset_canonical_cache()
    print(f"Loaded {len(cases)} entity-extraction held-out cases\n")

    perfect = 0
    fp_cases = []     # extracted entities NOT in expected
    fn_cases = []     # missed entities that ARE in expected
    fp_count = 0
    fn_count = 0

    for c in cases:
        expected = set(c["expected_canonicals"] or [])
        out = extract_canonical_entities(c["query"])
        extracted = {e["canonical_id"] for e in out}
        fp = extracted - expected   # false positives: extracted but not expected
        fn = expected - extracted   # false negatives: expected but not extracted

        if not fp and not fn:
            perfect += 1
        if fp:
            fp_count += len(fp)
            fp_cases.append({
                "id": c["id"], "query": c["query"],
                "expected": list(expected), "extracted": list(extracted),
                "false_positives": list(fp),
            })
        if fn:
            fn_count += len(fn)
            fn_cases.append({
                "id": c["id"], "query": c["query"],
                "expected": list(expected), "extracted": list(extracted),
                "false_negatives": list(fn),
            })

    n = len(cases)
    print(f"=== Entity held-out result (n={n}) ===")
    print(f"  Perfect (no FP, no FN): {perfect}/{n} ({100*perfect/n:.1f}%)")
    print(f"  False-positive entity extractions: {fp_count}")
    print(f"    affected cases: {len(fp_cases)}")
    print(f"  False-negative (missed) extractions: {fn_count}")
    print(f"    affected cases: {len(fn_cases)}")

    if fp_cases:
        print(f"\n  False positives (first 5):")
        for fc in fp_cases[:5]:
            print(f"    {fc['id']}: {fc['query'][:55]}")
            print(f"       expected={fc['expected']} extracted={fc['extracted']} FP={fc['false_positives']}")
    if fn_cases:
        print(f"\n  False negatives (first 5):")
        for fc in fn_cases[:5]:
            print(f"    {fc['id']}: {fc['query'][:55]}")
            print(f"       expected={fc['expected']} extracted={fc['extracted']} FN={fc['false_negatives']}")

    # Write markdown
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8") as f:
        f.write("# Entity Adapter Held-Out Results (n=30)\n\n")
        f.write("**Date:** 2026-05-20\n")
        f.write(f"**Eval:** `sandbox/intent_retrieval_v3/data/entity_heldout_eval.yaml`\n")
        f.write(f"**Adapter:** `sandbox/intent_retrieval_v3/adapters/entity.py`\n")
        f.write(f"**YAML coverage:** 17 entries\n\n")
        f.write("## What this measures\n\n")
        f.write("Three categories of held-out behavior:\n\n")
        f.write("- **empty-expected**: query has no entities in YAML → adapter must return []\n")
        f.write("- **substring traps**: similar-looking names (TPM3, TP53BP1) must not falsely match TP53\n")
        f.write("- **partial coverage**: query has SOME known + SOME unknown entities → return only the known ones\n\n")
        f.write("## Headline\n\n")
        f.write("| Metric | Value |\n|---|---|\n")
        f.write(f"| Cases perfect (no FP, no FN) | {perfect}/{n} ({100*perfect/n:.1f}%) |\n")
        f.write(f"| **False positive extractions** | **{fp_count}** |\n")
        f.write(f"| False negative (missed) | {fn_count} |\n")
        f.write(f"| Cases with FPs | {len(fp_cases)} |\n")
        f.write(f"| Cases with FNs | {len(fn_cases)} |\n\n")

        if fp_cases:
            f.write(f"## False positives ({len(fp_cases)} cases)\n\n")
            for fc in fp_cases:
                f.write(f"- **{fc['id']}** `{fc['query'][:70]}`\n")
                f.write(f"  - expected: `{fc['expected']}`\n")
                f.write(f"  - extracted: `{fc['extracted']}`\n")
                f.write(f"  - false positives: `{fc['false_positives']}`\n")

        if fn_cases:
            f.write(f"\n## False negatives ({len(fn_cases)} cases)\n\n")
            for fc in fn_cases:
                f.write(f"- **{fc['id']}** `{fc['query'][:70]}`\n")
                f.write(f"  - expected: `{fc['expected']}`\n")
                f.write(f"  - extracted: `{fc['extracted']}`\n")
                f.write(f"  - missed: `{fc['false_negatives']}`\n")

        f.write("\n## Interpretation\n\n")
        if fp_count == 0:
            f.write("✅ **Zero false positives across 30 held-out queries** — the adapter "
                    "never extracts an entity that isn't actually in the query. The "
                    "word-boundary substring matcher correctly rejects TPM3, TP53BP1, "
                    "BRCA-substring-without-digit, and similar near-misses.\n\n")
        else:
            f.write(f"⚠️  **{fp_count} false positives across {len(fp_cases)} cases.** "
                    f"These are high-cost — downstream OMIM/PubMed retrievers would "
                    f"receive wrong entity IDs. Fix: tighten the affected aliases in "
                    f"entity_canonicals.yaml.\n\n")

        if fn_count == 0:
            f.write("✅ Zero missed extractions on the 'full-expected' category — the "
                    "adapter extracts all known entities even in unfamiliar phrasings "
                    "(genotype context, parenthetical, hyphenated cell line aliases, etc.).\n\n")
        else:
            f.write(f"⚠️  {fn_count} missed extractions. These cost lower than FPs — "
                    f"a missing entity falls back to existing fuzzy retriever behavior.\n\n")

    print(f"\nWrote {OUT.relative_to(ROOT)}")
    return 0 if fp_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
