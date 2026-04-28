"""
Pilot Step 5: Generate figures and summary report.

Produces 4 publication-quality figures for the grant proposal:
  Fig 1: UMAP of prior ensemble colored by gap status and conformer type
  Fig 2: RMSD-to-nearest-cryoDRGN distribution (gap fraction histogram)
  Fig 3: Pocket score comparison: cryoDRGN vs gap conformers
  Fig 4: λ scan — ESS and gap probability vs reweighting strength
          (demonstrates the CryoEnsemble posterior concept)
"""

import numpy as np
import json, os, warnings
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
from matplotlib.patches import Patch
from sklearn.decomposition import PCA
from sklearn.manifold import TSNE

warnings.filterwarnings("ignore")

OUT  = "/home/yzhang/biomate/pilot_study"
FIGS = f"{OUT}/figures"
os.makedirs(FIGS, exist_ok=True)

COLORS = {
    "local":    "#4C72B0",
    "domain":   "#DD8452",
    "rare":     "#C44E52",
    "cryo":     "#2ca02c",
    "captured": "#76b7b2",
    "gap":      "#e15759",
}

plt.rcParams.update({
    "font.family": "sans-serif",
    "font.size": 10,
    "axes.titlesize": 11,
    "axes.labelsize": 10,
    "figure.dpi": 150,
    "axes.spines.top": False,
    "axes.spines.right": False,
})

# ─── Load data ────────────────────────────────────────────────────────────────
with open(f"{OUT}/analysis/gap_analysis_results.json") as f:
    gap_results = json.load(f)
with open(f"{OUT}/analysis/pocket_analysis_results.json") as f:
    pocket_results = json.load(f)
with open(f"{OUT}/analysis/reweighting_results.json") as f:
    rw_results = json.load(f)

proteins = {
    "beta2ar": "β₂-Adrenergic Receptor (β₂AR, 2RH1)",
    "trpv1":   "TRPV1 Ion Channel (3J5P)",
}

# ─── Figure 1: PCA of prior ensemble (colored by gap/captured and type) ──────
fig1, axes = plt.subplots(2, 2, figsize=(12, 10))
fig1.suptitle("Figure 1: Conformational Space — Prior Ensemble vs cryoDRGN Coverage",
               fontsize=13, fontweight="bold", y=0.98)

for col, (name, title) in enumerate(proteins.items()):
    prior  = np.load(f"{OUT}/conformers/{name}/prior_ensemble.npy")
    centers= np.load(f"{OUT}/cryodrgn_clusters/{name}/cluster_centers.npy")
    in_gap = np.load(f"{OUT}/analysis/{name}_in_gap.npy")
    with open(f"{OUT}/conformers/{name}/prior_labels.json") as f:
        labels = np.array(json.load(f))

    # PCA on flattened coordinates
    flat_prior   = prior.reshape(len(prior), -1).astype(np.float64)
    flat_centers = centers.reshape(len(centers), -1).astype(np.float64)

    pca = PCA(n_components=2, random_state=42)
    pca.fit(flat_prior)
    emb_prior   = pca.transform(flat_prior)
    emb_centers = pca.transform(flat_centers)
    var_exp = pca.explained_variance_ratio_ * 100

    gap_frac = gap_results[name]["gap_fraction"]

    # Top panel: colored by gap vs captured
    ax = axes[0, col]
    ax.scatter(emb_prior[~in_gap, 0], emb_prior[~in_gap, 1],
               c=COLORS["captured"], alpha=0.5, s=12, label="Captured by cryoDRGN", zorder=2)
    ax.scatter(emb_prior[in_gap, 0], emb_prior[in_gap, 1],
               c=COLORS["gap"], alpha=0.7, s=14, label=f"Gap ({gap_frac:.0%})", zorder=3)
    ax.scatter(emb_centers[:, 0], emb_centers[:, 1],
               c=COLORS["cryo"], marker="D", s=60, edgecolors="black", linewidths=0.5,
               label="cryoDRGN clusters", zorder=4)
    ax.set_xlabel(f"PC1 ({var_exp[0]:.1f}%)")
    ax.set_ylabel(f"PC2 ({var_exp[1]:.1f}%)")
    ax.set_title(f"{title}\nGap fraction: {gap_frac:.1%}")
    ax.legend(fontsize=8, markerscale=1.2)

    # Bottom panel: colored by conformer type
    ax = axes[1, col]
    for t in ["local", "domain", "rare"]:
        mask = labels == t
        ax.scatter(emb_prior[mask, 0], emb_prior[mask, 1],
                   c=COLORS[t], alpha=0.5, s=12,
                   label=f"{t.capitalize()} (n={mask.sum()})", zorder=2)
    ax.scatter(emb_centers[:, 0], emb_centers[:, 1],
               c=COLORS["cryo"], marker="D", s=60, edgecolors="black", linewidths=0.5,
               label="cryoDRGN clusters", zorder=4)
    ax.set_xlabel(f"PC1 ({var_exp[0]:.1f}%)")
    ax.set_ylabel(f"PC2 ({var_exp[1]:.1f}%)")
    ax.set_title(f"{title}\nConformer type breakdown")
    ax.legend(fontsize=8, markerscale=1.2)

