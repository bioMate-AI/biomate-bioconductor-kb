#!/usr/bin/env python3
"""C8 (Auto-Update tool discovery) figures.
Fig 1: the 6-stage pipeline schematic, colour-coded by where automation works vs breaks.
Fig 2: the honest-negative boundary — per-stage completion, all numbers from the manuscript
       Results (§5): discovery 264 repos; selection 5/10; container 8/16 broken -> 15/15 fixed;
       parameters 0/14 workflow-ready; execution-validated wrappers 0.
No fabricated numbers — every value is quoted in MANUSCRIPT_DRAFT.md §5.
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
GREEN = "#2a9d8f"; AMBER = "#e9a23b"; RED = "#c1121f"; NAVY = "#22445f"; GREY = "#9aa5ad"

# ---------------------------------------------------------------- Fig 1
def fig1():
    fig, ax = plt.subplots(figsize=(11, 3.6))
    stages = [
        ("DETECT", "GitHub search\n55+ topics", GREEN, "works"),
        ("FETCH", "docs + citations\n(CrossRef)", GREEN, "works"),
        ("GENERATE", "Galaxy XML +\ncontainer", AMBER, "partial"),
        ("VALIDATE", "6 XML checks\n(syntactic)", AMBER, "syntactic only"),
        ("TEST", "container exec\non test data", RED, "0 pass"),
        ("INTEGRATE", "DB row\nauto_discovered=1", GREEN, "works*"),
    ]
    n = len(stages); w = 1.55; h = 1.5; gap = 0.30; x = 0.2; y = 1.7
    centers = []
    for name, sub, col, tag in stages:
        box = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.12",
                             linewidth=2, edgecolor=col, facecolor=col + "22")
        ax.add_patch(box)
        ax.text(x + w/2, y + h - 0.32, name, ha="center", va="center", fontsize=11, fontweight="bold", color=col)
        ax.text(x + w/2, y + 0.52, sub, ha="center", va="center", fontsize=8, color="#333")
        ax.text(x + w/2, y - 0.28, tag, ha="center", va="center", fontsize=8, style="italic", color=col)
        centers.append(x + w/2)
        x += w + gap
    # arrows
    xx = 0.2 + w
    for _ in range(n - 1):
        ar = FancyArrowPatch((xx, y + h/2), (xx + gap, y + h/2), arrowstyle="-|>",
                             mutation_scale=14, lw=1.6, color=NAVY)
        ax.add_patch(ar)
        xx += w + gap
    # BLOG branch off INTEGRATE
    ax.text(centers[-1], y + h + 0.55, "→ BLOG (LLM draft + review loop, works)",
            ha="center", fontsize=8.5, color=GREEN, style="italic")
    # the container sub-fix callout under GENERATE
    ax.annotate("container tag via BioContainers API\n(not `:latest` guessing) → 15/15 valid",
                xy=(centers[2], y - 0.05), xytext=(centers[2] - 0.2, y - 1.15),
                fontsize=8, color=GREEN, ha="center",
                arrowprops=dict(arrowstyle="->", color=GREEN, lw=1))
    # the wall between metadata and executable core
    wall_x = 0.2 + 2*(w+gap) - gap/2
    ax.axvline(wall_x, ymin=0.12, ymax=0.82, color=RED, lw=1.4, ls="--", alpha=0.6)
    ax.text(wall_x, y + h + 0.15, "automation works ←", ha="right", fontsize=9, color=GREEN, fontweight="bold")
    ax.text(wall_x, y + h + 0.15, " → executable core breaks", ha="left", fontsize=9, color=RED, fontweight="bold")

    ax.text(0.2, 0.15, "*INTEGRATE succeeds only with execution TEST disabled (ENABLE_TEST=0).",
            fontsize=7.5, color="#666", style="italic")
    ax.set_xlim(0, x + 0.2); ax.set_ylim(0.0, 4.3); ax.axis("off")
    ax.set_title("Figure 1. The six-stage auto-update pipeline — green stages are production-viable; the GENERATE→TEST core is where autonomy breaks",
                 fontsize=10, fontweight="bold")
    plt.tight_layout()
    out = os.path.join(HERE, "fig1_pipeline.png")
    plt.savefig(out, dpi=185, bbox_inches="tight"); print("wrote", out)
    plt.close()

# ---------------------------------------------------------------- Fig 2
def fig2():
    # (label, completion 0-1, annotation, color) — from §5
    rows = [
        ("Discovery\n(264 repos / 25 min)", 1.00, "264 repos surfaced, quality-tiered", GREEN),
        ("Feasibility / selection\n(blog-worthiness)", 1.00, "5/10 correctly triaged tool vs library", GREEN),
        ("Metadata + citation\nextraction", 1.00, "README + CrossRef citations", GREEN),
        ("Container resolution\n(after BioContainers API)", 1.00, "8/16 broken → 15/15 valid (fixed)", GREEN),
        ("Parameter completeness", 0.00, "0/14 workflow-ready (params empty/dummy in 11/14)", RED),
        ("Execution-validated\nwrappers", 0.00, "0 passed execution testing in every run", RED),
    ]
    fig, ax = plt.subplots(figsize=(10, 5.2))
    ys = list(range(len(rows)))[::-1]
    for y, (label, val, note, col) in zip(ys, rows):
        ax.barh(y, max(val, 0.012), height=0.44, color=col, alpha=0.85 if val > 0 else 1.0,
                edgecolor=col, linewidth=1.5 if val == 0 else 0)
        ax.text(-0.02, y, label, ha="right", va="center", fontsize=9.5)
        # note ABOVE the bar (left-aligned) — avoids any right-edge collision
        ax.text(0.005, y + 0.34, note, ha="left", va="center", fontsize=8.2, color="#555")
        mark = "✓" if val > 0 else "✗"
        ax.text(val/2 if val > 0.1 else 0.02, y, mark, ha="center", va="center",
                fontsize=13, color="white" if val > 0.1 else RED, fontweight="bold")
    # divider between "works" and "breaks"
    ax.axhline(1.5, color="#888", lw=1, ls=":")
    ax.text(1.06, 4.0, "AUTOMATION WORKS", rotation=90, va="center", ha="center", fontsize=9,
            color=GREEN, fontweight="bold")
    ax.text(1.06, 0.5, "AUTOMATION STOPS", rotation=90, va="center", ha="center", fontsize=9,
            color=RED, fontweight="bold")
    ax.set_xlim(0, 1.14); ax.set_ylim(-0.6, len(rows) - 0.05)
    ax.set_yticks([])
    ax.set_xticks([0, 0.25, 0.5, 0.75, 1.0]); ax.set_xticklabels(["0%", "25%", "50%", "75%", "100%"])
    ax.set_xlabel("Stage completion (production-ready fraction)", fontsize=10)
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.set_title("Figure 2. Where automation stops: discovery, metadata and container resolution reach 100%;\nparameter-complete, execution-validated wrappers reach 0% (the paper's central honest finding)",
                 fontsize=10, fontweight="bold")
    plt.tight_layout()
    out = os.path.join(HERE, "fig2_boundary.png")
    plt.savefig(out, dpi=185, bbox_inches="tight"); print("wrote", out)
    plt.close()

fig1(); fig2()
