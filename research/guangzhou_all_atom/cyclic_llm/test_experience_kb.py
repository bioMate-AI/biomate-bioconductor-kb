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
    """Every SERVED entry is evidence-supported (verified True); unverified knowledge is quarantined, never served."""
    r = kb.resolve("avb6")
    prov = {p["entry"]: p for p in r["provenance"]}
    cand = {c["entry"]: c for c in r["candidates"]}
    # SERVED knowledge is 100% verified (the hard evidence invariant)
    for p in r["provenance"]:
        assert p["verified"] in (True, "n/a"), f"{p['entry']} served but verified={p['verified']}"
    assert prov["avb6:metal"]["verified"] is True and prov["avb6:metal"]["tier"] == "T1"
    assert prov["avb6:pharmacophore"]["verified"] is True and prov["avb6:pharmacophore"]["tier"] == "T1"
    assert prov["cmc:universal"]["verified"] is True
    assert prov["avb6:sar-renal-charge"]["verified"] is True
    # b6-selectivity UPGRADED to verified via Dong NSMB 2014 (4UM8/4UM9) — now served + authoritative
    assert prov["avb6:sar-b6-selectivity"]["verified"] is True
    assert "Dong" in prov["avb6:sar-b6-selectivity"]["source"] and "2014" in prov["avb6:sar-b6-selectivity"]["source"]
    # FTO patent id unverifiable -> QUARANTINED as a candidate, NOT in the served provenance
    assert "avb6:fto-genus" not in prov
    assert cand["avb6:fto-genus"]["verified"] == "unverifiable" and cand["avb6:fto-genus"]["status"] == "candidate"
    # pdl1 served pharmacophore is the GENERAL ppi-groove class principle (Clackson & Wells / Walensky), verified
    pprov = {p["entry"]: p for p in kb.resolve("pdl1")["provenance"]}
    assert pprov["pdl1:pharmacophore"]["verified"] is True


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
    # ingested general liabilities (RDKit structural alerts) now part of the gate-set
    assert crits["structural_alert_liabilities"]["checker"] == "medchem_kb.screen_liabilities"
    # FTO genus is QUARANTINED (unverifiable patent id) -> NOT a served gate
    assert "fto_genus_clearance" not in crits
    assert any(c["entry"] == "avb6:fto-genus" for c in kb.resolve("avb6")["candidates"])
    # every SERVED criterion carries a checker, a tier, and is verified
    for c in crits.values():
        assert c.get("checker") and c.get("tier") in kb.TIERS and c.get("verified") is True


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
    # only the modality-agnostic GENERAL advisories fire (universal CMC + ingested structural alerts);
    # nothing target-specific, no hard gate, no physchem/modality (gated on a known spec)
    assert crits <= {"cmc_liabilities", "structural_alert_liabilities"}
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


def test_evidence_invariant_enforced():
    """A knowledge entry with no real source FAILS validate(); config is exempt; unverified -> quarantined."""
    # knowledge kind + empty ref -> hard fail (not admitted)
    bad = kb.KBEntry(id="x:bad", kind="sar", statement="unsourced claim",
                     provenance={"evidence_tier": "T3", "verified": True, "ref": ""})
    try:
        bad.validate(); raise AssertionError("expected evidence-invariant failure on empty ref")
    except AssertionError as e:
        assert "evidence invariant" in str(e) or "provenance.ref" in str(e)
    # config kind is exempt from the evidence requirement (it is not a knowledge claim)
    cfg = kb.KBEntry(id="x:cfg", kind="config", statement="engine default",
                     provenance={"evidence_tier": "n/a", "verified": "n/a", "ref": "program-config"}).validate()
    assert cfg.admitted and cfg.status == "config"
    # cited but unverified knowledge validates but is QUARANTINED (status candidate, not admitted)
    cand = kb.KBEntry(id="x:cand", kind="pharmacophore", statement="cited but unconfirmed",
                      provenance={"evidence_tier": "T2", "verified": "unverifiable", "ref": "Some Review 2020"}).validate()
    assert cand.status == "candidate" and not cand.admitted
    # verified knowledge is admitted
    good = kb.KBEntry(id="x:good", kind="metal", statement="verified",
                      provenance={"evidence_tier": "T1", "verified": True, "ref": "Harding 2006"}).validate()
    assert good.status == "active" and good.admitted


def test_liability_ingested_from_rdkit():
    """DOMAIN 1 is INGESTED from RDKit FilterCatalog (not hand-written); the live screener carries provenance."""
    import medchem_kb
    reg = medchem_kb.ingest_liability_catalogs()
    if not reg:                                              # RDKit missing -> domain honestly reports un-ingested
        return
    assert sum(e["n_alerts"] for e in reg) >= 1000           # ~1,585 published alerts ingested for free
    assert any("Baell" in e["source"] for e in reg)          # PAINS carries its canonical paper
    # live screen of a known PAINS/BRENK substructure (aryl azo) returns matches WITH per-alert provenance
    hits = medchem_kb.screen_liabilities("O=C(O)c1ccccc1N=Nc1ccccc1")
    assert hits and all(h.get("source") and h.get("rule_set") for h in hits)


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
