#!/usr/bin/env python3
"""Aggregate the L7 model-comparison replay (PREREG_LOOP.md L7a-L7f) into results/l7_aggregate.json.
usage: aggregate_l7.py OUT.json --small DIR[,DIR...] [--llm DIR] [--rounds-llm 5]
Reads <backend>_<regime>_<seed>.json (small models) and <model>__<regime>_<seed>.json (large LLMs). Every contrast is PAIRED by (regime, seed); intervals are percentile bootstraps over seeds (B = 5000);
n is always reported. Nothing is pooled across regimes. Claims follow the pre-registered rules only; contrasts with fewer than 8 paired sequences are labelled `inconclusive (power)`."""
import sys, os, json, glob, re, collections, argparse
import numpy as np

B_BOOT = 5000


def _seed(v, lo, hi):
    import zlib
    return zlib.crc32(repr((len(v), tuple(round(float(x), 6) for x in v), lo, hi)).encode())          # seed derived from the data and the level -> identical output on every regeneration, independent of call order


def ci(v, lo=2.5, hi=97.5):
    """Percentile bootstrap CI of the MEAN over seeds (not a spread); deterministic per (data, level)."""
    v = np.asarray([x for x in v if x == x], float)
    if len(v) == 0: return None
    if len(v) == 1: return [float(v[0]), float(v[0])]
    rng = np.random.default_rng(_seed(v, lo, hi)); bs = [float(np.mean(rng.choice(v, len(v)))) for _ in range(B_BOOT)]
    return [round(float(np.percentile(bs, lo)), 4), round(float(np.percentile(bs, hi)), 4)]


def summ(v, lo=2.5, hi=97.5):
    v = [x for x in v if x == x]
    return dict(n=len(v), mean=round(float(np.mean(v)), 4) if v else None, ci=ci(v, lo, hi), ci_level_pct=round(hi - lo, 1))


# ------------------------------------------------------------------ source-cluster bootstrap (L7j (3)): the unit of resampling is the SOURCE (laboratory)
def _rank(x):
    from scipy.stats import rankdata
    return rankdata(x)


def _rho(a, b):
    a, b = _rank(a), _rank(b); a = a - a.mean(); b = b - b.mean(); d = float(np.sqrt((a * a).sum() * (b * b).sum())); return float((a * b).sum() / d) if d > 0 else 0.0


def source_rho_table(task_results, arm, y, srcs, min_n=15):
    """{source: {seed: within-source Spearman(score, y) over that source's E peptides}} for one arm; E indices and final E scores are read from each task result."""
    tab = {}
    for seed, r in task_results.items():
        rec = r.get(arm)
        if not rec or "E_scores_final" not in rec or "E" not in r: continue
        E = np.asarray(r["E"], int); sc = np.asarray(rec["E_scores_final"], float); s_of = np.asarray([srcs[i] for i in E])
        for s in sorted(set(s_of.tolist())):
            m = s_of == s
            if m.sum() >= min_n and np.all(np.isfinite(sc[m])) and np.std(sc[m]) > 0 and np.std(y[E][m]) > 0: tab.setdefault(s, {})[seed] = _rho(sc[m], y[E][m])
            elif m.sum() >= min_n and not np.all(np.isfinite(sc[m])): continue                                       # non-finite scores: this (source, seed) is missing, not 0
            elif m.sum() >= min_n: tab.setdefault(s, {})[seed] = 0.0                                            # constant score within a source counts as rho = 0 (ties)
    return tab


