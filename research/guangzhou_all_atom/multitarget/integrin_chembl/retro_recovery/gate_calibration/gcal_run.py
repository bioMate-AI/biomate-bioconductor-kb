"""Runner for the calibrated-gate programme (docs/20261031_GATE_CALIBRATION_PREREG.md).
  python3 gcal_run.py calibrate_syn            planted-signal strengths for the synthetic shortcut cells (separate seeds 2,900,001-2,900,030)
  python3 gcal_run.py real                      compact registered-gate records of the REAL benchmarks (analysis I, M2)
  python3 gcal_run.py run [--workers N]         FRESH validation jobs (seeds >= 2,000,000), resumable JSONL; prints counts only, never statuses"""
import os, sys, json, time, argparse
HERE = os.path.dirname(os.path.abspath(__file__)); GP = os.path.join(os.path.dirname(HERE), "gate_positive_control"); sys.path.insert(0, GP)
import gpc_lib as L
import numpy as np
OUT = f"{HERE}/results"; os.makedirs(OUT, exist_ok=True)
FAMS = ["S-tpsa", "S-typ", "S-cens", "S-diffuse"]; AS = [0.65, 0.70]


def jobs():
    J = [dict(id=f"gVI-{s}", kind="VI", seed=2000000 + s) for s in range(1, 401)] + [dict(id=f"gVM2-{s}", kind="VM2", seed=2100000 + s) for s in range(1, 201)]
    for F in (20, 26, 47): J += [dict(id=f"gV3-F{F}-{s}", kind="V3", F=F, seed=2200000 + 1000 * F + s) for s in range(1, 401)]
    for fi, fam in enumerate(FAMS):
        for ai, a in enumerate(AS):
            if fam == "S-cens" and a == 0.70: continue            # infeasible by the earlier calibration
            J += [dict(id=f"gS-{fam}|{a}-{s}", kind="S", family=fam, a=a, seed=2300000 + 10000 * fi + 1000 * ai + s) for s in range(1, 61)]
    for F in (20, 47):
        for fi, fam in enumerate(["S-tpsa", "S-typ", "S-diffuse"]):
            for ai, a in enumerate(AS):
                J += [dict(id=f"gSS-F{F}-{fam}|{a}-{s}", kind="SS", F=F, family=fam, a=a, seed=2400000 + 10000 * F + 2000 * fi + 1000 * ai + s) for s in range(1, 61)]
    return J


def run_job2(job, calib, csyn):
    kind = job["kind"]; seed = job["seed"]
    if kind in ("VI", "VM2", "S"): return L.run_job(job, calib)
    S = L.state(); rng = np.random.default_rng(seed)
    items, tf, folds = L.synth_benchmark(job["F"], seed, tpf=3, clip=400)
    if kind == "SS":
        z = L.planted_score(items, job["family"]); d = csyn[f"{job['family']}|{job['a']}|{job['F']}"]["d"]; items = L.planted_labels(items, z, d, rng)
    r = L.run_A11_like(items, tf, folds, False)
    return dict(id=job["id"], kind=kind, family=job.get("family"), a=job.get("a"), F=job["F"], seed=seed, **L.compact(r))


def _work(args):
    job, calib, csyn = args; t0 = time.time(); r = run_job2(job, calib, csyn); r["sec"] = round(time.time() - t0, 1); return r


def calibrate_syn():
    out = {}
    for F in (20, 47):
        items, _, _ = L.synth_benchmark(F, 2950000 + F, tpf=3, clip=400)
        for fam in ["S-tpsa", "S-typ", "S-diffuse"]:
            for a in AS:
                out[f"{fam}|{a}|{F}"] = L.calibrate(items, fam, a, seeds=range(2900001, 2900031)); print(fam, a, F, out[f"{fam}|{a}|{F}"], flush=True)
    json.dump(out, open(f"{OUT}/calibration_syn.json", "w"), indent=1)


def real():
    S = L.state(); out = {}
    out["I"] = L.compact(L.run_A11_like(S["I"], S["tf"], S["folds"], True)); out["M2"] = L.compact(L.run_A11_like(S["M2"], S["tf"], S["folds"], False))
    json.dump(out, open(f"{OUT}/real_records.json", "w"), indent=1); print("real records written", {k: v["status"] for k, v in out.items()})


def run(workers):
    import multiprocessing as mp
    calib = json.load(open(f"{GP}/results/calibration.json")); csyn = json.load(open(f"{OUT}/calibration_syn.json"))
    J = jobs()
    J = [j for j in J if j["kind"] != "S" or calib[f"{j['family']}|{j['a']}"]["feasible"]]
    J = [j for j in J if j["kind"] != "SS" or csyn[f"{j['family']}|{j['a']}|{j['F']}"]["feasible"]]
    path = f"{OUT}/gcal_validation.jsonl"; done = set()
    if os.path.exists(path): done = {json.loads(l)["id"] for l in open(path)}
    J = [j for j in J if j["id"] not in done]; J.sort(key=lambda j: -(j.get("F") or 26))
    print(f"{len(done)} done, {len(J)} to run, workers {workers}", flush=True); t0 = time.time()
    ctx = mp.get_context("spawn")
    with ctx.Pool(workers) as pool, open(path, "a") as f:
        for i, r in enumerate(pool.imap_unordered(_work, [(j, calib, csyn) for j in J], chunksize=1)):
            f.write(json.dumps(r) + "\n"); f.flush()
            if (i + 1) % 50 == 0: print(f"{len(done) + i + 1} complete; elapsed {time.time() - t0:.0f}s", flush=True)
    print("ALL DONE", flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("cmd"); ap.add_argument("--workers", type=int, default=5); a = ap.parse_args()
    {"calibrate_syn": calibrate_syn, "real": real}.get(a.cmd, lambda: run(a.workers))()
