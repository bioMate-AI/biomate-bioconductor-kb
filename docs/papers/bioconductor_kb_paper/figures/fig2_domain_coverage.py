#!/usr/bin/env python3
"""
Figure 2 (Paper 1 — NAR Database Issue):
BioMate-KB Domain Coverage across Bioconductor 3.20

Generates:
  fig2_domain_coverage.pdf   (vector, for publication)
  fig2_domain_coverage.png   (300 dpi, for manuscript draft)
"""

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

# ── Data ────────────────────────────────────────────────────────────────────
domains = [
    "Transcriptomics\n(RNA-seq, GeneExpression)",
    "Genomics\n(Sequencing, Variants, Annotation)",
    "Statistical / ML Methods",
    "Visualization / Infrastructure",
    "Single-cell\n(SingleCell, scRNASeq)",
    "Epigenomics\n(ChIP-seq, ATAC-seq, Methylation)",
    "Network Analysis",
    "Proteomics / Mass Spectrometry",
    "Microbiome / Metagenomics / Metabolomics",
    "Spatial Transcriptomics",
]
packages = [831, 722, 528, 485, 287, 261, 232, 229, 156, 55]
pct = [p / 2241 * 100 for p in packages]

# Color gradient: dark blue → teal
colors = [
    "#1E3A5F", "#1D4ED8", "#2563EB", "#3B82F6", "#0891B2",
    "#059669", "#16A34A", "#65A30D", "#D97706", "#DC2626",
]

# ── Layout ───────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(11, 6))
fig.patch.set_facecolor("white")

y = np.arange(len(domains))
bars = ax.barh(y, packages, color=colors, edgecolor="white", linewidth=0.5, height=0.72)

# ── Annotations ──────────────────────────────────────────────────────────────
for i, (bar, n, p) in enumerate(zip(bars, packages, pct)):
    ax.text(
        bar.get_width() + 8, bar.get_y() + bar.get_height() / 2,
        f"{n:,}  ({p:.1f}%)",
        va="center", ha="left", fontsize=9, color="#374151",
    )

# ── Axes ─────────────────────────────────────────────────────────────────────
ax.set_yticks(y)
ax.set_yticklabels(domains, fontsize=9.5)
ax.invert_yaxis()
ax.set_xlabel("Number of Bioconductor 3.20 packages", fontsize=10)
ax.set_xlim(0, 1050)
ax.spines["top"].set_visible(False)
ax.spines["right"].set_visible(False)
ax.spines["left"].set_visible(False)
ax.tick_params(left=False)
ax.xaxis.grid(True, linestyle="--", alpha=0.4, color="#D1D5DB")
ax.set_axisbelow(True)

# ── Multi-domain note ────────────────────────────────────────────────────────
ax.text(
    1040, 9.6,
    "78.5% of packages span\nmultiple domains\n(counts non-exclusive)",
    ha="right", va="bottom", fontsize=8, color="#6B7280",
    style="italic",
)

# ── Total line ────────────────────────────────────────────────────────────────
ax.axvline(x=2241 * 0, color="none")  # placeholder

# ── Title ────────────────────────────────────────────────────────────────────
ax.set_title(
    "BioMate-KB Domain Coverage across Bioconductor 3.20 (2,241 packages)",
    fontsize=12, fontweight="bold", color="#1E3A5F", pad=14,
)

plt.tight_layout()
plt.savefig("fig2_domain_coverage.pdf", dpi=300, bbox_inches="tight")
plt.savefig("fig2_domain_coverage.png", dpi=300, bbox_inches="tight")
print("Saved: fig2_domain_coverage.pdf / .png")
