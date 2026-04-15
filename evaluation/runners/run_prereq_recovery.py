#!/usr/bin/env python3
"""
run_prereq_recovery.py — Run Prereq Recovery benchmark (40 multi-turn trajectories).

Usage:
    python runners/run_prereq_recovery.py
    python runners/run_prereq_recovery.py --domain rna_seq
    python runners/run_prereq_recovery.py --recovery-type accession_provided
    python runners/run_prereq_recovery.py --max-tasks 10 --dry-run

Recovery types:
    accession_provided   — user provides SRA/EMBL accession
    file_uploaded        — user uploads local file
    clarification_only   — user provides metadata (no data)
    impossible           — prerequisites cannot be satisfied

Scoring:
    1.0 — RESOLVED within max_turns_allowed
    0.5 — RESOLVED but exceeded max_turns_allowed
    0.0 — UNRESOLVED (BioMate never launched workflow)
   -0.5 — FALSE_LAUNCH (BioMate launched without real data)
    0.0 — LOOP (BioMate kept asking same question)
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters import PrereqRecoveryAdapter


DOMAINS = ["rna_seq", "variant_calling", "drug_docking", "proteomics"]
RECOVERY_TYPES = ["accession_provided", "file_uploaded", "clarification_only", "impossible"]
OUTCOMES = ["RESOLVED", "UNRESOLVED", "LOOP", "FALSE_LAUNCH"]


def main():
    parser = argparse.ArgumentParser(description="Prereq Recovery benchmark runner")
    parser.add_argument("--output", default="results/prereq_recovery/")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--max-tasks", type=int, default=None)
    parser.add_argument("--domain", choices=DOMAINS, default=None)
    parser.add_argument("--recovery-type", choices=RECOVERY_TYPES, default=None)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    if args.domain:
        config.setdefault("prereq_recovery", {})["domain_filter"] = args.domain
    if args.recovery_type:
        config.setdefault("prereq_recovery", {})["recovery_type_filter"] = args.recovery_type

    adapter = PrereqRecoveryAdapter(config)
    tasks = adapter.load_tasks()
    if args.max_tasks:
        tasks = tasks[:args.max_tasks]

    if args.dry_run:
        print(f"Prereq Recovery — {len(tasks)} trajectories would run:\n")
        by_domain: dict[str, int] = {}
        by_type: dict[str, int] = {}
        by_outcome: dict[str, int] = {}
        for t in tasks:
            by_domain[t.domain] = by_domain.get(t.domain, 0) + 1
            rt = t.metadata.get("recovery_type", "?")
            by_type[rt] = by_type.get(rt, 0) + 1
            eo = t.metadata.get("expected_outcome", "?")
            by_outcome[eo] = by_outcome.get(eo, 0) + 1
        print("  By domain:", dict(sorted(by_domain.items())))
        print("  By recovery type:", dict(sorted(by_type.items())))
        print("  By expected outcome:", dict(sorted(by_outcome.items())))
        return

    print(f"Prereq Recovery Benchmark")
    print(f"  Trajectories: {len(tasks)}")
    print(f"  Domain:       {args.domain or 'all'}")
    print(f"  RecovType:    {args.recovery_type or 'all'}")
    print(f"  Output:       {args.output}")
    print()

    client = BioMateEvalClient.from_config(config)
    store = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run("prereq_recovery", suite="standalone", config=config)

    t0 = time.time()
    results = adapter.run(client, max_tasks=args.max_tasks)
    store.save(run_id, results)
    store.finish_run(run_id)
    elapsed = time.time() - t0

    summary = store.summary(run_id).get("prereq_recovery", {})
    n = summary.get("n", len(results))
    mean = summary.get("mean", 0.0)

    # Outcome breakdown
    outcome_counts: dict[str, int] = {}
    for r in results:
        oc = r.metadata.get("actual_outcome", "unknown")
        outcome_counts[oc] = outcome_counts.get(oc, 0) + 1

    # Per-domain breakdown
    by_domain_scores: dict[str, list[float]] = {}
    for r in results:
        by_domain_scores.setdefault(r.metadata.get("domain", "?"), []).append(r.score)

    print(f"\n{'='*55}")
    print(f"Prereq Recovery Results")
    print(f"{'='*55}")
    print(f"  Overall:  n={n}  mean={mean:.3f}  elapsed={elapsed:.0f}s\n")

    print(f"  Outcome breakdown:")
    for oc in OUTCOMES + ["unknown"]:
        count = outcome_counts.get(oc, 0)
        if count:
            pct = 100 * count // n if n else 0
            print(f"    {oc:<20}: {count:>3} ({pct}%)")

    false_launches = [r for r in results if r.metadata.get("actual_outcome") == "FALSE_LAUNCH"]
    if false_launches:
        print(f"\n  !! FALSE_LAUNCH cases ({len(false_launches)}) — critical failures:")
        for r in false_launches[:5]:
            q = r.metadata.get("initial_query", "?")[:60]
            print(f"    [{r.task_id}] {q}...")

    print(f"\n  {'Domain':<20} {'N':>4} {'Mean':>7}")
    print(f"  {'-'*32}")
    for domain, scores in sorted(by_domain_scores.items()):
        dm = sum(scores) / len(scores) if scores else 0.0
        print(f"  {domain:<20} {len(scores):>4} {dm:>7.3f}")

    print(f"\n  Results saved to: {config['paths']['results_db']}")


if __name__ == "__main__":
    main()
