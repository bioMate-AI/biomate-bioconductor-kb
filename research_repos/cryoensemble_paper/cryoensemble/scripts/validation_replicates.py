"""Multi-seed replicate study: report mean ± std at each condition.

Runs the ADK gold-standard validation across N seeds per (fraction, noise) cell.
This produces the publishable validation table.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cryoensemble.scripts.validate_adk_gold import (
    load_calpha, run_one,
)
from cryoensemble.evaluate import kabsch_rmsd


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--open_pdb",   default=str(Path(__file__).resolve().parents[1] / "data/goldstd/4AKE.pdb"))
    ap.add_argument("--closed_pdb", default=str(Path(__file__).resolve().parents[1] / "data/goldstd/1AKE.pdb"))
    ap.add_argument("--fractions", default="0.50,0.20,0.10,0.05,0.02")
    ap.add_argument("--noise_levels", default="0.1,0.5,1.0,2.0")
    ap.add_argument("--n_replicates", type=int, default=5)
    ap.add_argument("--n_particles", type=int, default=400)
    ap.add_argument("--device", default="cpu")
    ap.add_argument("--outjson", default="/tmp/cryoensemble_replicates.json")
    args = ap.parse_args()

    open_xyz = load_calpha(args.open_pdb)
    closed_xyz = load_calpha(args.closed_pdb)
    n = min(len(open_xyz), len(closed_xyz))
    open_xyz, closed_xyz = open_xyz[:n], closed_xyz[:n]
    gt_rmsd = kabsch_rmsd(open_xyz, closed_xyz)

    print(f"ADK 4AKE/1AKE  N={n} Cα   open↔closed RMSD={gt_rmsd:.2f} Å")
    print(f"{args.n_replicates} replicates per cell, {args.n_particles} particles, "
          f"box=96, apix=1.5\n")

    print(f"{'noise':>6} | {'truth':>5} | {'recovered (mean±std)':>22} | {'abs_err':>9} | {'assign_acc':>12}")
    print("-" * 75)

    rows = []
    for noise in (float(s) for s in args.noise_levels.split(",")):
        for frac in (float(s) for s in args.fractions.split(",")):
            rec, errs, accs = [], [], []
            for k in range(args.n_replicates):
                r = run_one(
                    open_xyz, closed_xyz,
                    n_particles=args.n_particles, closed_frac_truth=frac,
                    D=96, apix=1.5, sigma_a=1.5, sigma_noise=0.5,
                    noise_level=noise,
                    n_open_perturb=15, n_closed_perturb=5,
                    seed=1000 * k + int(round(1000 * frac)),
                    device=args.device,
                )
                rec.append(r["closed_frac_recovered"])
                errs.append(r["abs_error"])
                accs.append(r["particle_assignment_accuracy"])
            mean_r, std_r = statistics.mean(rec), statistics.stdev(rec) if len(rec) > 1 else 0.0
            print(f"  {noise:>4.2f} | {frac:>4.3f} |   {mean_r:.3f} ± {std_r:.3f}      | "
                  f"  {statistics.mean(errs):.3f}  |  {statistics.mean(accs):.3f}")
            rows.append({
                "noise_level": noise, "closed_frac_truth": frac,
                "recovered_mean": mean_r, "recovered_std": std_r,
                "abs_error_mean": statistics.mean(errs),
                "assign_acc_mean": statistics.mean(accs),
                "n_replicates": args.n_replicates,
            })
    with open(args.outjson, "w") as f:
        json.dump({"ground_truth_rmsd_A": gt_rmsd, "rows": rows}, f, indent=2)
    print(f"\nReplicates written to {args.outjson}")


if __name__ == "__main__":
    main()
