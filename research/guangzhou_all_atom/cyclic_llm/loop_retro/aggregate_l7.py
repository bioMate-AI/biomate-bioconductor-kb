#!/usr/bin/env python3
"""Aggregate the L7 model-comparison replay (PREREG_LOOP.md L7a-L7f) into results/l7_aggregate.json.
usage: aggregate_l7.py OUT.json --small DIR[,DIR...] [--llm DIR] [--rounds-llm 5]
Reads <backend>_<regime>_<seed>.json (small models) and <model>__<regime>_<seed>.json (large LLMs). Every contrast is PAIRED by (regime, seed); intervals are percentile bootstraps over seeds (B = 5000);
n is always reported. Nothing is pooled across regimes. Claims follow the pre-registered rules only; contrasts with fewer than 8 paired sequences are labelled `inconclusive (power)`."""
import sys, os, json, glob, re, collections, argparse
import numpy as np

B_BOOT, RNG = 5000, np.random.default_rng(0)


def ci(v, lo=2.5, hi=97.5):
    v = np.asarray([x for x in v if x == x], float)
    if len(v) == 0: return None
    if len(v) == 1: return [float(v[0]), float(v[0])]
    bs = [float(np.mean(RNG.choice(v, len(v)))) for _ in range(B_BOOT)]; return [round(float(np.percentile(bs, lo)), 4), round(float(np.percentile(bs, hi)), 4)]


def summ(v, lo=2.5, hi=97.5):
    v = [x for x in v if x == x]
    return dict(n=len(v), mean=round(float(np.mean(v)), 4) if v else None, ci=ci(v, lo, hi))


def load_small(dirs):
    R = collections.defaultdict(dict)                                  # (backend, regime) -> seed -> result
    for d in dirs:
        for f in glob.glob(f"{d}/*.json"):
            try: r = json.load(open(f))
            except Exception: continue
            if "backend" not in r: continue
            tag = r["backend"]
            R[(tag, r["regime"])].setdefault(r["seed"], {}).update(r)   # merge result files of the same task (arm-filtered runs)
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
    ap = argparse.ArgumentParser(); ap.add_argument("out"); ap.add_argument("--small", default=""); ap.add_argument("--llm", default=""); ap.add_argument("--rounds-llm", type=int, default=5)
    a = ap.parse_args(); out = dict(version="L7 aggregate", note="paired by (regime, seed); percentile bootstrap over seeds; regimes never pooled; PAMPA permeability of cyclic peptides only", small={}, llm={}, controls={}, noninferiority={})
    S = load_small([d for d in a.small.split(",") if d]); Lm = load_llm(a.llm) if a.llm else {}
    for (be, reg), seeds in sorted(S.items()):
        key = (be, reg); R = {key: seeds}; arms = sorted({k for r in seeds.values() for k, v in r.items() if isinstance(v, dict) and "hits" in v})
        o = dict(n_seeds=len(seeds), yield_total={}, yield_5rounds={}, E_auroc_gain={}, E_ef5_gain={}, stereo={}, contrasts={}, controls={})
        for arm in arms:
            o["yield_total"][arm] = summ([hits(r[arm]) for r in seeds.values() if arm in r]); o["yield_5rounds"][arm] = summ([hits(r[arm], 5) for r in seeds.values() if arm in r])
            g = [r[arm]["auroc_E"][-1] - r[arm]["auroc_E0"] for r in seeds.values() if arm in r and r[arm].get("auroc_E")]; o["E_auroc_gain"][arm] = summ(g)
            g2 = [r[arm]["ef5_E"][-1] - r[arm]["ef5_E0"] for r in seeds.values() if arm in r and r[arm].get("ef5_E")]; o["E_ef5_gain"][arm] = summ(g2)
            st = [r[arm]["stereo_rho"][-1] for r in seeds.values() if arm in r and r[arm].get("stereo_rho")]; sar = [r[arm]["stereo_rho_sar"] for r in seeds.values() if arm in r and r[arm].get("stereo_rho_sar") is not None]
            o["stereo"][arm] = dict(zero_sibling=summ(st), sar=summ(sar))
        def contrast(name, x, y_, field="yield"):
            if field == "yield": d = paired(R, key, x, y_, lambda p, q: hits(p) - hits(q))
            else: d = paired(R, key, x, y_, lambda p, q: (p["auroc_E"][-1] - p["auroc_E0"]) - (q["auroc_E"][-1] - q["auroc_E0"]))
            o["contrasts"][f"{name} [{field}]"] = summ(d, 0.5, 99.5) if "kphys" in name or "kn" in name else summ(d)
        for nm, x, y_ in (("loop - random_fb", "loop", "random_fb"), ("loop - frozen", "loop", "frozen"), ("loop - shuffled", "loop", "shuffled"), ("loop_sub - frozen_sub", "loop_sub", "frozen_sub"),
                          ("loop_sub - shuffled_sub", "loop_sub", "shuffled_sub"), ("loop_kphys_sub - loop_sub", "loop_kphys_sub", "loop_sub"), ("loop_kphys_contra_sub - loop_sub", "loop_kphys_contra_sub", "loop_sub"),
                          ("loop_kshuf_sub - loop_sub", "loop_kshuf_sub", "loop_sub"), ("loop_kn_sub - loop_sub", "loop_kn_sub", "loop_sub"), ("noisy_sub - shuffled_sub", "noisy_sub", "shuffled_sub")):
            contrast(nm, x, y_)
        for nm, x, y_ in (("loop - one_shot", "loop", "one_shot"), ("loop - random_fb", "loop", "random_fb"), ("loop_sub - shuffled_sub", "loop_sub", "shuffled_sub"), ("loop_kphys_sub - loop_sub", "loop_kphys_sub", "loop_sub")):
            contrast(nm, x, y_, "E_auroc_gain")
        # pre-registered controls: shuffled / frozen must not improve on E
        for arm in ("shuffled", "shuffled_sub", "frozen", "frozen_sub", "loop_kshuf_sub"):
            if arm in o["E_auroc_gain"] and o["E_auroc_gain"][arm]["n"]:
                g = o["E_auroc_gain"][arm]; o["controls"][arm] = dict(auroc_E_gain=g, passes=bool(g["ci"] is not None and g["ci"][0] <= 0.0))
        o["claim_C1_loop_beats_random_feedback_yield"] = o["contrasts"].get("loop - random_fb [yield]"); o["status"] = "inconclusive (power)" if len(seeds) < 8 else "n>=8"
        out["small"][f"{be}|{reg}"] = o
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
    json.dump(out, open(a.out, "w"), indent=1, default=float); print("wrote", a.out, "| small groups", len(out["small"]), "| llm groups", len(out["llm"]), "| noninferiority pairs", len(out["noninferiority"]))


if __name__ == "__main__":
    main()
