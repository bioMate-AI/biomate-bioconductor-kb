#!/usr/bin/env python3
"""
run_license_gating.py — Run License-Gated Orchestration benchmark (30 cases × 3 scenarios).

Usage:
    python runners/run_license_gating.py
    python runners/run_license_gating.py --scenario b --output results/license/
    python runners/run_license_gating.py --tool-category docking
    python runners/run_license_gating.py --dry-run

Scenarios:
    a — user has the commercial license (should use commercial tool, no fallback)
    b — user has no license (should fall back to OSS alternative)
    c — BioMate has master license (should use BioMate-provided key silently)

Scoring per case (mean of 4 criteria, each 0.0/1.0):
    correct_routing      — used the right tool for the scenario
    no_silent_failure    — never claimed to run unavailable tool
    fallback_quality     — fallback explanation quality (scenario b only)
    explanation_provided — told user why the routing decision was made
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters import LicenseGatingAdapter


TOOL_CATEGORIES = ["docking", "md_simulation", "structure_prediction", "mixed"]
SCENARIOS = ["a", "b", "c"]


def main():
    parser = argparse.ArgumentParser(description="License gating benchmark runner")
    parser.add_argument("--output", default="results/license_gating/")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--max-tasks", type=int, default=None)
    parser.add_argument("--scenario", choices=SCENARIOS, default=None,
                        help="Run only one scenario (a/b/c)")
    parser.add_argument("--tool-category", choices=TOOL_CATEGORIES, default=None)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    if args.scenario:
        config.setdefault("license_gating", {})["scenario_filter"] = args.scenario
    if args.tool_category:
        config.setdefault("license_gating", {})["category_filter"] = args.tool_category

    adapter = LicenseGatingAdapter(config)
    tasks = adapter.load_tasks()
    if args.max_tasks:
        tasks = tasks[:args.max_tasks]

    if args.dry_run:
        print(f"License Gating — {len(tasks)} cases would run:\n")
        scenarios_seen: dict[str, int] = {}
        cats_seen: dict[str, int] = {}
        for t in tasks:
            s = t.metadata.get("scenario", "?")
            c = t.metadata.get("tool_category", "?")
            scenarios_seen[s] = scenarios_seen.get(s, 0) + 1
            cats_seen[c] = cats_seen.get(c, 0) + 1
        print("  By scenario:", dict(sorted(scenarios_seen.items())))
        print("  By category:", dict(sorted(cats_seen.items())))
        return

    print(f"License Gating Benchmark")
    print(f"  Cases:    {len(tasks)}")
    print(f"  Scenario: {args.scenario or 'all (a/b/c)'}")
    print(f"  Category: {args.tool_category or 'all'}")
    print(f"  Output:   {args.output}")
    print()

    client = BioMateEvalClient.from_config(config)
    store = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run("license_gating", suite="standalone", config=config)

    t0 = time.time()
    results = adapter.run(client, max_tasks=args.max_tasks)
    store.save(run_id, results)
    store.finish_run(run_id)
    elapsed = time.time() - t0

    summary = store.summary(run_id).get("license_gating", {})
    n = summary.get("n", len(results))
    mean = summary.get("mean", 0.0)

    # Per-scenario breakdown
    by_scenario: dict[str, list[float]] = {}
    by_category: dict[str, list[float]] = {}
    silent_failures: list = []
    for r in results:
        by_scenario.setdefault(r.metadata.get("scenario", "?"), []).append(r.score)
        by_category.setdefault(r.metadata.get("tool_category", "?"), []).append(r.score)
        if r.metadata.get("silent_failure_detected"):
            silent_failures.append(r)

    print(f"\n{'='*55}")
    print(f"License Gating Results")
    print(f"{'='*55}")
    print(f"  Overall:  n={n}  mean={mean:.3f}  elapsed={elapsed:.0f}s\n")

    print(f"  {'Scenario':<15} {'N':>4} {'Mean':>7}  {'Description'}")
    print(f"  {'-'*55}")
    scenario_desc = {
        "a": "user has license (use commercial)",
        "b": "no license (fall back to OSS)",
        "c": "BioMate master key (use silently)",
    }
    for sc in ["a", "b", "c"]:
        scores = by_scenario.get(sc, [])
        if scores:
            sm = sum(scores) / len(scores)
            desc = scenario_desc.get(sc, "")
            print(f"  {'scenario_' + sc:<15} {len(scores):>4} {sm:>7.3f}  {desc}")

    if silent_failures:
        print(f"\n  !! SILENT FAILURES ({len(silent_failures)}) — claimed unavailable tool ran:")
        for r in silent_failures[:5]:
            print(f"    [{r.task_id}] tool={r.metadata.get('tool', '?')}")

    print(f"\n  {'Category':<25} {'N':>4} {'Mean':>7}")
    print(f"  {'-'*37}")
    for cat, scores in sorted(by_category.items()):
        cm = sum(scores) / len(scores) if scores else 0.0
        print(f"  {cat:<25} {len(scores):>4} {cm:>7.3f}")

    print(f"\n  Results saved to: {config['paths']['results_db']}")


if __name__ == "__main__":
    main()
