#!/usr/bin/env python3
"""Dock pharmacophore-filtered ZINC deck on 9P3I via local BioMate → AWS Batch.

Runs until Vina completes, copies results to zinc600_pharmacophore/vina/, writes summary.

  python3 research/anti-virus/scripts/run_zinc_pharmacophore_docking.py
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
LIBRARY = PUB / "zinc600_pharmacophore/zinc600_pharmacophore_filtered.smi"
OUT_DIR = PUB / "zinc600_pharmacophore/vina"
BASELINE_RUN = ROOT / "research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z"
DOCK_SCRIPT = ROOT / "research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py"
RAW_RESULTS = PUB / "zinc150_screen/vina/docking_autodock_vina_results.json"
PDB_S3 = "s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb"


def log(msg: str) -> None:
    print(msg, flush=True)


def load_smiles(path: Path) -> list[str]:
    return [ln.strip().split()[0] for ln in path.read_text(encoding="utf-8").splitlines() if ln.strip() and not ln.startswith("#")]


def api_up(url: str = "http://127.0.0.1:8081") -> bool:
    try:
        urllib.request.urlopen(url, timeout=3)
        return True
    except Exception:
        return False


def step_dir_for_suffix(suffix: str) -> Path:
    return BASELINE_RUN / f"04_docking_vina_{suffix}"


def write_summary(results: dict[str, Any], library_smiles: set[str]) -> None:
    rows = [
        r
        for r in results.get("results") or []
        if r.get("smiles") in library_smiles and r.get("best_affinity_kcal_mol") is not None
    ]
    rows.sort(key=lambda r: float(r["best_affinity_kcal_mol"]))
    raw_by: dict[str, float] = {}
    if RAW_RESULTS.is_file():
        raw = json.loads(RAW_RESULTS.read_text(encoding="utf-8"))
        raw_by = {
            r["smiles"]: float(r["best_affinity_kcal_mol"])
            for r in raw.get("results") or []
            if r.get("smiles") and r.get("best_affinity_kcal_mol") is not None
        }

    lines = [
        "# Pharmacophore-filtered ZINC — Vina results (9P3I rigid)",
        "",
        f"_Generated: {datetime.now(timezone.utc).isoformat()}_",
        "",
        f"- Library: **{len(library_smiles)}** compounds",
        f"- Docked: **{len(rows)}**",
        "",
        "| Rank | Vina (kcal/mol) | vs raw AAAC | SMILES |",
        "| ---: | ---: | ---: | --- |",
    ]
    for i, r in enumerate(rows[:20], 1):
        sm = r["smiles"]
        aff = float(r["best_affinity_kcal_mol"])
        raw = raw_by.get(sm)
        delta = f"{aff - raw:+.3f}" if raw is not None else "—"
        lines.append(f"| {i} | {aff:.3f} | {delta} | `{sm[:40]}` |")

    inh01 = "N=C(N)NC(=O)c1nccnc1N"
    inh_row = next((r for r in rows if r["smiles"] == inh01), None)
    if inh_row:
        lines.extend(
            [
                "",
                "## INH-01 (compute lead)",
                "",
                f"- Vina: **{float(inh_row['best_affinity_kcal_mol']):.3f} kcal/mol**",
                f"- Rank: **{rows.index(inh_row) + 1} / {len(rows)}** in pharmacophore deck",
            ]
        )
    (OUT_DIR / "ZINC_PHARMACOPHORE_VINA_SUMMARY.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def download_docking_json(step_dir: Path, dest: Path) -> bool:
    src = step_dir / "docking_autodock_vina_results.json"
    if src.is_file():
        shutil.copy2(src, dest)
        return True
    status_path = step_dir / "status.json"
    if not status_path.is_file():
        return False
    st = json.loads(status_path.read_text(encoding="utf-8"))
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


def finalize_from_step_dir(step_dir: Path, library_smiles: set[str], run_meta: dict[str, Any]) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    dest = OUT_DIR / "docking_autodock_vina_results.json"
    if not download_docking_json(step_dir, dest):
        raise SystemExit(f"Missing docking JSON in {step_dir} (check status.json / S3)")
    data = json.loads(dest.read_text(encoding="utf-8"))
    data.update(run_meta)
    data.update(run_meta)
    dest.write_text(json.dumps(data, indent=2), encoding="utf-8")
    write_summary(data, library_smiles)
    n = len([r for r in data.get("results") or [] if r.get("smiles") in library_smiles])
    log(f"Done: {n}/{len(library_smiles)} → {dest}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--api-url", default="http://127.0.0.1:8081")
    ap.add_argument("--step-suffix", default=None)
    ap.add_argument("--finalize-only", action="store_true")
    args = ap.parse_args()

    library_smiles = set(load_smiles(LIBRARY))
    state_path = OUT_DIR / "dock_run.json"

    if args.finalize_only:
        state = json.loads(state_path.read_text(encoding="utf-8"))
        finalize_from_step_dir(step_dir_for_suffix(state["step_suffix"]), library_smiles, state)
        return

    if not LIBRARY.is_file():
        raise SystemExit(f"Missing {LIBRARY}")
    if not api_up(args.api_url):
        raise SystemExit(f"Start BioMate API first ({args.api_url})")

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    suffix = args.step_suffix or f"pharm_{stamp}"
    smiles = load_smiles(LIBRARY)
    s3_lib = f"s3://biomate-nextflow-work/inputs/andv_campaign/zinc600_pharmacophore/{stamp}/library.smi"
    subprocess.run(["aws", "s3", "cp", str(LIBRARY), s3_lib], check=False)

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
        json.dumps(smiles),
        "--use-top-pocket-box",
        "--skip-downloads",
        "--step-timeout",
        "7200",
        "--poll-interval",
        "30",
        "--user-id",
        f"zinc-pharm-{stamp[:8]}",
    ]
    log(f"Docking {len(smiles)} compounds (suffix={suffix}) …")
    rc = subprocess.run(cmd, cwd=str(ROOT))
    submit_path = step_dir_for_suffix(suffix) / "submit.json"
    run_id = None
    if submit_path.is_file():
        run_id = json.loads(submit_path.read_text(encoding="utf-8")).get("run_id")

    state = {
        "submitted_at": datetime.now(timezone.utc).isoformat(),
        "step_suffix": suffix,
        "n_compounds": len(smiles),
        "run_id": run_id,
        "s3_library": s3_lib,
        "returncode": rc.returncode,
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state, indent=2), encoding="utf-8")

    if rc.returncode != 0:
        raise SystemExit(f"Pipeline failed rc={rc.returncode} (run_id={run_id})")

    state["status"] = "completed"
    state["completed_at"] = datetime.now(timezone.utc).isoformat()
    finalize_from_step_dir(step_dir_for_suffix(suffix), library_smiles, state)
    state_path.write_text(json.dumps(state, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
