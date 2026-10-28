"""F-K — knowledge channel validity: leave-one-lab-out Spearman of the zero-fit knowledge channels per held-out laboratory.
K_phys (TPSA/HBD/logP/Veber rules mined from training labs only), K_nme (N-methyl count), K_total. Medians and lab-bootstrap CIs from lolo_summary.json;
pooled held-out Spearman from lolo_pooled.json; shuffled-label negative control from the summary. Artifacts: kb_audit/lolo_*.
"""
import json

import numpy as np
import pandas as pd

from common import C, check, check_many, plt, reread, savefig, sources_of, src

B = "research/guangzhou_all_atom/cyclic_llm/kb_audit/"
per = pd.read_csv(src(B + "lolo_per_lab.csv"))
summ = json.load(open(src(B + "lolo_summary.json")))
pooled = json.load(open(src(B + "lolo_pooled.json")))
per = per.sort_values("K_phys").reset_index(drop=True)
fig, (ax, ax2) = plt.subplots(1, 2, figsize=(9.6, 4.8), gridspec_kw=dict(width_ratios=[2.2, 1]))
cols = {"K_phys": C["blue"], "K_nme": C["purple"], "K_total": C["green"]}
checks = []
for ch, mk in (("K_phys", "o"), ("K_nme", "s"), ("K_total", "^")):
    sc = ax.scatter(per[ch], range(len(per)), s=np.sqrt(per.n) * 2.2, marker=mk, color=cols[ch], alpha=0.85, label=ch, edgecolor="white", linewidth=0.3)
    offs = np.ma.getdata(sc.get_offsets()[:, 0])
    fin = per[ch].notna().values                      # a lab without a defined K_nme correlation is not drawn
    checks += [(x, v) for x, v, f in zip(offs, per[ch].values, fin) if f]
for ch in ("K_phys", "K_nme", "K_total"):
    h = summ["heldout"][ch]
    ax.axvline(h["median"], color=cols[ch], lw=0.8, ls=":")
ax.axvline(0, color=C["black"], lw=0.8, ls="--")
ax.set_yticks(range(len(per)), [f"{l}  (n={n})" for l, n in zip(per.lab, per.n)], fontsize=5.8)
ax.set_xlabel("Spearman within held-out laboratory (rules mined from the other labs only)")
ax.set_title("Per held-out laboratory (marker area ~ sqrt n)", loc="left")
ax.legend(frameon=False, fontsize=6.5, loc="lower right")
check_many("F-K per-lab markers", checks)

# right: medians with lab-bootstrap CI + pooled values
for i, ch in enumerate(("K_phys", "K_nme", "K_total")):
    h = summ["heldout"][ch]
    cont = ax2.errorbar(h["median"], 2 - i, xerr=[[h["median"] - h["ci95"][0]], [h["ci95"][1] - h["median"]]], fmt="o", color=cols[ch], capsize=2, ms=4)
    seg = cont.lines[2][0].get_segments()[0]
    check(f"{ch} median", float(cont.lines[0].get_xdata()[0]), float(reread(B + "lolo_summary.json", "heldout", ch, "median")))
    check(f"{ch} ci lo", float(seg[0][0]), float(reread(B + "lolo_summary.json", "heldout", ch, "ci95")[0]))
    check(f"{ch} ci hi", float(seg[1][0]), float(reread(B + "lolo_summary.json", "heldout", ch, "ci95")[1]))
    ax2.text(h["ci95"][1] + 0.02, 2 - i, f"{h['n_pos']}/{h['n_labs']} labs > 0", va="center", fontsize=6)
    ax2.plot(pooled["pooled_heldout_spearman"][ch], 2 - i - 0.28, marker="|", color=cols[ch], ms=7)
neg = summ["shuffled_negative_control_median_of_lab_medians"]["K_phys"]
ax2.axvspan(neg["min"], neg["max"], color=C["grey"], alpha=0.25, label="shuffled-label control (range)")
ax2.axvline(0, color=C["black"], lw=0.8, ls="--")
ax2.set_yticks([2, 1, 0], ["K_phys", "K_nme", "K_total"])
ax2.set_xlabel("median per-lab Spearman, 95% CI\n('|' marks the pooled value)", fontsize=7)
ax2.set_xlim(-0.25, 0.8)
ax2.legend(frameon=False, fontsize=6, loc="lower right")
ax2.set_title("Medians and pooled values", loc="left")
fig.tight_layout(w_pad=2.0)
caption = (f"F-K. Leave-one-lab-out validity of the zero-fit knowledge channels (21 laboratories; n peptides per lab in the labels). Left: Spearman between each channel and "
           "within-source standardised permeability in the held-out lab, with rules mined from the other labs only. Right: median per-lab Spearman with 95% lab-bootstrap CI "
           "and the number of labs with positive value; ticks mark the pooled held-out Spearman (dominated by the two largest labs, 65% of peptides); grey band: shuffled-label negative control. "
           "TPSA alone in the knowledge-base direction scores 0.41 pooled, so mining adds nothing over the textbook rule (workstream-5 report).")
savefig(fig, "FK_knowledge_channel_lolo", "knowledge channel leave-lab-out", caption, sources_of(B + "lolo_per_lab.csv", B + "lolo_summary.json", B + "lolo_pooled.json"))
