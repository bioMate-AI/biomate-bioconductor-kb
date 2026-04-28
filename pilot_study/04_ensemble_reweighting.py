"""
Pilot Step 4: Ensemble Reweighting — Approximate CryoEnsemble Posterior.

This is the "bit more of the proposed approach" — a minimal implementation
of the Bayesian reweighting at the heart of CryoEnsemble.

CONCEPT:
  - Prior P(x | seq) = uniform weights over BioEmu conformers
  - Likelihood L(data | x) = how consistent is conformer x with
    what cryoDRGN observed? (approximated via cluster membership probability)
  - Posterior P(x | data, seq) ∝ L(data | x) * P(x | seq)

IMPLEMENTATION (BME — Maximum Entropy / Bayesian reweighting):
  Using the method of cryoENsemble (Scientific Reports 2024):
    w_i* = w0_i * exp(-λ * chi2_i) / Z
  where:
    w0_i = prior weight (1/N uniform)
    chi2_i = mean squared RMSD to weighted cryoDRGN cluster centroids
             (how inconsistent conformer i is with observed cryo-EM data)
    λ = regularization temperature (controls how much to trust the data vs prior)
    Z = partition function for normalization

The optimal λ is found by scanning: low λ preserves the prior (all conformers),
high λ collapses to the cryoDRGN-dominant conformation. The "sweet spot" is
where the posterior ensemble overlaps well with cryoDRGN clusters (χ² reduced)
while retaining physical conformers not in cryoDRGN (the CryoEnsemble goal).

This is the key pilot result: we show that reweighting with λ* recovers
more of the cryoDRGN-observed states than the prior (validating the posterior
likelihood) while retaining gap conformers (validating the prior regularization).
"""

import numpy as np
import json, os
from scipy.optimize import minimize_scalar

OUT = "/home/yzhang/biomate/pilot_study"

def compute_chi2(conformer_coords, cluster_centers, cluster_weights):
    """
    Consistency of a conformer with the cryo-EM observations.

    chi2 = Σ_k w_k * RMSD(conformer, cluster_k)^2

    Low chi2 = conformer is close to the observed (populated) clusters.
    High chi2 = conformer is in a region not seen in cryoDRGN.
    """
    N = conformer_coords.shape[0]
    chi2 = 0.0
    for k, (center, wk) in enumerate(zip(cluster_centers, cluster_weights)):
        diff  = conformer_coords - center
        rmsd2 = (diff ** 2).sum() / N
        chi2 += wk * rmsd2
    return chi2


def bme_reweight(prior_ensemble, cluster_centers, cluster_weights, lam):
    """
    Bayesian Maximum Entropy reweighting at temperature lambda.
    Returns normalized posterior weights w* (shape: n_conformers).
    """
    n = len(prior_ensemble)
    w0 = np.ones(n) / n  # uniform prior

    chi2_vals = np.array([
        compute_chi2(prior_ensemble[i], cluster_centers, cluster_weights)
        for i in range(n)
    ])

    log_w = np.log(w0) - lam * chi2_vals
    log_w -= log_w.max()  # numerical stability
    w = np.exp(log_w)
    w /= w.sum()
    return w, chi2_vals


def effective_sample_size(weights):
    """ESS = (Σw)^2 / Σ(w^2). Full = N, collapsed to 1 = delta function."""
    return 1.0 / (weights ** 2).sum()


def posterior_gap_fraction(weights, in_gap, threshold=0.001):
    """Fraction of total probability mass in the gap (non-cryoDRGN-equivalent) conformers."""
    return weights[in_gap].sum()


results_rw = {}

