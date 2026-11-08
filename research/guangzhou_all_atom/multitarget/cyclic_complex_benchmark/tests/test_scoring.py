import json, os, sys, math
import numpy as np
import pytest
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "scripts"))
pytest.importorskip("DockQ")
import scoring as S

FX = os.path.join(HERE, "fixtures", "9CDT_2")
NATIVE = os.path.join(FX, "native.pdb")
META = json.load(open(os.path.join(FX, "meta.json")))
CH = META["receptor_chains"] + ["Z"]


def _transform(src, dst, fn_by_chain):
    out = []
    for l in open(src):
        if l.startswith(("ATOM", "HETATM")):
            ch = l[21]
            xyz = np.array([float(l[30:38]), float(l[38:46]), float(l[46:54])])
            xyz = fn_by_chain(ch, xyz)
            l = l[:30] + "%8.3f%8.3f%8.3f" % tuple(xyz) + l[54:]
        out.append(l)
    open(dst, "w").write("".join(out))
    return dst


def test_gt_vs_itself_is_one(tmp_path):
    m = S.dockq_metrics(NATIVE, NATIVE, CH)
    assert m["primary"]["DockQ"] > 0.999 and m["primary"]["fnat"] == 1.0 and m["primary"]["iRMSD"] < 1e-3


def test_rigid_motion_of_whole_complex_invariant(tmp_path):
    th = 0.7
    R = np.array([[math.cos(th), -math.sin(th), 0], [math.sin(th), math.cos(th), 0], [0, 0, 1]])
    mv = _transform(NATIVE, str(tmp_path / "rot.pdb"), lambda c, x: R @ x + np.array([10., -5., 3.]))
    assert S.dockq_metrics(mv, NATIVE, CH)["primary"]["DockQ"] > 0.99


def test_shifted_peptide_scores_low(tmp_path):
    mv = _transform(NATIVE, str(tmp_path / "shift.pdb"), lambda c, x: x + np.array([15., 0, 0]) if c == "Z" else x)
    p = S.dockq_metrics(mv, NATIVE, CH)["primary"]
    assert p["DockQ"] < 0.23 and p["fnat"] == 0.0 and p["LRMSD"] > 10


def test_small_shift_still_acceptable(tmp_path):
    mv = _transform(NATIVE, str(tmp_path / "small.pdb"), lambda c, x: x + np.array([1.0, 0, 0]) if c == "Z" else x)
    assert S.dockq_metrics(mv, NATIVE, CH)["primary"]["DockQ"] > 0.5


def test_ring_geometry_native_is_closed_and_broken_copy_is_not(tmp_path):
    atoms = S.load_atoms(NATIVE)["Z"]
    rg = S.ring_geometry(atoms, META["closures"], len(META["peptide_ccds"]))
    assert rg["valid"] and max(rg["bond_dev"]) < 0.3 and rg["omega_dev"][0] < 40
    # move residue 1 away from the C-terminus: closure bond breaks
    broken = [(a[0], a[1], a[2], a[3], a[4] + (np.array([6., 0, 0]) if a[0] == 1 else 0), a[5]) for a in atoms]
    rg2 = S.ring_geometry(broken, META["closures"], len(META["peptide_ccds"]))
    assert not rg2["valid"] and max(rg2["bond_dev"]) > 1.0 and S.ring_strain(rg2) > S.ring_strain(rg)


def test_consensus_identical_and_outlier():
    rng = np.random.default_rng(0)
    rca = rng.normal(size=(30, 3)) * 10
    pep = rng.normal(size=(8, 3)) * 3
    same = [(rca, pep.copy()) for _ in range(5)]
    c, M, big = S.consensus_features(same)
    assert all(x["cons_mean_rmsd"] < 1e-6 and x["cons_nbr"] == 4 for x in c) and big == 5
    far = same[:4] + [(rca, pep + 30.0)]
    c, M, big = S.consensus_features(far)
    assert c[4]["cons_nbr"] == 0 and c[0]["cons_nbr"] == 3 and c[4]["cons_mean_rmsd"] > c[0]["cons_mean_rmsd"]


def test_consensus_is_receptor_superposition_invariant():
    rng = np.random.default_rng(1)
    rca = rng.normal(size=(30, 3)) * 10
    pep = rng.normal(size=(8, 3)) * 3
    th = 1.1
    R = np.array([[1, 0, 0], [0, math.cos(th), -math.sin(th)], [0, math.sin(th), math.cos(th)]])
    moved = (rca @ R.T + 7, pep @ R.T + 7)
    c, M, big = S.consensus_features([(rca, pep), moved])
    assert M[0, 1] < 1e-6


def test_sample_features_on_native(tmp_path):
    conf = tmp_path / "c.json"
    conf.write_text(json.dumps({"confidence_score": 0.9, "ptm": 0.8, "iptm": 0.7, "protein_iptm": 0.7, "ligand_iptm": 0.0, "complex_plddt": 0.8,
                                "complex_iplddt": 0.7, "complex_pde": 1.0, "complex_ipde": 2.0, "pair_chains_iptm": {"0": {"1": 0.6}, "1": {"0": 0.5}}}))
    f = S.sample_features(NATIVE, str(conf), META, {"pae_if_mean": 3.0, "pae_pep_to_rec": 3.1})
    assert f["clash_count"] == 0 and f["contact_density"] > 3 and f["ring_valid"] and f["iptm_pep_rec"] == 0.6 and f["pae_if"] == 3.0


def test_prep_closure_parse():
    import prep_inputs as P
    c = P.parse_closures("1:DAL.N-11:ALA.C;3:CYS.SG-13:CYS.SG")
    assert c[0]["pos1"] == 1 and c[1]["atom2"] == "SG"
    assert P.classify_closure(c[0], 11) == "h2t" and P.classify_closure(c[1], 11) == "other"
