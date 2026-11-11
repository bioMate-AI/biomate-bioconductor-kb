"""Label-scarcity sweep: does knowledge compensate for data scarcity (the surveys' core claim)?

===========================================================================================
PURPOSE
===========================================================================================
The knowledge-features baseline (run_knowledge_features_probe.py) tested at ~1000 labelled cells
and found knowledge REDUNDANT with raw RNA. But the single-cell knowledge literature (GenePT,
scELMo, GEARS, GeneCompass) reports its wins under DATA SCARCITY / low-data / unseen regimes --
precisely where a biological prior bridges absent data. ~1000 well-measured in-distribution cells
is the regime where raw expression saturates and knowledge helps LEAST.

This sweep nests-subsamples the SAME registered labelled pool down to ~60 cells and asks: does
know_real (or raw+know) ever OVERTAKE raw RNA as labels shrink? If yes, the earlier "knowledge
adds ~0" was an evaluation-regime artifact, and knowledge works in our model exactly where the
literature says it should.

KEY DESIGN POINTS
  * Subsampling is NESTED and STRATIFIED within the already-registered 10% labelled indices
    (sub) -- no new data access, no leakage into the test folds, both classes guaranteed present.
  * The size-matched SHUFFLED null (know_shuf0) is carried through the sweep, so any scarcity win
    can be attributed to biological gene-set CONTENT rather than to "768 averaged dims regularize
    better than 2000 raw dims at low n".
  * C is chosen per (arm, seed, budget) as best-over-C by POOLED-OOF AUPRC -- an EQUAL-TREATMENT
    oracle-C upper bound applied identically to every arm. It is optimistic in absolute terms, but
    the raw-vs-knowledge COMPARISON stays fair (the oracle, if anything, helps the raw arm). We
    deliberately avoided in-sample C selection, which monotonically favours the largest C.

ARMS: raw (2000-d) | know_real (768-d) | know_shuf0 (size-matched null) | raw_plus_know (2768-d).
PROTOCOL otherwise matches the baseline: GSE261278, 3 cell-type-holdout folds, 3 seeds, corpus
scaler, same feature construction. Pooled OOF AUPRC over the 3 folds, mean over 3 seeds. CPU-only.

RUN:
  WS=/home/yzhang/immune_fm_spark AUD=/home/yzhang/immune_fm_spark/eval_repair_20261107 \
    python3 run_scarcity_sweep.py
===========================================================================================
"""
import json, time, resource, warnings, sys, os, platform
from pathlib import Path
import numpy as np
import anndata as ad
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score, average_precision_score
from sklearn.exceptions import ConvergenceWarning

WS = os.environ.get("WS", "/workspace"); AUD = os.environ.get("AUD", "/audit")
OUT = Path(AUD) / "scarcity_sweep_20261108"; OUT.mkdir(exist_ok=True)
sys.path.insert(0, f"{WS}/code_20261004")
import knowledge_channel as K
K._s3 = lambda src, dst: Path(dst).is_file()          # local resources only; no S3 refresh
start = time.time()

# align_genes inlined (its module imports torch, absent on the host python); pure numpy.
def align_genes(names, X, hvg):
    idx = {str(g).upper(): i for i, g in enumerate(names)}
    cols = [idx.get(str(g).upper(), -1) for g in hvg]
    out = np.zeros((X.shape[0], len(hvg)), np.float32)
    have = [j for j, c in enumerate(cols) if c >= 0]
    Xs = X[:, [cols[j] for j in have]]
    out[:, have] = np.asarray(Xs.todense() if hasattr(Xs, "todense") else Xs, np.float32)
    return out, len(have)

# --- inputs: scaler (hvg order), data -> CP10k+log1p -> HVG-aligned -> corpus-scaled ---
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

# --- knowledge features: real sets + one size-matched shuffled null -------------------------------
bases = K.fit_bases(hvg, f"{WS}/fs_long/work"); assert bases["n_know"] == 768
n_hvg = len(hvg); sizes = [len(c) for c in (bases["pathways"] + bases["tf"])]
def shuf_bases(seed):
    rng = np.random.RandomState(seed)
    cols = [np.sort(rng.choice(n_hvg, size=s, replace=False)).astype(np.int64) for s in sizes]
    k = len(bases["pathways"]); return {"pathways": cols[:k], "tf": cols[k:], "n_know": len(cols), "n_hvg": n_hvg}
Kreal = K.transform(xs, bases); Kshuf0 = K.transform(xs, shuf_bases(0))
FEAT = {"raw": xs, "know_real": Kreal, "know_shuf0": Kshuf0,
        "raw_plus_know": np.concatenate([xs, Kreal], axis=1)}

splits = np.load(f"{AUD}/normalization_20261108/split_indices.npz")
FRACS = [1.0, 0.5, 0.25, 0.125, 0.06]      # fraction of the registered ~1000-cell labelled pool
CGRID = [.001, .01, .1, 1., 10.]           # wider low end: scarce budgets need strong regularization
MINPOS = 4                                 # floor on positives/negatives per budget (else skip fold)

def strat_subsample(sub, yy, frac, rng):
    # Draw a stratified nested subset of the labelled pool: keep class balance, honour MINPOS floor.
    pos = sub[yy[sub] == 1]; neg = sub[yy[sub] == 0]
    npos = max(MINPOS, int(round(len(pos) * frac))); nneg = max(MINPOS, int(round(len(neg) * frac)))
    npos = min(npos, len(pos)); nneg = min(nneg, len(neg))
    return np.concatenate([rng.choice(pos, npos, replace=False), rng.choice(neg, nneg, replace=False)])

