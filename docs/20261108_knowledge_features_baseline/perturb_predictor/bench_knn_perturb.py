"""Leave-KO-out benchmark of the knowledge-neighbor perturbation predictor on the FULL DE_stats.
Per culture context. Metrics on each KO's true top-50 residual-DE genes: Pearson + direction accuracy.
Baselines: random-neighbor (size-matched), mean-null. Variants: plain-count, jaccard, topk10, topk25,
degeneric (top-1 PC removed before averaging). Shared-count kernel computed ONCE per context and reused.
Pure numpy + h5py (this python's torch is broken -> scipy unusable; read h5ad directly)."""
import json, os, sys, gzip, time
from pathlib import Path
import numpy as np, h5py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from knn_perturb_predictor import KnnPerturbPredictor

H5 = "/home/yzhang/immune_fm_spark/perturb_full/GWCD4i.DE_stats.h5ad"
GMTDIR = "/home/yzhang/immune_fm_spark/fs_long/work"
OUT = Path("/home/yzhang/immune_fm_spark/ws_pertpred"); OUT.mkdir(exist_ok=True)
TOPK_METRIC = 50
t0 = time.time()

def pear(a, b):
    a = a - a.mean(); b = b - b.mean()
    d = np.sqrt((a * a).sum() * (b * b).sum())
    return float((a * b).sum() / d) if d > 1e-12 else 0.0

def metrics(pred, Y, idx):
    rs, sg = [], []
    for i in idx:
        top = np.argsort(-np.abs(Y[i]))[:TOPK_METRIC]
        pt, tt = pred[i, top], Y[i, top]
        if pt.std() > 1e-9 and tt.std() > 1e-9:
            rs.append(pear(pt, tt)); sg.append(float(np.mean(np.sign(pt) == np.sign(tt))))
    return np.asarray(rs), np.asarray(sg)

def tstat(d):
    d = np.asarray(d)
    return float(d.mean() / (d.std(ddof=1) / np.sqrt(len(d)))) if len(d) > 1 and d.std() > 0 else float("nan")

def read_cat(g):
    cats = g["categories"][:]; codes = g["codes"][:]
    cats = np.array([x.decode() if isinstance(x, (bytes, bytearray)) else str(x) for x in cats])
    return np.where(codes < 0, "NA", cats[np.clip(codes, 0, len(cats) - 1)])

def read_gmt(p):
    op = gzip.open(p, "rt") if p.endswith(".gz") else open(p); out = []
    for ln in op:
        q = ln.rstrip("\n").split("\t")
        if len(q) >= 3: out.append(set(q[2:]))
    return out

f = h5py.File(H5, "r")
Y_all = f["layers"]["log_fc"][:].astype(np.float32)
ko_all = read_cat(f["obs"]["target_contrast_gene_name"]).astype(str)
cond_all = read_cat(f["obs"]["culture_condition"]).astype(str)
keep = f["obs"]["ontarget_significant"][:].astype(bool) & (~f["obs"]["low_target_gex"][:].astype(bool))
f.close()
gene_sets = []
for nm in ("reactome.gmt", "kegg.gmt", "go_bp.gmt"):
    p = os.path.join(GMTDIR, nm)
    if os.path.exists(p): gene_sets += read_gmt(p)
set_of = {}
for j, s in enumerate(gene_sets):
    for g in s: set_of.setdefault(g, []).append(j)
print(f"Y={Y_all.shape} KOuniq={len(set(ko_all))} QC={int(keep.sum())}/{len(ko_all)} gene_sets={len(gene_sets)} ({time.time()-t0:.0f}s)", flush=True)

def build_S(kos):
    touched = sorted({j for g in kos for j in set_of.get(g, [])})
    col = {j: c for c, j in enumerate(touched)}
    Mb = np.zeros((len(kos), max(1, len(touched))), np.float32)
    for a, g in enumerate(kos):
        for j in set_of.get(g, []): Mb[a, col[j]] = 1.0
    S = Mb @ Mb.T; np.fill_diagonal(S, 0.0)
    deg = np.array([len(set_of.get(g, [])) for g in kos], np.float32)
    return S, deg

def weighted(S, Y):
    den = S.sum(1, keepdims=True)
    return np.where(den > 0, (S @ Y) / np.maximum(den, 1e-9), 0.0)

def topk_mat(S, k):
    W = np.zeros_like(S)
    for i in range(S.shape[0]):
        nz = np.where(S[i] > 0)[0]
        if len(nz) == 0: continue
        keepi = nz[np.argsort(-S[i, nz])[:k]]
        W[i, keepi] = S[i, keepi]
    return W

