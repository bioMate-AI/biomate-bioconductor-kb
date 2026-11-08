"""Tests for the group-A re-mining. Run on EC2: python -m pytest -q test_mine_groupA.py (after mine_groupA.py wrote its outputs).
Controls that must be able to FAIL: the original all-lab file must raise for S/B sources; group A must raise for itself."""
import json
import os
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
CYC = os.path.abspath(os.path.join(HERE, "..", ".."))
import importlib.util  # noqa: E402

# torch-free: load ihlm/symbolic.py directly (ihlm/__init__.py imports torch via model.py)
_spec = importlib.util.spec_from_file_location("ihlm_symbolic", os.path.join(CYC, "ihlm", "symbolic.py"))
_sym = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_sym)
assert_priors_clean = _sym.assert_priors_clean

OUT = os.path.join(HERE, "peptide_sar_rules_v1_groupA.json")
MAN = os.path.join(HERE, "groupA_manifest.json")
OLD = os.path.join(CYC, "kb_audit", "peptide_sar_rules_v1.json")
pytestmark = pytest.mark.skipif(not os.path.exists(OUT), reason="run mine_groupA.py first")


def _load(p):
    with open(p) as fh:
        return json.load(fh)


def test_new_rules_clean_for_stop_and_heldout_groups():
    rules, man = _load(OUT), _load(MAN)
    assert assert_priors_clean(rules, man["group_S"]) is True
    assert assert_priors_clean(rules, man["group_B"]) is True


def test_train_sources_are_group_A_only_and_manifest_matches():
    rules, man = _load(OUT), _load(MAN)
    assert set(rules["train_sources"]) == set(man["group_A_sources_used"])
    assert set(man["group_A_sources_used"]) <= set(man["group_A_all"])
    assert not (set(man["group_A_sources_used"]) & (set(man["group_S"]) | set(man["group_B"])))
    for name, r in rules["rules"].items():
        assert set(map(str, r.get("mined_from", []))) <= set(man["group_A_sources_used"]), name


def test_control_original_all_lab_file_fails_for_S_or_B():
    """Must be able to FAIL: the old file (21 sources) contains S/B sources that are eligible, so the guard has to raise."""
    man = _load(MAN)
    old = _load(OLD)
    held = [s for s in (man["group_S"] + man["group_B"]) if s in set(old["train_sources"])]
    if not held:
        pytest.skip("no S/B source among the old file's train sources (guard cannot be exercised)")
    with pytest.raises(AssertionError):
        assert_priors_clean(old, held)


def test_control_new_rules_fail_for_group_A_itself():
    rules, man = _load(OUT), _load(MAN)
    with pytest.raises(AssertionError):
        assert_priors_clean(rules, man["group_A_sources_used"][:1])


def test_groups_come_from_the_committed_file_not_a_recomputation():
    man = _load(MAN)
    f = man["groups_from"]["file"]
    assert os.path.basename(f).startswith("source_groups") and f.endswith(".json") and man["groups_from"]["sha256"], man["groups_from"]
    path = os.path.join(CYC, "allatom_paper", "track_e", os.path.basename(f))
    if os.path.exists(path):                    # the recorded hash must be the hash of the committed file
        import hashlib
        assert hashlib.sha256(open(path, "rb").read()).hexdigest() == man["groups_from"]["sha256"]


def test_manifest_hash_matches_output():
    import hashlib
    man = _load(MAN)
    h = hashlib.sha256(open(OUT, "rb").read()).hexdigest()
    assert h == man["output_sha256"]


def test_sensitivity_file_support_counts_and_drop_one_rules_clean():
    man = _load(MAN)
    sens = _load(os.path.join(HERE, "groupA_sensitivity.json"))
    assert sens["rule_support_n_sources"], "no per-rule support counts"
    assert max(sens["rule_support_n_sources"].values()) <= len(man["group_A_sources_used"])
    nt_path = os.path.join(HERE, "peptide_sar_rules_v1_groupA_noTownsend.json")
    if os.path.exists(nt_path):
        nt = _load(nt_path)
        assert "2020_Townsend" not in nt["train_sources"] and set(nt["train_sources"]) < set(man["group_A_sources_used"])
        assert assert_priors_clean(nt, man["group_S"]) and assert_priors_clean(nt, man["group_B"])


def test_validated_rule_count_is_reported_and_honest():
    man = _load(MAN)
    st = man["rule_status"]
    assert man["n_validated_rules"] == sum(1 for v in st.values() if v == "rule")
    rules = _load(OUT)["rules"]
    assert {k: v["status"] for k, v in rules.items()} == st          # manifest agrees with the rules file
    # support is the number of sources that actually entered each rule (n_sources), not len(mined_from)
    for k, n in man["rule_support_n_sources"].items():
        assert n == int(rules[k].get("n_sources", len(rules[k].get("mined_from", []))))


def test_per_source_descriptive_table_covers_every_group_A_source():
    man = _load(MAN)
    ps = _load(os.path.join(HERE, "groupA_sensitivity.json"))["per_source_descriptive"]
    assert set(ps) == set(man["group_A_sources_used"])
