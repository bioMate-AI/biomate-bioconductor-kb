#!/usr/bin/env python3
"""
Sequential ANDV inhibitor track — BioMate Nextflow API (AWS Batch).

Executes the computational plan **step by step** via POST /api/nextflow/execute,
polls /api/nextflow/status/{run_id}, optionally downloads S3 outputs, and writes a
JSON manifest for handoffs between steps.

This script finishes the **planned Nextflow stages** without relying on chat/UI
chaining. Later steps need chemistry inputs (library SMILES, seed compounds); step 1
(pocket / druggability) runs from a receptor PDB alone.

Typical usage (receptor already on S3):

  python3 research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py \\
    --pdb-input s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb \\
    --through-step 1

Continue the pipeline when you have libraries / SMILES:

  python3 ... --through-step 4 \\
    --reference-actives-s3 s3://bucket/path/actives.smi \\
    --compound-library-s3 s3://bucket/path/library.smi \\
    [--smiles-json '[\"CCO\"]']   # optional fallback if pharmacophore produces no hits

Steps 3–4 (ADMET, Vina) prefer **SMILES from step 2** `filtered_compounds.smi` when present.

Steps (see manifest `steps[].key`):

  1 pocket          — Pocket Detection Druggability (same path as campaign docs).
  2 pharmacophore   — Requires --reference-actives-s3 and --compound-library-s3.
  3 admet           — Uses pharmacophore hits when available; else --smiles-json or demo default.
  4 docking_vina    — AutoDock Vina; uses top-pocket box from step 1 manifest when --use-top-pocket-box.
  5 gromacs_mmgbsa  — Optional MD + MM-GBSA (heavy); pass --ligand-s3 (S3 URI to .sdf/.mol2 **or**
                    a SMILES string — GROMACS workflow auto-converts SMILES in-container).
  6 reinvent4       — Generative optimization; pass --seed-smiles.

Resume after an earlier manifest (skip re-running completed steps):

  python3 ... --append-to-run research/anti-virus/runs/andv_nf_pipeline_YYYYMMDD... \\
    --through-step 6 --ligand-s3 '...' --seed-smiles '...'

Run **REINVENT4 only** (e.g. when GROMACS failed and you want generative follow-up without MD):

  python3 ... --append-to-run .../andv_nf_pipeline_... \\
    --through-step 6 --append-only-keys reinvent4 \\
    --pdb-input s3://.../9P3I.pdb \\
    --seed-smiles 'CC(=O)Oc1ccccc1C(=O)O'

Environment: GALAXY_API_KEY or bootstrap_admin_api_key in backend/config/galaxy.yml.
AWS CLI configured for s3 cp when downloading artifacts.

API URL: BIOMATE_API_URL or --api-url (default http://127.0.0.1:8081).
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
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]


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


def request_json(
    api_url: str,
    api_key: str,
    method: str,
    path: str,
    payload: dict[str, Any] | None = None,
    timeout: int = 180,
) -> Any:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        api_url.rstrip("/") + path,
        data=data,
        method=method,
        headers={"Content-Type": "application/json", "X-API-Key": api_key},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def request_json_retry(
    api_url: str,
    api_key: str,
    method: str,
    path: str,
    payload: dict[str, Any] | None = None,
    timeout: int = 180,
    *,
    max_retries: int = 8,
    retry_sleep_sec: float = 15.0,
) -> Any:
    """Same as request_json but retries on transient 5xx (long MD polls can hit flaky Galaxy)."""
    for attempt in range(max_retries):
        try:
            return request_json(api_url, api_key, method, path, payload, timeout=timeout)
        except urllib.error.HTTPError as e:
            if e.code in (500, 502, 503, 504) and attempt < max_retries - 1:
                log(f"  request_json: HTTP {e.code} on {path} (attempt {attempt + 1}/{max_retries}), retrying in {retry_sleep_sec}s…")
                time.sleep(retry_sleep_sec)
                continue
            raise
        except urllib.error.URLError as e:
            if attempt < max_retries - 1:
                log(f"  request_json: URLError {e} (attempt {attempt + 1}/{max_retries}), retrying…")
                time.sleep(retry_sleep_sec)
                continue
            raise
    raise RuntimeError("request_json_retry: exhausted retries")


def post_execute(
    api_url: str,
    api_key: str,
    nextflow_path: str,
    parameters: dict[str, Any],
    user_id: str,
    workflow_domain: str = "drug_discovery",
) -> dict[str, Any]:
    body = {
        "nextflow_path": nextflow_path,
        "parameters": parameters,
        "compute_config": {"executor": "awsbatch", "s3_bucket": "biomate-nextflow-work"},
        "workflow_domain": workflow_domain,
        "user_id": user_id,
        "profile": "aws",
    }
    return request_json(api_url, api_key, "POST", "/api/nextflow/execute", body, timeout=180)


def poll_status(
    api_url: str,
    api_key: str,
    run_id: str,
    timeout_sec: int,
    poll_interval: int,
) -> dict[str, Any]:
    terminal = {"completed", "succeeded", "failed", "cancelled", "error"}
    deadline = time.time() + timeout_sec
    last: dict[str, Any] = {}
    while time.time() < deadline:
        last = request_json_retry(api_url, api_key, "GET", f"/api/nextflow/status/{run_id}", timeout=120)
        st = last.get("status", "")
        log(f"  poll: status={st!r} progress={last.get('progressPercent')} tasks={last.get('completedTasks')}/{last.get('totalTasks')}")
        if st in terminal:
            return last
        time.sleep(poll_interval)
    last["_timeout"] = True
    return last


def s3_cp(uri: str, dest: Path) -> bool:
    r = subprocess.run(["aws", "s3", "cp", uri, str(dest)], capture_output=True, text=True, check=False)
    return r.returncode == 0


def download_useful_files(files: list[Any], dest_dir: Path) -> list[str]:
    dest_dir.mkdir(parents=True, exist_ok=True)
    out: list[str] = []
    for item in files or []:
        if not isinstance(item, dict):
            continue
        uri = item.get("s3_uri") or ""
        name = item.get("filename") or item.get("name") or ""
        if not uri or not name or name.endswith("/"):
            continue
        dest = dest_dir / Path(name).name
        if s3_cp(uri, dest):
            out.append(str(dest))
            log(f"    downloaded {dest.name}")
    return out


def fetch_output_files(api_url: str, api_key: str, run_id: str) -> list[Any]:
    try:
        payload = request_json_retry(api_url, api_key, "GET", f"/api/nextflow/runs/{run_id}/output_files", timeout=120)
        if isinstance(payload, dict):
            return payload.get("files") or []
        return list(payload) if payload else []
    except Exception:
        return []


def find_pockets_json(directory: Path) -> Path | None:
    matches = sorted(directory.glob("*_pockets.json"))
    return matches[0] if matches else None


def top_pocket_center(pockets_path: Path) -> tuple[float, float, float] | None:
    data = json.loads(pockets_path.read_text(encoding="utf-8"))
    pockets = data.get("pockets") or []
    if not pockets:
        return None
    top = pockets[0]
    return (float(top["center_x"]), float(top["center_y"]), float(top["center_z"]))


def volume_to_box_size(vol_a3: float) -> tuple[float, float, float]:
    """Crude cube edge from spherical volume assumption."""
    import math

    r = max(8.0, (3.0 * vol_a3 / (4.0 * math.pi)) ** (1.0 / 3.0) * 1.8)
    edge = min(40.0, 2.2 * r)
    return (edge, edge, edge)


@dataclass
class StepSpec:
    key: str
    title: str
    nextflow_path: str
    workflow_domain: str = "drug_discovery"


# Order matches the inhibitor campaign + curated target-to-lead semantics; docking uses
# pharmacology/docking_autodock_vina (PDB + SMILES + box), not AF3 structure_prediction_docking.
PIPELINE: list[StepSpec] = [
    StepSpec(
        "pocket",
        "Pocket detection + druggability",
        "nextflow_nfcore/subworkflows/drug_discovery/pocket_detection_druggability/main.nf",
    ),
    StepSpec(
        "pharmacophore",
        "Pharmacophore library filtering",
        "nextflow_nfcore/subworkflows/drug_discovery/pharmacophore_filtering/main.nf",
    ),
    StepSpec(
        "admet",
        "Predict ADMET properties",
        "nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf",
        "pharmacology",
    ),
    StepSpec(
        "docking_vina",
        "AutoDock Vina docking",
        "nextflow_nfcore/subworkflows/pharmacology/docking_autodock_vina/main.nf",
        "pharmacology",
    ),
    StepSpec(
        "gromacs_mmgbsa",
        "GROMACS MD + MM-GBSA",
        "nextflow_nfcore/subworkflows/drug_discovery/gromacs_protein_md/main.nf",
    ),
    StepSpec(
        "reinvent4",
        "REINVENT4 generative lead design",
        "nextflow_nfcore/subworkflows/drug_discovery/reinvent4_lead_design/main.nf",
    ),
]


def smiles_json_from_pharmacophore_filtered(manifest_steps: list[dict[str, Any]]) -> str | None:
    """
    If step 2 (pharmacophore) completed and downloaded filtered_compounds.smi, parse SMILES
    (first column) so ADMET and docking use the same ligands as the screen — not a static
    --smiles-json override unless the file is missing.
    """
    pharm = next((s for s in manifest_steps if s.get("key") == "pharmacophore"), None)
    if not pharm:
        return None
    adir = pharm.get("artifact_dir")
    if not adir:
        return None
    fp = Path(adir) / "filtered_compounds.smi"
    if not fp.is_file():
        return None
    out: list[str] = []
    for line in fp.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if not parts:
            continue
        smi = parts[0].strip()
        if smi:
            out.append(smi)
    if not out:
        return None
    return json.dumps(out)


def build_parameters_for_step(
    spec: StepSpec,
    args: argparse.Namespace,
    manifest_steps: list[dict[str, Any]],
) -> dict[str, Any]:
    if spec.key == "pocket":
        return {
            "pdb_input": args.pdb_input,
            "min_druggability": args.min_druggability,
            "min_volume": args.min_volume,
        }
    if spec.key == "pharmacophore":
        if not args.reference_actives_s3 or not args.compound_library_s3:
            raise ValueError("pharmacophore step requires --reference-actives-s3 and --compound-library-s3")
        return {
            "reference_actives": args.reference_actives_s3,
            "compound_library": args.compound_library_s3,
            "min_features": args.min_features,
        }
    if spec.key == "admet":
        smiles = smiles_json_from_pharmacophore_filtered(manifest_steps)
        if smiles is None:
            smiles = args.smiles_json
        if not smiles:
            # Demo-safe default (documented in predict_admet workflow)
            smiles = '["CC(=O)OC1=CC=CC=C1C(=O)O"]'
        return {"smiles_list": smiles, "ADMET_model_type": "MPNN"}
    if spec.key == "docking_vina":
        smiles = smiles_json_from_pharmacophore_filtered(manifest_steps)
        if smiles is None:
            if not args.smiles_json:
                raise ValueError(
                    "docking_vina requires --smiles-json when no pharmacophore "
                    "filtered_compounds.smi is available in the manifest"
                )
            smiles = args.smiles_json
        center = None
        box_size = [22.0, 22.0, 22.0]
        if args.use_top_pocket_box:
            pocket_entry = next((s for s in manifest_steps if s.get("key") == "pocket"), None)
            local_dir = (pocket_entry or {}).get("artifact_dir")
            pj = None
            if local_dir:
                pj = find_pockets_json(Path(local_dir))
            if pj:
                center = top_pocket_center(pj)
                try:
                    pdata = json.loads(pj.read_text(encoding="utf-8"))
                    vol = float((pdata.get("pockets") or [{}])[0].get("volume_A3") or 500.0)
                    box_size = list(volume_to_box_size(vol))
                except Exception:
                    pass
            if center is None:
                raise ValueError("Could not resolve top pocket center; run step 1 with downloads or pass explicit box")
        else:
            if args.box_center_json:
                center = tuple(json.loads(args.box_center_json))
            else:
                raise ValueError("Provide --use-top-pocket-box or --box-center-json '[x,y,z]'")
        if args.box_size_json:
            box_size = json.loads(args.box_size_json)
        return {
            "smiles_list": smiles,
            "receptor_pdb_file": args.pdb_input,
            "box_center": json.dumps(list(center)),
            "box_size": json.dumps(box_size),
            "ncpu": str(args.vina_ncpu),
            "exhaustiveness": str(args.vina_exhaustiveness),
        }
    if spec.key == "gromacs_mmgbsa":
        if not args.ligand_s3:
            raise ValueError("gromacs_mmgbsa step requires --ligand-s3 (e.g. docked ligand SDF on S3)")
        return {
            "receptor": args.pdb_input,
            "ligand": args.ligand_s3,
            "use_aws": True,
            "n_steps": args.gromacs_n_steps,
        }
    if spec.key == "reinvent4":
        seed = args.seed_smiles or "c1ccc2c(c1)ccc(=O)o2"
        params: dict[str, Any] = {
            "seed_smiles": seed,
            "mode": args.reinvent_mode,
            "n_steps": args.reinvent_n_steps,
            "scoring_function": args.reinvent_scoring,
        }
        if args.reinvent_scoring == "docking_gnina" and args.pdb_input:
            params["receptor"] = args.pdb_input
        return params
    raise ValueError(f"unknown step {spec.key}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--api-url", default=os.environ.get("BIOMATE_API_URL", "http://127.0.0.1:8081"))
    ap.add_argument("--user-id", default=f"andv-pipeline-{datetime.now(timezone.utc).strftime('%Y%m%d')}")
    ap.add_argument(
        "--pdb-input",
        required=True,
        help="Receptor: RCSB ID or s3:// path to PDB (must match Nextflow expectations)",
    )
    ap.add_argument(
        "--through-step",
        type=int,
        default=1,
        choices=[1, 2, 3, 4, 5, 6],
        help="Run steps 1..N (default 1)",
    )
    ap.add_argument("--poll-interval", type=int, default=20)
    ap.add_argument("--step-timeout", type=int, default=3600, help="Seconds per step (default 1h; increase for MD)")
    ap.add_argument("--min-druggability", type=float, default=0.35)
    ap.add_argument("--min-volume", type=float, default=200.0)
    ap.add_argument("--reference-actives-s3", default="", help="Step 2: S3 URI to reference SMILES")
    ap.add_argument("--compound-library-s3", default="", help="Step 2: S3 URI to screening library")
    ap.add_argument("--min-features", type=int, default=3)
    ap.add_argument(
        "--smiles-json",
        default="",
        help="Optional JSON array for ADMET/docking when step-2 filtered_compounds.smi is absent",
    )
    ap.add_argument("--use-top-pocket-box", action="store_true", help="Step 4: derive Vina box from step 1 *_pockets.json")
    ap.add_argument("--box-center-json", default="", help='Override pocket box: "[x,y,z]"')
    ap.add_argument("--box-size-json", default="", help='Override box edges: "[sx,sy,sz]"')
    ap.add_argument("--vina-ncpu", default="4")
    ap.add_argument("--vina-exhaustiveness", default="8")
    ap.add_argument("--ligand-s3", default="", help="Step 5: S3 .sdf/.mol2 URI, or SMILES string (GROMACS NF converts SMILES)")
    ap.add_argument("--gromacs-n-steps", type=int, default=5000000, help="MD steps (default ~10 ns at 2 fs)")
    ap.add_argument("--seed-smiles", default="", help="Step 6: REINVENT4 seed SMILES")
    ap.add_argument("--reinvent-mode", default="scaffold_decoration")
    ap.add_argument("--reinvent-n-steps", type=int, default=200)
    ap.add_argument("--reinvent-scoring", default="qed_sa", choices=["qed_sa", "docking_gnina", "custom_toml"])
    ap.add_argument("--skip-downloads", action="store_true", help="Do not aws s3 cp outputs after each step")
    ap.add_argument(
        "--append-to-run",
        default="",
        help="Path (relative to repo root) to an existing run dir with pipeline_manifest.json; "
        "only new steps through --through-step (or --append-only-keys) are executed.",
    )
    ap.add_argument(
        "--append-only-keys",
        default="",
        help="With --append-to-run only: run just these PIPELINE step keys (comma-separated), "
        "e.g. reinvent4 — skips gromacs_mmgbsa when MD is not needed or has failed. "
        "Steps are appended in the order listed; directories use canonical indices (e.g. 06_reinvent4).",
    )
    args = ap.parse_args()

    if args.through_step >= 2 and (not args.reference_actives_s3 or not args.compound_library_s3):
        log("Note: steps 2+ require --reference-actives-s3 and --compound-library-s3 for pharmacophore.")
    if args.through_step >= 4 and not args.smiles_json:
        log(
            "Note: docking uses 02_pharmacophore/filtered_compounds.smi when steps 1–2 run; "
            "--smiles-json only if pharmacophore is skipped or produced no hits."
        )

    api_key = load_api_key()

    append_dir = (ROOT / args.append_to_run).resolve() if args.append_to_run.strip() else None
    append_only = [x.strip() for x in args.append_only_keys.split(",") if x.strip()]
    if append_only and not append_dir:
        raise SystemExit("--append-only-keys requires --append-to-run")

    if append_dir:
        mf_path = append_dir / "pipeline_manifest.json"
        if not mf_path.is_file():
            raise SystemExit(f"--append-to-run: missing {mf_path}")
        manifest = json.loads(mf_path.read_text(encoding="utf-8"))
        run_root = append_dir
        # Stale manifest["error"] from a prior append misleads reviewers; each append is a fresh attempt.
        manifest.pop("error", None)
        done = len(manifest.get("steps") or [])
        present_keys = {e.get("key") for e in manifest.get("steps") or []}

        if append_only:
            unknown = set(append_only) - {s.key for s in PIPELINE}
            if unknown:
                raise SystemExit(f"--append-only-keys: unknown {unknown}")
            steps_to_run = []
            for k in append_only:
                if k in present_keys:
                    log(f"Skip {k}: already in manifest")
                    continue
                steps_to_run.append(next(s for s in PIPELINE if s.key == k))
            if not steps_to_run:
                log("Nothing to do: all requested keys already in manifest.")
                raise SystemExit(0)
            manifest["through_step"] = max(int(manifest.get("through_step") or 0), int(args.through_step))
            manifest["resumed_at"] = datetime.now(timezone.utc).isoformat()
            log(f"Appending selected keys to {run_root}: {[s.key for s in steps_to_run]}")
        elif args.through_step <= done:
            log(f"Nothing to do: manifest already has {done} steps, --through-step is {args.through_step}")
            raise SystemExit(0)
        else:
            steps_to_run = PIPELINE[done : args.through_step]
            manifest["through_step"] = args.through_step
            manifest["resumed_at"] = datetime.now(timezone.utc).isoformat()
            log(f"Appending to {run_root} (existing steps={done}, will run {len(steps_to_run)} more)")
    else:
        run_root = ROOT / "research/anti-virus/runs" / f"andv_nf_pipeline_{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
        run_root.mkdir(parents=True, exist_ok=True)
        manifest = {
            "created_at": datetime.now(timezone.utc).isoformat(),
            "api_url": args.api_url,
            "user_id": args.user_id,
            "pdb_input": args.pdb_input,
            "through_step": args.through_step,
            "steps": [],
        }
        steps_to_run = PIPELINE[: args.through_step]

    for spec in steps_to_run:
        idx = PIPELINE.index(spec) + 1
        log("")
        log("=" * 72)
        log(f"STEP {idx}/{len(PIPELINE)}: {spec.key} — {spec.title}")
        log("=" * 72)
        step_dir = run_root / f"{idx:02d}_{spec.key}"
        step_dir.mkdir(parents=True, exist_ok=True)

        try:
            params = build_parameters_for_step(spec, args, manifest["steps"])
        except ValueError as e:
            log(f"ABORT: {e}")
            manifest["error"] = str(e)
            (run_root / "pipeline_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
            raise SystemExit(2)

        (step_dir / "parameters.json").write_text(json.dumps(params, indent=2), encoding="utf-8")

        submit = post_execute(
            args.api_url,
            api_key,
            spec.nextflow_path,
            params,
            args.user_id,
            workflow_domain=spec.workflow_domain,
        )
        (step_dir / "submit.json").write_text(json.dumps(submit, indent=2), encoding="utf-8")
        run_id = submit.get("run_id")
        if not run_id:
            log(f"ABORT: no run_id in submit response: {json.dumps(submit)[:1500]}")
            raise SystemExit(3)

        status = poll_status(args.api_url, api_key, run_id, args.step_timeout, args.poll_interval)
        (step_dir / "status.json").write_text(json.dumps(status, indent=2), encoding="utf-8")

        st = status.get("status", "")
        if status.get("_timeout"):
            manifest["error"] = f"step {spec.key} timed out"
            (run_root / "pipeline_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
            raise SystemExit(4)
        if st not in {"completed", "succeeded"}:
            manifest["error"] = f"step {spec.key} ended with status {st!r}"
            (run_root / "pipeline_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
            raise SystemExit(5)

        downloaded: list[str] = []
        files = status.get("s3_output_files") or []
        if not files:
            files = fetch_output_files(args.api_url, api_key, run_id)
        if not args.skip_downloads:
            downloaded = download_useful_files(files, step_dir)

        entry: dict[str, Any] = {
            "key": spec.key,
            "title": spec.title,
            "nextflow_path": spec.nextflow_path,
            "run_id": run_id,
            "status": st,
            "artifact_dir": str(step_dir),
            "downloaded_files": downloaded,
        }
        pj = find_pockets_json(step_dir)
        if pj:
            entry["pockets_json"] = str(pj)
            ctr = top_pocket_center(pj)
            if ctr:
                entry["top_pocket_center"] = list(ctr)

        manifest["steps"].append(entry)
        (run_root / "pipeline_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        log(f"Step {spec.key} finished ({st}). Manifest updated.")

    log("")
    log(f"Done. Manifest: {run_root / 'pipeline_manifest.json'}")
    log("See docs/20260509_ANDV_NEXTFLOW_PIPELINE_EXECUTION.md for interpretation and next actions.")


if __name__ == "__main__":
    main()
