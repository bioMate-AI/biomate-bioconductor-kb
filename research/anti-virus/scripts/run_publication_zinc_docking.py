#!/usr/bin/env python3
"""Chunked Vina docking for publication_zinc/dock_set.smi until complete.

  python3 research/anti-virus/scripts/run_publication_zinc_docking.py
  python3 research/anti-virus/scripts/run_publication_zinc_docking.py --chunk-size 50 --max-chunks 2  # smoke
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
LIBRARY = PUB / "publication_zinc/dock_set.smi"
OUT_DIR = PUB / "publication_zinc/vina"
RESULTS = OUT_DIR / "docking_autodock_vina_results.json"
BASELINE_RUN = ROOT / "research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z"
DOCK_SCRIPT = ROOT / "research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py"
PDB_S3 = "s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb"
SPRINT = ROOT / "research/anti-virus/science_sprint/runs"


def log(msg: str) -> None:
    print(msg, flush=True)


def load_api_key() -> str:
    text = (ROOT / "backend/config/galaxy.yml").read_text(encoding="utf-8")
    m = re.search(r"bootstrap_admin_api_key:\s*(\S+)", text)
    if not m:
        raise SystemExit("No API key")
    return m.group(1).strip()


def load_all_smiles(path: Path) -> list[str]:
    return [ln.strip().split()[0] for ln in path.read_text(encoding="utf-8").splitlines() if ln.strip()]


def load_done(path: Path) -> set[str]:
    if not path.is_file():
        return set()
    data = json.loads(path.read_text(encoding="utf-8"))
    return {r["smiles"] for r in data.get("results") or [] if r.get("smiles")}


def api_up(url: str = "http://127.0.0.1:8081") -> bool:
    try:
        urllib.request.urlopen(url, timeout=3)
        return True
    except Exception:
        return False


def find_run_id(suffix: str) -> str | None:
    submit = BASELINE_RUN / f"04_docking_vina_{suffix}" / "submit.json"
    if submit.is_file():
        return json.loads(submit.read_text(encoding="utf-8")).get("run_id")
    return None


def get_status(api_url: str, key: str, run_id: str) -> dict[str, Any]:
    req = urllib.request.Request(
        f"{api_url.rstrip('/')}/api/nextflow/status/{run_id}",
        headers={"X-API-Key": key},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode("utf-8"))


def download_docking_json(st: dict[str, Any], dest: Path) -> bool:
    target = "docking_autodock_vina_results.json"
    for item in st.get("s3_output_files") or []:
        if isinstance(item, dict) and (item.get("filename") or "").lower() == target:
            uri = item.get("s3_uri") or ""
            if uri and subprocess.run(["aws", "s3", "cp", uri, str(dest)], capture_output=True).returncode == 0:
                return True
    outdir = (st.get("outdir") or "").rstrip("/")
    if outdir.startswith("s3://"):
        for suffix in ("", "/run"):
            uri = f"{outdir}{suffix}/{target}"
            if subprocess.run(["aws", "s3", "cp", uri, str(dest)], capture_output=True).returncode == 0:
                return True
    return False


def merge_into_results(existing: dict[str, Any], chunk_data: dict[str, Any]) -> tuple[dict[str, Any], int]:
    by_smiles = {r["smiles"]: r for r in existing.get("results") or [] if r.get("smiles")}
    added = 0
    for row in chunk_data.get("results") or []:
        sm = row.get("smiles")
        if not sm or sm in by_smiles:
            continue
        by_smiles[sm] = row
        added += 1
    out = dict(existing)
    out["results"] = sorted(by_smiles.values(), key=lambda r: float(r.get("best_affinity_kcal_mol") or 0))
    out["n_results"] = len(out["results"])
    out["merged_at"] = datetime.now(timezone.utc).isoformat()
    return out, added


def poll_and_merge(api_url: str, key: str, run_id: str, poll_interval: int, timeout: int) -> dict[str, Any] | None:
    deadline = time.time() + timeout
    cache = OUT_DIR / "cache"
    cache.mkdir(parents=True, exist_ok=True)
    tmp = cache / f"{run_id[:8]}_chunk.json"
    while time.time() < deadline:
        st = get_status(api_url, key, run_id)
        status = (st.get("status") or "").lower()
        log(f"    poll {run_id[:8]}… {status!r}")
        if status in {"succeeded", "completed", "failed", "error", "cancelled"}:
            if download_docking_json(st, tmp):
                return json.loads(tmp.read_text(encoding="utf-8"))
            if status in {"failed", "error", "cancelled"}:
                return None
        time.sleep(poll_interval)
    return None


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--api-url", default="http://127.0.0.1:8081")
    ap.add_argument("--chunk-size", type=int, default=50)
    ap.add_argument("--max-chunks", type=int, default=0, help="0 = until library complete")
    ap.add_argument("--poll-interval", type=int, default=25)
    ap.add_argument("--chunk-timeout", type=int, default=7200)
    args = ap.parse_args()

    if not LIBRARY.is_file():
        raise SystemExit(f"Run build_publication_zinc_library.py first — missing {LIBRARY}")
    if not api_up(args.api_url):
        raise SystemExit(f"API down: {args.api_url}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    all_sm = load_all_smiles(LIBRARY)
    existing = json.loads(RESULTS.read_text(encoding="utf-8")) if RESULTS.is_file() else {"results": []}
    done = load_done(RESULTS)
    remaining = [s for s in all_sm if s not in done]
    key = load_api_key()
    progress_path = OUT_DIR / "dock_progress.json"

    log(f"Publication dock: {len(done)}/{len(all_sm)} done, {len(remaining)} remaining")

    chunks_run = 0
    while remaining:
        if args.max_chunks and chunks_run >= args.max_chunks:
            log(f"Stopped at max_chunks={args.max_chunks}")
            break
        chunk = remaining[: args.chunk_size]
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        suffix = f"pubzinc_{stamp}"
        run_track = SPRINT / stamp / "track_publication_zinc_dock"
        run_track.mkdir(parents=True, exist_ok=True)
        chunk_file = run_track / "chunk.smi"
        chunk_file.write_text("\n".join(chunk) + "\n", encoding="utf-8")

        cmd = [
            sys.executable,
            str(DOCK_SCRIPT),
            "--api-url",
            args.api_url,
            "--pdb-input",
            PDB_S3,
            "--through-step",
            "4",
            "--append-to-run",
            "research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z",
            "--append-only-keys",
            "docking_vina",
            "--step-suffix",
            suffix,
            "--smiles-json",
            json.dumps(chunk),
            "--use-top-pocket-box",
            "--skip-downloads",
            "--step-timeout",
            str(args.chunk_timeout),
            "--poll-interval",
            str(args.poll_interval),
            "--user-id",
            f"pub-zinc-{stamp[:8]}",
        ]
        log(f"Chunk {chunks_run + 1}: {len(chunk)} compounds (suffix={suffix})")
        rc = subprocess.run(cmd, cwd=str(ROOT))
        run_id = find_run_id(suffix)
        if rc.returncode != 0 or not run_id:
            log(f"Submit failed rc={rc} run_id={run_id}")
            break

        chunk_data = poll_and_merge(args.api_url, key, run_id, args.poll_interval, args.chunk_timeout)
        if not chunk_data:
            log("No chunk JSON — stopping")
            break

        existing, added = merge_into_results(existing, chunk_data)
        RESULTS.write_text(json.dumps(existing, indent=2), encoding="utf-8")
        done = load_done(RESULTS)
        remaining = [s for s in all_sm if s not in done]
        chunks_run += 1
        progress = {
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "docked": len(done),
            "total": len(all_sm),
            "remaining": len(remaining),
            "chunks_completed": chunks_run,
            "last_run_id": run_id,
            "last_suffix": suffix,
        }
        progress_path.write_text(json.dumps(progress, indent=2), encoding="utf-8")
        log(f"  merged +{added} → {len(done)}/{len(all_sm)}")

    log(f"Final: {len(load_done(RESULTS))}/{len(all_sm)} in {RESULTS}")


if __name__ == "__main__":
    main()
