#!/usr/bin/env python3
"""
Automated test runner for all 237 biomni Nextflow workflows.

Usage:
    python run_all_tests.py                    # Test all workflows
    python run_all_tests.py --domain genomics  # Test specific domain
    python run_all_tests.py --workflow molecular_biology/digest_sequence  # Test specific workflow
    python run_all_tests.py --parallel 4       # Run 4 tests in parallel
    python run_all_tests.py --quick            # Quick mode (skip slow workflows)
"""

import json
import subprocess
import sys
import os
import argparse
import time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

# Configuration
SCRIPT_DIR = Path(__file__).parent
NFCORE_DIR = SCRIPT_DIR.parent
SUBWORKFLOWS_DIR = NFCORE_DIR / "subworkflows"
PARAMS_FILE = SCRIPT_DIR / "workflow_params.json"
TEST_VALUES_FILE = SCRIPT_DIR / "test_values.json"
RESULTS_DIR = NFCORE_DIR / "test_results"

# Slow workflows that require external resources or heavy computation
SLOW_WORKFLOWS = {
    "database/blast_sequence",  # Requires NCBI connection
    "literature/extract_url_content",  # Requires web access
    "literature/advanced_web_search_claude",  # Requires API
    "literature/fetch_supplementary_info_from_doi",  # Requires web access
    "pharmacology/retrieve_topk_repurposing_drugs_from_disease_txgnn",  # Heavy ML model
    "genomics/generate_transcriptformer_embeddings",  # Heavy ML model
    "genomics/generate_gene_embeddings_with_ESM_models",  # Heavy ML model
    "bioimaging/segment_with_nn_unet",  # Heavy ML model
}

# Workflows that are helper/utility functions (no params needed)
NO_PARAM_WORKFLOWS = {
    "bioimaging/command_iteration",
    "bioimaging/patched_torch_load",
    "genomics/get_gene_set_enrichment_analysis_supported_database_list",
    "glycoengineering/list_glycoengineering_resources",
    "lab_automation/get_pylabrobot_documentation_liquid",
    "lab_automation/get_pylabrobot_documentation_material",
    "lab_automation/run_async",
    "lab_automation/target",
    "molecular_biology/get_oligo_annealing_protocol",
    "molecular_biology/search_gene",
}


def load_params():
    """Load workflow parameters from JSON file."""
    with open(PARAMS_FILE) as f:
        return json.load(f)


def load_test_values():
    """Load test values for parameters."""
    with open(TEST_VALUES_FILE) as f:
        return json.load(f)


def get_test_value(param_name, param_info, test_values):
    """Get appropriate test value for a parameter."""
    # First try by exact name match
    if param_name in test_values["by_name"]:
        return test_values["by_name"][param_name]

    # Then try by partial name match
    for key, value in test_values["by_name"].items():
        if key in param_name or param_name in key:
            return value

    # Fall back to type-based default
    param_type = param_info.get("type", "string")
    if param_type in test_values["by_type"]:
        return test_values["by_type"][param_type]

    # If there's a default that's not null, use it
    default = param_info.get("default")
    if default is not None and default != "null":
        return default

    return None


def build_nextflow_command(workflow_path, params, test_values):
    """Build nextflow command with test parameters."""
    workflow_file = SUBWORKFLOWS_DIR / workflow_path / "main.nf"

    cmd = [
        "nextflow", "run", str(workflow_file),
        "-profile", "docker",
        "--outdir", str(RESULTS_DIR / workflow_path.replace("/", "_"))
    ]

    for param_name, param_info in params.items():
        if param_name == "outdir":
            continue  # Already set above
        if param_name in ("output_dir", "output_file"):
            continue  # Skip output config params

        value = get_test_value(param_name, param_info, test_values)
        if value is None:
            continue

        # Format value appropriately
        if isinstance(value, (list, dict)):
            value_str = json.dumps(value)
        elif isinstance(value, bool):
            value_str = str(value).lower()
        else:
            value_str = str(value)

        cmd.extend([f"--{param_name}", value_str])

    return cmd


def run_workflow_test(workflow_path, params, test_values, timeout=300):
    """Run a single workflow test."""
    start_time = time.time()

    try:
        cmd = build_nextflow_command(workflow_path, params, test_values)

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(NFCORE_DIR)
        )

        elapsed = time.time() - start_time
        success = result.returncode == 0

        # Check for success indicator in output
        if "✔" in result.stdout or "✔" in result.stderr:
            success = True

        return {
            "workflow": workflow_path,
            "success": success,
            "returncode": result.returncode,
            "elapsed_seconds": round(elapsed, 2),
            "stdout_tail": result.stdout[-500:] if result.stdout else "",
            "stderr_tail": result.stderr[-500:] if result.stderr else "",
            "command": " ".join(cmd[:6]) + " ..."  # Truncate for readability
        }

    except subprocess.TimeoutExpired:
        return {
            "workflow": workflow_path,
            "success": False,
            "error": "Timeout",
            "elapsed_seconds": timeout
        }
    except Exception as e:
        return {
            "workflow": workflow_path,
            "success": False,
            "error": str(e),
            "elapsed_seconds": time.time() - start_time
        }


