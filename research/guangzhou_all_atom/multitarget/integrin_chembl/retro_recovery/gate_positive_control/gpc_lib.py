"""Validity-gate positive control (docs/20261031_GATE_POSITIVE_CONTROL_PREREG.md): planted-valid / planted-shortcut / synthetic-curve constructions and a faithful
re-implementation of the A11 gate configuration (20_gate_A11.py) that returns a compact, rerunnable record per construction."""
import os
for _v in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_v, "1")          # one BLAS thread per worker (lesson: nproc/OMP interplay made the T2 pool serial)
import sys, json
import numpy as np, pandas as pd
from scipy.stats import norm, rankdata
HERE = os.path.dirname(os.path.abspath(__file__)); RD = os.path.dirname(HERE); DATA = f"{RD}/data"; sys.path.insert(0, RD)
import validity_gate as G, harness as H

SHORTCUTS = {"S-tpsa": ["tpsa"], "S-typ": ["typicality"], "S-cens": ["C4_censored_label"], "S-diffuse": ["heavy", "tpsa", "logp", "hbd", "rotb", "fsp3"]}
DETECTORS = {"S-tpsa": ["secondary:tpsa", "primary:C2_multiproxy_leave_fold_out"], "S-typ": ["primary:C1_atomlm_typicality", "primary:C2_multiproxy_leave_fold_out"],
             "S-cens": ["secondary:C4_censored_label"], "S-diffuse": ["primary:C2_multiproxy_leave_fold_out"]}      # S-diffuse: any secondary also counts (aggregator)
_S = {}


def state():
    if _S: return _S
    prox = G.load_proxies()
    T = pd.read_csv(f"{DATA}/targets.csv"); fo = pd.read_csv(f"{DATA}/folds_v1.csv")
    P = pd.read_csv(f"{DATA}/pair_labels.csv.gz"); meta = P.set_index(["compound_id", "target_key"])
    I = pd.read_csv(f"{DATA}/items_I.csv.gz"); M2 = pd.read_csv(f"{DATA}/items_M2.csv.gz")
    cache = f"{HERE}/cache/fp_all.npz"
    if os.path.exists(cache):
        z = np.load(cache, allow_pickle=True); FP = pd.DataFrame(z["X"], index=z["ids"])
    else:
        ok = prox[G.MULTI].astype(float).notna().all(axis=1); ids = sorted(set(prox.index[ok]) | set(I.compound_id) | set(M2.compound_id))
        C = pd.read_csv(f"{DATA}/compounds.csv.gz"); ids = [c for c in ids if c in set(C.compound_id)]
        FP = G.fp_table(ids); os.makedirs(f"{HERE}/cache", exist_ok=True); np.savez(cache, X=FP.values.astype(np.float32), ids=np.array(FP.index, dtype=object))
    ok = prox[G.MULTI].astype(float).notna().all(axis=1)
    pool = sorted(c for c in prox.index[ok] if c in FP.index)
    _S.update(prox=prox, tf=T[["target_key", "family", "genes"]], folds=dict(zip(fo.family, fo.fold)), meta=meta, I=I, M2=M2, FP=FP, pool=pool)
    return _S


def item_controls(items):
    meta = state()["meta"]
    m = meta.reindex(list(zip(items.compound_id, items.target_key))); rel = m.relations.fillna("").values; at = m.assay_types.fillna("").values
    return {"C4_censored_label": np.array([("<" in r or ">" in r) for r in rel], float), "C5_assay_IC50_only": np.array([a == "IC50" for a in at], float),
            "C5_assay_has_Ki_or_Kd": np.array([("Ki" in a or "Kd" in a) for a in at], float), "C5_assay_has_EC50": np.array([("EC50" in a) for a in at], float)}


def run_A11_like(items, tf, folds, ic, FP=None):
    """Same sequence as 20_gate_A11.py for an I-type (ic=True, item-level controls) or M-type (ic=False) set; no flat-disjoint exclusion."""
    S = state(); FP = S["FP"] if FP is None else FP
    r = G.run_gate(items, tf, S["prox"], folds, FP=FP)
    if ic:
        ctl = item_controls(items); n_sec = len(G.SECONDARY) + len(ctl); adj = 1 - 0.05 / n_sec
        for k, v in ctl.items():
            rows = [dict(target_key=t, auc=H.tie_aware_auc(items.label.values[(items.target_key == t).values], v[(items.target_key == t).values])) for t in items.target_key.unique() if len(set(v[(items.target_key == t).values])) > 0]
            r["secondary"][k] = G._family_ci(pd.DataFrame(rows), tf, adj); r["secondary"][k]["items_used_frac"] = 1.0
        r = G.assign_status(r)
    return r


