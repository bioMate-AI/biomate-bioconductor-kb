"""Experiment H1 — DPS recovers off-prior rare states; reweighting cannot.

This is the decisive test of the framework's central claim.

Setup (synthetic, controlled ground truth):
  • Truth: ADK particle stack synthesised from real PDBs 4AKE (open) and 1AKE (closed).
  • Rare state population: 5% (40 closed / 760 open = 800 particles).
  • Prior pool: ONLY perturbations of the open state. NO closed-state conformers.
    This is the critical constraint — the rare state is *off* the prior's training
    distribution.

Methods:
  • Reweighting baseline (Tang/Cossio-style): compute per-particle log-likelihoods,
    aggregate via EM mixture over the prior pool. Pre-registered: posterior mass on
    closed-equivalent conformers ≤ 0.05 (no closed conformers exist in the pool).
  • CryoEnsemble DPS: refine each prior-pool starting point with N steps of
    DPS toward the image evidence. Refined conformers may land OFF the original
    pool. Pre-registered: at least 10% of DPS-refined conformers land within 2 Å
    RMSD of the true closed state.

Threshold for H1 to PASS:
  - Reweighting: <0.05 posterior mass on RMSD<2Å-to-closed conformers
  - DPS: ≥0.20 posterior mass on RMSD<2Å-to-closed conformers
  - Posterior mass differential ≥ 0.15 (one-tailed)

If H1 fails, the DPS step adds nothing — the framework's distinct contribution
collapses to "reweighting with a different smoother". This would be a publishable
negative finding.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
from dataclasses import asdict
from pathlib import Path

import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cryoensemble.dps import DPSConfig, reweight_prior
from cryoensemble.dps_sampler import DPSEMConfig, dps_em_posterior, em_dps_posterior
from cryoensemble.evaluate import kabsch_rmsd
from cryoensemble.forward_model import render_particle, euler_zyz_to_matrix
from cryoensemble.priors import DeltaEnsemblePrior


# ──────────────────────────────────────────────────────────────────────────────
# Data
# ──────────────────────────────────────────────────────────────────────────────

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


def synthesise_particles(
    open_state: torch.Tensor,
    closed_state: torch.Tensor,
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
        [closed_state if c else open_state for c in is_closed], dim=0
    )
    g = torch.Generator().manual_seed(seed)
    alpha = torch.rand(n_particles, generator=g) * 2 * math.pi
    beta = torch.acos(2 * torch.rand(n_particles, generator=g) - 1)
    gamma = torch.rand(n_particles, generator=g) * 2 * math.pi
    R = euler_zyz_to_matrix(alpha, beta, gamma)
    t = torch.zeros(n_particles, 2)
    ctf = dict(
        defocus_u=torch.linspace(8000, 25000, n_particles),
        defocus_v=torch.linspace(8500, 25500, n_particles),
        astig_angle_deg=torch.zeros(n_particles),
        voltage_kV=300.0, cs_mm=2.0, amp_contrast=0.1,
    )
    imgs = render_particle(coords_truth, R, t, D=D, apix=apix, **ctf)
    imgs = imgs + noise_level * torch.randn_like(imgs)
    return imgs, R, t, ctf, is_closed


def build_open_only_prior(open_state: np.ndarray, n: int, sigma: float, seed: int) -> tuple[torch.Tensor, np.ndarray]:
    rng = np.random.default_rng(seed)
    pool = np.stack([
        open_state + rng.normal(0, sigma, open_state.shape).astype(np.float32)
        for _ in range(n)
    ])
    pool = pool - pool.mean(axis=1, keepdims=True)
    rmsds_to_open = np.array([kabsch_rmsd(c, open_state) for c in pool])
    return torch.from_numpy(pool), rmsds_to_open


# ──────────────────────────────────────────────────────────────────────────────
# Methods
# ──────────────────────────────────────────────────────────────────────────────

def run_reweighting(prior_pool: torch.Tensor, particles, R, t, ctf, cfg: DPSConfig) -> dict:
    """Tang/Cossio-style reweighting baseline."""
    prior_obj = DeltaEnsemblePrior(prior_pool, kernel_sigma=0.5, name="reweight_baseline")
    raw = reweight_prior(prior_pool, particles, R, t, ctf, cfg, posterior_mode="mixture")
    return raw


def run_dps(prior_pool: torch.Tensor, particles, R, t, ctf, cfg_em: DPSEMConfig,
            kernel_sigma: float = 1.0, n_trajectories: int = 20,
            n_outer_iters: int = 5) -> dict:
    """CryoEnsemble EM-DPS posterior — responsibility-weighted DPS.

    Each of n_trajectories gets gradient weighted by per-particle responsibility,
    so a trajectory that explains the rare-state particles best receives the
    rare-state pull (not drowned out by the dominant-state majority).
    """
    prior_obj = DeltaEnsemblePrior(prior_pool, kernel_sigma=kernel_sigma, name="dps_prior")
    return em_dps_posterior(
        prior_obj, particles=particles, R=R, t=t, ctf_params=ctf,
        config=cfg_em, n_trajectories=n_trajectories,
        n_outer_iters=n_outer_iters,
    )


def fraction_near_closed(coords: torch.Tensor, closed_state: np.ndarray, threshold: float = 2.0) -> tuple[np.ndarray, float]:
    """Return per-conformer RMSD-to-closed and the count below threshold."""
    arr = coords.numpy() if isinstance(coords, torch.Tensor) else coords
    n = arr.shape[0]
    rmsds = np.array([kabsch_rmsd(arr[i], closed_state[:arr.shape[1]]) for i in range(n)])
    return rmsds, float((rmsds < threshold).sum()) / n


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--open_pdb",
                    default=str(Path(__file__).resolve().parents[1] / "data/goldstd/4AKE.pdb"))
    ap.add_argument("--closed_pdb",
                    default=str(Path(__file__).resolve().parents[1] / "data/goldstd/1AKE.pdb"))
    ap.add_argument("--n_particles", type=int, default=400)
    ap.add_argument("--closed_frac", type=float, default=0.05)
    ap.add_argument("--n_prior", type=int, default=15)
    ap.add_argument("--prior_sigma", type=float, default=0.5)
    ap.add_argument("--n_dps_trajectories", type=int, default=20)
    ap.add_argument("--n_dps_steps", type=int, default=40)
    ap.add_argument("--dps_lik_lr", type=float, default=0.002)
    ap.add_argument("--dps_prior_lr", type=float, default=0.05)
    ap.add_argument("--dps_kernel_sigma", type=float, default=2.0)
    ap.add_argument("--box_size", type=int, default=96)
    ap.add_argument("--apix", type=float, default=1.5)
    ap.add_argument("--sigma_noise", type=float, default=0.5)
    ap.add_argument("--noise_level", type=float, default=0.05)
    ap.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--outdir", default="/tmp/exp_h1")
    args = ap.parse_args()

    print(f"=== Experiment H1: DPS recovers off-prior rare states ===\n")
    open_xyz = load_calpha(args.open_pdb)
    closed_xyz = load_calpha(args.closed_pdb)
    n = min(len(open_xyz), len(closed_xyz))
    open_xyz, closed_xyz = open_xyz[:n] - open_xyz[:n].mean(0), closed_xyz[:n] - closed_xyz[:n].mean(0)
    gt_rmsd = kabsch_rmsd(open_xyz, closed_xyz)
    print(f"  Open ↔ Closed Cα RMSD: {gt_rmsd:.2f} Å  ({n} atoms)")
    print(f"  Particles: {args.n_particles}  ({100*args.closed_frac:.0f}% closed)")
    print(f"  Prior pool: {args.n_prior} OPEN-only perturbations (σ={args.prior_sigma} Å)")
    print(f"  DPS: {args.n_dps_trajectories} trajectories × {args.n_dps_steps} steps")
    print(f"  Device: {args.device}")

    # ── Build data ────────────────────────────────────────────────────────────
    open_t = torch.from_numpy(open_xyz)
    closed_t = torch.from_numpy(closed_xyz)
    imgs, R, t, ctf, is_closed = synthesise_particles(
        open_t, closed_t,
        n_particles=args.n_particles, closed_frac=args.closed_frac,
        D=args.box_size, apix=args.apix, noise_level=args.noise_level, seed=args.seed,
    )
    prior_pool, prior_to_open = build_open_only_prior(open_xyz, args.n_prior, args.prior_sigma, args.seed + 1)
    print(f"\n  Prior RMSD to open:   mean={prior_to_open.mean():.2f}, max={prior_to_open.max():.2f}")
    prior_to_closed = np.array([kabsch_rmsd(c.numpy(), closed_xyz) for c in prior_pool])
    print(f"  Prior RMSD to closed: mean={prior_to_closed.mean():.2f}, min={prior_to_closed.min():.2f}")
    print(f"  → Closest prior member is {prior_to_closed.min():.1f} Å from closed (rare state is off-manifold)\n")

    # ── Move to device ────────────────────────────────────────────────────────
    prior_pool_dev = prior_pool.to(args.device)
    imgs_dev = imgs.to(args.device)
    R_dev = R.to(args.device); t_dev = t.to(args.device)
    ctf_dev = {k: v.to(args.device) if isinstance(v, torch.Tensor) else v for k, v in ctf.items()}

    # ── A: Reweighting baseline ───────────────────────────────────────────────
    print("[A] Reweighting baseline (Tang/Cossio-style)…")
    t0 = time.time()
    cfg_rw = DPSConfig(D=args.box_size, apix=args.apix, sigma_a=1.5,
                       sigma_noise=args.sigma_noise, particle_batch=64)
    rw_out = run_reweighting(prior_pool_dev, imgs_dev, R_dev, t_dev, ctf_dev, cfg_rw)
    rw_post = rw_out["posterior"]
    rmsds_rw, rw_recall = fraction_near_closed(prior_pool, closed_xyz)
    rw_closed_mass = float(rw_post[rmsds_rw < 2.0].sum())
    print(f"  Reweighting time: {time.time()-t0:.1f}s")
    print(f"  Conformers in pool within 2 Å of closed: {int((rmsds_rw < 2.0).sum())}/{len(rmsds_rw)}")
    print(f"  Posterior mass on near-closed: {rw_closed_mass:.4f}")
    print(f"  ESS: {rw_out['ess']:.1f}/{len(prior_pool)}")

    # ── B: DPS ────────────────────────────────────────────────────────────────
    print(f"\n[B] CryoEnsemble DPS ({args.n_dps_trajectories} trajectories × {args.n_dps_steps} steps)…")
    t0 = time.time()
    cfg_dps = DPSEMConfig(
        D=args.box_size, apix=args.apix, sigma_a=1.5, sigma_noise=args.sigma_noise,
        n_steps=args.n_dps_steps, sigma_max=0.5, sigma_min=0.05,
        likelihood_lr=args.dps_lik_lr, prior_lr=args.dps_prior_lr,
        particle_batch=64, grad_clip=20.0,
    )
    dps_out = run_dps(prior_pool_dev, imgs_dev, R_dev, t_dev, ctf_dev, cfg_dps,
                     kernel_sigma=args.dps_kernel_sigma,
                     n_trajectories=args.n_dps_trajectories)
    dps_post = dps_out["posterior"]
    refined = dps_out["refined_conformers"]
    rmsds_dps, dps_recall = fraction_near_closed(refined, closed_xyz)
    dps_closed_mass = float(dps_post[rmsds_dps < 2.0].sum())
    print(f"  DPS time: {time.time()-t0:.1f}s")
    print(f"  Refined conformers within 2 Å of closed: {int((rmsds_dps < 2.0).sum())}/{len(rmsds_dps)}")
    print(f"  Posterior mass on near-closed (refined): {dps_closed_mass:.4f}")
    print(f"  ESS: {dps_out['ess']:.1f}/{args.n_dps_trajectories}")
    print(f"  Closest refined conformer to closed: {rmsds_dps.min():.2f} Å")

    # ── Hypothesis check ──────────────────────────────────────────────────────
    print(f"\n=== H1 outcome ===")
    print(f"  Reweighting near-closed mass: {rw_closed_mass:.4f}  (pre-reg threshold ≤ 0.05)")
    print(f"  DPS         near-closed mass: {dps_closed_mass:.4f}  (pre-reg threshold ≥ 0.20)")
    print(f"  Differential: {dps_closed_mass - rw_closed_mass:+.4f}  (pre-reg threshold ≥ 0.15)")
    h1_pass = (rw_closed_mass < 0.05) and (dps_closed_mass > 0.20) and (dps_closed_mass - rw_closed_mass > 0.15)
    print(f"  H1: {'PASS' if h1_pass else 'FAIL'}")

    # ── Save ──────────────────────────────────────────────────────────────────
    outdir = Path(args.outdir); outdir.mkdir(parents=True, exist_ok=True)
    result = {
        "system": "ADK 4AKE/1AKE", "gt_rmsd_A": float(gt_rmsd), "n_atoms": int(n),
        "n_particles": args.n_particles, "closed_frac_truth": args.closed_frac,
        "n_prior": args.n_prior, "prior_sigma_A": args.prior_sigma,
        "n_dps_trajectories": args.n_dps_trajectories, "n_dps_steps": args.n_dps_steps,
        "dps_lik_lr": args.dps_lik_lr, "dps_prior_lr": args.dps_prior_lr,
        "dps_kernel_sigma": args.dps_kernel_sigma,
        "reweighting_near_closed_mass": rw_closed_mass,
        "reweighting_ess": float(rw_out["ess"]),
        "dps_near_closed_mass": dps_closed_mass,
        "dps_ess": float(dps_out["ess"]),
        "dps_min_rmsd_to_closed": float(rmsds_dps.min()),
        "dps_n_refined_within_2A": int((rmsds_dps < 2.0).sum()),
        "h1_pass": bool(h1_pass),
    }
    with open(outdir / "summary.json", "w") as f:
        json.dump(result, f, indent=2)
    np.save(outdir / "rw_posterior.npy", rw_post.numpy())
    np.save(outdir / "dps_posterior.npy", dps_post.numpy())
    np.save(outdir / "rmsds_dps_to_closed.npy", rmsds_dps)
    print(f"\nSaved to {outdir}/summary.json")


if __name__ == "__main__":
    main()
