"""F-CV — overall skill under three evaluation schemes: random 5-fold, CV grouped by flat structure, leave-labs-out (grouped by source).
Spearman of out-of-fold predictions vs within-source labels, source-cluster bootstrap 95% CI (B=2000, seed 0).
Artifact: stratification/data/cv_preds.csv.gz (out-of-fold predictions) + annotations (Source per peptide). Cross-checked against the
numbers stated in docs/20261029_CYCLIC_PEPTIDE_STRATIFICATION_ANALYSIS.md (Part B).
"""
import re

import numpy as np
import pandas as pd
from scipy.stats import spearmanr

from common import C, check, plt, savefig, sources_of, src

PRED = "research/guangzhou_all_atom/cyclic_llm/stratification/data/cv_preds.csv.gz"
ANN = "research/guangzhou_all_atom/cyclic_llm/stratification/data/annotations.csv.gz"
DOC = "docs/20261029_CYCLIC_PEPTIDE_STRATIFICATION_ANALYSIS.md"
p = pd.read_csv(src(PRED))
a = pd.read_csv(src(ANN))[["Structurally_Unique_ID", "Source"]].rename(columns={"Structurally_Unique_ID": "sid"})
p = p.merge(a, on="sid", how="left")
assert p.Source.notna().all()
rng = np.random.default_rng(0)
src_groups = {s: g.index.values for s, g in p.groupby("Source")}
snames = list(src_groups)
B = 2000
boot_idx = [np.concatenate([src_groups[snames[i]] for i in rng.integers(0, len(snames), len(snames))]) for _ in range(B)]

models = [("fp_blind", "fingerprint GBM (chirality-blind)", C["blue"]), ("fp_chiral", "fingerprint GBM (chirality-aware)", C["sky"]), ("desc", "descriptor GBM", C["orange"])]
schemes = [("random", "random 5-fold"), ("grp_flat", "grouped by flat structure"), ("grp_source", "leave-labs-out (grouped by source)")]
res = {}
for m, _, _ in models:
    for sc, _ in schemes:
        col = f"{m}__{sc}"
        pt = spearmanr(p[col], p["y"])[0]
        bs = np.array([spearmanr(p[col].values[ix], p["y"].values[ix])[0] for ix in boot_idx])
        res[(m, sc)] = (pt, *np.percentile(bs, [2.5, 97.5]))

fig, ax = plt.subplots(figsize=(6.6, 3.3))
w = 0.26
for i, (m, ml, col) in enumerate(models):
    xs = np.arange(len(schemes)) + (i - 1) * w
    pt = [res[(m, sc)][0] for sc, _ in schemes]
    lo = [res[(m, sc)][0] - res[(m, sc)][1] for sc, _ in schemes]
    hi = [res[(m, sc)][2] - res[(m, sc)][0] for sc, _ in schemes]
    ax.bar(xs, pt, width=w * 0.92, color=col, label=ml, yerr=[lo, hi], capsize=1.8, error_kw=dict(lw=0.8))
    for x, v, h in zip(xs, pt, hi):
        ax.text(x, v + h + 0.012, f"{v:.2f}", ha="center", fontsize=6)
ax.set_xticks(range(len(schemes)), [s[1] for s in schemes])
ax.set_ylabel("Spearman (out-of-fold, within-source labels)")
ax.set_ylim(0, 0.95)
ax.set_title(f"Skill under three evaluation schemes (n = {len(p):,} peptides, {len(snames)} sources)", loc="left")
ax.legend(frameon=False, fontsize=6.4, loc="upper right")
fig.tight_layout()

# cross-check with the numbers stated in the committed analysis document
doc = open(src(DOC)).read()
m = re.search(r"leave-labs-out \(grouped by source\)\s*\*{0,2}\s*([0-9.]+) / ([0-9.]+) / ([0-9.]+)", doc)
if m:
    for (mm, _, _), v in zip(models, m.groups()):
        check(f"leave-labs-out {mm} vs doc ({v})", round(res[(mm, 'grp_source')][0], 2), float(v), tol=0.011)
else:
    raise AssertionError("could not find the leave-labs-out line in the analysis document")
caption = ("F-CV. Overall Spearman of three baselines under random 5-fold CV, CV grouped by flat structure (no stereoisomer sibling in training) and leave-labs-out (grouped by source), "
           "within-source standardised labels. Intervals: source-cluster bootstrap (B = 2000, seed 0). Skill drops from ~0.7 to ~0.3 when labs are held out. "
           "Out-of-fold predictions from the committed artifact; the bootstrap is computed here.")
savefig(fig, "FCV_evaluation_schemes", "evaluation schemes", caption, sources_of(PRED, ANN, DOC))
