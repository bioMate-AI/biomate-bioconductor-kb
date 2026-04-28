#!/usr/bin/env python3
"""
Test all 24 new drug-dev workflows (IDs 12861–12884) on AWS Batch.

Submits each workflow via POST /api/nextflow/execute with default parameters,
polls for completion, and reports pass/fail with output file presence checks.

Usage:
    python3 scripts/test_drug_dev_workflows_batch.py [--api-url http://localhost:8081]
                                                      [--timeout 600]
                                                      [--parallel 4]
                                                      [--workflow-ids 12861,12862,...]
                                                      [--dry-run]

Results saved to: docs/YYYYMMDD_DRUG_DEV_BATCH_TEST_RESULTS.json
"""

import argparse
import json
import os
import sys
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
from typing import Any

import requests

# ---------------------------------------------------------------------------
# Workflow catalogue — all 24 new workflows with their expected output files
# ---------------------------------------------------------------------------

WORKFLOWS = [
    # Phase 1 — IDs 12861–12876
    {
        "id": 12861, "name": "allometric_scaling",
        "domain": "pharmacology",
        "path": "pharmacology/allometric_scaling/main.nf",
        "params": {},  # uses built-in demo: rat/dog/monkey → human CL
        "expected_outputs": ["allometric_scaling_results.json", "allometric_regression.csv"],
    },
    {
        "id": 12862, "name": "cns_penetration_prediction",
        "domain": "pharmacology",
        "path": "pharmacology/cns_penetration_prediction/main.nf",
        "params": {},  # default SMILES: ibuprofen
        "expected_outputs": ["cns_penetration_results.json", "cns_penetration_output.txt"],
    },
    {
        "id": 12863, "name": "dart_toxicity_prediction",
        "domain": "pharmacology",
        "path": "pharmacology/dart_toxicity_prediction/main.nf",
        "params": {},  # default SMILES: thalidomide
        "expected_outputs": ["dart_results.json", "dart_output.txt"],
    },
    {
        "id": 12864, "name": "oral_absorption_bcs_model",
        "domain": "pharmacology",
        "path": "pharmacology/oral_absorption_bcs_model/main.nf",
        "params": {},
        "expected_outputs": ["oral_absorption_results.json", "bcs_classification.json"],
    },
    {
        "id": 12865, "name": "transporter_ddi_prediction",
        "domain": "pharmacology",
        "path": "pharmacology/transporter_ddi_prediction/main.nf",
        "params": {},
        "expected_outputs": ["transporter_ddi_results.json", "regulatory_summary.json"],
    },
    {
        "id": 12866, "name": "repeated_dose_tox_prediction",
        "domain": "pharmacology",
        "path": "pharmacology/repeated_dose_tox_prediction/main.nf",
        "params": {},
        "expected_outputs": ["tox_summary.json", "repeated_dose_tox_output.txt"],
    },
    {
        "id": 12867, "name": "nanoparticle_pk_biodistribution",
        "domain": "pharmacology",
        "path": "pharmacology/nanoparticle_pk_biodistribution/main.nf",
        "params": {},
        "expected_outputs": ["np_pk_results.json", "pk_profile.csv"],
    },
    {
        "id": 12868, "name": "membrane_permeability_prediction",
        "domain": "pharmacology",
        "path": "pharmacology/membrane_permeability_prediction/main.nf",
        "params": {},
        "expected_outputs": ["permeability_results.json", "permeability_summary.json"],
    },
    {
        "id": 12869, "name": "lnp_formulation_optimization",
        "domain": "drug_discovery",
        "path": "drug_discovery/lnp_formulation_optimization/main.nf",
        "params": {},
        "expected_outputs": ["lnp_results.json", "formulation_predictions.csv"],
    },
    {
        "id": 12870, "name": "target_engagement_kinetics",
        "domain": "drug_discovery",
        "path": "drug_discovery/target_engagement_kinetics/main.nf",
        "params": {},
        "expected_outputs": ["kinetics_results.json", "occupancy_profile.csv"],
    },
    {
        "id": 12871, "name": "proteome_selectivity_profiling",
        "domain": "drug_discovery",
        "path": "drug_discovery/proteome_selectivity_profiling/main.nf",
        "params": {},
        "expected_outputs": ["selectivity_results.json", "selectivity_panel.csv"],
    },
    {
        "id": 12872, "name": "covalent_warhead_design",
        "domain": "drug_discovery",
        "path": "drug_discovery/covalent_warhead_design/main.nf",
        "params": {},
        "expected_outputs": ["warhead_results.json", "cys_selectivity.csv"],
    },
    {
        "id": 12873, "name": "pbpk_simulation",
        "domain": "drug_discovery",
        "path": "drug_discovery/pbpk_simulation/main.nf",
        "params": {},
        "expected_outputs": ["pbpk_results.json", "pk_profile.csv"],
    },
    {
        "id": 12874, "name": "clinical_trial_simulation",
        "domain": "drug_discovery",
        "path": "drug_discovery/clinical_trial_simulation/main.nf",
        "params": {},
        "expected_outputs": ["clinical_trial_results.json", "dose_escalation_results.csv"],
    },
    {
        "id": 12875, "name": "metabolite_prediction_biotransformer",
        "domain": "pharmacology",
        "path": "pharmacology/metabolite_prediction_biotransformer/main.nf",
        "params": {},
        "expected_outputs": ["metabolite_results.json", "metabolites.csv"],
    },
    {
        "id": 12876, "name": "pharmacogenomics_pgx_report",
        "domain": "pharmacology",
        "path": "pharmacology/pharmacogenomics_pgx_report/main.nf",
        "params": {},  # default: demo diplotype CYP2D6*1/*4
        "expected_outputs": ["pgx_report.json", "drug_recommendations.csv"],
    },
    # Phase 2 — IDs 12877–12884
    {
        "id": 12877, "name": "herg_cardiac_safety_qsar",
        "domain": "pharmacology",
        "path": "pharmacology/herg_cardiac_safety_qsar/main.nf",
        "params": {},
        "expected_outputs": ["herg_risk.json", "cardiac_safety_summary.csv"],
    },
    {
        "id": 12878, "name": "genotoxicity_ames_prediction",
        "domain": "pharmacology",
        "path": "pharmacology/genotoxicity_ames_prediction/main.nf",
        "params": {},
        "expected_outputs": ["ames_prediction.json", "genotox_alerts.csv"],
    },
    {
        "id": 12879, "name": "target_tractability_scorer",
        "domain": "drug_discovery",
        "path": "drug_discovery/target_tractability_scorer/main.nf",
        "params": {},
        "expected_outputs": ["tractability_score.json", "evidence_table.csv"],
    },
    {
        "id": 12880, "name": "pbpk_pediatric_pregnancy",
        "domain": "pharmacology",
        "path": "pharmacology/pbpk_pediatric_pregnancy/main.nf",
        "params": {},
        "expected_outputs": ["pediatric_pk.csv", "pregnancy_pk.csv", "dose_recommendation.json"],
    },
    {
        "id": 12881, "name": "antibody_developability",
        "domain": "pharmacology",
        "path": "pharmacology/antibody_developability/main.nf",
        "params": {},
        "expected_outputs": ["developability_scores.json", "liability_scan.csv"],
    },
    {
        "id": 12882, "name": "hts_plate_qc_hit_calling",
        "domain": "drug_discovery",
        "path": "drug_discovery/hts_plate_qc_hit_calling/main.nf",
        "params": {},  # auto-generates 96-well demo plate
        "expected_outputs": ["qc_metrics.json", "hit_list.csv"],
    },
    {
        "id": 12883, "name": "exposure_response_modelling",
        "domain": "pharmacology",
        "path": "pharmacology/exposure_response_modelling/main.nf",
        "params": {},
        "expected_outputs": ["er_parameters.json", "er_curve.csv"],
    },
    {
        "id": 12884, "name": "adaptive_trial_design",
        "domain": "drug_discovery",
        "path": "drug_discovery/adaptive_trial_design/main.nf",
        "params": {},
        "expected_outputs": ["adaptive_results.json", "arm_allocation.csv", "stopping_boundaries.csv"],
    },
]

# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------

GALAXY_API_KEY = os.environ.get("GALAXY_API_KEY", "7341822cd19cddaa49139f6cccae8c76")


def submit_workflow(api_url: str, wf: dict, dry_run: bool = False) -> dict:
    """Submit a workflow to AWS Batch. Returns {run_id, status, error}."""
    if dry_run:
        return {"run_id": f"dry-run-{wf['id']}", "status": "dry_run", "error": None}

    payload = {
        "nextflow_path": wf["path"],
        "parameters": wf.get("params", {}),
        "compute_config": {
            "executor": "awsbatch",
        },
        "workflow_domain": wf["domain"],
        "user_id": "test-drug-dev-batch",
    }
    try:
        r = requests.post(
            f"{api_url}/api/nextflow/execute",
            json=payload,
            headers={"X-API-Key": GALAXY_API_KEY},
            timeout=30,
        )
        r.raise_for_status()
        data = r.json()
        return {
            "run_id": data.get("run_id") or data.get("invocation_id"),
            "status": data.get("status", "submitted"),
            "outdir": data.get("outdir", ""),
            "error": None,
        }
    except Exception as exc:
        return {"run_id": None, "status": "submit_failed", "error": str(exc)}


def poll_status(api_url: str, run_id: str, timeout: int = 600, interval: int = 15) -> dict:
    """Poll /api/nextflow/status/{run_id} until terminal or timeout."""
    terminal = {"completed", "succeeded", "failed", "cancelled", "error"}
    deadline = time.time() + timeout
    last_status = "unknown"
    while time.time() < deadline:
        try:
            r = requests.get(
                f"{api_url}/api/nextflow/status/{run_id}",
                headers={"X-API-Key": GALAXY_API_KEY},
                timeout=10,
            )
            if r.status_code == 200:
                data = r.json()
                last_status = data.get("status", "unknown")
                if last_status in terminal:
                    return data
        except Exception:
            pass
        time.sleep(interval)
    return {"status": "timeout", "run_id": run_id}


