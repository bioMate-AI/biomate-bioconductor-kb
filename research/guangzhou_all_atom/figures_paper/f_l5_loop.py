"""F-L5 — controlled retrospective loop (L5; 810/810 tasks; 30 seeds per arm and regime).
(a) loop minus random and loop minus zero-learning rule (K_z, K_nme), 95% seed-bootstrap CI;
(b) knowledge arms minus fingerprint-only loop, 99% CI;
(c) where the loop's 500 picks come from (mean picks by source) vs population share.
Regimes: A in-distribution, B scaffold-shifted, C identical-structure-excluded in-distribution (analogues retained).
Artifacts: loop_retro/results/l5_aggregate.json, stratification annotations (population shares).
"""
import json

import pandas as pd

from common import C, check, plt, reread, savefig, sources_of, src

L5 = "research/guangzhou_all_atom/cyclic_llm/loop_retro/results/l5_aggregate.json"
ANN = "research/guangzhou_all_atom/cyclic_llm/stratification/data/annotations.csv.gz"
d = json.load(open(src(L5)))
regs = [("A", "A in-distribution"), ("B", "B scaffold-shifted"), ("C", "C identical-structure-excluded")]

fig = plt.figure(figsize=(10.4, 6.2))
gs = fig.add_gridspec(2, 2, height_ratios=[1, 1], wspace=0.32, hspace=0.5)

def forest(ax, rows, title, xlabel):
    """rows: list of (label, key_path_in_json, colour, mean_key, ci_key). Draw horizontal forest with checks."""
    for i, (lab, keys, col, mk, ck) in enumerate(rows):
        y = len(rows) - 1 - i
        node = d
        for k in keys:
            node = node[k]
        m, (lo, hi) = node[mk], node[ck]
        cont = ax.errorbar(m, y, xerr=[[m - lo], [hi - m]], fmt="o", color=col, ms=4, capsize=2, lw=1.0)
        seg = cont.lines[2][0].get_segments()[0]
        check(f"L5 {lab} mean", float(cont.lines[0].get_xdata()[0]), float(reread(L5, *keys, mk)))
        check(f"L5 {lab} lo", float(seg[0][0]), float(reread(L5, *keys, ck)[0]))
        check(f"L5 {lab} hi", float(seg[1][0]), float(reread(L5, *keys, ck)[1]))
        ax.text(hi + 3, y, f"{m:+.1f}", va="center", fontsize=6)
    ax.set_yticks(range(len(rows)), [r[0] for r in reversed(rows)], fontsize=6.4)
    ax.axvline(0, color=C["black"], lw=0.8, ls="--")
    ax.set_xlabel(xlabel); ax.set_title(title, loc="left")

# (a)
ax = fig.add_subplot(gs[0, 0])
rows = []
for r, rl in regs:
    rows += [(f"{rl}: loop − random", (f"fp_minus_random_{r}",), C["blue"], "mean", "ci95"),
             (f"{rl}: loop − rule K_z", (f"fp_minus_rule_z_{r}",), C["green"], "mean", "ci95"),
             (f"{rl}: loop − rule K_nme", (f"fp_minus_rule_nme_{r}",), C["purple"], "mean", "ci95")]
forest(ax, rows, "(a) Loop vs random and vs zero-learning rules", "difference in hits among 500 picks (post hoc 95% CI of the mean, 30 seeds; transductive standardisation: upper bound)")

# (b)
ax = fig.add_subplot(gs[0, 1])
rows = []
armname = {"kn": "descriptor arm", "resid_nme": "residual N-Me", "resid_z": "residual K_z", "fuse_nme": "fusion N-Me", "fuse_z": "fusion K_z"}
cols = {"A": C["blue"], "B": C["orange"], "C": C["sky"]}
for r, rl in regs:
    for a in armname:
        rows.append((f"{r}: {armname[a]}", (f"{a}_{r}", "d_total"), cols[r], "mean", "ci"))
forest(ax, rows, "(b) Knowledge arms vs fingerprint-only loop", "difference in hits (99% CI)")
ax.tick_params(axis="y", labelsize=5.6)

# (c) pick provenance
pop = pd.read_csv(src(ANN))
pop = pop[pop["y_loader"].notna()]
n = len(pop)
share = {"townsend": (pop.Source == "2020_Townsend").sum() / n, "kelly": (pop.Source == "2021_Kelly").sum() / n}
share["other"] = 1 - share["townsend"] - share["kelly"]
ax = fig.add_subplot(gs[1, :])
bars = [("population share", share)] + [(f"loop picks, regime {r}", {k: v / 500 for k, v in d["PICK_SOURCE_MEANS"][f"fp_{r}"].items()}) for r, _ in regs] + \
       [(f"random picks, regime {r}", {k: v / 500 for k, v in d["PICK_SOURCE_MEANS"][f"random_{r}"].items()}) for r, _ in regs]
colsrc = {"townsend": C["vermilion"], "kelly": C["orange"], "other": C["sky"]}
for i, (lab, sh) in enumerate(bars):
    left = 0
    for s in ("townsend", "kelly", "other"):
        ax.barh(len(bars) - 1 - i, sh[s], left=left, color=colsrc[s], edgecolor="white", linewidth=0.4, label={"townsend": "2020_Townsend", "kelly": "2021_Kelly", "other": "all other sources"}[s] if i == 0 else None)
        if sh[s] > 0.05:
            ax.text(left + sh[s] / 2, len(bars) - 1 - i, f"{100*sh[s]:.0f}%", ha="center", va="center", fontsize=6, color="white" if s != "other" else "black")
        left += sh[s]
    if lab.startswith("loop picks") or lab.startswith("random picks"):
        r = lab[-1]
        key = ("fp_" if lab.startswith("loop") else "random_") + r
        check(f"L5 pick mean {key} townsend", float(sh["townsend"] * 500), float(reread(L5, "PICK_SOURCE_MEANS", key, "townsend")), tol=1e-6)
ax.set_yticks(range(len(bars)), [b[0] for b in reversed(bars)], fontsize=6.6)
ax.set_xlabel("share of the 500 selections (mean over 30 seeds) / share of peptides"); ax.set_xlim(0, 1)
ax.set_title("(c) Where the picks come from (hit labels standardised within source using all labels of the source)", loc="left")
ax.legend(frameon=False, ncol=3, fontsize=6.4, loc="upper center", bbox_to_anchor=(0.5, -0.18))
check("population share Townsend (loader set)", round(float(share["townsend"]), 3), round(2881 / 6960, 3))
caption = ("F-L5. Controlled retrospective loop (L5, pre-registered; 810/810 tasks). (a) Loop minus random and minus zero-learning physchem rules (K_z, K_nme; ties broken at random with the task seed), "
           "95% percentile CI over 30 paired seeds. (b) Knowledge-prior/fusion arms minus the fingerprint-only loop, 99% CI; every interval includes 0. "
           "(c) Mean source composition of the 500 selections vs. source shares of the 6,960 peptides; in regime A the loop over-draws from one laboratory. In regimes B and C the candidate pool is restricted, so compare each loop bar with the random-pick bar of the same regime, not with the population share. "
           "Pre-registered claim C1 (loop beats random in A and B) is NOT met: B's interval includes 0 "
           f"(B: {d['fp_minus_random_B']['mean']:+.1f} [{d['fp_minus_random_B']['ci95'][0]:+.1f}, {d['fp_minus_random_B']['ci95'][1]:+.1f}]).")
savefig(fig, "FL5_loop_results", "L5 loop results", caption, sources_of(L5, ANN))
