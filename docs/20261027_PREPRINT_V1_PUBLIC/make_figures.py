#!/usr/bin/env python3
"""Figures for the manuscript. Figures 1 and 5 are schematics; Figure 2 and Figure 4 plot measured values; Figures 3 and 6 are drawn from
evaluation outputs (JSON) when those files are passed, so no result is ever typed in by hand.
usage: make_figures.py [stageB_eval.json] [loop_result.json]"""
import sys, json, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

BLUE, ORANGE, AQUA, GRAY, INK, INK2, GRID, SURF = "#2a78d6", "#eb6834", "#1baf7a", "#7a7974", "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 9, "axes.edgecolor": GRID, "axes.labelcolor": INK2, "xtick.color": INK2,
                     "ytick.color": INK2, "text.color": INK, "figure.facecolor": SURF, "axes.facecolor": SURF, "savefig.facecolor": SURF})
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "figures")


def box(ax, x, y, w, h, text, fc="#ffffff", ec=GRID, color=INK, fs=8.5, bold=False):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.01,rounding_size=0.015", fc=fc, ec=ec, lw=1.2))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fs, color=color, fontweight="bold" if bold else "normal", wrap=True)


def arrow(ax, x1, y1, x2, y2, color=INK2):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle="-|>", mutation_scale=11, lw=1.3, color=color))


def fig1():
    f, ax = plt.subplots(figsize=(10.5, 5.6)); ax.set_xlim(-0.02, 1.02); ax.set_ylim(0, 1); ax.axis("off")
    ax.text(-0.02, 0.99, "Study design", fontsize=12, fontweight="bold", va="top")
    box(ax, 0.00, 0.68, 0.19, 0.22, "Experimental\ncyclic-peptide\ncomplexes (PDB),\ncovalent-link records", fc="#f2f1ee", fs=8)
    box(ax, 0.235, 0.79, 0.245, 0.11, "Deposited before 2023-10-01\nTRAIN: fit selector only", ec=BLUE, color=BLUE, bold=True, fs=7.5)
    box(ax, 0.235, 0.66, 0.245, 0.11, "Deposited on/after 2023-10-01\nTEST: evaluated once", ec=ORANGE, color=ORANGE, bold=True, fs=7.5)
    arrow(ax, 0.19, 0.82, 0.235, 0.845); arrow(ax, 0.19, 0.76, 0.235, 0.715)
    box(ax, 0.52, 0.68, 0.22, 0.22, "Co-folding model:\n25 diffusion samples\nper complex (sequence and\nring topology only; no\nnative coordinates)", fc="#f2f1ee", fs=8)
    arrow(ax, 0.48, 0.845, 0.52, 0.82); arrow(ax, 0.48, 0.715, 0.52, 0.76)
    box(ax, 0.79, 0.68, 0.21, 0.22, "Ground-truth-free\nfeatures per sample:\nconfidences, ring geometry,\nclashes, pose consensus\n(z-scored within complex)", fc="#f2f1ee", fs=8)
    arrow(ax, 0.74, 0.79, 0.79, 0.79)
    # bus from cofold output to both selector families
    ax.plot([0.63, 0.63], [0.68, 0.58], color=INK2, lw=1.3); ax.plot([0.14, 0.63], [0.58, 0.58], color=INK2, lw=1.3)
    ax.plot([0.89, 0.89], [0.68, 0.58], color=INK2, lw=1.3); ax.plot([0.48, 0.89], [0.58, 0.58], color=INK2, lw=1.3)
    arrow(ax, 0.14, 0.58, 0.14, 0.52); arrow(ax, 0.48, 0.58, 0.48, 0.52)
    box(ax, 0.00, 0.37, 0.30, 0.15, "Six fixed baselines (raw scores):\nmodel confidence, ipTM, pTM,\ninterface pLDDT, ring strain, clashes", ec=GRAY, color=INK2, fs=8)
    box(ax, 0.34, 0.37, 0.30, 0.15, "Learned selector\nL2 logistic regression;\nbest-scoring sample per complex", ec=BLUE, color=BLUE, bold=True, fs=8)
    box(ax, 0.70, 0.37, 0.30, 0.15, "References (not methods):\nrandom sample (expectation) and\noracle best-of-25", ec=GRAY, color=INK2, fs=8)
    arrow(ax, 0.15, 0.37, 0.22, 0.30); arrow(ax, 0.49, 0.37, 0.49, 0.30); arrow(ax, 0.85, 0.37, 0.68, 0.30)
    box(ax, 0.08, 0.17, 0.62, 0.13, "Top-1 success: DockQ of the picked sample vs the experimental\ncomplex, at \u2265 0.23 (acceptable) and \u2265 0.49 (medium)", fc="#f2f1ee", fs=8)
    box(ax, 0.75, 0.17, 0.25, 0.13, "Protocol and claim rule\nfixed before any test\nsample was scored", fs=7.5)
    box(ax, 0.00, 0.01, 1.00, 0.10, "Paired bootstrap over receptor clusters (complexes of one receptor are not independent). Strongest baseline chosen on the test set.\nReported on all test complexes AND on receptors absent from training.", fs=7.5)
    f.savefig(f"{OUT}/fig1_study_design.png", dpi=220, bbox_inches="tight"); plt.close(f)