fig1.tight_layout(rect=[0, 0, 1, 0.96])
fig1.savefig(f"{FIGS}/fig1_conformational_space.png", dpi=150, bbox_inches="tight")
plt.close(fig1)
print("  Fig 1 saved: fig1_conformational_space.png")

# ─── Figure 2: RMSD distribution — the gap fraction histogram ────────────────
fig2, axes2 = plt.subplots(1, 2, figsize=(12, 5))
fig2.suptitle("Figure 2: Conformational Gap — RMSD to Nearest cryoDRGN Cluster",
               fontsize=13, fontweight="bold")

for col, (name, title) in enumerate(proteins.items()):
    min_rmsd = np.load(f"{OUT}/analysis/{name}_min_rmsd.npy")
    in_gap   = np.load(f"{OUT}/analysis/{name}_in_gap.npy")
    with open(f"{OUT}/conformers/{name}/prior_labels.json") as f:
        labels = np.array(json.load(f))

    ax = axes2[col]
    gap_frac = gap_results[name]["gap_fraction"]
    threshold = gap_results[name]["gap_threshold_angstrom"]

    # Stacked histogram by type
    bins = np.linspace(0, min_rmsd.max() * 1.05, 35)
    for t in ["local", "domain", "rare"]:
        mask = labels == t
        ax.hist(min_rmsd[mask], bins=bins, alpha=0.65, color=COLORS[t],
                label=t.capitalize(), histtype="stepfilled", edgecolor="white", linewidth=0.3)

    # Gap threshold line
    ax.axvline(threshold, color="black", linestyle="--", linewidth=1.5,
               label=f"Gap threshold ({threshold} Å)")

    # Shade gap region
    ax.axvspan(threshold, bins[-1], alpha=0.08, color=COLORS["gap"],
               label=f"Gap region ({gap_frac:.1%})")

    ax.set_xlabel("RMSD to nearest cryoDRGN cluster (Å)")
    ax.set_ylabel("Number of conformers")
    ax.set_title(f"{title.split('(')[0].strip()}\n"
                 f"Gap fraction: {gap_frac:.1%}  "
                 f"(median RMSD: {np.median(min_rmsd):.2f} Å)")
    ax.legend(fontsize=8)

    # Annotate stats
    ax.text(0.97, 0.95,
            f"Captured: {(~in_gap).sum()}\nIn gap: {in_gap.sum()}",
            transform=ax.transAxes, ha="right", va="top", fontsize=9,
            bbox=dict(boxstyle="round,pad=0.3", facecolor="white", alpha=0.8))

fig2.tight_layout()
fig2.savefig(f"{FIGS}/fig2_gap_histogram.png", dpi=150, bbox_inches="tight")
plt.close(fig2)
print("  Fig 2 saved: fig2_gap_histogram.png")

