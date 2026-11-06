#!/usr/bin/env python3
"""Lab-cluster intervals for paper 1 (run on EC2 only).

usage: paper1_cluster.py CSV LADDER_DIR L7_SMALL_ROOT OUT_PREFIX
  CSV            CycPeptMPDB_Peptide_All.csv (same file the runs used)
  LADDER_DIR     directory with ladder_*.json task files (s3://.../ihlm_ladder/res/)
  L7_SMALL_ROOT  directory whose sub-directories are the res7[a-z]_* result prefixes (as collect_l7.sh builds them)
  OUT_PREFIX     writes OUT_PREFIX.json and OUT_PREFIX.md

Rulebook (docs/committee_raw/20261030c/audit_gates_data_criteria.md section D, rules 4-5): the unit of inference is the laboratory (source id).
  * Yield contrasts (hits over the rounds): cluster = POOL source of the picked compound. Per-pick source and hit flag are recomputed from the picks (indices) with the
    dataset (srcs, hit = y >= thr, exactly as run_l7a/ladder_core define them); every recomputed per-round hit count is asserted equal to the recorded one.
    Estimate = sum over sources of the per-source mean (over seeds) paired difference in hits (= the mean over seeds of the total difference).
    Primary interval: cluster t, S-1 df, applied to the per-source means and scaled by S (S = number of sources with a pick in either arm in any seed of the group).
    Secondary (labelled): cluster percentile bootstrap (sources resampled, S draws).
  * Held-out-ranking contrasts (E slice): cluster = held-out laboratory; per-lab metric (within-source Spearman for L7, per-lab AUROC for the ladder) paired difference,
    mean over the seeds in which the lab was evaluated (>= 3 seeds, >= 15 peptides per lab and seed), cluster t with n-1 df over laboratories (primary), percentile bootstrap (secondary).
  * Seed-level intervals recomputed with the same code for comparison (t over seeds; percentile bootstrap of the mean over seeds).
Effective n: S, the number of non-zero contributors, the top laboratory and its share, and the estimate without the top laboratory.
"""
import sys, os, json, glob, collections
import numpy as np
from scipy import stats
from scipy.stats import rankdata

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "loop_retro")); sys.path.insert(0, os.path.join(HERE, "..", "ihlm_ladder"))
os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA")
import run_l7a as L7
import aggregate_l7 as AG
import aggregate_ladder as AL

B_BOOT = 10000
MIN_N, MIN_SEEDS = 15, 3
RNG = np.random.default_rng(20261031)


def r3(x): return None if x is None else round(float(x), 3)
def rci(ci): return None if ci is None else [r3(ci[0]), r3(ci[1])]


def tci(x, scale=1.0):
    x = np.asarray(x, float); n = len(x)
    if n < 2: return None
    m, sd = x.mean(), x.std(ddof=1); h = stats.t.ppf(0.975, n - 1) * sd / np.sqrt(n)
    return [scale * (m - h), scale * (m + h)]


def pboot(x, scale=1.0, B=B_BOOT):
    x = np.asarray(x, float); n = len(x)
    if n < 2: return None
    bs = RNG.choice(x, (B, n), replace=True).mean(1)
    return [scale * np.percentile(bs, 2.5), scale * np.percentile(bs, 97.5)]


def src_hits(rec, srcs, hit):
    """Counter source -> hits over all rounds; flag whether the recomputed per-round hit counts equal the recorded ones."""
    c = collections.Counter(); ok = True
    for pk, h in zip(rec["picks"], rec["hits"]):
        hh = 0
        for i in pk:
            if hit[i]: c[srcs[i]] += 1; hh += 1
        ok = ok and (hh == h)
    return c, ok


