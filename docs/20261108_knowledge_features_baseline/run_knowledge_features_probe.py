"""Direct knowledge-FEATURES baseline (CPU-only, no torch/GPU).

===========================================================================================
PURPOSE
===========================================================================================
User's standing question: "everyone reports knowledge helps, how come worse here?"

Prior diagnostic (20261108_0110_..._SAVED_SCALER_KNOWLEDGE_RESULTS.md) found that toggling the
encoder's RNA-derived pathway/TF knowledge channel ON *lowered* frozen transfer (AUPRC 0.685 on
vs 0.709 off at C=1). But that toggle confounds TWO things:
  (a) whether the knowledge CONTENT carries endpoint signal, and
  (b) whether the neural CHANNEL INTEGRATION inside the frozen encoder uses it.

This probe removes the encoder entirely and tests the exact features the channel computes --
transform(scaled_HVG) = per-cell MEAN over each gene-set's HVG members -- as plain logistic-
regression inputs. That isolates (a) from (b). A size/coverage-matched SHUFFLED-gene-set null
further separates biological CONTENT from mere dimensionality/averaging.

ARMS (all computed on the saved corpus-scaled HVG expr the encoder sees):
  raw            : scaled HVG expr, 2000-d          (baseline; expect ~0.877 AUPRC @ C=1)
  know_real      : real GO/KEGG/Reactome + TF-regulon set means, 768-d
  know_shuf{0,1,2}: SHUFFLED gene sets, same size distribution, 3 null seeds, 768-d
  raw_plus_know  : concat(scaled HVG, know_real), 2768-d

DISCRIMINATION:
  know_real vs know_shuf  -> does biological membership (not dimensionality) carry stim signal?
  raw_plus_know vs raw    -> do the features add anything on top of raw RNA?
  know_real vs raw        -> are the summaries competitive with raw RNA on this endpoint?

PROTOCOL matches the restored-input diagnostic exactly: GSE261278, 15k cells (14.3% stim-positive,
flu/sars vs unstimulated), 3 cell-type-holdout folds, 3 label-sampling seeds, 10% label budget,
saved corpus scaler, fixed logistic C-grid, StandardScaler fit on labelled rows only, convergence
enforced, no selection on outer scores. CPU-only: the raw arm needs no encoder, and the knowledge
features are numpy gene-set means -- so the whole thing runs without torch/GPU.

RUN (on the Spark host, directly, no container needed):
  WS=/home/yzhang/immune_fm_spark AUD=/home/yzhang/immune_fm_spark/eval_repair_20261107 \
    python3 run_knowledge_features_probe.py
  WS mounts the code + data (code_20261004/, fs_long/work, step0/); AUD holds the scaler, splits,
  and receives the output dir knowledge_features_20261108/.
===========================================================================================
"""
import json, time, resource, warnings, sys, platform
from pathlib import Path
import numpy as np
import anndata as ad
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score, average_precision_score
from sklearn.exceptions import ConvergenceWarning

import os
# Container mount points by default; overridable so the same script runs directly on the host.
WS = os.environ.get("WS", "/workspace"); AUD = os.environ.get("AUD", "/audit")
OUT = Path(AUD) / "knowledge_features_20261108"; OUT.mkdir(exist_ok=True)
sys.path.insert(0, f"{WS}/code_20261004")      # knowledge_channel lives here and is torch-free
import knowledge_channel as K
# The real knowledge channel tries to refresh gene-set resources (gmt/TF parquet) from S3 if a
# file is absent. We force it to use ONLY the preserved local resources (no network, byte-stable):
# the override makes _s3 a no-op that reports "present" iff the file already exists on disk.
K._s3 = lambda src, dst: Path(dst).is_file()
start = time.time()

# --- align_genes inlined from finetune_pretrained_vs_scratch.py -----------------------------------
# That module does `import torch` at top level, which is absent in the host's system python. The
# function itself is pure numpy, so we inline it verbatim to keep the probe torch-free.
def align_genes(names, X, hvg):
    # Map the data's genes onto the checkpoint's fixed 2000-HVG axis (upper-cased symbol match).
    # Genes present in the HVG panel but missing from the data are left as zeros (explicit convention).
    idx = {str(g).upper(): i for i, g in enumerate(names)}
    cols = [idx.get(str(g).upper(), -1) for g in hvg]
    out = np.zeros((X.shape[0], len(hvg)), np.float32)
    have = [j for j, c in enumerate(cols) if c >= 0]
    Xs = X[:, [cols[j] for j in have]]
    out[:, have] = np.asarray(Xs.todense() if hasattr(Xs, "todense") else Xs, np.float32)
    return out, len(have)

