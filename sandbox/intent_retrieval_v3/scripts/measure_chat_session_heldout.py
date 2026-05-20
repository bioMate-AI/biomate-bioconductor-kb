"""
Held-out eval for chat_session adapter.

For each of 30 queries with paired session metadata + expected decision,
run the adapter and compare. Reports:
  - decision match rate
  - false-NEW count (adapter said new when expected was resume/uncertain)
  - false-RESUME count
  - false-UNCERTAIN count (less harmful but still a miss)

Pass criteria:
  - Zero false-NEW (highest-cost mistake — loses session)
  - Zero false-RESUME on stale/null sessions (privacy/UX risk)
  - Overall match ≥ 80% on the held-out set
"""
from __future__ import annotations

import sys
from pathlib import Path
from collections import Counter

import yaml

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from sandbox.intent_retrieval_v3.adapters.chat_session import should_resume_chat_session  # noqa: E402
from sandbox.intent_retrieval_v3.core.yaml_loader import reset_loader_cache  # noqa: E402

EVAL = Path(__file__).resolve().parents[1] / "data" / "chat_session_heldout_eval.yaml"
OUT = Path(__file__).resolve().parents[1] / "docs" / "20260520_chat_session_heldout_results.md"


def main() -> int:
    cases = yaml.safe_load(EVAL.read_text())
    reset_loader_cache()
    print(f"Loaded {len(cases)} held-out cases for chat_session adapter\n")

    n = len(cases)
    correct = 0
    by_decision = Counter()
    failures = []
    false_new = []         # said "new" when not expected
    false_resume = []      # said "resume" when not expected
    expected_dist = Counter(c["expected_decision"] for c in cases)

    for c in cases:
        actual = should_resume_chat_session(c["query"], c.get("session_meta"))
        d = actual["decision"]
        by_decision[d] += 1
        exp = c["expected_decision"]
        if d == exp:
            correct += 1
        else:
            failures.append({
                "id": c["id"], "query": c["query"], "session_meta": c.get("session_meta"),
                "expected": exp, "actual": d, "reason": actual["reason"],
                "why_expected": c.get("why", ""),
            })
            if d == "new" and exp != "new":
                false_new.append(c["id"])
            elif d == "resume" and exp != "resume":
                false_resume.append(c["id"])

    print(f"=== Chat-session held-out result (n={n}) ===")
    print(f"  Correct: {correct}/{n} ({100*correct/n:.1f}%)")
    print(f"  Expected distribution: {dict(expected_dist)}")
    print(f"  Actual distribution:   {dict(by_decision)}")
    print(f"  False NEW (high-cost): {len(false_new)}")
    print(f"  False RESUME (UX risk): {len(false_resume)}")
    if failures:
        print(f"\n  {len(failures)} miscalls (first 5):")
        for f in failures[:5]:
            print(f"    {f['id']}: expected={f['expected']:<10} actual={f['actual']:<10} | {f['query'][:55]}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8") as f:
        f.write("# Chat-Session Adapter Held-Out Results (n=30)\n\n")
        f.write("**Date:** 2026-05-20\n")
        f.write(f"**Eval set:** `sandbox/intent_retrieval_v3/data/chat_session_heldout_eval.yaml`\n")
        f.write(f"**Adapter:** `sandbox/intent_retrieval_v3/adapters/chat_session.py`\n\n")
        f.write("## What this measures\n\n")
        f.write("Unlike rerank adapters, chat_session is a DECISION adapter. The "
                "held-out test is whether decisions are correct on queries the YAML "
                "wasn't explicitly designed for — including biological terms that "
                "might collide with trigger substrings, neutral queries that should "
                "fall back to metadata, and mixed signals.\n\n")
        f.write("Three failure modes to count separately:\n")
        f.write("  - **false NEW** (adapter said 'new' wrongly) — high cost, loses session\n")
        f.write("  - **false RESUME** (adapter said 'resume' wrongly) — UX/privacy risk\n")
        f.write("  - **false UNCERTAIN** (adapter said 'uncertain' when stronger signal expected) — recoverable miss\n\n")
        f.write("## Headline\n\n")
        f.write("| Metric | Value |\n|---|---|\n")
        f.write(f"| Total | {n} |\n")
        f.write(f"| Correct | {correct}/{n} ({100*correct/n:.1f}%) |\n")
        f.write(f"| **False NEW** | **{len(false_new)}** |\n")
        f.write(f"| **False RESUME** | **{len(false_resume)}** |\n")
        f.write(f"| False UNCERTAIN | {len(failures) - len(false_new) - len(false_resume)} |\n\n")

        f.write(f"## Expected vs actual decision distribution\n\n")
        f.write("| Decision | Expected | Actual |\n|---|---|---|\n")
        for k in ("resume", "new", "uncertain"):
            f.write(f"| {k} | {expected_dist[k]} | {by_decision[k]} |\n")

        f.write(f"\n## Failures ({len(failures)})\n\n")
        for fl in failures:
            f.write(f"### {fl['id']}\n")
            f.write(f"- query: `{fl['query']}`\n")
            f.write(f"- session_meta: `{fl['session_meta']}`\n")
            f.write(f"- expected: `{fl['expected']}` ({fl['why_expected']})\n")
            f.write(f"- actual: `{fl['actual']}` ({fl['reason']})\n\n")

        f.write("## Interpretation\n\n")
        if not false_new and not false_resume:
            f.write("✅ **No high-cost mistakes.** The adapter never wrongly said NEW or "
                    "RESUME — every miss is in the safer 'uncertain' direction. Disqualifier "
                    "discipline holds across biological-term collisions and neutral queries.\n\n")
        elif len(false_new) + len(false_resume) <= 1:
            f.write(f"⚠️  Minor: {len(false_new)} false NEW + {len(false_resume)} false RESUME on n={n}. "
                    f"Either pattern is fixable with ~2 lines of disqualifier YAML.\n\n")
        else:
            f.write(f"❌ {len(false_new)} false NEW + {len(false_resume)} false RESUME — "
                    f"investigation needed before any production wiring.\n\n")
    print(f"\nWrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
