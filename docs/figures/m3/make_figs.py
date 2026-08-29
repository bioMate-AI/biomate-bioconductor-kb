#!/usr/bin/env python3
"""M3 (Isotype gate-3) manuscript figures.

Style matches docs/figures/c8/make_figs.py:
  palette navy #22445f, teal #2a9d8f, amber #e9a23b, red #c1121f, grey #9aa5ad;
  FancyBboxPatch; matplotlib.use("Agg"); dpi=185; bbox_inches="tight".

Fig 1 (fig1_isotype_mechanism.png) — SCHEMATIC, contains NO patient data
  (per manuscript Fig-1 legend, line 98). Pure mechanism:
  anti-AChR pool by isotype -> FcRn clears IgG only -> BAFF/APRIL lowers all
  -> predicted crossing of treatment benefit by isotype status.
  No numbers appear on the panel.

Fig 2 (fig2_auditable_2x2.png) — AUDITABLE verdict-concordance table.
  ANTI-FABRICATION: the M3 manuscript (§Methods, line 80) states, for six
  biomarker-stratified randomized trials, the true predictive/prognostic class
  and the interaction-test VERDICT, but commits NO 2x2 responder cell counts.
  Because NONE of the trials have committed cell counts in the manuscript, and
  the task forbids inventing any, Fig 2 is built as a VERDICT-CONCORDANCE table
  (trial -> true class -> test verdict), all values quoted from the manuscript
  text. Every trial row also carries its source citation (ref 7 / ref 4).
  ZERO fabricated numbers: the figure contains no responder counts at all.
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
NAVY = "#22445f"; TEAL = "#2a9d8f"; AMBER = "#e9a23b"; RED = "#c1121f"; GREY = "#9aa5ad"


# ---------------------------------------------------------------- Fig 1
def fig1():
    """Isotype -> mechanism -> therapy schematic. No patient data / no numbers."""
    fig, ax = plt.subplots(figsize=(11.5, 6.2))

    # --- LEFT: anti-AChR autoantibody pool decomposed by isotype -------------
    pool_x, pool_y, pool_w, pool_h = 0.30, 3.4, 2.35, 2.6
    pool = FancyBboxPatch((pool_x, pool_y), pool_w, pool_h,
                          boxstyle="round,pad=0.03,rounding_size=0.12",
                          linewidth=2, edgecolor=NAVY, facecolor=NAVY + "10")
    ax.add_patch(pool)
    ax.text(pool_x + pool_w / 2, pool_y + pool_h + 0.18,
            "Anti-AChR autoantibody pool", ha="center", va="bottom",
            fontsize=10.5, fontweight="bold", color=NAVY)
    # isotype chips inside the pool (IgG subclasses = teal = FcRn-clearable;
    # IgA/IgM = amber = FcRn-refractory). No quantities.
    isos = [
        ("IgG1", TEAL), ("IgG2", TEAL), ("IgG3", TEAL), ("IgG4", TEAL),
        ("IgA", AMBER), ("IgM", AMBER),
    ]
    cw, ch, cgap = 0.62, 0.46, 0.12
    cols = 2
    for i, (lab, col) in enumerate(isos):
        r, c = divmod(i, cols)
        cx = pool_x + 0.28 + c * (cw + cgap)
        cy = pool_y + pool_h - 0.62 - r * (ch + 0.10)
        chip = FancyBboxPatch((cx, cy), cw, ch,
                              boxstyle="round,pad=0.01,rounding_size=0.06",
                              linewidth=1.4, edgecolor=col, facecolor=col + "33")
        ax.add_patch(chip)
        ax.text(cx + cw / 2, cy + ch / 2, lab, ha="center", va="center",
                fontsize=8.5, fontweight="bold", color=col)
    ax.text(pool_x + pool_w / 2, pool_y - 0.02,
            "IgG subclasses (teal) vs IgA / IgM (amber)",
            ha="center", va="top", fontsize=7.6, style="italic", color="#555")

    # --- TWO mechanism arrows to two therapy boxes --------------------------
    # FcRn antagonism (upper) — clears IgG only
    fcrn_x, fcrn_y, bw, bh = 4.35, 4.55, 3.0, 1.35
    fcrn = FancyBboxPatch((fcrn_x, fcrn_y), bw, bh,
                          boxstyle="round,pad=0.03,rounding_size=0.12",
                          linewidth=2, edgecolor=TEAL, facecolor=TEAL + "18")
    ax.add_patch(fcrn)
    ax.text(fcrn_x + bw / 2, fcrn_y + bh - 0.30, "FcRn antagonism",
            ha="center", va="center", fontsize=10.5, fontweight="bold", color=TEAL)
    ax.text(fcrn_x + bw / 2, fcrn_y + 0.42,
            "clears IgG only\n→ IgA / IgM pathology remains",
            ha="center", va="center", fontsize=8.6, color="#333")
    ar1 = FancyArrowPatch((pool_x + pool_w, pool_y + pool_h - 0.5),
                          (fcrn_x, fcrn_y + bh / 2),
                          arrowstyle="-|>", mutation_scale=16, lw=1.8,
                          color=TEAL, connectionstyle="arc3,rad=-0.18")
    ax.add_patch(ar1)

    # BAFF/APRIL depletion (lower) — lowers all isotypes
    baff_x, baff_y = 4.35, 2.55
    baff = FancyBboxPatch((baff_x, baff_y), bw, bh,
                          boxstyle="round,pad=0.03,rounding_size=0.12",
                          linewidth=2, edgecolor=AMBER, facecolor=AMBER + "18")
    ax.add_patch(baff)
    ax.text(baff_x + bw / 2, baff_y + bh - 0.30, "BAFF / APRIL depletion",
            ha="center", va="center", fontsize=10.5, fontweight="bold", color=AMBER)
    ax.text(baff_x + bw / 2, baff_y + 0.42,
            "depletes B / plasma cells\n→ lowers ALL isotypes",
            ha="center", va="center", fontsize=8.6, color="#333")
    ar2 = FancyArrowPatch((pool_x + pool_w, pool_y + 0.5),
                          (baff_x, baff_y + bh / 2),
                          arrowstyle="-|>", mutation_scale=16, lw=1.8,
                          color=AMBER, connectionstyle="arc3,rad=0.18")
    ax.add_patch(ar2)

    # --- RIGHT: predicted crossing of treatment benefit by isotype status ----
    # inset axes for the interaction (crossing) schematic. No numeric ticks.
    ix, iy, iw, ih = 8.15, 2.65, 2.9, 3.25
    ins = fig.add_axes([0, 0, 1, 1])  # placeholder; replaced below
    ins.remove()
    ax_in = ax.inset_axes([ix, iy, iw, ih], transform=ax.transData)
    # two lines crossing: FcRn benefit high for IgG-dominant, low for IgA/IgM;
    # BAFF/APRIL benefit flat/high across -> crossing = interaction.
    xg = [0, 1]  # 0 = IgG-dominant, 1 = IgA/IgM-contributing (schematic)
    ax_in.plot(xg, [0.85, 0.30], color=TEAL, lw=2.6, marker="o", label="FcRn inhibitor")
    ax_in.plot(xg, [0.55, 0.78], color=AMBER, lw=2.6, marker="s", label="BAFF/APRIL")
    ax_in.plot(0.62, 0.55, marker="X", ms=11, color=RED)  # crossing marker
    ax_in.annotate("crossing =\nbiomarker × treatment\ninteraction",
                   xy=(0.62, 0.55), xytext=(0.02, 0.10),
                   fontsize=7.6, color=RED, ha="left", va="bottom",
                   arrowprops=dict(arrowstyle="->", color=RED, lw=1.2))
    ax_in.set_xlim(-0.12, 1.12); ax_in.set_ylim(0, 1)
    ax_in.set_xticks([0, 1])
    ax_in.set_xticklabels(["IgG-\ndominant", "IgA/IgM-\ncontributing"], fontsize=7.4)
    ax_in.set_yticks([])
    ax_in.set_ylabel("predicted treatment benefit", fontsize=7.8)
    ax_in.set_title("Predicted crossing by isotype status", fontsize=8.6,
                    fontweight="bold", color=NAVY)
    ax_in.legend(fontsize=6.8, loc="lower center", frameon=False,
                 ncol=2, bbox_to_anchor=(0.5, -0.30))
    for s in ("top", "right"):
        ax_in.spines[s].set_visible(False)

    ax.set_xlim(0, 11.4); ax.set_ylim(1.4, 6.9); ax.axis("off")
    ax.set_title(
        "Figure 1. Isotype → mechanism → therapy. FcRn antagonism clears IgG only "
        "(IgA/IgM pathology persists);\nBAFF/APRIL depletion lowers all isotypes — "
        "predicting a crossing of treatment benefit by isotype status. Schematic; no patient data.",
        fontsize=9.6, fontweight="bold")
    plt.tight_layout()
    out = os.path.join(HERE, "fig1_isotype_mechanism.png")
    plt.savefig(out, dpi=185, bbox_inches="tight"); print("wrote", out)
    plt.close()


# ---------------------------------------------------------------- Fig 2
def fig2():
    """Auditable verdict-concordance table.

    Every field below is quoted from the M3 manuscript (§Methods, line 80;
    references 4 and 7). NO 2x2 responder cell counts exist in the manuscript,
    so none are shown. The 'Cells' column records the manuscript's own caveat.
    """
    # (trial, biomarker / setting, true class, test verdict, cells-status, ref)
    rows = [
        ("IPASS", "EGFR mutation (gefitinib)", "predictive", "predictive",
         "cells not reconstructed\n(not stated in manuscript)", "ref 7a"),
        ("CRYSTAL", "KRAS/RAS (anti-EGFR)", "predictive", "predictive",
         "cells not reconstructed\n(not stated in manuscript)", "ref 7b"),
        ("OPUS", "KRAS/RAS (anti-EGFR)", "predictive", "predictive",
         "cells not reconstructed\n(not stated in manuscript)", "ref 7c"),
        ("PROFILE", "prognostic signature (Crohn's)", "non-predictive", "non-predictive",
         "cells not reconstructed\n(not stated in manuscript)", "ref 4"),
        ("MERiDiAN", "plasma VEGF-A (bevacizumab)", "non-predictive", "non-predictive",
         "cells not reconstructed\n(not stated in manuscript)", "ref 7d"),
        ("COIN", "KRAS (negative trial)", "non-predictive", "non-predictive",
         "cells not reconstructed\n(not stated in manuscript)", "ref 7e"),
    ]

    fig, ax = plt.subplots(figsize=(12.4, 5.6))
    ax.set_xlim(0, 12.4); ax.set_ylim(0, 6.4); ax.axis("off")

    # column layout
    cols = [
        ("Trial", 0.35, 1.55, "left"),
        ("Biomarker / setting", 1.95, 3.55, "left"),
        ("True class", 5.65, 1.55, "center"),
        ("Test verdict", 7.35, 1.55, "center"),
        ("2×2 cells", 9.05, 2.35, "center"),
        ("Source", 11.55, 0.75, "center"),
    ]
    header_y = 5.75
    for name, x0, w, align in cols:
        cx = x0 if align == "left" else x0 + w / 2
        ax.text(cx, header_y, name, ha=align, va="center",
                fontsize=9.5, fontweight="bold", color=NAVY)
    ax.plot([0.25, 12.15], [header_y - 0.28, header_y - 0.28], color=NAVY, lw=1.6)

    row_h = 0.85
    y = header_y - 0.65
    for trial, bmk, tcls, verdict, cells, ref in rows:
        concordant = (tcls == verdict)
        vcol = TEAL if verdict == "predictive" else GREY
        # subtle row band
        band = FancyBboxPatch((0.25, y - row_h / 2 + 0.06), 11.9, row_h - 0.12,
                              boxstyle="round,pad=0.005,rounding_size=0.03",
                              linewidth=0, facecolor=(TEAL + "12" if concordant else RED + "14"))
        ax.add_patch(band)
        ax.text(cols[0][1], y, trial, ha="left", va="center",
                fontsize=9.2, fontweight="bold", color=NAVY)
        ax.text(cols[1][1], y, bmk, ha="left", va="center", fontsize=8.4, color="#333")
        # true class pill
        ax.text(cols[2][1] + cols[2][2] / 2, y, tcls, ha="center", va="center",
                fontsize=8.6, color="#333")
        # verdict pill (coloured)
        vx = cols[3][1]; vw = cols[3][2]
        pill = FancyBboxPatch((vx + 0.12, y - 0.22), vw - 0.24, 0.44,
                              boxstyle="round,pad=0.01,rounding_size=0.10",
                              linewidth=1.4, edgecolor=vcol, facecolor=vcol + "2a")
        ax.add_patch(pill)
        ax.text(vx + vw / 2, y, verdict, ha="center", va="center",
                fontsize=8.4, fontweight="bold", color=vcol)
        # cells caveat
        ax.text(cols[4][1] + cols[4][2] / 2, y, cells, ha="center", va="center",
                fontsize=7.0, style="italic", color=AMBER)
        # source
        ax.text(cols[5][1], y, ref, ha="center", va="center", fontsize=7.8, color="#555")
        # concordance check at far right edge of row
        y -= row_h

    # footer / provenance note
    note = ("All classes and verdicts quoted verbatim from the M3 manuscript, §Methods "
            "(line 80) and references 4, 7. No trial's 2×2 responder cell counts are stated "
            "in the manuscript, so none are shown — this panel reports verdict concordance only "
            "(zero reconstructed cells).")
    ax.text(0.25, y + 0.05, note, ha="left", va="top", fontsize=7.6,
            color="#555", wrap=True)

    ax.set_title(
        "Figure 2. Verdict concordance of the gate-3 interaction test on six real biomarker-stratified trials\n"
        "(true class vs test verdict) — auditable, source-cited; 2×2 cells not reconstructed because not published in the manuscript",
        fontsize=9.8, fontweight="bold")
    plt.tight_layout()
    out = os.path.join(HERE, "fig2_auditable_2x2.png")
    plt.savefig(out, dpi=185, bbox_inches="tight"); print("wrote", out)
    plt.close()


fig1(); fig2()
