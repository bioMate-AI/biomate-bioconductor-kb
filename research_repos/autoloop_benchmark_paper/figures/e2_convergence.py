#!/usr/bin/env python3
"""
Figure 2 (E2): Single-shot vs auto-loop gate-pass rate per domain.

Reads results/e2_convergence_per_domain.csv (written by the benchmark
aggregation step) and produces e2_convergence.png next to this script.
"""
from pathlib import Path
import csv
import matplotlib.pyplot as plt
import numpy as np

HERE = Path(__file__).resolve().parent
CSV = HERE.parent / "results" / "e2_convergence_per_domain.csv"
OUT = HERE / "e2_convergence.png"

rows = list(csv.DictReader(open(CSV)))
domains = [r["domain"] for r in rows]
baseline = [float(r["baseline_single_shot_pct"]) for r in rows]
autoloop = [float(r["autoloop_gate_pass_within_3_pct"]) for r in rows]
passat1 = [float(r["autoloop_gate_pass_at_1_pct"]) for r in rows]

x = np.arange(len(domains))
w = 0.38

fig, ax = plt.subplots(figsize=(8, 5))
b1 = ax.bar(x - w/2, baseline, w, label="Single-shot (published baseline)",
            color="#888", edgecolor="black")
b2 = ax.bar(x + w/2, autoloop, w, label="BioMate auto-loop (within 3 iter)",
            color="#2b8cbe", edgecolor="black")

# Annotate bars
for b, v in zip(b1, baseline):
    ax.text(b.get_x()+b.get_width()/2, v+1.5, f"{v:.0f}%", ha="center", fontsize=9)
for b, v in zip(b2, autoloop):
    ax.text(b.get_x()+b.get_width()/2, v+1.5, f"{v:.1f}%", ha="center", fontsize=9,
            fontweight="bold")

ax.set_xticks(x)
ax.set_xticklabels(domains)
ax.set_ylabel("Gate-pass rate (%)")
ax.set_ylim(0, 110)
ax.set_title("E2: Auto-loop convergence vs single-shot baseline (gate-pass within 3 iterations)")
ax.axhline(100, color="lightgray", linewidth=0.5, linestyle="--")
ax.legend(loc="lower right", framealpha=0.95)
ax.grid(axis="y", alpha=0.25)

plt.tight_layout()
plt.savefig(OUT, dpi=200)
print(f"wrote {OUT}")
