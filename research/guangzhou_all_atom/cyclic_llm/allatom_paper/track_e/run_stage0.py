#!/usr/bin/env python3
"""Stage-0 runner (Track E): tune / evaluate / control runs of the non-LM baselines under the PMO-style budget. EC2 or Spark only.
  run_stage0.py tune     OUT --budget 1000 --seeds 100-102      # each method is tuned on the OTHER family's train objective
  run_stage0.py eval     OUT --budget 1000 --seeds 0-9 --cfg OUT/tuned.json
  run_stage0.py controls OUT --budget 1000 --seeds 0-4          # shuffled reward, planted optimum, copy-seed
Resumable: a finished (mode, family, method, seed) result file is skipped. Held-out verifiers are applied to the FINAL top-10 only."""
import os

for _v in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ.setdefault(_v, "1")
import argparse
import json
import sys
import time
from multiprocessing import get_context

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import baselines as BL  # noqa: E402
import verifiers_e as VE  # noqa: E402
import pmo_harness as H  # noqa: E402

G = {}   # fork-shared state


def parse_seeds(s):
    if "-" in s:
        a, b = s.split("-")
        return list(range(int(a), int(b) + 1))
    return [int(x) for x in s.split(",")]


def setup(a):
    t0 = time.time()
    import random as _r
    rr = _r.Random(20261029); gen_ref = []
    while len(gen_ref) < a.gen_ref_n:      # A4 scale reference: rule-satisfying random draws from the library sampler (the generation space)
        for s in BL.GP.gen_lib([], 200, rr, rr.choice(BL.LIB_CFGS)):
            c = VE.canon(s)
            if c and BL.constraint(c):
                gen_ref.append(c)
    gen_ref = gen_ref[: a.gen_ref_n]
    L = VE.build_ladder(a.ann, version=a.groups, gen_ref=gen_ref if a.scale == "z_gen" else None)
    G.update(L)
    G["seeds"] = BL.build_seeds(L["d"], L["groups"])
    G["reg"] = BL.registry(G["seeds"])
    ph, nref = VE.physics_heldout_verifier(L["ref"], n_ref=a.n_ref)
    ph = ph
    G["physics"] = ph
    json.dump(dict(scale=L["scale"], group_summary=L["group_summary"], n_seeds=len(G["seeds"]), n_phys_ref=nref, setup_s=round(time.time() - t0, 1)),
              open(os.path.join(a.out, "setup.json"), "w"), indent=1, default=str)
    print("setup done", round(time.time() - t0), "s; seeds", len(G["seeds"]), "physics ref", nref, flush=True)


def family_objs(fam):
    L = G["ladder"][fam]
    held = [G["physics"]] if fam == "F1" else [L["heldout"]]
    return L["train"], L["stop"], held


