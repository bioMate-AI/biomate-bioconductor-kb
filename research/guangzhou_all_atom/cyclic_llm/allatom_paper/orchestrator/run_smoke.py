"""Smoke experiment for I-A: planted-optimum oracle + shuffled-reward control, learned loop vs random search (EC2 only).
Writes smoke_result.json with typed intervals. Usage: python3.11 -m orchestrator.run_smoke OUTDIR [n_seeds] [budget]"""
import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))

import numpy as np  # noqa: E402

from orchestrator.loop import LoopConfig, run_loop  # noqa: E402
from orchestrator.toy import (ScoreTopKRetriever, ToyGenerator, ToyPairUpdater, planted_verifier, random_sampler)  # noqa: E402
from pmo_harness import hash_noise_verifier, paired_contrast, random_search, run_one, summarise  # noqa: E402

L = 10


def one(seed, verifier, budget):
    g = ToyGenerator(L)
    cfg = LoopConfig(run_id=f"smoke{seed}", seed=seed, budget=budget, n_per_round=20, lr=0.8, topk=10)
    res = run_loop(cfg, g, verifier, retriever=ScoreTopKRetriever(), updater=ToyPairUpdater(g))
    rnd = run_one(random_search(random_sampler(L)), verifier, budget, seed, k=10)
    return res, rnd


def main(out, n_seeds=10, budget=300):
    os.makedirs(out, exist_ok=True)
    out_json = {"n_seeds": n_seeds, "budget": budget, "L": L, "interval_note": "ci_boot_mean = percentile bootstrap of the mean over seeds; ci_t = t-interval; ci_wide = the wider of the two"}
    for name, mk in (("planted", lambda s: planted_verifier(L=L)), ("shuffled", lambda s: hash_noise_verifier("shuffled", salt="ia"))):
        la, ra, found, found_r, curves = [], [], 0, 0, []
        for s in range(n_seeds):
            res, rnd = one(s, mk(s), budget)
            la.append(res["auc_topk"]); ra.append(rnd["auc_topk"]); found += int(res["final_topk"] >= 0.999); found_r += int(rnd["final_topk"] >= 0.999)
            curves.append((np.asarray(res["curve"]), np.asarray(rnd["curve"])))
        mean_loop = np.mean([c[0] for c in curves], axis=0)
        mean_rand = np.mean([c[1] for c in curves], axis=0)
        out_json[name] = {"loop_auc": summarise(la), "random_auc": summarise(ra), "paired_loop_minus_random": paired_contrast(la, ra),
                          "optimum_found_seeds": found if name == "planted" else None, "optimum_found_seeds_random_search": found_r if name == "planted" else None,
                          "calls_to_topk_0.95": {"loop": next((i + 1 for i, v in enumerate(mean_loop) if v >= 0.95), None),
                                                  "random": next((i + 1 for i, v in enumerate(mean_rand) if v >= 0.95), None)} if name == "planted" else None}
    p = out_json["planted"]["paired_loop_minus_random"]
    sh = out_json["shuffled"]["paired_loop_minus_random"]
    out_json["checks"] = {"planted_optimum_found_at_least_as_often_as_random_search": (out_json["planted"]["optimum_found_seeds"] or 0) >= (out_json["planted"]["optimum_found_seeds_random_search"] or 0),
                          "learning_beats_random_on_planted": bool(p["mean"] > 0 and p["ci_wide"][0] > 0),
                          "shuffled_does_not_beat_random": bool(not (sh["ci_t"][0] > 0))}
    json.dump(out_json, open(os.path.join(out, "smoke_result.json"), "w"), indent=1, default=float)
    print(json.dumps(out_json["checks"]), json.dumps({k: out_json[k]["paired_loop_minus_random"]["mean"] for k in ("planted", "shuffled")}))


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 10, int(sys.argv[3]) if len(sys.argv) > 3 else 300)
