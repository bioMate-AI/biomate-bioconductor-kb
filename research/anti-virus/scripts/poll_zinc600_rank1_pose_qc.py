#!/usr/bin/env python3
"""Poll ZINC600 rank-1 GROMACS run; download MD artifacts and compute ligand RMSD when ready."""
from __future__ import annotations

import json
import re
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
MANIFEST = PUB / "zinc600_screen/rank1_pose_qc/RANK1_POSE_QC_MANIFEST.json"
ANALYZE = ROOT / "research/anti-virus/scripts/analyze_inhibitor_ligand_rmsd.py"


def load_api_key() -> str:
    cfg = (ROOT / "backend/config/galaxy.yml").read_text(encoding="utf-8")
    m = re.search(r"bootstrap_admin_api_key:\s*(\S+)", cfg)
    if not m:
        raise SystemExit("No Galaxy API key")
    return m.group(1)


def aws_cp(uri: str, dest: Path) -> bool:
    dest.parent.mkdir(parents=True, exist_ok=True)
    return subprocess.run(["aws", "s3", "cp", uri, str(dest)], capture_output=True, check=False).returncode == 0


def main() -> None:
    if not MANIFEST.is_file():
        raise SystemExit(f"Missing {MANIFEST} — run submit_zinc600_rank1_pose_qc.py first")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    run_id = manifest.get("run_id")
    if not run_id:
        raise SystemExit("No run_id in manifest")
    step_dir = Path(manifest["step_dir"])

    key = load_api_key()
    req = urllib.request.Request(
        f"http://127.0.0.1:8081/api/nextflow/status/{run_id}",
        headers={"X-API-Key": key},
    )
    status = json.loads(urllib.request.urlopen(req, timeout=120).read())
    manifest["polled_at"] = datetime.now(timezone.utc).isoformat()
    manifest["galaxy_status"] = status.get("status")

    md_dir = step_dir / "md"
    md_dir.mkdir(parents=True, exist_ok=True)
    for item in status.get("s3_output_files") or []:
        if not isinstance(item, dict):
            continue
        name = (item.get("filename") or "").lower()
        uri = item.get("s3_uri") or ""
        if not uri:
            continue
        if name in {"trajectory.xtc", "production.gro"}:
            aws_cp(uri, md_dir / name)

    if (md_dir / "trajectory.xtc").is_file() and (md_dir / "production.gro").is_file():
        out_json = step_dir / "ligand_rmsd_qc.json"
        rc = subprocess.run(
            [sys.executable, str(ANALYZE), "--traj-dir", str(md_dir), "--out-json", str(out_json)],
            capture_output=True,
            text=True,
        )
        if rc.returncode == 0 and out_json.is_file():
            manifest["ligand_rmsd"] = json.loads(out_json.read_text(encoding="utf-8"))
            manifest["pose_qc_status"] = "complete"
        else:
            manifest["pose_qc_status"] = "rmsd_failed"
            manifest["rmsd_error"] = (rc.stderr or rc.stdout or "")[:500]
    else:
        manifest["pose_qc_status"] = "awaiting_md_outputs"

    MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    summary = {
        "run_id": run_id,
        "galaxy_status": manifest.get("galaxy_status"),
        "pose_qc_status": manifest.get("pose_qc_status"),
        "ligand_rmsd_mean_nm": (manifest.get("ligand_rmsd") or {}).get("ligand_rmsd_mean_nm"),
    }
    (PUB / "zinc600_screen/rank1_pose_qc/RANK1_POSE_QC.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )
    md_path = PUB / "zinc600_screen/rank1_pose_qc/RANK1_POSE_QC.md"
    lines = [
        "# ZINC600 rank-1 pose QC (GROMACS MD)",
        "",
        f"Updated: {manifest['polled_at']}",
        "",
        f"| Field | Value |",
        f"| --- | --- |",
        f"| SMILES | `{manifest.get('smiles', '')}` |",
        f"| Vina (kcal/mol) | {manifest.get('vina_kcal_mol')} |",
        f"| Galaxy status | {manifest.get('galaxy_status')} |",
        f"| Pose QC | {manifest.get('pose_qc_status')} |",
    ]
    lr = manifest.get("ligand_rmsd") or {}
    if lr.get("ligand_rmsd_mean_nm") is not None:
        lines.append(f"| Ligand RMSD mean (nm) | {lr['ligand_rmsd_mean_nm']} |")
        lines.append(f"| Ligand RMSD max (nm) | {lr.get('ligand_rmsd_max_nm', '—')} |")
        inh01 = 0.204
        mean = float(lr["ligand_rmsd_mean_nm"])
        verdict = "PASS (≤0.35 nm)" if mean <= 0.35 else ("WARN (≤0.50 nm)" if mean <= 0.50 else "FAIL")
        lines.extend(["", f"**Verdict vs INH-01 baseline (~0.20 nm):** {verdict}"])
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
