#!/usr/bin/env python3
"""
Science sprint — Plan A epitope prediction with multiple tools (MHCnuggets + MHCflurry).

Submits nf-core/epitopeprediction (Galaxy workflow id 12700) via POST
/api/nextflow/execute, following research/anti-virus/scripts/run_plan_a_epitopeprediction_batch.py.

Each tool writes under a dedicated S3 sub-prefix. Default tools are commercial-safe (Apache 2.0).
Optional netmhcpan requires a DTU academic tarball on S3 and is not used for product builds.

Manifest: research/anti-virus/science_sprint/runs/<timestamp>/track_plan_a_multitool/manifest.json

Usage (from repo root):

  python3 research/anti-virus/science_sprint/track_plan_a_multitool.py --ensure-worktree

  python3 research/anti-virus/science_sprint/track_plan_a_multitool.py \\
    --outdir s3://biomate-nextflow-work/nextflow/outputs/plan_a_science_sprint/20260527T120000Z/ \\
    --sequential
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_NEXTFLOW_PATH = "nfcore/epitopeprediction/main.nf"
TEMPLATE_DIR = ROOT / "research/anti-virus/runs/plan_a_epitope_samplesheet_template"
DEFAULT_SAMPLESHEET_S3 = (
    "s3://biomate-nextflow-work/inputs/andv_campaign/plan_a_epitope_samplesheet/samplesheet.csv"
)
# Licensed DTU tarball (not in git). Upload after academic registration:
#   aws s3 cp netMHCpan-4.1b.Linux.tar.gz s3://biomate-nextflow-work/inputs/andv_campaign/netmhcpan/
DEFAULT_NETMHCPAN_TARBALL_S3 = (
    "s3://biomate-nextflow-work/inputs/andv_campaign/netmhcpan/netMHCpan-4.1b.Linux.tar.gz"
)
DEFAULT_WORKFLOW_DOMAIN = "epitope_prediction"
TOOLS = ("mhcnuggets", "mhcflurry")
TERMINAL = {"completed", "succeeded", "failed", "cancelled", "error"}
_NETMHCPAN_FAIL_MARKERS = (
    "netmhcpan_path not specified",
    "WorkflowScriptErrorException",
)
_PREDICTION_OUTPUT_SUFFIXES = (".tsv", ".xls", ".csv")


def log(msg: str) -> None:
    print(msg, flush=True)


def load_api_key() -> str:
    if os.environ.get("GALAXY_API_KEY"):
        return os.environ["GALAXY_API_KEY"]
    gal_yml = ROOT / "backend" / "config" / "galaxy.yml"
    if not gal_yml.is_file():
        raise SystemExit("Set GALAXY_API_KEY or ensure backend/config/galaxy.yml has bootstrap_admin_api_key.")
    text = gal_yml.read_text(encoding="utf-8")
    match = re.search(r"bootstrap_admin_api_key:\s*(\S+)", text)
    if not match:
        raise SystemExit("Set GALAXY_API_KEY or ensure backend/config/galaxy.yml has bootstrap_admin_api_key.")
    return match.group(1).strip()


def ensure_epitope_worktree() -> None:
    script = ROOT / "research" / "anti-virus" / "scripts" / "ensure_nfcore_epitopeprediction_worktree.sh"
    if not script.is_file():
        log(f"WARNING: missing {script} — skip worktree repair.")
        return
    log(f"Running: bash {script}")
    result = subprocess.run(["bash", str(script)], check=False)
    if result.returncode != 0:
        raise SystemExit(
            f"ensure_nfcore_epitopeprediction_worktree.sh failed (exit {result.returncode}). "
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
        headers={"Content-Type": "application/json", "X-API-Key": api_key},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        log(f"HTTP {exc.code}: {body}")
        raise


def get_status(api_url: str, api_key: str, run_id: str) -> dict[str, Any]:
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
    for attempt in range(max_retries):
        try:
            return get_status(api_url, api_key, run_id)
        except urllib.error.HTTPError as exc:
            if exc.code in (500, 502, 503, 504) and attempt < max_retries - 1:
                log(
                    f"  get_status: HTTP {exc.code} (attempt {attempt + 1}/{max_retries}), "
                    f"sleep {retry_sleep_sec}s…"
                )
                time.sleep(retry_sleep_sec)
                continue
            raise
        except urllib.error.URLError as exc:
            if attempt < max_retries - 1:
                log(f"  get_status: URLError {exc!r}, retry…")
                time.sleep(retry_sleep_sec)
                continue
            raise
    raise RuntimeError("get_status_with_retry: exhausted retries")


def s3_object_exists(s3_uri: str) -> bool:
    if not s3_uri.startswith("s3://"):
        return False
    no_scheme = s3_uri[5:]
    bucket, _, key = no_scheme.partition("/")
    if not bucket or not key:
        return False
    try:
        proc = subprocess.run(
            ["aws", "s3", "ls", f"s3://{bucket}/{key}"],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        return proc.returncode == 0 and bool(proc.stdout.strip())
    except (OSError, subprocess.TimeoutExpired):
        return False


def resolve_netmhcpan_path(explicit: str) -> str:
    path = (explicit or os.environ.get("BIOMATE_NETMHCPAN_PATH") or DEFAULT_NETMHCPAN_TARBALL_S3).strip()
    if not path:
        raise SystemExit(
            "NetMHCpan requires --netmhcpan-path or BIOMATE_NETMHCPAN_PATH "
            f"(default: {DEFAULT_NETMHCPAN_TARBALL_S3}). "
            "Download netMHCpan-4.1b.Linux.tar.gz from DTU and upload to that S3 key."
        )
    if not path.startswith("s3://"):
        raise SystemExit(f"--netmhcpan-path must be an s3:// URI for AWS Batch (got {path!r}).")
    if not s3_object_exists(path):
        raise SystemExit(
            f"NetMHCpan tarball not found at {path}. "
            "Upload netMHCpan-4.1b.Linux.tar.gz (DTU academic license) before running netmhcpan."
        )
    return path


def epitope_run_looks_failed(status_payload: dict[str, Any], tool: str) -> str | None:
    """Return an error string when API status looks successful but outputs/logs say otherwise."""
    api_status = status_payload.get("terminal_status") or status_payload.get("status", "")
    if api_status not in ("completed", "succeeded"):
        return None
    rc = status_payload.get("returncode")
    if rc not in (0, None):
        return f"returncode={rc}"
    s3_files = status_payload.get("s3_output_files") or []
    has_prediction = any(
        str(f.get("filename", "")).endswith(_PREDICTION_OUTPUT_SUFFIXES)
        for f in s3_files
    )
    total = status_payload.get("totalTasks") or status_payload.get("totalSteps") or 0
    duration = status_payload.get("duration_s")
    if tool == "netmhcpan" and not has_prediction and (total == 0 or duration is not None and duration < 300):
        log_text = "\n".join(str(line) for line in (status_payload.get("log_tail") or []))
        for marker in _NETMHCPAN_FAIL_MARKERS:
            if marker in log_text:
                return marker
        return "no NetMHCpan prediction outputs on S3 (only pipeline_info/)"
    if tool in ("mhcnuggets", "mhcflurry") and not has_prediction and total == 0:
        return f"no {tool} prediction outputs on S3"
    return None


def resolve_samplesheet_input(explicit: str, template_dir: Path) -> str:
    if explicit.strip():
        return explicit.strip()
    batch_csv = template_dir / "samplesheet_s3_batch.csv"
    if batch_csv.is_file():
        for line in batch_csv.read_text(encoding="utf-8").splitlines()[1:]:
            parts = line.split(",")
            if len(parts) >= 4 and parts[3].strip().startswith("s3://"):
                return parts[3].strip()
    return DEFAULT_SAMPLESHEET_S3


def poll_until_terminal(
    api_url: str,
    api_key: str,
    run_id: str,
    *,
    tool: str,
    poll_interval: int,
    timeout: int,
) -> dict[str, Any]:
    deadline = time.time() + timeout
    poll_n = 0
    last_status = ""
    status_payload: dict[str, Any] = {}
    while time.time() < deadline:
        poll_n += 1
        status_payload = get_status_with_retry(api_url, api_key, run_id)
        last_status = status_payload.get("status", "")
        prog = status_payload.get("progressPercent")
        tasks = status_payload.get("completedTasks")
        total = status_payload.get("totalTasks")
        log(
            f"  [{tool}] poll {poll_n:04d} status={last_status!r} progress={prog}% "
            f"tasks={tasks}/{total} batch={status_payload.get('is_batch')}"
        )
        if last_status in TERMINAL:
            break
        time.sleep(poll_interval)
    else:
        status_payload["error"] = f"TIMEOUT after {timeout}s (last status={last_status!r})"
    status_payload["terminal_status"] = last_status
    return status_payload


def run_tool_job(
    tool: str,
    *,
    api_url: str,
    api_key: str,
    nextflow_path: str,
    samplesheet: str,
    outdir_base: str,
    user_id: str,
    profile: str,
    compute_config: dict[str, Any],
    genome_reference: str,
    workflow_domain: str | None,
    netmhcpan_path: str | None,
    poll_interval: int,
    timeout: int,
) -> dict[str, Any]:
    outdir = f"{outdir_base.rstrip('/')}/{tool}/"
    parameters = {
        "input": samplesheet,
        "outdir": outdir,
        "tools": tool,
        "genome_reference": genome_reference,
    }
    if tool == "netmhcpan":
        if not netmhcpan_path:
            raise ValueError("netmhcpan_path is required for netmhcpan runs")
        parameters["netmhcpan_path"] = netmhcpan_path
    record: dict[str, Any] = {
        "tool": tool,
        "parameters": parameters,
        "status": "pending",
    }
    log(f"[{tool}] submitting epitopeprediction outdir={outdir}")
    try:
        submit = post_execute(
            api_url,
            api_key,
            nextflow_path,
            parameters,
            f"{user_id}-{tool}",
            profile,
            compute_config,
            workflow_domain,
        )
    except Exception as exc:  # noqa: BLE001 - capture per-tool failure for manifest
        record["status"] = "submit_error"
        record["error"] = repr(exc)
        log(f"[{tool}] submit failed: {exc!r}")
        return record

    record["submit"] = submit
    if submit.get("success") is False or not submit.get("run_id"):
        record["status"] = "submit_rejected"
        record["error"] = submit.get("error") or "missing run_id"
        log(f"[{tool}] submit rejected: {json.dumps(submit)[:1200]}")
        return record

    run_id = submit["run_id"]
    record["run_id"] = run_id
    log(f"[{tool}] run_id={run_id}")
    status_payload = poll_until_terminal(
        api_url,
        api_key,
        run_id,
        tool=tool,
        poll_interval=poll_interval,
        timeout=timeout,
    )
    record["latest_status"] = status_payload
    terminal = status_payload.get("terminal_status", "")
    record["status"] = terminal or status_payload.get("status", "unknown")
    false_ok = epitope_run_looks_failed(status_payload, tool)
    if false_ok:
        record["status"] = "failed"
        record["error"] = f"false success: {false_ok}"
        log(f"[{tool}] {record['error']}")
    elif record["status"] not in ("completed", "succeeded"):
        record["error"] = status_payload.get("error") or f"terminal status={record['status']!r}"
    tail = status_payload.get("log_tail") or []
    if tail:
        record["log_tail"] = tail[-15:]
    return record


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--api-url", default=os.environ.get("BIOMATE_API_URL", "http://127.0.0.1:8081"))
    ap.add_argument("--nextflow-path", default=DEFAULT_NEXTFLOW_PATH)
    ap.add_argument(
        "--input",
        default="",
        help="S3 samplesheet URI (default: s3 path from plan_a_epitope_samplesheet_template/samplesheet_s3_batch.csv)",
    )
    ap.add_argument(
        "--samplesheet-template-dir",
        type=Path,
        default=TEMPLATE_DIR,
        help="Local template dir used when --input is omitted",
    )
    ap.add_argument(
        "--outdir",
        default="",
        help="S3 prefix (default: s3://biomate-nextflow-work/nextflow/outputs/plan_a_science_sprint/<timestamp>/)",
    )
    ap.add_argument("--user-id", default=os.environ.get("BIOMATE_NF_USER_ID", "plan-a-science-sprint"))
    ap.add_argument("--genome-reference", default="grch37")
    ap.add_argument("--s3-bucket", default="biomate-nextflow-work")
    ap.add_argument(
        "--workflow-domain",
        default=DEFAULT_WORKFLOW_DOMAIN,
        help=f"workflow_domain for /api/nextflow/execute (default: {DEFAULT_WORKFLOW_DOMAIN})",
    )
    ap.add_argument(
        "--netmhcpan-path",
        default="",
        help=(
            "S3 URI to netMHCpan-4.1b.Linux.tar.gz (required for netmhcpan; "
            f"default env BIOMATE_NETMHCPAN_PATH or {DEFAULT_NETMHCPAN_TARBALL_S3})"
        ),
    )
    ap.add_argument("--profile", default="docker")
    ap.add_argument("--poll-interval", type=int, default=20)
    ap.add_argument("--timeout", type=int, default=7200)
    ap.add_argument("--ensure-worktree", action="store_true")
    ap.add_argument(
        "--sequential",
        action="store_true",
        help="Run tools one after another (default: parallel threads)",
    )
    ap.add_argument(
        "--tools",
        default=",".join(TOOLS),
        help=f"Comma-separated epitope tools (default: {','.join(TOOLS)})",
    )
    args = ap.parse_args()

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    outdir_base = args.outdir.strip() or (
        f"s3://biomate-nextflow-work/nextflow/outputs/plan_a_science_sprint/{stamp}/"
    )
    if not outdir_base.startswith("s3://"):
        raise SystemExit("--outdir must be an s3:// URI for AWS Batch outputs.")

    manifest_dir = ROOT / "research/anti-virus/science_sprint/runs" / stamp / "track_plan_a_multitool"
    manifest_dir.mkdir(parents=True, exist_ok=True)

    api_key = load_api_key()
    if args.ensure_worktree:
        ensure_epitope_worktree()

    samplesheet = resolve_samplesheet_input(args.input, args.samplesheet_template_dir.resolve())
    tools = [t.strip() for t in args.tools.split(",") if t.strip()]
    compute_config = {"executor": "awsbatch", "s3_bucket": args.s3_bucket}
    wf_domain = args.workflow_domain.strip() or DEFAULT_WORKFLOW_DOMAIN
    netmhcpan_tarball: str | None = None
    if "netmhcpan" in tools:
        netmhcpan_tarball = resolve_netmhcpan_path(args.netmhcpan_path)
        log(f"  netmhcpan_path: {netmhcpan_tarball}")

    log(f"Science sprint Plan A multitool stamp={stamp}")
    log(f"  samplesheet: {samplesheet}")
    log(f"  outdir_base: {outdir_base}")
    log(f"  tools:       {tools}")
    log(f"  manifest:    {manifest_dir}")

    common = {
        "api_url": args.api_url,
        "api_key": api_key,
        "nextflow_path": args.nextflow_path,
        "samplesheet": samplesheet,
        "outdir_base": outdir_base,
        "user_id": args.user_id,
        "profile": args.profile,
        "compute_config": compute_config,
        "genome_reference": args.genome_reference,
        "workflow_domain": wf_domain,
        "netmhcpan_path": netmhcpan_tarball,
        "poll_interval": args.poll_interval,
        "timeout": args.timeout,
    }

    runs: list[dict[str, Any]] = []
    if args.sequential:
        for tool in tools:
            runs.append(run_tool_job(tool, **common))
    else:
        with ThreadPoolExecutor(max_workers=len(tools)) as pool:
            futures = {pool.submit(run_tool_job, tool, **common): tool for tool in tools}
            for future in as_completed(futures):
                runs.append(future.result())

    runs.sort(key=lambda r: r.get("tool", ""))
    manifest = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "stamp": stamp,
        "nextflow_path": args.nextflow_path,
        "samplesheet": samplesheet,
        "samplesheet_template_dir": str(args.samplesheet_template_dir.resolve()),
        "outdir_base": outdir_base,
        "profile": args.profile,
        "compute_config": compute_config,
        "parallel": not args.sequential,
        "runs": runs,
    }
    manifest_path = manifest_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    log(f"Manifest -> {manifest_path}")
    log(json.dumps({r["tool"]: r["status"] for r in runs}, indent=2))

    by_tool = {r["tool"]: r for r in runs}
    mhc = by_tool.get("mhcnuggets")
    net = by_tool.get("netmhcpan")

    if mhc and mhc.get("status") not in ("completed", "succeeded"):
        raise SystemExit(f"MHCnuggets run failed: status={mhc.get('status')!r}")

    if net and net.get("status") not in ("completed", "succeeded"):
        log(f"WARNING: NetMHCpan run did not succeed (status={net.get('status')!r}); continuing.")

    optional_tools = {"netmhcpan", "netmhciipan"}
    failed_required = [
        r for r in runs if r["tool"] not in optional_tools and r.get("status") not in ("completed", "succeeded")
    ]
    if failed_required:
        raise SystemExit(f"Required tool run(s) failed: {[r['tool'] for r in failed_required]}")


if __name__ == "__main__":
    main()
