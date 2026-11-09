"""Mechanism test + cheap fix: does per-cell-normalized aggregation recover cross-tissue transfer?

STAGED 2026-11-08 (Spark unreachable at write time) -- ready to run when Spark returns.

The 2x2 decomposition showed knowledge (pathway/TF MEANS) wins only under {scarce labels x held-out
CELL-TYPE} and LOSES under held-out TISSUE at every budget. Proposed mechanism (from the 2026-09-02
KNOWLEDGE_BOTTLENECK_V1_ERROR_ANALYSIS E2): a per-cell MEAN inherits the compartment's baseline
OFFSET, so across tissues the knowledge features carry a tissue-batch term that breaks transfer.

Direct, FALSIFIABLE prediction of that mechanism: strip the per-cell offset BEFORE aggregating and the
cross-tissue transfer failure should shrink or vanish. This is testable at the FEATURE LEVEL (no
encoder, CPU) -- i.e. a cheap fix that needs no GPU retrain if it works.

VARIANTS of the knowledge features (same 512 pathway + 256 TF gene sets):
  know_mean : mean over corpus-scaled HVG expr          <- the CURRENT construction (inherits offset)
  know_pc   : mean over PER-CELL z-scored HVG expr      <- offset-stripped (the fix)
  know_pc_shuf : per-cell-z mean over size-matched SHUFFLED sets  <- null for the fix
  raw       : corpus-scaled HVG expr                    <- baseline (as in all prior probes)

TEST: leave-one-tissue-out for the well-powered held-out tissues (lung, spleen), at FULL and SCARCE
training budgets (strip offset should help most under shift; scarce tests it doesn't break the
cell-type-scarcity win's regularization). 10 paired draws for scarce budgets, fixed C=0.01.
DECISIVE CONTRAST per (tissue,budget): know_pc - raw  vs  know_mean - raw.
  If know_pc - raw >> know_mean - raw (ideally >= 0): offset is the cause; per-cell-norm is the fix.
  If know_pc - raw ~ know_mean - raw (still negative): offset is NOT the (sole) cause -- revisit.

RUN (when Spark is back):
  WS=/home/yzhang/immune_fm_spark AUD=/home/yzhang/immune_fm_spark/eval_repair_20261107 \
    python3 run_percellnorm_crosstissue.py
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
OUT = Path(AUD) / "percellnorm_crosstissue_20261108"; OUT.mkdir(exist_ok=True)
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
x, ng = align_genes(list(A.var_names), norm, hvg)              # log1p CP10k HVG matrix [N,2000]
y = (A.obs["stim"].astype(str).to_numpy() != "unstimulated").astype(int)
tissue = A.obs["tissue"].astype(str).to_numpy(); del A, counts, norm

xs = ((x - sc["mean"]) / sc["scale"]).astype(np.float32)        # corpus-scaled (per-GENE); raw + know_mean
# per-cell z-score across the HVG axis -> strips each cell's global offset/depth BEFORE aggregation
mu = x.mean(1, keepdims=True); sd = x.std(1, keepdims=True); sd[sd == 0] = 1.0
xr = ((x - mu) / sd).astype(np.float32)

bases = K.fit_bases(hvg, f"{WS}/fs_long/work"); assert bases["n_know"] == 768
n_hvg = len(hvg); sizes = [len(c) for c in (bases["pathways"] + bases["tf"])]
def shuf_bases(seed):
    rng = np.random.RandomState(seed)
    cols = [np.sort(rng.choice(n_hvg, size=s, replace=False)).astype(np.int64) for s in sizes]
    k = len(bases["pathways"]); return {"pathways": cols[:k], "tf": cols[k:], "n_know": len(cols), "n_hvg": n_hvg}
FEAT = {
    "raw":          xs,
    "know_mean":    K.transform(xs, bases),       # current (offset-carrying)
    "know_pc":      K.transform(xr, bases),       # offset-stripped (the fix)
    "know_pc_shuf": K.transform(xr, shuf_bases(0)),
}

BUDGETS = [None, 125, 60]; DRAWS = 10; MINPOS = 4; HELDOUT = ["lung", "spleen"]
def strat_n(pool, n, rng):
    pos = pool[y[pool] == 1]; neg = pool[y[pool] == 0]; frac = n / len(pool)
    npos = min(max(MINPOS, int(round(len(pos) * frac))), len(pos))
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
        rep = {a: [] for a in FEAT}
        for d in range(DRAWS):
            tr = pool if bud is None else strat_n(pool, bud, np.random.RandomState(777 * d + bud))
            if bud is not None and (y[tr].sum() < MINPOS or (1 - y[tr]).sum() < MINPOS): continue
            for a, F in FEAT.items():
                rep[a].append(float(average_precision_score(yt, fit_pred(F, tr, te))))
            if bud is None: break
        dm = np.asarray(rep["know_mean"]) - np.asarray(rep["raw"])   # current - raw
        dp = np.asarray(rep["know_pc"]) - np.asarray(rep["raw"])     # fixed   - raw
        ds = np.asarray(rep["know_pc"]) - np.asarray(rep["know_pc_shuf"])
        results.append(dict(tissue=T, budget=("full" if bud is None else bud), n_test=int(len(te)),
                            n_test_pos=int(yt.sum()), n_draws=len(rep["raw"]),
                            raw=float(np.mean(rep["raw"])), know_mean=float(np.mean(rep["know_mean"])),
                            know_pc=float(np.mean(rep["know_pc"])),
                            know_mean_minus_raw=float(dm.mean()), know_pc_minus_raw=float(dp.mean()),
                            know_pc_minus_raw_fracpos=float((dp > 0).mean()),
                            know_pc_minus_shuf=float(ds.mean())))
        print(json.dumps(results[-1]), flush=True)

(OUT / "results.json").write_text(json.dumps(dict(protocol="percellnorm_aggregation_fix_leave_tissue_out",
    interpreter=sys.version, platform=platform.platform(), results=results), indent=2))
(OUT / "memory.json").write_text(json.dumps(dict(seconds=time.time() - start,
    maxrss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss), indent=2))
print("\n=== per-cell-norm fix: does offset-stripping recover cross-tissue transfer? ===", flush=True)
print("  (decisive: know_pc-raw should be >> know_mean-raw, ideally >=0)", flush=True)
for T in HELDOUT:
    print(f" held-out {T}:", flush=True)
    for r in [r for r in results if r["tissue"] == T]:
        print(f"   train~{str(r['budget']):>5s}  raw={r['raw']:.3f}  know_mean={r['know_mean']:.3f}"
              f"  know_pc={r['know_pc']:.3f}   [know_mean-raw={r['know_mean_minus_raw']:+.4f}]"
              f"  know_pc-raw={r['know_pc_minus_raw']:+.4f} (p+={r['know_pc_minus_raw_fracpos']:.2f})", flush=True)
print("PERCELLNORM_CROSSTISSUE_COMPLETE", flush=True)
