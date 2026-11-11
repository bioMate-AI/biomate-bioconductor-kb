"""Leave-KO-out: does EXTERNAL knowledge predict UNSEEN perturbation effects? (the GEARS regime, for real)

The stimulation endpoint had no unseen-entity gap. This one does: predict a held-out KO gene's whole
transcriptional effect vector (delta over 18,533 genes) from the KO's KNOWN relations to training KOs.
If knowledge-selected neighbors predict the held-out effect better than the hard mean-null AND a
size-matched random-neighbor control, external knowledge bridges unseen perturbations -> a real,
buildable capability (the thing stimulation could never show).

Data: czi_tcell_deltas.npz (CZI genome-scale CD4+ T Perturb-seq, Marson/Pritchard 2026) -- 300 KO
genes x 18,533 readout genes, delta = LFC(KO)-LFC(ctrl). Local, no S3.

Leave-ONE-KO-out (300 folds; prediction is neighbor-averaging, no training). For held-out KO g:
  know : mean delta of TRAIN KOs sharing >=1 GO/KEGG/Reactome gene-set with g  (external knowledge)
  rand : mean delta of |N(g)| RANDOM train KOs  (size-matched control -> isolates knowledge CONTENT)
  null : mean delta of ALL train KOs            (the hard "generic perturbation response" baseline)
  zero : 0                                        (no-change)

METRIC (avoids the mean-saturation trap: full-transcriptome corr can't rank models). Per held-out KO,
score ONLY on that KO's true top-50 DE genes (|delta| rank): Pearson(pred,true) and sign-agreement.
Same eval genes for every method per KO (fair). Paired across the 300 KOs -> paired t for know-vs-null
and know-vs-rand. CPU-only.
"""
import json, time, resource, sys, os, platform, gzip
from pathlib import Path
import numpy as np
from scipy.stats import pearsonr

WS = os.environ.get("WS", "/workspace")
OUT = Path(os.environ.get("AUD", "/audit")) / "perturb_leaveKOout_20261108"; OUT.mkdir(exist_ok=True)
start = time.time()
D = np.load(f"{WS}/fs_long/work/czi_tcell_deltas.npz", allow_pickle=True)
delta = D["delta"].astype(np.float32)                 # [300 KO, 18533 genes]
ko = D["genes"].astype(str)                           # KO gene symbols
nko = len(ko)
print(f"KOs={nko}, readout genes={delta.shape[1]}", flush=True)

# --- external knowledge: which GMT gene-sets each KO gene belongs to (membership, a priori) ----------
def read_gmt(path):
    op = gzip.open(path, "rt") if path.endswith(".gz") else open(path)
    sets = []
    for ln in op:
        p = ln.rstrip("\n").split("\t")
        if len(p) >= 3: sets.append(set(p[2:]))
    return sets
gmt_sets = []
for nm in ("reactome.gmt", "kegg.gmt", "go_bp.gmt"):
    pth = f"{WS}/fs_long/work/{nm}"
    if os.path.exists(pth): gmt_sets += read_gmt(pth)
print(f"gene-sets loaded: {len(gmt_sets)}", flush=True)
# ko -> set of gmt-set indices containing it
ko_sets = [set(j for j, s in enumerate(gmt_sets) if g in s) for g in ko]
# knowledge neighbor adjacency: KOs sharing >=1 set
shared = np.zeros((nko, nko), np.int32)
for i in range(nko):
    for j in range(i + 1, nko):
        c = len(ko_sets[i] & ko_sets[j])
        if c: shared[i, j] = shared[j, i] = c
n_with_nb = int((shared.sum(1) > 0).sum())
print(f"KOs with >=1 knowledge neighbor: {n_with_nb}/{nko}", flush=True)

TOPK = 50
rng = np.random.RandomState(0)
rows = []
for g in range(nko):
    tr = np.setdiff1d(np.arange(nko), [g])
    true = delta[g]
    top = np.argsort(-np.abs(true))[:TOPK]           # this KO's true top-DE genes
    tt = true[top]
    nb = np.where(shared[g] > 0)[0]                   # knowledge neighbors (all in tr by construction)
    preds = {"null": delta[tr].mean(0), "zero": np.zeros_like(true)}
    if len(nb) > 0:
        w = shared[g, nb].astype(np.float32)
        preds["know"] = (delta[nb] * w[:, None]).sum(0) / w.sum()     # shared-count-weighted mean
        ridx = rng.choice(tr, size=len(nb), replace=False)
        preds["rand"] = delta[ridx].mean(0)                           # size-matched random neighbors
    rec = dict(ko=str(ko[g]), n_nb=int(len(nb)))
    for m, p in preds.items():
        pt = p[top]
        r = float(pearsonr(pt, tt)[0]) if np.std(pt) > 1e-9 and np.std(tt) > 1e-9 else 0.0
        sign = float(np.mean(np.sign(pt) == np.sign(tt)))
        rec[f"{m}_r"] = r; rec[f"{m}_sign"] = sign
    rows.append(rec)

def agg(key):
    v = [r[key] for r in rows if key in r]; v = np.asarray(v)
    return float(v.mean()), float(v.std(ddof=1)), len(v)
def paired(a, b):   # over KOs that have BOTH (i.e. have knowledge neighbors)
    d = np.asarray([r[a] - r[b] for r in rows if a in r and b in r])
    t = float(d.mean() / (d.std(ddof=1) / np.sqrt(len(d)))) if len(d) > 1 and d.std() > 0 else float("nan")
    return dict(mean=float(d.mean()), t=t, n=len(d), frac_pos=float((d > 0).mean()))

summary = dict(
    metric_topk=TOPK, n_ko=nko, n_with_knowledge_neighbor=n_with_nb,
    pearson={m: agg(f"{m}_r") for m in ("know", "rand", "null", "zero")},
    sign={m: agg(f"{m}_sign") for m in ("know", "rand", "null", "zero")},
    paired_pearson=dict(know_vs_null=paired("know_r", "null_r"), know_vs_rand=paired("know_r", "rand_r")),
    paired_sign=dict(know_vs_null=paired("know_sign", "null_sign"), know_vs_rand=paired("know_sign", "rand_sign")))
(OUT / "results.json").write_text(json.dumps(dict(protocol="leaveKOout_knowledge_vs_null_vs_rand_topDE",
    interpreter=sys.version, platform=platform.platform(), summary=summary, rows=rows), indent=2))
(OUT / "memory.json").write_text(json.dumps(dict(seconds=time.time() - start,
    maxrss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss), indent=2))

print(f"\n=== leave-KO-out, Pearson on true top-{TOPK} DE genes (mean over KOs) ===", flush=True)
for m in ("know", "rand", "null", "zero"):
    mu, sdv, n = agg(f"{m}_r"); mus, _, _ = agg(f"{m}_sign")
    print(f"  {m:5s}  pearson={mu:+.4f}±{sdv:.3f}  sign-acc={mus:.3f}  (n={n})", flush=True)
pn = summary["paired_pearson"]
print(f"\n  PAIRED (KOs with knowledge neighbors, n={pn['know_vs_null']['n']}):", flush=True)
print(f"   know-null: Δr={pn['know_vs_null']['mean']:+.4f} t={pn['know_vs_null']['t']:+.1f} frac>0={pn['know_vs_null']['frac_pos']:.2f}", flush=True)
print(f"   know-rand: Δr={pn['know_vs_rand']['mean']:+.4f} t={pn['know_vs_rand']['t']:+.1f} frac>0={pn['know_vs_rand']['frac_pos']:.2f}", flush=True)
print("PERTURB_LEAVEKOOUT_COMPLETE", flush=True)
