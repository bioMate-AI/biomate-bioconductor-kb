#!/usr/bin/env python3
"""
generate_cryo_heterogeneity_test.py

Generates a minimal synthetic cryo-EM test dataset for pipeline validation:
  - cryo_het_test_particles.mrcs : 50 particles, 64×64 pixels
                                   25 from "state A" (soft sphere) +
                                   25 from "state B" (soft sphere + offset lobe)
  - cryo_het_test_ctf.pkl        : matching CTF parameters in cryoDRGN format

Usage:
    python generate_cryo_heterogeneity_test.py [--outdir test_data/]

Then run on AWS Batch:
    nextflow run workflows/cryo_em_heterogeneity.nf \\
        -profile aws \\
        --particles s3://biomate-nextflow-work/test-inputs/cryo-het/cryo_het_test_particles.mrcs \\
        --ctf      s3://biomate-nextflow-work/test-inputs/cryo-het/cryo_het_test_ctf.pkl \\
        --poses    s3://biomate-nextflow-work/test-inputs/cryo-het/cryo_het_test_poses.pkl \\
        --n_zdim   2 \\
        --n_epochs 5 \\
        --n_clusters 2 \\
        --outdir   s3://biomate-nextflow-work/test-outputs/cryo-het/
"""

import argparse
import os
import pickle
import sys

try:
    import numpy as np
except ImportError:
    sys.exit("ERROR: numpy is required. Install with: pip install numpy")

try:
    import mrcfile
except ImportError:
    sys.exit("ERROR: mrcfile is required. Install with: pip install mrcfile")


# ── Helpers ───────────────────────────────────────────────────────────────────

def gaussian_2d(size: int, cx: float, cy: float, sigma: float) -> np.ndarray:
    """Return a 2D Gaussian blob on a (size × size) grid."""
    y, x = np.mgrid[0:size, 0:size]
    return np.exp(-((x - cx) ** 2 + (y - cy) ** 2) / (2 * sigma ** 2))


def make_particle(size: int, state: str, noise_std: float = 0.05,
                  rng: np.random.Generator = None) -> np.ndarray:
    """
    Simulate a single 2D particle projection.

    State A — single central blob  (mimics e.g. closed conformation)
    State B — central blob + small offset lobe (open conformation)
    """
    if rng is None:
        rng = np.random.default_rng()

    cx, cy = size / 2, size / 2
    sigma  = size / 8.0

    img = gaussian_2d(size, cx, cy, sigma)

    if state == "B":
        # Additional smaller lobe shifted by sigma units in x
        shift = sigma * 1.2
        lobe  = 0.5 * gaussian_2d(size, cx + shift, cy, sigma * 0.7)
        img   = img + lobe

    # Apply random in-plane rotation (±180°)
    angle = rng.uniform(-np.pi, np.pi)
    cos_a, sin_a = np.cos(angle), np.sin(angle)
    y, x = np.mgrid[0:size, 0:size]
    xc, yc = x - cx, y - cy
    xr = cos_a * xc + sin_a * yc + cx
    yr = -sin_a * xc + cos_a * yc + cy

    from scipy.ndimage import map_coordinates  # lazy import
    coords = np.array([yr.ravel(), xr.ravel()])
    img = map_coordinates(img, coords, order=1, mode='constant').reshape(size, size)

    # Add Gaussian noise
    img = img + rng.normal(0, noise_std, img.shape)

    # Normalize to zero-mean, unit variance (standard cryo-EM convention)
    img = (img - img.mean()) / (img.std() + 1e-8)
    return img.astype(np.float32)


