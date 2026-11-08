"""renal_paper_results.py — produce ALL numbers for the manuscript (one place, reproducible, seeded).

Reports: dataset summary; cross-target Leave-One-Target-Out (mechanistic grey-box vs black-box GBM vs
net-charge heuristic) with mean-per-class Spearman + cluster bootstrap 95% CI + permutation p; temporal
quasi-prospective validation (train on earlier publication years, test on later); and feature ablations.
All %ID/g, mouse, timepoint as covariate. Honest: small n, wide CIs — effect sizes with uncertainty.
"""
from __future__ import annotations
import collections, json, warnings
import numpy as np
from scipy.stats import spearmanr, ConstantInputWarning
from sklearn.ensemble import GradientBoostingRegressor
import renal_mechmodel as mm

warnings.filterwarnings("ignore", category=ConstantInputWarning)
FEATS = ["q_pos", "q_neg", "residual", "alb", "cleave", "log_t", "is_sm"]


def _vec(o, drop=()):
    return [o[f] for f in FEATS if f not in drop]


def _mpc(score, y, cls):
    per = {}
    for c in set(cls):
        m = np.array([cc == c for cc in cls])
        if m.sum() >= 3 and len(set(np.array(y)[m])) > 1:
            rho = spearmanr(np.array(score)[m], np.array(y)[m]).correlation
            if not np.isnan(rho):
                per[c] = rho
    return per


def _aggregate_constructs(S, Y, CL, CA):
    """FIX B (reviewer B): collapse the (construct, timepoint) observations to ONE value per construct
    (median of score and of truth, within each class) BEFORE the within-class Spearman. The observation-
    level estimand pseudo-replicates — a construct measured at 1h/4h/24h counts 3x — inflating n and
    correlating repeated measurements of the same molecule. The construct-level estimand is the honest
    'ranks DISTINCT constructs within a held-out target'. Returns aggregated (S, Y, CL, CA)."""
    groups = {}
    order = []
    for s, y, c, a in zip(S, Y, CL, CA):
        key = (c, a)                                   # one point per (class, construct)
        if key not in groups:
            groups[key] = ([], []); order.append(key)
        groups[key][0].append(float(s)); groups[key][1].append(float(y))
    S2, Y2, CL2, CA2 = [], [], [], []
    for (c, a) in order:
        ss, yy = groups[(c, a)]
        S2.append(float(np.median(ss))); Y2.append(float(np.median(yy))); CL2.append(c); CA2.append(a)
    return np.array(S2), np.array(Y2), CL2, CA2


def _loto(obs, model, drop=()):
    classes = [c for c, n in collections.Counter(o["cls"] for o in obs).items()
               if sum(1 for o in obs if o["cls"] == c) >= 3]
    S, Y, CL, CA = [], [], [], []
    for held in classes:
        tr = [o for o in obs if o["cls"] != held]
        te = [o for o in obs if o["cls"] == held]
        if len(tr) < 8 or len(te) < 3:
            continue
        if model == "mechanistic":
            p = mm.fit(tr); s = mm.predict(p, te)
        elif model == "net_charge":
            s = [o["q_pos"] - o["q_neg"] for o in te]
        else:
            g = GradientBoostingRegressor(n_estimators=200, max_depth=2, learning_rate=0.05, random_state=0)
            g.fit(np.array([_vec(o, drop) for o in tr]), np.array([o["y"] for o in tr]))
            s = g.predict(np.array([_vec(o, drop) for o in te]))
        S += list(s); Y += [o["y"] for o in te]; CL += [held] * len(te); CA += [o["canon"] for o in te]
    return np.array(S), np.array(Y), CL, CA


BOOT_SEED = 0          # FIX C: pinned bootstrap seed  -> CIs reproducible run-to-run
N_BOOT = 2000          # FIX C: pinned resample count   -> CIs reproducible run-to-run


