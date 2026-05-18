"""Real-data CryoEnsemble demo — TRPV1 EMPIAR-10059.

Inputs (must exist locally):
  particles/        : extracted particle MRCS stacks
  poses/pose.50.pkl : cryoDRGN ab-initio poses (R, t fractional)
  poses/ctf_v1compat.pkl : per-particle CTF parameters (cryoDRGN 9-col format)
  poses/particles.star : RELION star indexing which particle ↔ which MRCS
  priors/           : BioEmu conformer ensemble (tar.gz of PDBs)
  reference PDB     : TRPV1 chain A (PDB 3J5P) — for evaluating rare-state distance

Output: posterior over BioEmu conformers + per-particle assignments + summary JSON.

This is the proposal's central demonstration: per-particle image conditioning on
REAL cryo-EM particles with REAL CTF, on a real protein, yielding a real posterior.
"""

from __future__ import annotations

import argparse
import os
import pickle
import re
import sys
import tarfile
from pathlib import Path

import numpy as np
import torch

# Allow imports when run as a script
ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cryoensemble.dps import DPSConfig, reweight_prior
from cryoensemble.evaluate import evaluate, save_results, kabsch_rmsd
from cryoensemble.particles import MRCSStack


# ──────────────────────────────────────────────────────────────────────────────
# I/O helpers tailored to the TRPV1 dataset
# ──────────────────────────────────────────────────────────────────────────────

def load_prior_from_tarball(tarball: str, n_max: int | None = None, chain: str = "A") -> torch.Tensor:
    """Load Cα coords (chain A) of each PDB in a BioEmu ensemble tarball.

    Returns (n_conf, n_atoms, 3). Trimmed to a common atom count across conformers.
    """
    coords_list: list[np.ndarray] = []
    with tarfile.open(tarball) as tf:
        members = sorted([m for m in tf.getmembers() if m.name.endswith(".pdb")], key=lambda m: m.name)
        if n_max is not None:
            members = members[:n_max]
        for m in members:
            fh = tf.extractfile(m)
            if fh is None:
                continue
            ca = []
            for line in fh.read().decode().splitlines():
                if line.startswith("ATOM") and line[12:16].strip() == "CA" and line[21] == chain:
                    ca.append([float(line[30:38]), float(line[38:46]), float(line[46:54])])
            if ca:
                coords_list.append(np.asarray(ca, dtype=np.float32))
    if not coords_list:
        raise RuntimeError(f"No conformers in {tarball}")
    n = min(c.shape[0] for c in coords_list)
    arr = np.stack([c[:n] for c in coords_list])      # (n_conf, n_atoms, 3)
    # Center each conformer at its centroid
    arr = arr - arr.mean(axis=1, keepdims=True)
    return torch.from_numpy(arr)


def parse_image_to_particle_index(star_path: str) -> tuple[list[tuple[str, int]], np.ndarray]:
    """From a RELION star, return (image_specs, ordered_particle_idx_in_ctf_pose).

    image_specs is the list expected by ParticleDataset (path, frame_idx 0-based).
    ordered_particle_idx is the absolute particle index in the global star/ctf/pose order.

    The function is permissive about path resolution: it strips any directory prefix
    on _rlnImageName and looks for the basename inside the supplied directory.
    """
    text = Path(star_path).read_text()
    blocks = re.split(r"\ndata_", text)
    chosen = blocks[1] if len(blocks) > 1 else blocks[0]
    m = re.search(r"loop_\s*((?:_[^\n]+\n)+)((?:.+\n?)+)", chosen)
    cols, rows = m.group(1), m.group(2)

    col_names = []
    for ln in cols.strip().splitlines():
        s = ln.strip().split()
        if s and s[0].startswith("_"):
            col_names.append(s[0].lstrip("_"))
    img_col = col_names.index("rlnImageName")

    specs = []
    idx = []
    for k, ln in enumerate(rows.splitlines()):
        s = ln.strip()
        if not s or s.startswith(("data_", "loop_", "_")):
            continue
        parts = s.split()
        if len(parts) < len(col_names):
            continue
        rln_img = parts[img_col]
        if "@" not in rln_img:
            continue
        ix_str, p = rln_img.split("@", 1)
        ix0 = int(ix_str) - 1
        fname = Path(p).name
        specs.append((fname, ix0))
        idx.append(k)
    return specs, np.asarray(idx)


