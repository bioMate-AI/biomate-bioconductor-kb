#!/usr/bin/env python3
"""Poll Galaxy zinc600 runs and merge docking JSON into publication results."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
RESULTS = PUB / "zinc150_screen/vina/docking_autodock_vina_results.json"
SPRINT = ROOT / "research/anti-virus/science_sprint/runs"
BASELINE_RUN = ROOT / "research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z"


def load_api_key() -> str:
    cfg = (ROOT / "backend/config/galaxy.yml").read_text(encoding="utf-8")
    m = re.search(r"bootstrap_admin_api_key:\s*(\S+)", cfg)
    if not m:
        raise SystemExit("No Galaxy API key")
    return m.group(1)


def get_status(api_url: str, key: str, run_id: str) -> dict[str, Any]:
    req = urllib.request.Request(
        f"{api_url.rstrip('/')}/api/nextflow/status/{run_id}",
        headers={"X-API-Key": key},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode("utf-8"))


def aws_cp(uri: str, dest: Path) -> bool:
    dest.parent.mkdir(parents=True, exist_ok=True)
    return subprocess.run(["aws", "s3", "cp", uri, str(dest)], capture_output=True, check=False).returncode == 0


def find_docking_json(st: dict[str, Any], cache: Path) -> dict[str, Any] | None:
    target = "docking_autodock_vina_results.json"
    for item in st.get("s3_output_files") or []:
        if not isinstance(item, dict):
            continue
        name = (item.get("filename") or "").lower()
        uri = item.get("s3_uri") or ""
        if name == target and uri:
            local = cache / f"{st.get('run_id', 'run')[:8]}_{target}"
            if aws_cp(uri, local):
                return json.loads(local.read_text(encoding="utf-8"))
    outdir = (st.get("outdir") or "").rstrip("/")
    if outdir.startswith("s3://"):
        for suffix in ("", "/run"):
            uri = f"{outdir}{suffix}/{target}"
            local = cache / f"out_{Path(uri).name}"
            if aws_cp(uri, local):
                return json.loads(local.read_text(encoding="utf-8"))
    return None


def merge_results(existing: dict[str, Any], new_data: dict[str, Any]) -> dict[str, Any]:
    by_smiles: dict[str, dict[str, Any]] = {
        r["smiles"]: r for r in existing.get("results") or [] if r.get("smiles")
    }
    added = 0
    for row in new_data.get("results") or []:
        sm = row.get("smiles")
        if not sm or sm in by_smiles:
            continue
        by_smiles[sm] = row
        added += 1
    merged = sorted(by_smiles.values(), key=lambda r: float(r.get("best_affinity_kcal_mol") or 0))
    out = dict(existing)
    out["results"] = merged
    out["merged_at"] = datetime.now(timezone.utc).isoformat()
    out["n_results"] = len(merged)
    return out, added


def collect_run_ids() -> list[str]:
    ids: list[str] = []
    for manifest_path in sorted(SPRINT.glob("*/track_zinc600_dock/manifest.json"), reverse=True):
        m = json.loads(manifest_path.read_text(encoding="utf-8"))
        rid = m.get("run_id")
        if rid:
            ids.append(rid)
    for submit_path in sorted(BASELINE_RUN.glob("04_docking_vina_z600_*/submit.json")):
        rid = json.loads(submit_path.read_text(encoding="utf-8")).get("run_id")
        if rid:
            ids.append(rid)
    mf = BASELINE_RUN / "pipeline_manifest.json"
    if mf.is_file():
        for step in json.loads(mf.read_text(encoding="utf-8")).get("steps") or []:
            key = step.get("key") or ""
            rid = step.get("run_id")
            if rid and key.startswith("docking_vina_z600_"):
                ids.append(rid)
    for log in (PUB / "compute_parallel_logs").glob("*zinc600*.log"):
        for m in re.finditer(r"run_id['\"]?\s*[:=]\s*['\"]?([0-9a-f-]{36})", log.read_text(errors="replace")):
            ids.append(m.group(1))
    return list(dict.fromkeys(ids))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--api-url", default="http://127.0.0.1:8081")
    ap.add_argument("--poll-manifests-only", action="store_true", help="Only report status from batch manifests")
    args = ap.parse_args()

    existing = json.loads(RESULTS.read_text(encoding="utf-8")) if RESULTS.is_file() else {"results": []}
    cache = PUB / "zinc600_screen/cache"
    cache.mkdir(parents=True, exist_ok=True)

    report: list[dict[str, Any]] = []
    total_added = 0

    if args.poll_manifests_only:
        for mf in sorted(SPRINT.glob("*/track_zinc600_dock/manifest.json")):
            m = json.loads(mf.read_text(encoding="utf-8"))
            report.append(
                {
                    "stamp": mf.parents[1].name,
                    "status": m.get("status"),
                    "remaining": m.get("remaining"),
                    "run_id": m.get("run_id"),
                    "step_suffix": m.get("step_suffix"),
                }
            )
        (PUB / "zinc600_screen/ZINC600_POLL.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(json.dumps(report, indent=2))
        print(f"Current docked: {len(existing.get('results') or [])}")
        return

    key = load_api_key()
    run_ids = collect_run_ids()
    for rid in run_ids:
        try:
            st = get_status(args.api_url, key, rid)
        except Exception as exc:
            report.append({"run_id": rid, "error": str(exc)})
            continue
        entry = {"run_id": rid, "status": st.get("status"), "n_s3_files": len(st.get("s3_output_files") or [])}
        if st.get("status") in {"succeeded", "completed"}:
            data = find_docking_json(st, cache)
            if data:
                existing, added = merge_results(existing, data)
                entry["merged"] = added
                total_added += added
        report.append(entry)

    RESULTS.parent.mkdir(parents=True, exist_ok=True)
    RESULTS.write_text(json.dumps(existing, indent=2), encoding="utf-8")
    summary = {
        "polled_at": datetime.now(timezone.utc).isoformat(),
        "total_docked": len(existing.get("results") or []),
        "newly_merged": total_added,
        "runs": report,
    }
    (PUB / "zinc600_screen/ZINC600_MERGE.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"Docked total: {summary['total_docked']} (+{total_added} this poll)")


if __name__ == "__main__":
    main()
