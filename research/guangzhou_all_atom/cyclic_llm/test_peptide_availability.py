"""Regression tests for peptide_availability (defects found by the 2026-10-25 committee review). Run: python3 test_peptide_availability.py"""
import math, sys; sys.path.insert(0, ".")
from peptide_availability import predict_availability as pa, _resolve

def test_met_is_not_me_plus_t():
    assert _resolve("Met") == "M"

def test_2nal_not_silently_dropped():
    # a di-2Nal macrocycle must look greasier (lower score) than the same ring with Ala in those positions
    grease = pa("cyclo(F-R-G-D-L-A-[2Nal]-[dP]-[2Nal])"); ala = pa("cyclo(F-R-G-D-L-A-A-[dP]-A)")
    assert not grease.abstain and grease.mean_hydrophobicity > ala.mean_hydrophobicity

def test_unparsable_abstains_not_safe():
    r = pa("cyclo([Xyz1]-[Xyz2]-[Xyz3]-[Xyz4])")
    assert r.abstain and r.low_availability is None and math.isnan(r.score)

def test_nmethyl_is_counted_not_erased():
    assert pa("cyclo(A-R-G-D-L-A-A-[dP]-[NMeK])").nmethyl_fraction > 0

def test_anionic_scores_higher_than_cationic_same_composition_shape():
    assert pa("AAEAAAAAA").score > pa("AAKAAAAAA").score   # documented direction: net-negative > net-positive

def test_d_enantiomer_same_letter():
    assert abs(pa("cyclo(A-A-[dL]-A)").score - pa("cyclo(A-A-L-A)").score) < 1e-9

if __name__ == "__main__":
    n = 0
    for k, f in sorted(globals().items()):
        if k.startswith("test_"): f(); n += 1; print("PASS", k)
    print(f"{n} tests passed")
