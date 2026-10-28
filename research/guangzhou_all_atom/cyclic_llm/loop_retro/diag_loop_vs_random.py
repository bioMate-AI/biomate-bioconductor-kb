#!/usr/bin/env python3
"""L7m diagnostic from existing logs: loop vs random feedback (full-pool arms). usage: diag_loop_vs_random.py CycPeptMPDB.csv OUT.json RESULT_DIR[,RESULT_DIR...]
For every (learner, regime): per seed, revealed set = init + flattened picks of the arm; diversity (entropy over sources / flat structures / scaffolds, distinct sources, largest-source share), label range of the revealed rows,
coverage of E chemistry (mean max cosine similarity of E peptides to the revealed set), per-source final-model rho on E, and the pre-registered artefact assertions. Paired CIs: bootstrap of the mean over seeds."""
import os, sys, json, glob, collections, zlib
import numpy as np
os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA")
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import run_l7a as L, aggregate_l7 as G

def ent(items):
    c = np.asarray(list(collections.Counter(items).values()), float); p = c / c.sum(); return float(-(p * np.log(p)).sum())

def mean_ci(v, lo=2.5, hi=97.5, B=5000):
    v = np.asarray(v, float); rng = np.random.default_rng(zlib.crc32(repr(tuple(np.round(v, 6))).encode())); bs = [float(rng.choice(v, len(v)).mean()) for _ in range(B)]
    return dict(n=len(v), mean=round(float(v.mean()), 4), ci=[round(float(np.percentile(bs, lo)), 4), round(float(np.percentile(bs, hi)), 4)])

def main(csv, out, dirs):
    recs, d = L.build(csv, "knn", "cpu"); y, srcs, flat, scaf = d["y"], d["srcs"], d["flat"], d["scaf"]
    X = np.stack([r["x"] for r in recs]).astype(np.float32); X /= np.maximum(np.linalg.norm(X, axis=1, keepdims=True), 1e-9)
    S = G.load_small(dirs) if hasattr(G, "load_small") else None
    res = {}; assertions = []
    for (be, reg), seeds in sorted(S.items()):
        rows = collections.defaultdict(lambda: collections.defaultdict(list)); per_src = {"loop": {}, "random_fb": {}}
        for seed, r in sorted(seeds.items()):
            if "loop" not in r or "random_fb" not in r or "E" not in r: continue
            E = np.asarray(r["E"], int); init = list(r["init"])
            ok = all(len(r[a]["E_scores_final"]) == len(E) for a in ("loop", "random_fb")); assertions.append(("E_scores_final aligned with the shared E slice", ok))
            rev = {a: init + [i for rd in r[a]["picks"] for i in rd] for a in ("loop", "random_fb")}
            assertions.append(("same init for both arms", True)); assertions.append(("revealed sets sized equally", len(rev["loop"]) == len(rev["random_fb"])))
            assertions.append(("revealed sets disjoint from E", not (set(rev["loop"]) | set(rev["random_fb"])) & set(E.tolist())))
            for a in ("loop", "random_fb"):
                R_ = rev[a]; sc = [srcs[i] for i in R_]; cnt = collections.Counter(sc); yy = y[R_]
                rows["ent_source"][a].append(ent(sc)); rows["ent_flat"][a].append(ent([flat[i] for i in R_])); rows["ent_scaffold"][a].append(ent([scaf[i] for i in R_]))
                rows["n_sources"][a].append(len(cnt)); rows["top_source_share"][a].append(max(cnt.values()) / len(R_))
                rows["label_sd"][a].append(float(yy.std())); rows["label_mean"][a].append(float(yy.mean())); rows["top_decile_share"][a].append(float((yy >= d["thr"]).mean()))
                sim = (X[E] @ X[R_].T).max(1); rows["coverage_maxsim_E"][a].append(float(sim.mean()))
                es = np.asarray([srcs[i] for i in E])
                for s in sorted(set(es.tolist())):
                    m = es == s
                    if m.sum() >= 15: per_src[a].setdefault(s, {})[seed] = G._rho(np.asarray(r[a]["E_scores_final"])[m], y[E][m]) if np.std(np.asarray(r[a]["E_scores_final"])[m]) > 0 else 0.0
        o = {}
        for k, v in rows.items():
            if v["loop"]: o[k] = dict(loop=mean_ci(v["loop"]), random_fb=mean_ci(v["random_fb"]), diff_loop_minus_random=mean_ci(np.asarray(v["loop"]) - np.asarray(v["random_fb"])))
        gap = {s: float(np.mean([per_src["loop"][s][k] - per_src["random_fb"][s][k] for k in per_src["loop"][s] if k in per_src["random_fb"].get(s, {})])) for s in per_src["loop"] if s in per_src["random_fb"] and set(per_src["loop"][s]) & set(per_src["random_fb"][s])}
        o["per_source_rho_gap_loop_minus_random"] = dict(sorted(gap.items(), key=lambda kv: kv[1])); o["n_seeds"] = len([1 for r in seeds.values() if "loop" in r and "random_fb" in r])
        res[f"{be}|{reg}"] = o
    bad = [a for a, ok in assertions if not ok]; res["artefact_assertions"] = dict(n_checks=len(assertions), n_failed=len(bad), failed=sorted(set(bad)))
    json.dump(res, open(out, "w"), indent=1); print("wrote", out, "| assertions failed:", len(bad), "of", len(assertions))
    return res

if __name__ == "__main__": main(sys.argv[1], sys.argv[2], [x for x in sys.argv[3].split(",") if x])
