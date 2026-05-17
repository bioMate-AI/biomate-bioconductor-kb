#!/usr/bin/env python3
"""
Parallel ANDV screening tracks (library vs REINVENT4) → ADMET → Vina.

Branch A — Open-library screening:
  predict_admet_properties → docking_autodock_vina on the first N SMILES from a local .smi file.

Branch B — Pocket-aware generation:
  reinvent4_lead_design (scoring_function=docking_gnina) → parse generated_molecules.csv →
  predict_admet_properties → docking_autodock_vina on the top generated SMILES.

Requires local *_pockets.json (from a completed pocket run) for Vina box geometry.

Usage:
  python3 research/anti-virus/scripts/download_open_screening_library.py --max-compounds 400

  python3 research/anti-virus/scripts/run_parallel_library_vs_generative.py \\
    --pdb-input s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb \\
    --pockets-json research/anti-virus/runs/.../01_pocket/structure_pockets.json \\
    --library-smi research/anti-virus/libraries/delaney_esol_*.smi \\
    --seed-smiles c1ccc(O)cc1 \\
    --max-library-compounds 300

Environment: GALAXY_API_KEY or bootstrap_admin_api_key in backend/config/galaxy.yml.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]


def log(msg: str) -> None:
    print(msg, flush=True)


def load_api_key() -> str:
    if os.environ.get("GALAXY_API_KEY"):
        return os.environ["GALAXY_API_KEY"]
    text = (ROOT / "backend/config/galaxy.yml").read_text(encoding="utf-8")
    m = re.search(r"bootstrap_admin_api_key:\s*(\S+)", text)
    if not m:
        raise SystemExit("Set GALAXY_API_KEY or bootstrap_admin_api_key in backend/config/galaxy.yml")
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


def execute_nf(
    api_url: str,
    api_key: str,
    nextflow_path: str,
    parameters: dict[str, Any],
    user_id: str,
    workflow_domain: str,
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


def poll_until_done(api_url: str, api_key: str, run_id: str, label: str, timeout_sec: int, poll_interval: int) -> dict[str, Any]:
    terminal = {"completed", "succeeded", "failed", "cancelled", "error"}
    deadline = time.time() + timeout_sec
    last: dict[str, Any] = {}
    while time.time() < deadline:
        last = request_json(api_url, api_key, "GET", f"/api/nextflow/status/{run_id}", timeout=120)
        st = last.get("status", "")
        log(f"  [{label}] {run_id[:8]}… status={st!r}")
        if st in terminal:
            return last
        time.sleep(poll_interval)
    last["_timeout"] = True
    return last


def pocket_geometry(pockets_path: Path) -> tuple[list[float], list[float]]:
    data = json.loads(pockets_path.read_text(encoding="utf-8"))
    pockets = data.get("pockets") or []
    if not pockets:
        raise SystemExit(f"No pockets in {pockets_path}")
    top = pockets[0]
    cx, cy, cz = float(top["center_x"]), float(top["center_y"]), float(top["center_z"])
    vol = float(top.get("volume_A3") or 500.0)
    r = max(8.0, (3.0 * vol / (4.0 * math.pi)) ** (1.0 / 3.0) * 1.8)
    edge = min(40.0, 2.2 * r)
    return [cx, cy, cz], [edge, edge, edge]


def read_smiles_library(path: Path, max_n: int) -> list[str]:
    out: list[str] = []
    with path.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.strip().split()
            if not parts:
                continue
            out.append(parts[0])
            if len(out) >= max_n:
                break
    if not out:
        raise SystemExit(f"No SMILES read from {path}")
    return out


def branch_library_screen(
    api_url: str,
    api_key: str,
    pdb_input: str,
    box_center: list[float],
    box_size: list[float],
    smiles: list[str],
    user_id: str,
    work_dir: Path,
    timeouts: tuple[int, int],
) -> dict[str, Any]:
    """ADMET → Vina for fixed smiles list."""
    work_dir.mkdir(parents=True, exist_ok=True)
    admet_path = "nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf"
    dock_path = "nextflow_nfcore/subworkflows/pharmacology/docking_autodock_vina/main.nf"
    sm_json = json.dumps(smiles)

    log("[branch-A] predict_admet_properties …")
    sub = execute_nf(
        api_url,
        api_key,
        admet_path,
        {"smiles_list": sm_json, "ADMET_model_type": "MPNN"},
        user_id + "-lib-admet",
        "pharmacology",
    )
    rid = sub.get("run_id")
    if not rid:
        return {"branch": "library", "error": "no run_id admet", "submit": sub}
    st = poll_until_done(api_url, api_key, rid, "lib-admet", timeouts[0], 20)
    (work_dir / "branch_a_admet_status.json").write_text(json.dumps(st, indent=2), encoding="utf-8")
    if st.get("status") not in {"succeeded", "completed"}:
        return {"branch": "library", "error": f"admet failed {st.get('status')}", "status": st}

    log("[branch-A] docking_autodock_vina …")
    dock_params = {
        "smiles_list": sm_json,
        "receptor_pdb_file": pdb_input,
        "box_center": json.dumps(box_center),
        "box_size": json.dumps(box_size),
        "ncpu": "4",
        "exhaustiveness": "8",
    }
    sub2 = execute_nf(api_url, api_key, dock_path, dock_params, user_id + "-lib-dock", "pharmacology")
    rid2 = sub2.get("run_id")
    if not rid2:
        return {"branch": "library", "error": "no run_id dock", "submit": sub2}
    st2 = poll_until_done(api_url, api_key, rid2, "lib-dock", timeouts[1], 20)
    (work_dir / "branch_a_dock_status.json").write_text(json.dumps(st2, indent=2), encoding="utf-8")
    return {"branch": "library", "admet_run_id": rid, "dock_run_id": rid2, "dock_status": st2}


def parse_generated_csv(path: Path, top_n: int) -> list[str]:
    """Parse REINVENT CSV; strip R-group placeholders ([*]) for downstream RDKit/Vina."""

    def sanitize(sm: str) -> str:
        s = sm.strip()
        if "[*]" in s:
            s = s.replace("[*]", "")  # drop attachment point for a quick-dockable capping estimate
        return s

    smiles_col = None
    with path.open(encoding="utf-8", errors="replace") as f:
        r = csv.DictReader(f)
        if not r.fieldnames:
            return []
        lower = {h.lower(): h for h in r.fieldnames}
        for candidate in ("smiles", "SMILES", "canonical_smiles"):
            if candidate.lower() in lower:
                smiles_col = lower[candidate.lower()]
                break
        if smiles_col is None:
            smiles_col = r.fieldnames[0]
        out: list[str] = []
        for row in r:
            sm = sanitize(row.get(smiles_col) or "")
            if sm and sm not in out:
                out.append(sm)
            if len(out) >= top_n:
                break
    return out


def aws_cp(uri: str, dest: Path) -> bool:
    r = subprocess.run(["aws", "s3", "cp", uri, str(dest)], capture_output=True, text=True, check=False)
    return r.returncode == 0


def fetch_generated_csv_from_run(
    api_url: str,
    api_key: str,
    run_id: str,
    dest: Path,
    status_payload: dict[str, Any] | None = None,
) -> Path | None:
    """Download REINVENT4 CSV: REST output_files + same keys already on status (s3_output_files)."""
    merged: list[Any] = []
    try:
        payload = request_json(api_url, api_key, "GET", f"/api/nextflow/runs/{run_id}/output_files", timeout=120)
        merged.extend(payload.get("files") if isinstance(payload, dict) else [])
    except Exception:
        pass
    if status_payload:
        merged.extend(status_payload.get("s3_output_files") or [])

    generated_uri = ""
    raw_uri = ""
    other_csv: list[str] = []
    for item in merged:
        if not isinstance(item, dict):
            continue
        name = (item.get("name") or item.get("filename") or "").lower()
        uri = item.get("s3_uri") or ""
        if not uri.endswith(".csv"):
            continue
        if "generated_molecules" in name:
            generated_uri = uri
        elif "raw_molecules" in name:
            raw_uri = uri
        else:
            other_csv.append(uri)
    for uri in [generated_uri, raw_uri] + other_csv:
        if uri and aws_cp(uri, dest):
            return dest
    return None


def branch_generative_design(
    api_url: str,
    api_key: str,
    pdb_input: str,
    box_center: list[float],
    box_size: list[float],
    seed_smiles: str,
    reinvent_steps: int,
    user_id: str,
    work_dir: Path,
    timeouts: tuple[int, int, int],
    top_gen: int,
) -> dict[str, Any]:
    work_dir.mkdir(parents=True, exist_ok=True)
    nf = "nextflow_nfcore/subworkflows/drug_discovery/reinvent4_lead_design/main.nf"
    params = {
        "seed_smiles": seed_smiles,
        "mode": "scaffold_decoration",
        "scoring_function": "docking_gnina",
        "receptor": pdb_input,
        "n_steps": reinvent_steps,
        "batch_size": 128,
        "top_n": max(50, top_gen),
        "gpu": True,
    }
    log("[branch-B] REINVENT4 (docking_gnina) …")
    sub = execute_nf(api_url, api_key, nf, params, user_id + "-reinvent", "drug_discovery")
    rid = sub.get("run_id")
    if not rid:
        return {"branch": "generative", "error": "no run_id reinvent", "submit": sub}
    st = poll_until_done(api_url, api_key, rid, "reinvent", timeouts[0], 30)
    (work_dir / "branch_b_reinvent_status.json").write_text(json.dumps(st, indent=2), encoding="utf-8")
    if st.get("status") not in {"succeeded", "completed"}:
        return {"branch": "generative", "error": f"reinvent failed {st.get('status')}", "status": st}

    csv_path = work_dir / "reinvent_molecules.csv"
    got = fetch_generated_csv_from_run(api_url, api_key, rid, csv_path, st)
    if not got or not csv_path.is_file():
        outdir = (st.get("outdir") or "").rstrip("/")
        if outdir.startswith("s3://"):
            for suffix in ("generated_molecules.csv", "rl/raw_molecules.csv"):
                attempt = f"{outdir}/{suffix}"
                log(f"[branch-B] trying {attempt}")
                if aws_cp(attempt, csv_path):
                    break
    if not csv_path.is_file():
        return {"branch": "generative", "error": "could not download REINVENT CSV (generated or raw)", "reinvent_run_id": rid}

    gen_smiles = parse_generated_csv(csv_path, top_gen)
    if not gen_smiles:
        return {"branch": "generative", "error": "no smiles parsed from csv", "csv": str(csv_path)}

    sm_json = json.dumps(gen_smiles)
    log(f"[branch-B] ADMET + Vina on {len(gen_smiles)} generated SMILES …")
    admet_path = "nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf"
    dock_path = "nextflow_nfcore/subworkflows/pharmacology/docking_autodock_vina/main.nf"

    sub_a = execute_nf(
        api_url,
        api_key,
        admet_path,
        {"smiles_list": sm_json, "ADMET_model_type": "MPNN"},
        user_id + "-gen-admet",
        "pharmacology",
    )
    ra = sub_a.get("run_id")
    if not ra:
        return {"branch": "generative", "error": "no gen admet run_id"}
    sta = poll_until_done(api_url, api_key, ra, "gen-admet", timeouts[1], 20)
    sub_d = execute_nf(
        api_url,
        api_key,
        dock_path,
        {
            "smiles_list": sm_json,
            "receptor_pdb_file": pdb_input,
            "box_center": json.dumps(box_center),
            "box_size": json.dumps(box_size),
            "ncpu": "4",
            "exhaustiveness": "8",
        },
        user_id + "-gen-dock",
        "pharmacology",
    )
    rd = sub_d.get("run_id")
    std = poll_until_done(api_url, api_key, rd, "gen-dock", timeouts[2], 20) if rd else {}
    return {
        "branch": "generative",
        "reinvent_run_id": rid,
        "generated_smiles_n": len(gen_smiles),
        "admet_run_id": ra,
        "dock_run_id": rd,
        "dock_status": std,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--api-url", default=os.environ.get("BIOMATE_API_URL", "http://127.0.0.1:8081"))
    ap.add_argument("--pdb-input", required=True, help="Receptor PDB (s3:// or PDB ID)")
    ap.add_argument("--pockets-json", required=True, type=Path, help="Local *_pockets.json from pocket run")
    ap.add_argument("--library-smi", required=True, type=Path, help="Local .smi file (open library)")
    ap.add_argument("--max-library-compounds", type=int, default=250)
    ap.add_argument("--seed-smiles", default="c1ccc(O)cc1", help="REINVENT4 seed (fragment hypothesis)")
    ap.add_argument("--reinvent-n-steps", type=int, default=200)
    ap.add_argument("--top-generated", type=int, default=40, help="Max generated SMILES to triage after REINVENT4")
    ap.add_argument("--user-id", default=f"andv-parallel-{datetime.now(timezone.utc).strftime('%Y%m%d')}")
    ap.add_argument("--timeout-admet", type=int, default=3600)
    ap.add_argument("--timeout-dock", type=int, default=7200)
    ap.add_argument("--timeout-reinvent", type=int, default=14400)
    args = ap.parse_args()

    api_key = load_api_key()
    box_c, box_s = pocket_geometry(args.pockets_json.resolve())

    lib_smiles = read_smiles_library(args.library_smi.resolve(), args.max_library_compounds)
    log(f"Loaded {len(lib_smiles)} library SMILES from {args.library_smi}")

    run_root = ROOT / "research/anti-virus/runs" / f"parallel_vs_gen_{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
    run_root.mkdir(parents=True, exist_ok=True)
    meta = {
        "pdb_input": args.pdb_input,
        "pockets_json": str(args.pockets_json),
        "library_smi": str(args.library_smi),
        "seed_smiles": args.seed_smiles,
        "box_center": box_c,
        "box_size": box_s,
        "library_smiles_count": len(lib_smiles),
    }
    (run_root / "run_config.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")

    (run_root / "branch_library").mkdir(parents=True, exist_ok=True)
    (run_root / "branch_generative").mkdir(parents=True, exist_ok=True)

    results: dict[str, Any] = {}
    with ThreadPoolExecutor(max_workers=2) as ex:
        f_lib = ex.submit(
            branch_library_screen,
            args.api_url,
            api_key,
            args.pdb_input,
            box_c,
            box_s,
            lib_smiles,
            args.user_id,
            run_root / "branch_library",
            (args.timeout_admet, args.timeout_dock),
        )
        f_gen = ex.submit(
            branch_generative_design,
            args.api_url,
            api_key,
            args.pdb_input,
            box_c,
            box_s,
            args.seed_smiles,
            args.reinvent_n_steps,
            args.user_id,
            run_root / "branch_generative",
            (args.timeout_reinvent, args.timeout_admet, args.timeout_dock),
            args.top_generated,
        )
        futs = {f_lib: "library", f_gen: "generative"}
        for fut in as_completed(futs):
            name = futs[fut]
            try:
                results[name] = fut.result()
            except Exception as e:  # noqa: BLE001
                results[name] = {"error": str(e)}

    (run_root / "parallel_results.json").write_text(json.dumps(results, indent=2, default=str), encoding="utf-8")
    log("Done.")
    log(json.dumps(results, indent=2, default=str))
    errs = [k for k, v in results.items() if isinstance(v, dict) and v.get("error")]
    if errs:
        raise SystemExit(3)


if __name__ == "__main__":
    main()
