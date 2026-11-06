"""F11 (partial) — knowledge coverage of the benchmark. Left: fraction of the 46 analysis-I targets on which each score is non-constant
(a rule that is constant on a target cannot rank its compounds). Right: knowledge-base-mapped targets with n positives and eligibility.
The knowledge-base x property x substructure-level matrix has no machine-readable artifact and is NOT drawn (listed as pending).
Artifacts: retro_recovery/results/results_V2_I.json (coverage), kb_audit/kb_target_coverage.csv.
"""
import json

import pandas as pd

from common import C, check, check_many, plt, reread, savefig, sources_of, src

R = "research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery/results/results_V2_I.json"
K = "research/guangzhou_all_atom/cyclic_llm/kb_audit/kb_target_coverage.csv"
cov = json.load(open(src(R)))["coverage"]
arms = [("S1a_rules", "rules (RGD etc.)"), ("S1b_KB", "knowledge-base gate"), ("B1_rgd", "RGD baseline"), ("S1b_induction", "induced rules (10 predicates)"),
        ("S1c_induction", "induced rules (31 predicates)"), ("B4_depth_neg", "annotation-depth null")]
fig, (ax, ax2) = plt.subplots(1, 2, figsize=(9.6, 3.4), gridspec_kw=dict(width_ratios=[1.1, 1]))
pairs = []
for i, (a, lab) in enumerate(arms):
    v = cov[a]["targets_nonconstant"]; t = cov[a]["targets_total"]
    bar = ax.barh(len(arms) - 1 - i, v, color=C["green"] if v == t else C["vermilion"], height=0.65)
    ax.text(v + 0.8, len(arms) - 1 - i, f"{v}/{t}", va="center", fontsize=6.5)
    pairs.append((bar.patches[0].get_width(), reread(R, "coverage", a, "targets_nonconstant")))
ax.set_yticks(range(len(arms)), [a[1] for a in reversed(arms)], fontsize=6.6)
ax.set_xlim(0, 52); ax.set_xlabel("analysis-I targets on which the score is non-constant (of 46)")
ax.set_title("(a) Score coverage", loc="left")
check_many("F11 coverage bars", pairs)

k = pd.read_csv(src(K))
k = k.sort_values("n_pos", ascending=True).reset_index(drop=True)
cols = [C["blue"] if (r.eligible_M and r.eligible_I) else (C["orange"] if r.eligible_M else C["grey"]) for r in k.itertuples()]
bars = ax2.barh(range(len(k)), k.n_pos, color=cols, height=0.65)
ax2.set_yticks(range(len(k)), [f"{kb} ({g})" for kb, g in zip(k.kb, k.genes)], fontsize=5.8)
for i, v in enumerate(k.n_pos):
    ax2.text(v + 0.8, i, str(int(v)), va="center", fontsize=6)
ax2.set_xlabel("positives (≤ 1 µM) per KB-mapped target key")
ax2.set_title("(b) Knowledge-base-mapped targets", loc="left")
from matplotlib.patches import Patch
ax2.legend(handles=[Patch(color=C["blue"], label="eligible in I and M"), Patch(color=C["orange"], label="eligible in M only"), Patch(color=C["grey"], label="not eligible")],
           frameon=False, fontsize=6, loc="lower right")
check_many("F11 KB-target positives", [(b.get_width(), v) for b, v in zip(bars.patches, k.n_pos)])
fig.tight_layout()
caption = ("F11 (partial). (a) Number of the 46 analysis-I targets on which each benchmark score takes more than one value (a constant score cannot rank compounds): "
           "the knowledge-base gate is non-constant on 0 of 46 targets and the rule score on 3. (b) Targets mapped to the knowledge base (strict identifier mapping), n positives and eligibility "
           "(≥5 positives and enough decoys). The knowledge × property × substructure-level matrix is pending (no machine-readable artifact; see docs/20261029_KB_AUDIT_AND_GAPS.md).")
savefig(fig, "F11_coverage_partial", "F11 coverage (partial)", caption, sources_of(R, K))
