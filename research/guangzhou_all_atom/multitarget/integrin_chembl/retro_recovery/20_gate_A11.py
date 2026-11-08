"""A11 gate runs (new statuses, Bonferroni primary level, equivalence margin) on the registered and variant benchmarks. Writes results/gate_A11_<tag>.json and one summary table.
Tags: I_v1 (registered folds), I_v1_Tall (flat-disjoint training), I_v1_Ttan (Tanimoto>=0.90 purge), I_CD, I_EX (exact Ki/Kd, non-censored), I_v2 (folds_v2), M2_v1_Tall, M_v1_Tall.
Item-level controls for I-type sets: C4 censoring indicator, C5 assay-type indicators (IC50-only / contains Ki-Kd / contains EC50)."""
import os, sys, json
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; RES = f"{HERE}/results"; sys.path.insert(0, HERE)
import validity_gate as G, harness as H
from rdkit import Chem, DataStructs, RDLogger
from rdkit.Chem import AllChem
RDLogger.DisableLog("rdApp.*")
prox = G.load_proxies(); C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); flat = C.flat_key; P = pd.read_csv(f"{DATA}/pair_labels.csv.gz")
def tf_folds(ver):
    T = pd.read_csv(f"{DATA}/targets{'_v2' if ver == 2 else ''}.csv"); fo = pd.read_csv(f"{DATA}/folds_v{ver}.csv"); return T[["target_key", "family", "genes"]], dict(zip(fo.family, fo.fold)), dict(zip(T.target_key, T.family))
def excl_all(fam, folds): P["fold"] = P.target_key.map(lambda t: folds[fam[t]]); return {f: set(P[P.fold == f].compound_id.map(flat)) for f in range(5)}
def excl_tan(fam, folds, thr=0.90):
    gen = AllChem.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=True); ids = sorted(set(P.compound_id)); idx = {c: i for i, c in enumerate(ids)}
    X = np.stack([np.array(list(gen.GetFingerprintAsNumPy(Chem.MolFromSmiles(C.loc[c, "iso_smiles"]))), np.uint8) for c in ids]).astype(np.float32); xs = X.sum(1)
    P["fold"] = P.target_key.map(lambda t: folds[fam[t]]); out = {}
    for f in range(5):
        held = sorted(set(P[P.fold == f].compound_id)); hi = np.array([idx[c] for c in held]); near = np.zeros(len(ids), bool)
        for a in range(0, len(ids), 1500):
            inter = X[a:a + 1500] @ X[hi].T; S = inter / (xs[a:a + 1500, None] + xs[hi][None, :] - inter + 1e-9); near[a:a + 1500] = (S >= thr).any(1)
        out[f] = set(flat[np.array(ids)[near]])
    return out
meta = P.set_index(["compound_id", "target_key"])
def item_controls(items):
    m = meta.reindex(list(zip(items.compound_id, items.target_key))); rel = m.relations.fillna("").values; at = m.assay_types.fillna("").values
    return {"C4_censored_label": np.array([("<" in r or ">" in r) for r in rel], float), "C5_assay_IC50_only": np.array([a == "IC50" for a in at], float),
            "C5_assay_has_Ki_or_Kd": np.array([("Ki" in a or "Kd" in a) for a in at], float), "C5_assay_has_EC50": np.array([("EC50" in a) for a in at], float)}
def build_IEX(items):
    m = meta.reindex(list(zip(items.compound_id, items.target_key))); ok = (m.relations.fillna("") == "=").values & np.array([set(a.split(";")) <= {"Ki", "Kd"} and a != "" for a in m.assay_types.fillna("").values])
    d = items[ok]; c = d.groupby("target_key").label.agg(pos="sum", n="count"); keep = c[(c.pos >= 5) & ((c.n - c.pos) >= 20)].index; return d[d.target_key.isin(keep)].reset_index(drop=True)
runs = {}
tf1, folds1, fam1 = tf_folds(1); tf2, folds2, fam2 = tf_folds(2)
I = pd.read_csv(f"{DATA}/items_I.csv.gz"); ICD = pd.read_csv(f"{DATA}/items_I_CD.csv.gz"); IEX = build_IEX(I); IEX.to_csv(f"{DATA}/items_I_EX.csv.gz", index=False, compression=dict(method="gzip", mtime=0))
sel = sys.argv[1:] or ["I_v1", "I_v1_Tall", "I_v1_Ttan", "I_CD", "I_EX", "I_v2", "M2_v1_Tall", "M_v1_Tall"]
summary = {}
for tag in sel:
    if tag == "I_v1": it, tf, fo, ex, ic = I, tf1, folds1, None, True
    elif tag == "I_v1_Tall": it, tf, fo, ex, ic = I, tf1, folds1, excl_all(fam1, folds1), True
    elif tag == "I_v1_Ttan": it, tf, fo, ex, ic = I, tf1, folds1, excl_tan(fam1, folds1), True
    elif tag == "I_CD": it, tf, fo, ex, ic = ICD, tf1, folds1, excl_all(fam1, folds1), True
    elif tag == "I_EX": it, tf, fo, ex, ic = IEX, tf1, folds1, excl_all(fam1, folds1), True
    elif tag == "I_v2": it, tf, fo, ex, ic = I, tf2, folds2, excl_all(fam2, folds2), True
    elif tag == "M2_v1_Tall": it, tf, fo, ex, ic = pd.read_csv(f"{DATA}/items_M2.csv.gz"), tf1, folds1, excl_all(fam1, folds1), False
    elif tag == "M_v1_Tall": it, tf, fo, ex, ic = pd.read_csv(f"{DATA}/items_M.csv.gz"), tf1, folds1, excl_all(fam1, folds1), False
    r = G.run_gate(it, tf, prox, fo, FP=G.fp_table(it.compound_id), flat=flat, excl=ex)
    if ic:                                                         # item-level controls (secondary, Bonferroni over all secondary controls)
        ctl = item_controls(it); n_sec = len(G.SECONDARY) + len(ctl); adj = 1 - 0.05 / n_sec
        for k, v in ctl.items():
            rows = [dict(target_key=t, auc=H.tie_aware_auc(it.label.values[(it.target_key == t).values], v[(it.target_key == t).values])) for t in it.target_key.unique() if len(set(v[(it.target_key == t).values])) > 0]
            r["secondary"][k] = G._family_ci(pd.DataFrame(rows), tf, adj); r["secondary"][k]["items_used_frac"] = 1.0
        r = G.assign_status(r)
    json.dump(r, open(f"{RES}/gate_A11_{tag}.json", "w"), indent=1, default=float)
    f = lambda v: v if isinstance(v, str) else [round(v["point"], 4), round(v["lo95"], 4), round(v["hi95"], 4), v["n_families"]]
    summary[tag] = dict(status=r["status"], n_targets=int(it.target_key.nunique()), primary={k: f(v) for k, v in r["primary"].items()}, biased=r["biased_controls"], unverifiable=r["unverifiable_controls"], not_equivalent=r["not_equivalent_controls"],
                        C4=f(r["secondary"]["C4_censored_label"]) if "C4_censored_label" in r["secondary"] else None, C5=({k: f(v) for k, v in r["secondary"].items() if k.startswith("C5")} if ic else None))
    print(tag, json.dumps(summary[tag]), flush=True)
    json.dump(summary, open(f"{RES}/gate_A11_summary{'_'+'_'.join(sel) if len(sys.argv) > 1 else ''}.json", "w"), indent=1, default=float)
