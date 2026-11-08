"""Figures for the cyclic-peptide governance manuscript (Paper B). Every number is read from a committed
result file or quoted from the cited manuscript section."""
import json, os
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
R = os.path.join(os.path.dirname(__file__), "..", "..", "research", "guangzhou_all_atom", "results")
BLUE, GREY, RED, GREEN = "#2f6db5", "#8a8f98", "#c0392b", "#2e8b57"
plt.rcParams.update({"font.size": 9, "axes.spines.top": False, "axes.spines.right": False})

# ---- Fig 1: loop + ladder + firewall
fig, ax = plt.subplots(figsize=(10, 4.6)); ax.axis("off"); ax.set_xlim(0, 10); ax.set_ylim(0, 5)
def box(x, y, w, h, t, fc="#eef3fa", ec=BLUE):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.03", fc=fc, ec=ec, lw=1.2))
    ax.text(x + w/2, y + h/2, t, ha="center", va="center")
def arrow(a, b, c=BLUE):
    ax.add_patch(FancyArrowPatch(a, b, arrowstyle="-|>", mutation_scale=12, color=c, lw=1.2))
for i, t in enumerate(["Design\n(generator)", "Verify\n(ladder)", "Select\n(firewalled)", "Learn\n(retrain)"]):
    box(0.3 + i*2.45, 3.6, 1.9, 0.9, t)
    if i < 3: arrow((2.2 + i*2.45, 4.05), (2.75 + i*2.45, 4.05))
arrow((9.35, 3.6), (9.35, 3.2)); arrow((9.35, 3.2), (1.25, 3.2)); arrow((1.25, 3.2), (1.25, 3.6))
ax.text(5.3, 3.3, "promotion of any learned change only if it passes the firewall", ha="center", fontsize=8, color=GREY)
rungs = [("L0  free deterministic gates", "cost ≈ 0"), ("L1  real execution", "seconds"),
         ("L2  in-silico physics (co-folding, MM-GBSA, FEP)", "GPU-hours"), ("L3  wet-lab assay (v2)", "weeks, money")]
for i, (t, c) in enumerate(rungs):
    box(0.3, 2.35 - i*0.62, 5.6, 0.5, t, fc="#fff" if i < 3 else "#f4f4f4", ec=BLUE if i < 3 else GREY)
    ax.text(6.05, 2.6 - i*0.62, c, va="center", color=GREY, fontsize=8)
box(7.3, 0.35, 2.4, 1.95, "Leakage firewall\nheld-out TARGET\nheld-out SCAFFOLD\nheld-out ASSAY\n(not held-out instances)", fc="#fdf1ef", ec=RED)
ax.text(0.3, 4.75, "Cost-ordered verifier ladder (left) and biology-structured firewall (right)", fontsize=9, weight="bold")
fig.savefig("fig1_loop_ladder_firewall.png", dpi=200, bbox_inches="tight"); plt.close(fig)

# ---- Fig 2: three refutations
fig, axs = plt.subplots(1, 3, figsize=(11, 3.6))
a = axs[0]  # family memorization, random split (values from SELECTOR_LEAKAGE_AUDIT)
names = ["Abeta42", "hIAPP"]; km = [0.986, 0.698]; lm = [0.990, 0.689]
x = range(2); a.bar([i-0.18 for i in x], km, 0.35, color=GREY, label="k-mer logistic")
a.bar([i+0.18 for i in x], lm, 0.35, color=BLUE, label="LM selector")
a.set_xticks(list(x)); a.set_xticklabels(names); a.set_ylim(0.4, 1.2); a.set_ylabel("AUC, random split")
a.set_title("(a) A trivial k-mer model matches the LM", fontsize=9); a.legend(frameon=False, loc="upper center", ncol=2, fontsize=8)
a.text(0.5, 1.09, "family-disjoint splits: hIAPP 0.52, FIKK13 0.42", ha="center", fontsize=7.5, color=RED)
b = axs[1]  # renal rho before/after
rho = [0.27, -0.26]; lo = [0.01, -0.55]; hi = [0.51, 0.09]
for i, (r, l, h, c, t) in enumerate(zip(rho, lo, hi, [RED, GREEN], ["before\n(charge bug)", "after\ncorrection"])):
    b.errorbar(i, r, yerr=[[r-l], [h-r]], fmt="o", color=c, capsize=4)
b.axhline(0, color=GREY, lw=0.8, ls="--"); b.set_xlim(-0.6, 1.6); b.set_xticks([0, 1]); b.set_xticklabels(["before\n(charge bug)", "after\ncorrection"])
b.set_ylabel("cross-target Spearman ρ (95% CI)"); b.set_title("(b) Renal transfer vanishes after the fix", fontsize=9)
b.set_ylim(-0.7, 0.7); b.text(0, 0.55, "p = 0.036", ha="center", fontsize=8); b.text(1, 0.18, "p = 0.11", ha="center", fontsize=8)
c = axs[2]  # FEP control edge
c.bar([0, 1], [-0.95, -0.18], 0.5, color=[GREY, BLUE], yerr=[0, 0.15], capsize=4)
c.axhline(0, color=GREY, lw=0.8); c.set_xticks([0, 1]); c.set_xticklabels(["measured", "computed\n(metal-free pocket)"])
c.set_ylabel("YY→FF ΔΔG (kcal/mol)"); c.set_title("(c) FEP control missed ~5×; Mn 30–37 Å away", fontsize=9)
fig.tight_layout(); fig.savefig("fig2_three_refutations.png", dpi=200, bbox_inches="tight"); plt.close(fig)

# ---- Fig 3: honest bounds
bm = json.load(open(os.path.join(R, "binding_model_metrics_cyclic.json")))["splits"]
pm = json.load(open(os.path.join(R, "permeability_predictor_metrics.json")))
lt = json.load(open(os.path.join(R, "boltzgen_loto_smoke_summary.json")))["head_to_head_ft_minus_base"]
fig, axs = plt.subplots(1, 3, figsize=(11, 3.4))
a = axs[0]; v = [bm["random"]["RandomForest"]["r2"], bm["novel_target_pdl1_avb6"]["RandomForest"]["r2"]]
a.bar(["random split", "novel target\n(PD-L1+αvβ6)"], v, color=[GREY, BLUE]); a.set_ylabel("R² (random forest)"); a.set_title("(a) Binding affinity", fontsize=9)
for i, y in enumerate(v): a.text(i, y+0.01, f"{y:.2f}", ha="center")
b = axs[1]; v = [pm["scaffold_r2"], pm["reference_r2"]["CPMP"], pm["reference_r2"]["CycPeptMP"]]
b.bar(["ours\n(scaffold split)", "CPMP\n(published)", "CycPeptMP\n(published)"], v, color=[BLUE, GREY, GREY]); b.set_title("(b) Permeability R²", fontsize=9)
for i, y in enumerate(v): b.text(i, y+0.01, f"{y:.2f}", ha="center")
c = axs[2]; ks = list(lt); d = [lt[k]["d_iptm"] for k in ks]
c.bar(ks, d, color=RED); c.axhline(0, color=GREY, lw=0.8); c.set_ylabel("Δ iPTM (fine-tuned − base)")
c.set_title("(c) Held-out-target smoke: worse", fontsize=9)
fig.tight_layout(); fig.savefig("fig3_honest_bounds.png", dpi=200, bbox_inches="tight"); plt.close(fig)
print("ok", d)
