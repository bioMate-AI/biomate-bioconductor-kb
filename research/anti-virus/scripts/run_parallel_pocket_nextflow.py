#!/usr/bin/env python3
"""Submit and validate parallel BioMate Nextflow pocket-detection runs."""

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
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
NF_PATH = "nextflow_nfcore/subworkflows/drug_discovery/pocket_detection_druggability/main.nf"


def log(message: str) -> None:
    print(message, flush=True)


def load_api_key() -> str:
    if os.environ.get("GALAXY_API_KEY"):
        return os.environ["GALAXY_API_KEY"]
    text = (ROOT / "backend/config/galaxy.yml").read_text(encoding="utf-8")
    match = re.search(r"bootstrap_admin_api_key:\s*(\S+)", text)
    if not match:
        raise SystemExit("Set GALAXY_API_KEY or configure bootstrap_admin_api_key.")
    return match.group(1).strip()


def request_json(api_url: str, api_key: str, method: str, path: str, payload: Any = None, timeout: int = 120) -> Any:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        api_url.rstrip("/") + path,
        data=data,
        method=method,
        headers={"Content-Type": "application/json", "X-API-Key": api_key},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def download_selected_outputs(files: list[Any], dest_dir: Path) -> list[str]:
    downloaded: list[str] = []
    for item in files:
        if not isinstance(item, dict):
            continue
        name = item.get("filename") or item.get("name") or Path(item.get("key", "")).name
        uri = item.get("s3_uri") or ""
        if not name or not uri or name.endswith("/"):
            continue
        if not (
            name.endswith(("_pockets.json", "_qc_result.json", "_druggability_report.tsv", "_top_pocket.pdb"))
            or name in {"workflow-trace.txt", "report.html"}
        ):
            continue
        dest = dest_dir / name
        result = subprocess.run(["aws", "s3", "cp", uri, str(dest)], capture_output=True, text=True, check=False)
        if result.returncode == 0:
            downloaded.append(str(dest))
            log(f"  downloaded {dest.name}")
        else:
            log(f"  failed to download {uri}: {result.stderr[:500]}")
    return downloaded


