"""Baseline implementations: BME (map-level) and cryoDRGN-style k-means clustering.

These are reference baselines for Experiment A in EXPERIMENTAL_DESIGN.md.
They share our codebase's I/O so the comparison against CryoEnsemble is apples-to-apples.

BME (Bayesian Maximum Entropy / map-level reweighting):
    - Following cryoENsemble (Bonomi 2018) and EMMIVox (Hummer 2024):
      reweight a prior conformer ensemble against a cluster-of-particles map
      (the cryo-EM reconstruction), not against individual particles.
    - Key consequence: low-population states are absent from the map's clusters
      (resolution floor), so their likelihood under the map is essentially
      uniform across conformers → BME cannot move probability mass to them.

cryoDRGN-style k-means (data-only):
    - Following Zhong 2021: cluster particle images directly (after a learned
      embedding, here a simpler PCA/centroid surrogate) and treat clusters as
      "discovered conformational states". States below the resolution floor
      (~3–5% of particles) merge into noise clusters.
"""

from __future__ import annotations

import torch
import numpy as np
from sklearn.cluster import KMeans

from .forward_model import render_particle
from .likelihood import per_particle_log_likelihood, aggregate_posterior


# ──────────────────────────────────────────────────────────────────────────────
# Baseline 1: BME / map-level reweighting (cryoENsemble-style)
# ──────────────────────────────────────────────────────────────────────────────

def bme_reweight(
    prior_coords: torch.Tensor,             # (n_conf, n_atoms, 3)
    particles: torch.Tensor,                # (n_part, D, D)
    R: torch.Tensor,                        # (n_part, 3, 3)
    t: torch.Tensor,                        # (n_part, 2)
    ctf_params: dict,
    *,
    D: int,
    apix: float,
    sigma_a: float,
    sigma_noise: float,
    n_clusters: int = 20,
    rare_frac_excluded: float = 0.10,        # below this, merged as noise
    lambda_: float = 1.0,
    prior_weights: torch.Tensor | None = None,
) -> dict:
    """Map-level reweighting baseline.

    Steps:
    1. Cluster particles into n_clusters reconstruction clusters
       (simulates cryoDRGN/cryoSPARC heterogeneity output).
    2. The rare_frac_excluded smallest clusters are discarded as noise
       (simulates the particle-count resolution floor — sub-population states
       are not reconstructed into a map).
    3. For each retained cluster, compute the average image (the "reconstruction").
    4. For each prior conformer, compute log L wrt each cluster centroid.
    5. Cluster-weight-averaged log L per conformer:
           log L_i = log Σ_k (n_k / N) · exp(log L(conformer_i | cluster_k))
    6. Posterior ∝ exp(λ · log L_i)
    """
    device = particles.device
    n_part = particles.shape[0]
    n_conf = prior_coords.shape[0]

    # Flatten + cluster particles in image space (1D)
    flat = particles.reshape(n_part, -1).cpu().numpy()
    km = KMeans(n_clusters=min(n_clusters, n_part), n_init=10, random_state=42)
    labels = km.fit_predict(flat)

    cluster_sizes = np.bincount(labels, minlength=n_clusters)
    # Drop sub-resolution-floor clusters
    threshold = max(1, int(rare_frac_excluded * n_part / n_clusters))
    retained = np.where(cluster_sizes > threshold)[0]
    if retained.size == 0:
        retained = np.array([np.argmax(cluster_sizes)])

    # Cluster-average images (the "reconstructed maps")
    cluster_images = []
    cluster_weights = []
    for k in retained:
        mask = labels == k
        if mask.sum() == 0:
            continue
        avg = particles[torch.tensor(mask, device=device)].mean(dim=0, keepdim=True)
        cluster_images.append(avg)
        cluster_weights.append(int(mask.sum()))
    cluster_images = torch.cat(cluster_images, dim=0)           # (K_eff, D, D)
    cluster_weights = torch.tensor(cluster_weights, dtype=torch.float32, device=device)
    cluster_weights = cluster_weights / cluster_weights.sum()

    # For each conformer, render at the *average pose* of each cluster
    # (Standard BME uses the reconstruction's volume; we approximate by averaging
    #  per-particle poses within each cluster as the cluster's "reference pose")
    cluster_R = torch.zeros(cluster_images.shape[0], 3, 3, device=device, dtype=R.dtype)
    cluster_t = torch.zeros(cluster_images.shape[0], 2, device=device, dtype=t.dtype)
    cluster_ctf = {k: torch.zeros(cluster_images.shape[0], device=device, dtype=v.dtype)
                   if isinstance(v, torch.Tensor) else v
                   for k, v in ctf_params.items()}
    for ki, k in enumerate(retained):
        mask = labels == k
        if mask.sum() == 0:
            continue
        idx_t = torch.tensor(np.where(mask)[0], device=device)
        # average pose of cluster — for rotations, project to nearest valid rotation via SVD
        Ravg = R[idx_t].mean(dim=0)
        U, _, Vt = torch.linalg.svd(Ravg)
        cluster_R[ki] = U @ Vt
        cluster_t[ki] = t[idx_t].mean(dim=0)
        for kc, v in ctf_params.items():
            if isinstance(v, torch.Tensor):
                cluster_ctf[kc][ki] = v[idx_t].mean()

    # Compute log L for each (conformer, cluster) pair
    log_p = torch.zeros(n_conf, cluster_images.shape[0], device=device, dtype=particles.dtype)
    for i in range(n_conf):
        ll = per_particle_log_likelihood(
            prior_coords[i], cluster_images, cluster_R, cluster_t, cluster_ctf,
            D=D, apix=apix, sigma_a=sigma_a, sigma_noise=sigma_noise,
        )
        log_p[i] = ll

    # Weighted log evidence per conformer
    log_w = torch.log(cluster_weights + 1e-30).unsqueeze(0)      # (1, K_eff)
    log_evidence = torch.logsumexp(log_w + lambda_ * log_p, dim=-1)
    if prior_weights is not None:
        log_evidence = log_evidence + torch.log(prior_weights + 1e-30)
    log_evidence = log_evidence - log_evidence.max()
    w = torch.exp(log_evidence)
    posterior = w / w.sum()
    ess = (1.0 / (posterior ** 2).sum()).item()

    return {
        "log_evidence": log_evidence.detach().cpu(),
        "posterior": posterior.detach().cpu(),
        "ess": ess,
        "n_clusters_retained": int(retained.size),
        "cluster_sizes": cluster_sizes.tolist(),
    }


