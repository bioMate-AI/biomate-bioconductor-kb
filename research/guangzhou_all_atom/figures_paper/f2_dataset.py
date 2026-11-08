"""F2 — dataset structure of the CycPeptMPDB PAMPA set used by the loop.
(a) flat-structure group sizes (6,960 peptides -> 2,460 flat structures)
(b) within-group label spread for groups of >=2 stereoisomers (raw log Papp, max-min)
(c) source concentration of hits after within-source standardisation vs. share of peptides.
Artifacts: stratification annotations (committed), L5 label audit (committed).
"""
import json

import numpy as np
import pandas as pd

from common import C, check, plt, savefig, sources_of, src

ANN = "research/guangzhou_all_atom/cyclic_llm/stratification/data/annotations.csv.gz"
AUD = "research/guangzhou_all_atom/cyclic_llm/loop_retro/results/l5_label_audit.json"

a = pd.read_csv(src(ANN))
b = a[a["y_loader"].notna()].copy()            # the 6,960-peptide loader set
audit = json.load(open(src(AUD)))

grp = b.groupby("flat_smiles")["y_loader"]
size = grp.size()
n_pep, n_flat = len(b), len(size)
multi = size[size > 1]
n_in_groups = int(multi.sum())
spread = (grp.max() - grp.min())[multi.index]

check("n peptides (loader set) == l5_label_audit.n", n_pep, audit["n"])
check("n flat structures", n_flat, 2460)                       # value stated in docs/20261029_BASELINE_ERROR_ANALYSIS.md
check("peptides in stereoisomer groups (>=2)", n_in_groups, 4912)
check("max group size", int(size.max()), 116)

fig, axs = plt.subplots(1, 3, figsize=(10.2, 3.0), gridspec_kw=dict(width_ratios=[1.0, 1.0, 1.1], wspace=0.42))

# (a) group-size distribution
bins = [(1, 1), (2, 2), (3, 3), (4, 4), (5, 8), (9, 16), (17, 32), (33, 200)]
labels = ["1", "2", "3", "4", "5–8", "9–16", "17–32", "33+"]
counts = [int(((size >= lo) & (size <= hi)).sum()) for lo, hi in bins]
check("sum of group counts == n flat structures", sum(counts), n_flat)
ax = axs[0]
ax.bar(range(len(bins)), counts, color=C["blue"], width=0.75)
ax.set_yscale("log")
ax.set_xticks(range(len(bins)), labels, rotation=35, ha="right")
ax.set_xlabel("peptides per flat structure")
ax.set_ylabel("number of flat structures")
for i, c in enumerate(counts):
    ax.text(i, c * 1.15, str(c), ha="center", fontsize=6)
ax.set_title("(a) Stereoisomer-group sizes", loc="left")
ax.set_ylim(top=9000)
ax.text(0.98, 0.97, f"{n_pep:,} peptides,\n{n_flat:,} flat structures;\n{n_in_groups:,} peptides ({100*n_in_groups/n_pep:.0f}%)\nin groups of ≥2",
        transform=ax.transAxes, ha="right", va="top", fontsize=6.5)

# (b) within-group spread
ax = axs[1]
ax.hist(spread.values, bins=np.arange(0, spread.max() + 0.25, 0.25), color=C["orange"], edgecolor="white", linewidth=0.4)
med = float(np.median(spread.values))
ax.axvline(med, color=C["black"], ls="--", lw=0.9)
ax.text(med + 0.05, ax.get_ylim()[1] * 0.92, f"median {med:.3f}", fontsize=6.5)
ax.set_xlabel("label range within group (log Papp)")
ax.set_ylabel("groups with ≥2 peptides")
ax.set_title(f"(b) Within-group label range", loc="left")
check("number of multi-member groups", len(spread), int(len(multi)))
check("median within-group range vs 0.86 stated in docs/20261029_BASELINE_ERROR_ANALYSIS.md (tol 0.006)", float(med), 0.86, tol=0.006)

# (c) source concentration of hits vs peptides
ax = axs[2]
top = audit["top_groups_hits"]
n_hits = audit["n_hits"]
peps = b["Source"].value_counts()
names = [t[0] for t in top]
hit_share = [t[1] / n_hits for t in top]
pep_share = [peps.get(nm, 0) / n_pep for nm in names]
other_hits = 1 - sum(hit_share)
other_peps = 1 - sum(pep_share)
check("top source hit share == audit.max_group_share", round(hit_share[0], 3), audit["max_group_share"])
y = np.arange(len(names) + 1)[::-1]
w = 0.38
ax.barh(y - w / 2, hit_share + [other_hits], height=w, color=C["vermilion"], label=f"share of hits (n = {n_hits})")
ax.barh(y + w / 2, pep_share + [other_peps], height=w, color=C["sky"], label=f"share of peptides (n = {n_pep:,})")
ax.set_yticks(y, [nm.replace("20", "20", 1) for nm in names] + ["other sources"], fontsize=6.5)
ax.set_xlabel("fraction"); ax.set_xlim(0, 0.75)
ax.legend(frameon=False, loc="lower right", fontsize=6)
ax.set_title("(c) Hits vs peptides by source", loc="left")

caption = (f"F2. Dataset structure. (a) Number of flat structures by stereoisomer-group size ({n_pep:,} peptides, {n_flat:,} flat structures; "
           f"{n_in_groups:,} peptides in groups of ≥2). (b) Within-group range of raw log Papp for the {len(spread)} groups with ≥2 peptides (median {med:.3f}). "
           f"(c) Share of top-decile hits (within-source standardised labels; threshold {audit['threshold']}) vs share of peptides by source. "
           "No intervals: descriptive counts of the full dataset.")
savefig(fig, "F2_dataset_structure", "F2 dataset structure", caption, sources_of(ANN, AUD))