preds, records = {}, []   # preds keyed per (arm,seed,frac,C) -> full OOF; best-C chosen after, by pooled OOF
for arm, F in FEAT.items():
    for seed in (0, 1, 2):
        for frac in FRACS:
            ok = True; fold_pred = {c: np.full(len(y), np.nan) for c in CGRID}
            for fold in range(3):
                stem = f"s{seed}_f{fold}"
                sub = splits[stem + "_labelled"]; te = splits[stem + "_test"]
                # Deterministic per (seed, frac, fold) so the sweep is reproducible.
                rng = np.random.RandomState(1000 * seed + int(frac * 1000) + fold)
                bud = strat_subsample(sub, y, frac, rng)
                # Guard: too few of either class at this budget -> skip the whole (arm,seed,frac).
                if int(y[bud].sum()) < MINPOS or int((1 - y[bud]).sum()) < MINPOS:
                    ok = False; break
                scaler = StandardScaler().fit(F[bud]); aa = scaler.transform(F[bud]); bb = scaler.transform(F[te])
                for c in CGRID:
                    clf = LogisticRegression(C=c, max_iter=8000, tol=1e-6, class_weight="balanced", solver="lbfgs")
                    with warnings.catch_warnings(record=True) as w:
                        warnings.simplefilter("always", ConvergenceWarning); clf.fit(aa, y[bud])
                    conv = (not any(issubclass(v.category, ConvergenceWarning) for v in w)) and int(clf.n_iter_.max()) < 8000
                    if not conv: raise RuntimeError(f"Unconverged {arm} s{seed} f{fold} frac{frac} C{c}")
                    fold_pred[c][te] = clf.predict_proba(bb)[:, 1]   # accumulate OOF per C
                records.append(dict(arm=arm, seed=seed, fold=fold, frac=frac, n_budget=int(len(bud)),
                                    n_pos=int(y[bud].sum()), n_feat=int(F.shape[1])))
            if ok:
                for c in CGRID:
                    preds[f"{arm}__{seed}__frac{frac}__C{c}"] = fold_pred[c]
        print(json.dumps({"arm": arm, "seed": seed, "done": True}), flush=True)

# --- per (arm,seed,frac): best-over-C by pooled-OOF AUPRC (equal-treatment oracle, same for all arms) ---
tmp = {}
for key, v in preds.items():
    if not np.isfinite(v).all(): continue              # a skipped budget leaves NaNs -> drop
    arm, seed, fr, cstr = key.split("__")
    tmp.setdefault((arm, int(seed), float(fr[4:])), []).append(
        (float(average_precision_score(y, v)), float(roc_auc_score(y, v)), float(cstr[1:])))
per = []
for (arm, seed, frac), lst in tmp.items():
    ap, au, c = max(lst, key=lambda t: t[0])           # pick the C with best pooled-OOF AUPRC
    per.append(dict(arm=arm, seed=seed, frac=frac, auprc=ap, auroc=au, bestC=c))
agg = {}
for r in per: agg.setdefault((r["arm"], r["frac"]), []).append(r["auprc"])
table = [dict(arm=a, frac=f, auprc_mean=float(np.mean(v)), auprc_sd=float(np.std(v)), n_seeds=len(v))
         for (a, f), v in sorted(agg.items())]
# approximate mean labelled count per fraction (for the human-readable x-axis)
budget_n = {}
for rec in records: budget_n.setdefault(rec["frac"], []).append(rec["n_budget"])
budget_n = {f: int(np.mean(v)) for f, v in budget_n.items()}

(OUT / "results.json").write_text(json.dumps(dict(
    protocol="label_scarcity_sweep_feature_level_equal_treatment_bestC",
    fracs=FRACS, budget_mean_n=budget_n, interpreter=sys.version, platform=platform.platform(),
    table=table, per_seed=per, fit_records=records), indent=2))
np.savez_compressed(OUT / "predictions.npz", y=y, grp=g.astype(str), **preds)
(OUT / "memory.json").write_text(json.dumps(dict(seconds=time.time() - start,
    maxrss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss), indent=2))

# --- console summary: the AUPRC-vs-budget curve and the key deltas vs raw -------------------------
print("\n=== AUPRC vs labelled budget (mean over 3 seeds) ===", flush=True)
print("budget(n)   " + "  ".join(f"{a:>13s}" for a in FEAT), flush=True)
for fr in FRACS:
    row = f"~{budget_n.get(fr,0):<6d}    "
    for a in FEAT:
        m = [t for t in table if t["arm"] == a and t["frac"] == fr]
        row += f"  {m[0]['auprc_mean']:.4f}±{m[0]['auprc_sd']:.3f}" if m else "          --  "
    print(row, flush=True)
print("\n=== deltas vs raw (mean over seeds) -- positive = knowledge wins at that budget ===", flush=True)
for fr in FRACS:
    raw = [t for t in table if t["arm"] == "raw" and t["frac"] == fr]
    if not raw: continue
    r = raw[0]["auprc_mean"]
    dk = [t for t in table if t["arm"] == "know_real" and t["frac"] == fr]
    dp = [t for t in table if t["arm"] == "raw_plus_know" and t["frac"] == fr]
    print(f"~{budget_n.get(fr,0):<6d}  know_real-raw={dk[0]['auprc_mean']-r:+.4f}  "
          f"raw+know-raw={dp[0]['auprc_mean']-r:+.4f}" if dk and dp else "", flush=True)
print("SCARCITY_SWEEP_COMPLETE", flush=True)
