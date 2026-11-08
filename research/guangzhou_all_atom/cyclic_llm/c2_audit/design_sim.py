#!/usr/bin/env python3
"""D1-b..e of docs/20261030_C2_RERUN_AND_ANCHOR_TEST.md (amendment D1, committed before this code was run).
Simulation of shared-anchor-panel calibration on real CycPeptMPDB chemistry features.
usage: design_sim.py anchor_data.npz results_D1_census.json OUTDIR   env DS_STUDIES=200 DS_WORKERS DS_PILOT=1
Deviations/choices fixed a priori (not tuned on results): ridge lambda = 0.02 * n_train; PCs scaled to unit variance; lab peptides drawn at random from the 7,027-row bank
(lab-specific chemistry not modelled); panel compounds are extra measurements not added to training; intercept by centering."""
import json, os, sys, time, itertools, collections, zlib
import numpy as np
from concurrent.futures import ProcessPoolExecutor, as_completed
NPZ, CEN, OUT = sys.argv[1:4]
STUDIES = int(os.environ.get("DS_STUDIES", "200")); WORKERS = int(os.environ.get("DS_WORKERS", str(os.cpu_count() or 4))); PILOT = os.environ.get("DS_PILOT") == "1"
cen = json.load(open(CEN)); SIGMA_M = cen["sigma_m"]; TAU_HAT = cen["tau_hat_registered"]; WD = cen["within_lab_sd_median_ge30"]
SIZES = np.array([c for c in cen["lab_sizes_all"] if c >= 30])
z = np.load(NPZ, allow_pickle=True); FP = z["fp"].astype(np.float32)
Xc = FP - FP.mean(0); U, S, Vt = np.linalg.svd(Xc, full_matrices=False); PC = (U[:, :200] * np.sqrt(len(FP))).astype(np.float64)   # unit-variance PC scores (200)
NB = len(PC); rngw = np.random.default_rng(12345); W = rngw.normal(0, 1, 200); G0 = PC @ W; G0 = (G0 - G0.mean()) / G0.std()                     # fixed unit-variance true signal direction
PS = (0.0, 1.0)  # placeholder
def rank(a): return np.argsort(np.argsort(a)).astype(float)
def spear(a, b):
    ra, rb = rank(a), rank(b); ra -= ra.mean(); rb -= rb.mean(); d = np.sqrt((ra @ ra) * (rb @ rb)); return float(ra @ rb / d) if d > 0 else 0.0

def draw_labs(rng, L):
    sizes = rng.choice(SIZES, L); return [rng.choice(NB, int(n), replace=False) for n in sizes]

def study(rng, L, tau, s_sig, sw, sa, panel_grid):
    """Simulate one study; returns {(P,r): gain_by_heldout_lab array} plus raw rho array."""
    labs = draw_labs(rng, L); b = rng.normal(0, tau, L) if tau > 0 else np.zeros(L); sigw = np.sqrt(max(WD ** 2 - s_sig ** 2, 0.01)) * sw
    ys = [s_sig * G0[idx] + b[k] + rng.normal(0, sigw, len(idx)) for k, idx in enumerate(labs)]
    Xs = [PC[idx] for idx in labs]
    A = [x.T @ x for x in Xs]; c = [x.T @ y for x, y in zip(Xs, ys)]; u = [x.sum(0) for x in Xs]; n = np.array([len(i) for i in labs]); ysum = np.array([y.sum() for y in ys])
    At, ct, ut, nt, yt = sum(A), sum(c), sum(u), n.sum(), ysum.sum()
    maxP = max(p for p, _ in panel_grid); panel = rng.choice(NB, maxP, replace=False)
    yp = np.stack([[s_sig * G0[panel] + b[k] for _ in range(max(r for _, r in panel_grid))] for k in range(L)])    # (L, rmax, maxP) true values
    yp = yp + rng.normal(0, sa, yp.shape)
    out = {pr: [] for pr in panel_grid}; raw = []
    for h in range(L):
        T = np.array([k for k in range(L) if k != h]); nT = nt - n[h]; lam = 0.02 * nT
        Ah = At - A[h] + lam * np.eye(200); mh = (yt - ysum[h]) / nT
        def solve(rhs_c, rhs_u, m_label):
            return np.linalg.solve(Ah, rhs_c - m_label * rhs_u)
        ch, uh = ct - c[h], ut - u[h]
        w_raw = solve(ch, uh, mh); Xh = Xs[h]; rho_raw = spear(Xh @ w_raw, ys[h]); raw.append(rho_raw)
        for (P, r) in panel_grid:
            ybar = yp[:, :r, :P].mean(1)                    # (L, P)
            sT = ybar[T].sum(0); ref = (sT[None, :] - ybar[T]) / (len(T) - 1)    # for training lab s: mean of OTHER training labs
            bh = np.zeros(L); bh[T] = (ybar[T] - ref).mean(1)
            adj_c = sum(bh[s] * u[s] for s in T); adj_n = sum(bh[s] * n[s] for s in T)
            ml = mh - adj_n / nT
            w_cal = np.linalg.solve(Ah, ch - adj_c - ml * uh)
            # calibrated labels y - bh[s]:  X'y_cal = c - bh*u ; centred by mean label ml
            out[(P, r)].append(spear(Xh @ w_cal, ys[h]) - rho_raw)
    return {k: np.array(v) for k, v in out.items()}, np.array(raw)

