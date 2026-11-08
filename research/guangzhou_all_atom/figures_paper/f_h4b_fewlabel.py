"""F-H4b — few-label new-target adaptation (analysis I, family-held-out). AUROC vs number of revealed labels k for the target.
Arms: NN to revealed compounds, FP-k (fit on revealed only), PT+k (pretrained logistic prior + revealed), PT (no-target pretrained),
R (random); plus the compound-only control C3 (Morgan leave-fold-out) from the per-k validity gate for reference.
Artifacts: retro_recovery/results/h4b_baselines.json, validity_gate_h4b.json.
"""
from common import C, check, hbar_check, plt, reread, savefig, sources_of, src, vbar_check
import json

RR = "research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery/results/"
H = RR + "h4b_baselines.json"
G = RR + "validity_gate_h4b.json"
h = json.load(open(src(H)))
g = json.load(open(src(G)))
ks = ["0", "5", "10", "25"]
arms = [("NN", "nearest neighbour to revealed", C["blue"], "o"), ("FP-k", "fingerprint fit on revealed only", C["sky"], "s"),
        ("PT+k", "pretrained prior + revealed", C["orange"], "^"), ("PT", "no-target pretrained (other families)", C["purple"], "v"),
        ("R", "random", C["grey"], "x")]
fig, ax = plt.subplots(figsize=(6.4, 3.6))
off = {a[0]: (i - 2) * 0.12 for i, a in enumerate(arms)}
for key, label, col, mk in arms:
    xs, ys, lo, hi, kk = [], [], [], [], []
    for i, k in enumerate(ks):
        if key in h[k]["arms"]:
            a = h[k]["arms"][key]["auc"]
            xs.append(i + off[key]); ys.append(a["point"]); lo.append(a["point"] - a["lo"]); hi.append(a["hi"] - a["point"]); kk.append(k)
    cont = ax.errorbar(xs, ys, yerr=[lo, hi], fmt=mk + "-", color=col, ms=4, capsize=1.6, lw=0.9, label=label)
    # checks: drawn markers and intervals vs fresh artifact reads
    segs = cont.lines[2][0].get_segments()
    for j, k in enumerate(kk):
        check(f"h4b {key} k={k} point", float(cont.lines[0].get_ydata()[j]), float(reread(H, k, "arms", key, "auc", "point")))
        check(f"h4b {key} k={k} lo", float(segs[j][0][1]), float(reread(H, k, "arms", key, "auc", "lo")))
        check(f"h4b {key} k={k} hi", float(segs[j][1][1]), float(reread(H, k, "arms", key, "auc", "hi")))
# control C3 from the per-k gate (k=5,10,25)
cx, cy, clo, chi, ck = [], [], [], [], []
for i, k in enumerate(ks):
    if k in g:
        c3 = g[k]["primary"]["C3_morgan_fp_leave_fold_out"]
        cx.append(i); cy.append(c3["point"]); clo.append(c3["point"] - c3["lo"]); chi.append(c3["hi"] - c3["point"]); ck.append(k)
cont = ax.errorbar(cx, cy, yerr=[clo, chi], fmt="D--", color=C["vermilion"], ms=3.5, capsize=1.6, lw=0.8, label="control C3 (compound-only, Morgan leave-fold-out)")
segs = cont.lines[2][0].get_segments()
for j, k in enumerate(ck):
    check(f"h4b control C3 k={k} point", float(cont.lines[0].get_ydata()[j]), float(reread(G, k, "primary", "C3_morgan_fp_leave_fold_out", "point")))
    check(f"h4b control C3 k={k} lo", float(segs[j][0][1]), float(reread(G, k, "primary", "C3_morgan_fp_leave_fold_out", "lo")))
ax.axhline(0.5, color=C["black"], lw=0.7, ls=":")
ax.set_xticks(range(4), [f"k = {k}\n({h[k]['targets']} targets,\n{h[k]['families']} families)" for k in ks])
ax.set_ylabel("AUROC (family-cluster bootstrap 95% CI)")
ax.set_ylim(0.4, 0.95)
ax.set_title("Few-label adaptation to a held-out target (analysis I)", loc="left")
ax.legend(frameon=False, fontsize=6, loc="upper left", bbox_to_anchor=(1.01, 1.0))
fig.tight_layout()
caption = ("F-H4b. AUROC for ranking a held-out target's remaining compounds after revealing k labelled compounds (seeded, 5 seeds), family-held-out "
           "(fold files folds_v1.csv). Nearest-neighbour to the revealed compounds is the strongest arm; gain is analog lookup within a series. "
           "Control C3 (compound-only Morgan classifier, leave-fold-out) exceeds 0.5 at every k, so results are control-adjusted. Intervals: family-cluster bootstrap.")
savefig(fig, "FH4b_fewlabel_adaptation", "H4b few-label adaptation", caption, sources_of(H, G))
