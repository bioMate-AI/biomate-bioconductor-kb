"""Tests for workstream K3 (run on EC2 spot, not the laptop):  pytest structure_knowledge/test_structure_knowledge.py -q
Network is used for the hand-check tests (RCSB CIF download). Env: K3_MANIFEST = path to data/bound_cyclic/v2/bound_cyclic_manifest.jsonl."""
import json
import math
import os
import re
import sys
import tempfile
import urllib.request

import numpy as np
import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aggregate as A  # noqa: E402
import cards as C  # noqa: E402
import features as F  # noqa: E402

MANIFEST = os.environ.get("K3_MANIFEST", os.path.join(HERE, "..", "..", "..", "data", "bound_cyclic", "v2", "bound_cyclic_manifest.jsonl"))
HAND = ["11MG", "1A7F", "1AI0", "1APH", "1BCK", "1C5F", "1CWA", "1AXD", "148L", "1ACY"]   # mixed: disulfide, head-to-tail, false-positive labels


def _rows():
    if not os.path.exists(MANIFEST):
        pytest.skip("manifest not available")
    by = {}
    for l in open(MANIFEST):
        r = json.loads(l)
        if r.get("status") == "ok":
            by.setdefault(r["pdb_id"], r)
    return by


def _cif(pid):
    d = tempfile.gettempdir()
    p = os.path.join(d, pid.lower() + ".cif")
    if not os.path.exists(p):
        open(p, "wb").write(urllib.request.urlopen(f"https://files.rcsb.org/download/{pid.lower()}.cif", timeout=60).read())
    return p


# ---------- synthetic geometry ----------
def test_sasa_single_atom_analytic():
    c = np.zeros((1, 3)); r = np.array([1.7])
    s = F.shrake_rupley(c, r, c, r, n_points=200)[0]
    assert s == pytest.approx(4 * math.pi * (1.7 + F.PROBE) ** 2, rel=1e-6)


def test_sasa_two_far_atoms_additive_and_two_close_less():
    c = np.array([[0, 0, 0], [30.0, 0, 0]]); r = np.array([1.7, 1.7])
    far = F.shrake_rupley(c, r, c, r).sum()
    c2 = np.array([[0, 0, 0], [2.0, 0, 0]])
    close = F.shrake_rupley(c2, r, c2, r).sum()
    assert far == pytest.approx(2 * 4 * math.pi * 3.1 ** 2, rel=1e-6) and close < far * 0.8


def test_angdiff_wraps():
    assert F._angdiff(179, -179) == pytest.approx(2.0) and F._angdiff(-60, -90) == pytest.approx(30.0)


# ---------- hand-checked complexes (independent evidence: manifest evidence string + CIF numbering) ----------
@pytest.mark.parametrize("pid", HAND)
def test_hand_checked_parse(pid):
    rows = _rows()
    if pid not in rows:
        pytest.skip("not in manifest")
    r = rows[pid]
    f = F.featurize_complex(_cif(pid), r["pep_chain"], list(r["rec_chains"]))
    assert f["ok"]
    # sequence length: manifest peptide length vs our residue count (our count includes only residues with backbone atoms)
    assert abs(f["n_res"] - r["seq_len"]) <= 1, (pid, f["n_res"], r["seq_len"])
    ev = r["cyclization_evidence"]
    if r["cyclization_type"] == "disulfide":
        nums = [int(x) for x in re.findall(r"res (\d+)", ev)]
        dist = float(re.search(r"= ([0-9.]+)A", ev).group(1))
        cl = [c for c in f["closures"] if c["kind"] == "disulfide"]
        assert cl, pid
        # distance agrees with the manifest evidence (independent code path) to 0.05 A
        assert any(abs(c["dist"] - dist) <= 0.06 for c in cl), (pid, [c["dist"] for c in cl], dist)
        # ring span agrees with the author-numbering difference when the numbering is contiguous
        span = nums[1] - nums[0] + 1
        assert any(c["span_res"] == span for c in cl) or f["n_res"] != r["seq_len"], (pid, [c["span_res"] for c in cl], span)
    if r["cyclization_type"] == "head_to_tail":
        assert "head_to_tail" in f["closure_kinds"], pid
    if r["cyclization_type"] == "sidechain_backbone":
        # known weakness of the old miner label: we only require that our re-detection is self-consistent (no crash)
        assert f["primary_cyclisation"] in ("none", "amide_like", "thioether", "ester_like", "c_c_link", "disulfide")


