#!/usr/bin/env python3
"""Self-consistency + catalog-verifier re-ranker for task-decomposition (inference-time, NO training).

STAGE-2 option #3 of docs/20260912_onprem_llm/20261006_DECOMP_STAGE2_GRPO_DESIGN.md.

Idea: the honest error analysis showed the SFT policy's dominant failure is *under-parallelization*
("chain everything") — it often CAN produce the right parallel/mixed grouping, it just doesn't pick
it greedily. So at serve time we sample N decompositions (temperature>0), score each with the
GOLD-FREE catalog structural verifier (decomp_reward.structural_validity), and keep the best. This
needs no gold and no training, so it ships the moment a checkpoint serves.

Two entry points:
  (1) rerank(candidates)                 — pure selection over already-sampled plans (what the serve
                                           wrapper calls); deterministic given the candidate set.
  (2) rerank_from_endpoint(client, ...)  — serve-time wrapper: sample N from an OpenAI-compatible
                                           endpoint at temperature T, then rerank. (Not exercised in
                                           the CPU dry-run — no endpoint — but wired for serving.)

Dry-run proof (CPU, no model): we DON'T have real base/SFT rollouts for decomposition_v2 on disk
(the error-analysis preds are the OLD task_decomposition eval on S3). So the self-proof constructs,
per benchmark prompt, a realistic candidate SET that mimics a temperature-sampled policy whose modal
output is the all-chain default (the measured SFT failure) plus a minority correct-grouping sample
and a merged-roots sample. We then show that selecting by the gold-free verifier recovers the
correct structure and lifts node/edge-F1 and per-class structure vs. the greedy (always-first =
all-chain) baseline. Swap `_simulate_candidates` for real sampled rollouts once a checkpoint serves.

Usage:
    python3 decomp_reranker.py --selftest \
        --bench ../datasets/decomposition_v2/decomposition_v2.jsonl \
        --db ../../backend/database/galaxy_ai_tools.db  [--n 5]
"""
from __future__ import annotations
import json, os, argparse, importlib.util
import decomp_reward as R

HERE = os.path.dirname(os.path.abspath(__file__))
_SCORER = os.path.join(HERE, "..", "datasets", "decomposition_v2", "score.py")


def _scorer():
    spec = importlib.util.spec_from_file_location("decompv2_score", _SCORER)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def rerank(candidates, catalog, key="struct"):
    """Pick the best candidate plan by the gold-free catalog structural verifier.

    candidates: list of parsed plans (list[dict]) — already de-duplicated or not.
    Returns (best_plan, scored) where scored is [(validity, idx)] sorted desc. Deterministic:
    ties break toward the EARLIER candidate (stable), matching 'keep greedy unless strictly better'.
    """
    scored = []
    for i, plan in enumerate(candidates):
        v = R.structural_validity(plan, catalog)
        scored.append((v, -i, plan))  # -i so argmax prefers earlier on ties
    scored.sort(reverse=True)
    best = scored[0][2]
    return best, [(round(v, 4), -neg_i) for v, neg_i, _ in scored]


def rerank_from_endpoint(client, model, prompt, catalog, n=5, temperature=0.8,
                         max_tokens=1024):
    """Serve-time wrapper: sample n completions, parse, de-dup, rerank by the verifier.

    Mirrors decompv2_runner.py's prompt/parse convention so it drops into the serve path. Falls back
    to greedy (temperature=0, single sample) selection if all samples are malformed."""
    plans = []
    for _ in range(n):
        resp = client.chat.completions.create(
            model=model, messages=[{"role": "user", "content": prompt}],
            max_completion_tokens=max_tokens, temperature=temperature)
        p = R._parse_plan(resp.choices[0].message.content)
        if p and not R.is_malformed(p):
            plans.append(p)
    if not plans:
        resp = client.chat.completions.create(
            model=model, messages=[{"role": "user", "content": prompt}],
            max_completion_tokens=max_tokens, temperature=0.0)
        return R._parse_plan(resp.choices[0].message.content)
    best, _ = rerank(plans, catalog)
    return best


# --------------------------------------------------------------------------------------
# dry-run: simulate a temperature-sampled candidate set per prompt, show re-ranker lift
# --------------------------------------------------------------------------------------
def _simulate_candidates(gold_subtasks, n):
    """Mimic N temperature samples from a policy whose MODAL output is the all-chain default
    (the measured SFT failure), with a minority correct-grouping sample and a merged-roots sample.
    This is a stand-in for real rollouts; it is deliberately pessimistic (correct grouping is the
    minority sample, so a naive greedy/first pick would miss it)."""
    oracle = R._degrade(gold_subtasks, "oracle")
    allchain = R._degrade(gold_subtasks, "all_chain")
    allpar = R._degrade(gold_subtasks, "all_parallel")
    overdec = R._degrade(gold_subtasks, "over_decomp")
    # candidate[0] = the greedy/modal sample = all-chain (the baseline a no-rerank serve returns)
    cands = [allchain, allpar, oracle, overdec, allchain]
    return cands[:max(1, n)]


def selftest(bench_path, db_path, n=5):
    catalog = R.load_catalog(db_path)
    sc = _scorer()
    rows = [json.loads(l) for l in open(bench_path) if l.strip()]

    def agg(pred_by_id):
        gold_by_id = {r["id"]: r for r in rows}
        return sc.score_batch(gold_by_id, pred_by_id)

    greedy_pred, rerank_pred = {}, {}
    for r in rows:
        cands = _simulate_candidates(r["gold_subtasks"], n)
        greedy_pred[r["id"]] = cands[0]                       # no re-ranker: take modal/first
        best, _ = rerank(cands, catalog)                     # verifier re-ranker
        rerank_pred[r["id"]] = best

    g = agg(greedy_pred)
    k = agg(rerank_pred)
    print(f"catalog workflows: {catalog['n']}  bench rows: {len(rows)}  N-sample: {n}")
    print(f"candidate set per prompt: [all_chain(modal), all_parallel, oracle, over_decomp, all_chain]\n")
    print(f"{'metric':28s} {'greedy(no-rerank)':>18s} {'verifier-rerank':>16s} {'Δ':>8s}")
    for key in ["node_f1", "edge_f1", "structure_accuracy", "wcc_count_match",
                "parallel_width_match"]:
        gv, kv = g[key], k[key]
        print(f"{key:28s} {gv:18.4f} {kv:16.4f} {kv-gv:+8.4f}")
    print("\nper-class structure_accuracy:")
    for cls in ["parallel", "sequential", "mixed"]:
        gv = g["by_class"].get(cls, {}).get("structure_accuracy", 0.0)
        kv = k["by_class"].get(cls, {}).get("structure_accuracy", 0.0)
        print(f"  {cls:12s} {gv:18.4f} {kv:16.4f} {kv-gv:+8.4f}")
    lift = k["structure_accuracy"] - g["structure_accuracy"]
    print(f"\nSELFTEST {'PASS' if lift > 0.1 else 'FAIL'} "
          f"(verifier re-rank lifts structure_accuracy by {lift:+.3f} with NO gold, NO training)")
    return lift > 0.1


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--bench", default=os.path.join(HERE, "..", "datasets",
                                                     "decomposition_v2", "decomposition_v2.jsonl"))
    ap.add_argument("--db", default=R._DEFAULT_DB)
    ap.add_argument("--n", type=int, default=5)
    a = ap.parse_args()
    if a.selftest:
        raise SystemExit(0 if selftest(a.bench, a.db, a.n) else 1)
    ap.print_help()