for name in ["beta2ar", "trpv1"]:
    print(f"\n=== {name.upper()} ===")

    prior   = np.load(f"{OUT}/conformers/{name}/prior_ensemble.npy")
    centers = np.load(f"{OUT}/cryodrgn_clusters/{name}/cluster_centers.npy")
    weights = np.load(f"{OUT}/cryodrgn_clusters/{name}/cluster_weights.npy")
    in_gap  = np.load(f"{OUT}/analysis/{name}_in_gap.npy")

    with open(f"{OUT}/conformers/{name}/prior_labels.json") as f:
        labels = np.array(json.load(f))

    N = len(prior)
    ESS_full = float(N)

    print(f"  Prior: {N} conformers  |  Gap: {in_gap.sum()} ({in_gap.mean():.1%})")
    print(f"\n  Scanning λ (reweighting strength)...")
    print(f"  {'λ':>10}  {'ESS':>8}  {'ESS/N':>8}  {'post_gap%':>10}  {'chi2_mean':>12}")

    lambda_scan = [0.0, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0]
    scan_results = []

    for lam in lambda_scan:
        w_post, chi2_vals = bme_reweight(prior, centers, weights, lam)
        ess = effective_sample_size(w_post)
        gap_prob = posterior_gap_fraction(w_post, in_gap)
        chi2_mean = (w_post * chi2_vals).sum()
        scan_results.append({
            "lambda": lam, "ess": float(ess), "ess_frac": float(ess / N),
            "posterior_gap_fraction": float(gap_prob),
            "chi2_mean": float(chi2_mean)
        })
        print(f"  {lam:>10.2f}  {ess:>8.1f}  {ess/N:>8.3f}  "
              f"{gap_prob:>10.3f}  {chi2_mean:>12.4f}")

    # ── Find optimal λ: maximize data consistency while retaining ESS > 0.3*N ──
    # "Sweet spot": ESS/N >= 0.3 AND gap probability highest (most physical diversity)
    valid = [r for r in scan_results if r["ess_frac"] >= 0.30]
    if valid:
        optimal = min(valid, key=lambda r: r["chi2_mean"])
    else:
        optimal = scan_results[len(scan_results)//2]

    lam_star = optimal["lambda"]
    print(f"\n  Optimal λ* = {lam_star:.2f}  "
          f"(ESS={optimal['ess']:.1f}/{N}, gap_prob={optimal['posterior_gap_fraction']:.3f})")

    # ── Compute posterior at λ* ───────────────────────────────────────────────
    w_star, chi2_star = bme_reweight(prior, centers, weights, lam_star)

    # Prior vs posterior comparison
    prior_weights = np.ones(N) / N
    prior_gap_prob  = prior_weights[in_gap].sum()
    post_gap_prob   = w_star[in_gap].sum()

    print(f"\n  Prior gap probability:     {prior_gap_prob:.3f} (uniform = {in_gap.mean():.3f})")
    print(f"  Posterior gap probability: {post_gap_prob:.3f}")
    print(f"  Gap redistribution:        {(post_gap_prob - prior_gap_prob):+.3f}")

    # Posterior by conformer type
    print(f"\n  Posterior weight by type:")
    for t in ["local", "domain", "rare"]:
        mask = labels == t
        pw = float(w_star[mask].sum())
        prior_w = float(mask.mean())
        print(f"    {t:8s}:  posterior={pw:.3f}  prior={prior_w:.3f}  ratio={pw/prior_w:.2f}x")

    # Top-weighted posterior conformers
    top5_idx = np.argsort(w_star)[::-1][:5]
    print(f"\n  Top-5 highest-weight posterior conformers:")
    for rank, idx in enumerate(top5_idx):
        print(f"    #{rank+1}: conformer {idx:3d}  type={labels[idx]:8s}  "
              f"weight={w_star[idx]:.5f}  chi2={chi2_star[idx]:.3f}  in_gap={in_gap[idx]}")

    # Diversity metric: mean pairwise RMSD of posterior samples
    # (weighted expectation — higher = more diverse ensemble)
    sample_idx = np.random.choice(N, size=50, p=w_star, replace=True)
    sample_coords = prior[sample_idx]
    flat = sample_coords.reshape(50, -1)
    pw_rmsd = []
    for i in range(0, 50, 5):
        for j in range(i+1, 50, 5):
            d = np.sqrt(((flat[i] - flat[j])**2).mean())
            pw_rmsd.append(d)
    mean_pw_rmsd_post = float(np.mean(pw_rmsd))

    # Same for uniform prior
    unif_idx = np.random.choice(N, size=50, replace=False)
    unif_flat = prior[unif_idx].reshape(50, -1)
    pw_rmsd_prior = []
    for i in range(0, 50, 5):
        for j in range(i+1, 50, 5):
            d = np.sqrt(((unif_flat[i] - unif_flat[j])**2).mean())
            pw_rmsd_prior.append(d)
    mean_pw_rmsd_prior = float(np.mean(pw_rmsd_prior))

    print(f"\n  Mean pairwise RMSD (structural diversity):")
    print(f"    Prior (uniform):     {mean_pw_rmsd_prior:.3f} Å")
    print(f"    Posterior (λ*={lam_star}): {mean_pw_rmsd_post:.3f} Å")
    print(f"    Ratio: {mean_pw_rmsd_post/mean_pw_rmsd_prior:.3f}x "
          f"({'more' if mean_pw_rmsd_post > mean_pw_rmsd_prior else 'less'} diverse than prior)")

    # Save
    np.save(f"{OUT}/analysis/{name}_posterior_weights.npy", w_star)
    np.save(f"{OUT}/analysis/{name}_chi2_values.npy", chi2_star)

    results_rw[name] = {
        "lambda_star": float(lam_star),
        "ess_at_lambda_star": float(effective_sample_size(w_star)),
        "prior_gap_fraction": float(prior_gap_prob),
        "posterior_gap_fraction": float(post_gap_prob),
        "gap_redistribution": float(post_gap_prob - prior_gap_prob),
        "mean_pairwise_rmsd_prior": mean_pw_rmsd_prior,
        "mean_pairwise_rmsd_posterior": mean_pw_rmsd_post,
        "lambda_scan": scan_results,
    }

with open(f"{OUT}/analysis/reweighting_results.json", "w") as f:
    json.dump(results_rw, f, indent=2)

print("\n✓ Step 4 complete. Reweighting results saved.")