def yield_cluster(tasks, getarm, a, b, srcs, hit):
    """tasks {seed: task record}; getarm(task, arm) -> arm record or None. Paired contrast a - b on hits, cluster = pool source."""
    deltas, tot, universe, mism, used = {}, [], set(), 0, 0
    for sd, t in sorted(tasks.items()):
        ra, rb = getarm(t, a), getarm(t, b)
        if ra is None or rb is None or "picks" not in ra or "picks" not in rb: continue
        ca, oka = src_hits(ra, srcs, hit); cb, okb = src_hits(rb, srcs, hit); mism += int(not oka) + int(not okb); used += 1
        d = collections.Counter(ca)
        for k, v in cb.items(): d[k] -= v
        deltas[sd] = d; universe |= set(ca) | set(cb); tot.append(sum(ca.values()) - sum(cb.values()))
    if used < 3 or not universe: return None
    S = len(universe); per = {s: float(np.mean([deltas[sd].get(s, 0) for sd in deltas])) for s in sorted(universe)}; x = np.array(list(per.values()))
    est = float(x.sum()); nz = [s for s, v in per.items() if abs(v) > 1e-12]
    top = max(per, key=lambda s: abs(per[s])) if per else None
    denom = float(np.abs(x).sum())
    return dict(n_seeds=used, estimate=r3(est), seed_t=rci(tci(tot)), seed_boot=rci(pboot(tot)), cluster_t=rci(tci(x, S)), cluster_boot=rci(pboot(x, S)),
                n_clusters=S, n_nonzero=len(nz), top_lab=top, top_share=r3(abs(per[top]) / denom) if (top and denom > 0) else None,
                est_without_top=r3(est - per[top]) if top else None, hit_recompute_mismatches=mism)


def auc(score, hit):
    hit = np.asarray(hit, bool); npos, nneg = int(hit.sum()), int((~hit).sum())
    if npos == 0 or nneg == 0: return float("nan")
    return float((rankdata(score)[hit].sum() - npos * (npos + 1) / 2) / (npos * nneg))


