"""Stage 3: nested inner selection for every (repeat, outer fold). Reads fits/fit_r{r}_f{f}.npz (inner priors), scores the inner-validation targets (training families only, seeds 0-4, k in {3,5,10}) and writes results/configs/cfg_r{r}_f{f}.json.
usage: p5select.py R0 R1 [--jobs N] [--fits DIR]"""
import os, sys, json, argparse, numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p5common as C, p5score as S
ap = argparse.ArgumentParser(); ap.add_argument("r0", type=int); ap.add_argument("r1", type=int); ap.add_argument("--jobs", type=int, default=4); ap.add_argument("--fits", default=f"{C.RES}/fits"); A = ap.parse_args()
OUT = f"{C.RES}/configs"; os.makedirs(OUT, exist_ok=True)
_W = {}


def world():
    if "W" not in _W: _W["W"] = C.world(); _W["TC"] = {}
    return _W["W"], _W["TC"]


def unit(r, f):
    path = f"{OUT}/cfg_r{r}_f{f}.json"
    if os.path.exists(path): return path
    W, TCc = world(); fmap = C.assign_outer(W, r); outer_h = {fa for fa, k in fmap.items() if k == f}; imap = C.assign_inner(W, r, f, fmap)
    z = np.load(f"{A.fits}/fit_r{r}_f{f}.npz"); inner = z["inner"]; rec = []
    for j in range(C.N_INNER):
        hold = outer_h | {fa for fa, k in imap.items() if k == j}; sp = C.sigma_p(W, hold)
        for tk in W["elig"]:
            if W["fam"][tk] in outer_h or imap.get(W["fam"][tk]) != j: continue
            if tk not in TCc: TCc[tk] = S.TC(tk, W)
            rec += S.eval_target(TCc[tk], inner[j], sp, seeds=range(5), ks=S.KS_SEL, full=False)
    df = pd.DataFrame(rec, columns=S.COLS); sel, obj = S.select(df)
    json.dump(dict(r=r, f=f, sigma_p_outer=C.sigma_p(W, outer_h), n_inner_targets=int(df.target.nunique()), n_inner_families=int(df.family.nunique()), selected=sel,
                   selected_objective={k: obj[v] for k, v in sel.items()}), open(path, "w"), indent=1)
    return path


if __name__ == "__main__":
    from joblib import Parallel, delayed
    Parallel(n_jobs=A.jobs, backend="loky")(delayed(unit)(r, f) for r in range(A.r0, A.r1) for f in range(C.K_OUT)); print("select done")