# ─── Figure 3: Pocket score comparison ───────────────────────────────────────
fig3, axes3 = plt.subplots(1, 2, figsize=(12, 5))
fig3.suptitle("Figure 3: Pocket Landscape — cryoDRGN Clusters vs Gap Conformers",
               fontsize=13, fontweight="bold")

for col, (name, title) in enumerate(proteins.items()):
    scores_cryo     = np.load(f"{OUT}/analysis/{name}_scores_cryo.npy")
    scores_gap      = np.load(f"{OUT}/analysis/{name}_scores_gap.npy")
    scores_captured = np.load(f"{OUT}/analysis/{name}_scores_captured.npy")

    pr = pocket_results[name]

    ax = axes3[col]

    # Distribution of best-pocket scores per conformer
    best_cryo     = scores_cryo.max(axis=1)     if len(scores_cryo)     > 0 else np.array([0])
    best_gap      = scores_gap.max(axis=1)      if len(scores_gap)      > 0 else np.array([0])
    best_captured = scores_captured.max(axis=1) if len(scores_captured) > 0 else np.array([0])

    data   = [best_cryo, best_captured, best_gap]
    labels_plot = [
        f"cryoDRGN\n(n={len(best_cryo)})",
        f"Captured\n(n={len(best_captured)})",
        f"Gap\n(n={len(best_gap)})",
    ]
    colors_plot = [COLORS["cryo"], COLORS["captured"], COLORS["gap"]]

    bp = ax.boxplot(data, patch_artist=True, notch=False,
                    medianprops=dict(color="black", linewidth=2),
                    whiskerprops=dict(linewidth=1.2),
                    capprops=dict(linewidth=1.2),
                    flierprops=dict(marker="o", markersize=3, alpha=0.4))
    for patch, color in zip(bp["boxes"], colors_plot):
        patch.set_facecolor(color)
        patch.set_alpha(0.7)

    ax.set_xticklabels(labels_plot)
    ax.set_ylabel("Best-pocket score (higher = more exposed)")
    ax.set_title(f"{title.split('(')[0].strip()}\n"
                 f"Gap enrichment: {pr['pocket_enrichment_pct']:+.1f}%")

    # Annotate novel gap sites
    if pr["unique_gap_only_pocket_sites"]:
        ax.text(0.97, 0.05,
                f"Novel gap-only\npocket residues:\n{pr['unique_gap_only_pocket_sites']}",
                transform=ax.transAxes, ha="right", va="bottom", fontsize=8,
                bbox=dict(boxstyle="round,pad=0.3", facecolor="#ffe0e0", alpha=0.9))

fig3.tight_layout()
fig3.savefig(f"{FIGS}/fig3_pocket_landscape.png", dpi=150, bbox_inches="tight")
plt.close(fig3)
print("  Fig 3 saved: fig3_pocket_landscape.png")

# ─── Figure 4: Reweighting λ scan (CryoEnsemble concept demonstration) ───────
fig4, axes4 = plt.subplots(1, 2, figsize=(12, 5))
fig4.suptitle("Figure 4: CryoEnsemble Reweighting — Posterior Ensemble Optimization",
               fontsize=13, fontweight="bold")

