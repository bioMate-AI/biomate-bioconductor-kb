"""Experiment H1c — AlphaFlow-prior DPS recovers off-prior rare states.

H1a/b (in H1_NEGATIVE_RESULTS.md) established that:
  - Reweighting a *fixed* open-state pool: 0% posterior on closed.
  - DPS over a *fixed* open-state pool: 0% posterior on closed (KDE pulls back).

H1c tests whether DPS through a **generative prior (AlphaFlow-MD+Templates)**
can recover the off-manifold closed state.

Setup:
  - AlphaFlow ensemble of 30 conformers generated from 4AKE-A sequence + 4AKE PDB
    template. Pre-computed (cached) in
    cryoensemble/data/alphaflow_ensembles/4AKE_30conf.pdb.
  - Pool diversity: pairwise RMSD 2.17 Å mean (1.8× BioEmu baseline).
  - Pool coverage: RMSDs to 4AKE-open 1.41-4.71 Å; RMSDs to 1AKE-closed 4.07-7.46 Å.
    → No conformer within 2 Å of closed: rare state remains off-manifold.
  - Particle stack: 200 synthetic from 4AKE/1AKE at 5% closed population, full CTF.

Methods compared:
  A. Reweighting (Tang/Cossio-style EM mixture) over the AlphaFlow pool
  B. CryoEnsemble EM-DPS over the AlphaFlow pool (responsibility-weighted)

Pre-registered thresholds:
  Method A posterior on RMSD<2Å-to-closed ≤ 0.05  (pool doesn't reach closed)
  Method B posterior on RMSD<2Å-to-closed ≥ 0.10  (DPS refines some trajectory(ies))
  Differential ≥ 0.05

If B > A by ≥0.05: the DPS step adds real off-manifold-recovery capability.
If B = A: the cached-mode (KDE-smoothed) DPS does not provide enough refinement
power on top of reweighting; we'd need true neural-score DPS (running inside the
AlphaFlow container) to make the claim.
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
from cryoensemble.dps_sampler import DPSEMConfig, em_dps_posterior
from cryoensemble.evaluate import kabsch_rmsd
from cryoensemble.forward_model import render_particle, euler_zyz_to_matrix
from cryoensemble.priors import AlphaflowPrior, DeltaEnsemblePrior


# ──────────────────────────────────────────────────────────────────────────────
# I/O
# ──────────────────────────────────────────────────────────────────────────────

def load_calpha(pdb_path: str, chain: str = "A") -> np.ndarray:
    coords = []; seen = set()
    for line in open(pdb_path):
        if not line.startswith("ATOM"): continue
        if line[12:16].strip() != "CA": continue
        if line[21] != chain: continue
        rn = int(line[22:26])
        if rn in seen: continue
        seen.add(rn)
        coords.append([float(line[30:38]), float(line[38:46]), float(line[46:54])])
    return np.asarray(coords, dtype=np.float32)


def load_multimodel_pdb(pdb_path: str) -> torch.Tensor:
    """Load all MODEL blocks from a multimodel PDB into (N_conf, N_atoms, 3)."""
    models = []
    cur = []
    for ln in open(pdb_path):
        if ln.startswith("MODEL"):
            cur = []
        elif ln.startswith("ATOM") and ln[12:16].strip() == "CA":
            cur.append([float(ln[30:38]), float(ln[38:46]), float(ln[46:54])])
        elif ln.startswith("ENDMDL"):
            if cur:
                models.append(cur)
            cur = []
    if cur:
        models.append(cur)
    n = min(len(m) for m in models)
    return torch.tensor([m[:n] for m in models], dtype=torch.float32)


def synthesise(open_t, closed_t, *, n_particles, closed_frac, D, apix, noise_level, seed):
    n_closed = int(round(closed_frac * n_particles))
    n_open = n_particles - n_closed
    truth = torch.stack([open_t] * n_open + [closed_t] * n_closed, dim=0)
    g = torch.Generator().manual_seed(seed)
    alpha = (torch.rand(n_particles, generator=g) * 2 * math.pi).float()
    beta = torch.acos(2 * torch.rand(n_particles, generator=g) - 1).float()
    gamma = (torch.rand(n_particles, generator=g) * 2 * math.pi).float()
    R = euler_zyz_to_matrix(alpha, beta, gamma).float()
    t = torch.zeros(n_particles, 2)
    ctf = dict(
        defocus_u=torch.linspace(8000, 25000, n_particles).float(),
        defocus_v=torch.linspace(8500, 25500, n_particles).float(),
        astig_angle_deg=torch.zeros(n_particles),
        voltage_kV=300.0, cs_mm=2.0, amp_contrast=0.1,
    )
    imgs = render_particle(truth, R, t, D=D, apix=apix, **ctf)
    imgs = imgs + noise_level * torch.randn_like(imgs)
    return imgs, R, t, ctf


def fraction_near_closed(coords: torch.Tensor, closed_state: np.ndarray, threshold: float = 2.0):
    arr = coords.numpy() if isinstance(coords, torch.Tensor) else coords
    n = arr.shape[0]
    rmsds = np.array([kabsch_rmsd(arr[i], closed_state[:arr.shape[1]]) for i in range(n)])
    return rmsds, float((rmsds < threshold).sum()) / n


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--alphaflow_pdb",
                    default=str(Path(__file__).resolve().parents[1]
                                / "data/alphaflow_ensembles/4AKE_30conf.pdb"))
    ap.add_argument("--open_pdb",
                    default=str(Path(__file__).resolve().parents[1] / "data/goldstd/4AKE.pdb"))
    ap.add_argument("--closed_pdb",
                    default=str(Path(__file__).resolve().parents[1] / "data/goldstd/1AKE.pdb"))
    ap.add_argument("--n_particles", type=int, default=200)
    ap.add_argument("--closed_frac", type=float, default=0.05)
    ap.add_argument("--noise_level", type=float, default=0.05)
    ap.add_argument("--n_dps_trajectories", type=int, default=12)
    ap.add_argument("--n_dps_steps", type=int, default=50)
    ap.add_argument("--n_outer_iters", type=int, default=5)
    ap.add_argument("--dps_lik_lr", type=float, default=0.5)
    ap.add_argument("--dps_prior_lr", type=float, default=0.01)
    ap.add_argument("--dps_kernel_sigma", type=float, default=5.0)
    ap.add_argument("--box_size", type=int, default=96)
    ap.add_argument("--apix", type=float, default=1.5)
    ap.add_argument("--sigma_noise", type=float, default=0.5)
    ap.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--outdir", default="/tmp/exp_h1c")
    args = ap.parse_args()

    print("=== Experiment H1c — AlphaFlow-prior DPS recovers off-prior rare states ===\n")

    # ── Load data ────────────────────────────────────────────────────────────
    print(f"Loading AlphaFlow ensemble: {args.alphaflow_pdb}")
    pool = load_multimodel_pdb(args.alphaflow_pdb)
    print(f"  pool: {pool.shape[0]} conformers × {pool.shape[1]} Cα")

    open_xyz = load_calpha(args.open_pdb)
    closed_xyz = load_calpha(args.closed_pdb)
    n = min(len(open_xyz), len(closed_xyz), pool.shape[1])
    open_xyz, closed_xyz = open_xyz[:n] - open_xyz[:n].mean(0), closed_xyz[:n] - closed_xyz[:n].mean(0)
    pool = pool[:, :n, :]
    pool = pool - pool.mean(dim=1, keepdim=True)
    gt_rmsd = kabsch_rmsd(open_xyz, closed_xyz)
    print(f"  open ↔ closed RMSD: {gt_rmsd:.2f} Å")

    r_open = np.array([kabsch_rmsd(pool[i].numpy(), open_xyz) for i in range(pool.shape[0])])
    r_closed = np.array([kabsch_rmsd(pool[i].numpy(), closed_xyz) for i in range(pool.shape[0])])
    print(f"  pool RMSD→open  : {r_open.mean():.2f} ± {r_open.std():.2f}, min {r_open.min():.2f}, max {r_open.max():.2f}")
    print(f"  pool RMSD→closed: {r_closed.mean():.2f} ± {r_closed.std():.2f}, min {r_closed.min():.2f}, max {r_closed.max():.2f}")
    print(f"  pool members within 2Å of closed: {int((r_closed < 2.0).sum())}/{pool.shape[0]}")

    # ── Synthesise particles ─────────────────────────────────────────────────
    open_t = torch.from_numpy(open_xyz); closed_t = torch.from_numpy(closed_xyz)
    imgs, R, t, ctf = synthesise(
        open_t, closed_t,
        n_particles=args.n_particles, closed_frac=args.closed_frac,
        D=args.box_size, apix=args.apix, noise_level=args.noise_level, seed=args.seed,
    )
    print(f"\nParticle stack: {args.n_particles}  ({int(args.closed_frac*args.n_particles)} closed = {100*args.closed_frac:.0f}%)")

    # ── Move to device ───────────────────────────────────────────────────────
    pool_dev = pool.to(args.device)
    imgs_dev = imgs.to(args.device)
    R_dev = R.to(args.device); t_dev = t.to(args.device)
    ctf_dev = {k: v.to(args.device) if isinstance(v, torch.Tensor) else v for k, v in ctf.items()}

    results = {}

    # ── A: Reweight AlphaFlow pool ───────────────────────────────────────────
    print("\n[A] Reweighting AlphaFlow pool (Tang/Cossio-style)…")
    cfg_rw = DPSConfig(D=args.box_size, apix=args.apix, sigma_a=1.5,
                       sigma_noise=args.sigma_noise, particle_batch=64)
    t0 = time.time()
    rw_out = reweight_prior(pool_dev, imgs_dev, R_dev, t_dev, ctf_dev, cfg_rw,
                            posterior_mode="mixture")
    rw_t = time.time() - t0
    rw_post = rw_out["posterior"].numpy()
    rw_closed_mass = float(rw_post[r_closed < 2.0].sum())
    rw_min_rmsd = float(r_closed.min())   # unchanged (pool unchanged)
    print(f"  time: {rw_t:.1f}s")
    print(f"  pool members within 2Å of closed: {int((r_closed < 2.0).sum())}")
    print(f"  posterior mass on near-closed pool members: {rw_closed_mass:.4f}")
    print(f"  ESS: {rw_out['ess']:.1f}/{pool.shape[0]}")
    results["reweighting"] = dict(time_s=rw_t, near_closed_mass=rw_closed_mass,
                                  ess=float(rw_out["ess"]),
                                  min_rmsd_closed=rw_min_rmsd)

    # ── B: EM-DPS over AlphaFlow pool ────────────────────────────────────────
    print(f"\n[B] CryoEnsemble EM-DPS over AlphaFlow pool"
          f"  ({args.n_dps_trajectories} traj × {args.n_outer_iters} outer × {args.n_dps_steps // args.n_outer_iters} inner)…")
    cfg_dps = DPSEMConfig(
        D=args.box_size, apix=args.apix, sigma_a=1.5, sigma_noise=args.sigma_noise,
        n_steps=args.n_dps_steps, sigma_max=0.5, sigma_min=0.05,
        likelihood_lr=args.dps_lik_lr, prior_lr=args.dps_prior_lr,
        particle_batch=64, grad_clip=20.0,
    )
    prior_obj = AlphaflowPrior(pool, kernel_sigma=args.dps_kernel_sigma)
    t0 = time.time()
    dps_out = em_dps_posterior(prior_obj, particles=imgs_dev, R=R_dev, t=t_dev, ctf_params=ctf_dev,
                               config=cfg_dps, n_trajectories=args.n_dps_trajectories,
                               n_outer_iters=args.n_outer_iters)
    dps_t = time.time() - t0
    refined = dps_out["refined_conformers"]
    refined_rmsds_closed, _ = fraction_near_closed(refined, closed_xyz, threshold=2.0)
    dps_post = dps_out["posterior"].numpy()
    dps_closed_mass = float(dps_post[refined_rmsds_closed < 2.0].sum())
    print(f"  time: {dps_t:.1f}s")
    print(f"  refined min RMSD to closed: {refined_rmsds_closed.min():.2f} Å"
          f"  (initial was {r_closed.min():.2f})")
    print(f"  refined within 2Å of closed: {int((refined_rmsds_closed<2.0).sum())}/{refined.shape[0]}")
    print(f"  posterior mass on refined-near-closed: {dps_closed_mass:.4f}")
    print(f"  ESS: {dps_out['ess']:.1f}/{args.n_dps_trajectories}")
    print(f"  outer log-evidence: {[f'{x:.0f}' for x in dps_out['outer_log_evidence'].tolist()]}")
    results["dps"] = dict(time_s=dps_t,
                          near_closed_mass=dps_closed_mass,
                          ess=float(dps_out["ess"]),
                          min_rmsd_closed=float(refined_rmsds_closed.min()),
                          n_refined_within_2A=int((refined_rmsds_closed<2.0).sum()))

    # ── Hypothesis check ─────────────────────────────────────────────────────
    diff = dps_closed_mass - rw_closed_mass
    h1c_pass = (rw_closed_mass < 0.05) and (dps_closed_mass > 0.10) and (diff > 0.05)
    print(f"\n=== H1c outcome ===")
    print(f"  AlphaFlow + Reweighting near-closed mass : {rw_closed_mass:.4f}  (pre-reg ≤ 0.05)")
    print(f"  AlphaFlow + DPS         near-closed mass : {dps_closed_mass:.4f}  (pre-reg ≥ 0.10)")
    print(f"  Differential (DPS − RW)                  : {diff:+.4f}  (pre-reg ≥ 0.05)")
    print(f"  AlphaFlow alone, min RMSD to closed      : {r_closed.min():.2f} Å")
    print(f"  After DPS refinement, min RMSD to closed : {refined_rmsds_closed.min():.2f} Å")
    print(f"  H1c: {'PASS' if h1c_pass else 'FAIL'}")

    # ── Save ─────────────────────────────────────────────────────────────────
    outdir = Path(args.outdir); outdir.mkdir(parents=True, exist_ok=True)
    summary = {
        "system": "ADK 4AKE/1AKE",
        "prior": "AlphaFlow-MD+Templates-12l-distilled (30 conformers from 4AKE)",
        "gt_rmsd_A": float(gt_rmsd),
        "n_atoms": int(n),
        "n_particles": args.n_particles,
        "closed_frac_truth": args.closed_frac,
        "pool_size": pool.shape[0],
        "pool_min_rmsd_to_closed": float(r_closed.min()),
        "pool_max_rmsd_to_open":   float(r_open.max()),
        "results": results,
        "h1c_pass": bool(h1c_pass),
    }
    with open(outdir / "summary.json", "w") as f:
        json.dump(summary, f, indent=2)
    np.save(outdir / "rw_posterior.npy", rw_post)
    np.save(outdir / "dps_posterior.npy", dps_post)
    np.save(outdir / "refined_rmsds_to_closed.npy", refined_rmsds_closed)
    print(f"\nSaved to {outdir}/summary.json")


if __name__ == "__main__":
    main()
