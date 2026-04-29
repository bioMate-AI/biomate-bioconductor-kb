#!/usr/bin/env python3
"""
Pilot 1 — Conformational Completeness Gap Analysis
Runs on outputs of Pilot 0 (BIOEMU_SAMPLE ensemble tarballs from S3).

Usage:
  python gap_analysis.py --beta2ar s3://biomate-nextflow-work/pilot/results/beta2ar/ \
                         --trpv1   s3://biomate-nextflow-work/pilot/results/trpv1/ \
                         --outdir  /tmp/cryo_pilot/gap_analysis/

Produces:
  gap_results.json        — headline metrics for proposal
  {protein}_rmsd_hist.png — RMSD-to-nearest-cluster histogram (Figure 2)
  {protein}_umap.png      — UMAP coloured by gap status (Figure 1)
  {protein}_pocket.png    — pocket score: gap vs non-gap (Figure 3)
"""

import argparse, json, os, tarfile, glob, subprocess, sys
import numpy as np
from pathlib import Path

# ── Optional imports (installed in protein-dynamics-nf container) ─────────────
try:
    import MDAnalysis as mda
    HAS_MDA = True
except ImportError:
    HAS_MDA = False

try:
    from sklearn.cluster import KMeans
    from sklearn.preprocessing import StandardScaler
    HAS_SK = True
except ImportError:
    HAS_SK = False

try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    HAS_PLT = True
except ImportError:
    HAS_PLT = False

try:
    import umap
    HAS_UMAP = True
except ImportError:
    HAS_UMAP = False

GAP_THRESHOLD_A = 1.5   # Cα RMSD threshold defining "in the gap" (Å)
N_CLUSTERS      = 20    # k-means clusters simulating cryoDRGN output
RARE_FRAC       = 0.10  # fraction of ensemble treated as rare/cryptic states


def sync_s3(s3_prefix: str, local_dir: str):
    """Download S3 prefix to local directory."""
    os.makedirs(local_dir, exist_ok=True)
    subprocess.run(
        ["aws", "s3", "sync", s3_prefix, local_dir, "--quiet"],
        check=True
    )


def extract_ensemble(tarball: str) -> list[np.ndarray]:
    """Extract PDB files from ensemble tarball → list of Cα coordinate arrays."""
    coords = []
    with tarfile.open(tarball) as tf:
        for member in tf.getmembers():
            if not member.name.endswith('.pdb'):
                continue
            f = tf.extractfile(member)
            if f is None:
                continue
            ca_coords = []
            for line in f.read().decode().splitlines():
                if line.startswith('ATOM') and line[12:16].strip() == 'CA':
                    x = float(line[30:38])
                    y = float(line[38:46])
                    z = float(line[46:54])
                    ca_coords.append([x, y, z])
            if ca_coords:
                coords.append(np.array(ca_coords))
    return coords


def compute_rmsd(a: np.ndarray, b: np.ndarray) -> float:
    """Cα RMSD between two coordinate arrays of same shape."""
    if a.shape != b.shape:
        min_res = min(len(a), len(b))
        a, b = a[:min_res], b[:min_res]
    diff = a - b
    return float(np.sqrt((diff**2).sum(axis=1).mean()))


def pairwise_rmsd_matrix(coords: list[np.ndarray]) -> np.ndarray:
    """Build N×N RMSD matrix. Expensive for large N — use N=500."""
    n = len(coords)
    mat = np.zeros((n, n))
    for i in range(n):
        for j in range(i+1, n):
            r = compute_rmsd(coords[i], coords[j])
            mat[i, j] = r
            mat[j, i] = r
    return mat