for col, (name, title) in enumerate(proteins.items()):
    rw = rw_results[name]
    scan = rw["lambda_scan"]

    lambdas   = [r["lambda"]           for r in scan]
    ess_frac  = [r["ess_frac"]         for r in scan]
    gap_prob  = [r["posterior_gap_fraction"] for r in scan]
    chi2_mean = [r["chi2_mean"]        for r in scan]

    ax = axes4[col]
    ax2 = ax.twinx()

    l1, = ax.plot(lambdas, ess_frac, "o-", color="#4C72B0", linewidth=2, label="ESS / N (diversity)")
    l2, = ax.plot(lambdas, gap_prob,  "s--", color=COLORS["gap"], linewidth=2, label="Gap probability")
    l3, = ax2.plot(lambdas, chi2_mean, "^:", color="#2ca02c", linewidth=2, label="χ² (data fit)")

    # Mark λ*
    lam_star = rw["lambda_star"]
    ax.axvline(lam_star, color="black", linestyle="--", linewidth=1.5,
               label=f"λ* = {lam_star}")
    ax.axhline(0.30, color="gray", linestyle=":", linewidth=1, alpha=0.7)
    ax.text(lambdas[-1] * 0.5, 0.32, "ESS threshold (0.30)", color="gray", fontsize=8)

    ax.set_xlabel("Reweighting strength λ")
    ax.set_ylabel("Fraction (ESS/N or gap probability)")
    ax2.set_ylabel("Mean χ² (Å²)", color="#2ca02c")
    ax2.tick_params(axis="y", labelcolor="#2ca02c")
    ax.set_title(f"{title.split('(')[0].strip()}\n"
                 f"λ* = {lam_star}  |  Post. gap = {rw['posterior_gap_fraction']:.3f}")

    lines = [l1, l2, l3]
    labs  = [l.get_label() for l in lines]
    ax.legend(lines, labs, fontsize=8, loc="center right")

    # Annotation: what the posterior achieves
    ax.text(0.02, 0.05,
            f"Prior gap: {rw['prior_gap_fraction']:.3f}\n"
            f"Post. gap: {rw['posterior_gap_fraction']:.3f}\n"
            f"ESS at λ*: {rw['ess_at_lambda_star']:.0f}",
            transform=ax.transAxes, ha="left", va="bottom", fontsize=9,
            bbox=dict(boxstyle="round,pad=0.3", facecolor="white", alpha=0.9))

fig4.tight_layout()
fig4.savefig(f"{FIGS}/fig4_reweighting_scan.png", dpi=150, bbox_inches="tight")
plt.close(fig4)
print("  Fig 4 saved: fig4_reweighting_scan.png")

# ─── Summary report ───────────────────────────────────────────────────────────
print("\n" + "="*70)
print("PILOT STUDY SUMMARY — CryoEnsemble Proof-of-Concept")
print("="*70)

for name, title in proteins.items():
    g  = gap_results[name]
    p  = pocket_results[name]
    rw = rw_results[name]

    print(f"\n{'─'*60}")
    print(f"  {title}")
    print(f"{'─'*60}")
    print(f"  Conformational gap:")
    print(f"    Prior ensemble:   {g['n_prior']} conformers")
    print(f"    cryoDRGN states:  {g['n_cryodrgn_clusters']} clusters (≥2% population)")
    print(f"    Gap fraction:     {g['gap_fraction']:.1%}  "
          f"({g['gap_count']} conformers not captured)")
    print(f"    Rare-state gap:   "
          f"{g['type_breakdown']['rare']['gap_fraction']:.1%} of rare conformers missed")
    print(f"  Pocket landscape:")
    print(f"    Gap conformers {p['pocket_enrichment_pct']:+.1f}% more pocket-exposed than cryoDRGN")
    print(f"    Novel gap-only sites: residues {p['unique_gap_only_pocket_sites']}")
    print(f"  CryoEnsemble reweighting (BME posterior):")
    print(f"    Optimal λ*:      {rw['lambda_star']}")
    print(f"    Prior diversity: {rw['mean_pairwise_rmsd_prior']:.3f} Å mean pw-RMSD")
    print(f"    Post. diversity: {rw['mean_pairwise_rmsd_posterior']:.3f} Å mean pw-RMSD")
    print(f"    Gap probability: {rw['prior_gap_fraction']:.3f} → {rw['posterior_gap_fraction']:.3f} "
          f"(posterior retains {rw['posterior_gap_fraction']/rw['prior_gap_fraction']:.2f}x gap)")

print("\n" + "="*70)
print(f"  4 figures saved to: {FIGS}/")
print("="*70)