def calibrate_signal(tau, sw=1.0, target=0.28, L=15, nsim=24):
    lo, hi = 0.05, WD * 0.98
    for _ in range(9):
        mid = (lo + hi) / 2; rng = np.random.default_rng(777); vals = []
        for _ in range(nsim): vals.append(study(rng, L, tau, mid, sw, SIGMA_M, [(3, 1)])[1].mean())
        m = float(np.mean(vals)); lo, hi = (mid, hi) if m < target else (lo, mid)
    return (lo + hi) / 2, m

def cluster_ci(g, rng, B=2000):
    ix = rng.integers(0, len(g), (B, len(g))); mb = g[ix].mean(1); return float(np.percentile(mb, 2.5)), float(np.percentile(mb, 97.5))

def run_group(args):
    L, tau, swm, sam, s_sig, panel_grid, ns, seed, tag = args
    rng = np.random.default_rng(seed); res = {pr: dict(g=[], lo=[]) for pr in panel_grid}; raws = []
    for _ in range(ns):
        out, raw = study(rng, L, tau, s_sig, swm, SIGMA_M * sam, panel_grid); raws.append(raw.mean())
        for pr, g in out.items():
            lo, _ = cluster_ci(g, rng, 500); res[pr]["g"].append(float(g.mean())); res[pr]["lo"].append(lo)
    rows = []
    for pr, d in res.items():
        g = np.array(d["g"]); lo = np.array(d["lo"])
        rows.append(dict(tag=tag, L=L, tau=tau, sw_mult=swm, sa_mult=sam, P=pr[0], r=pr[1], n_studies=ns, median_gain=float(np.median(g)), q25=float(np.percentile(g, 25)), q75=float(np.percentile(g, 75)),
                         power_003=float(np.mean((g >= 0.03) & (lo > 0))), power_005=float(np.mean((g >= 0.05) & (lo > 0))), frac_lo_gt0=float(np.mean(lo > 0)), mean_raw_rho=float(np.mean(raws))))
    return rows

def main():
    t0 = time.time(); os.makedirs(OUT, exist_ok=True)
    panel_grid = [(P, r) for P in (3, 5, 10, 20, 40) for r in (1, 2, 3)]; ns = 6 if PILOT else STUDIES
    taus = {"0.25": 0.25, "tau_hat": TAU_HAT, "0.48_external": 0.48, "0.75": 0.75, "1.0": 1.0}
    cal = {}
    for k, tv in taus.items():     # signal strength calibrated once per tau at the base noise so raw leave-lab-out rho = 0.28 (frozen across the grid)
        cal[k] = calibrate_signal(tv, nsim=6 if PILOT else 24); print("calibrated", k, tv, "s=%.3f raw_rho=%.3f" % cal[k], flush=True)
    s_ref = cal["tau_hat"][0]
    jobs = []
    for tk, tv in taus.items():
        for L in (8, 15, 30, 60): jobs.append((L, tv, 1.0, 1.0, cal[tk][0], panel_grid, ns, zlib.crc32(f"{tk}|{L}|base".encode()), f"base:{tk}"))
    for L in (15, 30):
        jobs.append((L, 0.48, 1.5, 1.0, cal["0.48_external"][0], panel_grid, ns, 91 + L, "sens:sigma_w_x1.5"))
        jobs.append((L, 0.48, 1.0, 2.0, cal["0.48_external"][0], panel_grid, ns, 191 + L, "sens:sigma_a_x2"))
    for L in (15, 30):
        jobs.append((L, 0.0, 1.0, 1.0, cal["0.48_external"][0], [(10, 1), (10, 3)], ns, 291 + L, "ctrl:tau0"))
        jobs.append((L, 0.48, 1.0, 1.0, 0.0, [(10, 1), (10, 3)], ns, 391 + L, "ctrl:no_signal"))
    if PILOT: jobs = jobs[:3] + jobs[-4:]
    rows = []
    with ProcessPoolExecutor(max_workers=WORKERS) as ex:
        futs = {ex.submit(run_group, j): j for j in jobs}
        for f in as_completed(futs):
            rows += f.result(); print("done", futs[f][8], futs[f][0], "(%ds)" % (time.time() - t0), flush=True)
    json.dump(dict(calibration={k: dict(signal_sd=v[0], raw_rho=v[1], tau=taus[k]) for k, v in cal.items()}, sigma_m=SIGMA_M, tau_hat=TAU_HAT, within_lab_sd=WD, studies=ns, rows=rows), open(f"{OUT}/D1_sim_results.json", "w"), indent=1)
    print("SIM_DONE %ds rows=%d" % (time.time() - t0, len(rows)), flush=True)

if __name__ == "__main__": main()
