"""Typicality check regression/positive control (needs the frozen WS3 data + results/scores_A2_atomlm.csv):
 - the typicality score itself must be FLAGGED on M2 (measured AUC 0.665, CI above 0.5) and NOT on analysis I (AUC 0.503, CI includes 0.5)
 - a random score file must not be flagged on I (|rho| small); a score file equal to typicality must be flagged via |rho| > 0.5 on any analysis"""
import os, sys, numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import typicality_check as TC
HERE = os.path.dirname(os.path.abspath(__file__)); A2 = f"{HERE}/results/scores_A2_atomlm.csv"

def test_typicality_flags_M2_not_I():
    assert TC.check(A2, "M2")["flag"] == "TYPICALITY_SHORTCUT"
    r = TC.check(A2, "I"); assert r["typicality_auc"]["lo"] <= 0.5 <= r["typicality_auc"]["hi"], r

def test_random_not_flagged_and_copy_flagged_by_rho(tmp_path=None):
    import tempfile
    t = pd.read_csv(A2); rnd = t.assign(score=np.random.default_rng(0).normal(size=len(t)))
    with tempfile.TemporaryDirectory() as d:
        f = f"{d}/rnd.csv"; rnd.to_csv(f, index=False); r = TC.check(f, "I"); assert abs(r["spearman_score_vs_typicality"]) < 0.2 and "score_mostly_typicality(|rho|>0.5)" not in r["flag_reasons"], r
        g = f"{d}/copy.csv"; t.to_csv(g, index=False); r2 = TC.check(g, "I"); assert r2["flag"] == "TYPICALITY_SHORTCUT" and "score_mostly_typicality(|rho|>0.5)" in r2["flag_reasons"], r2
