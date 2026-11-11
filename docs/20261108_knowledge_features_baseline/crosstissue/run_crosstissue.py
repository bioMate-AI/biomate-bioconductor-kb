"""Cross-tissue transfer: does knowledge transfer better than raw RNA under DOMAIN SHIFT (full labels)?

The scarcity sweep showed knowledge beats raw when LABELS are scarce. The surveys make a second claim:
knowledge (pathway-level) is more transferable than raw expression under DISTRIBUTION SHIFT, even with
abundant labels. D534 spans 4 tissue compartments (bone_marrow, lung, lung_lymph_node, spleen) -- a
real microenvironment shift within one donor. Leave-one-tissue-out tests whether a stim classifier
trained in some compartments transfers to a held-out compartment, and whether knowledge features
transfer better than raw.

KEY: these are FEATURE-LEVEL arms (raw HVG, knowledge gene-set means) -- NO pretrained encoder is used
anywhere -- so pretraining overlap is irrelevant to this comparison (it is not testing the encoder's
learned z). The test is clean on held-in data.

Arms: raw | know_real | know_shuf0 (size-matched null) | raw_plus_know. FULL labels (the no-scarcity
regime, so a knowledge win here is a pure domain-transfer effect, distinct from the scarcity effect).
Fixed pre-registered C=0.01 (matches the hardened scarcity run). Per-held-out-tissue AUPRC, with a
test-set bootstrap (1000 resamples) giving a CI on the paired delta know_real - raw. CPU-only.

RUN:
  WS=/home/yzhang/immune_fm_spark AUD=/home/yzhang/immune_fm_spark/eval_repair_20261107 \
    python3 run_crosstissue.py
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
OUT = Path(AUD) / "crosstissue_20261108"; OUT.mkdir(exist_ok=True)
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

sc = np.load(f"{AUD}/input_artifacts/stream_hvg_scaler.npz"); hvg = list(sc["hvg_names"].astype(str))
A = ad.read_h5ad(f"{WS}/step0/GSE261278_D534.paired.h5ad")
counts = A.X.tocsr().astype(np.float64)
lib = np.asarray(counts.sum(1)).ravel(); lib[lib == 0] = 1
norm = counts.multiply(1e4 / lib[:, None]).tocsr(); norm.data = np.log1p(norm.data)
x, ng = align_genes(list(A.var_names), norm, hvg)
y = (A.obs["stim"].astype(str).to_numpy() != "unstimulated").astype(int)
tissue = A.obs["tissue"].astype(str).to_numpy()
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

def fit_pred(F, tr, te):
    scaler = StandardScaler().fit(F[tr]); aa = scaler.transform(F[tr]); bb = scaler.transform(F[te])
    clf = LogisticRegression(C=0.01, max_iter=8000, tol=1e-6, class_weight="balanced", solver="lbfgs")
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always", ConvergenceWarning); clf.fit(aa, y[tr])
    if any(issubclass(v.category, ConvergenceWarning) for v in w) or int(clf.n_iter_.max()) >= 8000:
        raise RuntimeError("unconverged")
    return clf.predict_proba(bb)[:, 1]

tissues = sorted(set(tissue))
rows, preds = [], {}
for T in tissues:
    te = np.where(tissue == T)[0]; tr = np.where(tissue != T)[0]
    yt = y[te]
    if yt.sum() < 2 or (1 - yt).sum() < 2:   # need both classes in the held-out tissue to score
        rows.append(dict(tissue=T, note="held-out tissue lacks both classes", n_test=int(len(te)), n_pos=int(yt.sum()))); continue
    arm_pred = {}
    for arm, F in FEAT.items():
        p = fit_pred(F, tr, te); arm_pred[arm] = p
        preds[f"{T}__{arm}"] = p
        rows.append(dict(tissue=T, arm=arm, n_train=int(len(tr)), n_test=int(len(te)), n_pos=int(yt.sum()),
                         auprc=float(average_precision_score(yt, p)), auroc=float(roc_auc_score(yt, p))))
    # test-set bootstrap CI on paired deltas within this held-out tissue
    rng = np.random.RandomState(0); B = 1000
    dkr, dps, dks = [], [], []
    for _ in range(B):
        bi = rng.randint(0, len(te), len(te))
        yb = yt[bi]
        if yb.sum() < 2 or (1 - yb).sum() < 2: continue
        ap = {a: average_precision_score(yb, arm_pred[a][bi]) for a in FEAT}
        dkr.append(ap["know_real"] - ap["raw"]); dps.append(ap["raw_plus_know"] - ap["raw"]); dks.append(ap["know_real"] - ap["know_shuf0"])
    def ci(d): d = np.asarray(d); return dict(mean=float(d.mean()), lo=float(np.percentile(d, 2.5)), hi=float(np.percentile(d, 97.5)), frac_pos=float((d > 0).mean()))
    rows.append(dict(tissue=T, boot_know_real_minus_raw=ci(dkr), boot_raw_plus_know_minus_raw=ci(dps), boot_know_real_minus_shuf=ci(dks)))

(OUT / "results.json").write_text(json.dumps(dict(
    protocol="leave_one_tissue_out_fullLabels_fixedC0.01_bootstrapCI",
    interpreter=sys.version, platform=platform.platform(), rows=rows), indent=2))
np.savez_compressed(OUT / "predictions.npz", y=y, tissue=tissue.astype(str), **preds)
(OUT / "memory.json").write_text(json.dumps(dict(seconds=time.time() - start,
    maxrss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss), indent=2))

print("\n=== Leave-one-tissue-out AUPRC (full labels, fixed C=0.01) ===", flush=True)
print(f"{'held-out tissue':18s} {'n_test':>7s} {'n_pos':>6s}   " + "  ".join(f"{a:>13s}" for a in FEAT), flush=True)
for T in tissues:
    rs = [r for r in rows if r.get("tissue") == T and "arm" in r]
    if not rs:
        print(f"{T:18s}  (skipped: lacks both classes)", flush=True); continue
    n_test = rs[0]["n_test"]; n_pos = rs[0]["n_pos"]
    cells = "  ".join(f"{[r for r in rs if r['arm']==a][0]['auprc']:.4f}       " for a in FEAT)
    print(f"{T:18s} {n_test:>7d} {n_pos:>6d}   {cells}", flush=True)
print("\n=== paired delta (test-bootstrap mean [95% CI], frac>0) ===", flush=True)
for T in tissues:
    b = [r for r in rows if r.get("tissue") == T and "boot_know_real_minus_raw" in r]
    if not b: continue
    a = b[0]["boot_know_real_minus_raw"]; s = b[0]["boot_know_real_minus_shuf"]
    print(f"{T:18s} know-raw={a['mean']:+.4f} [{a['lo']:+.3f},{a['hi']:+.3f}] p+={a['frac_pos']:.2f}   "
          f"know-shuf={s['mean']:+.4f} [{s['lo']:+.3f},{s['hi']:+.3f}]", flush=True)
print("CROSSTISSUE_COMPLETE", flush=True)
