#!/usr/bin/env python3
"""
run_routing.py — Run Cross-Domain Routing benchmark (150 queries, 14 domains).

Usage:
    python runners/run_routing.py
    python runners/run_routing.py --domain rna_seq --output results/routing/
    python runners/run_routing.py --difficulty hard --max-tasks 20
    python runners/run_routing.py --adversarial-only --dry-run

Scoring:
    1.0 — correct_workflow mentioned AND no disqualified workflow mentioned
    0.5 — acceptable_alt matched (correct not found, no disqualified)
    0.0 — correct not found, or disqualified workflow mentioned
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters import RoutingBenchmarkAdapter


DOMAINS = [
    "rna_seq", "single_cell", "variant_calling", "epigenomics",
    "metagenomics", "proteomics", "transcriptomics", "genomics",
    "immunology", "drug_discovery",
]


def main():
    parser = argparse.ArgumentParser(description="Cross-domain routing benchmark runner")
    parser.add_argument("--output", default="results/routing/")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--max-tasks", type=int, default=None)
    parser.add_argument("--domain", choices=DOMAINS, default=None,
                        help="Filter to a single domain")
    parser.add_argument("--difficulty", choices=["easy", "medium", "hard"], default=None)
    parser.add_argument("--adversarial-only", action="store_true",
                        help="Run only the 10 adversarial confusable pairs")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--workers", type=int, default=3,
                        help="Parallel workers (default 3, reduces ~70 min → ~25 min; set higher with caution — overloads SSE server)")
    parser.add_argument("--ir-mode", action="store_true",
                        help=(
                            "IR evaluation mode: call /api/ai_assistant/search_ranked directly "
                            "and compute MRR, P@K, NDCG@3 on the raw ranked list. "
                            "Much faster than chat mode; measures search quality not LLM quality."
                        ))
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    if args.domain:
        config.setdefault("routing", {})["domain_filter"] = args.domain
    if args.difficulty:
        config.setdefault("routing", {})["difficulty_filter"] = args.difficulty
    if args.adversarial_only:
        config.setdefault("routing", {})["adversarial_only"] = True

    adapter = RoutingBenchmarkAdapter(config)
    tasks = adapter.load_tasks()
    if args.max_tasks:
        tasks = tasks[:args.max_tasks]

    if args.dry_run:
        print(f"Cross-Domain Routing — {len(tasks)} queries would run:\n")
        domain_counts: dict[str, int] = {}
        for t in tasks:
            domain_counts[t.domain] = domain_counts.get(t.domain, 0) + 1
        for d, c in sorted(domain_counts.items()):
            print(f"  {d}: {c}")
        return

    mode_label = "IR (search layer)" if args.ir_mode else "Chat (end-to-end)"
    print(f"Cross-Domain Routing Benchmark  [{mode_label}]")
    print(f"  Tasks:   {len(tasks)}")
    print(f"  Domain:  {args.domain or 'all'}")
    print(f"  Output:  {args.output}")
    print()

    client = BioMateEvalClient.from_config(config)
    store = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run("cross_domain_routing", suite="standalone", config=config)

    tasks = adapter.load_tasks()
    if args.max_tasks:
        tasks = tasks[:args.max_tasks]
    total = len(tasks)
    import threading
    completed = [0]
    _lock = threading.Lock()

    # ── IR mode: call search_ranked directly, compute IR metrics ─────────────
    if args.ir_mode:
        from concurrent.futures import ThreadPoolExecutor, as_completed
        import copy

        ir_rows: list[dict] = []

        def _run_ir_one(task):
            thread_client = copy.copy(client)
            import requests as _req
            thread_client._session = _req.Session()
            thread_client._session.headers.update({
                "Authorization": f"Bearer {client.token}",
                "Content-Type": "application/json",
            })
            ranked = adapter.fetch_ranked_list(thread_client, task.question, limit=10)
            gt = task.ground_truth
            metrics = adapter.ir_metrics(
                ranked,
                gt["correct_workflow"],
                alts=gt.get("acceptable_alts", []),
            )
            metrics["task_id"] = task.task_id
            metrics["domain"] = task.metadata.get("domain", "unknown")
            metrics["question"] = task.question[:80]
            metrics["correct"] = gt["correct_workflow"]
            metrics["top1_name"] = ranked[0] if ranked else ""
            metrics["ranked"] = ranked[:5]
            return metrics

        futures = {}
        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            for i, task in enumerate(tasks):
                futures[executor.submit(_run_ir_one, task)] = i
            for future in as_completed(futures):
                row = future.result()
                ir_rows.append(row)
                with _lock:
                    completed[0] += 1
                    n_done = completed[0]
                hit = "✓" if row.get("hit_at_1", 0) >= 1 else ("~" if row.get("hit_at_3", 0) >= 1 else "✗")
                print(
                    f"  [{n_done:3d}/{total}] {hit}  "
                    f"MRR={row['mrr']:.2f}  NDCG@3={row['ndcg_3']:.2f}  "
                    f"top1={row['top1_name'][:35]:35s}  {row['task_id'].replace('routing__', '')}",
                    flush=True,
                )

        store.finish_run(run_id)

        # ── IR summary ────────────────────────────────────────────────────────
        n = len(ir_rows)
        mrr       = sum(r["mrr"] for r in ir_rows) / n if n else 0
        ndcg3     = sum(r["ndcg_3"] for r in ir_rows) / n if n else 0
        p_at_1    = sum(r.get("p_at_1", 0) for r in ir_rows) / n if n else 0
        p_at_3    = sum(r.get("p_at_3", 0) for r in ir_rows) / n if n else 0
        hit_at_5  = sum(r.get("hit_at_5", 0) for r in ir_rows) / n if n else 0

        by_domain: dict[str, list] = {}
        for r in ir_rows:
            by_domain.setdefault(r["domain"], []).append(r)

        print(f"\n{'='*60}")
        print(f"IR Retrieval Metrics — Cross-Domain Routing (n={n})")
        print(f"{'='*60}")
        print(f"  MRR       : {mrr:.4f}  (higher = correct answer ranked earlier)")
        print(f"  P@1       : {p_at_1:.4f}  ({sum(r.get('p_at_1',0)>=1 for r in ir_rows)}/{n} exact top-1 matches)")
        print(f"  P@3       : {p_at_3:.4f}  (correct in top-3)")
        print(f"  NDCG@3    : {ndcg3:.4f}  (position-weighted relevance)")
        print(f"  Hit@5     : {hit_at_5:.4f}  (correct in top-5)")

        print(f"\n  {'Domain':<28} {'N':>4} {'MRR':>8} {'P@1':>8} {'NDCG@3':>8}")
        print(f"  {'-'*60}")
        for domain, rows in sorted(by_domain.items()):
            dm  = sum(r["mrr"] for r in rows) / len(rows)
            dp1 = sum(r.get("p_at_1",0) for r in rows) / len(rows)
            dn3 = sum(r["ndcg_3"] for r in rows) / len(rows)
            flag = " !" if dm < 0.5 else ""
            print(f"  {domain:<28} {len(rows):>4} {dm:>8.4f} {dp1:>8.4f} {dn3:>8.4f}{flag}")

        # Worst-ranked queries
        misses = [r for r in ir_rows if r.get("hit_at_5", 0) == 0]
        if misses:
            print(f"\n  Not found in top-5 ({len(misses)} queries):")
            for r in sorted(misses, key=lambda x: x["task_id"])[:10]:
                print(f"    [{r['task_id'].replace('routing__','')}] correct={r['correct']:30s}  "
                      f"top1={r['top1_name'][:35]}")

        print(f"\n  Results saved to: {config['paths']['results_db']}")
        return

    # ── Chat mode (default): end-to-end scoring via chat API ─────────────────
    def on_result(r):
        store.save_one(run_id, r)
        with _lock:
            completed[0] += 1
            n_done = completed[0]
        routed = r.agent_response.split("[routed:")[1].split("]")[0] if "[routed:" in r.agent_response else ""
        is_disambig = r.metadata.get("workflow_type") == "disambiguation" or "[disambig]" in r.agent_response
        label = f"[disambig:{routed[:25]}]" if is_disambig else routed[:40]
        status = "✓" if r.score >= 1.0 else ("~" if r.score > 0 else "✗")
        print(f"  [{n_done:3d}/{total}] {status} {r.score:.1f}  {label:40s}  {r.task_id.replace('routing__','')}", flush=True)

    t0 = time.time()
    results = adapter.run(client, max_tasks=args.max_tasks, on_result=on_result, workers=args.workers)
    store.finish_run(run_id)
    elapsed = time.time() - t0

    summary = store.summary(run_id).get("cross_domain_routing", {})
    n = summary.get("n", len(results))
    mean = summary.get("mean", 0.0)

    # Score distribution
    exact = sum(1 for r in results if r.score >= 1.0)
    partial = sum(1 for r in results if 0.0 < r.score < 1.0)
    wrong = sum(1 for r in results if r.score == 0.0)

    # Per-domain breakdown
    by_domain: dict[str, list[float]] = {}
    for r in results:
        by_domain.setdefault(r.metadata.get("domain", "unknown"), []).append(r.score)

    print(f"\n{'='*55}")
    print(f"Cross-Domain Routing Results")
    print(f"{'='*55}")
    print(f"  Overall:  n={n}  mean={mean:.3f}  elapsed={elapsed:.0f}s")
    print(f"  Exact (1.0): {exact}/{n} ({100*exact//n if n else 0}%)")
    print(f"  Alt   (0.5): {partial}/{n}")
    print(f"  Wrong (0.0): {wrong}/{n}\n")

    print(f"  {'Domain':<28} {'N':>4} {'Mean':>7}")
    print(f"  {'-'*40}")
    for domain, scores in sorted(by_domain.items()):
        dm = sum(scores) / len(scores) if scores else 0.0
        flag = " !" if dm < 0.7 else ""
        print(f"  {domain:<28} {len(scores):>4} {dm:>7.3f}{flag}")

    # Worst queries
    errors = [r for r in results if r.score == 0.0]
    if errors:
        print(f"\n  Failed queries ({len(errors)}):")
        for r in sorted(errors, key=lambda x: x.task_id)[:10]:
            q = r.metadata.get("question", "?")[:60]
            print(f"    [{r.task_id}] {q}...")

    print(f"\n  Results saved to: {config['paths']['results_db']}")


if __name__ == "__main__":
    main()