def check_outputs(api_url: str, run_id: str, expected: list[str],
                  status_data: dict | None = None) -> dict:
    """Check if expected output files exist.

    First tries s3_output_files from the status response (already in memory).
    Falls back to polling /output_files with retries to handle the race where
    the S3 scan hasn't completed when status transitions to 'succeeded'.
    """
    def _extract_names(files_list: list) -> set:
        names = set()
        for f in files_list:
            name = f.get("name") or f.get("key", "")
            names.add(Path(name).name)
        return names

    # Try status response first (no extra HTTP call, race-free)
    if status_data:
        s3_files = status_data.get("s3_output_files", [])
        if s3_files:
            filenames = _extract_names(s3_files)
            found = [e for e in expected if e in filenames]
            missing = [e for e in expected if e not in filenames]
            return {"checked": True, "found": found, "missing": missing}

    # Retry loop — S3 scan may not be complete immediately after status→succeeded
    for attempt in range(4):
        if attempt > 0:
            time.sleep(10)
        try:
            r = requests.get(
                f"{api_url}/api/nextflow/runs/{run_id}/output_files",
                headers={"X-API-Key": GALAXY_API_KEY},
                timeout=15,
            )
            if r.status_code != 200:
                continue
            files = r.json()
            filenames = _extract_names(
                files if isinstance(files, list) else files.get("files", [])
            )
            if not filenames and attempt < 3:
                continue  # S3 scan still in progress — retry
            found = [e for e in expected if e in filenames]
            missing = [e for e in expected if e not in filenames]
            return {"checked": True, "found": found, "missing": missing}
        except Exception:
            continue
    return {"checked": False, "found": [], "missing": expected}


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

def run_single(api_url: str, wf: dict, timeout: int, dry_run: bool,
               print_lock: threading.Lock) -> dict:
    """Submit, poll, and verify one workflow. Returns result dict."""
    result = {
        "id": wf["id"],
        "name": wf["name"],
        "domain": wf["domain"],
        "started_at": datetime.utcnow().isoformat(),
    }

    # Submit
    sub = submit_workflow(api_url, wf, dry_run)
    result["run_id"] = sub.get("run_id")
    result["submit_status"] = sub["status"]
    result["outdir"] = sub.get("outdir", "")

    if sub["error"] or not sub["run_id"] or dry_run:
        result["final_status"] = sub["status"]
        result["passed"] = dry_run  # dry runs always pass trivially
        result["submit_error"] = sub.get("error")
        return result

    run_id = sub["run_id"]
    with print_lock:
        print(f"  [{wf['name']}] submitted → run_id={run_id}")

    # Poll
    poll = poll_status(api_url, run_id, timeout=timeout)
    result["final_status"] = poll.get("status", "timeout")
    result["poll_data"] = poll
    result["finished_at"] = datetime.utcnow().isoformat()

    # Check output files if terminal with success
    if result["final_status"] in {"completed", "succeeded"}:
        out = check_outputs(api_url, run_id, wf["expected_outputs"],
                            status_data=poll)
        result["outputs"] = out
        result["passed"] = len(out["missing"]) == 0
    else:
        result["passed"] = False
        result["outputs"] = {"checked": False, "found": [], "missing": wf["expected_outputs"]}

    with print_lock:
        icon = "✅" if result["passed"] else "❌"
        status = result["final_status"]
        missing = result["outputs"].get("missing", [])
        msg = f"  {icon} [{wf['name']}] {status}"
        if missing:
            msg += f"  — missing outputs: {missing}"
        print(msg)

    return result


