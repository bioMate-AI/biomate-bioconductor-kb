"""Real-data demo with diversity-injected prior.

Variation on run_real_data_demo: replaces the homogeneous BioEmu prior with a
mix of (a) the actual cryo-EM reference structure (chain A of the input PDB) and
(b) deliberately-perturbed alternatives. Since the EMPIAR particles physically
correspond to (a), the per-particle posterior MUST concentrate weight on the
reference-derived conformers if the pipeline is working correctly.

This validates the pipeline on real data without needing a multi-state generative
prior in hand.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cryoensemble.dps import DPSConfig, reweight_prior
from cryoensemble.evaluate import evaluate, save_results, kabsch_rmsd
from cryoensemble.scripts.run_real_data_demo import (
    load_prior_from_tarball,
    load_real_particles_subset,
    load_cryodrgn_pose,
    load_cryodrgn_ctf,
)


def load_pdb_chainA_calpha(pdb_path: str) -> np.ndarray:
    coords = []
    with open(pdb_path) as f:
        for line in f:
            if line.startswith("ATOM") and line[12:16].strip() == "CA" and line[21] == "A":
                coords.append([float(line[30:38]), float(line[38:46]), float(line[46:54])])
    return np.asarray(coords, dtype=np.float32)


def load_pdb_all_chains_calpha(pdb_path: str) -> np.ndarray:
    """Load Cα coords across ALL chains — needed when particles are oligomeric assemblies.

    Returns concatenated Cα coords in PDB order.
    """
    coords = []
    for line in open(pdb_path):
        if line.startswith("ATOM") and line[12:16].strip() == "CA":
            coords.append([float(line[30:38]), float(line[38:46]), float(line[46:54])])
    return np.asarray(coords, dtype=np.float32)


def build_diverse_prior(
    reference_pdb: str,
    bioemu_tarball: str | None,
    n_reference_perturbations: int = 20,
    n_bioemu: int = 20,
    n_random_shuffled: int = 10,
    perturb_sigma: float = 0.5,
    perturb_strong: float = 5.0,
    use_full_assembly: bool = False,
    seed: int = 0,
) -> tuple[torch.Tensor, np.ndarray]:
    """Build a structurally diverse prior.

    Blocks:
      ref           : small-σ perturbations of the reference structure
      ref_strong    : large-σ perturbations (closer to a "wrong" state)
      bioemu        : BioEmu conformers (only if use_full_assembly is False — BioEmu
                      is monomer-only, can't be mixed with a tetramer reference)
      decoy         : Cα-shuffled reference (preserves point cloud, breaks topology)

    If use_full_assembly=True, loads ALL chains from the reference PDB so the
    prior atom count matches the particle's full oligomeric assembly.
    """
    rng = np.random.default_rng(seed)

    if use_full_assembly:
        ref = load_pdb_all_chains_calpha(reference_pdb)
    else:
        ref = load_pdb_chainA_calpha(reference_pdb)
    ref = ref - ref.mean(0)

    bio = None
    if (not use_full_assembly) and bioemu_tarball and n_bioemu > 0:
        bio_t = load_prior_from_tarball(bioemu_tarball, n_max=n_bioemu, chain="A")
        bio = bio_t.numpy()
        n_common = min(ref.shape[0], bio.shape[1])
        ref = ref[:n_common]
        bio = bio[:, :n_common, :]
    n_atoms = ref.shape[0]

    perturbed_ref = np.stack([
        ref + rng.normal(0, perturb_sigma, ref.shape).astype(np.float32)
        for _ in range(n_reference_perturbations)
    ])

    # Strong perturbations (~5 Å rms) — should look "wrong but plausible"
    strong = np.stack([
        ref + rng.normal(0, perturb_strong, ref.shape).astype(np.float32)
        for _ in range(n_reference_perturbations)
    ])

    # decoys: shuffle the order of Cα atoms → preserves point cloud but breaks structure
    decoys = np.stack([
        ref[rng.permutation(n_atoms)] for _ in range(n_random_shuffled)
    ])

    blocks = [perturbed_ref, strong, decoys]
    labels_list = (["ref"] * n_reference_perturbations
                   + ["ref_strong"] * n_reference_perturbations
                   + ["decoy"] * n_random_shuffled)
    if bio is not None:
        blocks.insert(1, bio)
        labels_list = (["ref"] * n_reference_perturbations
                       + ["bioemu"] * n_bioemu
                       + ["ref_strong"] * n_reference_perturbations
                       + ["decoy"] * n_random_shuffled)

    prior = np.concatenate(blocks, axis=0).astype(np.float32)
    prior = prior - prior.mean(axis=1, keepdims=True)
    return torch.from_numpy(prior), np.array(labels_list)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reference_pdb", required=True)
    ap.add_argument("--prior_tarball", default=None)
    ap.add_argument("--use_full_assembly", action="store_true",
                    help="Use all chains of the reference PDB (for oligomeric particles)")
    ap.add_argument("--particles_dir", required=True)
    ap.add_argument("--star", required=True)
    ap.add_argument("--pose_pkl", required=True)
    ap.add_argument("--ctf_pkl", required=True)
    ap.add_argument("--n_particles", type=int, default=200)
    ap.add_argument("--n_ref_perturb", type=int, default=20)
    ap.add_argument("--n_bioemu", type=int, default=20)
    ap.add_argument("--n_decoys", type=int, default=10)
    ap.add_argument("--box_size", type=int, default=192)
    ap.add_argument("--apix", type=float, default=3.768)
    ap.add_argument("--sigma_noise", type=float, default=1.0)
    ap.add_argument("--sigma_a", type=float, default=2.0)
    ap.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    ap.add_argument("--outdir", default="./cryoensemble_diversity_out")
    args = ap.parse_args()

    print(f"[demo] device={args.device}")
    print(f"[demo] building diverse prior  (ref={args.n_ref_perturb}, "
          f"bioemu={args.n_bioemu}, decoy={args.n_decoys})…")
    prior, labels = build_diverse_prior(
        args.reference_pdb, args.prior_tarball,
        n_reference_perturbations=args.n_ref_perturb,
        n_bioemu=args.n_bioemu, n_random_shuffled=args.n_decoys,
        use_full_assembly=args.use_full_assembly,
    )
    print(f"  prior shape: {prior.shape}, labels: {dict(zip(*np.unique(labels, return_counts=True)))}")

    print(f"[demo] loading particles…")
    images, sel_idx = load_real_particles_subset(args.star, args.particles_dir,
                                                  n_keep=args.n_particles,
                                                  box_size=args.box_size)
    print(f"  images: {images.shape}")

    R, t = load_cryodrgn_pose(args.pose_pkl, sel_idx, D=args.box_size, apix=args.apix)
    ctf_params = load_cryodrgn_ctf(args.ctf_pkl, sel_idx)

    prior = prior.to(args.device)
    images = images.to(args.device)
    R = R.to(args.device)
    t = t.to(args.device)
    ctf_dev = {k: v.to(args.device) if isinstance(v, torch.Tensor) else v
               for k, v in ctf_params.items()}

    cfg = DPSConfig(
        D=args.box_size, apix=args.apix,
        sigma_a=args.sigma_a, sigma_noise=args.sigma_noise,
        particle_batch=16,
    )

    print(f"[demo] running per-particle posterior  (EM mixture)…")
    summary, raw = evaluate(prior, images, R, t, ctf_dev, cfg)
    post = raw["posterior"].numpy()

    # Aggregate mass by block
    masses = {lab: float(post[labels == lab].sum()) for lab in np.unique(labels)}
    print(f"\n=== Posterior mass by block ===")
    for lab, m in masses.items():
        bar = "█" * int(m * 60)
        print(f"  {lab:8s}  {m:.4f}  {bar}")

    print(f"\n=== Posterior summary ===")
    print(f"  ESS: {summary.posterior_ess:.2f} / {summary.n_conformers}")
    print(f"  Max weight: {summary.posterior_max_weight:.4f}")
    print(f"  Entropy: {summary.posterior_entropy_bits:.2f} bits")

    print(f"\n=== Top 10 conformers ===")
    order = np.argsort(post)[::-1]
    for r, i in enumerate(order[:10]):
        bar = "█" * int(post[i] * 80)
        print(f"  rank {r:02d}  conf #{i:03d}  block={labels[i]:6s}  w={post[i]:.4f}  {bar}")

    save_results(summary, raw, args.outdir)
    # also save block labels for downstream analysis
    np.save(Path(args.outdir) / "labels.npy", labels)
    print(f"\nSaved to {args.outdir}/")

    # Hypothesis check: ref block should win heavily over decoys per-conformer
    n_ref = (labels == "ref").sum()
    n_decoy = (labels == "decoy").sum()
    ref_per = masses.get("ref", 0) / max(n_ref, 1)
    decoy_per = masses.get("decoy", 0) / max(n_decoy, 1)
    print(f"\nPer-conformer mean weight:  ref={ref_per:.4f}   decoy={decoy_per:.4f}")
    print(f"Hypothesis check {'PASSED' if ref_per > 2 * decoy_per else 'FAILED'}: "
          f"ref conformers should have ≥2× the per-conformer weight of decoys")


if __name__ == "__main__":
    main()
