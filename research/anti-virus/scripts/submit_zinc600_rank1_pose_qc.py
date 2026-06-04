#!/usr/bin/env python3
"""
Submit GROMACS MD + pose QC for ZINC600 rank-1 Vina hit (compute-only).

Submits via Galaxy API directly; records run_id for poll_zinc600_rank1_pose_qc.py.
"""
from __future__ import annotations

import json
import re
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
DOCK = PUB / "zinc150_screen/vina/docking_autodock_vina_results.json"
PIPELINE = ROOT / "research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z"


def load_api_key() -> str:
    cfg = (ROOT / "backend/config/galaxy.yml").read_text(encoding="utf-8")
    m = re.search(r"bootstrap_admin_api_key:\s*(\S+)", cfg)
    if not m:
        raise SystemExit("No Galaxy API key")
    return m.group(1)


def rank1_hit() -> dict[str, Any]:
    data = json.loads(DOCK.read_text(encoding="utf-8"))
    ok = [r for r in data.get("results") or [] if r.get("best_affinity_kcal_mol") is not None]
    return sorted(ok, key=lambda r: float(r["best_affinity_kcal_mol"]))[0]


def pocket_box() -> tuple[list[float], list[float]]:
    mf = json.loads((PIPELINE / "pipeline_manifest.json").read_text(encoding="utf-8"))
    for step in mf.get("steps") or []:
        if step.get("key") == "pocket" and step.get("top_pocket_center"):
            ctr = step["top_pocket_center"]
            return list(ctr), [22.0, 22.0, 22.0]
    return [173.607, 208.847, 174.042], [22.0, 22.0, 22.0]


def post_gromacs(api_url: str, key: str, params: dict[str, Any], user_id: str) -> dict[str, Any]:
    body = {
        "nextflow_path": "nextflow_nfcore/subworkflows/drug_discovery/gromacs_protein_md/main.nf",
        "parameters": params,
        "compute_config": {"executor": "awsbatch", "s3_bucket": "biomate-nextflow-work"},
        "workflow_domain": "drug_discovery",
        "user_id": user_id,
        "profile": "aws",
    }
    req = urllib.request.Request(
        f"{api_url.rstrip('/')}/api/nextflow/execute",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "X-API-Key": key},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> None:
    hit = rank1_hit()
    smiles = hit["smiles"]
    vina = hit["best_affinity_kcal_mol"]
    center, box = pocket_box()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    suffix = f"rank1_z600_{stamp}"
    step_dir = PIPELINE / f"05_gromacs_mmgbsa_{suffix}"
    step_dir.mkdir(parents=True, exist_ok=True)

    params = {
        "receptor": "s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb",
        "ligand": smiles,
        "use_aws": True,
        "n_steps": 500000,
        "gpu": False,
        "auto_trim_receptor": True,
        "trim_pad": 10.0,
        "box_center": json.dumps(center),
        "box_size": json.dumps(box),
    }
    (step_dir / "parameters.json").write_text(json.dumps(params, indent=2), encoding="utf-8")

    key = load_api_key()
    submit = post_gromacs(key=key, api_url="http://127.0.0.1:8081", params=params, user_id=f"zinc600-rank1-{stamp[:8]}")
    (step_dir / "submit.json").write_text(json.dumps(submit, indent=2), encoding="utf-8")
    run_id = submit.get("run_id")

    out_dir = PUB / "zinc600_screen/rank1_pose_qc"
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "compound_id": "Z600-R1",
        "smiles": smiles,
        "vina_kcal_mol": vina,
        "step_suffix": suffix,
        "step_dir": str(step_dir),
        "run_id": run_id,
        "status": "submitted" if run_id else "submit_failed",
        "compare_to": {
            "INH-01_smiles": "N=C(N)NC(=O)c1nccnc1N",
            "INH-01_vina_kcal_mol": -6.267,
            "INH-01_ligand_rmsd_mean_nm": 0.204,
        },
        "poll_hint": "python3 research/anti-virus/scripts/poll_zinc600_rank1_pose_qc.py",
    }
    (out_dir / "RANK1_POSE_QC_MANIFEST.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps({k: manifest[k] for k in ("compound_id", "vina_kcal_mol", "run_id", "status")}, indent=2))
    if not run_id:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