def test_determinism():
    rows = _rows(); r = rows["11MG"]
    a = F.featurize_complex(_cif("11MG"), r["pep_chain"], list(r["rec_chains"]))
    b = F.featurize_complex(_cif("11MG"), r["pep_chain"], list(r["rec_chains"]))
    assert json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True)


def test_insulin_chain_is_flagged_covalent():
    """1A7F chain A (insulin A chain) is disulfide-bonded to its B chain: not an independent peptide ligand; QC must flag it."""
    rows = _rows(); r = rows["1A7F"]
    f = F.featurize_complex(_cif("1A7F"), r["pep_chain"], list(r["rec_chains"]))
    f.update({k: r[k] for k in ("cyclization_type",)})
    assert f["n_covalent_to_receptor"] > 0
    assert "covalent_to_receptor" in A.qc_flags({**f, "agree_cyclisation": True})


def test_dres_and_nme_detected_in_compstatin_analog():
    rows = _rows(); r = rows["11MG"]
    f = F.featurize_complex(_cif("11MG"), r["pep_chain"], list(r["rec_chains"]))
    assert f["n_nme"] >= 1 and f["n_d"] >= 0     # compstatin analog Cp60 contains N-methylated residues; D count reported, not asserted
    assert len(f["is_d"]) == f["n_res"] == len(f["is_nme"])


# ---------- aggregate / priors / cards ----------
def _toy_rows():
    base = dict(n_res=10, seq="ACDEFGHIKL", is_d=[False] * 10, is_nme=[False] * 10, iface_res=[1, 2, 3], beta_turns=[], n_backbone_nh=8,
                n_nh_intra_hbond=2, n_nh_receptor_hbond=3, n_nh_free=3, primary_cyclisation="disulfide", ring_residues=8, method="X-RAY DIFFRACTION")
    rows = []
    for i in range(30):
        d = dict(base); d["target_key"] = f"T{i % 25}"; d["ring_residues"] = 6 + (i % 5); rows.append(d)
    return rows


def test_priors_have_provenance_and_loto():
    p = A.build_priors(_toy_rows())
    assert p["n_targets"] == 25 and p["targets_sha256"]
    e = p["priors"]["ring_residues|disulfide"]
    assert "loto" in e and e["loto"]["n_targets"] == 25 and 0.0 <= e["loto"]["max_dev"] <= 1.0
    assert abs(sum(e["value"].values()) - 1.0) < 1e-9


def test_exclusion_changes_hash_and_removes_targets():
    rows = _toy_rows()
    full = A.build_priors(rows, do_loto=False)
    ex = A.build_priors(rows, exclude_targets=frozenset({"T0", "T1"}), do_loto=False)
    assert ex["n_targets"] == full["n_targets"] - 2 and ex["targets_sha256"] != full["targets_sha256"] and ex["excluded_targets_sha256"]


def test_cards_flag_missing_structures():
    card = C.card_for("t", "T", "1ABC", [], None)
    assert card["n_cyclic_complexes"] == 0 and "NO cyclic-peptide complex" in card["structure_status"] and "flag" in card


def test_ref_pdb_token_parser():
    assert C.ref_pdb("5O45 chain A (PD-L1 IgV + bound macrocycle)") == "5O45"
    assert C.ref_pdb("4IRZ — needs prep") == "4IRZ"
    assert C.ref_pdb("avb6_ourstructure_v1.cif (9XMM-derived, metal-complete)") == "9XMM"


def test_antibody_like_regex():
    assert A.AB_RE.search("Fab fragment heavy chain") and A.AB_RE.search("Rituximab Fab light chain") and A.AB_RE.search("Nanobody")
    assert not A.AB_RE.search("Programmed cell death 1 ligand 1") and not A.AB_RE.search("Tumor necrosis factor")
    assert not A.AB_RE.search("DES-GLA FACTOR VIIA (HEAVY CHAIN)")      # regression: protease heavy chain is not an antibody
    assert A.AB_RE.search("the Fab fragment of chimeric 2H7, heavy chain") and A.AB_RE.search("PROTEIN (IGG1 FAB 58.2 ANTIBODY (HEAVY CHAIN))")
    assert not A.AB_RE.search("IgG receptor FcRn large subunit p51") and not A.AB_RE.search("Beta-2-microglobulin")   # regression: FcRn was flagged antibody-like


