"""
M6 cryo-EM density guidance term for OM-TPS.

This is the REAL M6 code artifact (destined for the OM-TPS container patch): a
differentiable cryo-EM density log-likelihood that plugs into the OM action as one
additive scalar term, exactly at the injection point verified in actions.py.

Forward model (rigid-atom map simulation):
  rho_sim(g | x) = sum_i exp(-||g - x_i||^2 / (2 sigma^2))            [Gaussian atoms at map resolution]
Likelihood (real-space cross-correlation, the standard cryo-EM fit score):
  nll(x) = 1 - CC(rho_sim(x), D_exp)  in [0, 2],  0 == perfect fit

Path guidance (the novelty axis): the density constrains WHICH frame(s) of the path
visit the observed state, via a soft-min over frames (a waypoint the path must pass
through) — NOT a per-frame pull toward one map (that would be endpoint/state fitting).
"""
import torch


def simulate_density(coords: torch.Tensor, grid: torch.Tensor, sigma: float) -> torch.Tensor:
    """coords [N,3], grid [M,3] -> rho [M] (differentiable). Gaussian sum, resolution ~ sigma."""
    d2 = ((grid[:, None, :] - coords[None, :, :]) ** 2).sum(-1)   # [M, N]
    return torch.exp(-d2 / (2.0 * sigma * sigma)).sum(-1)         # [M]


def cc_nll(rho: torch.Tensor, d_exp: torch.Tensor, eps: float = 1e-8) -> torch.Tensor:
    """1 - normalized cross-correlation. 0 == identical density."""
    rc = rho - rho.mean()
    dc = d_exp - d_exp.mean()
    cc = (rc * dc).sum() / (rc.norm() * dc.norm() + eps)
    return 1.0 - cc


def density_term(
    path: torch.Tensor,      # [B, P, N, 3]
    grid: torch.Tensor,      # [M, 3]
    d_exp: torch.Tensor,     # [M]  experimental (or simulated-from-known-state) density
    sigma: float,
    tau: float = 0.05,       # soft-min temperature over frames
) -> torch.Tensor:
    """Additive scalar: min-over-frames cryo-EM nll (the path must visit the observed state once)."""
    B, P, N, _ = path.shape
    total = path.new_zeros(())
    for b in range(B):
        nll_frames = torch.stack([cc_nll(simulate_density(path[b, k], grid, sigma), d_exp)
                                  for k in range(P)])          # [P]
        m = nll_frames.min()
        soft_min = m - tau * torch.log(torch.exp(-(nll_frames - m) / tau).sum())
        total = total + soft_min
    return total


def guided_action(action, path, grid, d_exp, sigma, lam, tau=0.05):
    """M6 objective = OM action (real actions.py) + lam * cryo-EM density term.

    HutchinsonAction computes forces AND their divergence internally (double-backward),
    so it must receive forces=None. TruncatedAction requires forces passed in.
    """
    if hasattr(action, "D"):                       # HutchinsonAction (stores self.D)
        path_t, force_t, div_t = action(path, None)
    else:                                          # TruncatedAction
        forces = action.force_func(path.reshape(-1, path.shape[-2], path.shape[-1])).reshape(path.shape)
        path_t, force_t, div_t = action(path, forces)
    om = path_t + force_t + div_t
    return om + lam * density_term(path, grid, d_exp, sigma, tau), om