# ──────────────────────────────────────────────────────────────────────────────
# Baseline 2: cryoDRGN-style data-only k-means (no prior)
# ──────────────────────────────────────────────────────────────────────────────

def cryodrgn_kmeans_clustering(
    particles: torch.Tensor,                # (n_part, D, D)
    n_clusters: int = 20,
    rare_frac_excluded: float = 0.10,
) -> dict:
    """Data-only clustering baseline (no prior conformer ensemble).

    Returns per-cluster centroid images and cluster sizes.
    To compare against a prior, the calling code can compute RMSD-equivalent
    nearest-neighbour assignments from prior conformers to cluster centroids.
    """
    n_part = particles.shape[0]
    flat = particles.reshape(n_part, -1).cpu().numpy()
    km = KMeans(n_clusters=min(n_clusters, n_part), n_init=10, random_state=42)
    labels = km.fit_predict(flat)
    cluster_sizes = np.bincount(labels, minlength=n_clusters).tolist()
    threshold = max(1, int(rare_frac_excluded * n_part / n_clusters))
    retained = [k for k in range(n_clusters) if cluster_sizes[k] > threshold]

    return {
        "labels": labels,
        "cluster_sizes": cluster_sizes,
        "centroid_images": torch.from_numpy(km.cluster_centers_.reshape(n_clusters, *particles.shape[1:])),
        "retained_clusters": retained,
    }


def evaluate_cryodrgn_on_prior(
    prior_coords: torch.Tensor,
    cluster_result: dict,
    *,
    poses_per_cluster: torch.Tensor,
    ctf_per_cluster: dict,
    D: int,
    apix: float,
    sigma_a: float,
    sigma_noise: float,
) -> dict:
    """For each prior conformer, find its nearest cluster centroid by log-likelihood.

    A prior conformer is 'recovered' iff there is a retained cluster whose centroid
    is the best-matching cluster for it. The fraction of prior weight that lands
    on retained clusters is the posterior-mass equivalent.
    """
    centroids = cluster_result["centroid_images"].to(prior_coords.device)
    retained = set(cluster_result["retained_clusters"])

    n_conf = prior_coords.shape[0]
    log_p = torch.zeros(n_conf, centroids.shape[0], device=prior_coords.device, dtype=prior_coords.dtype)
    for i in range(n_conf):
        ll = per_particle_log_likelihood(
            prior_coords[i], centroids,
            poses_per_cluster["R"], poses_per_cluster["t"], ctf_per_cluster,
            D=D, apix=apix, sigma_a=sigma_a, sigma_noise=sigma_noise,
        )
        log_p[i] = ll

    best_cluster_per_conformer = log_p.argmax(dim=1).cpu().numpy()
    recovered_mask = torch.tensor([
        int(c) in retained for c in best_cluster_per_conformer
    ])
    # Posterior weight = uniform over conformers whose best cluster is retained
    posterior = recovered_mask.float() / recovered_mask.sum().clamp_min(1)
    return {
        "posterior": posterior,
        "n_recovered": int(recovered_mask.sum().item()),
        "best_cluster_per_conformer": best_cluster_per_conformer,
    }


__all__ = ["bme_reweight", "cryodrgn_kmeans_clustering", "evaluate_cryodrgn_on_prior"]