def _cluster_boot_ci(S, Y, CL, CA, n_boot=N_BOOT):
    """Mean-per-class Spearman, bootstrap over CONSTRUCT CLUSTERS (canon) within each class.

    FIX C (reviewer B): the CI was irreproducible across runs ([-0.01,0.51] vs [-0.012,0.527]) because the
    resampled-cluster array was built as `list({...})` — a set whose iteration order varies with Python's
    per-process hash randomization (PYTHONHASHSEED), so rng.choice drew from a differently-ordered array
    each run despite the fixed rng seed. Sorting the canon list makes the resample order deterministic, so
    (BOOT_SEED, N_BOOT) now fully pin the CI."""
    rng = np.random.default_rng(BOOT_SEED)
    by_cls = {}
    for i, c in enumerate(CL):
        by_cls.setdefault(c, []).append(i)
    vals = []
    for _ in range(n_boot):
        rhos = []
        for c, idx in by_cls.items():
            canons = sorted({CA[i] for i in idx})   # FIX C: deterministic order (was list({...}))
            if len(canons) < 2:
                continue
            pick = rng.choice(canons, len(canons), replace=True)
            sel = [i for i in idx if CA[i] in pick]  # include all obs of picked clusters
            if len(set(Y[sel])) < 2:
                continue
            rho = spearmanr(S[sel], Y[sel]).correlation
            if not np.isnan(rho):
                rhos.append(rho)
        if rhos:
            vals.append(np.mean(rhos))
    if not vals:
        return (float("nan"), float("nan"))
    return (round(float(np.percentile(vals, 2.5)), 3), round(float(np.percentile(vals, 97.5)), 3))


def _perm_p(S, Y, CL, n_perm=5000):
    obs_mpc = np.mean(list(_mpc(S, Y, CL).values()))
    rng = np.random.default_rng(0); ge = cnt = 0
    by = {}
    for i, c in enumerate(CL):
        by.setdefault(c, []).append(i)
    for _ in range(n_perm):
        Yp = Y.copy()
        for c, idx in by.items():
            Yp[idx] = rng.permutation(Y[idx])
        per = _mpc(S, Yp, CL)
        if per:
            cnt += 1
            if abs(np.mean(list(per.values()))) >= abs(obs_mpc):
                ge += 1
    return round(float(obs_mpc), 3), round((ge + 1) / (cnt + 1), 4)


def _level_summary(cache, aggregate):
    """Per-model {per_class, mean_per_class_common, ci95, perm_p} at one level.
    aggregate=False -> observation-level (current estimand); True -> construct-level (FIX B, median per
    construct before the within-class Spearman). 'common' = classes all 3 models can rank at this level."""
    out = {}
    agg_cache = {}
    for model, (S, Y, CL, CA) in cache.items():
        if aggregate:
            S, Y, CL, CA = _aggregate_constructs(S, Y, CL, CA)
        agg_cache[model] = (S, Y, CL, CA)
        per = _mpc(S, Y, CL)
        out[model] = {"per_class": {k: round(v, 3) for k, v in per.items()}}
    common = set.intersection(*[set(out[m]["per_class"]) for m in out]) if out else set()
    for model in out:
        S, Y, CL, CA = agg_cache[model]
        keep = np.array([c in common for c in CL]) if len(CL) else np.array([], dtype=bool)
        Sc, Yc = S[keep], Y[keep]
        CLc = [CL[i] for i in range(len(CL)) if CL[i] in common]
        CAc = [CA[i] for i in range(len(CL)) if CL[i] in common]
        if len(set(CLc)) >= 1 and len(Sc) >= 3:
            mpc, p = _perm_p(Sc, Yc, CLc)
            lo, hi = _cluster_boot_ci(Sc, Yc, CLc, CAc)
        else:
            mpc, p, lo, hi = float("nan"), float("nan"), float("nan"), float("nan")
        out[model].update({"mean_per_class_common": mpc, "ci95": [lo, hi], "perm_p": p,
                           "n_points": int(len(S))})
    return {"common_classes": sorted(common), "results": out}


