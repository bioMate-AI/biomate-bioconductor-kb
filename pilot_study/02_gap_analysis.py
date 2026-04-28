"""
Pilot Step 2: Gap Analysis — Prior Ensemble vs cryoDRGN Clusters.

For each conformer in the prior ensemble, compute:
  - RMSD to the nearest cryoDRGN cluster centroid
  - Whether it is "captured" (RMSD < threshold) or "in the gap"

The gap fraction is the headline number for the grant proposal:
  "X% of the conformational ensemble is not captured by cryoDRGN"

Also computes per-type breakdown (local/domain/rare) and saves all
results for downstream reweighting and plotting.
"""

import numpy as np
import json, os

OUT = "/home/yzhang/biomate/pilot_study"
GAP_THRESHOLD_AA = 1.5   # Å RMSD — conformers farther than this from any
                          # cryoDRGN cluster are considered "in the gap"


def rmsd_matrix(A, B):
    """
    Compute pairwise RMSD between two sets of Cα coordinate arrays.
    A: (M, N_res, 3)   B: (K, N_res, 3)
    Returns: (M, K) RMSD matrix
    """
    M, N, _ = A.shape
    K = B.shape[0]
    # Flatten: (M, N*3), (K, N*3)
    Af = A.reshape(M, -1).astype(np.float64)
    Bf = B.reshape(K, -1).astype(np.float64)
    # ||A_i - B_j||^2 = ||A_i||^2 + ||B_j||^2 - 2 A_i·B_j
    AA = (Af ** 2).sum(axis=1, keepdims=True)   # (M,1)
    BB = (Bf ** 2).sum(axis=1, keepdims=True).T  # (1,K)
    AB = Af @ Bf.T                               # (M,K)
    sq = np.maximum(AA + BB - 2 * AB, 0)         # (M,K) numerical stability
    rmsd = np.sqrt(sq / N)                        # per-atom RMSD
    return rmsd.astype(np.float32)


results = {}

for name in ["beta2ar", "trpv1"]:
    print(f"\n=== {name.upper()} ===")

    prior    = np.load(f"{OUT}/conformers/{name}/prior_ensemble.npy")    # (500, N_res, 3)
    centers  = np.load(f"{OUT}/cryodrgn_clusters/{name}/cluster_centers.npy")  # (K_vis, N_res, 3)
    weights  = np.load(f"{OUT}/cryodrgn_clusters/{name}/cluster_weights.npy")  # (K_vis,)

    with open(f"{OUT}/conformers/{name}/prior_labels.json") as f:
        labels = json.load(f)
    labels = np.array(labels)

    # ── A. Full pairwise RMSD matrix ─────────────────────────────────────────
    print(f"  Computing {len(prior)}×{len(centers)} RMSD matrix...", end=" ", flush=True)
    rmat = rmsd_matrix(prior, centers)   # (500, K_vis)
    print("done.")

    # ── B. Nearest-cluster RMSD per conformer ─────────────────────────────────
    min_rmsd = rmat.min(axis=1)           # (500,)
    nearest_cluster = rmat.argmin(axis=1) # (500,)

    in_gap    = min_rmsd > GAP_THRESHOLD_AA
    captured  = ~in_gap
    gap_frac  = in_gap.mean()

    print(f"  Gap fraction (RMSD > {GAP_THRESHOLD_AA} Å): {gap_frac:.1%}")
    print(f"  Captured: {captured.sum()}  |  In gap: {in_gap.sum()}")

    # ── C. Breakdown by conformer type ───────────────────────────────────────
    type_stats = {}
    for t in ["local", "domain", "rare"]:
        mask = labels == t
        g = in_gap[mask].mean() if mask.sum() > 0 else 0.0
        type_stats[t] = {
            "count": int(mask.sum()),
            "gap_fraction": float(g),
            "mean_min_rmsd": float(min_rmsd[mask].mean()),
            "max_min_rmsd": float(min_rmsd[mask].max()),
        }
        print(f"    {t:8s}: n={mask.sum():3d}  gap={g:.1%}  "
              f"mean_RMSD={min_rmsd[mask].mean():.2f} Å  max={min_rmsd[mask].max():.2f} Å")

    # ── D. Coverage of cryoDRGN clusters by prior ────────────────────────────
    # For each cryoDRGN cluster, find its nearest prior conformer
    rmat_T = rmat.T  # (K_vis, 500)
    cluster_nearest_rmsd = rmat_T.min(axis=1)
    cluster_coverage = (cluster_nearest_rmsd < GAP_THRESHOLD_AA).mean()
    print(f"  cryoDRGN cluster coverage by prior: {cluster_coverage:.1%} "
          f"(clusters that have a near prior analog)")

    # ── E. RMSD distribution statistics ──────────────────────────────────────
    pct = np.percentile(min_rmsd, [25, 50, 75, 90, 95, 99])
    print(f"  Min-RMSD percentiles: "
          f"p25={pct[0]:.2f} p50={pct[1]:.2f} p75={pct[2]:.2f} "
          f"p90={pct[3]:.2f} p95={pct[4]:.2f} p99={pct[5]:.2f} Å")

    # ── Save ─────────────────────────────────────────────────────────────────
    np.save(f"{OUT}/analysis/{name}_rmsd_matrix.npy", rmat)
    np.save(f"{OUT}/analysis/{name}_min_rmsd.npy", min_rmsd)
    np.save(f"{OUT}/analysis/{name}_in_gap.npy", in_gap)
    np.save(f"{OUT}/analysis/{name}_nearest_cluster.npy", nearest_cluster)

    results[name] = {
        "n_prior": int(len(prior)),
        "n_cryodrgn_clusters": int(len(centers)),
        "gap_threshold_angstrom": GAP_THRESHOLD_AA,
        "gap_fraction": float(gap_frac),
        "captured_count": int(captured.sum()),
        "gap_count": int(in_gap.sum()),
        "type_breakdown": type_stats,
        "cluster_coverage": float(cluster_coverage),
        "rmsd_percentiles": {
            "p25": float(pct[0]), "p50": float(pct[1]), "p75": float(pct[2]),
            "p90": float(pct[3]), "p95": float(pct[4]), "p99": float(pct[5])
        }
    }

with open(f"{OUT}/analysis/gap_analysis_results.json", "w") as f:
    json.dump(results, f, indent=2)

print("\n✓ Step 2 complete. Gap analysis results saved.")