def compact(r):
    prim = {}
    for k, v in r["primary"].items():
        prim[k] = None if isinstance(v, str) else {x: (None if v[x] != v[x] else float(v[x])) for x in ("point", "lo", "hi", "lo90", "hi90")} | {"n_families": int(v["n_families"])}
    sec = {k: {x: (None if v[x] != v[x] else float(v[x])) for x in ("point", "lo", "hi")} | {"n_families": int(v["n_families"])} for k, v in r["secondary"].items() if isinstance(v, dict)}
    return dict(status=r["status"], biased=list(r["biased_controls"]), unverifiable=list(r["unverifiable_controls"]), not_equivalent=list(r["not_equivalent_controls"]), degenerate=list(r["degenerate_controls"]), primary=prim, secondary=sec)


def _groups(items):
    g = items.groupby("target_key").indices
    return [(t, g[t]) for t in sorted(g)]


def permute_labels(items, rng):
    lab = items.label.values.copy()
    for t, idx in _groups(items): lab[idx] = rng.permutation(lab[idx])
    return items.assign(label=lab)


def rank_normal(v):
    v = np.asarray(v, float); out = np.zeros(len(v)); ok = ~np.isnan(v)
    if ok.sum() > 1:
        r = rankdata(v[ok]); out[ok] = norm.ppf((r - 0.5) / ok.sum())
    return out


def planted_score(items, family):
    """Per-item planted score z (standardised within target)."""
    S = state(); prox = S["prox"]; z = np.zeros(len(items))
    def prop(name):
        if name == "C4_censored_label": return item_controls(items)["C4_censored_label"]
        return prox[name].reindex(items.compound_id).values.astype(float)
    for t, idx in _groups(items):
        parts = []
        for name in SHORTCUTS[family]:
            v = prop(name)[idx]
            parts.append(v - np.nanmean(v) if name == "C4_censored_label" else rank_normal(v))
        z[idx] = np.sum(parts, axis=0) / np.sqrt(len(parts))
    return z


def planted_labels(items, z, d, rng):
    lab = np.zeros(len(items), int); y = items.label.values
    for t, idx in _groups(items):
        n_pos = int(y[idx].sum()); lat = d * z[idx] + rng.standard_normal(len(idx)); lab[idx[np.argsort(-lat, kind="stable")[:n_pos]]] = 1
    return items.assign(label=lab)


def mean_target_auc(items, z):
    a = [H.tie_aware_auc(items.label.values[idx], z[idx]) for t, idx in _groups(items)]; a = [x for x in a if x == x]; return float(np.mean(a))


def calibrate(items, family, a, seeds, tol=0.005):
    """Bisection on d so the mean per-target AUC of the planted score equals a (averaged over calibration constructions)."""
    z = planted_score(items, family)
    def f(d): return float(np.mean([mean_target_auc(planted_labels(items, z, d, np.random.default_rng(s)), z) for s in seeds]))
    lo, hi = 0.0, 20.0
    if f(hi) < a - tol: return dict(d=None, achieved=f(hi), feasible=False)
    for _ in range(30):
        mid = (lo + hi) / 2; v = f(mid)
        if abs(v - a) <= tol / 4: break
        lo, hi = (mid, hi) if v < a else (lo, mid)
    return dict(d=mid, achieved=v, feasible=abs(v - a) <= tol)


def synth_benchmark(F, seed, tpf=2, clip=600):
    S = state(); I = S["I"]; rng = np.random.default_rng(seed); g = I.groupby("target_key").label.agg(["size", "sum"]); sz = g["size"].values; ps = g["sum"].values / sz
    pool = np.array(S["pool"]); rows = []; tf = []; folds = {}
    for f in range(F):
        fam = f"F{f}"; folds[fam] = f % 5
        for j in range(tpf):
            k = int(rng.integers(len(sz))); n = int(min(sz[k], clip)); npos = int(np.clip(round(n * ps[k]), 1, n - 1)); tk = f"T{f}_{j}"; tf.append((tk, fam, ""))
            comps = rng.choice(pool, n, replace=False); lab = np.zeros(n, int); lab[rng.choice(n, npos, replace=False)] = 1
            rows += [(tk, c, int(l)) for c, l in zip(comps, lab)]
    return pd.DataFrame(rows, columns=["target_key", "compound_id", "label"]), pd.DataFrame(tf, columns=["target_key", "family", "genes"]), folds


def run_job(job, calib=None):
    S = state(); kind = job["kind"]; seed = job["seed"]; rng = np.random.default_rng(seed)
    if kind == "VI":
        items = permute_labels(S["I"], rng); r = run_A11_like(items, S["tf"], S["folds"], True)
    elif kind == "VM2":
        items = permute_labels(S["M2"], rng); r = run_A11_like(items, S["tf"], S["folds"], False)
    elif kind == "S":
        z = S.setdefault("_z", {}).setdefault(job["family"], planted_score(S["I"], job["family"])); d = calib[f"{job['family']}|{job['a']}"]["d"]
        items = planted_labels(S["I"], z, d, rng); r = run_A11_like(items, S["tf"], S["folds"], True)
    elif kind == "CURVE":
        items, tf, folds = synth_benchmark(job["F"], seed); r = run_A11_like(items, tf, folds, False)
    else: raise ValueError(kind)
    return dict(id=job["id"], kind=kind, family=job.get("family"), a=job.get("a"), F=job.get("F"), seed=seed, **compact(r))