def cluster_contrast(tab_a, tab_b, min_seeds=3, B=B_BOOT, lo=2.5, hi=97.5):
    """Paired contrast arm A minus arm B on the within-source rho. POINT ESTIMATE = mean over sources of the per-source mean (over the seeds in which that source was held out/evaluated).
    ci_cluster: sources resampled with replacement (the interval to cite). ci_seed_only: seeds resampled with replacement, sources fixed, with the SAME statistic recomputed on each resample
    (per-source mean over the resampled seeds in which the source appears, then mean over sources) -- an interval for the reported mean even when sources are present in only some seeds."""
    d = {}
    for s in sorted(set(tab_a) & set(tab_b)):                     # sorted: set iteration order of strings varies between processes (hash randomisation) and would change the resampling
        common = sorted(set(tab_a[s]) & set(tab_b[s]))
        dd = {k: tab_a[s][k] - tab_b[s][k] for k in common}; dd = {k: v for k, v in dd.items() if np.isfinite(v)}        # NaN guard (committee 2): a non-finite per-seed value is dropped, never propagated into a mean or a bootstrap
        if len(dd) >= min_seeds: d[s] = dd
    if len(d) < 2: return dict(n_sources=len(d), mean=None, ci_cluster=None, ci_seed_only=None, interval_type="insufficient clusters")
    per_src = np.asarray([np.mean(list(v.values())) for v in d.values()], float); srcs_sorted = sorted(d)
    rng = np.random.default_rng(_seed(per_src, lo, hi)); bs = [float(rng.choice(per_src, len(per_src)).mean()) for _ in range(B)]
    seeds_all = sorted({k for v in d.values() for k in v}); rng2 = np.random.default_rng(_seed(per_src, lo, hi) + 1); bs2 = []
    for _ in range(B):
        draw = rng2.choice(len(seeds_all), len(seeds_all)); cnt = np.bincount(draw, minlength=len(seeds_all)); w = dict(zip(seeds_all, cnt)); vals = []
        for s in srcs_sorted:
            den = sum(w[k] for k in d[s]); 
            if den > 0: vals.append(sum(w[k] * x for k, x in d[s].items()) / den)
        bs2.append(float(np.mean(vals)))
    r4 = lambda x: round(float(x), 4)
    return dict(n_sources=len(d), n_seeds=len(seeds_all), mean=r4(per_src.mean()), ci_cluster=[r4(np.percentile(bs, lo)), r4(np.percentile(bs, hi))], ci_seed_only=[r4(np.percentile(bs2, lo)), r4(np.percentile(bs2, hi))],
                interval_type="bootstrap CI of the mean over SOURCES (cluster); ci_seed_only = bootstrap over seeds, sources fixed, same statistic recomputed", ci_level_pct=round(hi - lo, 1))


def learner_key(dirpath, r):
    """Learner label for a result file. The `backend` field alone is NOT unique: the chirality-aware and stereo-blind GBM runs both write backend 'gbm' (found by the 2026-10-30 code review: the blind runs
    silently overwrote the aware ones). The learner is therefore taken from the field `learner` when present (new runs), else derived from the DIRECTORY NAME:
      *blind* -> <backend>_blind;  *confirm* -> <backend>_aware_confirm (confirmatory seeds, kept apart from the development seeds);  *res7m_* -> <backend>_aware_srcmatch (diagnostic re-runs of loop/random_fb);
      any other plain 'gbm' -> gbm_aware; every other backend keeps its own name (gbm_physchem, atom_lm, chemberta, ...)."""
    if r.get("learner"): return r["learner"]
    b = r["backend"]; name = os.path.basename(os.path.normpath(dirpath)).lower()
    if b == "gbm_physchem" and "confirm" not in name and "res7m_" not in name and "res7q_" not in name: return b
    suffix = "_confirm" if "confirm" in name else ("_srcmatch" if "res7m_" in name else "")
    if "res7q_" in name: suffix = "_detK" + suffix                      # deterministic-K_shuf re-runs of the knowledge arms (2026-10-30); kept apart from the original runs, whose K_shuf depended on PYTHONHASHSEED
    if b in ("gbm",): return ("gbm_blind" if "blind" in name else "gbm_aware") + suffix
    return b + suffix


