"""Hardened scarcity crossover: pre-registered fixed C + paired power, removing the oracle-C caveat.

The scarcity sweep (run_scarcity_sweep.py) showed knowledge overtakes raw RNA as labels shrink, but
it used (a) a best-over-C ORACLE (open to "you cherry-picked C by test AUPRC") and (b) only 3 seeds
with large variance at n~60. This run closes both:

  * FIXED pre-registered C = 0.01 (strong regularization) for EVERY arm and budget -- no selection,
    no oracle, identical treatment. (0.01 was best-or-near-best at full budget for raw and know in
    the sweep, so it is a sensible a-priori default, not tuned to the crossover.)
  * 10 independent PAIRED subsample DRAWS per registered seed => 3 x 10 = 30 replicates. The same
    subsample indices are used across all arms within a draw, so know_real - raw is a PAIRED delta.
  * Paired significance per budget: mean delta, SD, fraction of draws with delta>0, paired t.

Arms: raw | know_real | know_shuf0 (size-matched null) | raw_plus_know. Same GSE261278 splits,
corpus scaler, feature construction. Pooled OOF AUPRC over 3 cell-type folds per replicate. CPU-only.

RUN:
  WS=/home/yzhang/immune_fm_spark AUD=/home/yzhang/immune_fm_spark/eval_repair_20261107 \
    python3 run_scarcity_power.py
"""
import json, time, resource, warnings, sys, os, platform
from pathlib import Path
import numpy as np
import anndata as ad
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.exceptions import ConvergenceWarning

WS = os.environ.get("WS", "/workspace"); AUD = os.environ.get("AUD", "/audit")
OUT = Path(AUD) / "scarcity_power_20261108"; OUT.mkdir(exist_ok=True)
sys.path.insert(0, f"{WS}/code_20261004")
import knowledge_channel as K
K._s3 = lambda src, dst: Path(dst).is_file()
start = time.time()

def align_genes(names, X, hvg):
    idx = {str(g).upper(): i for i, g in enumerate(names)}
    cols = [idx.get(str(g).upper(), -1) for g in hvg]
    out = np.zeros((X.shape[0], len(hvg)), np.float32)
    have = [j for j, c in enumerate(cols) if c >= 0]
    Xs = X[:, [cols[j] for j in have]]
    out[:, have] = np.asarray(Xs.todense() if hasattr(Xs, "todense") else Xs, np.float32)
    return out, len(have)

sc = np.load(f"{AUD}/input_artifacts/stream_hvg_scaler.npz")
hvg = list(sc["hvg_names"].astype(str))
A = ad.read_h5ad(f"{WS}/step0/GSE261278_D534.paired.h5ad")
counts = A.X.tocsr().astype(np.float64)
lib = np.asarray(counts.sum(1)).ravel(); lib[lib == 0] = 1
norm = counts.multiply(1e4 / lib[:, None]).tocsr(); norm.data = np.log1p(norm.data)
x, ng = align_genes(list(A.var_names), norm, hvg)
y = (A.obs["stim"].astype(str).to_numpy() != "unstimulated").astype(int)
g = A.obs["cell_type"].astype(str).to_numpy()
del A, counts, norm
xs = ((x - sc["mean"]) / sc["scale"]).astype(np.float32)

bases = K.fit_bases(hvg, f"{WS}/fs_long/work"); assert bases["n_know"] == 768
n_hvg = len(hvg); sizes = [len(c) for c in (bases["pathways"] + bases["tf"])]
def shuf_bases(seed):
    rng = np.random.RandomState(seed)
    cols = [np.sort(rng.choice(n_hvg, size=s, replace=False)).astype(np.int64) for s in sizes]
    k = len(bases["pathways"]); return {"pathways": cols[:k], "tf": cols[k:], "n_know": len(cols), "n_hvg": n_hvg}
Kreal = K.transform(xs, bases); Kshuf0 = K.transform(xs, shuf_bases(0))
FEAT = {"raw": xs, "know_real": Kreal, "know_shuf0": Kshuf0, "raw_plus_know": np.concatenate([xs, Kreal], 1)}

splits = np.load(f"{AUD}/normalization_20261108/split_indices.npz")
FRACS = [1.0, 0.5, 0.25, 0.125, 0.06]
C_FIXED = 0.01          # pre-registered, strong regularization, identical for all arms/budgets
DRAWS = 10              # paired subsample draws per registered seed
MINPOS = 4

def strat_subsample(sub, yy, frac, rng):
    pos = sub[yy[sub] == 1]; neg = sub[yy[sub] == 0]
    npos = min(max(MINPOS, int(round(len(pos) * frac))), len(pos))
    nneg = min(max(MINPOS, int(round(len(neg) * frac))), len(neg))
    return np.concatenate([rng.choice(pos, npos, replace=False), rng.choice(neg, nneg, replace=False)])

