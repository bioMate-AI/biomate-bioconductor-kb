"""parse_helm must be LENGTH-PRESERVING and map non-canonical residues to their canonical parent (same table as fto_score._BB_MAP); unknown tokens must be explicit, never dropped or mis-mapped.
Run: python3 test_parse_helm_ncaa.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from knowledge_liability_flags import parse_helm
from fto_score import _BB_MAP

def res(t): return parse_helm(f"cyclo(R-G-D-{t}-L)")[0]

def test_length_is_preserved_for_every_token():
    for t in ["K", "[2Nal]", "[Phe4F]", "[Phe4Cl]", "[Aib]", "[Abu]", "[dP]", "[NMeK]", "[NMeA]", "[Nle]", "[Sar]", "[Bip]", "[hPhe]", "[1Nal]", "[Nal]", "[Orn]", "[Cit]", "[ZZZ]"]:
        assert len(res(t)) == 5, (t, res(t))

def test_ncaa_map_matches_the_fto_table_and_is_not_proline_or_dropped():
    for k, v in _BB_MAP.items(): assert res(f"[{k}]")[3] == v, (k, res(f"[{k}]"))
    assert res("[Phe4F]")[3] == "F" and res("[Phe4Cl]")[3] == "F" and res("[2Nal]")[3] == "F"

def test_prefix_handling_is_unchanged():
    assert res("[dP]")[3] == "P" and res("[NMeK]")[3] == "K" and res("[NMeA]")[3] == "A"
    r, mods, _ = parse_helm("cyclo(R-G-D-[NMeK]-[dP])"); assert mods[3]["n_methyl"] and mods[4]["d_stereo"]

def test_unknown_token_is_explicit_not_silent():
    r, mods, scaf = parse_helm("cyclo(R-G-D-[Zzz9]-L)"); assert r[3] == "X" and scaf["unmapped"] == ["Zzz9"], (r, scaf)
    assert parse_helm("cyclo(R-G-D-L)")[2]["unmapped"] == []

if __name__ == "__main__":
    k = 0
    for n, f in sorted(globals().items()):
        if n.startswith("test_"): f(); k += 1; print("PASS", n)
    print(k, "tests passed")
