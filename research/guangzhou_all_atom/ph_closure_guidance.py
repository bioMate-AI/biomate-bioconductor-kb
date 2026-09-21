#!/usr/bin/env python3
"""ph_closure_guidance.py — MacroGuide-style persistent-homology ring-closure guidance
for PepGLAD's latent-diffusion sampler (research/guangzhou_all_atom).

Reimplements the MacroGuide (arXiv:2602.14977, MIT: github.com/ala1705/MacroGuide)
H1-birth / H1-death / H0-death topological penalty on PepGLAD's *latent* peptide points,
scaled to model.consec_dist_mean/std (NOT raw Angstrom) so it is commensurate with
PepGLAD's existing dist_energy guidance. Slots into sample_opt['energy_func'] exactly
where cyclic_closure_energy already lives.

WIRING (parent adds these lines to generate_validation.py, mirroring the 'cyclic' branch):

    from ph_closure_guidance import ph_closure_energy       # near the other energy imports
    # extend the argparse choices:  choices=['none','default','cyclic','ph']
    elif args.guidance == 'ph':
        assert getattr(model, 'consec_dist_mean', None) is not None, \
            'checkpoint not calibrated: run setup_latent_guidance.py first'
        _energy = partial(ph_closure_energy,
                          mean=model.consec_dist_mean, std=model.consec_dist_std,
                          tolerance=args.closure_thresh)   # reuse existing flag as latent tol band
        sample_opt = {'energy_func': _energy, 'energy_lambda': args.energy_lambda}

Then closure_smoke.sh gains a third run_mode 'ph' and the summaries are compared.

Persistent-homology backend: torch_topological (as in MacroGuide). If unavailable at
runtime the term degrades to the incumbent head-to-tail first<->last penalty so a run
never crashes on a missing dep (it logs the fallback once).
"""
from __future__ import annotations
import os
import torch

from models.LDM.energies.dist import dist_energy      # PepGLAD base geometry guidance
from utils.nn_utils import graph_to_batch

# --- optional differentiable PH backend (MacroGuide dependency) ------------------
try:
    from torch_topological.nn import VietorisRipsComplex
    _VR = VietorisRipsComplex(dim=1, p=2, threshold=torch.inf,
                              keep_infinite_features=False)
    _HAS_TDA = True
except Exception:                                     # torch_topological missing / import error
    _VR, _HAS_TDA = None, False

_WARNED = {"fallback": False}


# ---- MacroGuide terms, ported and latent-scaled --------------------------------
def _window_hinge(value, low, high, power=2.0):
    return (torch.relu(low - value) + torch.relu(value - high)).pow(power)


def _top_h1(coords, h1_info, n_rings):
    """The n_rings longest-lived H1 features; critical distances recomputed from
    coords so they carry gradient (mirrors MacroGuide topology.top_h1_features)."""
    pairing, diagram = h1_info.pairing, h1_info.diagram
    if len(pairing) == 0 or diagram.numel() == 0:
        return []
    k = min(n_rings, len(pairing))
    order = torch.topk(diagram[:, 1], k=k).indices
    out = []
    for idx in order:
        p = pairing[idx]
        birth = torch.norm(coords[p[1]] - coords[p[0]])
        death = torch.norm(coords[p[3]] - coords[p[2]])
        out.append((birth, death))
    return out


def _long_h0(coords, h0_info, l_star):
    """H0 merges needing a gap > l_star: pull the outer atom inward (anchored inner)."""
    diagram = torch.as_tensor(h0_info.diagram, device=coords.device, dtype=coords.dtype)
    pairing = torch.as_tensor(h0_info.pairing, device=coords.device, dtype=torch.long)
    if diagram.numel() == 0:
        return coords.new_zeros(0)
    mask = diagram[:, 1] > l_star
    if not torch.any(mask):
        return coords.new_zeros(0)
    edges = pairing[mask, 1:3]
    u, v = edges[:, 0], edges[:, 1]
    radial = torch.cdist(coords, coords.mean(0, keepdim=True)).squeeze(1)
    outer = torch.where(radial[u] >= radial[v], u, v)
    inner = torch.where(radial[u] >= radial[v], v, u)
    return torch.norm(coords[outer] - coords[inner].detach(), dim=1)


def _ph_term(gb, gmask, mean, std, tolerance,
             ring_lo_frac, ring_hi_frac, n_rings, weights):
    """MacroGuide H1-birth + H1-death + H0-death on ONE batch of latent point clouds,
    with all thresholds in units of the calibrated consecutive-residue latent distance.

    gb:   [bs, Lmax, 3] latent channel-0 points (from graph_to_batch)
    gmask:[bs, Lmax]    valid-node mask
    """
    m, s = float(mean), float(std)
    l_star = m + tolerance * s                     # "one chemical bond" in latent units
    w_b, w_d, w_h0 = weights
    total = gb.new_tensor(0.0)
    clouds = [gb[b][gmask[b].bool()] for b in range(gb.size(0))]
    clouds = [c for c in clouds if c.size(0) >= 3]  # need >=3 pts for an H1 ring
    if not clouds:
        return total
    persistence = _VR(clouds)                       # list; [0]=H0, [1]=H1 per cloud
    for coords, info in zip(clouds, persistence):
        L = coords.size(0)
        d_min, d_max = ring_lo_frac * L * m, ring_hi_frac * L * m   # target ring "size"
        for birth, death in _top_h1(coords, info[1], n_rings):
            total = total + w_b * torch.relu(birth - l_star).pow(2.0)   # ring is chemical
            total = total + w_d * _window_hinge(death, d_min, d_max)     # ring size window
        h0 = _long_h0(coords, info[0], l_star)
        if h0.numel():
            total = total + w_h0 * torch.relu(h0 - l_star).pow(2.0).sum()  # stay connected
    return total


def ph_closure_energy(X, mask_generate, batch_ids, mean, std,
                      tolerance=3.0, ring_lo_frac=0.6, ring_hi_frac=1.4,
                      n_rings=1, weights=(1.0, 1.0, 0.5), **kw):
    """PepGLAD energy_func: base dist_energy + MacroGuide PH ring-closure term.
    Signature matches cyclic_closure_energy so it drops into sample_opt['energy_func']."""
    base = dist_energy(X, mask_generate, batch_ids, mean, std, tolerance=tolerance)
    gen_X = X[mask_generate][:, 0]
    gb, gmask = graph_to_batch(gen_X, batch_ids[mask_generate], mask_is_pad=False)

    if not _HAS_TDA:
        if not _WARNED["fallback"]:
            print("[ph_closure_energy] torch_topological unavailable -> falling back to "
                  "head-to-tail first<->last latent penalty (incumbent cyclic term).")
            _WARNED["fallback"] = True
        lengths = gmask.sum(-1)
        valid = lengths >= 2
        first = gb[:, 0]
        last = gb[torch.arange(gb.size(0), device=gb.device),
                  (lengths - 1).clamp(min=0).long()]
        d = torch.norm(first - last, dim=-1)
        m, s = round(float(mean), 4), round(float(std), 4)
        lb, ub = m - tolerance * s, m + tolerance * s
        loss = torch.where((d < lb) & valid, lb - d, torch.zeros_like(d))
        loss = torch.where((d > ub) & valid, d - ub, loss)
        return base + torch.sum(loss)

    ph = _ph_term(gb, gmask, mean, std, tolerance,
                  ring_lo_frac, ring_hi_frac, n_rings, weights)
    return base + ph
