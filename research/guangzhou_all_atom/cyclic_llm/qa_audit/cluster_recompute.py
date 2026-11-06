"""T-QA: source-cluster contrast (loop_sub - frozen_sub, E source-rho) for regime L, aware vs blind, from raw files. Own rank-correlation + own cluster bootstrap (seed 777, B=20000)."""
import os, sys, json, glob, numpy as np
from scipy.stats import spearmanr
os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA")
LR = os.path.join(os.path.dirname(__file__), "..", "loop_retro"); sys.path.insert(0, LR)
import run_l7a as L7
csv = os.path.join(os.path.dirname(__file__), "..", "..", "data", "raw", "CycPeptMPDB_Peptide_All.csv")
recs, d = L7.build(csv, "knn", "cpu"); y, srcs = np.asarray(d["y"]), d["srcs"]
def tab(dirn, arm):
    t = {}
    for f in sorted(glob.glob(f"{LR}/results/l7_collect/small/{dirn}/gbm_L_*.json")):
        r = json.load(open(f)); rec = r.get(arm)
        if not rec or "E_scores_final" not in rec: continue
        E = np.asarray(r["E"], int); sc = np.asarray(rec["E_scores_final"], float); so = np.asarray([srcs[i] for i in E])
        for s in sorted(set(so)):
            m = so == s
            if m.sum() >= 15 and np.isfinite(sc[m]).all():
                t.setdefault(s, {})[r["seed"]] = 0.0 if (np.std(sc[m]) == 0 or np.std(y[E][m]) == 0) else float(spearmanr(sc[m], y[E][m])[0])
    return t
for dirn in ("res7f_gbm_aware", "res7f_gbm_blind"):
    for a, b in (("loop_sub", "frozen_sub"), ("loop_sub", "shuffled_sub"), ("loop_kphys_sub", "loop_kshuf_sub")):
        ta, tb = tab(dirn, a), tab(dirn, b); per = []
        for s in sorted(set(ta) & set(tb)):
            dd = [ta[s][k] - tb[s][k] for k in sorted(set(ta[s]) & set(tb[s]))]
            if len(dd) >= 3: per.append(np.mean(dd))
        per = np.asarray(per); rng = np.random.default_rng(777); bs = [rng.choice(per, len(per)).mean() for _ in range(20000)]
        print(f"{dirn} {a}-{b}: n_sources={len(per)} mean {per.mean():+.3f} [{np.percentile(bs,2.5):+.3f}, {np.percentile(bs,97.5):+.3f}]")
