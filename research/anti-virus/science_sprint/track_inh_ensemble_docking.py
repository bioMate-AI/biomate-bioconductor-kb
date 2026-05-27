#!/usr/bin/env python3
"""
Publication sprint — ensemble AutoDock Vina docking across multiple receptor conformations.

Loads rigid-receptor baseline scores, docks the same SMILES against a receptor ensemble
(top pocket + deposited full structures), aggregates best affinity per compound, and flags
improvements vs the rigid baseline.

Requires:
  - BioMate Galaxy API running (default http://127.0.0.1:8081)
  - GALAXY_API_KEY or bootstrap_admin_api_key in backend/config/galaxy.yml
  - AWS CLI configured for uploading local PDBs and downloading docking outputs

Dependencies: Python stdlib + urllib only (CIF→PDB via subprocess to cif_to_pdb.py; S3 via aws CLI).

Usage:
  python3 research/anti-virus/science_sprint/track_inh_ensemble_docking.py

  python3 research/anti-virus/science_sprint/track_inh_ensemble_docking.py \\
    --baseline-run research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z \\
    --dry-run
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
ANTI_VIRUS = ROOT / "research/anti-virus"
DEFAULT_BASELINE_RUN = ANTI_VIRUS / "runs/andv_nf_pipeline_20260513T032000Z"
STRUCTURES_DIR = ANTI_VIRUS / "structures"
CIF_TO_PDB = ANTI_VIRUS / "scripts/cif_to_pdb.py"
GUO_DEPOSIT_IDS = ("9P3I", "9P3Y", "9P3X")
DOCK_NF = "nextflow_nfcore/subworkflows/pharmacology/docking_autodock_vina/main.nf"
KNOWN_S3_RECEPTORS: dict[str, str] = {
    "9P3I": "s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb",
    "9P3I_top_pocket_only": "s3://biomate-nextflow-work/inputs/andv_campaign/20260514/9P3I_top_pocket_only.pdb",
}


def log(msg: str) -> None:
    print(msg, flush=True)


def load_api_key() -> str:
    if os.environ.get("GALAXY_API_KEY"):
        return os.environ["GALAXY_API_KEY"]
    gal = ROOT / "backend/config/galaxy.yml"
    text = gal.read_text(encoding="utf-8")
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


def poll_until_done(
    api_url: str,
    api_key: str,
    run_id: str,
    label: str,
    timeout_sec: int,
    poll_interval: int,
) -> dict[str, Any]:
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


def aws_cp(src: str, dest: Path | str, *, upload: bool = False) -> bool:
    if upload:
        cmd = ["aws", "s3", "cp", str(src), str(dest)]
    else:
        cmd = ["aws", "s3", "cp", str(src), str(dest)]
    r = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if r.returncode != 0:
        log(f"  aws s3 cp failed: {r.stderr.strip() or r.stdout.strip()}")
    return r.returncode == 0


def cif_to_pdb_subprocess(cif_path: Path, pdb_path: Path) -> None:
    pdb_path.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(
        [sys.executable, str(CIF_TO_PDB), str(cif_path), "-o", str(pdb_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if r.returncode != 0 or not pdb_path.is_file():
        raise RuntimeError(f"cif_to_pdb failed for {cif_path}: {r.stderr.strip() or r.stdout.strip()}")


def deposit_id_from_stem(stem: str) -> str | None:
    m = re.match(r"^([0-9][A-Za-z0-9]{3})$", stem)
    return m.group(1).upper() if m else None


def resolve_local_pdb(deposit_id: str, work_receptors: Path) -> Path | None:
    """Return a local PDB for a deposit ID from structures/ (.pdb or converted .cif)."""
    for ext in (".pdb", ".cif"):
        candidate = STRUCTURES_DIR / f"{deposit_id}{ext}"
        if not candidate.is_file():
            continue
        if ext == ".pdb":
            return candidate
        out = work_receptors / f"{deposit_id}.pdb"
        if not out.is_file():
            cif_to_pdb_subprocess(candidate, out)
        return out
    return None


def build_receptor_ensemble(baseline_run: Path, work_dir: Path) -> list[dict[str, Any]]:
    """
    Build ordered receptor conformers:
      1. Top pocket PDB from baseline pocket step
      2. Guo deposits 9P3I, 9P3Y, 9P3X (when files exist locally or on known S3)
      3. Any other *.pdb / *.cif in structures/ not already included
    """
    work_receptors = work_dir / "receptors"
    work_receptors.mkdir(parents=True, exist_ok=True)
    conformers: list[dict[str, Any]] = []
    seen_ids: set[str] = set()

    top_pocket = baseline_run / "01_pocket/structure_top_pocket.pdb"
    if top_pocket.is_file():
        conformers.append(
            {
                "label": "top_pocket",
                "deposit_id": None,
                "source": str(top_pocket),
                "local_pdb": top_pocket,
                "known_s3": KNOWN_S3_RECEPTORS.get("9P3I_top_pocket_only"),
            }
        )
    else:
        log(f"WARNING: missing top pocket PDB: {top_pocket}")

    for deposit_id in GUO_DEPOSIT_IDS:
        if deposit_id in seen_ids:
            continue
        local = resolve_local_pdb(deposit_id, work_receptors)
        if local:
            seen_ids.add(deposit_id)
            conformers.append(
                {
                    "label": deposit_id,
                    "deposit_id": deposit_id,
                    "source": str(local),
                    "local_pdb": local,
                    "known_s3": KNOWN_S3_RECEPTORS.get(deposit_id),
                }
            )
            continue
        known = KNOWN_S3_RECEPTORS.get(deposit_id)
        if known:
            seen_ids.add(deposit_id)
            conformers.append(
                {
                    "label": deposit_id,
                    "deposit_id": deposit_id,
                    "source": known,
                    "local_pdb": None,
                    "known_s3": known,
                }
            )

    for path in sorted(STRUCTURES_DIR.glob("*")):
        if not path.is_file() or path.name.startswith("."):
            continue
        if path.suffix.lower() not in {".pdb", ".cif"}:
            continue
        dep = deposit_id_from_stem(path.stem)
        if dep and dep in seen_ids:
            continue
        label = dep or path.stem
        if path.suffix.lower() == ".pdb":
            local_pdb = path
        else:
            local_pdb = work_receptors / f"{path.stem}.pdb"
            if not local_pdb.is_file():
                cif_to_pdb_subprocess(path, local_pdb)
        if dep:
            seen_ids.add(dep)
        conformers.append(
            {
                "label": label,
                "deposit_id": dep,
                "source": str(path),
                "local_pdb": local_pdb,
                "known_s3": KNOWN_S3_RECEPTORS.get(dep) if dep else None,
            }
        )

    if not conformers:
        raise SystemExit("No receptor conformers found — check baseline pocket PDB and structures/")
    return conformers


def stage_receptor_s3(conformer: dict[str, Any], s3_prefix: str, ts: str) -> str:
    """Return S3 URI for receptor_pdb_file parameter."""
    if conformer.get("known_s3") and conformer.get("local_pdb") is None:
        return conformer["known_s3"]
    local = conformer.get("local_pdb")
    if local is None or not Path(local).is_file():
        raise RuntimeError(f"No local PDB to upload for conformer {conformer['label']!r}")
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", conformer["label"])
    uri = f"{s3_prefix.rstrip('/')}/science_sprint/{ts}/{safe}.pdb"
    if not aws_cp(local, uri, upload=True):
        known = conformer.get("known_s3")
        if known:
            log(f"  upload failed; falling back to known S3 for {conformer['label']}: {known}")
            return known
        raise RuntimeError(f"Failed to upload {local} to {uri}")
    return uri


def load_baseline(baseline_run: Path) -> dict[str, Any]:
    path = baseline_run / "04_docking_vina/docking_autodock_vina_results.json"
    if not path.is_file():
        raise SystemExit(f"Baseline docking results not found: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    by_smiles: dict[str, float] = {}
    smiles_order: list[str] = []
    for row in data.get("results") or []:
        sm = row.get("smiles")
        aff = row.get("best_affinity_kcal_mol")
        if sm is None or aff is None:
            continue
        smiles_order.append(sm)
        by_smiles[sm] = float(aff)
    if not smiles_order:
        raise SystemExit(f"No SMILES in baseline results: {path}")
    return {
        "path": str(path),
        "raw": data,
        "smiles_list": smiles_order,
        "by_smiles": by_smiles,
    }


def fetch_output_files(api_url: str, api_key: str, run_id: str) -> list[Any]:
    try:
        payload = request_json(api_url, api_key, "GET", f"/api/nextflow/runs/{run_id}/output_files", timeout=120)
        if isinstance(payload, dict):
            return payload.get("files") or []
        return list(payload) if payload else []
    except Exception:
        return []


def download_docking_results(
    api_url: str,
    api_key: str,
    status: dict[str, Any],
    dest: Path,
) -> Path | None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    merged: list[Any] = list(status.get("s3_output_files") or [])
    run_id = status.get("run_id") or status.get("invocation_id") or ""
    if run_id:
        merged.extend(fetch_output_files(api_url, api_key, run_id))

    target_name = "docking_autodock_vina_results.json"
    for item in merged:
        if not isinstance(item, dict):
            continue
        name = (item.get("filename") or item.get("name") or "").lower()
        uri = item.get("s3_uri") or ""
        if name == target_name and uri:
            if aws_cp(uri, dest):
                return dest

    outdir = (status.get("outdir") or "").rstrip("/")
    if outdir.startswith("s3://"):
        attempt = f"{outdir}/{target_name}"
        if aws_cp(attempt, dest):
            return dest
    return None


def dock_one_conformer(
    api_url: str,
    api_key: str,
    conformer: dict[str, Any],
    receptor_s3: str,
    smiles_list: list[str],
    box_center: list[float],
    box_size: list[float],
    user_id: str,
    work_dir: Path,
    timeout_sec: int,
    poll_interval: int,
    dry_run: bool,
) -> dict[str, Any]:
    label = conformer["label"]
    cdir = work_dir / "conformers" / label
    cdir.mkdir(parents=True, exist_ok=True)

    dock_params = {
        "smiles_list": json.dumps(smiles_list),
        "receptor_pdb_file": receptor_s3,
        "box_center": json.dumps(box_center),
        "box_size": json.dumps(box_size),
        "ncpu": "4",
        "exhaustiveness": "8",
    }
    (cdir / "parameters.json").write_text(json.dumps(dock_params, indent=2), encoding="utf-8")

    record: dict[str, Any] = {
        "label": label,
        "deposit_id": conformer.get("deposit_id"),
        "receptor_source": conformer.get("source"),
        "receptor_s3": receptor_s3,
    }

    if dry_run:
        record["dry_run"] = True
        return record

    log(f"[{label}] docking_autodock_vina …")
    sub = execute_nf(
        api_url,
        api_key,
        DOCK_NF,
        dock_params,
        f"{user_id}-{label}",
        "pharmacology",
    )
    (cdir / "submit.json").write_text(json.dumps(sub, indent=2), encoding="utf-8")
    run_id = sub.get("run_id")
    if not run_id:
        record["error"] = "no run_id from execute"
        record["submit"] = sub
        return record

    st = poll_until_done(api_url, api_key, run_id, label, timeout_sec, poll_interval)
    (cdir / "status.json").write_text(json.dumps(st, indent=2), encoding="utf-8")
    record["run_id"] = run_id
    record["status"] = st.get("status")

    if st.get("status") not in {"succeeded", "completed"}:
        record["error"] = f"docking ended with status={st.get('status')!r}"
        if st.get("_timeout"):
            record["error"] = "polling timeout"
        return record

    results_path = cdir / "docking_autodock_vina_results.json"
    got = download_docking_results(api_url, api_key, st, results_path)
    if not got:
        record["error"] = "could not download docking_autodock_vina_results.json"
        return record

    dock_data = json.loads(results_path.read_text(encoding="utf-8"))
    record["results_path"] = str(results_path)
    record["by_smiles"] = {
        row["smiles"]: float(row["best_affinity_kcal_mol"])
        for row in dock_data.get("results") or []
        if row.get("smiles") is not None and row.get("best_affinity_kcal_mol") is not None
    }
    return record


def aggregate_ensemble(
    baseline: dict[str, Any],
    conformer_records: list[dict[str, Any]],
) -> dict[str, Any]:
    smiles_list = baseline["smiles_list"]
    baseline_by = baseline["by_smiles"]
    compounds: list[dict[str, Any]] = []

    for sm in smiles_list:
        base_aff = baseline_by.get(sm)
        per_conf: dict[str, float | None] = {}
        best_aff: float | None = None
        best_label: str | None = None

        for rec in conformer_records:
            label = rec["label"]
            by_sm = rec.get("by_smiles") or {}
            aff = by_sm.get(sm)
            per_conf[label] = aff
            if aff is not None and (best_aff is None or aff < best_aff):
                best_aff = aff
                best_label = label

        improved = False
        delta: float | None = None
        if base_aff is not None and best_aff is not None:
            delta = best_aff - base_aff
            improved = best_aff < base_aff

        compounds.append(
            {
                "smiles": sm,
                "baseline_affinity_kcal_mol": base_aff,
                "ensemble_best_affinity_kcal_mol": best_aff,
                "ensemble_best_conformer": best_label,
                "delta_kcal_mol": delta,
                "improved_vs_baseline": improved,
                "per_conformer_affinity_kcal_mol": per_conf,
            }
        )

    n_improved = sum(1 for c in compounds if c["improved_vs_baseline"])
    best_overall = min(
        (c for c in compounds if c["ensemble_best_affinity_kcal_mol"] is not None),
        key=lambda c: c["ensemble_best_affinity_kcal_mol"],
        default=None,
    )
    return {
        "n_compounds": len(compounds),
        "n_improved_vs_baseline": n_improved,
        "best_compound": best_overall,
        "compounds": compounds,
    }


def write_summary_md(
    path: Path,
    meta: dict[str, Any],
    conformers: list[dict[str, Any]],
    conformer_records: list[dict[str, Any]],
    aggregate: dict[str, Any],
) -> None:
    lines = [
        "# Ensemble Vina docking — inhibitor track",
        "",
        f"Generated: {meta['timestamp']}",
        "",
        "## Setup",
        "",
        f"- Baseline rigid docking: `{meta['baseline_results']}`",
        f"- Pocket box: `{meta['pockets_json']}`",
        f"- Receptor conformers: **{len(conformers)}**",
        f"- Compounds docked: **{aggregate['n_compounds']}**",
        "",
        "### Conformers",
        "",
        "| Label | Source | S3 receptor | Dock status |",
        "| --- | --- | --- | --- |",
    ]
    rec_by_label = {r["label"]: r for r in conformer_records}
    for c in conformers:
        rec = rec_by_label.get(c["label"], {})
        status = rec.get("status") or ("dry_run" if rec.get("dry_run") else rec.get("error", "—"))
        s3 = rec.get("receptor_s3") or "—"
        lines.append(f"| {c['label']} | `{c.get('source', '—')}` | `{s3}` | {status} |")

    lines.extend(
        [
            "",
            "## Aggregate vs rigid baseline",
            "",
            f"- Compounds with improved ensemble best score: **{aggregate['n_improved_vs_baseline']} / {aggregate['n_compounds']}**",
            "",
            "| SMILES | Baseline (kcal/mol) | Ensemble best | Δ | Improved | Best conformer |",
            "| --- | ---: | ---: | ---: | --- | --- |",
        ]
    )
    for c in aggregate["compounds"]:
        base = c["baseline_affinity_kcal_mol"]
        ens = c["ensemble_best_affinity_kcal_mol"]
        delta = c["delta_kcal_mol"]
        flag = "yes" if c["improved_vs_baseline"] else "no"
        ens_s = f"{ens:.3f}" if ens is not None else "—"
        delta_s = f"{delta:+.3f}" if delta is not None else "—"
        lines.append(
            f"| `{c['smiles']}` | {base:.3f} | "
            f"{ens_s} | {delta_s} | {flag} | {c['ensemble_best_conformer'] or '—'} |"
        )

    best = aggregate.get("best_compound")
    if best:
        lines.extend(
            [
                "",
                "## Strongest ensemble prediction",
                "",
                f"- SMILES: `{best['smiles']}`",
                f"- Ensemble best: **{best['ensemble_best_affinity_kcal_mol']:.3f} kcal/mol** ({best['ensemble_best_conformer']})",
                f"- Rigid baseline: {best['baseline_affinity_kcal_mol']:.3f} kcal/mol",
            ]
        )

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--api-url", default=os.environ.get("BIOMATE_API_URL", "http://127.0.0.1:8081"))
    ap.add_argument("--baseline-run", type=Path, default=DEFAULT_BASELINE_RUN)
    ap.add_argument(
        "--s3-input-prefix",
        default="s3://biomate-nextflow-work/inputs/andv_campaign",
        help="S3 prefix for uploaded ensemble receptor PDBs",
    )
    ap.add_argument("--user-id", default=None, help="Nextflow user_id prefix (default: inh-ensemble-<date>)")
    ap.add_argument("--timeout-dock", type=int, default=7200, help="Per-conformer docking poll timeout (seconds)")
    ap.add_argument("--poll-interval", type=int, default=20)
    ap.add_argument("--dry-run", action="store_true", help="Build ensemble and write config only; do not call API")
    args = ap.parse_args()

    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    user_id = args.user_id or f"inh-ensemble-{ts[:8]}"
    baseline_run = args.baseline_run.resolve()
    work_dir = ANTI_VIRUS / "science_sprint/runs" / ts / "track_inh_ensemble"
    work_dir.mkdir(parents=True, exist_ok=True)

    log(f"Run directory: {work_dir}")
    baseline = load_baseline(baseline_run)
    pockets_json = baseline_run / "01_pocket/structure_pockets.json"
    if not pockets_json.is_file():
        raise SystemExit(f"Missing pockets JSON: {pockets_json}")
    box_center, box_size = pocket_geometry(pockets_json)

    conformers = build_receptor_ensemble(baseline_run, work_dir)
    log(f"Receptor ensemble ({len(conformers)} conformers):")
    for c in conformers:
        log(f"  - {c['label']}: {c['source']}")

    api_key = load_api_key() if not args.dry_run else ""
    conformer_records: list[dict[str, Any]] = []

    for conformer in conformers:
        if args.dry_run:
            receptor_s3 = conformer.get("known_s3") or f"{args.s3_input_prefix}/science_sprint/{ts}/{conformer['label']}.pdb"
        else:
            receptor_s3 = stage_receptor_s3(conformer, args.s3_input_prefix, ts)
        rec = dock_one_conformer(
            args.api_url,
            api_key,
            conformer,
            receptor_s3,
            baseline["smiles_list"],
            box_center,
            box_size,
            user_id,
            work_dir,
            args.timeout_dock,
            args.poll_interval,
            args.dry_run,
        )
        conformer_records.append(rec)

    aggregate = aggregate_ensemble(baseline, conformer_records)

    meta = {
        "timestamp": ts,
        "baseline_run": str(baseline_run),
        "baseline_results": baseline["path"],
        "pockets_json": str(pockets_json),
        "box_center": box_center,
        "box_size": box_size,
        "smiles_list": baseline["smiles_list"],
        "n_conformers": len(conformers),
        "conformers": [
            {"label": c["label"], "source": c["source"], "deposit_id": c.get("deposit_id")}
            for c in conformers
        ],
        "dry_run": args.dry_run,
    }

    results = {
        "meta": meta,
        "conformer_runs": conformer_records,
        "aggregate": aggregate,
    }
    results_path = work_dir / "ensemble_results.json"
    results_path.write_text(json.dumps(results, indent=2), encoding="utf-8")
    write_summary_md(
        work_dir / "ensemble_summary.md",
        meta,
        conformers,
        conformer_records,
        aggregate,
    )
    (work_dir / "run_config.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")

    log(f"Wrote {results_path}")
    log(f"Improved vs baseline: {aggregate['n_improved_vs_baseline']}/{aggregate['n_compounds']}")

    failed = [r for r in conformer_records if r.get("error")]
    if failed and not args.dry_run:
        log(f"WARNING: {len(failed)} conformer run(s) failed")
        raise SystemExit(2)


if __name__ == "__main__":
    main()