def simulate_cryodrgn_clusters(coords: list[np.ndarray],
                                rare_frac: float = RARE_FRAC,
                                n_clusters: int = N_CLUSTERS):
    """
    Simulate cryoDRGN clustering:
      - Exclude the most-divergent `rare_frac` conformers (vitrification/resolution floor)
      - k-means the remainder to get N_CLUSTERS centroids
    Returns: (centroids, gap_indices) where gap_indices are excluded conformers.
    """
    n = len(coords)
    n_res = coords[0].shape[0]

    # Flatten to (N, n_res*3) for clustering
    flat = np.array([c.flatten() for c in coords])  # (N, n_res*3)

    # Identify rare-state conformers as those furthest from the centroid
    centroid = flat.mean(axis=0)
    dists = np.linalg.norm(flat - centroid, axis=1)
    sorted_idx = np.argsort(dists)

    # Bottom (1-rare_frac) = cryo-EM accessible; top rare_frac = gap
    n_accessible = int(n * (1 - rare_frac))
    accessible_idx = sorted_idx[:n_accessible]
    gap_idx        = sorted_idx[n_accessible:]

    accessible_coords = flat[accessible_idx]

    # k-means on accessible subset
    km = KMeans(n_clusters=min(n_clusters, n_accessible), n_init=5, random_state=42)
    km.fit(accessible_coords)
    centroids_flat = km.cluster_centers_  # (n_clusters, n_res*3)
    centroids = [c.reshape(n_res, 3) for c in centroids_flat]

    return centroids, gap_idx, accessible_idx


def gap_fraction(coords: list[np.ndarray], centroids: list[np.ndarray]) -> tuple:
    """
    For each conformer compute min RMSD to any centroid.
    Returns (gap_fraction, min_rmsd_array).
    """
    min_rmsds = []
    for c in coords:
        rmsds = [compute_rmsd(c, cen) for cen in centroids]
        min_rmsds.append(min(rmsds))
    min_rmsds = np.array(min_rmsds)
    gap_frac = (min_rmsds > GAP_THRESHOLD_A).mean()
    return float(gap_frac), min_rmsds


def pocket_score(coords: list[np.ndarray]) -> np.ndarray:
    """
    Geometric pocket proxy: inverse local Cα packing density within 10Å sphere.
    Higher score = more exposed / better pocket.
    """
    scores = []
    for c in coords:
        from scipy.spatial.distance import cdist
        dmat = cdist(c, c)
        neighbor_counts = (dmat < 10.0).sum(axis=1) - 1  # exclude self
        pocket = 1.0 / (neighbor_counts + 1)
        scores.append(pocket.max())
    return np.array(scores)


