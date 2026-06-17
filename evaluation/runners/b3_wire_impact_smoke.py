#!/usr/bin/env python3
"""B3 wire impact smoke — does org_id actually move LLM output?

The multi-model eval calls LLM adapters directly with pre-rendered
prompts and never traverses _build_rag_context, so it can't measure
whether the B3 per-org RAG injection actually changes outputs. This
script does.

Protocol:
  1. Seed a fresh test org with two customer feedback pairs whose
     `chosen` text strongly emphasises a specific PBPK citation
     (EMA/CHMP/EWP/37498/2011, the within-2-fold guideline).
  2. Run the worker tick once → compiler writes the rule pack.
  3. Call _llm_narrative(section_type="pbpk", ...) twice with the same
     PBPK metrics: once with org_id=None (baseline), once with
     org_id=<test org> (B3 wire hot).
  4. Print whether the seeded citation appears in each output.

  Pass criterion: the org-tagged call mentions the citation; the
  baseline call may or may not. A measurable lift is the B3 wire's
  whole purpose.

Cost: 2 Claude Sonnet 4.6 calls × ~$0.02 = ~$0.04. Cleans up after.

Usage:
  ANTHROPIC_API_KEY=... \
    REGULATORY_LLM_FRONTIER_MODEL=claude-sonnet-4-5 \
    python3 -m evaluation.runners.b3_wire_impact_smoke
"""
from __future__ import annotations
import json
import os
import sys
import uuid
from pathlib import Path

# Make backend importable.
HERE = Path(__file__).resolve()
REPO_ROOT = HERE.parents[2]
sys.path.insert(0, str(REPO_ROOT / "backend" / "lib"))


CITATION = "EMA/CHMP/EWP/37498/2011"


def main() -> int:
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("ERROR: ANTHROPIC_API_KEY not set", file=sys.stderr)
        return 2
    if not os.environ.get("REGULATORY_LLM_FRONTIER_MODEL", "").startswith("claude-"):
        os.environ["REGULATORY_LLM_FRONTIER_MODEL"] = "claude-sonnet-4-5"

    from galaxy.ai.drug_discovery import regulatory_pair_recorder as rec
    from galaxy.ai.drug_discovery import regulatory_training_jobs as rj
    from galaxy.ai.drug_discovery import regulatory_training_worker as rw
    from galaxy.ai.drug_discovery.ind_assembly import (
        _llm_narrative,
        _build_rag_context,
    )

    org_id = f"smoke{uuid.uuid4().hex[:10]}"
    print(f"[seed] using ephemeral org_id={org_id}")

    # 1. Seed two feedback pairs that heavily emphasise the target citation.
    rec.record_pair(
        user_id="smoke", org_id=org_id,
        chosen=(
            f"The BioMate PBPK model was qualified against the "
            f"{CITATION} within-2-fold acceptance criterion across 107 "
            f"marketed drugs; both Cmax and AUC predictions met the "
            f"guideline threshold."
        ),
        rejected="The PBPK model works well.",
        section_type="pbpk",
    )
    rec.record_pair(
        user_id="smoke", org_id=org_id,
        chosen=(
            f"In accordance with {CITATION}, model qualification used "
            f"AFE, AAFE, and within-2-fold metrics for both Cmax and "
            f"AUC. The model is fit-for-purpose per the guideline."
        ),
        rejected="Model is good.",
        section_type="pbpk",
    )
    assert rj.count_edit_pairs(org_id) == 2, "feedback pair count mismatch"

    # 2. Compile via worker tick.
    rj.submit(user_id="smoke", org_id=org_id)
    done = rw.tick(max_jobs=1)
    if not done or done[0].status != "succeeded":
        print(f"ERROR: worker tick failed: {done}", file=sys.stderr)
        return 3
    print(f"[compile] worker tick succeeded; rule pack written")

    # 3. Verify the rule pack injects the citation into RAG context.
    ctx_with = _build_rag_context("pbpk", {"org_id": org_id}, "FDA")
    ctx_without = _build_rag_context("pbpk", {}, "FDA")
    has_in_ctx = CITATION in ctx_with
    has_in_baseline = CITATION in ctx_without
    print(f"[rag-ctx] org_id     → citation in RAG context: {has_in_ctx}")
    print(f"[rag-ctx] baseline   → citation in RAG context: {has_in_baseline}")
    if not has_in_ctx:
        print("ERROR: B3 wire did not inject citation into RAG context!", file=sys.stderr)
        return 4

    # 4. Run two LLM calls with identical PBPK metrics; check output for citation.
    pbpk_data = {
        "AFE_Cmax": "1.12",
        "AAFE_Cmax": "1.45",
        "R2_Cmax": "0.87",
        "within_2fold_Cmax": "0.91",
        "within_2fold_AUC": "0.89",
        "ema_criterion_met": True,
        "org_id": org_id,  # only used by the with-org call
    }

    print(f"\n[call] WITHOUT org_id (baseline)...")
    txt_baseline = _llm_narrative(
        section_type="pbpk",
        data={k: v for k, v in pbpk_data.items() if k != "org_id"},
        region="FDA",
        org_id=None,
    )
    print(f"[call] WITH org_id={org_id}...")
    txt_with = _llm_narrative(
        section_type="pbpk",
        data=pbpk_data,
        region="FDA",
        org_id=org_id,
    )

    # 5. Score.
    hit_baseline = CITATION in (txt_baseline or "")
    hit_with = CITATION in (txt_with or "")
    print("\n" + "=" * 70)
    print(f"BASELINE call: {len(txt_baseline or '')} chars, citation hit: {hit_baseline}")
    print(f"WITH-ORG call: {len(txt_with or '')} chars, citation hit: {hit_with}")
    print("=" * 70)

    # 6. Cleanup.
    repo = Path(__file__).resolve().parents[2]
    (repo / "data" / "regulatory_training" / "org_rules" / f"{org_id}.yaml").unlink(missing_ok=True)
    (repo / "data" / "regulatory_training" / "org_fewshot" / f"{org_id}.jsonl").unlink(missing_ok=True)
    # Drop our two seeded rows from the shared JSONL.
    pairs = rec.PAIRS_PATH
    if pairs.exists():
        kept = [
            ln for ln in pairs.read_text(encoding="utf-8").splitlines()
            if ln.strip() and (json.loads(ln).get("meta") or {}).get("org_id") != org_id
        ]
        pairs.write_text("\n".join(kept) + ("\n" if kept else ""), encoding="utf-8")
    print("[cleanup] removed ephemeral org artifacts + feedback rows")

    # Pass criterion: with-org call hits citation.
    if hit_with:
        print("\nPASS: B3 wire delivers seeded citation into LLM output.")
        return 0
    print("\nFAIL: with-org call did not surface seeded citation in output.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