def load_small(dirs, manifest=None):
    """{(learner, regime): {seed: result}}. Two files for the same (learner, regime, seed) are merged ONLY if their arm sets are disjoint (arm-filtered runs of one task); overlapping arms raise ValueError
    (no silent overwrite). `manifest` (optional list) receives (file, key) for every file read, so a test can assert that every input is accounted for exactly once."""
    R = collections.defaultdict(dict)
    for d in dirs:
        for f in sorted(glob.glob(f"{d}/*.json")):
            try: r = json.load(open(f))
            except Exception: continue
            if "backend" not in r: continue
            key = (learner_key(d, r), r["regime"]); cur = R[key].get(r["seed"])
            if cur is not None:
                arms_new = {k for k, v in r.items() if isinstance(v, dict) and "hits" in v}; arms_old = {k for k, v in cur.items() if isinstance(v, dict) and "hits" in v}
                if arms_new & arms_old: raise ValueError(f"result collision for {key} seed {r['seed']}: {f} repeats arms {sorted(arms_new & arms_old)[:3]} already loaded")
                cur.update(r)
            else: R[key][r["seed"]] = dict(r)
            if manifest is not None: manifest.append((f, key))
    return R


def load_llm(d):
    R = collections.defaultdict(dict)
    for f in glob.glob(f"{d}/*__*_*.json"):
        if f.endswith(("__control.json", "__probe.json")): continue
        try: r = json.load(open(f))
        except Exception: continue
        if "regime" in r: R[(r["model"], r["regime"])][r["seed"]] = r
    return R


def hits(rec, n=None): return float(sum(rec["hits"][:n])) if rec and rec.get("hits") else float("nan")


