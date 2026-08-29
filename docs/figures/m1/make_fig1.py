#!/usr/bin/env python3
"""M1 (multi-omic endotyping pipeline) Figure 1.

Box-and-arrow schematic of the FIVE ordered stages, faithful to the manuscript
docs/20260727_M1_MULTIOMIC_ENDOTYPING_MANUSCRIPT.md.

Stage names + gate verdicts are quoted from the paper:
  - Results "Overview" (line 53) and Fig 1 legend (line 99):
    QC-triage gate -> grounded metadata harmonization ->
    select-and-evaluate integration (with over-correction detection) ->
    MOFA+ endotype discovery -> gate-0 out-of-cohort validation.
  - Gate verdicts INTEGRATE / TRIAGE / REJECT: line 56 & 82 ("returns an
    explicit verdict — INTEGRATE, TRIAGE (fixable, itemized), or REJECT").
  - Harmonization cascade + "never fabricates identifiers": lines 58-59, 84.
  - Method menu (Harmony, scVI/scANVI, Scanorama, FastMNN, ComBat-seq) and
    two-objective scoring (batch removal vs biology conservation), over-
    correction flag: lines 62, 86, Table 1 (lines 105-109).
  - MOFA+ latent factors / endotypes-as-hypothesis: lines 64-65.
  - Gate-0 checks (out-of-cohort label transfer, longitudinal stability,
    variance decomposition): lines 67-68, 88.

No metrics are printed on the schematic (a design diagram needs none); all
labels are quoted from the paper text.
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
# House palette (from docs/figures/c8/make_figs.py)
TEAL = "#2a9d8f"; AMBER = "#e9a23b"; RED = "#c1121f"; NAVY = "#22445f"; GREY = "#9aa5ad"


def stage_box(ax, x, y, w, h, name, sub, col):
    box = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.10",
                         linewidth=2, edgecolor=col, facecolor=col + "20")
    ax.add_patch(box)
    ax.text(x + w / 2, y + h - 0.30, name, ha="center", va="center",
            fontsize=10.5, fontweight="bold", color=col)
    ax.text(x + w / 2, y + (h - 0.55) / 2, sub, ha="center", va="center",
            fontsize=7.6, color="#333")
    return (x + w / 2, y)


def arrow(ax, x0, y0, x1, y1, col=NAVY):
    ax.add_patch(FancyArrowPatch((x0, y0), (x1, y1), arrowstyle="-|>",
                                 mutation_scale=14, lw=1.7, color=col))


def fig1():
    fig, ax = plt.subplots(figsize=(12.5, 4.6))
    w = 1.85; h = 1.55; gap = 0.42; x = 0.25; y = 1.85

    stages = [
        ("1 · QC-triage gate",
         "metadata completeness;\nbatch-vs-biology confounding\n(chi-sq, Cramer's V);\nprovenance; QC outliers", NAVY),
        ("2 · Metadata\nharmonization",
         "grounded match cascade\n(label / synonym / Jaccard /\nedit-distance);\nnever fabricates IDs", NAVY),
        ("3 · Select-and-\nevaluate integration",
         "method menu; two-objective\nscore (batch removal vs\nbiology conservation);\nover-correction detection", AMBER),
        ("4 · MOFA+ endotype\ndiscovery",
         "latent factors across\nomics layers;\nendotypes = hypothesis\n(k to be validated)", NAVY),
        ("5 · Gate-0\nvalidation",
         "out-of-cohort label transfer;\nlongitudinal stability;\nvariance decomposition\n(biology vs confound)", TEAL),
    ]

    centers = []
    for name, sub, col in stages:
        cx, by = stage_box(ax, x, y, w, h, name, sub, col)
        centers.append((x, cx, by))
        x += w + gap

    # sequential arrows
    xx = 0.25 + w
    for _ in range(len(stages) - 1):
        arrow(ax, xx, y + h / 2, xx + gap, y + h / 2)
        xx += w + gap

    # inputs feeding stage 1
    ax.text(centers[0][1], y + h + 0.65,
            "Candidate multi-omic cohort\n(scRNA / bulk RNA-seq, +clinical metadata)",
            ha="center", va="center", fontsize=8.2, color="#333",
            bbox=dict(boxstyle="round,pad=0.3", fc=GREY + "22", ec=GREY, lw=1.2))
    arrow(ax, centers[0][1], y + h + 0.30, centers[0][1], y + h + 0.02, col=GREY)

    # ---- gate verdict emissions (quoted from paper) ----
    # Stage 1 verdict: INTEGRATE / TRIAGE / REJECT
    ax.text(centers[0][1], y - 0.55,
            "verdict: INTEGRATE / TRIAGE\n(REJECT: un-integratable cohort,\nCramer's V ~ 1, exits here)",
            ha="center", va="top", fontsize=7.4, color=NAVY, style="italic")
    arrow(ax, centers[0][1], y - 0.02, centers[0][1], y - 0.30, col=NAVY)

    # Stage 2 emission: needs_review flag
    ax.text(centers[1][1], y - 0.55, "low-confidence values ->\nhuman review",
            ha="center", va="top", fontsize=7.4, color=NAVY, style="italic")

    # Stage 3 emission: auto-selected method + over-correction flag
    ax.text(centers[2][1], y - 0.55, "auto-selected method;\nover-correction flagged",
            ha="center", va="top", fontsize=7.4, color=AMBER, style="italic")

    # Stage 4 emission
    ax.text(centers[3][1], y - 0.55, "candidate endotypes +\nfactor-feature drivers",
            ha="center", va="top", fontsize=7.4, color=NAVY, style="italic")

    # Stage 5 output: validated vs rejected partition
    ax.text(centers[4][1], y - 0.62,
            "validated partition ->\nstratification / biomarker\n(else rejected)",
            ha="center", va="top", fontsize=7.6, color=TEAL, style="italic", fontweight="bold")
    arrow(ax, centers[4][1], y - 0.02, centers[4][1], y - 0.30, col=TEAL)

    ax.text(0.25, 0.02,
            "Every stage emits an explicit decision, logged and scored; a claimed endotype can be regenerated and re-validated by a third party.",
            fontsize=7.6, color="#666", style="italic")

    ax.set_xlim(0, x + 0.1); ax.set_ylim(-0.15, 4.5); ax.axis("off")
    ax.set_title("Figure 1. The reproducible multi-omic endotyping pipeline: five ordered stages, each gated on an explicit decision",
                 fontsize=11, fontweight="bold")
    plt.tight_layout()
    out = os.path.join(HERE, "fig1_endotyping_pipeline.png")
    plt.savefig(out, dpi=185, bbox_inches="tight"); print("wrote", out)
    plt.close()


fig1()
