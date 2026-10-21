"""Unit tests for the Experience KB first slice — resolve() drives params + eval from one store."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import experience_kb as kb


def test_all_entries_validate():
    for t in ("avb6", "pdl1"):
        for e in kb.all_entries(t):
            e.validate()  # schema-valid, tier in ladder, eval modes hard|advisory
            assert e.provenance.get("verified") in (True, False, "unverifiable", "n/a")  # mandatory + surfaced


def test_provenance_honesty():
    """The verified flags must reflect what was actually checked — not silently authoritative."""
    prov = {p["entry"]: p for p in kb.resolve("avb6")["provenance"]}
    # VERIFIED-authoritative (real cited literature confirmed 2026-10-21)
    assert prov["avb6:metal"]["verified"] is True and prov["avb6:metal"]["tier"] == "T1"
    assert prov["avb6:pharmacophore"]["verified"] is True and prov["avb6:pharmacophore"]["tier"] == "T1"
    assert prov["cmc:universal"]["verified"] is True
    assert prov["avb6:sar-renal-charge"]["verified"] is True
    # NOT authoritative — flagged honestly
    assert prov["avb6:sar-b6-selectivity"]["verified"] is False          # causal SAR inferred, not cited
    assert prov["avb6:fto-genus"]["verified"] == "unverifiable"          # specific patent id unconfirmed
    # pdl1 pharmacophore refs not checked this session
    pprov = {p["entry"]: p for p in kb.resolve("pdl1")["provenance"]}
    assert pprov["pdl1:pharmacophore"]["verified"] == "unverifiable"


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


def test_loop_consumes_resolve():
    """The DesignCampaign loop's params + eval gate-set come from resolve() (single source)."""
    import loop_batch
    r = loop_batch.run_round(["cyclo(F-R-G-D-L-A-F-P-K)"], target="avb6", submit=False, round_id="t")
    # params come from the KB, not a divergent path
    assert r["kb_params"].get("metal_model") == "CaDA-MN"
    assert r["kb_params"].get("cofactors")                       # metal cofactors surfaced
    # the hard gate-set is exactly the KB's, tier+verified carried through
    hard = {c["criterion"] for c in r["kb_gate_set"] if c["mode"] == "hard"}
    assert "pharmacophore_gate[avb6]" in hard and "sar:rgd-selectivity-element" in hard
    assert all("tier" in c and "verified" in c for c in r["kb_gate_set"])


def test_rag_fallback_novel_target():
    """Novel target: opt-in RAG seam proposes params/gates but tiers them T4/unverified (never authoritative)."""
    # default resolve stays deterministic-only (unknown target -> no target params)
    base = kb.resolve("no_such_target_xyz")
    assert base["tool_params"] == {}
    # opt-in RAG fallback: schema-valid, provenance-honest
    rag = kb.resolve("no_such_target_xyz", rag=True)
    assert rag["rag_used"] is True
    for p in rag["provenance"]:
        if p["entry"].endswith(":rag"):
            assert p["tier"] == "T4" and p["verified"] is False     # LLM-proposed is never silently authoritative


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
