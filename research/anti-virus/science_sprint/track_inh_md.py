#!/usr/bin/env python3
"""
ANDV science sprint — launch GROMACS MD (pipeline step 5) via the existing Nextflow driver.

Wraps ``run_andv_inhibitor_pipeline_nextflow.py`` with ``--append-only-keys gromacs_mmgbsa``,
resolving the top-pocket receptor S3 from a completed pocket step in ``pipeline_manifest.json``.

Usage (smoke MD, default 250k steps):

  python3 research/anti-virus/science_sprint/track_inh_md.py

Production MD (~10 ns at 2 fs):

  python3 research/anti-virus/science_sprint/track_inh_md.py --gromacs-n-steps 5000000

Environment: GALAXY_API_KEY or bootstrap_admin_api_key (used by the subprocess driver).
API URL: BIOMATE_API_URL or --api-url.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
PIPELINE_SCRIPT = ROOT / "research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py"
DEFAULT_BASE_RUN = "research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z"
DEFAULT_9P3I_S3 = "s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb"
ASPIRIN_SMILES = "CC(=O)Oc1ccccc1C(=O)O"


def log(msg: str) -> None:
    print(msg, flush=True)


def load_api_key() -> str:
    if os.environ.get("GALAXY_API_KEY"):
        return os.environ["GALAXY_API_KEY"]
    gal = ROOT / "backend/config/galaxy.yml"
    text = gal.read_text(encoding="utf-8")
    m = re.search(r"bootstrap_admin_api_key:\s*(\S+)", text)
    if not m:
        raise SystemExit("Set GALAXY_API_KEY or configure bootstrap_admin_api_key in backend/config/galaxy.yml")
    return m.group(1).strip()


def repo_rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def read_pipeline_manifest(base_run: Path) -> dict[str, Any]:
    mf_path = base_run / "pipeline_manifest.json"
    if not mf_path.is_file():
        raise SystemExit(f"Missing pipeline manifest: {mf_path}")
    return json.loads(mf_path.read_text(encoding="utf-8"))


def full_receptor_s3_from_manifest(manifest: dict[str, Any]) -> str:
    """Prefer campaign full-chain 9P3I; pocket-trimmed fragments break ParmEd/tleap."""
    pdb = (manifest.get("pdb_input") or "").strip()
    if pdb.startswith("s3://"):
        return pdb
    return DEFAULT_9P3I_S3


def top_pocket_s3_from_manifest(base_run: Path, manifest: dict[str, Any]) -> str:
    """Return S3 URI for structure_top_pocket.pdb from the pocket step status.json."""
    pocket = next((s for s in manifest.get("steps") or [] if s.get("key") == "pocket"), None)
    if not pocket:
        raise SystemExit(f"No pocket step in {base_run / 'pipeline_manifest.json'}")

    status_candidates = []
    artifact = pocket.get("artifact_dir")
    if artifact:
        status_candidates.append(Path(artifact) / "status.json")
    status_candidates.append(base_run / "01_pocket" / "status.json")

    status_path = next((p for p in status_candidates if p.is_file()), None)
    if not status_path:
        raise SystemExit(
            f"Cannot resolve top-pocket S3: no status.json under pocket artifact or {base_run / '01_pocket'}"
        )

    status = json.loads(status_path.read_text(encoding="utf-8"))
    for item in status.get("s3_output_files") or []:
        uri = (item.get("s3_uri") or "").strip()
        name = (item.get("filename") or uri.rsplit("/", 1)[-1]).strip()
        if name == "structure_top_pocket.pdb" and uri.startswith("s3://"):
            return uri

    for proc in status.get("processes") or []:
        for uri in proc.get("task_files") or []:
            if str(uri).endswith("structure_top_pocket.pdb"):
                return str(uri)

    raise SystemExit(f"No structure_top_pocket.pdb S3 URI in {status_path}")


def build_pipeline_command(
    *,
    base_run_rel: str,
    api_url: str,
    pdb_input: str,
    ligand_smiles: str,
    gromacs_n_steps: int,
    user_id: str | None,
    receptor_mode: str = "full",
    step_timeout: int = 21600,
) -> list[str]:
    cmd = [
        sys.executable,
        repo_rel(PIPELINE_SCRIPT),
        "--append-to-run",
        base_run_rel,
        "--through-step",
        "5",
        "--append-only-keys",
        "gromacs_mmgbsa",
        "--api-url",
        api_url,
        "--pdb-input",
        pdb_input,
        "--ligand-s3",
        ligand_smiles,
        "--gromacs-n-steps",
        str(gromacs_n_steps),
        "--step-timeout",
        str(step_timeout),
    ]
    if user_id:
        cmd.extend(["--user-id", user_id])
    # Full tetramer needs pocket-box crop before tleap; pocket fragment is already small.
    if receptor_mode == "full" or pdb_input.endswith("9P3I.pdb"):
        cmd.append("--use-top-pocket-box")
    return cmd


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument(
        "--base-run",
        default=DEFAULT_BASE_RUN,
        help=f"Existing NF run dir (repo-relative, default {DEFAULT_BASE_RUN})",
    )
    ap.add_argument("--api-url", default=os.environ.get("BIOMATE_API_URL", "http://127.0.0.1:8081"))
    ap.add_argument(
        "--pdb-input",
        default="",
        help="Receptor S3 (default: full 9P3I from pipeline manifest, not fpocket fragment)",
    )
    ap.add_argument(
        "--receptor",
        choices=("full", "pocket"),
        default="full",
        help="full = 9P3I tetramer S3 (default); pocket = structure_top_pocket.pdb from pocket step",
    )
    ap.add_argument("--ligand-smiles", default=ASPIRIN_SMILES, help="Ligand SMILES passed to --ligand-s3")
    ap.add_argument(
        "--gromacs-n-steps",
        type=int,
        default=250000,
        help="MD steps (default 250000 smoke; use 5000000 for production)",
    )
    ap.add_argument(
        "--step-timeout",
        type=int,
        default=21600,
        help="Seconds to poll each pipeline step (default 6h for MD on Batch)",
    )
    args = ap.parse_args()

    base_run = (ROOT / args.base_run).resolve()
    manifest = read_pipeline_manifest(base_run)
    base_run_rel = repo_rel(base_run)

    if args.pdb_input.strip():
        pdb_input = args.pdb_input.strip()
    elif args.receptor == "pocket":
        pdb_input = top_pocket_s3_from_manifest(base_run, manifest)
    else:
        pdb_input = full_receptor_s3_from_manifest(manifest)
    user_id = (manifest.get("user_id") or "").strip() or None

    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = ROOT / "research/anti-virus/science_sprint/runs" / ts / "track_inh_md"
    run_dir.mkdir(parents=True, exist_ok=True)

    cmd = build_pipeline_command(
        base_run_rel=base_run_rel,
        api_url=args.api_url,
        pdb_input=pdb_input,
        ligand_smiles=args.ligand_smiles,
        gromacs_n_steps=args.gromacs_n_steps,
        user_id=user_id,
        receptor_mode=args.receptor,
        step_timeout=args.step_timeout,
    )

    track_manifest: dict[str, Any] = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "track": "track_inh_md",
        "base_run": base_run_rel,
        "api_url": args.api_url,
        "pdb_input": pdb_input,
        "ligand_smiles": args.ligand_smiles,
        "gromacs_n_steps": args.gromacs_n_steps,
        "pipeline_script": repo_rel(PIPELINE_SCRIPT),
        "command": cmd,
        "status": "pending",
    }
    manifest_path = run_dir / "manifest.json"
    manifest_path.write_text(json.dumps(track_manifest, indent=2), encoding="utf-8")

    log(f"Track run dir: {repo_rel(run_dir)}")
    log(f"Receptor: {pdb_input}")
    log(f"Command: {' '.join(cmd)}")

    track_manifest["status"] = "running"
    track_manifest["started_at"] = datetime.now(timezone.utc).isoformat()
    manifest_path.write_text(json.dumps(track_manifest, indent=2), encoding="utf-8")

    proc = subprocess.run(cmd, cwd=ROOT)
    track_manifest["returncode"] = proc.returncode
    track_manifest["finished_at"] = datetime.now(timezone.utc).isoformat()
    track_manifest["status"] = "succeeded" if proc.returncode == 0 else "failed"
    manifest_path.write_text(json.dumps(track_manifest, indent=2), encoding="utf-8")

    if proc.returncode != 0:
        raise SystemExit(proc.returncode)
    log(f"Done. Manifest: {repo_rel(manifest_path)}")


if __name__ == "__main__":
    main()
