"""F8 — stratified baseline performance (CycPeptMPDB, within-source labels). Heatmaps of Spearman by stratum x baseline for
(left) CV grouped by flat structure (no stereoisomer sibling in training) and (right) leave-labs-out (grouped by source).
Cells for strata flagged `small` in the artifact are hatched; cells whose CI includes 0 (`near_zero`) are marked with a dot.
Artifact: stratification/data/strata_perf.csv (and annotations for n per level in the row labels).
"""
import numpy as np
import pandas as pd

from common import C, check_many, plt, savefig, sources_of, src

SP = "research/guangzhou_all_atom/cyclic_llm/stratification/data/strata_perf.csv"
d = pd.read_csv(src(SP))
models = ["fp_blind", "fp_chiral", "desc", "nme_rule"]
mlabel = {"fp_blind": "fingerprint GBM\n(chirality-blind)", "fp_chiral": "fingerprint GBM\n(chirality-aware)", "desc": "descriptor GBM", "nme_rule": "N-methyl rule"}
keep = ["topology", "length", "n_methyl", "n_D", "peptoid", "unknown_monomer", "source_size"]
rows = d[d.scheme == "grp_flat"].drop_duplicates(["stratifier", "level"])
rows = rows[rows.stratifier.isin(keep)][["stratifier", "level", "n"]].reset_index(drop=True)
rows["order"] = rows.stratifier.map({k: i for i, k in enumerate(keep)})
rows = rows.sort_values("order", kind="stable").reset_index(drop=True)

fig, axs = plt.subplots(1, 2, figsize=(9.4, 8.2), sharey=True, gridspec_kw=dict(wspace=0.05))
checks = []
for ax, scheme, title in ((axs[0], "grp_flat", "CV grouped by flat structure"), (axs[1], "grp_source", "Leave-labs-out (grouped by source)")):
    mods = models if scheme == "grp_flat" else models[:3]      # the label-free rule has no fitted/grouped variant in the artifact
    M = np.full((len(rows), len(mods)), np.nan)
    small = np.zeros_like(M, dtype=bool)
    near0 = np.zeros_like(M, dtype=bool)
    for i, r in rows.iterrows():
        for j, m in enumerate(mods):
            q = d[(d.scheme == scheme) & (d.stratifier == r.stratifier) & (d.level == r.level) & (d.model == m)]
            if len(q) == 1:
                M[i, j] = q.spearman.iloc[0]; small[i, j] = bool(q.small.iloc[0]); near0[i, j] = bool(q.near_zero.iloc[0])
    im = ax.imshow(M, cmap="cividis", vmin=-0.3, vmax=0.8, aspect="auto")
    for i in range(M.shape[0]):
        for j in range(M.shape[1]):
            if np.isnan(M[i, j]):
                continue
            col = "white" if M[i, j] < 0.35 else "black"
            ax.text(j, i, f"{M[i, j]:.2f}" + ("·" if near0[i, j] else ""), ha="center", va="center", fontsize=6, color=col)
            if small[i, j]:
                ax.add_patch(plt.Rectangle((j - .5, i - .5), 1, 1, fill=False, hatch="////", edgecolor="white", lw=0))
    ax.set_xticks(range(len(mods)), [mlabel[m] for m in mods], fontsize=6, rotation=0)
    ax.set_title(title, loc="left", fontsize=8)
    # checks vs a fresh read of the CSV
    fresh = pd.read_csv(src(SP))
    for i, r in rows.iterrows():
        for j, m in enumerate(mods):
            q = fresh[(fresh.scheme == scheme) & (fresh.stratifier == r.stratifier) & (fresh.level == r.level) & (fresh.model == m)]
            if len(q) == 1:
                checks.append((M[i, j], q.spearman.iloc[0]))
axs[0].set_yticks(range(len(rows)), [f"{r.stratifier}: {r.level}  (n={r.n})" for r in rows.itertuples()], fontsize=6)
cb = fig.colorbar(im, ax=axs, fraction=0.025, pad=0.02)
cb.set_label("Spearman (within-source labels)")
check_many("F8 heatmap cells", checks)
caption = ("F8. Stratified Spearman of four baselines on CycPeptMPDB PAMPA (6,960 peptides; within-source standardised labels). Left: 5-fold CV grouped by flat structure; right: grouped by source "
           "(leave-labs-out). Rows: strata with n peptides; hatched cells: strata flagged small in the artifact; '·': 95% cluster-bootstrap CI includes 0. "
           "The label-free N-methyl rule is shown only in the left panel (it has no fitted variant). Intervals for every cell are in strata_perf.csv; strata dominated by one laboratory (e.g. lariat_sc_cterm: 99.8% 2021_Kelly) reflect that laboratory.")
savefig(fig, "F8_strata_heatmap", "F8 stratified performance", caption, sources_of(SP))