def cross_target():
    obs = mm.build_observations()
    cache = {}
    for model in ("mechanistic", "gbm", "net_charge"):
        cache[model] = _loto(obs, model)
    # n accounting
    _, _, anyCL, anyCA = cache["gbm"]
    n_constructs = len(set(anyCA))
    n_classes = len(set(anyCL))
    observation_level = _level_summary(cache, aggregate=False)   # current estimand (pseudo-replicated)
    construct_level = _level_summary(cache, aggregate=True)      # FIX B: one value per construct (median)
    return {"n_obs": len(obs), "n_constructs": n_constructs, "n_classes_in_loto": n_classes,
            "observation_level": observation_level, "construct_level": construct_level,
            # back-compat: top-level mirrors the OBSERVATION level (what the prior manuscript reported)
            "common_classes": observation_level["common_classes"], "results": observation_level["results"]}


def temporal(cutoff=2021):
    obs = [o for o in mm.build_observations() if o["year"]]
    tr = [o for o in obs if o["year"] <= cutoff]; te = [o for o in obs if o["year"] > cutoff]
    if len(tr) < 10 or len(te) < 5:
        return {"runnable": False, "n_train": len(tr), "n_test": len(te)}
    g = GradientBoostingRegressor(n_estimators=200, max_depth=2, learning_rate=0.05, random_state=0)
    g.fit(np.array([_vec(o) for o in tr]), np.array([o["y"] for o in tr]))
    pred = g.predict(np.array([_vec(o) for o in te])); y = np.array([o["y"] for o in te])
    rho = spearmanr(pred, y).correlation
    # per-class on test
    per = _mpc(pred, y, [o["cls"] for o in te])
    return {"runnable": True, "cutoff": cutoff, "n_train": len(tr), "n_test": len(te),
            "pooled_spearman": round(float(rho), 3), "per_class": {k: round(v, 3) for k, v in per.items()}}


def _seq_clusters(obs, kmer=3, jac=0.5):
    """Single-linkage cluster constructs by sequence 3-mer Jaccard >= jac (leakage control: RGD motifs
    are shared across avb3/avb6, so target-out alone leaves sequence overlap). Small molecules / null-seq
    cluster by chemotype. Returns {canon: cluster_id}."""
    import collections
    # one representative sequence per canon
    seq_of, chem_of = {}, {}
    rows = [json.loads(l) for l in open(mm.os.path.join(mm.HERE, "renal_seed_corpus.jsonl"))]
    for r in rows:
        c = mm.rs._canonical(r["construct_id"])
        s = r.get("sequence")
        if isinstance(s, str) and len(s) >= 2:
            seq_of.setdefault(c, s.upper())
        chem_of.setdefault(c, r.get("chemotype") or "?")
    canons = sorted({o["canon"] for o in obs})

    def kmers(s):
        return {s[i:i+kmer] for i in range(len(s)-kmer+1)} if s and len(s) >= kmer else set()
    parent = {c: c for c in canons}
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x
    def union(a, b):
        parent[find(a)] = find(b)
    for i, a in enumerate(canons):
        ka = kmers(seq_of.get(a, ""))
        for b in canons[i+1:]:
            if a in seq_of and b in seq_of:
                kb = kmers(seq_of[b])
                if ka and kb and len(ka & kb) / len(ka | kb) >= jac:
                    union(a, b)
            elif a not in seq_of and b not in seq_of and chem_of.get(a) == chem_of.get(b):
                union(a, b)   # small molecules / null-seq: cluster by chemotype
    return {c: find(c) for c in canons}


def seq_cluster_cv():
    """Leave-one-sequence-cluster-out: pooled Spearman (model vs net-charge) with clusters held out
    whole — stricter leakage control than target-out where motifs are shared across targets."""
    obs = mm.build_observations()
    cl = _seq_clusters(obs)
    for o in obs:
        o["clu"] = cl.get(o["canon"], o["canon"])
    clusters = [c for c, n in collections.Counter(o["clu"] for o in obs).items()
                if sum(1 for o in obs if o["clu"] == c) >= 2]
    g_s, nc_s, Y = [], [], []
    for held in clusters:
        tr = [o for o in obs if o["clu"] != held]; te = [o for o in obs if o["clu"] == held]
        if len(tr) < 10 or len(te) < 2:
            continue
        g = GradientBoostingRegressor(n_estimators=200, max_depth=2, learning_rate=0.05, random_state=0)
        g.fit(np.array([_vec(o) for o in tr]), np.array([o["y"] for o in tr]))
        g_s += list(g.predict(np.array([_vec(o) for o in te])))
        nc_s += [o["q_pos"] - o["q_neg"] for o in te]; Y += [o["y"] for o in te]
    Y = np.array(Y)
    n_clusters_total = len(set(cl.values()))
    return {"n_clusters_total": n_clusters_total, "n_held_clusters": len(clusters), "n_test_pooled": len(Y),
            "gbm_pooled_spearman": round(float(spearmanr(g_s, Y).correlation), 3) if len(Y) > 3 else None,
            "netcharge_pooled_spearman": round(float(spearmanr(nc_s, Y).correlation), 3) if len(Y) > 3 else None}