def paired(R, key, a, b, fn):
    """fn(rec_a, rec_b) per seed where both exist."""
    return [fn(R[key][s][a], R[key][s][b]) for s in sorted(R[key]) if a in R[key][s] and b in R[key][s]]


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("out"); ap.add_argument("--small", default=""); ap.add_argument("--llm", default=""); ap.add_argument("--rounds-llm", type=int, default=5); ap.add_argument("--csv", default="")
    a = ap.parse_args(); out = dict(version="L7 aggregate", note="paired by (regime, seed); percentile bootstrap over seeds; regimes never pooled; PAMPA permeability of cyclic peptides only", small={}, llm={}, controls={}, noninferiority={})
    manifest = []; S = load_small([d for d in a.small.split(",") if d], manifest); Lm = load_llm(a.llm) if a.llm else {}
    for (be, reg), seeds in sorted(S.items()):
        key = (be, reg); R = {key: seeds}; arms = sorted({k for r in seeds.values() for k, v in r.items() if isinstance(v, dict) and "hits" in v})
        o = dict(n_seeds=len(seeds), yield_total={}, yield_5rounds={}, E_auroc_gain={}, E_ef5_gain={}, stereo={}, contrasts={}, controls={})
        for arm in arms:
            o["yield_total"][arm] = summ([hits(r[arm]) for r in seeds.values() if arm in r]); o["yield_5rounds"][arm] = summ([hits(r[arm], 5) for r in seeds.values() if arm in r])
            g = [r[arm]["auroc_E"][-1] - r[arm]["auroc_E0"] for r in seeds.values() if arm in r and r[arm].get("auroc_E")]; o["E_auroc_gain"][arm] = summ(g)
            g2 = [r[arm]["ef5_E"][-1] - r[arm]["ef5_E0"] for r in seeds.values() if arm in r and r[arm].get("ef5_E")]; o["E_ef5_gain"][arm] = summ(g2)
            st = [r[arm]["stereo_rho"][-1] for r in seeds.values() if arm in r and r[arm].get("stereo_rho")]
            # runs made before the 2026-10-29 fix (no `picked_final` key) fed mismatched label/index arrays into the SAR update of FROZEN arms: that single field is invalid there and excluded
            sar = [r[arm]["stereo_rho_sar"] for r in seeds.values() if arm in r and r[arm].get("stereo_rho_sar") is not None and not (arm.startswith("frozen") and "picked_final" not in r[arm])]
            o["stereo"][arm] = dict(zero_sibling=summ(st), sar=summ(sar))
        def contrast(name, x, y_, field="yield"):
            if field == "yield": d = paired(R, key, x, y_, lambda p, q: hits(p) - hits(q))
            else: d = paired(R, key, x, y_, lambda p, q: (p["auroc_E"][-1] - p["auroc_E0"]) - (q["auroc_E"][-1] - q["auroc_E0"]))
            o["contrasts"][f"{name} [{field}]"] = summ(d, 0.5, 99.5) if "kphys" in name or "kn" in name else summ(d)
        for nm, x, y_ in (("loop - random_fb", "loop", "random_fb"), ("loop - frozen", "loop", "frozen"), ("loop - shuffled", "loop", "shuffled"), ("loop_sub - frozen_sub", "loop_sub", "frozen_sub"),
                          ("loop_sub - shuffled_sub", "loop_sub", "shuffled_sub"), ("loop_kphys_sub - loop_sub", "loop_kphys_sub", "loop_sub"), ("loop_kphys_contra_sub - loop_sub", "loop_kphys_contra_sub", "loop_sub"),
                          ("loop_kshuf_sub - loop_sub", "loop_kshuf_sub", "loop_sub"), ("loop_kphys_sub - loop_kshuf_sub", "loop_kphys_sub", "loop_kshuf_sub"), ("loop_kn_sub - loop_sub", "loop_kn_sub", "loop_sub"), ("noisy_sub - shuffled_sub", "noisy_sub", "shuffled_sub")):
            contrast(nm, x, y_)
        for nm, x, y_ in (("loop - one_shot", "loop", "one_shot"), ("loop - random_fb", "loop", "random_fb"), ("loop_sub - shuffled_sub", "loop_sub", "shuffled_sub"), ("loop_kphys_sub - loop_sub", "loop_kphys_sub", "loop_sub"), ("loop_kphys_sub - loop_kshuf_sub", "loop_kphys_sub", "loop_kshuf_sub")):
            contrast(nm, x, y_, "E_auroc_gain")
        # pre-registered controls: shuffled / frozen must not improve on E
        for arm in ("shuffled", "shuffled_sub", "frozen", "frozen_sub"):      # L7k: loop_kshuf_sub is a KNOWLEDGE control (judged by the paired contrast), not a shuffled-label arm
            if arm in o["E_auroc_gain"] and o["E_auroc_gain"][arm]["n"]:
                g = o["E_auroc_gain"][arm]; o["controls"][arm] = dict(auroc_E_gain=g, passes=bool(g["ci"] is not None and g["ci"][0] <= 0.0))
        o["claim_C1_loop_beats_random_feedback_yield"] = o["contrasts"].get("loop - random_fb [yield]"); o["status"] = "inconclusive (power)" if len(seeds) < 8 else "n>=8"
        out["small"][f"{be}|{reg}"] = o
    # source-cluster bootstrap of E-metric contrasts (needs the dataset for sources and labels)
    if a.csv:
        os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA"); sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import run_l7a as L7; recs_, d_ = L7.build(a.csv, "knn", "cpu"); y_, srcs_ = d_["y"], d_["srcs"]
        for (be, reg), seeds in sorted(S.items()):
            cl = {}
            for nm, x, y2 in (("loop - random_fb", "loop", "random_fb"), ("loop - one_shot", "loop", "one_shot"), ("loop_sub - shuffled_sub", "loop_sub", "shuffled_sub"), ("loop_sub - frozen_sub", "loop_sub", "frozen_sub"),
                              ("loop_kphys_sub - loop_sub", "loop_kphys_sub", "loop_sub"), ("loop_kphys_sub - loop_kshuf_sub", "loop_kphys_sub", "loop_kshuf_sub")):
                ta, tb = source_rho_table(seeds, x, y_, srcs_), source_rho_table(seeds, y2, y_, srcs_)
                if ta and tb: cl[f"{nm} [E source-rho]"] = cluster_contrast(ta, tb)
            if cl: out["small"][f"{be}|{reg}"]["contrasts_cluster"] = cl
    # large LLMs
    for (m, reg), seeds in sorted(Lm.items()):
        arms = sorted({k for r in seeds.values() for k, v in r.items() if isinstance(v, dict) and "hits" in v}); R = {(m, reg): seeds}; key = (m, reg); n = a.rounds_llm
        o = dict(n_seeds=len(seeds), yield_cum={}, contrasts={}, cost={}, stereo={}, ef_sub={})
        for arm in arms:
            o["yield_cum"][arm] = summ([hits(r[arm], n) for r in seeds.values() if arm in r]); o["ef_sub"][arm] = summ([np.mean(r[arm]["ef_sub"][:n]) for r in seeds.values() if arm in r])
            c = [r[arm]["cost"] for r in seeds.values() if arm in r and "cost" in r[arm]]
            if c: o["cost"][arm] = dict(usd=round(sum(x["usd"] for x in c), 4), tin=int(sum(x["tin"] for x in c)), tout=int(sum(x["tout"] for x in c)), calls=int(sum(x["calls"] for x in c)), wall_seconds=round(sum(x.get("wall_seconds", 0) for x in c), 1))
            st = [r[arm]["stereo"]["mean_rho"] for r in seeds.values() if arm in r and "stereo" in r[arm]]
            if st: o["stereo"][arm] = summ(st)
            o.setdefault("fills", {})[arm] = int(sum(r[arm].get("fills", 0) for r in seeds.values() if arm in r))
        for nm, x, y_ in (("llm_loop - llm_frozen", "llm_loop", "llm_frozen"), ("llm_loop - llm_zeroshot", "llm_loop", "llm_zeroshot"), ("llm_loop - llm_shuffled", "llm_loop", "llm_shuffled"), ("llm_kb - llm_loop", "llm_kb", "llm_loop"),
                          ("llm_loop - subset_random", "llm_loop", "subset_random"), ("llm_loop - subset_gbm", "llm_loop", "subset_gbm"), ("llm_kb - subset_gbm", "llm_kb", "subset_gbm")):
            o["contrasts"][nm] = summ(paired(R, key, x, y_, lambda p, q: hits(p, n) - hits(q, n)))
        o["status"] = "inconclusive (power)" if len(seeds) < 8 else "n>=8"; out["llm"][f"{m}|{reg}"] = o
    # non-inferiority / superiority: small loop+kb vs large llm_kb, paired by (regime, seed), cumulative hits at n LLM rounds
    for (be, reg), seeds in sorted(S.items()):
        for (m, reg2), lseeds in sorted(Lm.items()):
            if reg2 != reg: continue
            pairs = [(hits(seeds[s].get("loop_kphys_sub"), a.rounds_llm), hits(lseeds[s].get("llm_kb"), a.rounds_llm)) for s in sorted(set(seeds) & set(lseeds)) if "loop_kphys_sub" in seeds[s] and "llm_kb" in lseeds[s]]
            if not pairs: continue
            ratio = [p / q for p, q in pairs if q > 0]; diff = [p - q for p, q in pairs]
            r = summ(ratio); d = summ(diff); npair = len(pairs)
            out["noninferiority"][f"{be} loop+K_phys (sub protocol) vs {m} llm_kb | {reg}"] = dict(n_pairs=npair, ratio=r, diff=d, rule="non-inferior iff lower 95% bound of mean ratio > 0.90; superior iff lower bound of diff > 0; claims need >= 8 pairs per regime",
                non_inferior=bool(npair >= 8 and r["ci"] and r["ci"][0] > 0.90), superior=bool(npair >= 8 and d["ci"] and d["ci"][0] > 0), status="inconclusive (power)" if npair < 8 else "evaluable")
    import hashlib
    files = sorted([f for d in a.small.split(",") if d for f in glob.glob(f"{d}/*.json")] + (glob.glob(f"{a.llm}/*.json") if a.llm else []))
    out["inputs"] = dict(n_files=len(files), n_small_files_loaded=len(manifest), n_small_keys=len({k for _, k in manifest}), files_per_key={f"{k[0]}|{k[1]}": sum(1 for _, kk in manifest if kk == k) for k in sorted({k for _, k in manifest})}, sha256=hashlib.sha256("".join(f"{os.path.basename(f)}:{os.path.getsize(f)};" for f in sorted(files, key=os.path.basename)).encode()).hexdigest())
    json.dump(out, open(a.out, "w"), indent=1, default=float); print("wrote", a.out, "| small groups", len(out["small"]), "| llm groups", len(out["llm"]), "| noninferiority pairs", len(out["noninferiority"]))


if __name__ == "__main__":
    main()
