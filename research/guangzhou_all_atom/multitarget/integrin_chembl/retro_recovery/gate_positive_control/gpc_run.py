"""Runner: python3 gpc_run.py calibrate | regress | run [--workers 5] [--only KIND,...]   (resumable JSONL; prints job counts only, never statuses)."""
import os, sys, json, time, argparse
import gpc_lib as L
import numpy as np, pandas as pd
HERE = L.HERE; OUT = f"{HERE}/results"; os.makedirs(OUT, exist_ok=True)
A_GRID = [0.55, 0.60, 0.65, 0.70]; F_GRID = [4, 6, 8, 10, 14, 26, 50, 100]


def jobs():
    J = [dict(id=f"VI-{s}", kind="VI", seed=s) for s in range(1, 201)] + [dict(id=f"VM2-{s}", kind="VM2", seed=5000 + s) for s in range(1, 201)]
    base = {"S-tpsa": 1000, "S-typ": 2000, "S-cens": 3000, "S-diffuse": 4000}
    for fam, b in base.items():
        n = 60 if fam == "S-diffuse" else 100
        for ai, a in enumerate(A_GRID):
            J += [dict(id=f"{fam}|{a}-{s}", kind="S", family=fam, a=a, seed=b + 100 * ai + s) for s in range(1, n + 1)]
    for F in F_GRID:
        n = 40 if F >= 50 else 60
        J += [dict(id=f"CURVE-F{F}-{s}", kind="CURVE", F=F, seed=7000 + 100 * F + s) for s in range(1, n + 1)]
    return J


def _work(args):
    job, calib = args; t0 = time.time(); r = L.run_job(job, calib); r["sec"] = round(time.time() - t0, 1); return r


def calibrate():
    S = L.state(); out = {}
    for fam in L.SHORTCUTS:
        for a in A_GRID:
            out[f"{fam}|{a}"] = L.calibrate(S["I"], fam, a, seeds=range(900001, 900031)); print(fam, a, out[f"{fam}|{a}"], flush=True)
    json.dump(out, open(f"{OUT}/calibration.json", "w"), indent=1)


def regress():
    S = L.state(); ok = True
    r = L.compact(L.run_A11_like(S["I"], S["tf"], S["folds"], True)); ref = json.load(open(f"{L.RD}/results/gate_A11_I_v1.json"))
    print("I_v1 status", r["status"], "ref", ref["status"]); ok &= r["status"] == ref["status"]
    for k, v in ref["primary"].items():
        for x in ("point", "lo", "hi", "lo90", "hi90"):
            d = abs(r["primary"][k][x] - v[x]); ok &= d < 1e-9; print(f"  {k}.{x} diff {d:.2e}")
    for k in ("C4_censored_label", "C5_assay_IC50_only", "C5_assay_has_Ki_or_Kd", "C5_assay_has_EC50"):
        d = abs(r["secondary"][k]["point"] - ref["secondary"][k]["point"]); ok &= d < 1e-9; print(f"  {k} diff {d:.2e}")
    rm = L.compact(L.run_A11_like(S["M2"], S["tf"], S["folds"], False)); refm = json.load(open(f"{L.RD}/results/validity_gate_M2.json"))
    for k, v in refm["primary"].items():
        if isinstance(v, str): continue
        d = abs(rm["primary"][k]["point"] - v["point"]); print(f"  M2 {k}.point diff {d:.2e} (old logic: points only)"); ok &= d < 1e-9
    print("REGRESSION", "PASS" if ok else "FAIL"); json.dump(dict(passed=bool(ok), I_v1_status=r["status"]), open(f"{OUT}/regression.json", "w"))
    return ok


def run(workers, only):
    import multiprocessing as mp
    calib = json.load(open(f"{OUT}/calibration.json")); J = jobs()
    J = [j for j in J if j["kind"] != "S" or calib[f"{j['family']}|{j['a']}"]["feasible"]]      # prereg section 2: infeasible levels are reported as infeasible, not run
    if only: J = [j for j in J if j["kind"] in only]
    path = f"{OUT}/gpc_results.jsonl"; done = set()
    if os.path.exists(path): done = {json.loads(l)["id"] for l in open(path)}
    J = [j for j in J if j["id"] not in done]; J.sort(key=lambda j: -(j.get("F") or 0))       # biggest first
    print(f"{len(done)} done, {len(J)} to run, workers {workers}", flush=True); t0 = time.time()
    ctx = mp.get_context("spawn")
    with ctx.Pool(workers) as pool, open(path, "a") as f:
        for i, r in enumerate(pool.imap_unordered(_work, [(j, calib) for j in J], chunksize=1)):
            f.write(json.dumps(r) + "\n"); f.flush()
            if (i + 1) % 25 == 0: print(f"{len(done) + i + 1} complete; elapsed {time.time() - t0:.0f}s", flush=True)
    print("ALL DONE", flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("cmd"); ap.add_argument("--workers", type=int, default=5); ap.add_argument("--only", default="")
    a = ap.parse_args()
    if a.cmd == "calibrate": calibrate()
    elif a.cmd == "regress": sys.exit(0 if regress() else 1)
    elif a.cmd == "run": run(a.workers, [x for x in a.only.split(",") if x])
