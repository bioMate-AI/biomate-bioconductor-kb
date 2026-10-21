"""Unit tests for the Experience KB first slice — resolve() drives params + eval from one store."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import experience_kb as kb


def test_all_entries_validate():
    for t in ("avb6", "pdl1"):
        for e in kb.all_entries(t):
            e.validate()  # schema-valid, tier in ladder, eval modes hard|advisory


def test_avb6_tool_params():
    r = kb.resolve("avb6")
    assert r["known"] and r["target_class"] == "integrin-MIDAS"
    tp = r["tool_params"]
    assert tp["metal_model"] == "CaDA-MN"
    assert tp["metal_ccd"] == "MN" and tp["metal_n"] == 3
    assert tp["metal_ff_file"].endswith("cada_mn.itp")
    assert tp["pose_method"] == "cofold+mmgbsa"
    assert "avb8" in tp["counter_targets"]              # selectivity counter-screen
    assert "RGD" in tp["generation_constraint"]["must_contain"]


def test_avb6_eval_gateset():
    crits = {c["criterion"]: c for c in kb.resolve("avb6")["eval_criteria"]}
    # the αvβ6 gate-set the design specified
    assert crits["metal_retained_in_run"]["mode"] == "hard"
    assert crits["sar:rgd-selectivity-element"]["mode"] == "hard"
    assert crits["sar:conformational-lock"]["mode"] == "hard"
    assert "pharmacophore_gate[avb6]" in crits
    assert crits["sar:renal-cationic-charge"]["mode"] == "advisory"
    assert crits["cmc_liabilities"]["mode"] == "advisory"
    assert "fto_genus_clearance" in crits                # FTO genus fired
    # every criterion carries a checker + a provenance tier
    for c in crits.values():
        assert c.get("checker") and c.get("tier") in kb.TIERS


def test_pdl1_no_metal_structure_gated():
    r = kb.resolve("pdl1")
    assert r["target_class"] == "ppi-groove"
    assert "metal_model" not in r["tool_params"]        # no cofactor -> no metal param, no void rule
    crits = {c["criterion"]: c for c in r["eval_criteria"]}
    assert "metal_retained_in_run" not in crits
    assert crits["pharmacophore_gate[pdl1]"]["mode"] == "advisory"   # structure-gated, not sequence-decisive


def test_unknown_target_safe():
    r = kb.resolve("no_such_target_xyz")
    # unknown target: no target-specific params/gates, but universal CMC liabilities still apply
    assert r["known"] is False
    assert r["tool_params"] == {}
    crits = {c["criterion"] for c in r["eval_criteria"]}
    assert crits <= {"cmc_liabilities"}                 # only the universal advisory, nothing target-specific/hard
    assert all(c["mode"] == "advisory" for c in r["eval_criteria"])


if __name__ == "__main__":
    import traceback
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    ok = 0
    for fn in fns:
        try:
            fn(); ok += 1; print(f"PASS {fn.__name__}")
        except Exception:
            print(f"FAIL {fn.__name__}"); traceback.print_exc()
    print(f"\n{ok}/{len(fns)} passed")
    sys.exit(0 if ok == len(fns) else 1)
