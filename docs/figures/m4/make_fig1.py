#!/usr/bin/env python3
"""M4 (TCR-HLA-peptide antigen resolution) Figure 1.

Box-and-arrow schematic of the three-axis fusion, faithful to
docs/20260727_M4_ANTIGEN_RESOLUTION_MANUSCRIPT.md.

Faithful labels (quoted from the paper):
  - Three upstream nf-core workflows feed the integration step (Results
    "Pipeline architecture", lines 44-52; Fig 1 legend line 128):
      1. Repertoire (nf-core/airrflow) -> clonotypes, CDR3s, clonal freq.
      2. HLA typing (nf-core/hlatyping) -> class-I & class-II alleles incl. DP, DQ.
      3. Binding prediction (nf-core/epitopeprediction) -> peptide:MHC %rank.
  - Central node: `antigen_resolution` integration step; "filters to the
    patient's own alleles" (lines 52, 128).
  - Three evidence axes of the composite score S(e) (Methods "Composite
    score", lines 110-112; Table 1 lines 132-139):
      B(e) HLA-binding strength (monotone in %rank; %rank <= 2 = strong binder),
      R(e) repertoire clonal support,
      D(e) optional disease-gene relevance,
      plus C(e) DP/DQ coverage emphasis (surfaces under-served class-II).
  - Output: ranked, provenance-tracked candidate-antigen list + JSON export
    + human-readable report (lines 52, 120).
  - Boundary: candidates must exit the computational loop for MS
    immunopeptidomics + functional confirmation (prediction != validation;
    lines 84, 128).

Threshold "%rank <= 2 = strong binder" is quoted from the paper (line 50,
Methods line 102). No other metrics are printed on the schematic.
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
# House palette (from docs/figures/c8/make_figs.py)
TEAL = "#2a9d8f"; AMBER = "#e9a23b"; RED = "#c1121f"; NAVY = "#22445f"; GREY = "#9aa5ad"


def box(ax, x, y, w, h, name, sub, col, name_fs=10, sub_fs=7.6):
    b = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.10",
                       linewidth=2, edgecolor=col, facecolor=col + "20")
    ax.add_patch(b)
    ax.text(x + w / 2, y + h - 0.30, name, ha="center", va="center",
            fontsize=name_fs, fontweight="bold", color=col)
    ax.text(x + w / 2, y + (h - 0.55) / 2, sub, ha="center", va="center",
            fontsize=sub_fs, color="#333")


def arrow(ax, x0, y0, x1, y1, col=NAVY, ls="-"):
    ax.add_patch(FancyArrowPatch((x0, y0), (x1, y1), arrowstyle="-|>",
                                 mutation_scale=14, lw=1.7, color=col, linestyle=ls))


def fig1():
    fig, ax = plt.subplots(figsize=(12.0, 6.4))

    # ---- three upstream nf-core workflows (left column) ----
    uw = 3.0; uh = 1.05; ux = 0.3
    up = [
        (5.35, "nf-core/airrflow",
         "TCR/BCR repertoire:\nclonotypes, CDR3s, clonal frequency"),
        (3.55, "nf-core/hlatyping",
         "patient class-I & class-II alleles\n(incl. HLA-DP, HLA-DQ)"),
        (1.75, "nf-core/epitopeprediction",
         "peptide:MHC %rank\n(NetMHCpan-4.1 / NetMHCIIpan-4.0)"),
    ]
    up_anchor = []
    for uy, name, sub in up:
        box(ax, ux, uy, uw, uh, name, sub, NAVY, name_fs=9.5, sub_fs=7.4)
        up_anchor.append((ux + uw, uy + uh / 2))

    ax.text(ux + uw / 2, 6.75, "Upstream nf-core workflows (ingested, never re-run)",
            ha="center", fontsize=8.4, color=GREY, style="italic")

    # ---- central integration node ----
    cx0 = 4.55; cy0 = 2.75; cw = 3.15; ch = 2.6
    b = FancyBboxPatch((cx0, cy0), cw, ch, boxstyle="round,pad=0.02,rounding_size=0.12",
                       linewidth=2.4, edgecolor=AMBER, facecolor=AMBER + "20")
    ax.add_patch(b)
    ax.text(cx0 + cw / 2, cy0 + ch - 0.34, "antigen_resolution",
            ha="center", fontsize=11.5, fontweight="bold", color=AMBER)
    ax.text(cx0 + cw / 2, cy0 + ch - 0.72, "integration step",
            ha="center", fontsize=8.2, color=AMBER, style="italic")
    ax.text(cx0 + cw / 2, cy0 + ch - 1.12,
            "filter to patient's own alleles",
            ha="center", fontsize=7.8, color="#333")

    # the three axes + coverage term, inside the node
    axis_lines = [
        ("B(e)", "HLA-binding strength", "(%rank <= 2 = strong binder)", NAVY),
        ("R(e)", "repertoire clonal support", "(expanded clonotype)", NAVY),
        ("D(e)", "disease-gene relevance", "(optional)", NAVY),
        ("C(e)", "DP/DQ coverage emphasis", "(surfaces class-II)", TEAL),
    ]
    ly = cy0 + ch - 1.52
    for tag, lab, note, col in axis_lines:
        ax.text(cx0 + 0.18, ly, tag, ha="left", va="center", fontsize=8.6,
                fontweight="bold", color=col)
        ax.text(cx0 + 0.78, ly, lab + "  " + note, ha="left", va="center",
                fontsize=7.6, color="#333")
        ly -= 0.34
    ax.text(cx0 + cw / 2, cy0 + 0.20,
            "composite S(e) = additive, reported weights",
            ha="center", va="center", fontsize=7.8, color="#333", style="italic")

    # three axis arrows converge on the node
    for ax_x, ax_y in up_anchor:
        arrow(ax, ax_x + 0.05, ax_y, cx0 - 0.02, cy0 + ch / 2, col=NAVY)

    # ---- ranked output ----
    ox = 8.35; oy = 3.35; ow = 3.15; oh = 1.45
    box(ax, ox, oy, ow, oh, "Ranked candidate antigens",
        "provenance-tracked table\n(axes that supported each row)\n+ JSON export + report",
        AMBER, name_fs=9.5, sub_fs=7.4)
    arrow(ax, cx0 + cw, cy0 + ch / 2, ox - 0.02, oy + oh / 2, col=AMBER)

    # ---- boundary: prediction != validation ----
    boundary_x = ox + ow / 2
    bx = boundary_x - 1.5; by = 1.15; bw = 3.0; bh = 1.15
    b2 = FancyBboxPatch((bx, by), bw, bh, boxstyle="round,pad=0.02,rounding_size=0.10",
                        linewidth=2, edgecolor=RED, facecolor="white")
    ax.add_patch(b2)
    ax.text(bx + bw / 2, by + bh - 0.30, "Experimental confirmation",
            ha="center", fontsize=9.2, fontweight="bold", color=RED)
    ax.text(bx + bw / 2, by + 0.40,
            "MS immunopeptidomics +\nfunctional assays",
            ha="center", fontsize=7.8, color="#333")
    arrow(ax, boundary_x, oy - 0.02, boundary_x, by + bh + 0.02, col=RED, ls="--")
    ax.text(boundary_x + 0.15, (oy + by + bh) / 2 + 0.05,
            "prediction is a hypothesis,\nnot a validated antigen",
            ha="left", va="center", fontsize=7.4, color=RED, style="italic")

    ax.text(0.3, 0.30,
            "The pipeline is an integration layer over established tools; it outputs ranked hypotheses for downstream MS + functional triage, not validated antigens.",
            fontsize=7.6, color="#666", style="italic")

    ax.set_xlim(0, 11.7); ax.set_ylim(0, 7.1); ax.axis("off")
    ax.set_title("Figure 1. Three-axis antigen-resolution fusion: repertoire, HLA type and predicted peptides converge on the antigen_resolution node,\n"
                 "scored on binding / repertoire / disease axes with a DP/DQ coverage emphasis, emitting a ranked candidate-antigen list",
                 fontsize=10, fontweight="bold")
    plt.tight_layout()
    out = os.path.join(HERE, "fig1_antigen_resolution.png")
    plt.savefig(out, dpi=185, bbox_inches="tight"); print("wrote", out)
    plt.close()


fig1()