def fig2():
    names = ["Model confidence\n(default pick)", "ipTM", "Random sample\n(expected)", "Best of 25\n(oracle)"]
    val = [80.8, 76.9, 80.3, 96.2]; lo = [65, 62, 68, 88]; hi = [96, 92, 92, 100]
    cols = [BLUE, BLUE, GRAY, ORANGE]
    f, ax = plt.subplots(figsize=(6.4, 3.8))
    bars = ax.bar(range(4), val, color=cols, width=0.55)
    ax.errorbar(range(4), val, yerr=[[v - l for v, l in zip(val, lo)], [h - v for v, h in zip(val, hi)]], fmt="none", ecolor=INK2, capsize=3, lw=1)
    for i, v in enumerate(val): ax.text(i, hi[i] + 1.5, f"{v:.1f}%", ha="center", fontsize=9, color=INK)
    ax.set_xticks(range(4)); ax.set_xticklabels(names, fontsize=8.5); ax.set_ylim(0, 112); ax.set_ylabel("Top-1 success, DockQ ≥ 0.23 (%)")
    ax.yaxis.grid(True, color=GRID); ax.set_axisbelow(True)
    for s in ("top", "right"): ax.spines[s].set_visible(False)
    ax.set_title("Pilot (26 complexes): the default pick is no better than a random sample", loc="left", fontsize=10, fontweight="bold")
    f.text(0.01, -0.02, "Error bars: 95% receptor-cluster bootstrap CI. Oracle uses the experimental structure and is an upper bound, not a method.", fontsize=7.5, color=INK2)
    f.savefig(f"{OUT}/fig2_pilot_headroom.png", dpi=220, bbox_inches="tight"); plt.close(f)


def fig3(path):
    r = json.load(open(path)); f, axes = plt.subplots(1, 2, figsize=(10, 3.9), sharey=True)
    order = [("S", "Learned selector", BLUE), ("default", "Model confidence", GRAY), ("iptm", "ipTM", GRAY), ("ptm", "pTM", GRAY), ("if_plddt", "Interface pLDDT", GRAY),
             ("ring_strain", "Ring strain", GRAY), ("clash_count", "Clashes", GRAY), ("random", "Random", GRAY), ("oracle", "Oracle", ORANGE)]
    for ax, key, title in zip(axes, ("all_thr0.23", "novel_receptor_thr0.23"), ("All test complexes", "Receptors absent from training")):
        if key not in r: ax.axis("off"); ax.set_title(title + " (n/a)"); continue
        v = [100 * r[key]["success"][k] for k, _, _ in order]
        ax.barh(range(len(order)), v, color=[c for _, _, c in order], height=0.6)
        for i, x in enumerate(v): ax.text(x + 1, i, f"{x:.1f}%", va="center", fontsize=8)
        ax.set_yticks(range(len(order))); ax.set_yticklabels([n for _, n, _ in order]); ax.set_xlim(0, 110)
        d = r[key]["S_minus_strongest"]; ax.set_title(f"{title} (n={r[key]['n_complexes']})\nselector − strongest baseline: {100*d['value']:+.1f} pp  [{100*d['ci95'][0]:+.1f}, {100*d['ci95'][1]:+.1f}]", loc="left", fontsize=9, fontweight="bold")
        ax.set_xlabel("Top-1 success, DockQ ≥ 0.23 (%)")
        for s in ("top", "right"): ax.spines[s].set_visible(False)
    axes[0].invert_yaxis()                       # shared y-axis: invert once so the selector is the top row
    f.savefig(f"{OUT}/fig3_primary_result.png", dpi=220, bbox_inches="tight"); plt.close(f)


