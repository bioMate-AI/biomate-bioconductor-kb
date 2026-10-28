"""T1b helpers (PREREG docs/20261030_TECHNIQUE_T1B_FUSION.md). Reuses T1's fusion.py read-only."""
import os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.abspath(f"{HERE}/../fusion"))
import fusion as F
z, fuse, fuse2, tanimoto, analog_perm, reliability_perm, reliability_nn, spearman = F.z, F.fuse, F.fuse2, F.tanimoto, F.analog_perm, F.reliability_perm, F.reliability_nn, F.spearman


def ptk(PT, sim, y_rev, PT_rev, p=4, lam=0.05):
    """PT + analog residual correction (T1 definition). PT, PT_rev: prior predictions at candidates / revealed items; y_rev raw revealed labels;
    PT standardised over the candidate set; revealed labels standardised by their own sd (sd 1 if k < 2 or constant)."""
    PT = np.asarray(PT, float); mu, sd = PT.mean(), (PT.std() or 1.0); pz = (PT - mu) / sd; pzr = (np.asarray(PT_rev, float) - mu) / sd
    y = np.asarray(y_rev, float); ysd = np.std(y, ddof=1) if len(y) > 1 and np.std(y, ddof=1) > 1e-12 else 1.0; res = (y - y.mean()) / ysd - pzr; W = np.asarray(sim, float) ** p
    return pz + (W @ res) / (W.sum(1) + lam)
