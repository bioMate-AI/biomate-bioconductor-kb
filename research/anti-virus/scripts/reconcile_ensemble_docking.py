#!/usr/bin/env python3
"""Re-read ensemble docking artifacts and regenerate aggregate + summary.

Use after a live `track_inh_ensemble_docking.py` run when conformers finished
on Batch but summary needs refresh, or when comparing deposit-only vs all-conformer
aggregation.

Usage:
  python3 research/anti-virus/scripts/reconcile_ensemble_docking.py \\
    research/anti-virus/science_sprint/runs/20260605T025716Z/track_inh_ensemble
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
TRACK = ROOT / "research/anti-virus/science_sprint/track_inh_ensemble_docking.py"


def load_track_module():
    spec = importlib.util.spec_from_file_location("track_inh_ensemble", TRACK)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(mod)
    return mod


def aggregate_ensemble(
    baseline: dict[str, Any],
    conformer_records: list[dict[str, Any]],
    *,
    deposit_only: bool = True,
) -> dict[str, Any]:
    smiles_list = baseline["smiles_list"]
    baseline_by = baseline["by_smiles"]
    usable = [
        r
        for r in conformer_records
        if r.get("by_smiles") and (not deposit_only or r.get("deposit_id"))
    ]
    compounds: list[dict[str, Any]] = []
    for sm in smiles_list:
        base_aff = baseline_by.get(sm)
        per_conf: dict[str, float | None] = {}
        best_aff: float | None = None
        best_label: str | None = None
        for rec in usable:
            label = rec["label"]
            aff = (rec.get("by_smiles") or {}).get(sm)
            per_conf[label] = aff
            if aff is not None and (best_aff is None or aff < best_aff):
                best_aff = aff
                best_label = label
        delta: float | None = None
        improved = False
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
        "n_conformers_used": len(usable),
        "deposit_only": deposit_only,
        "best_compound": best_overall,
        "compounds": compounds,
    }


def reload_conformer_record(cdir: Path) -> dict[str, Any]:
    label = cdir.name
    record: dict[str, Any] = {"label": label}
    params = cdir / "parameters.json"
    if params.is_file():
        p = json.loads(params.read_text(encoding="utf-8"))
        record["receptor_s3"] = p.get("receptor_pdb_file")

    for name in ("submit.json", "status.json"):
        path = cdir / name
        if path.is_file():
            data = json.loads(path.read_text(encoding="utf-8"))
            if name == "submit.json":
                record["run_id"] = data.get("run_id")
            else:
                record["status"] = data.get("status")
                record["error"] = data.get("error")

    dock_json = cdir / "docking_autodock_vina_results.json"
    if dock_json.is_file():
        dock_data = json.loads(dock_json.read_text(encoding="utf-8"))
        record["results_path"] = str(dock_json)
        record["by_smiles"] = {
            row["smiles"]: float(row["best_affinity_kcal_mol"])
            for row in dock_data.get("results") or []
            if row.get("smiles") is not None and row.get("best_affinity_kcal_mol") is not None
        }
        if record.get("by_smiles"):
            record["status"] = record.get("status") or "succeeded"
    elif record.get("error") is None and record.get("status") not in {"succeeded", "completed"}:
        record.setdefault("error", "missing docking_autodock_vina_results.json")

    return record


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("work_dir", type=Path, help="track_inh_ensemble directory")
    ap.add_argument(
        "--deposit-only",
        action="store_true",
        default=None,
        help="Aggregate using deposit conformers only (default: from existing JSON or True)",
    )
    ap.add_argument(
        "--all-conformers",
        action="store_true",
        help="Also write deposit-only=false aggregate into reconciled report",
    )
    args = ap.parse_args()

    work_dir = args.work_dir.resolve()
    results_path = work_dir / "ensemble_results.json"
    if not results_path.is_file():
        raise SystemExit(f"Missing {results_path}")

    track = load_track_module()
    results = json.loads(results_path.read_text(encoding="utf-8"))
    meta = results["meta"]
    baseline_run = Path(meta["baseline_run"])
    baseline = track.load_baseline(
        baseline_run,
        docking_json=Path(meta["baseline_results"]) if meta.get("baseline_results") else None,
        top_n=None,
    )
    # Restrict to smiles_list from meta if present
    if meta.get("smiles_list"):
        wanted = set(meta["smiles_list"])
        baseline["smiles_list"] = [s for s in baseline["smiles_list"] if s in wanted]
        baseline["by_smiles"] = {k: v for k, v in baseline["by_smiles"].items() if k in wanted}

    conformers_dir = work_dir / "conformers"
    conformer_records: list[dict[str, Any]] = []
    deposit_ids: dict[str, str | None] = {}
    for c in meta.get("conformers") or []:
        deposit_ids[c["label"]] = c.get("deposit_id")
    for cdir in sorted(conformers_dir.iterdir()) if conformers_dir.is_dir() else []:
        if not cdir.is_dir():
            continue
        rec = reload_conformer_record(cdir)
        rec["deposit_id"] = deposit_ids.get(rec["label"])
        conformer_records.append(rec)

    deposit_only = args.deposit_only if args.deposit_only is not None else results.get("aggregate", {}).get(
        "deposit_only", True
    )
    aggregate = aggregate_ensemble(baseline, conformer_records, deposit_only=deposit_only)
    results["conformer_runs"] = conformer_records
    results["aggregate"] = aggregate
    results_path.write_text(json.dumps(results, indent=2), encoding="utf-8")

    conformers = [
        {
            "label": c["label"],
            "source": next((m["source"] for m in meta.get("conformers") or [] if m["label"] == c["label"]), "—"),
            "deposit_id": c.get("deposit_id"),
        }
        for c in conformer_records
    ]
    track.write_summary_md(work_dir / "ensemble_summary.md", meta, conformers, conformer_records, aggregate)

    lines = [
        "# Ensemble reconcile report",
        "",
        f"Work dir: `{work_dir}`",
        f"Deposit-only aggregate: **{deposit_only}**",
        f"Improved vs rigid baseline: **{aggregate['n_improved_vs_baseline']} / {aggregate['n_compounds']}**",
        f"Conformers used in aggregate: **{aggregate['n_conformers_used']}**",
        "",
    ]
    if args.all_conformers or not deposit_only:
        agg_all = aggregate_ensemble(baseline, conformer_records, deposit_only=False)
        lines.extend(
            [
                "## All-conformer aggregate (includes top_pocket)",
                "",
                f"- Improved: **{agg_all['n_improved_vs_baseline']} / {agg_all['n_compounds']}**",
                "",
            ]
        )
        for c in agg_all["compounds"]:
            ens = c["ensemble_best_affinity_kcal_mol"]
            ens_s = f"{ens:.3f}" if ens is not None else "—"
            flag = "yes" if c["improved_vs_baseline"] else "no"
            lines.append(
                f"- `{c['smiles'][:40]}` baseline {c['baseline_affinity_kcal_mol']:.3f} → "
                f"ensemble {ens_s} ({c['ensemble_best_conformer']}) improved={flag}"
            )
    else:
        agg_all = aggregate_ensemble(baseline, conformer_records, deposit_only=False)
        lines.extend(
            [
                "## Note",
                "",
                f"All-conformer view (incl. top_pocket): {agg_all['n_improved_vs_baseline']}/{agg_all['n_compounds']} improved. "
                "Re-run with `--all-conformers` for full table.",
                "",
            ]
        )

    (work_dir / "RECONCILED.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Reconciled {results_path}")
    print(f"Improved (deposit-only={deposit_only}): {aggregate['n_improved_vs_baseline']}/{aggregate['n_compounds']}")


if __name__ == "__main__":
    main()
