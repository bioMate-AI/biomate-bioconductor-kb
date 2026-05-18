"""Gold-standard validation on the ADK open/closed system (PDB 4AKE/1AKE).

This sweeps the population fraction of the rare (closed) state from 50% down to 2%,
synthesises realistic cryo-EM particles at each fraction, and reports whether
CryoEnsemble's per-particle EM mixture recovers the true population — and the
true closed-state conformer — at each level.

This is what "validating before running on her data" looks like:
  - Ground truth is exactly known (synthesis populations are set by the script)
  - 4AKE/1AKE Cα RMSD = 7.13 Å (matches the proposal's headline ADK number)
  - Forward model uses real CTF, real random SO(3) poses, real noise
  - Output: a table of (true_frac, recovered_frac, RMSE) across runs

Expected outcomes:
  - At 50/50, both states recovered.
  - At 80/20, posterior assigns ~80% open / ~20% closed (within ~3% absolute).
  - At 95/5, posterior assigns ~95%/~5%; this is the proposal's headline claim.
  - At 2%, may fail — that's a finding worth reporting.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
from pathlib import Path

import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cryoensemble.dps import DPSConfig, reweight_prior
from cryoensemble.evaluate import kabsch_rmsd
from cryoensemble.forward_model import render_particle, euler_zyz_to_matrix


def load_calpha(pdb_path: str, chain: str = "A") -> np.ndarray:
    coords = []
    seen = set()
    for line in open(pdb_path):
        if not line.startswith("ATOM"):
            continue
        if line[12:16].strip() != "CA":
            continue
        if line[21] != chain:
            continue
        rn = int(line[22:26])
        if rn in seen:
            continue
        seen.add(rn)
        coords.append([float(line[30:38]), float(line[38:46]), float(line[46:54])])
    return np.asarray(coords, dtype=np.float32)


def random_poses(n: int, *, seed: int = 0) -> tuple[torch.Tensor, torch.Tensor]:
    """Uniform SO(3) rotations via random Euler ZYZ angles."""
    g = torch.Generator().manual_seed(seed)
    alpha = torch.rand(n, generator=g) * 2 * math.pi
    beta = torch.acos(2 * torch.rand(n, generator=g) - 1)
    gamma = torch.rand(n, generator=g) * 2 * math.pi
    R = euler_zyz_to_matrix(alpha, beta, gamma)
    t = torch.zeros(n, 2)  # no translation jitter (poses are exact)
    return R, t


def random_ctf(n: int, *, seed: int = 1) -> dict:
    """Realistic CTF distribution: defocus 0.5–3 μm, mild astigmatism."""
    g = torch.Generator().manual_seed(seed)
    df = 5000 + 25000 * torch.rand(n, generator=g)
    return dict(
        defocus_u=df,
        defocus_v=df + (200 * (torch.rand(n, generator=g) - 0.5)),
        astig_angle_deg=torch.rand(n, generator=g) * 90,
        voltage_kV=300.0,
        cs_mm=2.0,
        amp_contrast=0.1,
    )


def build_prior_from_two_states(
    open_xyz: np.ndarray,
    closed_xyz: np.ndarray,
    *,
    n_open_perturb: int = 20,
    n_closed_perturb: int = 4,
    sigma: float = 0.5,
    seed: int = 42,
) -> tuple[torch.Tensor, np.ndarray]:
    """Construct a prior that contains both states (but in OPPOSITE proportion
    to the particle population — so the posterior really has to learn from
    images, not from prior).
    """
    rng = np.random.default_rng(seed)
    open_b = np.stack([
        open_xyz + rng.normal(0, sigma, open_xyz.shape).astype(np.float32)
        for _ in range(n_open_perturb)
    ])
    closed_b = np.stack([
        closed_xyz + rng.normal(0, sigma, closed_xyz.shape).astype(np.float32)
        for _ in range(n_closed_perturb)
    ])
    prior = np.concatenate([open_b, closed_b]).astype(np.float32)
    prior = prior - prior.mean(axis=1, keepdims=True)
    labels = np.array(["open"] * n_open_perturb + ["closed"] * n_closed_perturb)
    return torch.from_numpy(prior), labels


def synthesize_particles(
    open_xyz: torch.Tensor,
    closed_xyz: torch.Tensor,
    *,
    n_particles: int,
    closed_frac: float,
    D: int,
    apix: float,
    noise_level: float,
    seed: int,
) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor, dict, torch.Tensor]:
    n_closed = int(round(closed_frac * n_particles))
    n_open = n_particles - n_closed
    is_closed = torch.cat([torch.zeros(n_open), torch.ones(n_closed)]).bool()
    coords_truth = torch.stack(
        [closed_xyz if c else open_xyz for c in is_closed], dim=0
    )
    R, t = random_poses(n_particles, seed=seed)
    ctf = random_ctf(n_particles, seed=seed + 1)
    imgs = render_particle(coords_truth, R, t, D=D, apix=apix, **ctf)
    imgs = imgs + noise_level * torch.randn_like(imgs)
    return imgs, R, t, ctf, is_closed


def run_one(
    open_xyz: np.ndarray,
    closed_xyz: np.ndarray,
    *,
    n_particles: int,
    closed_frac_truth: float,
    D: int,
    apix: float,
    sigma_a: float,
    sigma_noise: float,
    noise_level: float,
    n_open_perturb: int,
    n_closed_perturb: int,
    seed: int,
    device: str,
) -> dict:
    open_t = torch.from_numpy(open_xyz - open_xyz.mean(0))
    closed_t = torch.from_numpy(closed_xyz - closed_xyz.mean(0))

    imgs, R, t, ctf, is_closed = synthesize_particles(
        open_t, closed_t,
        n_particles=n_particles, closed_frac=closed_frac_truth,
        D=D, apix=apix, noise_level=noise_level, seed=seed,
    )
    prior, labels = build_prior_from_two_states(
        open_xyz - open_xyz.mean(0),
        closed_xyz - closed_xyz.mean(0),
        n_open_perturb=n_open_perturb, n_closed_perturb=n_closed_perturb,
        sigma=0.5, seed=seed + 100,
    )

    prior = prior.to(device); imgs = imgs.to(device)
    R = R.to(device); t = t.to(device)
    ctf_dev = {k: v.to(device) if isinstance(v, torch.Tensor) else v for k, v in ctf.items()}

    cfg = DPSConfig(D=D, apix=apix, sigma_a=sigma_a, sigma_noise=sigma_noise, particle_batch=64)
    raw = reweight_prior(prior, imgs, R, t, ctf_dev, cfg)

    post = raw["posterior"].numpy()
    closed_post = post[labels == "closed"].sum()
    open_post = post[labels == "open"].sum()
    abs_err = abs(closed_post - closed_frac_truth)
    rel_err = abs_err / max(closed_frac_truth, 0.01)
    assignments = raw["per_particle_assignments"].numpy()
    # Per-particle assignment accuracy: is each particle assigned to a conformer of its true block?
    correct = 0
    for p in range(n_particles):
        assigned_block = labels[assignments[p]]
        true_block = "closed" if is_closed[p] else "open"
        if assigned_block == true_block:
            correct += 1
    assign_acc = correct / n_particles

    return {
        "closed_frac_truth": closed_frac_truth,
        "closed_frac_recovered": float(closed_post),
        "open_frac_recovered": float(open_post),
        "abs_error": float(abs_err),
        "rel_error": float(rel_err),
        "particle_assignment_accuracy": assign_acc,
        "ess": float(raw["posterior"].pow(2).sum().reciprocal()),
        "n_particles": n_particles,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--open_pdb",   default=str(Path(__file__).resolve().parents[1] / "data/goldstd/4AKE.pdb"))
    ap.add_argument("--closed_pdb", default=str(Path(__file__).resolve().parents[1] / "data/goldstd/1AKE.pdb"))
    ap.add_argument("--fractions",  default="0.5,0.2,0.1,0.05,0.02",
                    help="Comma-separated closed-state fractions to test")
    ap.add_argument("--noise_level", type=float, default=0.05,
                    help="Additive Gaussian noise σ added to synthesised images")
    ap.add_argument("--n_particles", type=int, default=400)
    ap.add_argument("--n_open_perturb", type=int, default=15)
    ap.add_argument("--n_closed_perturb", type=int, default=5)
    ap.add_argument("--box_size", type=int, default=96)
    ap.add_argument("--apix", type=float, default=1.5)
    ap.add_argument("--sigma_a", type=float, default=1.5)
    ap.add_argument("--sigma_noise", type=float, default=0.5)
    ap.add_argument("--seed_base", type=int, default=0)
    ap.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    ap.add_argument("--outjson", default="/tmp/cryoensemble_validation.json")
    args = ap.parse_args()

    print(f"[validation] device={args.device}")
    open_xyz = load_calpha(args.open_pdb)
    closed_xyz = load_calpha(args.closed_pdb)
    n = min(len(open_xyz), len(closed_xyz))
    open_xyz, closed_xyz = open_xyz[:n], closed_xyz[:n]
    gt_rmsd = kabsch_rmsd(open_xyz, closed_xyz)
    print(f"  ADK: open={len(open_xyz)} CAs   open↔closed RMSD={gt_rmsd:.2f} Å")
    print(f"  particles={args.n_particles}  box={args.box_size}  apix={args.apix}")
    print(f"  prior: {args.n_open_perturb} open + {args.n_closed_perturb} closed perturbations\n")

    results = []
    print(f"{'truth':>7} | {'recovered':>10} | {'abs_err':>8} | {'rel_err':>8} | {'assign_acc':>10} | {'ess':>6}")
    print("-" * 70)
    for frac in (float(s) for s in args.fractions.split(",")):
        t0 = time.time()
        r = run_one(
            open_xyz, closed_xyz,
            n_particles=args.n_particles, closed_frac_truth=frac,
            D=args.box_size, apix=args.apix,
            sigma_a=args.sigma_a, sigma_noise=args.sigma_noise,
            noise_level=args.noise_level,
            n_open_perturb=args.n_open_perturb, n_closed_perturb=args.n_closed_perturb,
            seed=args.seed_base + int(round(1000 * frac)),
            device=args.device,
        )
        dt = time.time() - t0
        print(f"  {r['closed_frac_truth']:.3f}  |   {r['closed_frac_recovered']:.3f}    |  {r['abs_error']:.3f}   |  {r['rel_error']:.3f}   |    {r['particle_assignment_accuracy']:.3f}    | {r['ess']:.1f}   ({dt:.1f}s)")
        results.append(r)

    with open(args.outjson, "w") as f:
        json.dump({
            "system": "ADK 4AKE/1AKE",
            "ground_truth_rmsd_A": float(gt_rmsd),
            "n_atoms": int(n),
            "n_particles": args.n_particles,
            "box_size": args.box_size,
            "apix": args.apix,
            "noise_level": args.noise_level,
            "results": results,
        }, f, indent=2)
    print(f"\nResults written to {args.outjson}")


if __name__ == "__main__":
    main()
