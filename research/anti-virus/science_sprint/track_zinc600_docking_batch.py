#!/usr/bin/env python3
"""
Batch ZINC600 Vina docking — remaining compounds (compute-only).

Chunks library; submits via Galaxy API when up, else writes launch manifest.
Each chunk uses --step-suffix so append-only docking_vina runs do not no-op.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
LIBRARY = PUB / "assets/zinc600_library.smi"
EXISTING = PUB / "zinc150_screen/vina/docking_autodock_vina_results.json"
SPRINT = ROOT / "research/anti-virus/science_sprint/runs"
BASELINE_RUN = ROOT / "research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z"
DOCK_SCRIPT = ROOT / "research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py"


def load_smiles_done(path: Path) -> set[str]:
    if not path.is_file():
        return set()
    data = json.loads(path.read_text(encoding="utf-8"))
    return {r["smiles"] for r in data.get("results") or [] if r.get("smiles")}


def load_smiles_pending(sprint_root: Path) -> set[str]:
    """SMILES in submitted batches not yet reflected in merged results."""
    pending: set[str] = set()
    for mf in sprint_root.glob("*/track_zinc600_dock/manifest.json"):
        m = json.loads(mf.read_text(encoding="utf-8"))
        if m.get("status") not in {"submitted", "submitted_no_run_id", "running"}:
            continue
        chunk_file = Path(m.get("chunk_file") or "")
        if chunk_file.is_file():
            for line in chunk_file.read_text(encoding="utf-8").splitlines():
                sm = line.strip().split()[0] if line.strip() else ""
                if sm:
                    pending.add(sm)
    return pending


def load_all_smiles(path: Path) -> list[str]:
    out: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        sm = line.split()[0] if " " in line else line
        out.append(sm)
    return out


def api_up(url: str = "http://127.0.0.1:8081") -> bool:
    import urllib.request

    try:
        urllib.request.urlopen(url, timeout=3)
        return True
    except Exception:
        return False


def find_run_id(stamp: str) -> str | None:
    suffix = f"z600_{stamp}"
    submit = BASELINE_RUN / f"04_docking_vina_{suffix}" / "submit.json"
    if submit.is_file():
        return json.loads(submit.read_text(encoding="utf-8")).get("run_id")
    mf = BASELINE_RUN / "pipeline_manifest.json"
    if not mf.is_file():
        return None
    for step in json.loads(mf.read_text(encoding="utf-8")).get("steps") or []:
        if step.get("key") == f"docking_vina_{suffix}":
            return step.get("run_id")
    return None


def main() -> None:
    ap_chunk = int(os.environ.get("ZINC600_CHUNK", "50"))
    all_sm = load_all_smiles(LIBRARY)
    done = load_smiles_done(EXISTING)
    pending = load_smiles_pending(SPRINT)
    remaining = [s for s in all_sm if s not in done and s not in pending]

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    suffix = f"z600_{stamp}"
    run_dir = ROOT / "research/anti-virus/science_sprint/runs" / stamp / "track_zinc600_dock"
    run_dir.mkdir(parents=True, exist_ok=True)
    chunk = remaining[:ap_chunk]
    chunk_file = run_dir / "chunk.smi"
    chunk_file.write_text("\n".join(chunk) + "\n", encoding="utf-8")

    manifest = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "track": "zinc600_docking_batch",
        "library_total": len(all_sm),
        "already_docked_estimate": len(done),
        "pending_in_flight": len(pending),
        "remaining": len(remaining),
        "chunk_size": len(chunk),
        "chunk_file": str(chunk_file),
        "step_suffix": suffix,
        "status": "pending",
    }

    if chunk and api_up():
        s3_chunk = f"s3://biomate-nextflow-work/inputs/andv_campaign/zinc600/{stamp}/chunk.smi"
        subprocess.run(["aws", "s3", "cp", str(chunk_file), s3_chunk], check=False)
        smiles_json = json.dumps(chunk)
        cmd = [
            sys.executable,
            str(DOCK_SCRIPT),
            "--pdb-input",
            "s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb",
            "--through-step",
            "4",
            "--append-to-run",
            "research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z",
            "--append-only-keys",
            "docking_vina",
            "--step-suffix",
            suffix,
            "--smiles-json",
            smiles_json,
            "--use-top-pocket-box",
            "--submit-only",
            "--skip-downloads",
            "--user-id",
            f"zinc600-{stamp[:8]}",
        ]
        manifest["command"] = cmd
        rc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True)
        manifest["stdout_tail"] = (rc.stdout or "")[-2000:]
        manifest["stderr_tail"] = (rc.stderr or "")[-2000:]
        run_id = find_run_id(stamp)
        if run_id:
            manifest["run_id"] = run_id
        if rc.returncode == 0 and run_id:
            manifest["status"] = "submitted"
        elif rc.returncode == 0:
            manifest["status"] = "submitted_no_run_id"
        else:
            manifest["status"] = f"failed: {(rc.stderr or rc.stdout or '')[:400]}"
    else:
        manifest["status"] = "queued" if chunk else "complete"
        manifest["note"] = "Start Galaxy API and re-run, or increase ZINC600_CHUNK"

    out = run_dir / "manifest.json"
    out.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    pub_manifest = PUB / "zinc600_screen/ZINC600_BATCH_MANIFEST.json"
    pub_manifest.parent.mkdir(parents=True, exist_ok=True)
    pub_manifest.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Remaining: {len(remaining)} | chunk: {len(chunk)} | status: {manifest['status']}")
    if manifest.get("run_id"):
        print(f"run_id: {manifest['run_id']}")


if __name__ == "__main__":
    main()
