#!/usr/bin/env python3
"""
Figure 7 (Paper 2 — Methods/AI):
Structure-grounded vs. ungrounded LLM generation quality
across four key metrics.

Generates:
  fig7_results_comparison.pdf
  fig7_results_comparison.png
"""

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

# ── Data ────────────────────────────────────────────────────────────────────
metrics = [
    "Function citation\naccuracy",
    "Correct-package\ncitation rate",
    "Steps with executable\nsample code",
    "Steps with\nKB context provided",
]

llm_only  = [71.4, 85.7,  0.0,   0.0]   # ungrounded
biomatekb = [88.2, 97.9, 83.0, 100.0]   # structure-grounded
deltas    = [+16.8, +12.2, +83.0, +100.0]

# ── Layout ───────────────────────────────────────────────────────────────────
fig, axes = plt.subplots(1, 4, figsize=(14, 5), sharey=False)
fig.patch.set_facecolor("white")

colors_a = "#DC2626"   # ungrounded — red
colors_b = "#059669"   # grounded   — green
bar_width = 0.38
bar_positions = [0.25, 0.75]

for i, (ax, metric, va, vb, delta) in enumerate(
    zip(axes, metrics, llm_only, biomatekb, deltas)
):
    # Bars
    bar_a = ax.bar(bar_positions[0], va, width=bar_width, color=colors_a,
                   edgecolor="white", zorder=3, label="LLM-only")
    bar_b = ax.bar(bar_positions[1], vb, width=bar_width, color=colors_b,
                   edgecolor="white", zorder=3, label="BioMate+KB")

    # Value labels on bars
    for bar, val in [(bar_a, va), (bar_b, vb)]:
        ypos = bar[0].get_height()
        ax.text(bar[0].get_x() + bar[0].get_width() / 2,
                ypos + 1.5, f"{val:.1f}%",
                ha="center", va="bottom", fontsize=11, fontweight="bold",
                color="#111827")

    # Delta annotation
    max_val = max(va, vb)
    ax.annotate(
        f"+{delta:.1f} pp",
        xy=(bar_positions[1], max_val + 6),
        ha="center", va="bottom", fontsize=10, fontweight="bold",
        color="#7C3AED",
    )
    # Arrow between bars
    ax.annotate(
        "", xy=(bar_positions[1] - bar_width / 2 - 0.01, max(va, vb) * 0.55),
        xytext=(bar_positions[0] + bar_width / 2 + 0.01, max(va, vb) * 0.55),
        arrowprops=dict(arrowstyle="-|>", color="#7C3AED", lw=1.8),
    )

    # Styling
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 115)
    ax.set_xticks(bar_positions)
    ax.set_xticklabels(["LLM-only", "BioMate\n+KB"], fontsize=9)
    ax.set_title(metric, fontsize=9.5, fontweight="bold", color="#1E3A5F",
                 pad=8, wrap=True)
    ax.set_ylabel("%" if i == 0 else "", fontsize=9)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.yaxis.grid(True, linestyle="--", alpha=0.4, color="#E5E7EB")
    ax.set_axisbelow(True)
    ax.tick_params(bottom=False)

    # 100% reference line
    ax.axhline(100, color="#D1D5DB", lw=0.8, linestyle=":")

# ── Legend ────────────────────────────────────────────────────────────────────
legend_handles = [
    mpatches.Patch(color=colors_a, label="LLM-only (ungrounded)"),
    mpatches.Patch(color=colors_b, label="BioMate+KB (structure-grounded)"),
    mpatches.Patch(color="#7C3AED", label="Improvement (pp)"),
]
fig.legend(handles=legend_handles, loc="lower center", ncol=3, fontsize=10,
           bbox_to_anchor=(0.5, -0.02), frameon=False)

# ── Title ────────────────────────────────────────────────────────────────────
fig.suptitle(
    "Structure-Grounded LLM Generation vs. Ungrounded LLM\n"
    "across Four Workflow Quality Metrics (20 benchmark tasks, 7 domains)",
    fontsize=12, fontweight="bold", color="#1E3A5F", y=1.03,
)

plt.tight_layout()
plt.savefig("fig7_results_comparison.pdf", dpi=300, bbox_inches="tight")
plt.savefig("fig7_results_comparison.png", dpi=300, bbox_inches="tight")
print("Saved: fig7_results_comparison.pdf / .png")
