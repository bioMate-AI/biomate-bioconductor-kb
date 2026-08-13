"""Leverage proof-point: the market's #1 cleaning task (bulk expression normalize -> ComBat ->
outlier) with a QC VERDICT bolted on. Uses the REAL ComBat algorithm (combat.pycombat).

Demonstrates the generalization of the alignment-QC gate from single-cell to bulk: run ComBat,
then VERIFY it removed batch WITHOUT erasing the biological condition. Shows the verdict
correctly PASSES a clean correction and FLAGS an over-correction (batch confounded w/ condition).
"""
import numpy as np, pandas as pd
from combat.pycombat import pycombat
from sklearn.decomposition import PCA
from sklearn.metrics import silhouette_score

def simulate(confound, seed=0, N=80, G=500, cond_eff=1.0, batch_eff=2.0):
    rng = np.random.RandomState(seed)
    cond = np.array([0]*(N//2) + [1]*(N//2))
    # batch aligned with condition with prob 0.5+confound/2  (confound=0 -> independent)
    batch = np.array([c if rng.rand() < 0.5 + confound/2 else 1-c for c in cond])
    cg = np.arange(0, 100); bg = np.arange(100, 200)          # condition- and batch-driven genes
    X = rng.normal(0, 1, (G, N))                              # log-expression noise
    X[np.ix_(cg, np.arange(N))] += cond_eff * (2*cond - 1)    # biology signal
    X[np.ix_(bg, np.arange(N))] += batch_eff * (2*batch - 1)  # technical signal
    return pd.DataFrame(X), cond, batch

def sep(X, labels):           # separability of `labels` in PCA space (silhouette; higher=separable)
    emb = PCA(n_components=10, random_state=0).fit_transform(X.T.values)
    return float(silhouette_score(emb, labels))

def outliers(X, k=3.5):       # robust PCA-distance outlier flag
    emb = PCA(n_components=5, random_state=0).fit_transform(X.T.values)
    d = np.linalg.norm(emb - np.median(emb, 0), axis=1)
    mad = np.median(np.abs(d - np.median(d))) or 1.0
    return int(((d - np.median(d)) / (1.4826*mad) > k).sum())

def clean_and_verify(confound, tag):
    X, cond, batch = simulate(confound)
    cs_b, bs_b = sep(X, cond), sep(X, batch)                  # before
    Xc = pycombat(X, list(batch))                             # REAL ComBat batch correction
    cs_a, bs_a = sep(Xc, cond), sep(Xc, batch)               # after
    batch_removed = bs_a < 0.4 * bs_b or bs_a < 0.05
    biology_kept  = cs_a > 0.7 * cs_b
    verdict = ("TRUSTED" if batch_removed and biology_kept else
               "OVER-CORRECTED (biology erased)" if batch_removed and not biology_kept else
               "UNDER-CORRECTED (batch remains)" if not batch_removed and biology_kept else
               "FAILED (batch remains, biology hurt)")
    print(f"\n### {tag} (confound={confound}) — outliers flagged: {outliers(Xc)}")
    print(f"  condition separability: {cs_b:+.3f} -> {cs_a:+.3f}  (biology; want KEPT)")
    print(f"  batch     separability: {bs_b:+.3f} -> {bs_a:+.3f}  (technical; want REMOVED)")
    print(f"  batch_removed={batch_removed}  biology_kept={biology_kept}")
    print(f"  >>> QC VERDICT: {verdict}")
    return verdict

if __name__ == "__main__":
    print("CLEAN + PROVE IT — bulk normalize->ComBat->outlier with a QC verdict (real pyComBat)")
    v0 = clean_and_verify(0.0, "CLEAN case  (batch independent of condition)")
    v1 = clean_and_verify(0.95, "CONFOUNDED case (batch ~ condition)")
    print("\n================ SUMMARY ================")
    print(f"clean      -> {v0}")
    print(f"confounded -> {v1}")
    ok = v0 == "TRUSTED" and v1.startswith("OVER-CORRECTED")
    print("\nRESULT: the QC verdict distinguishes a good ComBat from an over-correction "
          + ("✓ (leverage proof-point works)" if ok else "✗ (needs tuning)"))
