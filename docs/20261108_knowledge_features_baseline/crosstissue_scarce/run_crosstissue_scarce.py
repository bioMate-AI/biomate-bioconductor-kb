"""Scarce + domain-shift: the 4th cell of the 2x2 (scarcity x distribution-shift).

Established so far (feature-level, GSE261278 D534, fixed C=0.01):
  abundant + in-distribution (cell-type holdout) : knowledge LOSES  (know-raw -0.036)
  scarce   + in-distribution                     : knowledge WINS   (know-raw +0.14 @ n60)
  abundant + domain-shift   (leave-tissue-out)   : knowledge ~TIES/LOSES (know-raw -0.06..0.00)
  scarce   + domain-shift                         : <- THIS RUN

Leave-one-tissue-out (well-powered test tissues: lung, spleen) while SUBSAMPLING the training pool
(the other tissues) to scarce budgets. Does scarcity's knowledge-advantage also appear -- or compound
-- under tissue shift? 10 paired draws per budget, fixed C=0.01. know_real - raw paired delta.
Feature-level (no encoder) so pretraining overlap is irrelevant. CPU-only.
"""
import json, time, resource, warnings, sys, os, platform
from pathlib import Path
import numpy as np
import anndata as ad
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import average_precision_score
from sklearn.exceptions import ConvergenceWarning

WS = os.environ.get("WS", "/workspace"); AUD = os.environ.get("AUD", "/audit")
OUT = Path(AUD) / "crosstissue_scarce_20261108"; OUT.mkdir(exist_ok=True)
sys.path.insert(0, f"{WS}/code_20261004")
import knowledge_channel as K
K._s3 = lambda src, dst: Path(dst).is_file()
start = time.time()

def align_genes(names, X, hvg):
    idx = {str(g).upper(): i for i, g in enumerate(names)}
    cols = [idx.get(str(g).upper(), -1) for g in hvg]
    out = np.zeros((X.shape[0], len(hvg)), np.float32); have = [j for j, c in enumerate(cols) if c >= 0]
    Xs = X[:, [cols[j] for j in have]]
    out[:, have] = np.asarray(Xs.todense() if hasattr(Xs, "todense") else Xs, np.float32)
    return out, len(have)

sc = np.load(f"{AUD}/input_artifacts/stream_hvg_scaler.npz"); hvg = list(sc["hvg_names"].astype(str))
A = ad.read_h5ad(f"{WS}/step0/GSE261278_D534.paired.h5ad")
counts = A.X.tocsr().astype(np.float64); lib = np.asarray(counts.sum(1)).ravel(); lib[lib == 0] = 1
norm = counts.multiply(1e4 / lib[:, None]).tocsr(); norm.data = np.log1p(norm.data)
x, ng = align_genes(list(A.var_names), norm, hvg)
y = (A.obs["stim"].astype(str).to_numpy() != "unstimulated").astype(int)
tissue = A.obs["tissue"].astype(str).to_numpy(); del A, counts, norm
xs = ((x - sc["mean"]) / sc["scale"]).astype(np.float32)
bases = K.fit_bases(hvg, f"{WS}/fs_long/work"); assert bases["n_know"] == 768
n_hvg = len(hvg); sizes = [len(c) for c in (bases["pathways"] + bases["tf"])]
def shuf_bases(seed):
    rng = np.random.RandomState(seed)
    cols = [np.sort(rng.choice(n_hvg, size=s, replace=False)).astype(np.int64) for s in sizes]
    k = len(bases["pathways"]); return {"pathways": cols[:k], "tf": cols[k:], "n_know": len(cols), "n_hvg": n_hvg}
Kreal = K.transform(xs, bases); Kshuf0 = K.transform(xs, shuf_bases(0))
FEAT = {"raw": xs, "know_real": Kreal, "know_shuf0": Kshuf0, "raw_plus_know": np.concatenate([xs, Kreal], 1)}