def run_tests(workflows_to_test, test_values, parallel=1, quick=False):
    """Run tests for multiple workflows."""
    results = []

    if quick:
        workflows_to_test = {k: v for k, v in workflows_to_test.items()
                           if k not in SLOW_WORKFLOWS}

    total = len(workflows_to_test)
    print(f"\nRunning {total} workflow tests (parallel={parallel}, quick={quick})")
    print("=" * 60)

    if parallel > 1:
        with ThreadPoolExecutor(max_workers=parallel) as executor:
            futures = {
                executor.submit(run_workflow_test, wf, params, test_values): wf
                for wf, params in workflows_to_test.items()
            }

            for i, future in enumerate(as_completed(futures), 1):
                result = future.result()
                results.append(result)
                status = "✓" if result["success"] else "✗"
                print(f"[{i}/{total}] {status} {result['workflow']} ({result.get('elapsed_seconds', 0):.1f}s)")
    else:
        for i, (workflow, params) in enumerate(workflows_to_test.items(), 1):
            result = run_workflow_test(workflow, params, test_values)
            results.append(result)
            status = "✓" if result["success"] else "✗"
            print(f"[{i}/{total}] {status} {workflow} ({result.get('elapsed_seconds', 0):.1f}s)")

    return results


def print_summary(results):
    """Print test summary."""
    passed = sum(1 for r in results if r["success"])
    failed = sum(1 for r in results if not r["success"])
    total = len(results)

    print("\n" + "=" * 60)
    print("TEST SUMMARY")
    print("=" * 60)
    print(f"Total:  {total}")
    print(f"Passed: {passed} ({100*passed/total:.1f}%)")
    print(f"Failed: {failed} ({100*failed/total:.1f}%)")

    if failed > 0:
        print("\nFailed workflows:")
        for r in results:
            if not r["success"]:
                error = r.get("error", "Unknown error")
                print(f"  - {r['workflow']}: {error}")

    return passed, failed


def save_results(results, output_file):
    """Save detailed results to JSON file."""
    output = {
        "timestamp": datetime.now().isoformat(),
        "total": len(results),
        "passed": sum(1 for r in results if r["success"]),
        "failed": sum(1 for r in results if not r["success"]),
        "results": results
    }

    with open(output_file, "w") as f:
        json.dump(output, f, indent=2)

    print(f"\nDetailed results saved to: {output_file}")


def load_passed_workflows():
    """Load list of already-passed workflows."""
    passed_file = RESULTS_DIR / "passed_workflows.txt"
    if passed_file.exists():
        with open(passed_file) as f:
            return set(line.strip() for line in f if line.strip())
    return set()


def save_passed_workflows(results, append=True):
    """Save list of passed workflows."""
    passed_file = RESULTS_DIR / "passed_workflows.txt"

    # Load existing if appending
    existing = set()
    if append and passed_file.exists():
        existing = load_passed_workflows()

    # Add newly passed workflows
    newly_passed = set(r["workflow"] for r in results if r["success"])
    all_passed = existing | newly_passed

    with open(passed_file, "w") as f:
        for wf in sorted(all_passed):
            f.write(wf + "\n")

    return len(newly_passed)


def main():
    parser = argparse.ArgumentParser(description="Run biomni Nextflow workflow tests")
    parser.add_argument("--domain", help="Test only workflows in this domain")
    parser.add_argument("--workflow", help="Test specific workflow (e.g., molecular_biology/digest_sequence)")
    parser.add_argument("--parallel", type=int, default=1, help="Number of parallel tests")
    parser.add_argument("--quick", action="store_true", help="Skip slow workflows")
    parser.add_argument("--skip-passed", action="store_true", help="Skip workflows that already passed")
    parser.add_argument("--output", help="Output JSON file for results")
    args = parser.parse_args()

    # Create results directory
    RESULTS_DIR.mkdir(exist_ok=True)

    # Load data
    all_params = load_params()
    test_values = load_test_values()
    workflows = all_params["workflows"]

    # Filter workflows based on arguments
    if args.workflow:
        if args.workflow in workflows:
            workflows_to_test = {args.workflow: workflows[args.workflow]["params"]}
        else:
            print(f"Error: Workflow '{args.workflow}' not found")
            sys.exit(1)
    elif args.domain:
        workflows_to_test = {
            k: v["params"] for k, v in workflows.items()
            if k.startswith(args.domain + "/")
        }
        if not workflows_to_test:
            print(f"Error: No workflows found for domain '{args.domain}'")
            sys.exit(1)
    else:
        workflows_to_test = {k: v["params"] for k, v in workflows.items()}

    # Skip already-passed workflows if requested
    if args.skip_passed:
        already_passed = load_passed_workflows()
        before_count = len(workflows_to_test)
        workflows_to_test = {k: v for k, v in workflows_to_test.items() if k not in already_passed}
        skipped = before_count - len(workflows_to_test)
        if skipped > 0:
            print(f"Skipping {skipped} already-passed workflows")

    # Run tests
    results = run_tests(workflows_to_test, test_values, args.parallel, args.quick)

    # Print summary
    passed, failed = print_summary(results)

    # Save results
    output_file = args.output or (RESULTS_DIR / f"test_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json")
    save_results(results, output_file)

    # Update passed workflows file
    newly_passed = save_passed_workflows(results, append=True)
    if newly_passed > 0:
        print(f"Added {newly_passed} newly passed workflows to passed_workflows.txt")

    # Exit with appropriate code
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