def fig4():
    t = ["Abeta42", "hIAPP", "hPCSK9", "PADI4", "FIKK13"]
    rand = [0.986, 0.698, 0.841, 0.865, 0.924]; fam = [0.957, 0.521, 0.653, 0.864, 0.415]; lm = [0.990, 0.689, 0.815, 0.968, None]
    f, ax = plt.subplots(figsize=(9, 4.2)); w = 0.26
    for j, (v, c, n) in enumerate(((rand, GRAY, "k-mer baseline, random split"), (fam, ORANGE, "k-mer baseline, family-disjoint split"), (lm, BLUE, "Language model, random split (as reported)"))):
        for i, y in enumerate(v):
            if y is None: continue
            x = i + (j - 1) * w; ax.bar(x, y, w * 0.92, color=c, label=n if i == 0 or (i == 1 and v[0] is None) else None)
            ax.text(x, y + 0.012, f"{y + 1e-9:.2f}", ha="center", fontsize=8)
    ax.axhline(0.5, color=INK2, lw=0.8, ls=(0, (4, 3))); ax.text(4.62, 0.505, "chance", fontsize=7.5, color=INK2, ha="right", va="bottom")
    ax.text(4 + w, 0.08, "no LM\nresult", fontsize=7.5, color=INK2, ha="center", va="center")
    ax.set_xticks(range(5)); ax.set_xticklabels(t); ax.set_ylim(0, 1.1); ax.set_ylabel("AUC (binder vs non-binder)")
    ax.yaxis.grid(True, color=GRID); ax.set_axisbelow(True); ax.legend(frameon=False, fontsize=8, loc="upper center", bbox_to_anchor=(0.5, 1.2), ncol=3)
    for s_ in ("top", "right"): ax.spines[s_].set_visible(False)
    f.text(0.01, -0.04, "Family = connected set of sequences differing by one substitution. FIKK13 random-split AUC rests on 8 test binders. hPCSK9 LM value is from a model trained jointly on five targets (single-target model: 0.36).", fontsize=7.2, color=INK2)
    f.savefig(f"{OUT}/fig4_reliability_audit.png", dpi=220, bbox_inches="tight"); plt.close(f)


def fig5():
    f, axes = plt.subplots(1, 3, figsize=(10, 3.3))
    import random
    rnd = random.Random(3)
    fams = [(0.2, 0.7, BLUE), (0.55, 0.78, BLUE), (0.3, 0.3, ORANGE), (0.7, 0.35, ORANGE), (0.82, 0.8, GRAY)]
    titles = ["Random split of sequences", "Family-disjoint split", "Receptor-disjoint split"]
    notes = ["Siblings of one family land on both\nsides: memorising a motif scores well", "Whole families held out:\ntests generalisation to new motifs", "Whole receptors held out:\ntests generalisation to new targets"]
    for k, ax in enumerate(axes):
        ax.set_xlim(0, 1); ax.set_ylim(0, 1); ax.axis("off"); ax.set_title(titles[k], fontsize=9.5, fontweight="bold", loc="left")
        for (cx, cy, c) in fams:
            ax.add_patch(plt.Circle((cx, cy), 0.12, fc="none", ec=GRID, lw=1))
            for _ in range(9):
                x = cx + rnd.uniform(-0.09, 0.09); y = cy + rnd.uniform(-0.09, 0.09)
                test = (rnd.random() < 0.3) if k == 0 else ((cx, cy) in [(0.3, 0.3), (0.82, 0.8)] if k == 1 else c == ORANGE)
                ax.scatter([x], [y], s=34, c=[c] if not test else ["#ffffff"], edgecolors=c, linewidths=1.5, zorder=3)
        ax.text(0.0, -0.08, notes[k], fontsize=8, color=INK2, va="top", transform=ax.transAxes)
    f.text(0.01, 1.0, "Filled = training, open = test. Colours = receptor; circles = sequence families.", fontsize=8, color=INK2, va="bottom")
    f.savefig(f"{OUT}/fig5_split_strategies.png", dpi=220, bbox_inches="tight"); plt.close(f)