def ablations():
    obs = mm.build_observations()
    base_S, base_Y, base_CL, base_CA = _loto(obs, "gbm")
    base = np.mean(list(_mpc(base_S, base_Y, base_CL).values()))
    rows = {"full": round(float(base), 3)}
    for name, drop in [("drop_charge", ("q_pos", "q_neg")), ("drop_timepoint", ("log_t",)),
                       ("drop_residual+albumin", ("residual", "alb")), ("drop_modality", ("is_sm",)),
                       ("drop_cleavable", ("cleave",))]:
        S, Y, CL, CA = _loto(obs, "gbm", drop=drop)
        per = _mpc(S, Y, CL)
        common = set(per) & set(_mpc(base_S, base_Y, base_CL))
        rows[name] = round(float(np.mean([per[c] for c in common])), 3) if common else float("nan")
    return rows


def _fmt_pc(d):
    return "{" + ", ".join(f"{k}:{v:+.3f}" for k, v in sorted(d.items())) + "}"


if __name__ == "__main__":
    print("=== MANUSCRIPT RESULTS (reproducible, seeded) ===\n")
    ct = cross_target()
    print(f"[Cross-target LOTO]  observations={ct['n_obs']}  constructs={ct['n_constructs']}  "
          f"classes_in_loto={ct['n_classes_in_loto']}")
    for level_name, level_key in (("OBSERVATION-LEVEL (pseudo-replicated; prior estimand)", "observation_level"),
                                  ("CONSTRUCT-LEVEL (median per construct; FIX B primary)", "construct_level")):
        lv = ct[level_key]
        print(f"\n  {level_name}  common classes={lv['common_classes']}")
        for m in ("mechanistic", "gbm", "net_charge"):
            r = lv["results"][m]
            ci = r["ci95"]
            print(f"    {m:12s} mean-per-class={r['mean_per_class_common']:+.3f}  "
                  f"95%CI[{ci[0]:+.3f},{ci[1]:+.3f}]  perm_p={r['perm_p']}  n={r['n_points']}")
        print(f"    per-class (gbm):        {_fmt_pc(lv['results']['gbm']['per_class'])}")
        print(f"    per-class (net_charge): {_fmt_pc(lv['results']['net_charge']['per_class'])}")
        print(f"    per-class (mechanistic):{_fmt_pc(lv['results']['mechanistic']['per_class'])}")
    print()
    for cut in (2018, 2021):
        t = temporal(cut)
        if t["runnable"]:
            print(f"[Temporal cut {cut}] train={t['n_train']} test={t['n_test']}  pooled rho={t['pooled_spearman']}  per-class={t['per_class']}")
        else:
            print(f"[Temporal cut {cut}] not runnable (train={t['n_train']} test={t['n_test']})")
    print()
    sc = seq_cluster_cv()
    print(f"[Sequence-cluster-disjoint CV] {sc['n_clusters_total']} clusters; held {sc['n_held_clusters']} "
          f"(test n={sc['n_test_pooled']}): GBM pooled rho={sc['gbm_pooled_spearman']} vs net-charge {sc['netcharge_pooled_spearman']}")
    print()
    ab = ablations()
    print(f"[Ablations — GBM LOTO mean-per-class]  full={ab['full']}")
    for k, v in ab.items():
        if k != "full":
            print(f"  {k:22s} {v:+.3f}  (Delta={v-ab['full']:+.3f})")
