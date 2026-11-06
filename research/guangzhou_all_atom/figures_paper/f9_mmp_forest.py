"""F9 — matched-molecular-pair effects within source (directed, interpretable transformations), four assays on one forest.
Pooled effect with the random-effects meta-analytic 95% interval across sources; n pairs printed beside each marker.
Artifact: stratification/data/mmp_effects_{pampa,caco2,rrck,mdck}.csv.
"""
import pandas as pd

from common import C, check_many, plt, savefig, sources_of, src

BASE = "research/guangzhou_all_atom/cyclic_llm/stratification/data/mmp_effects_{}.csv"
assays = [("pampa", "PAMPA", C["blue"], -0.27), ("caco2", "Caco-2", C["orange"], -0.09), ("rrck", "RRCK", C["green"], 0.09), ("mdck", "MDCK", C["vermilion"], 0.27)]
data = {}
rels = []
for key, *_ in assays:
    rel = BASE.format(key); rels.append(rel)
    d = pd.read_csv(src(rel))
    data[key] = d[d.directed & d.interpretable & d.meta_lo.notna()].set_index("transformation")
trans = sorted({t for d in data.values() for t in d.index}, key=lambda t: (data["pampa"].pooled.get(t, float("nan")) if t in data["pampa"].index else 9e9, t))
# order: PAMPA effect (ascending) first, transformations only seen in other assays last
fig, ax = plt.subplots(figsize=(8.6, 4.4))
checks = []
for key, name, col, off in assays:
    d = data[key]
    first = True
    for i, t in enumerate(trans):
        if t not in d.index:
            continue
        r = d.loc[t]
        y = len(trans) - 1 - i + off
        cont = ax.errorbar(r.pooled, y, xerr=[[r.pooled - r.meta_lo], [r.meta_hi - r.pooled]], fmt="o", ms=3.0, color=col, capsize=1.3, lw=0.8,
                           label=name if first else None)
        first = False
        seg = cont.lines[2][0].get_segments()[0]
        checks += [(cont.lines[0].get_xdata()[0], r.pooled), (seg[0][0], r.meta_lo), (seg[1][0], r.meta_hi)]
        ax.text(max(r.meta_hi, r.pooled) + 0.04, y, f"n={int(r.n_pairs):,}/{int(r.n_sources)}", va="center", fontsize=4.8, color=col)
ax.axvline(0, color=C["black"], lw=0.7, ls="--")
ax.set_yticks(range(len(trans)), list(reversed(trans)), fontsize=6)
ax.set_xlabel("pooled difference in within-source standardised permeability (random-effects 95% CI across sources)", fontsize=7)
ax.set_title("F9. Within-source matched-pair effects of directed transformations (n = pairs / sources)", loc="left")
ax.legend(frameon=False, fontsize=6.5, loc="lower right")
check_many("F9 MMP points and intervals", checks)
fig.tight_layout()
caption = ("F9. Matched-molecular-pair effects within source for four permeability assays (directed, interpretable transformations with a finite interval; artifact flags). "
           "Points: pooled mean difference (second minus first named state) in within-source standardised permeability; bars: random-effects 95% intervals across sources; "
           "n = pairs / sources. N-methyl addition is positive in PAMPA and Caco-2; D↔L flips have no consistent direction (PAMPA pooled −0.013 [−0.049, 0.023], SD of pair differences 0.52). "
           "Magnitude-only (undirected) rows and rows with a single source are in the CSVs.")
savefig(fig, "F9_mmp_forest", "F9 MMP effects", caption, sources_of(*rels))
