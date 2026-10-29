"""Stages 4/5: outer scoring with the frozen nested configurations.
usage: p5outer.py PASS R0 R1 [--jobs N]   PASS = A (baselines only: prior, nn, gp, d, fixed references) | B (H5, H5NN)   -> results/outer_{PASS}_r{r}.csv.gz
Learning-curve k: 0 (prior only), 1, 3, 5, 10, 25; seeds 0-9; full metrics (Spearman, NDCG@10, recall; all + hard)."""
import os, sys, json, argparse, numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p5common as C, p5score as S
ap = argparse.ArgumentParser(); ap.add_argument("passname", choices=["A", "B"]); ap.add_argument("r0", type=int); ap.add_argument("r1", type=int); ap.add_argument("--jobs", type=int, default=4); ap.add_argument("--fits", default=f"{C.RES}/fits"); A = ap.parse_args()
KS = (0, 1, 3, 5, 10, 25); ALIAS_A = ("prior", "nn", "gp", "d"); ALIAS_B = ("h5", "h5nn")
FIXED_A = ("nn_q3", "gp_2.25_0.25", "d_q6_l0.3")          # pilot 4's frozen reference settings


def unit(r, f):
    path = f"{C.RES}/outer_{A.passname}_r{r}_f{f}.csv.gz"
    if os.path.exists(path): return path
    W = C.world(); fmap = C.assign_outer(W, r); cfg = json.load(open(f"{C.RES}/configs/cfg_r{r}_f{f}.json")); sel = cfg["selected"]; sp = cfg["sigma_p_outer"]
    prior = np.load(f"{A.fits}/fit_r{r}_f{f}.npz")["outer"]
    names = {a: sel[a] for a in (ALIAS_A if A.passname == "A" else ALIAS_B) if a != "prior"}
    if A.passname == "A": names["prior"] = "prior"; names.update({n: n for n in FIXED_A})
    want = set(names.values()); rec = []
    for tk in W["elig"]:
        if fmap[W["fam"][tk]] != f: continue
        tc = S.TC(tk, W); rec += S.eval_target(tc, prior, sp, seeds=range(10), ks=KS, want=want, full=True)
    df = pd.DataFrame(rec, columns=S.COLS); inv = {}
    for a, n in names.items(): inv.setdefault(n, []).append(a)
    df = df.assign(alias=df.method.map(lambda m: ",".join(inv[m]))); df["repeat"] = r; df["fold"] = f
    df.to_csv(path, index=False); return path


if __name__ == "__main__":
    from joblib import Parallel, delayed
    Parallel(n_jobs=A.jobs, backend="loky")(delayed(unit)(r, f) for r in range(A.r0, A.r1) for f in range(C.K_OUT)); print("outer", A.passname, "done")
