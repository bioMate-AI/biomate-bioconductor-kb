"""
Pilot Step 3: Pocket Landscape Analysis.

Since fpocket requires full-atom PDB files, we approximate druggability
using a geometric proxy on Cα coordinates:
  - Local packing density: residues with few close neighbors are in
    surface-exposed loops/cavities
  - Pocket score = inverse of local Cα density in a 10Å sphere
    (high score = sparse local environment = potential pocket)
  - Cryptic pocket detection: compare pocket scores between the prior
    ensemble and cryoDRGN clusters to identify regions that open in
    BioEmu-only (gap) conformers

This is an approximation; the real pilot would run fpocket on full-atom
structures. Here we show the methodology and that the gap conformers
produce measurably different pocket landscapes.
"""

import numpy as np
import json, os

OUT = "/home/yzhang/biomate/pilot_study"
POCKET_RADIUS  = 10.0   # Å sphere for local density calculation
MIN_NEIGHBORS  = 3      # minimum neighbors to not be considered a pocket residue
TOP_K_POCKETS  = 5      # report top-K pocket sites per conformer


def compute_pocket_scores(coords_array):
    """
    For each conformer in coords_array (M, N_res, 3):
    Compute per-residue pocket score = 1 / (local_Cα_count + 1)
    Returns (M, N_res) pocket score matrix.
    Higher score = fewer local neighbors = more exposed/pocket-like.
    """
    M, N, _ = coords_array.shape
    scores = np.zeros((M, N), dtype=np.float32)
    for i in range(M):
        c = coords_array[i]  # (N, 3)
        # Pairwise distances
        diff = c[:, None, :] - c[None, :, :]   # (N, N, 3)
        dist = np.sqrt((diff ** 2).sum(axis=-1))  # (N, N)
        # Count neighbors within radius (excluding self)
        np.fill_diagonal(dist, 999.0)
        neighbor_count = (dist < POCKET_RADIUS).sum(axis=1).astype(np.float32)
        scores[i] = 1.0 / (neighbor_count + 1.0)
    return scores


def find_top_pocket_sites(scores, top_k=5):
    """
    Find top-K residue indices with highest mean pocket score across conformers.
    Returns sorted list of (residue_idx, mean_score).
    """
    mean_scores = scores.mean(axis=0)  # (N_res,)
    top_idx = np.argsort(mean_scores)[::-1][:top_k]
    return [(int(idx), float(mean_scores[idx])) for idx in top_idx]


results_pocket = {}

for name in ["beta2ar", "trpv1"]:
    print(f"\n=== {name.upper()} ===")

    prior   = np.load(f"{OUT}/conformers/{name}/prior_ensemble.npy")   # (500, N, 3)
    centers = np.load(f"{OUT}/cryodrgn_clusters/{name}/cluster_centers.npy")  # (K, N, 3)
    in_gap  = np.load(f"{OUT}/analysis/{name}_in_gap.npy")              # (500,) bool

    gap_conformers      = prior[in_gap]
    captured_conformers = prior[~in_gap]

    print(f"  Gap conformers: {len(gap_conformers)}  |  Captured: {len(captured_conformers)}")

    # ── Pocket scores ─────────────────────────────────────────────────────────
    print("  Computing pocket scores for cryoDRGN clusters...", end=" ", flush=True)
    scores_cryo     = compute_pocket_scores(centers)
    print("done.")

    print("  Computing pocket scores for gap conformers...", end=" ", flush=True)
    scores_gap      = compute_pocket_scores(gap_conformers) if len(gap_conformers) > 0 else np.zeros((0, prior.shape[1]))
    print("done.")

    print("  Computing pocket scores for captured conformers...", end=" ", flush=True)
    scores_captured = compute_pocket_scores(captured_conformers) if len(captured_conformers) > 0 else np.zeros((0, prior.shape[1]))
    print("done.")

    # ── Mean druggability comparison ──────────────────────────────────────────
    mean_cryo     = scores_cryo.max(axis=1).mean() if len(scores_cryo) > 0 else 0.0
    mean_gap      = scores_gap.max(axis=1).mean()  if len(scores_gap) > 0 else 0.0
    mean_captured = scores_captured.max(axis=1).mean() if len(scores_captured) > 0 else 0.0

    print(f"  Mean best-pocket score:")
    print(f"    cryoDRGN clusters:    {mean_cryo:.4f}")
    print(f"    Captured conformers:  {mean_captured:.4f}")
    print(f"    Gap conformers:       {mean_gap:.4f}  ← higher = more pocket exposure")
    pocket_enrichment = (mean_gap / mean_cryo - 1.0) * 100 if mean_cryo > 0 else 0.0
    print(f"  Gap-vs-cryoDRGN pocket enrichment: {pocket_enrichment:+.1f}%")

    # ── Top pocket sites comparison ───────────────────────────────────────────
    top_cryo = find_top_pocket_sites(scores_cryo, TOP_K_POCKETS)
    top_gap  = find_top_pocket_sites(scores_gap, TOP_K_POCKETS) if len(scores_gap) >= TOP_K_POCKETS else []

    cryo_residues = set(r for r, _ in top_cryo)
    gap_residues  = set(r for r, _ in top_gap)
    unique_gap_sites = gap_residues - cryo_residues
    shared_sites = gap_residues & cryo_residues

    print(f"  Top-{TOP_K_POCKETS} pocket residues:")
    print(f"    cryoDRGN: {[r for r,_ in top_cryo]}")
    print(f"    Gap-only: {[r for r,_ in top_gap]}")
    print(f"    Shared sites: {shared_sites}")
    print(f"    Novel gap-only sites: {unique_gap_sites}  ← cryptic pocket candidates")

    # Save scores
    os.makedirs(f"{OUT}/analysis", exist_ok=True)
    np.save(f"{OUT}/analysis/{name}_scores_cryo.npy",     scores_cryo)
    np.save(f"{OUT}/analysis/{name}_scores_gap.npy",      scores_gap)
    np.save(f"{OUT}/analysis/{name}_scores_captured.npy", scores_captured)

    results_pocket[name] = {
        "mean_pocket_score_cryodrgn":   float(mean_cryo),
        "mean_pocket_score_captured":   float(mean_captured),
        "mean_pocket_score_gap":        float(mean_gap),
        "pocket_enrichment_pct":        float(pocket_enrichment),
        "top_pocket_residues_cryodrgn": top_cryo,
        "top_pocket_residues_gap":      top_gap,
        "unique_gap_only_pocket_sites": list(unique_gap_sites),
        "shared_pocket_sites":          list(shared_sites),
    }

with open(f"{OUT}/analysis/pocket_analysis_results.json", "w") as f:
    json.dump(results_pocket, f, indent=2)

print("\n✓ Step 3 complete. Pocket analysis saved.")
