#!/usr/bin/env python3
"""
Submit nf-core/epitopeprediction (Galaxy workflow id 12700) to AWS Batch via BioMate
POST /api/nextflow/execute, using profile **docker** (not `aws` — epitopeprediction does not
ship an `aws` profile). Reproduces Plan A in silico MHC runs on **linux/amd64** Batch without
ARM Docker platform mismatches.

Prerequisite (vendored pipeline): if `POST …/execute` fails with missing `conf/base.config`,
the nested clone may use sparse-checkout. Run once:

  bash research/anti-virus/scripts/ensure_nfcore_epitopeprediction_worktree.sh

API key: set GALAXY_API_KEY or rely on bootstrap_admin_api_key in backend/config/galaxy.yml.

Samplesheet: rows must use absolute s3:// paths in the `filename` column when running on Batch.
Template: research/anti-virus/runs/plan_a_epitope_samplesheet_template/samplesheet_s3_batch.csv
Upload the sheet (and FASTA inputs) to S3, then pass the sheet URI via --input (default matches
EXECUTION_REPORT smoke path).

Usage (from repo root):

  python3 research/anti-virus/scripts/run_plan_a_epitopeprediction_batch.py \\
    --outdir s3://biomate-nextflow-work/nextflow/outputs/plan_a_epitope_smoke/20260512/run01 \\
    --ensure-worktree

  # Custom samplesheet + tool:
  python3 research/anti-virus/scripts/run_plan_a_epitopeprediction_batch.py \\
    --outdir s3://biomate-nextflow-work/nextflow/outputs/my_user/run01 \\
    --input s3://biomate-nextflow-work/inputs/andv_campaign/plan_a_epitope_samplesheet/samplesheet.csv \\
    --tools mhcnuggets

  # Resume poll only after a transient HTTP 500 (same run_id, no second submit):
  python3 research/anti-virus/scripts/run_plan_a_epitopeprediction_batch.py \\
    --poll-run-id '<uuid-from-submit-log>' \\
    --timeout 7200
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


# Logical path resolved by _resolve_nextflow_path() → backend/nf-core-workflows/epitopeprediction/main.nf
# (same string used for Galaxy workflow id 12700 in EXECUTION_REPORT.md).
DEFAULT_NEXTFLOW_PATH = "nfcore/epitopeprediction/main.nf"

DEFAULT_SAMPLESHEET_S3 = (
    "s3://biomate-nextflow-work/inputs/andv_campaign/plan_a_epitope_samplesheet/samplesheet.csv"
)


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _load_bootstrap_api_key() -> str | None:
    gal_yml = _repo_root() / "backend" / "config" / "galaxy.yml"
    if not gal_yml.is_file():
        return None
    text = gal_yml.read_text(encoding="utf-8")
    m = re.search(r"bootstrap_admin_api_key:\s*(\S+)", text)
    return m.group(1).strip() if m else None


def _ensure_epitope_worktree() -> None:
    script = _repo_root() / "research" / "anti-virus" / "scripts" / "ensure_nfcore_epitopeprediction_worktree.sh"
    if not script.is_file():
        print(f"WARNING: missing {script} — skip worktree repair.", file=sys.stderr)
        return
    print(f"Running: bash {script}")
    r = subprocess.run(["bash", str(script)], check=False)
    if r.returncode != 0:
        sys.exit(
            f"ensure_nfcore_epitopeprediction_worktree.sh failed (exit {r.returncode}). "
            "Fix the nested repo under backend/nf-core-workflows/epitopeprediction and retry."
        )


def post_execute(
    api_url: str,
    api_key: str,
    nextflow_path: str,
    parameters: dict[str, Any],
    user_id: str,
    profile: str,
    compute_config: dict[str, Any],
    workflow_domain: str | None,
) -> dict[str, Any]:
    import urllib.error
    import urllib.request

    payload: dict[str, Any] = {
        "nextflow_path": nextflow_path,
        "parameters": parameters,
        "compute_config": compute_config,
        "user_id": user_id,
        "profile": profile,
    }
    if workflow_domain:
        payload["workflow_domain"] = workflow_domain

    req = urllib.request.Request(
        f"{api_url.rstrip('/')}/api/nextflow/execute",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-API-Key": api_key,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print(f"HTTP {e.code}: {body}", file=sys.stderr)
        raise


def get_status(api_url: str, api_key: str, run_id: str) -> dict[str, Any]:
    import urllib.request

    req = urllib.request.Request(
        f"{api_url.rstrip('/')}/api/nextflow/status/{run_id}",
        headers={"X-API-Key": api_key},
        method="GET",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def get_status_with_retry(
    api_url: str,
    api_key: str,
    run_id: str,
    *,
    max_retries: int = 8,
    retry_sleep_sec: float = 15.0,
) -> dict[str, Any]:
    """GET status with retries on transient 5xx (Galaxy under load during long Batch jobs)."""
    import urllib.error
    import urllib.request

    for attempt in range(max_retries):
        try:
            return get_status(api_url, api_key, run_id)
        except urllib.error.HTTPError as e:
            if e.code in (500, 502, 503, 504) and attempt < max_retries - 1:
                print(
                    f"  get_status: HTTP {e.code} (attempt {attempt + 1}/{max_retries}), "
                    f"sleep {retry_sleep_sec}s…",
                    flush=True,
                )
                time.sleep(retry_sleep_sec)
                continue
            raise
        except urllib.error.URLError as e:
            if attempt < max_retries - 1:
                print(f"  get_status: URLError {e!r}, retry…", flush=True)
                time.sleep(retry_sleep_sec)
                continue
            raise
    raise RuntimeError("get_status_with_retry: exhausted retries")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--api-url", default=os.environ.get("BIOMATE_API_URL", "http://127.0.0.1:8081"))
    ap.add_argument(
        "--nextflow-path",
        default=DEFAULT_NEXTFLOW_PATH,
        help=f"Path for /api/nextflow/execute (default: {DEFAULT_NEXTFLOW_PATH})",
    )
    ap.add_argument(
        "--input",
        default=DEFAULT_SAMPLESHEET_S3,
        help="S3 URI to epitopeprediction samplesheet CSV (default: Plan A smoke path on biomate-nextflow-work)",
    )
    ap.add_argument(
        "--outdir",
        default="",
        help="S3 output prefix for --outdir (required unless --poll-run-id)",
    )
    ap.add_argument(
        "--poll-run-id",
        default="",
        help="Skip POST /execute; only poll this existing run_id until terminal (recover from client 500).",
    )
    ap.add_argument("--user-id", default=os.environ.get("BIOMATE_NF_USER_ID", "plan-a-epitope-batch"))
    ap.add_argument(
        "--tools",
        default="mhcnuggets",
        help="Epitope prediction tool(s), comma-separated (default: mhcnuggets; see nextflow_schema.json)",
    )
    ap.add_argument(
        "--genome-reference",
        default="grch37",
        help="genome_reference for epitopeprediction (default: grch37)",
    )
    ap.add_argument(
        "--s3-bucket",
        default="biomate-nextflow-work",
        help="S3 bucket for compute_config (must match outdir bucket for Batch workDir)",
    )
    ap.add_argument(
        "--workflow-domain",
        default="",
        help="Optional workflow_domain string for API (omit if empty)",
    )
    ap.add_argument("--poll-interval", type=int, default=20)
    ap.add_argument("--timeout", type=int, default=7200)
    ap.add_argument(
        "--ensure-worktree",
        action="store_true",
        help="Run ensure_nfcore_epitopeprediction_worktree.sh before submitting (server-side clone must exist)",
    )
    ap.add_argument(
        "--profile",
        default="docker",
        help="Nextflow -profile value (default: docker; do NOT use aws for epitopeprediction)",
    )
    args = ap.parse_args()

    poll_only = bool(args.poll_run_id.strip())
    if not poll_only:
        if not args.outdir.strip():
            sys.exit("Provide --outdir, or use --poll-run-id for poll-only mode.")
    else:
        if args.outdir.strip():
            print("Note: --poll-run-id set; ignoring --outdir for submission.", flush=True)

    api_key = os.environ.get("GALAXY_API_KEY") or _load_bootstrap_api_key()
    if not api_key:
        sys.exit("Set GALAXY_API_KEY or ensure backend/config/galaxy.yml has bootstrap_admin_api_key.")

    if args.ensure_worktree:
        _ensure_epitope_worktree()

    outdir = args.outdir.strip()
    if not poll_only and not outdir.startswith("s3://"):
        sys.exit("--outdir must be an s3:// URI for AWS Batch outputs.")

    parameters: dict[str, Any] = {
        "input": args.input.strip(),
        "outdir": outdir,
        "tools": args.tools,
        "genome_reference": args.genome_reference,
    }

    compute_config: dict[str, Any] = {
        "executor": "awsbatch",
        "s3_bucket": args.s3_bucket,
    }

    wf_domain = args.workflow_domain.strip() or None

    if poll_only:
        run_id = args.poll_run_id.strip()
        print(f"Poll-only: run_id={run_id}")
    else:
        print("Submitting epitopeprediction to AWS Batch via BioMate API")
        print(f"  nextflow_path:   {args.nextflow_path}")
        print(f"  profile:         {args.profile}")
        print(f"  compute_config:  {compute_config}")
        print(f"  input:           {parameters['input']}")
        print(f"  outdir:          {parameters['outdir']}")
        print(f"  tools:           {parameters['tools']}")
        print(f"  genome_reference:{parameters['genome_reference']}")

        submit = post_execute(
            args.api_url,
            api_key,
            args.nextflow_path,
            parameters,
            args.user_id,
            args.profile,
            compute_config,
            wf_domain,
        )

        if submit.get("success") is False or not submit.get("run_id"):
            print(json.dumps(submit, indent=2))
            sys.exit(3)

        run_id = submit["run_id"]
        print(f"  run_id: {run_id}")

    terminal = {"completed", "succeeded", "failed", "cancelled", "error"}
    deadline = time.time() + args.timeout
    poll_n = 0
    last_status = ""
    st: dict[str, Any] = {}
    while time.time() < deadline:
        poll_n += 1
        st = get_status_with_retry(args.api_url, api_key, run_id)
        last_status = st.get("status", "")
        prog = st.get("progressPercent")
        tasks = st.get("completedTasks")
        total = st.get("totalTasks")
        print(
            f"  [{poll_n:04d}] status={last_status!r} progress={prog}% "
            f"tasks={tasks}/{total} batch={st.get('is_batch')}"
        )
        if last_status in terminal:
            break
        time.sleep(args.poll_interval)
    else:
        sys.exit(f"TIMEOUT after {args.timeout}s (last status={last_status!r})")

    print(f"Final status: {last_status}")
    if last_status not in ("completed", "succeeded"):
        tail = st.get("log_tail") or []
        if tail:
            print("log_tail:", file=sys.stderr)
            for ln in tail[-15:]:
                print(f"  {ln}", file=sys.stderr)
        print(json.dumps(st, indent=2)[:6000], file=sys.stderr)
        sys.exit(f"Run failed: status={last_status!r}")


if __name__ == "__main__":
    main()