def fig6(path):
    r = json.load(open(path)); f, axes = plt.subplots(1, 2, figsize=(9, 3.6))
    for ax, key, title in zip(axes, ("regime_A_iid", "regime_B_shift"), ("In-distribution start", "Scaffold-shifted start")):
        d = r[key]; names = [("random", "Random", GRAY), ("greedy", "Greedy", BLUE), ("ucb", "Uncertainty-aware", AQUA), ("oracle", "Oracle", ORANGE)]
        m = [d[k]["mean"] for k, _, _ in names]; lo = [d[k]["ci95"][0] for k, _, _ in names]; hi = [d[k]["ci95"][1] for k, _, _ in names]
        ax.bar(range(4), m, color=[c for *_, c in names], width=0.55)
        ax.errorbar(range(4), m, yerr=[[a - b for a, b in zip(m, lo)], [b - a for a, b in zip(m, hi)]], fmt="none", ecolor=INK2, capsize=3, lw=1)
        ax.set_xticks(range(4)); ax.set_xticklabels([n for _, n, _ in names], fontsize=8); ax.set_title(title, loc="left", fontsize=9.5, fontweight="bold")
        ax.set_ylabel("Permeable peptides found (of 500 picks)"); ax.yaxis.grid(True, color=GRID); ax.set_axisbelow(True)
        for s in ("top", "right"): ax.spines[s].set_visible(False)
    f.savefig(f"{OUT}/fig6_retrospective_loop.png", dpi=220, bbox_inches="tight"); plt.close(f)


def fig_loop():
    f, ax = plt.subplots(figsize=(10, 4.2)); ax.set_xlim(-0.02, 1.02); ax.set_ylim(0, 1); ax.axis("off")
    ax.text(-0.02, 0.99, "Retrospective closed loop on measured permeability", fontsize=12, fontweight="bold", va="top")
    box(ax, 0.00, 0.45, 0.20, 0.30, "Pool of measured\ncyclic peptides\n(labels hidden)\n\nstart: 100 labelled", fc="#f2f1ee", fs=8.5)
    box(ax, 0.27, 0.45, 0.20, 0.30, "Model\nensemble of 5\ngradient-boosted\nregressors on\nfingerprints", ec=BLUE, color=BLUE, bold=True, fs=8.5)
    box(ax, 0.54, 0.45, 0.20, 0.30, "Policy picks 50\n\nrandom\ngreedy (mean)\nuncertainty-aware\n(mean + std)", fs=8.5)
    box(ax, 0.81, 0.45, 0.19, 0.30, "Held-out label\nrevealed for the\n50 picks (the\n\"assay\")", ec=ORANGE, color=ORANGE, bold=True, fs=8.5)
    arrow(ax, 0.20, 0.60, 0.27, 0.60); arrow(ax, 0.47, 0.60, 0.54, 0.60); arrow(ax, 0.74, 0.60, 0.81, 0.60)
    ax.plot([0.905, 0.905, 0.37], [0.45, 0.30, 0.30], color=INK2, lw=1.3); arrow(ax, 0.37, 0.30, 0.37, 0.45)
    ax.text(0.64, 0.255, "retrain on all revealed labels; repeat for 10 rounds", ha="center", fontsize=8.5, color=INK2)
    box(ax, 0.00, 0.03, 1.0, 0.13, "Two starts: in-distribution (random 100) and scaffold-shifted (100 from two literature sources; pool excludes their scaffolds).\nOutcome: permeable peptides (top 10% of the pool) found in 500 picks; 30 seeds; paired bootstrap.", fs=8)
    f.savefig(f"{OUT}/figL1_loop_design.png", dpi=220, bbox_inches="tight"); plt.close(f)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True); fig1(); fig2(); fig4(); fig5(); fig_loop()
    if len(sys.argv) > 1 and os.path.exists(sys.argv[1]): fig3(sys.argv[1])
    if len(sys.argv) > 2 and os.path.exists(sys.argv[2]): fig6(sys.argv[2])
    print(os.listdir(OUT))