def validate_run(dest_dir: Path) -> dict[str, Any]:
    pockets_files = sorted(dest_dir.glob("*_pockets.json"))
    qc_files = sorted(dest_dir.glob("*_qc_result.json"))
    if not pockets_files or not qc_files:
        return {"ok": False, "error": "missing *_pockets.json or *_qc_result.json"}

    pockets = json.loads(pockets_files[0].read_text(encoding="utf-8"))
    qc = json.loads(qc_files[0].read_text(encoding="utf-8"))
    status = qc.get("status")
    return {
        "ok": int(pockets.get("num_pockets", 0)) >= 1 and status in {"PASS", "WARN", "FAIL"},
        "num_pockets": pockets.get("num_pockets"),
        "qc_status": status,
        "top_druggability_score": qc.get("top_druggability_score"),
        "top_volume_A3": qc.get("top_volume"),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--api-url", default=os.environ.get("BIOMATE_API_URL", "http://127.0.0.1:8081"))
    parser.add_argument("--timeout", type=int, default=1200)
    parser.add_argument("--poll-interval", type=int, default=20)
    args = parser.parse_args()

    api_key = load_api_key()
    run_root = ROOT / "research/anti-virus/runs" / f"parallel_pocket_{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
    run_root.mkdir(parents=True, exist_ok=True)

    runs: list[dict[str, Any]] = [
        {
            "label": "andv_9p3i",
            "pdb_input": "s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb",
            "min_druggability": 0.35,
            "min_volume": 200.0,
            "user_id": "direct-andv-9p3i",
        },
        {
            "label": "control_1iep",
            "pdb_input": "1IEP",
            "min_druggability": 0.35,
            "min_volume": 200.0,
            "user_id": "direct-control-1iep",
        },
    ]

    log(f"[parallel-pocket] run_root={run_root}")
    for run in runs:
        payload = {
            "nextflow_path": NF_PATH,
            "parameters": {
                "pdb_input": run["pdb_input"],
                "min_druggability": run["min_druggability"],
                "min_volume": run["min_volume"],
            },
            "compute_config": {"executor": "awsbatch", "s3_bucket": "biomate-nextflow-work"},
            "workflow_domain": "drug_discovery",
            "user_id": run["user_id"],
            "profile": "aws",
        }
        try:
            submit = request_json(args.api_url, api_key, "POST", "/api/nextflow/execute", payload, timeout=180)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise SystemExit(f"submit failed for {run['label']}: HTTP {exc.code}: {body[:2000]}") from exc
        run["submit"] = submit
        run["run_id"] = submit.get("run_id")
        run["outdir"] = (submit.get("outputs") or {}).get("outdir") or submit.get("outdir")
        run["status"] = "submitted"
        log(f"[parallel-pocket] submitted {run['label']}: run_id={run['run_id']} outdir={run['outdir']}")
        if not run["run_id"]:
            raise SystemExit(f"No run_id for {run['label']}: {json.dumps(submit)[:2000]}")

    terminal = {"completed", "succeeded", "failed", "cancelled", "error"}
    deadline = time.time() + args.timeout
    poll = 0
    while time.time() < deadline:
        poll += 1
        all_done = True
        for run in runs:
            if run.get("status") in terminal:
                continue
            try:
                status_payload = request_json(args.api_url, api_key, "GET", f"/api/nextflow/status/{run['run_id']}", timeout=60)
            except Exception as exc:  # noqa: BLE001 - keep monitor alive across transient API failures.
                log(f"[parallel-pocket] poll {poll:03d} {run['label']}: status error {exc}")
                all_done = False
                continue
            run["latest_status_payload"] = status_payload
            run["status"] = status_payload.get("status", "")
            log(
                f"[parallel-pocket] poll {poll:03d} {run['label']}: "
                f"status={run['status']!r} progress={status_payload.get('progressPercent')} "
                f"tasks={status_payload.get('completedTasks')}/{status_payload.get('totalTasks')} "
                f"batch={status_payload.get('is_batch')}"
            )
            if run["status"] not in terminal:
                all_done = False
        if all_done:
            break
        time.sleep(args.poll_interval)
    else:
        log("[parallel-pocket] TIMEOUT waiting for terminal states")

    summary = {"api_url": args.api_url, "nextflow_path": NF_PATH, "run_root": str(run_root), "runs": []}
    for run in runs:
        label_dir = run_root / run["label"]
        label_dir.mkdir(parents=True, exist_ok=True)
        status_payload = run.get("latest_status_payload") or {}
        (label_dir / "submit.json").write_text(json.dumps(run.get("submit"), indent=2), encoding="utf-8")
        (label_dir / "status.json").write_text(json.dumps(status_payload, indent=2), encoding="utf-8")

        files = status_payload.get("s3_output_files") or []
        if not files:
            try:
                output_payload = request_json(args.api_url, api_key, "GET", f"/api/nextflow/runs/{run['run_id']}/output_files", timeout=60)
                (label_dir / "output_files.json").write_text(json.dumps(output_payload, indent=2), encoding="utf-8")
                files = output_payload.get("files") if isinstance(output_payload, dict) else output_payload
            except Exception as exc:  # noqa: BLE001
                log(f"[parallel-pocket] {run['label']}: output file lookup failed: {exc}")

        downloaded = download_selected_outputs(files or [], label_dir)
        validation = validate_run(label_dir)
        summary["runs"].append(
            {
                "label": run["label"],
                "run_id": run.get("run_id"),
                "outdir": run.get("outdir"),
                "pdb_input": run["pdb_input"],
                "status": run.get("status"),
                "downloaded": downloaded,
                "validation": validation,
            }
        )

    (run_root / "parallel_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    log("[parallel-pocket] summary")
    log(json.dumps(summary, indent=2))

    bad = [run for run in summary["runs"] if run["status"] not in {"completed", "succeeded"} or not run["validation"].get("ok")]
    if bad:
        raise SystemExit(4)


if __name__ == "__main__":
    main()
