"""F5 (PARTIAL) — loop controls for the models that have results in l7_aggregate.json (GBM variants only).
Paired differences vs the loop arm (sub protocol): loop − frozen, loop − shuffled-label (must be > 0 = the model uses feedback), K_phys − loop,
contradicted-K_phys − loop, shuffled-K_phys − loop; 95% seed-bootstrap CI. Regimes with < 8 paired seeds are hatched/greyed (no claim).
Models without results (atom LM, ChemBERTa, IH-LM rungs, larger pretrained LMs) are listed as PENDING in the figure itself.
Artifact: loop_retro/results/l7_aggregate.json.
"""
import json

from common import C, check, plt, reread, savefig, sources_of, src, watermark

L7 = "research/guangzhou_all_atom/cyclic_llm/loop_retro/results/l7_aggregate.json"
l7 = json.load(open(src(L7)))
contrasts = [("loop_sub - frozen_sub [yield]", "loop − frozen"), ("loop_sub - shuffled_sub [yield]", "loop − shuffled-label"),
             ("loop_kphys_sub - loop_sub [yield]", "K_phys prior − loop"), ("loop_kphys_contra_sub - loop_sub [yield]", "contradicted K_phys − loop"),
             ("loop_kshuf_sub - loop_sub [yield]", "shuffled K_phys − loop")]
models = [m for m in ("gbm", "gbm_physchem") if any(f"{m}|{r}" in l7["small"] for r in "ABL")]
regs = [("A", C["blue"]), ("B", C["orange"]), ("L", C["green"])]
fig, axs = plt.subplots(1, len(models), figsize=(9.6, 3.6), sharey=True)
for ax, m in zip(axs, models):
    for ci, (cname, clabel) in enumerate(contrasts):
        for ri, (reg, col) in enumerate(regs):
            e = l7["small"].get(f"{m}|{reg}")
            if not e or e["contrasts"].get(cname, {}).get("mean") is None:
                continue
            v = e["contrasts"][cname]
            y = len(contrasts) - 1 - ci + (ri - 1) * 0.22
            weak = e["n_seeds"] < 8
            cont = ax.errorbar(v["mean"], y, xerr=[[v["mean"] - v["ci"][0]], [v["ci"][1] - v["mean"]]], fmt="o", ms=3.4, color=col if not weak else C["grey"],
                               mfc="white" if weak else col, capsize=1.6, lw=0.9)
            seg = cont.lines[2][0].get_segments()[0]
            check(f"F5 {m}|{reg} {clabel} mean", float(cont.lines[0].get_xdata()[0]), float(reread(L7, "small", f"{m}|{reg}", "contrasts", cname, "mean")))
            check(f"F5 {m}|{reg} {clabel} lo", float(seg[0][0]), float(reread(L7, "small", f"{m}|{reg}", "contrasts", cname, "ci")[0]))
    ax.axvline(0, color=C["black"], lw=0.7, ls="--")
    ax.set_yticks(range(len(contrasts)), [c[1] for c in reversed(contrasts)], fontsize=6.4)
    ax.set_xlabel("difference in yield (95% seed-bootstrap CI)")
    ax.set_title(m, loc="left")
for reg, col in regs:
    axs[0].plot([], [], "o", color=col, label=f"regime {reg}", ms=4)
axs[0].plot([], [], "o", color=C["grey"], mfc="white", label="< 8 paired seeds (no claim)", ms=4)
axs[0].legend(frameon=False, fontsize=6, loc="lower right")
watermark(fig, "PARTIAL", alpha=0.10, size=60)
fig.text(0.5, -0.02, "PENDING: atom LM, ChemBERTa, IH-LM rungs R0–R4, larger pretrained peptide/chemistry LMs (no entries in l7_aggregate.json yet)", ha="center", fontsize=7, color=C["vermilion"])
fig.tight_layout()
caption = ("F5 (PARTIAL). Loop controls for the GBM baselines only. Differences are paired by seed (10 seeds; regime B for 'gbm' has only 2 seeds and is drawn hollow/grey). "
           "The shuffled-label control must lose to the loop; a contradicted knowledge prior must not help. Other models are PENDING.")
savefig(fig, "F5_controls_partial", "F5 controls (partial)", caption, sources_of(L7))
