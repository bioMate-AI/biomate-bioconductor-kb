"""Tests for the group-A re-mining. Run on EC2: python -m pytest -q test_mine_groupA.py (after mine_groupA.py wrote its outputs).
Controls that must be able to FAIL: the original all-lab file must raise for S/B sources; group A must raise for itself."""
import json
import os
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
CYC = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, CYC)
from ihlm.symbolic import assert_priors_clean  # noqa: E402

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
    assert man["groups_from"]["file"].endswith("source_groups.json") and man["groups_from"]["sha256"], man["groups_from"]


def test_manifest_hash_matches_output():
    import hashlib
    man = _load(MAN)
    h = hashlib.sha256(open(OUT, "rb").read()).hexdigest()
    assert h == man["output_sha256"]