rng = np.random.RandomState(0)
summary = {}
for c in sorted(set(cond_all)):
    sel = np.where(keep & (cond_all == c))[0]
    seen, rows = set(), []
    for r in sel:
        if ko_all[r] not in seen: seen.add(ko_all[r]); rows.append(r)
    rows = np.asarray(rows); kos = ko_all[rows]; n = len(rows)
    Yc = Y_all[rows].astype(np.float32); Yc -= Yc.mean(0, keepdims=True)
    S, deg = build_S(kos)
    has = (S > 0).any(1); idx = np.where(has)[0]
    # Jaccard weights
    with np.errstate(divide="ignore", invalid="ignore"):
        J = np.where((deg[:, None] + deg[None, :] - S) > 0, S / (deg[:, None] + deg[None, :] - S), 0.0)
    np.fill_diagonal(J, 0.0)
    # de-generic: remove top-1 PC (dominant generic axis) from Yc before averaging
    v1 = np.random.RandomState(0).randn(Yc.shape[1]).astype(np.float32)   # top-1 PC via power iteration (cheap)
    for _ in range(25):
        v1 = Yc.T @ (Yc @ v1); nv = np.linalg.norm(v1); v1 = v1 / (nv if nv > 0 else 1.0)
    Ydg = Yc - (Yc @ v1)[:, None] * v1[None, :]
    preds = {
        "plain_count":  weighted(S, Yc),
        "jaccard":      weighted(J, Yc),
        "topk10_count": weighted(topk_mat(S, 10), Yc),
        "topk25_count": weighted(topk_mat(S, 25), Yc),
        "degeneric_count": weighted(S, Ydg),
    }
    # baselines
    pr = np.zeros_like(Yc)
    for g in idx:
        m = int((S[g] > 0).sum())
        pr[g] = Yc[rng.choice(np.setdiff1d(np.arange(n), [g]), m, replace=False)].mean(0)
    preds["rand_neighbor"] = pr
    preds["mean_null"] = np.broadcast_to(Yc.mean(0), Yc.shape)
    res = {}
    base_r = None
    for name, P in preds.items():
        r, sg = metrics(np.asarray(P), Yc, idx)
        res[name] = dict(pearson=float(r.mean()), pearson_sd=float(r.std()), dir_acc=float(sg.mean()), n=int(len(r)))
        if name == "plain_count": base_r = r
    # paired variant-vs-plain significance
    for name, P in preds.items():
        if name in ("plain_count", "mean_null"): continue
        r, _ = metrics(np.asarray(P), Yc, idx)
        res[name]["t_vs_plain"] = tstat(r - base_r)
    summary[c] = dict(n_ko=int(n), n_with_nb=int(has.sum()), variants=res)
    print(json.dumps({c: {k: {kk: vv for kk, vv in v.items() if kk in ("pearson", "dir_acc", "t_vs_plain")} for k, v in res.items()}}), flush=True)

json.dump(summary, open(OUT / "benchmark_results.json", "w"), indent=2)

# sanity: module.predict_loo matches inline plain_count on a 400-KO subsample of Rest
csel = np.where(keep & (cond_all == "Rest"))[0]
seen, rows = set(), []
for r in csel:
    if ko_all[r] not in seen: seen.add(ko_all[r]); rows.append(r)
rows = np.asarray(rows[:400]); kos = ko_all[rows]
Yc = Y_all[rows].astype(np.float32); Yc -= Yc.mean(0, keepdims=True)
p = KnnPerturbPredictor(weighting="count").fit(kos, Yc, gene_sets)
mod_pred = p.predict_loo()
Ss, _ = build_S(kos); inline = weighted(Ss, Yc)
maxdiff = float(np.abs(mod_pred - inline).max())
print(f"\nMODULE SANITY: max|module - inline plain_count| = {maxdiff:.2e} (should be ~0)", flush=True)

print(f"\n=== BENCHMARK (full DE_stats, top-{TOPK_METRIC} residual-DE Pearson) time {time.time()-t0:.0f}s ===", flush=True)
hdr = "context   " + "".join(f"{k:>16s}" for k in ("plain_count","jaccard","topk10_count","topk25_count","degeneric_count","rand_neighbor"))
print(hdr, flush=True)
for c, s in summary.items():
    row = f"{c:9s} " + "".join(f"{s['variants'][k]['pearson']:+.4f}         "[:16] for k in ("plain_count","jaccard","topk10_count","topk25_count","degeneric_count","rand_neighbor"))
    print(row, flush=True)
print("\nvariant t-vs-plain (positive = beats plain neighbor-mean):", flush=True)
for c, s in summary.items():
    parts = [f"{k}={s['variants'][k].get('t_vs_plain',float('nan')):+.1f}" for k in ("jaccard","topk10_count","topk25_count","degeneric_count")]
    print(f"  {c:9s} " + "  ".join(parts), flush=True)
print("BENCH_COMPLETE", flush=True)