def load_real_particles_subset(
    star_path: str,
    particles_dir: str,
    n_keep: int,
    box_size: int = 256,
) -> tuple[torch.Tensor, np.ndarray]:
    """Load up to n_keep particles whose backing MRCS files exist in particles_dir.

    Returns
    -------
    images : (B, D, D) float32 tensor (background-normalised)
    sel_idx : (B,) global particle indices (for pose/CTF lookup)
    """
    specs, idx = parse_image_to_particle_index(star_path)
    pdir = Path(particles_dir)
    available_mrcs = {p.name for p in pdir.glob("*.mrcs")}
    keep_specs = []
    keep_idx = []
    stack_handles: dict[str, MRCSStack] = {}
    for (fname, frame), g in zip(specs, idx):
        if fname not in available_mrcs:
            continue
        if fname not in stack_handles:
            try:
                stack_handles[fname] = MRCSStack(pdir / fname)
            except Exception:
                continue
        keep_specs.append((fname, frame))
        keep_idx.append(g)
        if len(keep_specs) >= n_keep:
            break

    if not keep_specs:
        raise RuntimeError(f"No matching MRCS files in {particles_dir}")

    imgs = []
    for fname, frame in keep_specs:
        st = stack_handles[fname]
        if frame >= st.nz:
            continue
        img = st.get(frame).astype(np.float32)
        # Centre crop / pad to box_size
        H, W = img.shape
        if H != box_size or W != box_size:
            ch, cw = min(H, box_size), min(W, box_size)
            y0, x0 = (H - ch) // 2, (W - cw) // 2
            cropped = img[y0:y0 + ch, x0:x0 + cw]
            if ch < box_size or cw < box_size:
                padded = np.zeros((box_size, box_size), dtype=np.float32)
                py, px = (box_size - ch) // 2, (box_size - cw) // 2
                padded[py:py + ch, px:px + cw] = cropped
                img = padded
            else:
                img = cropped
        # Normalise background (mean 0, std 1 over outer pixels)
        mask = np.ones_like(img, dtype=bool)
        cy, cx = (box_size - 1) / 2.0, (box_size - 1) / 2.0
        yy, xx = np.meshgrid(np.arange(box_size), np.arange(box_size), indexing="ij")
        outer = (yy - cy) ** 2 + (xx - cx) ** 2 > (0.4 * box_size) ** 2
        bg_mean = img[outer].mean()
        bg_std = img[outer].std() + 1e-6
        img = (img - bg_mean) / bg_std
        imgs.append(img)
    images = torch.from_numpy(np.stack(imgs))
    return images, np.asarray(keep_idx[: len(imgs)])


def load_cryodrgn_pose(path: str, sel_idx: np.ndarray, D: int, apix: float) -> tuple[torch.Tensor, torch.Tensor]:
    """Load (R, t) for selected particles from cryoDRGN pose.pkl.

    cryoDRGN trans is fractional in [-0.5, 0.5]; convert to Å using D * apix.
    """
    with open(path, "rb") as f:
        raw = pickle.load(f)
    rots, trans = np.asarray(raw[0]), np.asarray(raw[1])
    rots = rots[sel_idx]
    trans = trans[sel_idx]
    R = torch.tensor(rots, dtype=torch.float32)
    t_A = torch.tensor(trans * D * apix, dtype=torch.float32)
    return R, t_A


