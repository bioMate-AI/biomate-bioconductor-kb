"""B3 prompt_rules compiler smoke + round-trip."""
from __future__ import annotations
import json, yaml
from pathlib import Path
import pytest
from galaxy.ai.drug_discovery.org_rule_compiler import (
    compile_org_rules, write_rule_pack, load_org_rule_block, compile_and_write,
)


@pytest.fixture
def pairs_file(tmp_path):
    """Write a small customer_pairs.jsonl with two orgs + a global pair."""
    p = tmp_path / "customer_pairs.jsonl"
    p.write_text("\n".join([
        json.dumps({
            "prompt": "Summarise pbpk qualification.",
            "chosen": (
                "PBPK qualification met the EMA/CHMP/EWP/37498/2011 within-2-fold criterion. "
                "Per ICH M3(R2) the model is fit for purpose."
            ),
            "rejected": (
                "PBPK model performance is acceptable. "
                "Per ICH M3(R2) the model is fit for purpose. "
                "Vaguely good."
            ),
            "meta": {"org_id": "acme", "task": "pbpk", "section_type": "pbpk"},
        }),
        json.dumps({
            "prompt": "Summarise genotoxicity.",
            # acme adds the S2(R1) citation + the Ames mention (real edit pattern)
            "chosen":   "Genotoxicity assessed per ICH S2(R1). Ames assay negative.",
            "rejected": "Genotoxicity studies were performed. No findings overall.",
            "meta": {"org_id": "acme", "task": "tox_genotox", "section_type": "tox_genotox"},
        }),
        # A pair for a DIFFERENT org — should be filtered out
        json.dumps({
            "chosen":   "Cardiac per ICH S7B. No QT prolongation.",
            "rejected": "Cardiac assessment was performed. No issues.",
            "meta": {"org_id": "other", "task": "tox_cardiac"},
        }),
        # Untagged ("global") — should count for every org
        json.dumps({
            "chosen":   "Use 21 CFR 312 audit-trail framing.",
            "rejected": "Audit logs are stored.",
            "meta": {},
        }),
    ]))
    return p


def test_compile_filters_by_org(pairs_file):
    pack = compile_org_rules(pairs_file, org_id="acme")
    assert pack["org_id"] == "acme"
    # acme + global = 3 pairs (other is filtered)
    assert pack["pairs_observed"] == 3
    cits = pack["preferred_citations"]
    # acme's preferred citations + the global "21 CFR 312"
    assert any("EMA/CHMP/EWP/37498/2011" in c for c in cits)
    assert any("S2(R1)" in c for c in cits)
    assert any("21 CFR 312" in c for c in cits)
    assert not any("S7B" in c for c in cits)  # belongs to other org


def test_compile_for_other_org(pairs_file):
    pack = compile_org_rules(pairs_file, org_id="other")
    assert pack["pairs_observed"] == 2  # other + global
    assert any("S7B" in c for c in pack["preferred_citations"])


def test_compile_unknown_org_only_globals(pairs_file):
    pack = compile_org_rules(pairs_file, org_id="nobody")
    assert pack["pairs_observed"] == 1  # only the global pair
    assert any("21 CFR 312" in c for c in pack["preferred_citations"])


def test_compile_missing_file_returns_empty(tmp_path):
    pack = compile_org_rules(tmp_path / "does-not-exist.jsonl", org_id="acme")
    assert pack["pairs_observed"] == 0
    assert pack["preferred_citations"] == []


def test_preferred_phrases_captured(pairs_file):
    pack = compile_org_rules(pairs_file, org_id="acme")
    preferred = " ".join(pack["preferred_phrases"]).lower()
    # The within-2-fold sentence appears only in chosen
    assert "within-2-fold criterion" in preferred or "within-2-fold" in preferred


def test_banned_phrases_captured(pairs_file):
    pack = compile_org_rules(pairs_file, org_id="acme")
    banned = " ".join(pack["banned_phrases"]).lower()
    # The "vaguely good" sentence appears only in rejected
    assert "vaguely good" in banned or "no findings overall" in banned


def test_round_trip_yaml(pairs_file, tmp_path):
    pack = compile_org_rules(pairs_file, org_id="acme")
    out = tmp_path / "acme.yaml"
    write_rule_pack(out, pack)
    assert out.exists()
    reloaded = yaml.safe_load(out.read_text())
    assert reloaded["org_id"] == "acme"
    assert reloaded["pairs_observed"] == 3
    assert reloaded["preferred_citations"] == pack["preferred_citations"]


def test_load_block_filters_for_rag(pairs_file, tmp_path):
    pack = compile_org_rules(pairs_file, org_id="acme")
    out = tmp_path / "acme.yaml"
    write_rule_pack(out, pack)
    bullets = load_org_rule_block(out, section_type="pbpk")
    assert bullets, "loader should return at least one bullet"
    joined = " | ".join(bullets)
    assert "this org prefers it" in joined  # citation framing
    # And the cap: at most 4 cit + 3 pref + 3 ban = 10
    assert len(bullets) <= 10


def test_load_block_missing_file_empty():
    assert load_org_rule_block(Path("/tmp/nope.yaml"), section_type="pbpk") == []


def test_compile_and_write_oneshot(pairs_file, tmp_path):
    out = tmp_path / "acme.yaml"
    n = compile_and_write(pairs_file, out, org_id="acme")
    assert n == 3
    assert out.exists()
    data = yaml.safe_load(out.read_text())
    assert data["pairs_observed"] == 3


def test_meta_distributions(pairs_file):
    pack = compile_org_rules(pairs_file, org_id="acme")
    assert pack["tasks"].get("pbpk") == 1
    assert pack["tasks"].get("tox_genotox") == 1
    assert pack["sections"].get("pbpk") == 1