def make_ctf_params(n_particles: int, box: int, pixel_size: float = 1.5,
                    rng: np.random.Generator = None) -> dict:
    """
    Generate synthetic CTF parameters in cryoDRGN format.

    cryoDRGN expects a dict with keys:
        D        — box size (pixels)
        Apix     — pixel size (Angstrom/pixel)
        ctf      — (N, 9) array of [df1, df2, angle, volt, cs, w, phase, bfactor, scale]
    """
    if rng is None:
        rng = np.random.default_rng()

    # Realistic ranges for cryo-EM CTF parameters
    df1     = rng.uniform(1.0e4, 3.0e4, n_particles)  # defocus 1 (Angstrom)
    df2     = df1 + rng.uniform(0, 500, n_particles)   # defocus 2 ≈ df1 + astigmatism
    ang     = rng.uniform(0, np.pi, n_particles)        # astigmatism angle (rad)
    volt    = np.full(n_particles, 300.0)               # accelerating voltage (kV)
    cs      = np.full(n_particles, 2.7)                 # spherical aberration (mm)
    w       = np.full(n_particles, 0.1)                 # amplitude contrast
    phase   = np.zeros(n_particles)                     # phase shift (rad)
    bfactor = np.zeros(n_particles)                     # B-factor
    scale   = np.ones(n_particles)                      # scale factor

    ctf_matrix = np.stack([df1, df2, ang, volt, cs, w, phase, bfactor, scale], axis=1)

    # Use plain Python types to avoid numpy version-specific pickle incompatibility
    # (numpy._core vs numpy.core across numpy 1.x/2.x)
    return {
        "D":    int(box),
        "Apix": float(pixel_size),
        "ctf":  ctf_matrix.astype(np.float32).tolist(),
    }


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--outdir",    default="test_data",
                        help="Output directory (default: test_data/)")
    parser.add_argument("--n",         type=int, default=50,
                        help="Total number of particles (default: 50)")
    parser.add_argument("--box",       type=int, default=64,
                        help="Box size in pixels (default: 64)")
    parser.add_argument("--pixel-size", type=float, default=1.5,
                        help="Pixel size in Angstrom (default: 1.5)")
    parser.add_argument("--noise",     type=float, default=0.08,
                        help="Gaussian noise std (default: 0.08)")
    parser.add_argument("--seed",      type=int, default=42,
                        help="Random seed (default: 42)")
    args = parser.parse_args()

    try:
        from scipy.ndimage import map_coordinates  # noqa: F401 — verify available
    except ImportError:
        sys.exit("ERROR: scipy is required. Install with: pip install scipy")

    os.makedirs(args.outdir, exist_ok=True)

    rng    = np.random.default_rng(args.seed)
    N      = args.n
    box    = args.box
    n_A    = N // 2
    n_B    = N - n_A

    print(f"Generating {N} synthetic particles ({n_A} state-A + {n_B} state-B), box={box}px")

    # Generate particle stack
    particles = np.zeros((N, box, box), dtype=np.float32)
    for i in range(n_A):
        particles[i] = make_particle(box, "A", noise_std=args.noise, rng=rng)
    for i in range(n_B):
        particles[n_A + i] = make_particle(box, "B", noise_std=args.noise, rng=rng)

    mrcs_path = os.path.join(args.outdir, "cryo_het_test_particles.mrcs")
    with mrcfile.new(mrcs_path, overwrite=True) as mrc:
        mrc.set_data(particles)
        mrc.voxel_size = args.pixel_size
    print(f"  Wrote {mrcs_path}  ({N} × {box} × {box}, float32)")

    # Generate CTF parameters
    ctf_params = make_ctf_params(N, box, pixel_size=args.pixel_size, rng=rng)
    ctf_path   = os.path.join(args.outdir, "cryo_het_test_ctf.pkl")
    with open(ctf_path, "wb") as fh:
        pickle.dump(ctf_params, fh)
    print(f"  Wrote {ctf_path}  ({N} CTF parameter vectors)")

    # Generate poses (rotation matrices + translations) in cryoDRGN format:
    # tuple of (rotations: N×3×3 float32, translations: N×2 float32)
    # Saved as plain Python lists to avoid numpy version-specific pickle incompatibility.
    # cryoDRGN's PoseTracker.load converts to numpy internally.
    random_mats = rng.standard_normal((N, 3, 3)).astype(np.float32)
    rotations   = np.array([np.linalg.qr(m)[0] for m in random_mats], dtype=np.float32)
    # Ensure det=+1 (proper rotation, not reflection)
    dets = np.linalg.det(rotations)
    rotations[dets < 0, :, 0] *= -1
    translations = np.zeros((N, 2), dtype=np.float32)  # zero in-plane translations

    # Convert to plain Python lists so pickle doesn't embed numpy version-specific
    # class references (numpy._core vs numpy.core across numpy 1.x/2.x)
    poses_path = os.path.join(args.outdir, "cryo_het_test_poses.pkl")
    with open(poses_path, "wb") as fh:
        pickle.dump((rotations.tolist(), translations.tolist()), fh)
    print(f"  Wrote {poses_path}  ({N} rotation matrices + zero translations)")

    # Usage hints
    print()
    print("=" * 65)
    print("TEST DATASET READY")
    print("=" * 65)
    print()
    print("Local test (small n_epochs / n_clusters for speed):")
    print(f"  nextflow run workflows/cryo_em_heterogeneity.nf \\")
    print(f"    -profile local \\")
    print(f"    --particles {mrcs_path} \\")
    print(f"    --ctf       {ctf_path} \\")
    print(f"    --poses     {poses_path} \\")
    print(f"    --n_zdim    2 \\")
    print(f"    --n_epochs  5 \\")
    print(f"    --n_clusters 2")
    print()
    print("AWS Batch (after uploading to S3 with test_cryo_heterogeneity.sh):")
    print(f"  nextflow run workflows/cryo_em_heterogeneity.nf \\")
    print(f"    -profile aws \\")
    print(f"    --particles s3://biomate-nextflow-work/test-inputs/cryo-het/cryo_het_test_particles.mrcs \\")
    print(f"    --ctf       s3://biomate-nextflow-work/test-inputs/cryo-het/cryo_het_test_ctf.pkl \\")
    print(f"    --poses     s3://biomate-nextflow-work/test-inputs/cryo-het/cryo_het_test_poses.pkl \\")
    print(f"    --n_zdim    2 \\")
    print(f"    --n_epochs  5 \\")
    print(f"    --n_clusters 2 \\")
    print(f"    --outdir    s3://biomate-nextflow-work/test-outputs/cryo-het/")


if __name__ == "__main__":
    main()
