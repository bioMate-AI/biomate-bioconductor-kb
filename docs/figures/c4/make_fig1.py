#!/usr/bin/env python3
"""C4 (BioMate-Cryo evidence-graded QC governance) Figure 1.

Box-and-arrow schematic of the interactive, evidence-graded QC governance layer
that BioMate-Cryo inserts on top of the 23-step CryoSPARC single-particle
analysis (SPA) pipeline. Every stage name, gate name, metric, evidence grade,
and decision label is quoted from the manuscript
research_repos/cryo_em_benchmark_paper/manuscript/MANUSCRIPT_DRAFT.md.

Source lines (MANUSCRIPT_DRAFT.md):
  - Pipeline: "23-step CryoSPARC single-particle analysis workflow across four
    parallelized phases" (Phase A Preprocessing, B Picking, C Classification,
    D Reconstruction) — §2.1, lines 78-88.
  - Input "Movie import" / "Movies" — §2.1 Phase A (line 80).
  - Seven QC gate modules, their phase placement, metric names and evidence
    grades — §2.2, lines 92-120:
      Gate 1 Motion correction (Phase A exit): total_drift_angstrom; per-frame
        drift <=5 A (BRONZE) — line 108.
      Gate 2 CTF estimation (Phase A exit): ctf_fit_to_angstrom; defocus_A
        1,000-100,000 A hard gate; astigmatism advisory (BRONZE) — line 110.
      Gate 3 Particle picking (Phase B exit): n_particles_picked > 1,000
        (BRONZE) — line 112.
      Gate 4 2D classification junk (Phase C exit): junk class fraction < 70%
        (BRONZE) — line 114.
      Gate 5 Orientation anisotropy (Phase D, after homogeneous refinement):
        sphericity ratio > 0.5 (SILVER, Tan et al. 2017) — line 116.
      Gate 6 FSC validation (Phase D exit): FSC 0.143 criterion (GOLD,
        Henderson et al. 2012); "only GOLD gate ... cannot be overridden
        without explicit PI-level sign-off" — line 118.
      Gate 7 Atomic model quality (Phase D, post-ModelAngelo/Phenix):
        Ramachandran favored >=95% (GOLD, wwPDB); rotamer outliers <=1% (GOLD);
        clashscore <=20 (SILVER); EMRinger >=1.0 (SILVER, Barad et al. 2015)
        — line 120.
  - Evidence tiers GOLD / SILVER / BRONZE and their override policy — §2.4,
    lines 141-147:
      GOLD  = published consensus; override needs PI-level written approval.
      SILVER = method-specific best practice; override needs logged
        justification.
      BRONZE = community heuristic; auditable but flexible.
  - Gate decision values PASS / HALT / ADVISORY — §2.2 gate-result JSON
    (lines 94-106) and §2.5 audit schema (line 151).
  - Interactive governance loop "halt -> explain -> suggest -> await decision
    -> record" — §4.1, line 327; §1.4 innovation 1 (line 64).
  - JSONL audit-trail fields — §2.5, line 151: ISO-8601 timestamp, run UUID,
    gate ID, phase, metric name, value, threshold, profile, evidence level,
    gate result (PASS/HALT/ADVISORY), override flag, override justification,
    approver, software version.

No metrics/results are printed on the schematic (a governance design diagram
needs none); this figure is labels only, all quoted from the paper text.
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
# House palette (from docs/figures/c8/make_figs.py)
NAVY = "#22445f"; TEAL = "#2a9d8f"; AMBER = "#e9a23b"; RED = "#c1121f"; GREY = "#9aa5ad"

# Evidence-grade -> colour (GOLD=amber, SILVER=grey, BRONZE=teal, chosen from
# the house palette; encodes only the paper's three named tiers).
GRADE_COL = {"GOLD": AMBER, "SILVER": GREY, "BRONZE": TEAL}


def gate_box(ax, x, y, w, h, gate_no, name, metric, grade):
    col = GRADE_COL[grade]
    box = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.10",
                         linewidth=2, edgecolor=col, facecolor=col + "20")
    ax.add_patch(box)
    ax.text(x + w / 2, y + h - 0.22, "Gate %d" % gate_no, ha="center", va="center",
            fontsize=8.5, fontweight="bold", color=col)
    ax.text(x + w / 2, y + h - 0.46, name, ha="center", va="center",
            fontsize=8.0, fontweight="bold", color="#222")
    ax.text(x + w / 2, y + 0.42, metric, ha="center", va="center",
            fontsize=6.8, color="#333")
    # evidence-grade chip
    ax.text(x + w / 2, y + 0.10, grade, ha="center", va="center",
            fontsize=7.2, fontweight="bold", color="white",
            bbox=dict(boxstyle="round,pad=0.18", fc=col, ec=col))
    return x + w / 2


def phase_box(ax, x, y, w, h, name, steps, col=NAVY):
    box = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.08",
                         linewidth=1.6, edgecolor=col, facecolor=col + "12")
    ax.add_patch(box)
    ax.text(x + w / 2, y + h - 0.22, name, ha="center", va="center",
            fontsize=8.6, fontweight="bold", color=col)
    ax.text(x + w / 2, y + (h - 0.5) / 2, steps, ha="center", va="center",
            fontsize=6.6, color="#444")
    return x + w / 2


def arrow(ax, x0, y0, x1, y1, col=NAVY, lw=1.7, ls="-"):
    ax.add_patch(FancyArrowPatch((x0, y0), (x1, y1), arrowstyle="-|>",
                                 mutation_scale=13, lw=lw, color=col,
                                 linestyle=ls))


def fig1():
    fig, ax = plt.subplots(figsize=(15.5, 7.4))

    # ---- Row geometry -------------------------------------------------
    phase_y = 5.5; phase_h = 1.15; phase_w = 2.55; phase_gap = 0.55
    gate_y = 3.15; gate_h = 1.35; gate_w = 1.72; gate_gap = 0.28
    x0 = 0.55

    # ---- Input: movies ------------------------------------------------
    in_x, in_y, in_w, in_h = x0, phase_y + 0.06, 1.55, phase_h - 0.12
    ibox = FancyBboxPatch((in_x, in_y), in_w, in_h,
                          boxstyle="round,pad=0.02,rounding_size=0.10",
                          linewidth=1.8, edgecolor=GREY, facecolor=GREY + "22")
    ax.add_patch(ibox)
    ax.text(in_x + in_w / 2, in_y + in_h - 0.28, "INPUT", ha="center",
            va="center", fontsize=8.6, fontweight="bold", color=GREY)
    ax.text(in_x + in_w / 2, in_y + 0.42, "Raw movies\n(EMPIAR import)",
            ha="center", va="center", fontsize=7.2, color="#333")

    # ---- Phases A-D (the 23-step CryoSPARC SPA pipeline) --------------
    px = in_x + in_w + phase_gap
    phases = [
        ("Phase A\nPreprocessing",
         "movie import ->\npatch motion corr. ->\npatch CTF est. ->\nmicrograph curation"),
        ("Phase B\nPicking",
         "blob picker (R1) ->\njunk 2D detector ->\ninspect picks ->\nextract (R1)"),
        ("Phase C\nClassification",
         "2D classification x2 ->\nclass selection ->\ntemplate picker (R2) ->\nextract (R2)"),
        ("Phase D\nReconstruction",
         "ab-initio -> homo refine ->\nvolume tools -> FSC valid. ->\nlocal CTF -> NU refine ->\nlocal res -> sharpen"),
    ]
    phase_centers = []
    for name, steps in phases:
        cx = phase_box(ax, px, phase_y, phase_w, phase_h, name, steps)
        phase_centers.append((px, cx, px + phase_w))
        px += phase_w + phase_gap

    # input -> phase A
    arrow(ax, in_x + in_w, phase_y + phase_h / 2,
          phase_centers[0][0], phase_y + phase_h / 2, col=GREY)
    # phase -> phase
    for i in range(len(phases) - 1):
        arrow(ax, phase_centers[i][2], phase_y + phase_h / 2,
              phase_centers[i + 1][0], phase_y + phase_h / 2)

    # banner over the phase row
    ax.text((phase_centers[0][0] + phase_centers[-1][2]) / 2, phase_y + phase_h + 0.30,
            "23-step CryoSPARC single-particle analysis (SPA) pipeline  -  4 parallelized phases",
            ha="center", va="center", fontsize=9.2, fontweight="bold", color=NAVY)

    # ---- Seven QC gate modules (blocking checkpoints) -----------------
    gates = [
        (1, "Motion\ncorrection", "total_drift_angstrom;\nper-frame drift <=5 A", "BRONZE"),
        (2, "CTF\nestimation", "ctf_fit_to_angstrom;\ndefocus 1k-100k A (hard);\nastigmatism advisory", "BRONZE"),
        (3, "Particle\npicking", "n_particles_picked\n> 1,000", "BRONZE"),
        (4, "2D class.\njunk", "junk class\nfraction < 70%", "BRONZE"),
        (5, "Orientation\nanisotropy", "sphericity ratio > 0.5\n(Tan et al. 2017)", "SILVER"),
        (6, "FSC\nvalidation", "FSC 0.143 criterion\n(Henderson et al. 2012)", "GOLD"),
        (7, "Atomic model\nquality", "Ramachandran >=95%;\nrotamer <=1%; clashscore\n<=20; EMRinger >=1.0", "GOLD"),
    ]
    # phase each gate belongs to (for the dashed drop-lines from the pipeline row)
    gate_phase = {1: 0, 2: 0, 3: 1, 4: 2, 5: 3, 6: 3, 7: 3}

    gx = x0 + 0.55
    gate_centers = {}
    for gate_no, name, metric, grade in gates:
        cx = gate_box(ax, gx, gate_y, gate_w, gate_h, gate_no, name, metric, grade)
        gate_centers[gate_no] = cx
        gx += gate_w + gate_gap

    # dashed drop-lines: pipeline phase -> its exit gate(s)
    for gate_no, name, metric, grade in gates:
        pcx = phase_centers[gate_phase[gate_no]][1]
        gcx = gate_centers[gate_no]
        col = GRADE_COL[grade]
        arrow(ax, pcx, phase_y - 0.02, gcx, gate_y + gate_h + 0.02,
              col=col, lw=1.2, ls=(0, (4, 3)))

    # sequential arrows across the gate row (the governance sequence)
    gnos = [g[0] for g in gates]
    for i in range(len(gnos) - 1):
        a = gate_centers[gnos[i]] + gate_w / 2
        b = gate_centers[gnos[i + 1]] - gate_w / 2
        arrow(ax, a, gate_y + gate_h / 2, b, gate_y + gate_h / 2, col=NAVY, lw=1.3)

    # ---- Interactive PASS / HALT / ADVISORY decision ------------------
    dec_y = 1.55; dec_h = 1.05
    dec_labels = [
        ("PASS", TEAL, "continue"),
        ("ADVISORY", AMBER, "log + continue"),
        ("HALT", RED, "suspend + notify"),
    ]
    dw = 2.05; dgap = 0.55
    dtot = len(dec_labels) * dw + (len(dec_labels) - 1) * dgap
    dx = gate_centers[4] - dtot / 2   # centred under the gate row (gate 4 ~ middle)
    dec_centers = []
    for lab, col, sub in dec_labels:
        b = FancyBboxPatch((dx, dec_y), dw, dec_h,
                           boxstyle="round,pad=0.02,rounding_size=0.12",
                           linewidth=2, edgecolor=col, facecolor=col + "1e")
        ax.add_patch(b)
        ax.text(dx + dw / 2, dec_y + dec_h - 0.34, lab, ha="center", va="center",
                fontsize=10, fontweight="bold", color=col)
        ax.text(dx + dw / 2, dec_y + 0.32, sub, ha="center", va="center",
                fontsize=7.6, color="#333", style="italic")
        dec_centers.append((dx + dw / 2, col))
        dx += dw + dgap

    # gate row -> interactive decision node
    ax.text(gate_centers[4], gate_y - 0.30,
            "interactive decision  (halt -> explain -> suggest -> await -> record)",
            ha="center", va="center", fontsize=8.6, fontweight="bold", color=NAVY)
    for cx, col in dec_centers:
        arrow(ax, gate_centers[4], gate_y - 0.02, cx, dec_y + dec_h + 0.02,
              col=col, lw=1.3)

    # GOLD override note anchored to the two GOLD gates (6 & 7)
    ax.annotate("GOLD gate: override requires explicit\nPI-level sign-off in the audit trail",
                xy=((gate_centers[6] + gate_centers[7]) / 2, gate_y + gate_h + 0.02),
                xytext=((gate_centers[6] + gate_centers[7]) / 2, gate_y + gate_h + 0.72),
                ha="center", va="center", fontsize=7.4, color=AMBER, fontweight="bold",
                arrowprops=dict(arrowstyle="->", color=AMBER, lw=1.2))

    # ---- JSONL audit trail (terminal sink) ----------------------------
    au_w = 6.6; au_h = 0.98
    au_x = dec_centers[1][0] - au_w / 2
    au_y = 0.08
    abox = FancyBboxPatch((au_x, au_y), au_w, au_h,
                          boxstyle="round,pad=0.02,rounding_size=0.10",
                          linewidth=2, edgecolor=NAVY, facecolor=NAVY + "14")
    ax.add_patch(abox)
    ax.text(au_x + au_w / 2, au_y + au_h - 0.26, "Portable JSONL audit trail",
            ha="center", va="center", fontsize=9, fontweight="bold", color=NAVY)
    ax.text(au_x + au_w / 2, au_y + 0.34,
            "timestamp - run UUID - gate ID - phase - metric - value - threshold - profile -\n"
            "evidence level - result (PASS/HALT/ADVISORY) - override flag + justification - approver - version",
            ha="center", va="center", fontsize=6.7, color="#333")

    # every decision writes to the audit trail
    for cx, col in dec_centers:
        arrow(ax, cx, dec_y - 0.02, au_x + au_w / 2, au_y + au_h + 0.02,
              col=NAVY, lw=1.1, ls=(0, (4, 3)))

    # ---- Evidence-grade legend ----------------------------------------
    leg_x = 12.6; leg_y = 1.35
    ax.text(leg_x, leg_y + 1.05, "Evidence grade", fontsize=8.4, fontweight="bold",
            color="#222")
    leg = [
        ("GOLD", "published consensus;\noverride = PI sign-off"),
        ("SILVER", "method best practice;\noverride = logged justification"),
        ("BRONZE", "community heuristic;\nauditable, flexible"),
    ]
    ly = leg_y + 0.62
    for grade, desc in leg:
        col = GRADE_COL[grade]
        ax.text(leg_x, ly, grade, ha="left", va="center", fontsize=7.6,
                fontweight="bold", color="white",
                bbox=dict(boxstyle="round,pad=0.18", fc=col, ec=col))
        ax.text(leg_x + 0.85, ly, desc, ha="left", va="center", fontsize=6.8,
                color="#333")
        ly -= 0.60

    ax.text(x0, -0.30,
            "Every threshold is citation-backed and every gate evaluation is logged: silent automatic filtering is replaced by "
            "interactive, evidence-graded QC governance with a portable, reproducible audit trail.",
            fontsize=7.6, color="#666", style="italic")

    ax.set_xlim(0, 15.4); ax.set_ylim(-0.55, 7.1); ax.axis("off")
    ax.set_title("Figure 1. BioMate-Cryo interactive evidence-graded QC governance: seven QC gates on the 23-step CryoSPARC SPA pipeline,\n"
                 "each graded GOLD/SILVER/BRONZE, resolving to an interactive PASS/HALT/ADVISORY decision recorded in a portable JSONL audit trail",
                 fontsize=10.5, fontweight="bold")
    plt.tight_layout()
    out = os.path.join(HERE, "fig1_governance.png")
    plt.savefig(out, dpi=185, bbox_inches="tight"); print("wrote", out)
    plt.close()


fig1()
