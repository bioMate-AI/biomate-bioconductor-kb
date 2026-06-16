"""B3 integration: org_id wire → _build_rag_context → per-org RAG injection.

Proves the org_id wire fires end-to-end. Writes the rule YAML + few-shot
index JSONL at the exact on-disk path `_build_rag_context` reads from,
then asserts the constructed block carries both the org-rule and the
exemplar bullets.

Uses a UUID-tagged org_id + tearDown cleanup so multiple test runs do
not collide.
"""
from __future__ import annotations
import json, uuid, pytest
from pathlib import Path
from galaxy.ai.drug_discovery.ind_assembly import _build_rag_context
from galaxy.ai.drug_discovery import org_rule_compiler as orc
from galaxy.ai.drug_discovery import org_fewshot_index as ofi


# Path mirrors the literal lookup in ind_assembly._build_rag_context. The
# function lives at backend/lib/galaxy/ai/drug_discovery/ind_assembly.py
# and uses parents[5] → repo root. This test file is one level deeper
# (parents[6]) because of the tests/ subdir.
_REPO_ROOT = Path(__file__).resolve().parents[6]
RULES_DIR   = _REPO_ROOT / "data" / "regulatory_training" / "org_rules"
FEWSHOT_DIR = _REPO_ROOT / "data" / "regulatory_training" / "org_fewshot"


@pytest.fixture
def acme_artifacts(tmp_path):
    """Compile + drop a real per-org rule pack + few-shot index where
    `_build_rag_context` looks for them. Uses a UUID-tagged org_id so
    cleanup is bounded."""
    org_id = f"test{uuid.uuid4().hex[:12]}"

    pairs = tmp_path / "pairs.jsonl"
    pairs.write_text("\n".join([
        json.dumps({
            "chosen":   "PBPK qualification met the EMA/CHMP/EWP/37498/2011 within-2-fold criterion.",
            "rejected": "PBPK acceptable.",
            "meta": {"org_id": org_id, "section_type": "pbpk"},
        }),
        json.dumps({
            "chosen":   "Per ICH M3(R2) the model is fit for purpose at all doses tested.",
            "rejected": "Model works.",
            "meta": {"org_id": org_id, "section_type": "pbpk"},
        }),
    ]))

    orc.write_rule_pack(
        RULES_DIR / f"{org_id}.yaml",
        orc.compile_org_rules(pairs, org_id),
    )
    ofi.build_and_write(pairs, FEWSHOT_DIR / f"{org_id}.jsonl", org_id)

    yield org_id

    # Cleanup
    (RULES_DIR / f"{org_id}.yaml").unlink(missing_ok=True)
    (FEWSHOT_DIR / f"{org_id}.jsonl").unlink(missing_ok=True)


def test_no_org_id_omits_org_blocks():
    """Baseline: without org_id, _build_rag_context does not emit per-org content."""
    block = _build_rag_context("pbpk", {}, "FDA")
    assert "Org-specific rules" not in block
    assert "Few-shot exemplars" not in block


def test_org_id_injects_rule_pack_and_exemplars(acme_artifacts):
    """The real wire: when data['org_id'] is set and the per-org artifacts
    exist on disk, both blocks land in the RAG context."""
    org_id = acme_artifacts
    block = _build_rag_context(
        "pbpk",
        {"org_id": org_id, "user_prompt": "Summarise PBPK qualification."},
        "FDA",
    )

    # Org-rule pack block
    assert "Org-specific rules" in block, f"missing rule block: {block[:600]}"
    assert f"{org_id} edit history" in block

    # Few-shot exemplar block — must include an actual exemplar fragment
    assert "Few-shot exemplars" in block, f"missing few-shot block: {block[:600]}"
    assert ("EMA/CHMP/EWP/37498/2011" in block) or ("M3(R2)" in block)


def test_unknown_org_id_no_op():
    """Unknown org doesn't raise, doesn't pollute the block."""
    block = _build_rag_context("pbpk", {"org_id": "definitelynobody"}, "FDA")
    assert "Org-specific rules" not in block
    assert "Few-shot exemplars" not in block