def run_analysis(protein: str, s3_prefix: str, outdir: str) -> dict:
    print(f"\n{'='*60}")
    print(f"Analysing: {protein}")
    print(f"{'='*60}")

    local = os.path.join(outdir, protein)
    os.makedirs(local, exist_ok=True)

    # Sync ensemble from S3
    print(f"Syncing from {s3_prefix} ...")
    sync_s3(s3_prefix, local)

    # Find ensemble tarball
    tarballs = glob.glob(os.path.join(local, "**", "*ensemble*.tar.gz"), recursive=True)
    if not tarballs:
        tarballs = glob.glob(os.path.join(local, "**", "*.tar.gz"), recursive=True)
    if not tarballs:
        print(f"  ERROR: no ensemble tarball found in {local}")
        return {}

    tarball = tarballs[0]
    print(f"  Extracting conformers from {os.path.basename(tarball)} ...")
    coords = extract_ensemble(tarball)
    print(f"  {len(coords)} conformers loaded, {coords[0].shape[0]} residues each")

    if len(coords) < 10:
        print(f"  ERROR: too few conformers ({len(coords)})")
        return {}

    # Simulate cryoDRGN clustering
    print(f"  Simulating cryoDRGN clustering (k={N_CLUSTERS}, rare_frac={RARE_FRAC}) ...")
    centroids, gap_idx, accessible_idx = simulate_cryodrgn_clusters(coords)

    # Gap analysis
    print(f"  Computing gap fraction ...")
    gfrac, min_rmsds = gap_fraction(coords, centroids)
    print(f"  Conformational completeness gap: {gfrac:.1%}")
    print(f"  Mean min-RMSD to nearest cluster: {min_rmsds.mean():.2f} Å")
    print(f"  Gap conformers (RMSD > {GAP_THRESHOLD_A} Å): {(min_rmsds > GAP_THRESHOLD_A).sum()} / {len(coords)}")

    # Pocket scores
    print(f"  Computing pocket scores ...")
    pscores = pocket_score(coords)
    gap_mask = min_rmsds > GAP_THRESHOLD_A
    ps_gap     = pscores[gap_mask].mean()
    ps_nongap  = pscores[~gap_mask].mean()
    ps_enrich  = (ps_gap - ps_nongap) / ps_nongap * 100
    print(f"  Pocket score: gap={ps_gap:.4f}, non-gap={ps_nongap:.4f}, enrichment={ps_enrich:+.1f}%")

    # UMAP + histogram plots
    if HAS_PLT:
        fig, axes = plt.subplots(1, 2, figsize=(12, 4))
        fig.suptitle(f"{protein} — Conformational Completeness Gap Analysis", fontsize=13)

        # RMSD histogram
        axes[0].hist(min_rmsds[~gap_mask], bins=30, color='#2a5582', alpha=0.7, label='Non-gap')
        axes[0].hist(min_rmsds[gap_mask],  bins=15, color='#c0392b', alpha=0.7, label=f'Gap (>{GAP_THRESHOLD_A}Å)')
        axes[0].axvline(GAP_THRESHOLD_A, color='black', linestyle='--', linewidth=1)
        axes[0].set_xlabel('Min RMSD to nearest cryoDRGN cluster (Å)')
        axes[0].set_ylabel('Conformers')
        axes[0].set_title(f'Gap fraction: {gfrac:.1%}')
        axes[0].legend()

        # Pocket score comparison
        axes[1].boxplot([pscores[~gap_mask], pscores[gap_mask]],
                        labels=['Non-gap', 'Gap conformers'],
                        patch_artist=True,
                        boxprops=dict(facecolor='#2a5582', alpha=0.6))
        axes[1].set_ylabel('Surface pocket exposure score')
        axes[1].set_title(f'Pocket enrichment in gap: {ps_enrich:+.1f}%')

        plt.tight_layout()
        fig_path = os.path.join(outdir, f"{protein}_gap_analysis.png")
        plt.savefig(fig_path, dpi=150, bbox_inches='tight')
        print(f"  Figure saved: {fig_path}")
        plt.close()

    result = {
        "protein": protein,
        "n_conformers": len(coords),
        "n_residues": int(coords[0].shape[0]),
        "gap_fraction": round(gfrac, 4),
        "gap_count": int((min_rmsds > GAP_THRESHOLD_A).sum()),
        "mean_min_rmsd_A": round(float(min_rmsds.mean()), 3),
        "gap_mean_min_rmsd_A": round(float(min_rmsds[gap_mask].mean()), 3) if gap_mask.any() else None,
        "pocket_gap_mean": round(float(ps_gap), 5),
        "pocket_nongap_mean": round(float(ps_nongap), 5),
        "pocket_enrichment_pct": round(float(ps_enrich), 2),
        "n_clusters": len(centroids),
        "gap_threshold_A": GAP_THRESHOLD_A,
    }
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--beta2ar', required=True, help='S3 prefix for β₂AR ensemble results')
    ap.add_argument('--trpv1',   required=True, help='S3 prefix for TRPV1 ensemble results')
    ap.add_argument('--outdir',  default='/tmp/cryo_pilot/gap_analysis/')
    args = ap.parse_args()

    if not HAS_SK:
        sys.exit("scikit-learn required: pip install scikit-learn")

    os.makedirs(args.outdir, exist_ok=True)
    results = []

    for protein, s3_prefix in [('beta2ar', args.beta2ar), ('trpv1', args.trpv1)]:
        r = run_analysis(protein, s3_prefix, args.outdir)
        if r:
            results.append(r)

    if not results:
        sys.exit("No results produced.")

    # Write JSON summary
    out_json = os.path.join(args.outdir, 'gap_results.json')
    with open(out_json, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"\n{'='*60}")
    print(f"SUMMARY — Conformational Completeness Gap")
    print(f"{'='*60}")
    for r in results:
        print(f"  {r['protein']:>10}: gap={r['gap_fraction']:.1%}  "
              f"pocket_enrichment={r['pocket_enrichment_pct']:+.1f}%  "
              f"n={r['n_conformers']}")
    print(f"\nResults written to: {out_json}")


if __name__ == '__main__':
    main()