def load_cryodrgn_ctf(path: str, sel_idx: np.ndarray) -> dict[str, torch.Tensor]:
    """Load CTF from cryoDRGN 9-column pkl: [D, Apix, DefU, DefV, Angle, kV, Cs, AC, PhaseShift]."""
    with open(path, "rb") as f:
        arr = np.asarray(pickle.load(f), dtype=np.float32)
    arr = arr[sel_idx]
    return {
        "defocus_u":       torch.tensor(arr[:, 2], dtype=torch.float32),
        "defocus_v":       torch.tensor(arr[:, 3], dtype=torch.float32),
        "astig_angle_deg": torch.tensor(arr[:, 4], dtype=torch.float32),
        "voltage_kV":      float(arr[0, 5]),
        "cs_mm":           float(arr[0, 6]),
        "amp_contrast":    float(arr[0, 7]),
        "phase_shift_deg": torch.tensor(arr[:, 8], dtype=torch.float32),
    }


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prior_tarball", required=True, help="BioEmu ensemble tarball")
    ap.add_argument("--particles_dir", required=True, help="Directory with mrcs files")
    ap.add_argument("--star",          required=True, help="RELION particles.star")
    ap.add_argument("--pose_pkl",      required=True, help="cryoDRGN pose.N.pkl")
    ap.add_argument("--ctf_pkl",       required=True, help="cryoDRGN ctf pkl (9 cols)")
    ap.add_argument("--n_particles",   type=int, default=500)
    ap.add_argument("--n_conformers",  type=int, default=50)
    ap.add_argument("--box_size",      type=int, default=256)
    ap.add_argument("--apix",          type=float, default=3.768)
    ap.add_argument("--sigma_noise",   type=float, default=1.0)
    ap.add_argument("--sigma_a",       type=float, default=2.0)
    ap.add_argument("--device",        default="cuda" if torch.cuda.is_available() else "cpu")
    ap.add_argument("--outdir",        default="./cryoensemble_demo_out")
    args = ap.parse_args()

    print(f"[demo] device={args.device}")
    print(f"[demo] loading prior conformers from {args.prior_tarball} (chain A)…")
    prior = load_prior_from_tarball(args.prior_tarball, n_max=args.n_conformers)
    print(f"  -> prior: {prior.shape}")

    print(f"[demo] loading particles from {args.particles_dir} (max {args.n_particles})…")
    images, sel_idx = load_real_particles_subset(args.star, args.particles_dir,
                                                  n_keep=args.n_particles,
                                                  box_size=args.box_size)
    print(f"  -> images: {images.shape},  selected global indices: {sel_idx[:5]}…")

    print(f"[demo] loading poses for selected particles…")
    R, t = load_cryodrgn_pose(args.pose_pkl, sel_idx, D=args.box_size, apix=args.apix)
    print(f"  -> R: {R.shape}, t: {t.shape}")

    print(f"[demo] loading CTF for selected particles…")
    ctf_params = load_cryodrgn_ctf(args.ctf_pkl, sel_idx)
    print(f"  -> defocus_u range: [{ctf_params['defocus_u'].min():.0f}, {ctf_params['defocus_u'].max():.0f}] Å,"
          f"  kV={ctf_params['voltage_kV']:.0f}")

    # Move to device
    prior   = prior.to(args.device)
    images  = images.to(args.device)
    R       = R.to(args.device)
    t       = t.to(args.device)
    ctf_params_dev = {k: v.to(args.device) if isinstance(v, torch.Tensor) else v
                      for k, v in ctf_params.items()}

    cfg = DPSConfig(
        D=args.box_size, apix=args.apix,
        sigma_a=args.sigma_a, sigma_noise=args.sigma_noise,
        particle_batch=32,
    )

    print(f"[demo] running per-particle posterior  "
          f"(prior={prior.shape[0]}, particles={images.shape[0]}, EM mixture)…")
    summary, raw = evaluate(prior, images, R, t, ctf_params_dev, cfg, rare_reference=None)

    print("\n=== Summary ===")
    print(f"  conformers in prior      : {summary.n_conformers}")
    print(f"  particles processed      : {summary.n_particles}")
    print(f"  posterior max weight     : {summary.posterior_max_weight:.4f}")
    print(f"  posterior ESS            : {summary.posterior_ess:.2f}  / {summary.n_conformers}")
    print(f"  posterior entropy (bits) : {summary.posterior_entropy_bits:.2f}")

    post = raw["posterior"].numpy()
    print("\n=== Posterior (sorted) ===")
    order = np.argsort(post)[::-1]
    for r, i in enumerate(order[:15]):
        bar = "█" * int(post[i] * 80)
        print(f"  rank {r:02d}  conf #{i:03d}  weight={post[i]:.4f}  {bar}")

    save_results(summary, raw, args.outdir)
    print(f"\nSaved results to {args.outdir}/")


if __name__ == "__main__":
    main()
