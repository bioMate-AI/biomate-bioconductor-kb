"""Pilot 5 prior-fit stage: for repeat r and outer fold f, fit the target-agnostic HGB prior on the training families (outer) and on each inner split (inner), store predictions over ALL compounds.
usage: p5fit.py R0 R1 [--procs N] [--threads T] [--fp PATH]   (resumable: skips existing npz)"""
import os, sys, time, argparse, numpy as np
ap = argparse.ArgumentParser(); ap.add_argument("r0", type=int); ap.add_argument("r1", type=int); ap.add_argument("--procs", type=int, default=2); ap.add_argument("--threads", type=int, default=4); ap.add_argument("--fp"); ap.add_argument("--out")
A = ap.parse_args()
os.environ["OMP_NUM_THREADS"] = str(A.threads)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p5common as C
OUT = A.out or f"{C.RES}/fits"; os.makedirs(OUT, exist_ok=True)


def task(r, f):
    path = f"{OUT}/fit_r{r}_f{f}.npz"
    if os.path.exists(path): return path
    t0 = time.time(); W = C.world(A.fp); fmap = C.assign_outer(W, r); outer_h = {fa for fa, k in fmap.items() if k == f}
    pr_out = C.fit_prior(W, outer_h); imap = C.assign_inner(W, r, f, fmap); pr_in = []
    for j in range(C.N_INNER):
        hold = outer_h | {fa for fa, k in imap.items() if k == j}; pr_in.append(C.fit_prior(W, hold))
    np.savez_compressed(path + ".tmp.npz", outer=pr_out, inner=np.stack(pr_in)); os.replace(path + ".tmp.npz", path)
    print(f"r{r} f{f} done {round(time.time() - t0)}s", flush=True); return path


if __name__ == "__main__":
    from joblib import Parallel, delayed
    jobs = [(r, f) for r in range(A.r0, A.r1) for f in range(C.K_OUT)]
    Parallel(n_jobs=A.procs, backend="loky")(delayed(task)(r, f) for r, f in jobs)