def lab_cluster(per_lab_seed):
    """per_lab_seed {lab: {seed: delta}} -> cluster summary + per-seed means across labs for the seed-level interval."""
    keep = {l: v for l, v in per_lab_seed.items() if len(v) >= MIN_SEEDS}
    if len(keep) < 2: return None
    m = {l: float(np.mean(list(v.values()))) for l, v in keep.items()}; x = np.array(list(m.values())); seeds = sorted({s for v in keep.values() for s in v})
    per_seed = [float(np.mean([v[s] for v in keep.values() if s in v])) for s in seeds]
    top = max(m, key=lambda l: abs(m[l])); denom = float(np.abs(x).sum()); sps = sorted(len(v) for v in keep.values())
    return dict(n_seeds=len(seeds), estimate=r3(x.mean()), seed_t=rci(tci(per_seed)), seed_boot=rci(pboot(per_seed)), cluster_t=rci(tci(x)), cluster_boot=rci(pboot(x)),
                n_clusters=len(x), n_nonzero=int(np.sum(np.abs(x) > 1e-12)), top_lab=top, top_share=r3(abs(m[top]) / denom) if denom > 0 else None,
                est_without_top=r3(np.mean([m[l] for l in m if l != top])) if len(m) > 1 else None, seeds_per_lab=[sps[0], sps[len(sps) // 2], sps[-1]])


def ladder_auc_cluster(tasks, a, b):
    pls = collections.defaultdict(dict)
    for sd, t in sorted(tasks.items()):
        ra, rb = t["arms"].get(a), t["arms"].get(b)
        if ra is None or rb is None or "E_score_final" not in ra or "E_score_final" not in rb: continue
        src = np.array(t["E_src"]); h = np.array(t["E_hit"], bool); sa = np.array(ra["E_score_final"], float); sb = np.array(rb["E_score_final"], float)
        for l in sorted(set(src.tolist())):
            m = src == l
            if m.sum() < MIN_N: continue
            d = auc(sa[m], h[m]) - auc(sb[m], h[m])
            if np.isfinite(d): pls[l][sd] = d
    return lab_cluster(pls)


def l7_rho_cluster(tasks, a, b, y, srcs):
    ta, tb = AG.source_rho_table(tasks, a, y, srcs, min_n=MIN_N), AG.source_rho_table(tasks, b, y, srcs, min_n=MIN_N)
    pls = {}
    for l in sorted(set(ta) & set(tb)):
        d = {s: ta[l][s] - tb[l][s] for s in set(ta[l]) & set(tb[l]) if np.isfinite(ta[l][s] - tb[l][s])}
        if d: pls[l] = d
    return lab_cluster(pls)


def main():
    csv, ladder_dir, l7root, outp = sys.argv[1:5]
    recs, d = L7.build(csv, "knn", "cpu"); y, thr, srcs = d["y"], d["thr"], d["srcs"]; hit = np.asarray(y) >= thr
    rows = []

    def add(analysis, group, regime, seedset, contrast, metric, res):
        if res is None: return
        rows.append(dict(analysis=analysis, group=group, regime=regime, seeds=seedset, contrast=contrast, metric=metric, **res))

    # ---- ladder
    lad = AL.load_dir(ladder_dir); T = collections.defaultdict(dict)
    for r in lad: T[(r["regime"], r["scheme"], r["k_anchor"])][r["seed"]] = r
    ladder_get = lambda t, arm: t["arms"].get(arm)
    pairs = [("R1", "R0"), ("R2", "R1"), ("R3", "R2"), ("R4", "R3"), ("R4", "gbm_aware"), ("R4", "knn"), ("R4", "gp"), ("R4", "rule_kphys"), ("R1", "R1_kshuf")]
    for reg in ("A", "B", "L"):
        full = T.get((reg, "zc", 5), {})
        for label, lo, hi in (("dev 0-9", 0, 9), ("conf 10-19", 10, 19)):
            tasks = {s: t for s, t in full.items() if lo <= s <= hi}
            if not tasks: continue
            for a, b in pairs:
                add("ladder", "ihlm_ladder zc k=5", reg, label, f"{a}-{b}", "yield (hits/500)", yield_cluster(tasks, ladder_get, a, b, srcs, hit))
                if (a, b) in pairs[:4]: add("ladder", "ihlm_ladder zc k=5", reg, label, f"{a}-{b}", "E-AUROC per lab", ladder_auc_cluster(tasks, a, b))

    # ---- L7
    small = AG.load_small(sorted(glob.glob(os.path.join(l7root, "*/"))))
    l7get = lambda t, arm: t.get(arm) if isinstance(t.get(arm), dict) and "hits" in t.get(arm) else None
    cl = [("loop_sub", "frozen_sub"), ("loop", "frozen"), ("loop", "random_fb"), ("loop_kphys_sub", "loop_kshuf_sub"), ("loop_kphys_sub", "loop_sub"), ("loop_sub", "shuffled_sub")]
    for (learner, reg), tasks in sorted(small.items()):
        if learner.startswith(("atom", "chemberta")) and len(tasks) < 8: continue
        det = "_detK" in learner
        for a, b in cl:
            if "kshuf" in a + b and not det: continue                      # old K_shuf depended on PYTHONHASHSEED: not used for K_phys-vs-shuffled
            add("L7", learner, reg, f"seeds {min(tasks)}-{max(tasks)} (n={len(tasks)})", f"{a}-{b}", "yield (hits)", yield_cluster(tasks, l7get, a, b, srcs, hit))
            if any(l7get(t, a) and "E_scores_final" in l7get(t, a) for t in tasks.values()) and "random_fb" not in b:
                add("L7", learner, reg, f"seeds {min(tasks)}-{max(tasks)} (n={len(tasks)})", f"{a}-{b}", "E source-rho (within lab)", l7_rho_cluster(tasks, a, b, np.asarray(y), srcs))
    out = dict(script="paper1_cluster.py", n_ladder_files=len(lad), n_l7_groups=len(small), thr=float(thr), rows=rows,
               hit_recompute_mismatches_total=int(sum(r.get("hit_recompute_mismatches", 0) or 0 for r in rows)))
    json.dump(out, open(outp + ".json", "w"), indent=1)
    with open(outp + ".md", "w") as f:
        f.write("| analysis | group | regime | seeds | contrast | metric | n seeds | estimate | seed t 95% | seed boot 95% | cluster t 95% (n-1 df, primary) | cluster boot 95% (secondary) | clusters (non-zero) | top lab (share) | est. without top lab |\n|" + "---|" * 15 + "\n")
        for r in rows:
            f.write(f"| {r['analysis']} | {r['group']} | {r['regime']} | {r['seeds']} | {r['contrast']} | {r['metric']} | {r['n_seeds']} | {r['estimate']} | {r['seed_t']} | {r['seed_boot']} | {r['cluster_t']} | {r['cluster_boot']} | {r['n_clusters']} ({r['n_nonzero']}) | {r['top_lab']} ({r['top_share']}) | {r['est_without_top']} |\n")
    print("rows", len(rows), "mismatches", out["hit_recompute_mismatches_total"], flush=True)


if __name__ == "__main__":
    main()
