"""Stage 6: controls C1 (planted series), C2 (shuffled potencies) on repeat 0 with that repeat's frozen configs and outer priors; C3 (prior at k = 0) is in the outer pass.
usage: p5controls.py [--jobs N]  -> results/controls.csv.gz, results/controls_summary.json"""
import os, sys, json, zlib, argparse, numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p5common as C, p5score as S
ap = argparse.ArgumentParser(); ap.add_argument("--jobs", type=int, default=4); ap.add_argument("--fits", default=f"{C.RES}/fits"); A = ap.parse_args()


def unit(f, r=0):
    W = C.world(); fmap = C.assign_outer(W, r); cfg = json.load(open(f"{C.RES}/configs/cfg_r{r}_f{f}.json")); sel = cfg["selected"]; sp = cfg["sigma_p_outer"]; prior = np.load(f"{A.fits}/fit_r{r}_f{f}.npz")["outer"]
    names = {"prior": "prior", "nn": sel["nn"], "gp": sel["gp"], "d": sel["d"], "h5": sel["h5"], "h5nn": sel["h5nn"]}; want = set(names.values()); rows = []
    for tk in W["elig"]:
        if fmap[W["fam"][tk]] != f: continue
        tc = S.TC(tk, W); rng = np.random.default_rng(zlib.crc32(tk.encode())); cs = rng.choice(tc.n, 3, replace=False); pl = 5 + 4 * tc.S[:, cs].mean(1) + rng.normal(0, 0.3, tc.n)
        rows += [("planted",) + x for x in S.eval_target(tc, prior, sp, seeds=range(5), ks=(10,), want=want, full=False, p_override=pl)]
        for rs in range(10):
            ps = np.random.default_rng(zlib.crc32(tk.encode()) + 31 * rs + 5).permutation(tc.p)
            rows += [("shuffled",) + x for x in S.eval_target(tc, prior, sp, seeds=[0], ks=(3, 5, 10), want=want, full=False, p_override=ps)]
    df = pd.DataFrame(rows, columns=["control"] + S.COLS); inv = {}
    for a, n in names.items(): inv.setdefault(n, []).append(a)
    df["alias"] = df.method.map(lambda m: ",".join(inv[m])); return df


if __name__ == "__main__":
    from joblib import Parallel, delayed
    df = pd.concat(Parallel(n_jobs=A.jobs, backend="loky")(delayed(unit)(f) for f in range(C.K_OUT))); df.to_csv(f"{C.RES}/controls.csv.gz", index=False)
    df["alias"] = df.alias.str.split(","); df = df.explode("alias"); rng = np.random.default_rng(3); out = {}
    def boot(v):
        v = np.asarray(v, float); return [float(np.percentile([v[rng.integers(0, len(v), len(v))].mean() for _ in range(2000)], q)) for q in (2.5, 97.5)]
    for (ctl, a, k), g in df.groupby(["control", "alias", "k"]):
        fam = g.groupby(["family", "target"]).sp.mean().groupby("family").mean(); out[f"{ctl}|{a}|k{k}"] = dict(mean=float(fam.mean()), ci95=boot(fam.values), n_fam=int(len(fam)))
    c1 = {a: out.get(f"planted|{a}|k10", {}).get("mean") for a in ("nn", "gp", "prior", "h5", "h5nn")}
    out["C1_values"] = c1; out["C1_pass"] = bool(c1["nn"] >= 0.4 and c1["gp"] >= 0.4 and c1["prior"] <= 0.15 and c1["h5"] >= 0.8 * c1["gp"] and c1["h5"] >= c1["prior"] + 0.2)
    sh = [(k, v) for k, v in out.items() if k.startswith("shuffled|")]; bad = [k for k, v in sh if not (v["ci95"][0] <= 0 <= v["ci95"][1] and abs(v["mean"]) <= 0.05)]; out["C2_pass"] = len(bad) == 0; out["C2_fail_cells"] = bad
    # amendment A2: ability of the shuffled control to pass under a TRUE null (normal approximation from each cell's own bootstrap CI half-width; independence across cells assumed, so this is an approximate LOWER-leaning figure because cells are positively correlated)
    from scipy.stats import norm
    pn = 1.0; ncell = 0
    for k, v in sh:
        se = (v["ci95"][1] - v["ci95"][0]) / 3.92
        if se <= 0: continue
        lim = min(0.05, 1.96 * se); pn *= (norm.cdf(lim / se) - norm.cdf(-lim / se)); ncell += 1
    out["C2_P_pass_under_true_null_approx"] = float(pn); out["C2_n_cells_in_rule"] = ncell
    out["C1_P_fail_under_planted_fault"] = "not computed (needs a planted-fault simulation; stated per amendment A2)"
    out["C2_P_fail_under_planted_fault"] = "not computed"
    out["reading"] = "C2 as registered requires every cell |mean|<=0.05 AND 95% CI covering 0; with many cells the probability of passing under a true null can be far below the 0.8 the rulebook asks of a control; a C2 'fail' is then weak evidence of a fault."
    json.dump(out, open(f"{C.RES}/controls_summary.json", "w"), indent=1, default=float); print("C1", out["C1_pass"], c1, "| C2", out["C2_pass"], bad)
