"""E4 Figure: box+strip plot of audit completeness by tool group."""
from __future__ import annotations
import csv
from pathlib import Path
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
PER_RUN = ROOT / "results" / "e4_audit_completeness_per_run.csv"
OUT = ROOT / "figures" / "e4_audit_completeness.png"


def load():
    bm, bl = [], []
    bl_tools = []
    with open(PER_RUN) as f:
        for row in csv.DictReader(f):
            s = float(row["completeness"])
            if row["tool"] == "biomate":
                bm.append(s)
            else:
                bl.append(s)
                bl_tools.append(row["tool"])
    return bm, bl, bl_tools


def main():
    bm, bl, bl_tools = load()
    fig, ax = plt.subplots(figsize=(7, 5))
    data = [bm, bl]
    labels = ["BioMate", "Baseline tools\n(CryoSPARC Live, RELION,\nDataWarrior, PK-Sim,\nSpotfire, SAS BOIN)"]
    bp = ax.boxplot(
        data, labels=labels, patch_artist=True, widths=0.5,
        medianprops=dict(color="black", linewidth=2),
    )
    for patch, color in zip(bp["boxes"], ["#3b82f6", "#94a3b8"]):
        patch.set_facecolor(color)
        patch.set_alpha(0.4)

    rng = np.random.default_rng(0)
    for i, vals in enumerate(data, start=1):
        x = rng.normal(i, 0.05, size=len(vals))
        ax.scatter(x, vals, color=["#1d4ed8", "#475569"][i - 1], s=44, zorder=3, edgecolor="white")

    # annotate medians + IQR
    for i, vals in enumerate(data, start=1):
        med = float(np.median(vals))
        q1, q3 = float(np.quantile(vals, 0.25)), float(np.quantile(vals, 0.75))
        ax.text(i + 0.28, med, f"median={med:.2f}\nIQR=[{q1:.2f}, {q3:.2f}]",
                va="center", fontsize=9)

    ax.set_ylim(-0.05, 1.1)
    ax.set_ylabel("Audit completeness score\n(per-decision avg of {paper_ref, DOI, provenance})")
    ax.set_title("Figure 4. Regulatory audit completeness of run logs\nBioMate vs standard tool baselines (n=10 runs each)")
    ax.axhline(1.0, ls=":", color="#16a34a", alpha=0.6, label="ideal=1.0")
    ax.axhline(0.0, ls=":", color="#dc2626", alpha=0.4)
    ax.legend(loc="center right")

    # significance annotation
    ax.plot([1, 1, 2, 2], [1.05, 1.07, 1.07, 1.05], color="black", lw=1)
    ax.text(1.5, 1.08, "Mann-Whitney U p = 1.6 × 10⁻⁴", ha="center", fontsize=10)

    plt.tight_layout()
    plt.savefig(OUT, dpi=180)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