# --- inputs: saved corpus scaler (also the source of hvg_names), the data, and the fixed splits ---
# The scaler npz carries hvg_names, so we never need to torch.load the checkpoint just for gene order.
sc = np.load(f"{AUD}/input_artifacts/stream_hvg_scaler.npz")
hvg = list(sc["hvg_names"].astype(str))
assert np.isfinite(sc["mean"]).all() and np.isfinite(sc["scale"]).all() and (sc["scale"] > 0).all()

A = ad.read_h5ad(f"{WS}/step0/GSE261278_D534.paired.h5ad")
counts = A.X.tocsr().astype(np.float64)
# Sanity: X must be raw integer counts (we apply the normalization ourselves below, reproducibly).
assert np.isfinite(counts.data).all() and (counts.data >= 0).all() and np.allclose(counts.data, np.round(counts.data))
lib = np.asarray(counts.sum(1)).ravel(); lib[lib == 0] = 1
norm = counts.multiply(1e4 / lib[:, None]).tocsr(); norm.data = np.log1p(norm.data)   # CP10k + log1p
x, ng = align_genes(list(A.var_names), norm, hvg)                                     # [N, 2000] HVG matrix
# Label = stimulated (flu or sars) vs unstimulated; group = cell type (the fold-holdout unit).
stim = A.obs["stim"].astype(str).to_numpy(); assert set(stim) <= {"unstimulated", "flu", "sars"}
y = (stim != "unstimulated").astype(int)
g = A.obs["cell_type"].astype(str).to_numpy()
del A, counts, norm

# Apply the saved corpus affine scaler -> the exact input distribution the encoder/channel sees.
xs = ((x - sc["mean"]) / sc["scale"]).astype(np.float32)

# --- knowledge bases: real gene sets + three size-matched shuffled nulls --------------------------
# fit_bases builds frozen HVG-index lists for 512 pathway + 256 TF gene sets (768 features total).
bases = K.fit_bases(hvg, f"{WS}/fs_long/work")
assert bases["n_know"] == 768, bases["n_know"]
n_hvg = len(hvg)
real_cols = bases["pathways"] + bases["tf"]
sizes = [len(c) for c in real_cols]        # preserve this size distribution in the nulls

def shuffled_bases(seed):
    # Null control: same NUMBER of sets and same SIZE of each set, but members are random HVG
    # indices. Destroys biological membership while holding dimensionality/coverage fixed, so a
    # real-vs-shuffled gap is attributable to gene-set CONTENT, not to "fewer averaged features".
    rng = np.random.RandomState(seed)
    cols = [np.sort(rng.choice(n_hvg, size=s, replace=False)).astype(np.int64) for s in sizes]
    k = len(bases["pathways"])
    return {"pathways": cols[:k], "tf": cols[k:], "n_know": len(cols), "n_hvg": n_hvg}

# The corpus scaler is global, so knowledge features are identical across folds -> compute once.
Kreal = K.transform(xs, bases)                               # [N, 768] real set means
Kshuf = {k: K.transform(xs, shuffled_bases(k)) for k in (0, 1, 2)}

