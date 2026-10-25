"""Gate-policy regression tests (committee finding: PD-L1/GRPR were auto-failed because rule_pass=None -> False). Run: python3 test_gate_policy.py"""
import sys; sys.path.insert(0, ".")
import score
HELM = "cyclo(F-R-G-D-L-G-[2Nal]-[dP]-[NMeK])"

def test_avb6_unchanged():
    r = score.score(HELM, target="avb6")
    assert r["rule_applicable"] and r["rule_pass"] is True and r["hard_gate_pass"] and "rule" in r["hard_gate_reasons"]

def test_avb6_non_rgd_still_fails():
    r = score.score("cyclo(A-A-A-A-A-A-A-A-A)", target="avb6")
    assert r["rule_applicable"] and not r["hard_gate_pass"] and r["hard_gate_reasons"]["rule"] is False

def test_pdl1_not_auto_failed_and_says_so():
    r = score.score(HELM, target="pdl1")
    assert r["rule_applicable"] is False and r["rule_pass"] is None
    assert r["hard_gate_pass"] is True and "rule" not in r["hard_gate_reasons"]

def test_pdl1_still_fails_on_liability():
    r = score.score("cyclo(A-N-G-A-A-F-A-A-A-A)", target="pdl1")
    assert not r["hard_gate_pass"] and r["hard_gate_reasons"]["developability"] is False

def test_reward_does_not_count_missing_rule_as_failure():
    import reward
    r = score.score(HELM, target="pdl1")
    assert reward.reward(r)["terms"]["gate"] == reward.DEFAULT_WEIGHTS["gate_pass"]

if __name__ == "__main__":
    n = 0
    for k, f in sorted(globals().items()):
        if k.startswith("test_"): f(); n += 1; print("PASS", k)
    print(f"{n} tests passed")
