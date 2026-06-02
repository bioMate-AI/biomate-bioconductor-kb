#!/usr/bin/env python3
"""
Figure 3 (Paper 1 — NAR Database Issue):
Knowledge base curation funnel — raw extraction → curated steps

Generates:
  fig3_curation_funnel.pdf
  fig3_curation_funnel.png
"""

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as FancyBboxPatch
from matplotlib.patches import FancyArrowPatch
import numpy as np

# ── Data ────────────────────────────────────────────────────────────────────
stages = [
    ("Bioconductor 3.20\nPackages", 2241, "#1E3A5F", "white"),
    ("Packages with\nVignettes", 1970, "#1D4ED8", "white"),
    ("Raw Workflow\nSteps Extracted", 28485, "#D97706", "white"),
    ("Steps After\nQuality Curation", 15641, "#065F46", "white"),
]

labels_right = [
    "",
    "87.9% extractable\n(271 not extractable: PDF-only,\ndata packages, GUI-only tools)",
    "28,485 raw steps\n50,959 function annotations\n14.5 steps/pkg (mean)",
    "45.1% noise removed\n12,844 steps removed\n8.2 steps/pkg (curated mean)",
]

# ── Layout ───────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(12, 7))
fig.patch.set_facecolor("white")
ax.set_xlim(0, 12)
ax.set_ylim(0, 8)
ax.axis("off")

# Title
ax.text(6, 7.7, "BioMate-KB Curation Funnel: From 2,241 Packages to 15,641 Curated Steps",
        ha="center", va="center", fontsize=13, fontweight="bold", color="#1E3A5F")

# Funnel widths (normalized to canvas)
widths = [6.0, 5.4, 4.6, 3.8]
x_center = 4.2
box_height = 0.75
y_positions = [6.5, 5.25, 4.0, 2.75]

for i, ((label, value, color, fontcolor), w, y_pos, anno) in enumerate(
    zip(stages, widths, y_positions, labels_right)
):
    x_left = x_center - w / 2
    rect = plt.Rectangle(
        (x_left, y_pos - box_height / 2), w, box_height,
        facecolor=color, edgecolor="white", linewidth=2, zorder=3
    )
    ax.add_patch(rect)

    # Number
    ax.text(x_center, y_pos + 0.05, f"{value:,}",
            ha="center", va="center", fontsize=15, fontweight="bold",
            color=fontcolor, zorder=4)
    ax.text(x_center, y_pos - 0.22, label,
            ha="center", va="center", fontsize=8.5,
            color=fontcolor, zorder=4)

    # Right annotation
    if anno:
        ax.text(x_center + w / 2 + 0.2, y_pos, anno,
                ha="left", va="center", fontsize=8, color="#374151",
                linespacing=1.4)

    # Arrow down (between boxes)
    if i < len(stages) - 1:
        ax.annotate(
            "", xy=(x_center, y_positions[i + 1] + box_height / 2 + 0.02),
            xytext=(x_center, y_pos - box_height / 2 - 0.02),
            arrowprops=dict(arrowstyle="-|>", color="#6B7280", lw=2),
            zorder=2,
        )

# ── Quality curation rounds box ───────────────────────────────────────────────
rounds_y = 1.6
ax.text(x_center, rounds_y + 0.3, "4-Round Quality Curation",
        ha="center", va="center", fontsize=10, fontweight="bold", color="#5B21B6")
round_labels = [
    "① Semantic consolidation",
    "② Noise removal (STRICT + EXTENDED filters)",
    "③ Phase expansion (single-step vignettes)",
    "④ Narrow-scope scoring (GUI/data-only packages)",
]
for j, rl in enumerate(round_labels):
    ax.text(x_center - 1.5, rounds_y - 0.05 - j * 0.28, f"  {rl}",
            ha="left", va="center", fontsize=8.5, color="#374151")

rect_rounds = plt.Rectangle(
    (x_center - 3.5, rounds_y - 1.25), 7, 1.7,
    facecolor="#EDE9FE", edgecolor="#5B21B6", linewidth=1.5, zorder=1
)
ax.add_patch(rect_rounds)

# Arrow from curation box to curated steps box
ax.annotate(
    "", xy=(x_center, y_positions[3] - box_height / 2 - 0.02),
    xytext=(x_center, rounds_y + 0.45),
    arrowprops=dict(arrowstyle="-|>", color="#5B21B6", lw=2.5),
    zorder=2,
)

# ── FAIR stats row ────────────────────────────────────────────────────────────
fair_y = 1.0
stats = [
    ("EDAM coverage", "94.7%", "#059669"),
    ("Biocontainer", "98.8%", "#059669"),
    ("Software DOI", "100%", "#059669"),
    ("Git provenance", "100%", "#059669"),
]
for k, (stat_label, stat_val, stat_color) in enumerate(stats):
    sx = 1.2 + k * 2.6
    ax.text(sx, fair_y + 0.15, stat_val, ha="center", fontsize=12,
            fontweight="bold", color=stat_color)
    ax.text(sx, fair_y - 0.1, stat_label, ha="center", fontsize=7.5,
            color="#6B7280")

ax.text(x_center, fair_y + 0.55, "Metadata Enrichment (applied to all curated steps)",
        ha="center", fontsize=9, fontweight="bold", color="#374151")

plt.tight_layout()
plt.savefig("fig3_curation_funnel.pdf", dpi=300, bbox_inches="tight")
plt.savefig("fig3_curation_funnel.png", dpi=300, bbox_inches="tight")
print("Saved: fig3_curation_funnel.pdf / .png")
