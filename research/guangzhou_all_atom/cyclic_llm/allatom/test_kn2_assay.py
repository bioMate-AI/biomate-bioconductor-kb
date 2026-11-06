"""KN-2 engagement scorer tests on trimmed real control complexes + synthetic negatives. Run: python3.11 test_kn2_assay.py"""
import os, sys, copy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gemmi, kn2_assay as K
FX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")

def test_known_binders_engage_with_expected_distances():
    r = K.engagement(f"{FX}/CTRL-TRIVEHEXIN.cif", ligand_iptm=0.916); assert r["asp_found"] and r["engaged"] and abs(r["d_asp_midas_mn"] - 0.81) < 0.05, r
    r = K.engagement(f"{FX}/CTRL-AVEBEHEXIN.cif", ligand_iptm=0.95); assert r["engaged"] and abs(r["d_asp_midas_mn"] - 1.91) < 0.05, r

def test_midas_is_identified_by_beta6_serine_coordination_not_by_order():
    r = K.engagement(f"{FX}/CTRL-TRIVEHEXIN.cif", ligand_iptm=0.9); assert r["midas_mn_chain"] == "M3", r

def test_low_ligand_iptm_blocks_engagement_even_with_good_geometry():
    r = K.engagement(f"{FX}/CTRL-TRIVEHEXIN.cif", ligand_iptm=0.5); assert r["d_asp_midas_mn"] < 1 and not r["engaged"]

def test_displaced_peptide_does_not_engage(tmp=None):
    import tempfile
    st = gemmi.read_structure(f"{FX}/CTRL-TRIVEHEXIN.cif"); m = st[0]
    for c in m:
        if c.name == "P":
            for r in c:
                for a in r: a.pos = gemmi.Position(a.pos.x + 15, a.pos.y, a.pos.z)
    p = os.path.join(tempfile.mkdtemp(), "moved.cif"); st.make_mmcif_document().write_file(p)
    r = K.engagement(p, ligand_iptm=0.95); assert r["asp_found"] and not r["engaged"] and r["d_asp_midas_mn"] > 5, r

def test_peptide_without_rgd_has_no_engagement():
    import tempfile
    st = gemmi.read_structure(f"{FX}/CTRL-TRIVEHEXIN.cif")
    for c in st[0]:
        if c.name == "P":
            for r in c:
                if r.name == "ASP": r.name = "GLU"
    p = os.path.join(tempfile.mkdtemp(), "norgd.cif"); st.make_mmcif_document().write_file(p)
    r = K.engagement(p, ligand_iptm=0.95); assert not r["asp_found"] and not r["engaged"], r

if __name__ == "__main__":
    k = 0
    for n, f in sorted(globals().items()):
        if n.startswith("test_"): f(); k += 1; print("PASS", n)
    print(k, "tests passed")
