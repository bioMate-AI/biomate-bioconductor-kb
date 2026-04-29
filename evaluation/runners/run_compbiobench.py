"""Runner for CompBioBench v1 benchmark.

Submits tasks to BioMate and writes a TSV for leaderboard submission at:
  https://huggingface.co/spaces/Genentech/compbiobench-leaderboard-v1

Usage:
  python -m runners.run_compbiobench --output results/compbiobench_v1
  python -m runners.run_compbiobench --output results/compbiobench_v1 --no-file-only
  python -m runners.run_compbiobench --output results/compbiobench_v1 --domain genomics
"""
import argparse
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.adapters.compbiobench_adapter import CompBioBenchAdapter
from evaluation.core.biomate_client import BioMateEvalClient
from evaluation.core.results_store import ResultsStore


def main():
    parser = argparse.ArgumentParser(description="CompBioBench benchmark runner")
    parser.add_argument("--output", default="results/compbiobench_v1")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--max-tasks", type=int, default=None)
    parser.add_argument("--domain", default=None,
                        help="Filter to one domain (e.g. genomics, single_cell)")
    parser.add_argument("--no-file-only", action="store_true",
                        help="Only run the 27 tasks that need no local files")
    args = parser.parse_args()

    with open(args.config) as f:
        config = yaml.safe_load(f)

    client = BioMateEvalClient.from_config(config)
    adapter = CompBioBenchAdapter(config)

    # Load and optionally filter tasks
    all_tasks = adapter.load_tasks()
    tasks = all_tasks
    if args.no_file_only:
        # Only tasks where the TSV has NO file_paths at all (27 tasks)
        tasks = [t for t in tasks if not t.metadata.get("needs_files")]
        print(f"No-file-only mode: {len(tasks)} tasks")
    else:
        # By default run tasks where we have the files OR no files needed
        tasks = [t for t in tasks if not t.metadata.get("needs_files") or t.metadata.get("has_local_files")]
        print(f"Available tasks (no files needed + files present): {len(tasks)}")
    if args.domain:
        tasks = [t for t in tasks if t.metadata.get("domain", "").startswith(args.domain.lower())]
        print(f"Domain filter '{args.domain}': {len(tasks)} tasks")
    if args.max_tasks:
        tasks = tasks[:args.max_tasks]

    # Monkey-patch to return filtered list
    adapter.load_tasks = lambda: tasks

    print(f"\n{'='*60}")
    print(f"CompBioBench v1")
    print(f"{'='*60}")

    results = adapter.run(client)

    # Save results
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    store = ResultsStore(str(out / "eval_results.db"))
    run_id = store.start_run("compbiobench", "compbiobench_v1", config)
    store.save(run_id, results)

    # Write submission TSV
    submission_path = str(out / "submission.tsv")
    adapter.write_submission_tsv(results, submission_path)

    # Summary
    answered = sum(1 for r in results if r.agent_response and not r.agent_response.startswith("ERROR"))
    errors = sum(1 for r in results if r.error)

    print(f"\n{'='*60}")
    print(f"CompBioBench v1 Summary")
    print(f"{'='*60}")
    print(f"  Total tasks:    {len(results)}")
    print(f"  Answered:       {answered}")
    print(f"  Errors:         {errors}")
    print(f"  Unanswered:     {len(results) - answered - errors}")
    print(f"\n  Results saved:  {args.output}")
    print(f"  Submission TSV: {submission_path}")
    print(f"\n  Submit to leaderboard:")
    print(f"  https://huggingface.co/spaces/Genentech/compbiobench-leaderboard-v1")


if __name__ == "__main__":
    main()
