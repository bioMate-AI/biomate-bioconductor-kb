"""Smoke replay (PLUMBING ONLY, NO CLAIM): pool of CycPeptMPDB PAMPA peptides, within-source z labels, init set + rounds of batch selection.
Arms: random vs IH-LM (fast memory only: M2 offsets + M3 symbolic retrieval + M4 edit effects; no neural net, no knowledge channel).
Every round the verifier hook grades the picked compounds the converter maps, and the bridge attaches the gate flag to the revealed rows. 5 seeds, tiny pool, no intervals:
this only shows the components run together on real data; it is not an evaluation (the real replays are loop_retro L5/L7)."""
import os, sys, json, time, csv
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _paths import CYCPEPT_CSV, load_ihlm
from v4_adapter import V4Adapter
from verifier_hook import VerifierHook
from graded_bridge import GradedMemoryBridge, grade_smiles
from symbolic import iso

N_POOL, N_INIT, ROUNDS, BATCH, SEEDS = 500, 40, 4, 20, 5


def load():
    rows = list(csv.DictReader(open(CYCPEPT_CSV, encoding="utf-8-sig"))); by = {}
    for r in rows:
        try: y = float(r["Permeability"]); pam = float(r["PAMPA"])
        except (ValueError, KeyError, TypeError): continue
        if y <= -9.99 or not r.get("SMILES"): continue
        k = iso(r["SMILES"])
        if k is None: continue
        by.setdefault(k, []).append((r["Source"], y))
    recs = [dict(smiles=k, source=v[0][0], y=float(np.mean([a[1] for a in v]))) for k, v in by.items()]
    cnt = {}
    for r in recs: cnt[r["source"]] = cnt.get(r["source"], 0) + 1
    recs = [r for r in recs if cnt[r["source"]] >= 20]
    for s in {r["source"] for r in recs}:
        ys = np.array([r["y"] for r in recs if r["source"] == s]); mu, sd = ys.mean(), (ys.std() or 1.0)
        for r in recs:
            if r["source"] == s: r["label"] = float((r["y"] - mu) / sd)
    return recs


def main():
    t0 = time.time(); recs = load(); ad = V4Adapter(); hook = VerifierHook("avb6"); M = load_ihlm()
    out = dict(NOTICE="PLUMBING SMOKE ONLY — NO CLAIM. 5 seeds, tiny pool, no intervals; not an evaluation.", n_pool=N_POOL, n_init=N_INIT, rounds=ROUNDS, batch=BATCH, seeds=SEEDS, per_seed=[])
    for seed in range(SEEDS):
        rng = np.random.default_rng(seed); idx = rng.choice(len(recs), N_POOL, replace=False); pool = [recs[i] for i in idx]
        thr = float(np.quantile([r["label"] for r in pool], 0.9)); init = pool[:N_INIT]; rest = pool[N_INIT:]
        arms = {}
        for arm in ("random", "ihlm"):
            model = M.IHLM(modules=("M2", "M3", "M4"), slow_every=99, seed=seed); revealed = list(init); unl = list(rest); hits = 0
            rows = [dict(smiles=r["smiles"], target_seq="T", label=r["label"], source=r["source"]) for r in revealed]; model = model.update(rows, mode="finetune_ranking", seed=seed)
            n_ann = 0; n_graded = 0
            for rd in range(ROUNDS):
                if arm == "random": pick = list(rng.choice(len(unl), BATCH, replace=False))
                else:
                    sc = model.score([r["smiles"] for r in unl], "T", sources=[r["source"] for r in unl]); key = np.array([(-1e9 if s is None else s) + 1e-6 * rng.random() for s in sc]); pick = list(np.argsort(-key)[:BATCH])
                got = [unl[i] for i in pick]; hits += sum(r["label"] >= thr for r in got); unl = [r for i, r in enumerate(unl) if i not in set(pick)]
                gr, st = grade_smiles(ad, hook, [r["smiles"] for r in got]); n_graded += st["graded"]
                rows = [dict(smiles=r["smiles"], target_seq="T", label=r["label"], source=r["source"]) for r in got]
                model, n = GradedMemoryBridge().ingest(model, rows, gr, mode="finetune_ranking", seed=seed + rd); n_ann += n
            arms[arm] = dict(hits=int(hits), graded=n_graded, annotated=n_ann, mem_rows=len(model.mem.rows), offsets_sources=len(model.offsets))
        out["per_seed"].append(dict(seed=seed, thr=round(thr, 3), **arms))
    out["mean_hits"] = {a: float(np.mean([s[a]["hits"] for s in out["per_seed"]])) for a in ("random", "ihlm")}
    out["v4_coverage_in_pool_sample"] = ad.coverage([r["smiles"] for r in recs[:300]])["fraction"]; out["checkpoint_unmodified"] = ad.verify_unmodified(); out["seconds"] = round(time.time() - t0, 1)
    json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "smoke_result.json"), "w"), indent=1); print(json.dumps({k: v for k, v in out.items() if k != "per_seed"}, indent=1)); print(out["per_seed"][0])


if __name__ == "__main__":
    main()