def fit_pred(F, bud, te):
    scaler = StandardScaler().fit(F[bud]); aa = scaler.transform(F[bud]); bb = scaler.transform(F[te])
    clf = LogisticRegression(C=C_FIXED, max_iter=8000, tol=1e-6, class_weight="balanced", solver="lbfgs")
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always", ConvergenceWarning); clf.fit(aa, y[bud])
    if any(issubclass(v.category, ConvergenceWarning) for v in w) or int(clf.n_iter_.max()) >= 8000:
        raise RuntimeError("unconverged")
    return clf.predict_proba(bb)[:, 1]

# rep_auprc[arm][frac] = list of 30 pooled-OOF AUPRC values (one per (seed,draw)); paired by index.
rep_auprc = {a: {f: [] for f in FRACS} for a in FEAT}
rep_key = {f: [] for f in FRACS}      # (seed,draw) label per replicate, same order for every arm
n_budget = {f: [] for f in FRACS}
for s in (0, 1, 2):
    for d in range(DRAWS):
        for frac in FRACS:
            # Draw the budget ONCE per (s,d,frac,fold); reuse across arms -> paired comparison.
            buds, tes, ok = [], [], True
            for f in range(3):
                stem = f"s{s}_f{f}"; sub = splits[stem + "_labelled"]; te = splits[stem + "_test"]
                rng = np.random.RandomState(100000 * s + 1000 * d + int(frac * 100) + f)
                bud = strat_subsample(sub, y, frac, rng)
                if int(y[bud].sum()) < MINPOS or int((1 - y[bud]).sum()) < MINPOS: ok = False; break
                buds.append(bud); tes.append(te)
            if not ok: continue
            n_budget[frac].append(int(np.mean([len(b) for b in buds])))
            rep_key[frac].append(f"s{s}d{d}")
            for arm, F in FEAT.items():
                oof = np.full(len(y), np.nan)
                for bud, te in zip(buds, tes):
                    oof[te] = fit_pred(F, bud, te)
                rep_auprc[arm][frac].append(float(average_precision_score(y, oof)))
    print(json.dumps({"seed": s, "done": True}), flush=True)

# --- summarize: per-arm mean/SD over 30 replicates, and PAIRED deltas vs raw with significance -----
def paired_stats(a, b):   # a - b over paired replicates
    d = np.asarray(a) - np.asarray(b); n = len(d)
    t = float(d.mean() / (d.std(ddof=1) / np.sqrt(n))) if n > 1 and d.std() > 0 else float("nan")
    return dict(mean=float(d.mean()), sd=float(d.std(ddof=1)), n=n, frac_pos=float((d > 0).mean()), t=t)

table, deltas = [], []
for frac in FRACS:
    for arm in FEAT:
        v = np.asarray(rep_auprc[arm][frac])
        table.append(dict(arm=arm, frac=frac, n_budget=int(np.mean(n_budget[frac])),
                          auprc_mean=float(v.mean()), auprc_sd=float(v.std(ddof=1)), n_rep=len(v)))
    r = rep_auprc["raw"][frac]
    deltas.append(dict(frac=frac, n_budget=int(np.mean(n_budget[frac])),
                       know_real_minus_raw=paired_stats(rep_auprc["know_real"][frac], r),
                       raw_plus_know_minus_raw=paired_stats(rep_auprc["raw_plus_know"][frac], r),
                       know_real_minus_shuf=paired_stats(rep_auprc["know_real"][frac], rep_auprc["know_shuf0"][frac])))

(OUT / "results.json").write_text(json.dumps(dict(
    protocol="scarcity_crossover_fixedC0.01_paired_30rep", C_fixed=C_FIXED, draws=DRAWS,
    interpreter=sys.version, platform=platform.platform(),
    table=table, deltas=deltas, rep_auprc={a: rep_auprc[a] for a in FEAT}, rep_key=rep_key), indent=2))
(OUT / "memory.json").write_text(json.dumps(dict(seconds=time.time() - start,
    maxrss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss), indent=2))

print("\n=== AUPRC vs budget (fixed C=0.01, mean +/- SD over 30 paired replicates) ===", flush=True)
print("budget(n)   " + "  ".join(f"{a:>13s}" for a in FEAT), flush=True)
for frac in FRACS:
    row = f"~{int(np.mean(n_budget[frac])):<6d}    "
    for a in FEAT:
        t = [r for r in table if r["arm"] == a and r["frac"] == frac][0]
        row += f"  {t['auprc_mean']:.4f}±{t['auprc_sd']:.3f}"
    print(row, flush=True)
print("\n=== paired delta know_real - raw   (and - shuffled null) ===", flush=True)
for dd in deltas:
    a = dd["know_real_minus_raw"]; b = dd["know_real_minus_shuf"]
    print(f"~{dd['n_budget']:<6d}  know-raw={a['mean']:+.4f}  frac>0={a['frac_pos']:.2f}  t={a['t']:+.1f}"
          f"   |  know-shuf={b['mean']:+.4f} t={b['t']:+.1f}", flush=True)
print("SCARCITY_POWER_COMPLETE", flush=True)