FEATS = {
    "raw":           lambda: xs,
    "know_real":     lambda: Kreal,
    "know_shuf0":    lambda: Kshuf[0],
    "know_shuf1":    lambda: Kshuf[1],
    "know_shuf2":    lambda: Kshuf[2],
    "raw_plus_know": lambda: np.concatenate([xs, Kreal], axis=1),
}
splits = np.load(f"{AUD}/normalization_20261108/split_indices.npz")   # 9 (seed x fold) x 3 index sets
CGRID = [.01, .1, 1., 10.]
preds, records = {}, []
for arm, getF in FEATS.items():
    F = getF()
    for seed in (0, 1, 2):
        for fold in range(3):
            stem = f"s{seed}_f{fold}"
            sub = splits[stem + "_labelled"]            # the 10% labelled training cells
            te = splits[stem + "_test"]                 # the held-out cell-type fold
            tr = splits[stem + "_normalization_fit"]    # all outer-training cells (sub is a subset)
            # Leakage guards: training and test disjoint; labelled subset lies inside training.
            assert not set(tr) & set(te) and set(sub) <= set(tr)
            # Classifier-side StandardScaler fits labelled rows ONLY (matches the prior diagnostic).
            scaler = StandardScaler().fit(F[sub]); aa = scaler.transform(F[sub]); bb = scaler.transform(F[te])
            for c in CGRID:
                clf = LogisticRegression(C=c, max_iter=5000, tol=1e-6, class_weight="balanced", solver="lbfgs")
                with warnings.catch_warnings(record=True) as w:
                    warnings.simplefilter("always", ConvergenceWarning); clf.fit(aa, y[sub])
                # Hard-fail on non-convergence so a silently truncated optimizer can't fake a result.
                conv = (not any(issubclass(v.category, ConvergenceWarning) for v in w)) and int(clf.n_iter_.max()) < 5000
                if not conv:
                    raise RuntimeError(f"Unconverged {arm} s{seed} f{fold} C{c} iters={int(clf.n_iter_.max())}")
                # Accumulate out-of-fold predictions: the 3 cell-type folds partition all cells, so
                # filling preds[key][te] across folds yields a full OOF array per (arm, seed, C).
                key = f"{arm}__{seed}__C{c}"
                preds.setdefault(key, np.full(len(y), np.nan)); preds[key][te] = clf.predict_proba(bb)[:, 1]
                records.append(dict(arm=arm, seed=seed, fold=fold, C=c, iters=int(clf.n_iter_.max()),
                                    n_labelled=int(len(sub)), n_test=int(len(te)), n_feat=int(F.shape[1])))
            print(json.dumps(records[-1]), flush=True)

# --- pooled OOF metrics per (arm, seed, C); then mean over seeds for the summary table ------------
per = []
for key, v in preds.items():
    assert np.isfinite(v).all()                          # every cell must have a prediction
    arm, seed, cstr = key.split("__")
    per.append(dict(arm=arm, seed=int(seed), C=float(cstr[1:]),
                    auroc=float(roc_auc_score(y, v)), auprc=float(average_precision_score(y, v))))
summary = {}
for r in per:
    summary.setdefault((r["arm"], r["C"]), []).append(r)
table = []
for (arm, c), rs in sorted(summary.items()):
    au = np.array([r["auroc"] for r in rs]); ap = np.array([r["auprc"] for r in rs])
    table.append(dict(arm=arm, C=c, auroc_mean=float(au.mean()), auroc_sd=float(au.std()),
                      auprc_mean=float(ap.mean()), auprc_sd=float(ap.std()), n_seeds=len(rs)))

np.savez_compressed(OUT / "predictions.npz", y=y, grp=g.astype(str), **preds)
(OUT / "results.json").write_text(json.dumps(dict(
    protocol="direct_knowledge_features_vs_shuffled_null_corpus_scaled_fixed_Cgrid",
    genes_aligned=int(ng), n_cells=int(len(y)), n_pos=int(y.sum()), pos_frac=float(y.mean()),
    n_pathways=len(bases["pathways"]), n_tf=len(bases["tf"]), set_size_min=int(min(sizes)),
    set_size_med=int(np.median(sizes)), set_size_max=int(max(sizes)),
    interpreter=sys.version, platform=platform.platform(),
    numpy=np.__version__, table=table, per_seed=per, fit_records=records), indent=2))
(OUT / "memory.json").write_text(json.dumps(dict(
    seconds=time.time() - start, maxrss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss), indent=2))

# compact console summary: best-over-C and C=1 per arm
print("\n=== AUPRC (mean over 3 seeds), per arm, best-over-C and at C=1 ===", flush=True)
for arm in FEATS:
    rows = [t for t in table if t["arm"] == arm]
    best = max(rows, key=lambda t: t["auprc_mean"]); c1 = [t for t in rows if t["C"] == 1.0][0]
    print(f"{arm:14s}  C=1 AUPRC={c1['auprc_mean']:.4f}  best AUPRC={best['auprc_mean']:.4f}@C{best['C']}  "
          f"(AUROC@C1={c1['auroc_mean']:.4f})", flush=True)
print("KNOWLEDGE_FEATURES_PROBE_COMPLETE", flush=True)