BUDGETS = [None, 250, 125, 60]   # None = full non-T training pool
DRAWS = 10; MINPOS = 4; HELDOUT = ["lung", "spleen"]
def strat_n(pool, n, rng):
    pos = pool[y[pool] == 1]; neg = pool[y[pool] == 0]
    # keep the pool's class ratio at budget n, floored at MINPOS each
    frac = n / len(pool); npos = min(max(MINPOS, int(round(len(pos) * frac))), len(pos))
    nneg = min(max(MINPOS, int(round(len(neg) * frac))), len(neg))
    return np.concatenate([rng.choice(pos, npos, replace=False), rng.choice(neg, nneg, replace=False)])
def fit_pred(F, tr, te):
    scaler = StandardScaler().fit(F[tr]); aa = scaler.transform(F[tr]); bb = scaler.transform(F[te])
    clf = LogisticRegression(C=0.01, max_iter=8000, tol=1e-6, class_weight="balanced", solver="lbfgs")
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always", ConvergenceWarning); clf.fit(aa, y[tr])
    if any(issubclass(v.category, ConvergenceWarning) for v in w) or int(clf.n_iter_.max()) >= 8000:
        raise RuntimeError("unconverged")
    return clf.predict_proba(bb)[:, 1]

results = []
for T in HELDOUT:
    te = np.where(tissue == T)[0]; pool = np.where(tissue != T)[0]; yt = y[te]
    for bud in BUDGETS:
        rep = {a: [] for a in FEAT}; n_eff = []
        for d in range(DRAWS):
            if bud is None:
                tr = pool
            else:
                rng = np.random.RandomState(777 * d + (0 if bud is None else bud))
                tr = strat_n(pool, bud, rng)
                if y[tr].sum() < MINPOS or (1 - y[tr]).sum() < MINPOS: continue
            n_eff.append(int(len(tr)))
            for a, F in FEAT.items():
                rep[a].append(float(average_precision_score(yt, fit_pred(F, tr, te))))
            if bud is None: break   # full pool is deterministic, 1 draw
        d_kr = np.asarray(rep["know_real"]) - np.asarray(rep["raw"])
        d_ks = np.asarray(rep["know_real"]) - np.asarray(rep["know_shuf0"])
        results.append(dict(tissue=T, budget=("full" if bud is None else bud), n_train=int(np.mean(n_eff)),
                            n_test=int(len(te)), n_test_pos=int(yt.sum()), n_draws=len(rep["raw"]),
                            raw=float(np.mean(rep["raw"])), know_real=float(np.mean(rep["know_real"])),
                            raw_plus_know=float(np.mean(rep["raw_plus_know"])),
                            know_minus_raw_mean=float(d_kr.mean()), know_minus_raw_fracpos=float((d_kr > 0).mean()),
                            know_minus_shuf_mean=float(d_ks.mean())))
        print(json.dumps(results[-1]), flush=True)

(OUT / "results.json").write_text(json.dumps(dict(protocol="leave_tissue_out_scarce_training_fixedC0.01",
    interpreter=sys.version, platform=platform.platform(), results=results), indent=2))
(OUT / "memory.json").write_text(json.dumps(dict(seconds=time.time() - start,
    maxrss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss), indent=2))
print("\n=== scarce + domain-shift: know_real - raw (paired over draws) ===", flush=True)
for T in HELDOUT:
    print(f" held-out {T} (test n_pos={[r for r in results if r['tissue']==T][0]['n_test_pos']}):", flush=True)
    for r in [r for r in results if r["tissue"] == T]:
        print(f"   train~{str(r['budget']):>5s} (n={r['n_train']:5d})  raw={r['raw']:.3f} know={r['know_real']:.3f}"
              f"  know-raw={r['know_minus_raw_mean']:+.4f} (p+={r['know_minus_raw_fracpos']:.2f})"
              f"  know-shuf={r['know_minus_shuf_mean']:+.4f}", flush=True)
print("CROSSTISSUE_SCARCE_COMPLETE", flush=True)
