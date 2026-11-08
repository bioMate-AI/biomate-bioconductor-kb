"""F1 — study design schematic (no data): replay loop with controls and evaluation slices; benchmark validity gates.
Drawn from the registered protocols (PREREG_LOOP.md, 20261028_AVB6_RETROSPECTIVE_RECOVERY_PREREG.md)."""
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

from common import C, plt, savefig, sources_of

P1 = "research/guangzhou_all_atom/cyclic_llm/loop_retro/PREREG_LOOP.md"
P2 = "docs/20261028_AVB6_RETROSPECTIVE_RECOVERY_PREREG.md"
fig, (a, b) = plt.subplots(1, 2, figsize=(13.0, 5.4), gridspec_kw=dict(width_ratios=[1.1, 1], wspace=0.06))
for ax in (a, b):
    ax.set_xlim(0, 10); ax.set_ylim(0, 10); ax.axis("off")


def box(ax, x, y, w, h, text, fc="#f2f2f2", ec=C["black"], fs=5.7, bold=False):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.04,rounding_size=0.12", fc=fc, ec=ec, lw=0.8))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fs, fontweight="bold" if bold else "normal", wrap=True)


def arrow(ax, p, q, rad=0.0, col=C["black"]):
    ax.add_patch(FancyArrowPatch(p, q, arrowstyle="-|>", mutation_scale=9, lw=0.9, color=col, connectionstyle=f"arc3,rad={rad}"))


a.set_title("(a) Retrospective closed-loop replay", loc="left", fontsize=9)
box(a, 0.2, 7.6, 3.0, 1.8, "Pool of measured\ncompounds (labels\nhidden); regimes\nA, B, L", fc="#e8f1fa")
box(a, 4.0, 7.6, 3.0, 1.8, "Model scores /\nproposes (IH-LM or\ncomparator; prior\nK_phys)", fc="#fdf0d5")
box(a, 7.6, 7.6, 2.2, 1.8, "Select batch\n(50 per round)", fc="#f2f2f2")
box(a, 7.6, 4.6, 2.2, 1.8, "Reveal hidden\nlabels (oracle:\nmeasured\nPAMPA)", fc="#e8f1fa")
box(a, 4.0, 4.6, 3.0, 1.8, "Update: fast\nsymbolic memory +\nslow neural\nfine-tune", fc="#fdf0d5")
arrow(a, (3.2, 8.5), (4.0, 8.5)); arrow(a, (7.0, 8.5), (7.6, 8.5)); arrow(a, (8.7, 7.6), (8.7, 6.4)); arrow(a, (7.6, 5.5), (7.0, 5.5)); arrow(a, (5.5, 6.4), (5.5, 7.6), rad=0.0)
a.text(5.6, 7.0, "repeat 10 rounds", fontsize=6, ha="left", style="italic")
box(a, 0.2, 2.2, 4.6, 1.9, "Five controls (same seeds, pools)\ndata-matched one-shot\nrandom feedback\nshuffled labels (must not improve)\nfrozen model · knowledge off", fc="#fbe9e7")
box(a, 5.2, 2.2, 4.6, 1.9, "Evaluation slices\nE: held-out ranking\nE_f: stereoisomer groups (one\nrevealed/target split per group)\nE_s: low-data sources", fc="#e6f4ea")
box(a, 0.2, 0.2, 9.6, 1.4, "Comparators: baselines (GBM, physchem, rule, nearest neighbour) · IH-LM ladder R0–R4 ·\nlarger pretrained peptide/chemistry LMs fine-tuned plainly", fc="#f2f2f2", fs=5.7)

b.set_title("(b) Benchmark with validity gates", loc="left", fontsize=9)
box(b, 0.2, 8.0, 4.3, 1.5, "Frozen positive / decoy\nlists (SHA-256; built\nbefore any scorer ran)", fc="#e8f1fa")
box(b, 5.4, 8.0, 4.3, 1.5, "Family-disjoint folds\n(size-balanced; held-out\nfamilies not in training)", fc="#e8f1fa")
box(b, 0.2, 5.6, 4.3, 1.6, "Arm scores (rules,\nknowledge base, models;\ncontamination flags)", fc="#fdf0d5")
box(b, 5.4, 5.6, 4.3, 1.6, "No-target controls\nC1 typicality\nC2 multi-proxy\nC3 Morgan leave-fold-out", fc="#fbe9e7")
box(b, 0.2, 2.9, 9.5, 1.7, "Gate: a control above chance (CI excludes 0.5) means compound-only information\nseparates positives from decoys, so the analysis cannot credit target knowledge:\narms must beat the controls as well as the strongest baseline", fc="#f2f2f2", fs=5.7)
box(b, 0.2, 0.6, 9.5, 1.5, "Verdict per arm: SUPPORTED / NOT_SUPPORTED / INCONCLUSIVE\n(family-cluster bootstrap; strongest baseline chosen on the test side)", fc="#e6f4ea", fs=5.7)
arrow(b, (2.35, 8.0), (2.35, 7.2)); arrow(b, (7.55, 8.0), (7.55, 7.2)); arrow(b, (4.5, 6.4), (5.4, 6.4)); arrow(b, (5.0, 5.6), (5.0, 4.6)); arrow(b, (5.0, 2.9), (5.0, 2.1))
fig.tight_layout()
caption = "F1. Study design. (a) Replay loop (select → reveal hidden measured label → update), controls and evaluation slices. (b) Benchmark construction and validity gates. Schematic; no data."
savefig(fig, "F1_study_design", "F1 study design", caption, sources_of(P1, P2))