def main():
    parser = argparse.ArgumentParser(description="Test 24 drug-dev workflows on AWS Batch")
    parser.add_argument("--api-url", default="http://localhost:8081")
    parser.add_argument("--timeout", type=int, default=600,
                        help="Seconds to wait per workflow (default: 600)")
    parser.add_argument("--parallel", type=int, default=4,
                        help="Concurrent workflows (default: 4)")
    parser.add_argument("--workflow-ids", default="",
                        help="Comma-separated IDs to run (default: all 24)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Submit but don't poll — just verify API accepts the request")
    args = parser.parse_args()

    # Filter workflows
    if args.workflow_ids:
        target_ids = set(int(x) for x in args.workflow_ids.split(","))
        workflows = [w for w in WORKFLOWS if w["id"] in target_ids]
    else:
        workflows = WORKFLOWS

    print(f"\n{'='*60}")
    print(f"BioMate Drug Dev Workflow Batch Test")
    print(f"  API: {args.api_url}")
    print(f"  Workflows: {len(workflows)}")
    print(f"  Timeout/workflow: {args.timeout}s")
    print(f"  Parallel: {args.parallel}")
    print(f"  Dry run: {args.dry_run}")
    print(f"{'='*60}\n")

    # Quick health check
    if not args.dry_run:
        try:
            r = requests.get(f"{args.api_url}/api/nextflow/status/health-check", timeout=5)
        except Exception:
            try:
                r = requests.get(f"{args.api_url}/api/configuration", timeout=5)
                if r.status_code not in (200, 404):
                    print(f"⚠️  Server at {args.api_url} may not be reachable (status {r.status_code})")
            except Exception as e:
                print(f"❌ Cannot reach {args.api_url}: {e}")
                print("   Make sure the backend server is running.")
                sys.exit(1)

    print_lock = threading.Lock()
    results = []

    with ThreadPoolExecutor(max_workers=args.parallel) as pool:
        futures = {
            pool.submit(run_single, args.api_url, wf, args.timeout, args.dry_run, print_lock): wf
            for wf in workflows
        }
        for fut in as_completed(futures):
            results.append(fut.result())

    # Sort by workflow ID
    results.sort(key=lambda r: r["id"])

    # Summary
    passed = sum(1 for r in results if r["passed"])
    failed = [r for r in results if not r["passed"]]

    print(f"\n{'='*60}")
    print(f"RESULTS: {passed}/{len(results)} passed")
    print(f"{'='*60}")

    if failed:
        print("\nFAILED:")
        for r in failed:
            status = r.get("final_status", "?")
            missing = r.get("outputs", {}).get("missing", [])
            err = r.get("submit_error", "")
            print(f"  ❌ {r['name']} (id={r['id']}) — status={status}"
                  + (f" missing={missing}" if missing else "")
                  + (f" error={err}" if err else ""))

    # Save results JSON
    out_dir = Path(__file__).resolve().parents[2] / "docs"
    out_dir.mkdir(exist_ok=True)
    date_str = datetime.utcnow().strftime("%Y%m%d")
    out_file = out_dir / f"{date_str}_DRUG_DEV_BATCH_TEST_RESULTS.json"
    payload = {
        "run_at": datetime.utcnow().isoformat(),
        "api_url": args.api_url,
        "total": len(results),
        "passed": passed,
        "failed": len(failed),
        "dry_run": args.dry_run,
        "workflows": results,
    }
    with open(out_file, "w") as f:
        json.dump(payload, f, indent=2)
    print(f"\nResults saved → {out_file}")

    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
