"""make_figures.py — publication figures for the renal-predictor preprint (local PNGs, not published).
CVD-safe Okabe-Ito palette (validated); single axis; direct value labels; recessive grid."""
from __future__ import annotations
import collections, json, os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import renal_paper_results as R
import renal_design as D
import renal_mechmodel as mm

HERE = os.path.dirname(os.path.abspath(__file__))
FIG = os.path.join(HERE, "figures"); os.makedirs(FIG, exist_ok=True)
BLUE, ORANGE, GRAY, GREEN, INK, MUTED = "#0072B2", "#E69F00", "#999999", "#009E73", "#222222", "#666666"
plt.rcParams.update({"font.size": 11, "axes.edgecolor": "#cccccc", "axes.linewidth": 0.8,
                     "axes.grid": True, "grid.color": "#ececec", "grid.linewidth": 0.8,
                     "figure.dpi": 150, "savefig.dpi": 200, "savefig.bbox": "tight", "font.family": "DejaVu Sans"})


def _despine(ax):
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.set_axisbelow(True)


def fig1_dataset():
    rows = [json.loads(l) for l in open(os.path.join(HERE, "renal_seed_corpus.jsonl"))]
    c = collections.Counter(mm.rs._target_class(r) for r in rows)
    items = sorted(c.items(), key=lambda kv: -kv[1])
    labels = [k.upper() for k, _ in items]; vals = [v for _, v in items]
    fig, ax = plt.subplots(figsize=(7, 3.6))
    y = np.arange(len(labels))
    ax.barh(y, vals, color=BLUE, height=0.64, zorder=3)
    for yi, v in zip(y, vals):
        ax.text(v + 0.6, yi, str(v), va="center", ha="left", color=INK, fontsize=9)
    ax.set_yticks(y); ax.set_yticklabels(labels); ax.invert_yaxis()
    ax.set_xlabel("constructs"); ax.set_title(f"Cross-target renal-biodistribution dataset (n={len(rows)} constructs)", loc="left")
    _despine(ax); ax.grid(axis="y", visible=False)
    fig.savefig(os.path.join(FIG, "F1_dataset.png")); plt.close(fig)


def fig2_crosstarget():
    ct = R.cross_target()
    order = [("gbm", "Learned model", BLUE), ("mechanistic", "Mechanistic grey-box", ORANGE), ("net_charge", "Net-charge heuristic", GRAY)]
    names, vals, los, his, cols, ps = [], [], [], [], [], []
    for key, lab, col in order:
        r = ct["results"][key]
        names.append(lab); vals.append(r["mean_per_class_common"])
        los.append(r["mean_per_class_common"] - r["ci95"][0]); his.append(r["ci95"][1] - r["mean_per_class_common"])
        cols.append(col); ps.append(r["perm_p"])
    fig, ax = plt.subplots(figsize=(7, 3.8))
    x = np.arange(len(names))
    ax.bar(x, vals, color=cols, width=0.6, zorder=3)
    ax.errorbar(x, vals, yerr=[los, his], fmt="none", ecolor=INK, elinewidth=1.3, capsize=5, zorder=4)
    ax.axhline(0, color=MUTED, lw=1)
    for xi, v, p in zip(x, vals, ps):
        ax.text(xi, v + (0.03 if v >= 0 else -0.06), f"{v:+.2f}\np={p}", ha="center", va="bottom" if v >= 0 else "top", fontsize=9, color=INK)
    ax.set_xticks(x); ax.set_xticklabels(names)
    ax.set_ylabel("mean within-held-out-target Spearman ρ")
    ax.set_title("Cross-target generalization (leave-one-target-out, 8 classes)", loc="left")
    ax.set_ylim(-0.5, 0.75)
    _despine(ax); ax.grid(axis="x", visible=False)
    fig.savefig(os.path.join(FIG, "F2_crosstarget.png")); plt.close(fig)


def fig3_design():
    _, rows = D.design_shortlist()
    rows = sorted(rows, key=lambda r: r["net_charge"])
    q = [r["net_charge"] for r in rows]; k = [r["pred_kidney_pid_g_4h"] for r in rows]
    fig, ax = plt.subplots(figsize=(6.4, 3.8))
    ax.plot(q, k, "-", color=GRAY, lw=1.6, zorder=2)
    ax.plot(q, k, "o", color=BLUE, ms=8, zorder=3)
    imin = int(np.argmin(k))
    ax.plot(q[imin], k[imin], "o", color=GREEN, ms=11, zorder=4)
    ax.annotate(f"min: net {q[imin]:+d}, {k[imin]:.1f} %ID/g", xy=(q[imin], k[imin]), xytext=(q[imin] + 0.4, k[imin] + 1.1),
                fontsize=9, color=GREEN, ha="left", arrowprops=dict(arrowstyle="-", color=GREEN, lw=0.8))
    ax.set_xlabel("engineered net charge (binder frozen)"); ax.set_ylabel("predicted kidney %ID/g @4h (¹⁷⁷Lu)")
    ax.set_title("Model-guided αvβ6 design: predicted renal U-shape", loc="left")
    _despine(ax)
    fig.savefig(os.path.join(FIG, "F3_design.png")); plt.close(fig)


def fig4_ablation():
    ab = R.ablations(); full = ab["full"]
    items = [(k.replace("drop_", "– ").replace("_", " "), full - v) for k, v in ab.items() if k != "full"]
    items.sort(key=lambda kv: -kv[1])
    labels = [k for k, _ in items]; deltas = [d for _, d in items]
    fig, ax = plt.subplots(figsize=(7, 3.6))
    y = np.arange(len(labels))
    ax.barh(y, deltas, color=BLUE, height=0.62, zorder=3)
    for yi, d in zip(y, deltas):
        ax.text(d + 0.005, yi, f"−{d:.2f}", va="center", ha="left", fontsize=9, color=INK)
    ax.set_yticks(y); ax.set_yticklabels(labels); ax.invert_yaxis()
    ax.set_xlabel("drop in cross-target ρ when feature removed"); ax.set_title(f"Feature ablations (full model ρ={full:.2f})", loc="left")
    _despine(ax); ax.grid(axis="y", visible=False)
    fig.savefig(os.path.join(FIG, "F4_ablation.png")); plt.close(fig)


if __name__ == "__main__":
    fig1_dataset(); print("F1_dataset.png")
    fig2_crosstarget(); print("F2_crosstarget.png")
    fig3_design(); print("F3_design.png")
    fig4_ablation(); print("F4_ablation.png")
    print(f"-> {FIG}")