def one_run(job):
    mode, fam, method, cfg, seed, budget, out = job
    path = os.path.join(out, mode, fam, f"{method}__s{seed}.json")
    if os.path.exists(path):
        return path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    t0 = time.time()
    train, stop, held = family_objs(fam)
    if mode == "tune":
        held = []                      # tuning never touches held-out verifiers (no peeking, no wasted physics calls)
    if mode == "controls":
        train = G["controls"][method.split("@")[1]]
        method = method.split("@")[0]
        held = []
    if method == "copy_seed":
        opt = H.copy_seed(G["seeds"])
    else:
        opt = G["reg"][method](cfg)
    r = H.run_one(opt, train, budget, seed, k=10, canon=VE.canon, constraint=BL.constraint, heldout=held)
    top = r["top_smiles"]
    r["stop_final"] = float(np.mean([stop.fn(s) for s in top])) if top else float("nan")
    r.update(dict(mode=mode, family=fam, method=job[2], cfg=cfg, wall_s=round(time.time() - t0, 1)))
    r["curve"] = [round(float(x), 5) for x in np.asarray(r["curve"])[:: max(1, len(r["curve"]) // 200)]]
    json.dump(r, open(path, "w"), default=float)
    return path


def run_jobs(jobs, workers):
    ctx = get_context("fork")
    with ctx.Pool(workers) as p:
        for i, path in enumerate(p.imap_unordered(one_run, jobs)):
            if i % 10 == 0:
                print(f"[{i + 1}/{len(jobs)}] {os.path.basename(path)}", flush=True)


def other(fam):
    return "F2" if fam == "F1" else "F1"


def cmd_tune(a):
    jobs = []
    seeds = parse_seeds(a.seeds)
    for fam in ("F1", "F2"):
        dev = other(fam)               # tune the methods used on `fam` on the other family's train objective
        for method, grid in BL.GRIDS.items():
            for ci, cfg in enumerate(grid):
                for s in seeds:
                    jobs.append(("tune", dev, f"{method}", dict(cfg, _ci=ci), s, a.budget, a.out))
    # file names must be unique per config: encode ci in the method label via cfg; use a wrapper naming
    uniq = []
    for j in jobs:
        mode, fam, method, cfg, s, b, out = j
        uniq.append((mode, fam, f"{method}#c{cfg['_ci']}", {k: v for k, v in cfg.items() if k != "_ci"}, s, b, out))
    G["reg"].update({f"{m}#c{ci}": (lambda cfg, _m=m: G["reg"][_m](cfg)) for m in BL.GRIDS for ci in range(len(BL.GRIDS[m]))})
    run_jobs(uniq, a.workers)


def best_cfgs(out):
    """For each method: the config with the highest mean AUC-top-10 over tuning seeds (tuned on the other family)."""
    best = {}
    for fam in ("F1", "F2"):
        d = os.path.join(out, "tune", fam)
        agg = {}
        for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            r = json.load(open(os.path.join(d, f)))
            m, c = r["method"].split("#c")
            agg.setdefault((m, int(c)), []).append(r["auc_topk"])
            agg.setdefault(("_cfg", m, int(c)), r["cfg"])
        for (m, c), v in [(k, v) for k, v in agg.items() if k[0] != "_cfg"]:
            cur = best.setdefault(other(fam), {}).get(m)       # config tuned on `fam` is USED on the other family
            if cur is None or np.mean(v) > cur[0]:
                best[other(fam)][m] = (float(np.mean(v)), c, agg[("_cfg", m, c)], len(v))
    return {fam: {m: dict(auc_dev=v[0], ci=v[1], cfg=v[2], n_seeds=v[3]) for m, v in d.items()} for fam, d in best.items()}


def cmd_eval(a):
    tuned = json.load(open(a.cfg)) if os.path.exists(a.cfg) else None
    if tuned is None:
        tuned = best_cfgs(a.out)
        json.dump(tuned, open(a.cfg, "w"), indent=1)
    seeds = parse_seeds(a.seeds)
    jobs = [("eval", fam, m, tuned[fam][m]["cfg"], s, a.budget, a.out) for fam in ("F1", "F2") for m in tuned[fam] for s in seeds]
    run_jobs(jobs, a.workers)


def cmd_controls(a):
    seeds = parse_seeds(a.seeds)
    nme = BL.GP.mol_stats

    def planted(c):
        m = BL.Chem.MolFromSmiles(c)
        ring, n = nme(m)
        return max(0.0, 1.0 - (abs(n - 4) + abs(ring - 20) / 4.0) / 4.0)

    G["controls"] = {
        "shuffled": H.hash_noise_verifier(),
        "planted": H.Verifier(name="planted_optimum", fn=planted, role="train"),
    }
    tuned = json.load(open(a.cfg))
    jobs = []
    for fam in ("F2",):
        for m in tuned[fam]:
            for ctl in ("shuffled", "planted"):
                for s in seeds:
                    jobs.append(("controls", fam, f"{m}@{ctl}", tuned[fam][m]["cfg"], s, a.budget, a.out))
        for s in seeds:
            jobs.append(("controls", fam, "copy_seed@shuffled", {}, s, a.budget, a.out))
            jobs.append(("controls", fam, "copy_seed@planted", {}, s, a.budget, a.out))
    run_jobs(jobs, a.workers)


def cmd_smoke(a):
    """pre-flight: every method on both families, budget 60, one seed, first grid config; fails loudly if any run crashes."""
    jobs = [("smoke", fam, m, BL.GRIDS[m][0], 0, 60, a.out) for fam in ("F1", "F2") for m in BL.GRIDS]
    run_jobs(jobs, a.workers)
    bad = [j for j in jobs if not os.path.exists(os.path.join(a.out, "smoke", j[1], f"{j[2]}__s0.json"))]
    print("smoke runs", len(jobs), "missing", len(bad), flush=True)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["smoke", "tune", "eval", "controls"])
    ap.add_argument("out")
    ap.add_argument("--budget", type=int, default=1000)
    ap.add_argument("--seeds", default="0-9")
    ap.add_argument("--cfg", default=None)
    ap.add_argument("--ann", default=VE.ANN_DEFAULT)
    ap.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 2)))
    ap.add_argument("--n-ref", type=int, default=60)
    ap.add_argument("--groups", default="v2", choices=["v1", "v2"])
    ap.add_argument("--scale", default="z_gen", choices=["z_gen", "percentile"])
    ap.add_argument("--gen-ref-n", type=int, default=1500)
    a = ap.parse_args()
    a.cfg = a.cfg or os.path.join(a.out, "tuned.json")
    os.makedirs(a.out, exist_ok=True)
    setup(a)
    {"smoke": cmd_smoke, "tune": cmd_tune, "eval": cmd_eval, "controls": cmd_controls}[a.mode](a)
