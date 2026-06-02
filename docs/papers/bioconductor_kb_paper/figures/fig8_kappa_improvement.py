#!/usr/bin/env python3
"""
Figure 8 (Paper 2 — Methods/AI):
Cohen's κ inter-rater agreement before and after iterative calibration,
per biological domain. Also shows step correctness by domain.

Generates:
  fig8_kappa_improvement.pdf
  fig8_kappa_improvement.png
"""

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

# ── Data ────────────────────────────────────────────────────────────────────
domains = [
    "Bulk\nRNA-seq",
    "Single-cell\nRNA-seq",
    "Genomics &\nVariants",
    "Epigenomics\n(ChIP/ATAC/Meth)",
    "Metagenomics &\nMicrobiome",
    "Proteomics &\nMetabolomics",
    "Multi-omics\n& General",
]

kappa_v1  = [0.803, 0.825, 0.848, 0.835, 0.817, 0.805, 0.671]
kappa_v2  = [0.983, 0.955, 0.979, 0.974, 0.953, 0.967, 0.912]
step_corr = [92.8, 87.8, 89.5, 93.3, 73.0, 86.3, 95.0]
n_steps   = [180, 139, 285, 285, 89, 271, 300]

x = np.arange(len(domains))
bar_w = 0.3

# ── Figure layout: two panels ─────────────────────────────────────────────────
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(13, 8.5), gridspec_kw={"hspace": 0.5})
fig.patch.set_facecolor("white")

# ── Panel A: κ before and after ───────────────────────────────────────────────
bars_v1 = ax1.bar(x - bar_w / 2, kappa_v1, width=bar_w, color="#93C5FD",
                   edgecolor="white", label="κ v1 (pre-calibration)", zorder=3)
bars_v2 = ax1.bar(x + bar_w / 2, kappa_v2, width=bar_w, color="#1D4ED8",
                   edgecolor="white", label="κ v2 (post-calibration)", zorder=3)

# Value labels
for bar in bars_v1:
    ax1.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.004,
             f"{bar.get_height():.3f}", ha="center", va="bottom", fontsize=7.5,
             color="#374151")
for bar in bars_v2:
    ax1.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.004,
             f"{bar.get_height():.3f}", ha="center", va="bottom", fontsize=7.5,
             color="#1E3A5F", fontweight="bold")

# Delta labels
for i, (v1, v2) in enumerate(zip(kappa_v1, kappa_v2)):
    delta = v2 - v1
    ax1.text(x[i], v2 + 0.022, f"Δ+{delta:.3f}",
             ha="center", va="bottom", fontsize=7, color="#7C3AED", fontweight="bold")

# Pre-registered threshold line
ax1.axhline(0.70, color="#EF4444", lw=1.4, linestyle="--", label="Pre-registered threshold (κ = 0.70)", zorder=2)
ax1.axhline(0.80, color="#D97706", lw=0.8, linestyle=":", label="κ = 0.80 (substantial agreement)", zorder=2)

# Overall κ labels
ax1.axhline(0.801, color="#93C5FD", lw=1, linestyle="-.", alpha=0.6)
ax1.axhline(0.960, color="#1D4ED8", lw=1, linestyle="-.", alpha=0.6)
ax1.text(6.8, 0.801 + 0.004, "v1 mean: 0.801", ha="right", fontsize=7.5, color="#3B82F6")
ax1.text(6.8, 0.960 + 0.004, "v2 mean: 0.960", ha="right", fontsize=7.5, color="#1D4ED8", fontweight="bold")

ax1.set_xlim(-0.5, 6.5)
ax1.set_ylim(0.55, 1.05)
ax1.set_xticks(x)
ax1.set_xticklabels(domains, fontsize=8.5)
ax1.set_ylabel("Cohen's κ", fontsize=10)
ax1.set_title("(A)  Inter-Rater Agreement Before and After Iterative Calibration",
              fontsize=11, fontweight="bold", color="#1E3A5F", pad=8)
ax1.legend(fontsize=8, loc="lower right", frameon=True, framealpha=0.9)
ax1.yaxis.grid(True, linestyle="--", alpha=0.35, color="#E5E7EB")
ax1.set_axisbelow(True)
ax1.spines["top"].set_visible(False)
ax1.spines["right"].set_visible(False)

# ── Panel B: Step correctness by domain ───────────────────────────────────────
colors_corr = ["#059669" if sc >= 85 else "#D97706" for sc in step_corr]
bars_corr = ax2.bar(x, step_corr, width=0.55, color=colors_corr, edgecolor="white", zorder=3)

for bar, n, sc in zip(bars_corr, n_steps, step_corr):
    ax2.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.5,
             f"{sc:.1f}%\n(n={n})", ha="center", va="bottom", fontsize=8,
             color="#111827", fontweight="bold")

ax2.axhline(85, color="#EF4444", lw=1.4, linestyle="--",
            label="Pre-registered threshold (85%)", zorder=2)
ax2.axhline(90.0, color="#1E3A5F", lw=1.0, linestyle="-.",
            label="Overall mean: 90.0%", zorder=2)

ax2.set_xlim(-0.5, 6.5)
ax2.set_ylim(60, 102)
ax2.set_xticks(x)
ax2.set_xticklabels(domains, fontsize=8.5)
ax2.set_ylabel("Step correctness (%)", fontsize=10)
ax2.set_title("(B)  Step Correctness by Biological Domain (140 packages, 1,549 steps reviewed)",
              fontsize=11, fontweight="bold", color="#1E3A5F", pad=8)

thresh_patch = mpatches.Patch(color="#EF4444", label="Pre-registered threshold (85%)")
mean_patch   = mpatches.Patch(color="#1E3A5F", label="Overall mean: 90.0%")
above_patch  = mpatches.Patch(color="#059669", label="≥ 85% (meets threshold)")
below_patch  = mpatches.Patch(color="#D97706", label="< 85% (below threshold)")
ax2.legend(handles=[thresh_patch, mean_patch, above_patch, below_patch],
           fontsize=8, loc="lower right", frameon=True, framealpha=0.9)
ax2.yaxis.grid(True, linestyle="--", alpha=0.35, color="#E5E7EB")
ax2.set_axisbelow(True)
ax2.spines["top"].set_visible(False)
ax2.spines["right"].set_visible(False)

# ── Supertitle ────────────────────────────────────────────────────────────────
fig.suptitle(
    "Dual-Agent LLM Review Quality: Inter-Rater Agreement and Step Correctness\n"
    "across Seven Biological Domains",
    fontsize=12, fontweight="bold", color="#1E3A5F", y=1.01,
)

plt.savefig("fig8_kappa_improvement.pdf", dpi=300, bbox_inches="tight")
plt.savefig("fig8_kappa_improvement.png", dpi=300, bbox_inches="tight")
print("Saved: fig8_kappa_improvement.pdf / .png")
