#!/usr/bin/env python3
"""Prepare ensemble-docking launch config for ZINC600 top-N (Galaxy API required to run)."""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
ENSEMBLE_SCRIPT = ROOT / "research/anti-virus/science_sprint/track_inh_ensemble_docking.py"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--publication-run", type=Path, default=DEFAULT_PUB)
    ap.add_argument("--top-n", type=int, default=5)
    ap.add_argument("--out-dir", type=Path, default=None)
    args = ap.parse_args()
    pub = args.publication_run.resolve()
    dock_path = pub / "zinc150_screen/vina/docking_autodock_vina_results.json"
    dock = json.loads(dock_path.read_text(encoding="utf-8"))
    ok = [r for r in dock.get("results") or [] if r.get("best_affinity_kcal_mol") is not None]
    top = sorted(ok, key=lambda r: float(r["best_affinity_kcal_mol"]))[: args.top_n]

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = args.out_dir or (
        ROOT / f"research/anti-virus/science_sprint/runs/{stamp}/track_inh_ensemble_z600_top{args.top_n}"
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    config = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "track": "inh_ensemble_zinc600_topN",
        "top_n": args.top_n,
        "baseline_docking_json": str(dock_path),
        "compounds": [
            {
                "rank": i,
                "smiles": r["smiles"],
                "vina_kcal_mol": float(r["best_affinity_kcal_mol"]),
            }
            for i, r in enumerate(top, 1)
        ],
        "launch_command": (
            f"python3 {ENSEMBLE_SCRIPT} "
            f"--baseline-docking-json {dock_path} "
            f"--top-n {args.top_n}"
        ),
        "status": "prepared",
        "note": "Requires Galaxy API at http://127.0.0.1:8081",
    }
    (out_dir / "run_config.json").write_text(json.dumps(config, indent=2), encoding="utf-8")
    (pub / "zinc600_screen/ZINC600_ENSEMBLE_TOP5_LAUNCH.md").write_text(
        "\n".join(
            [
                "# ZINC600 top-5 ensemble docking — launch config",
                "",
                f"Prepared: {config['created_at']}",
                "",
                "## Compounds",
                "",
                "| Rank | Vina (kcal/mol) | SMILES |",
                "| ---: | ---: | --- |",
            ]
            + [
                f"| {c['rank']} | {c['vina_kcal_mol']:.3f} | `{c['smiles']}` |"
                for c in config["compounds"]
            ]
            + [
                "",
                "## Run (when Galaxy API is up)",
                "",
                "```bash",
                config["launch_command"],
                "```",
                "",
                f"Config: `{out_dir / 'run_config.json'}`",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    print(json.dumps(config, indent=2))


if __name__ == "__main__":
    main()