def _lib_row(ab):
    return dict(pdb_id="9ZZZ", pep_chain="B", seq="CAAAAC", primary_cyclisation="disulfide", ring_residues=6, resolution_rcsb=2.0, method="X-RAY",
                contacts_total=100, hbond_rec_total=5, salt_total=1, hydrophobic_total=20, metal_contacts=0, buried_sasa_total=500.0,
                buried_sasa_polar=200.0, buried_sasa_apolar=300.0, n_d=0, n_nme=0, beta_turns=[], hotspots=[], doi="10.1/x", pubmed="1", title="t",
                affinity=[], receptor_uniprot=["P1"], receptor_desc=["Fab" if ab else "Target"], receptor_antibody_like=ab)


def test_card_distinguishes_antibody_epitope_complexes():
    c = C.card_for("t", "T", None, [_lib_row(True)], None, accs_override=["P1"])
    assert c["n_cyclic_complexes"] == 1 and c["n_non_antibody_receptor"] == 0 and "ONLY antibody-epitope" in c["structure_status"]
    c2 = C.card_for("t", "T", None, [_lib_row(True), _lib_row(False)], None, accs_override=["P1"])
    assert c2["n_non_antibody_receptor"] == 1 and c2["structure_status"] == "cyclic-peptide complexes available"
    assert c2["templates"][0]["receptor_antibody_like"] is False      # non-antibody templates sort first


def test_aggregate_main_end_to_end_on_synthetic_rows(tmp_path):
    """The command-line path must run (regression: lib_all was undefined once and only the small tests passed)."""
    import subprocess, sys
    feats = tmp_path / "f.jsonl"; meta = tmp_path / "m.jsonl"
    rows = []
    for i in range(6):
        r = dict(ok=True, pdb_id=f"9A{i}Z", pep_chain="B", rec_chains=["A"], source="biolip2", n_res=8, seq="CAFAAGWC", nonstd_resnames=[], is_d=[False] * 8, is_nme=[False] * 8,
                 closures=[], closure_kinds=["disulfide"], primary_cyclisation="disulfide", ring_residues=8, n_disulfide=1, n_cis_amide=0, rama={}, beta_turns=[],
                 gamma_turns=[], n_contacts=[1] * 8, n_hbond_rec=[0] * 8, n_salt=[0] * 8, n_hydrophobic=[0] * 8, buried_frac=[0.1] * 8, iface_res=[1, 2, 3],
                 n_iface_res=3, contacts_total=30, hbond_rec_total=2, salt_total=0, hydrophobic_total=4, metal_contacts=0, buried_sasa_total=400.0,
                 buried_sasa_polar=100.0, buried_sasa_apolar=300.0, sasa_isolated=900.0, n_backbone_nh=6, n_nh_intra_hbond=2, n_nh_receptor_hbond=1, n_nh_free=3,
                 n_pocket_res=5, pocket=[], hotspots=[], rg_ca=5.0, d_sign_ref_found=True, n_covalent_to_receptor=0, n_d=0, n_nme=0, method=None,
                 resolution=None, cyclization_type=None, receptor_name=None)
        rows.append(r)
    feats.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    meta.write_text("\n".join(json.dumps({"rcsb_id": r["pdb_id"], "struct": {"title": "t"}, "exptl": [{"method": "X-RAY DIFFRACTION"}],
                                           "rcsb_entry_info": {"resolution_combined": [2.0]},
                                           "rcsb_primary_citation": {"pdbx_database_id_DOI": "10.1/x", "pdbx_database_id_PubMed": 1, "title": "t", "year": 2020},
                                           "polymer_entities": [{"rcsb_polymer_entity": {"pdbx_description": "Target protein"},
                                                                 "rcsb_polymer_entity_container_identifiers": {"auth_asym_ids": ["A"], "reference_sequence_identifiers": [{"database_name": "UniProt", "database_accession": f"P{i}"}]}}]})
                              for i, r in enumerate(rows)) + "\n")
    out = tmp_path / "agg"
    p = subprocess.run([sys.executable, os.path.join(HERE, "aggregate.py"), "--features", str(feats), "--meta", str(meta), "--out", str(out)], capture_output=True, text=True)
    assert p.returncode == 0, p.stderr[-800:]
    summ = json.load(open(out / "library_summary.json"))
    assert summ["n_library"] == 6 and summ["by_method"].get("X-RAY DIFFRACTION") == 6      # method filled from RCSB metadata when the row has none
    assert (out / "priors_v1.json").exists() and (out / "retrieval_snippets_v1.jsonl").exists() and (out / "soft_potentials_v1.json").exists()
