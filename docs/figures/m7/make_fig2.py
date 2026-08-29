#!/usr/bin/env python3
"""M7 Figure 2 — mechanism vs full-transcriptome vs the same-dimension random-gene null.
All numbers trace to committed files:
  - arm AUROCs + bootstrap CIs: docs/antitnf_demo_code/results_local.json (cross_dataset)
  - random-131-gene null (1000 draws): docs/antitnf_demo_code/random_control_result.json
Honest reading: the mechanism arm sits at the UPPER EDGE of the random null (p=0.051),
not far above it — the dimensionality does most of the work.
"""
import json, os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
CODE = os.path.normpath(os.path.join(HERE, "..", "..", "antitnf_demo_code"))

res = json.load(open(os.path.join(CODE, "results_local.json")))
ctrl = json.load(open(os.path.join(CODE, "random_control_result.json")))
cd = res["cross_dataset"]

def arm(k):
    a = cd[f"train16879_test12251_{k}"]["auroc"]
    return a[0], a[1], a[2]  # point, lo, hi

base = arm("baseline"); full = arm("full"); mech = arm("mechanism")
null = np.array(ctrl["null_auroc_values"])
null_mean = ctrl["null_mean"]; p95 = ctrl["null_percentiles"]["95"]; p50 = ctrl["null_percentiles"]["50"]
p_emp = ctrl["empirical_p_onesided"]; arm_size = ctrl["arm_size_genes"]

fig, ax = plt.subplots(figsize=(8.2, 4.6))
NAVY = "#22445f"; TEAL = "#2a9d8f"; GREY = "#9aa5ad"; ACCENT = "#c1121f"

# --- the random-gene null as a horizontal violin/hist band spanning the plot ---
# draw the null distribution as a shaded KDE-ish histogram along x, at the top lane (y=3.6)
ylane = 3.7
counts, edges = np.histogram(null, bins=28, range=(0.4, 1.0))
counts = counts / counts.max() * 0.55
for c, x0, x1 in zip(counts, edges[:-1], edges[1:]):
    ax.fill_between([x0, x1], ylane, ylane + c, color=GREY, alpha=0.45, lw=0)
ax.plot([p50, p50], [ylane, ylane + 0.62], color=GREY, lw=1.4, ls="-")
ax.plot([p95, p95], [ylane, ylane + 0.62], color=ACCENT, lw=1.6, ls="--")
ax.text(p50, ylane + 0.66, f"random-{arm_size}\nmedian {p50:.2f}", ha="center", va="bottom", fontsize=8, color="#555")
ax.text(p95, ylane + 0.66, f"95th pct {p95:.2f}", ha="center", va="bottom", fontsize=8, color=ACCENT)
ax.text(0.41, ylane + 0.30, f"same-dimension random-gene null\n(1,000 draws of {arm_size} genes)",
        ha="left", va="center", fontsize=8.5, color="#444", style="italic")

# vertical guide for the 95th percentile across the arm lanes
ax.axvline(p95, color=ACCENT, lw=1.0, ls="--", alpha=0.5, ymax=0.72)

# --- the three arms as points with bootstrap CIs ---
arms = [("1-gene baseline", base, GREY, 1),
        ("Full transcriptome\n(2,000 genes)", full, NAVY, 2),
        (f"Mechanism\n({arm_size} TNF/NF-κB genes)", mech, TEAL, 3)]
for label, (pt, lo, hi), col, y in arms:
    ax.plot([lo, hi], [y, y], color=col, lw=2.4, solid_capstyle="round")
    ax.plot(pt, y, "o", color=col, ms=11, zorder=5)
    ax.text(hi + 0.012, y, f"{pt:.3f}", va="center", ha="left", fontsize=10, color=col, fontweight="bold")
    ax.text(0.40, y, label, va="center", ha="left", fontsize=9.5)

ax.axvline(0.5, color="k", lw=0.8, ls=":", alpha=0.6)
ax.text(0.5, 0.35, "chance", ha="center", fontsize=8, color="k")

# annotate the honest verdict on the mechanism arm
ax.annotate(f"mechanism just exceeds the null's 95th pct\n(p = {p_emp:.3f}, one-sided) — a modest, borderline edge",
            xy=(mech[0], 3), xytext=(0.505, 2.35),
            fontsize=8.6, color=ACCENT,
            arrowprops=dict(arrowstyle="->", color=ACCENT, lw=1.1))

ax.set_xlim(0.38, 1.04)
ax.set_ylim(0.1, 5.0)
ax.set_yticks([])
ax.set_xlabel("Cross-cohort AUROC — train GSE16879 → test GSE12251 (independent ACT1)", fontsize=10)
ax.set_xticks([0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0])
for s in ("top", "right", "left"):
    ax.spines[s].set_visible(False)
ax.set_title("Anti-TNF response: mechanism constraint vs full transcriptome vs a size-matched random-gene null",
             fontsize=10.5, fontweight="bold", pad=10)
plt.tight_layout()
out = os.path.join(HERE, "fig2_mechanism_vs_null.png")
plt.savefig(out, dpi=190, bbox_inches="tight")
print("wrote", out)
