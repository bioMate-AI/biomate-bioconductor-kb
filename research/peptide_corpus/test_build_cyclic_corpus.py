#!/usr/bin/env python3
"""test_build_cyclic_corpus.py — fast CPU unit tests for the D0 corpus pipeline (no GPU, no S3).

Run: python3 -m pytest test_build_cyclic_corpus.py -q   (or: python3 test_build_cyclic_corpus.py)

Covers each of the 4 fixes at the unit level plus a tiny end-to-end synthetic corpus, so a regression
in any stage is caught in <5s without touching the 19MB CSV or any download.
"""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import schema
import stage1_helm_canon as s1
import stage2_standardize_dedup as s2
import stage3_provenance as s3
import stage4_split as s4


def _synthetic():
    """A tiny mixed-source corpus: a few benzene-ring/aspirin-like small mols (parseable) with known
    duplicate + provenance mix, so we can assert dedup/provenance/split without real peptides."""
    recs = []
    # two exact duplicates from different tiers -> priority-merge keeps the experimental one, merges labels
    recs.append(schema.new_record("CycPeptMPDB", "CC(=O)Oc1ccccc1C(=O)O",
                                  conformer_provenance="none", source_tier="none",
                                  labels={"permeability": {"value": -6.0}}, source_id="a1", is_cyclic=False))
    recs.append(schema.new_record("PepBDB", "O=C(O)c1ccccc1OC(C)=O",  # same molecule, different string
                                  conformer_provenance="PDB_experimental", source_tier="PDB_experimental",
                                  labels={"ic50": {"value": 12.0}}, source_id="b1", is_cyclic=False))
    # distinct molecules
    recs.append(schema.new_record("CREMP", "c1ccccc1", conformer_provenance="xTB_CREMP",
                                  source_tier="xTB_CREMP", source_id="c1", is_cyclic=False))
    recs.append(schema.new_record("CREMP", "CCO", conformer_provenance="xTB_CREMP",
                                  source_tier="xTB_CREMP", source_id="c2", is_cyclic=False))
    recs[-1]["premium_eval"] = True  # force into frozen premium eval
    recs.append(schema.new_record("BindingDB_peptide", "CCN(CC)CC",
                                  conformer_provenance="none", source_tier="none", source_id="d1"))
    return recs


def test_fix1_helm_canon_and_gate():
    recs = [schema.new_record("CycPeptMPDB", "CCO", helm="PEPTIDE1{[Sar].[meL].V.[Hyp]}$$$$",
                              sequence=["Sar", "meL", "V", "Hyp"], source_id="h1")]
    st = s1.run(recs)
    assert recs[0]["sequence_canonical"] == ["Sar", "meL", "V", "Hyp"]
    assert recs[0]["helm_canonical"] and "Sar" in recs[0]["helm_canonical"]
    gate = s1.roundtrip_gate(recs, n=1)
    assert gate["pass_rate"] == 1.0, gate
    # alias normalization: 'hyp' -> 'Hyp', 'aib'->'Aib', 'nle'->'Nle'
    assert s1.canonicalize_token("hyp")[0] == "Hyp"
    assert s1.canonicalize_token("aib")[0] == "Aib"
    assert s1.canonicalize_token("nle")[0] == "Nle"


def test_fix2_standardize_and_priority_merge():
    recs = _synthetic()
    deduped, stats = s2.run(recs, do_tautomer=True)
    # the aspirin pair collapses to one record
    assert stats["duplicates_removed"] == 1, stats
    # the kept record is the PDB_experimental one (higher source_tier) with MERGED labels
    aspirin = [r for r in deduped if r.get("inchikey") and
               "CC(=O)Oc1ccccc1C(=O)O" in (r["smiles"] + r.get("std_smiles", ""))
               or "aspirin" in str(r).lower()]
    kept = [r for r in deduped if r["source_tier"] == "PDB_experimental"]
    assert kept, "priority-merge should keep the experimental tier record"
    assert "permeability" in kept[0]["labels"] and "ic50" in kept[0]["labels"], "labels must be merged"
    assert stats["labels_merged"] >= 1


def test_fix3_provenance_validation():
    recs = _synthetic()
    s2.run(recs)  # sets std keys; provenance already set at ingest
    st = s3.run(recs)
    assert set(st["by_provenance"]) == set(schema.CONFORMER_PROVENANCE)
    assert st["experimental_structures"] >= 1
    # illegal tag must raise
    bad = [schema.new_record("X", "CCO", conformer_provenance="none")]
    bad[0]["conformer_provenance"] = "made_up_tag"
    try:
        s3.run(bad)
        assert False, "stage3 must reject an illegal provenance tag"
    except ValueError:
        pass


def test_fix4_split_freezes_premium_and_reports_leakage():
    recs = _synthetic()
    recs, _ = s2.run(recs)
    s3.run(recs)
    report = s4.run(recs, test_frac=0.34, val_frac=0.0, seed=1)
    # the premium_eval record must be frozen into eval (never train)
    prem = [r for r in recs if r.get("premium_eval")]
    assert prem and all(r["split"] in ("test", "val") and r["eval_frozen"] for r in prem)
    assert "leakage_gate" in report and "median" in report["leakage_gate"]
    assert "intrinsic_corpus" in report
    # every record got a split and a cluster id
    assert all(r["split"] in ("train", "val", "test") for r in recs)
    assert all(r["cluster_id"] is not None for r in recs)


def test_schema_uid_stable():
    r = schema.new_record("CREMP", "CCO", source_id="x")
    assert schema.record_uid(r) == "CREMP:x"
    r2 = schema.new_record("CREMP", "CCO")  # no id -> hash of smiles
    assert schema.record_uid(r2).startswith("CREMP:")


def _run_all():
    fns = [v for k, v in globals().items() if k.startswith("test_") and callable(v)]
    for fn in fns:
        fn()
        print(f"  [ok] {fn.__name__}")
    print(f"all {len(fns)} tests passed")


if __name__ == "__main__":
    _run_all()
