"""
Developability-Conditioned Generation (DCG) — proprietary guidance for PepGLAD-class sampling.

WHAT THIS IS (the IP): instead of sampling for binding pose only and filtering for developability
afterwards (what property_guided_selection.py does, and what every published peptide generator does),
this steers the diffusion/flow SAMPLING itself toward candidates that are jointly
  (1) target-binding,   (2) synthetically accessible,   (3) permeable / drug-like.
i.e. the three Guangzhou-tender axes baked into the generative process.

HOW IT PLUGS IN: PepGLAD samples with `sample_opt = {'energy_func': f, 'energy_lambda': λ}` and takes
∇_X f at each denoising step (see ph_closure_guidance.py, which slots a ring-closure term into exactly
this hook). `developability_energy` has the SAME signature as PepGLAD's `cyclic_closure_energy` /
`ph_closure_energy` and returns:

    E = dist_energy(base geometry)  +  Σ_k  w_k(t) · G_k · term_k(X)

where term_k are differentiable developability proxies on the GENERATED atoms (mask_generate=True),
w_k(t) is a per-objective, time-scheduled weight (Pareto weights from the customer's target product
profile), and G_k is a per-term gradient-scale constant that matches each term's ∇-magnitude to the
base geometry term's O(1) scale — the hard-won lesson from the PH guidance work (un-scaled property
gradients swamp the geometry term and collapse/NaN the sample; ph_closure_guidance.py:47-53).

PROTOTYPE STATUS (honest): the property terms below are DIFFERENTIABLE PHYSICS PROXIES computable from
the all-atom coords — good enough to prove DCG changes the sampled distribution (P0). P1 replaces each
proxy with a LEARNED differentiable head distilled from our real predictors (EnsembleCycPerm ΔPSA3D for
permeability, an SA model, a docking/FEP ΔG surrogate) so the guidance matches the production scorers.
P2 fine-tunes the generator with DPO on verify-layer + wet-lab preferences (the closed-loop moat).

Usage (mirrors ph_closure_guidance.py):
    from developability_guidance import developability_energy
    from functools import partial
    tpp = {'affinity': 1.0, 'sa': 0.5, 'permeability': 0.7}   # customer target product profile
    _energy = partial(developability_energy, weights=tpp)
    sample_opt = {'energy_func': _energy, 'energy_lambda': args.energy_lambda}

At runtime any failing term degrades to 0 (never NaN) so a guided run can never do worse than the base
geometry guidance.
"""
from __future__ import annotations
import torch
from models.LDM.energies.dist import dist_energy   # PepGLAD base geometry guidance (same import as ph_closure)

# ── Gradient-scale constants (match each term's ∇-magnitude to dist_energy's O(1) scale). ──────────────
# Calibrated to the same target band as PH_ENERGY_SCALE in ph_closure_guidance.py (base cyclic term
# gradients were ~0–1.4). These are starting points; P1 auto-calibrates per-term on a warmup batch.
G_AFFINITY = 1.0
G_SA       = 0.15
G_PERM     = 0.10


def _generated_mask(mask_generate):
    return mask_generate.bool()


def _time_weight(schedule_t, kind):
    """Guidance schedule: geometry/affinity strong EARLY (get a binder), developability ramped LATE
    (refine to makeable/permeable). schedule_t in [0,1] = fraction of denoising completed (0=noisy,1=clean).
    Avoids the early-collapse mode we saw with a flat-strength penalty."""
    if schedule_t is None:
        return 1.0
    t = float(schedule_t)
    if kind == 'affinity':
        return 1.0                      # always on — binding is the primary objective
    # developability terms ramp in over the second half of denoising
    return max(0.0, (t - 0.4) / 0.6)


# ── Differentiable developability proxies on the generated peptide atoms ───────────────────────────────
def _affinity_term(X, gmask, batch_ids, mean, std):
    """Interface contact term: reward generated (peptide) atoms making close, non-clashing contacts with
    the receptor (mask_generate=False) atoms of the SAME complex. Differentiable proxy for ΔG until the
    learned surrogate lands (P1). Lower energy = tighter interface."""
    Xr = X * std + mean                         # de-normalise to Angstrom for physical distances
    gen = gmask
    rec = ~gmask
    e = X.new_zeros(())
    for b in torch.unique(batch_ids):
        sel = batch_ids == b
        g = gen & sel
        r = rec & sel
        if g.sum() == 0 or r.sum() == 0:
            continue
        d = torch.cdist(Xr[g], Xr[r])           # (n_gen, n_rec) Angstrom
        dmin = d.min(dim=1).values              # nearest receptor atom per peptide atom
        # LJ-like: reward contacts in the 3.5–5.5 Å band, penalise clashes < 3.0 Å
        contact = torch.exp(-((dmin - 4.5) ** 2) / 2.0)      # peak reward ~4.5 Å
        clash   = torch.relu(3.0 - dmin) ** 2                # steep penalty inside 3 Å
        e = e - contact.mean() + clash.mean()
    return e


def _sa_term(X, gmask, batch_ids, mean, std):
    """Synthetic-accessibility proxy: penalise geometric strain in the generated peptide — over-tight
    consecutive-atom spacing and high local curvature correlate with hard-to-synthesise / strained
    macrocycles. Differentiable proxy for the SA model (P1)."""
    Xr = X * std + mean
    e = X.new_zeros(())
    for b in torch.unique(batch_ids):
        g = gmask & (batch_ids == b)
        if g.sum() < 3:
            continue
        c = Xr[g]
        step = (c[1:] - c[:-1]).norm(dim=-1)                 # consecutive spacing
        # penalise deviation from a physical CA-CA-like spacing band (~3.8 Å); strain = variance + tightness
        strain = ((step - 3.8) ** 2).mean() + torch.relu(2.5 - step).pow(2).mean()
        e = e + strain
    return e


def _permeability_term(X, gmask, batch_ids, mean, std):
    """Permeability proxy (the 'chameleon' term): reward BURIAL of polar surface in the generated peptide —
    low exposed 3D-PSA is the EnsembleCycPerm ΔPSA3D signal for membrane permeability (perm_dpsa3d.sh).
    Here approximated geometrically as compactness (radius of gyration) of the generated atoms — a
    differentiable stand-in for exposed-polar-surface until the learned ΔPSA3D head lands (P1)."""
    Xr = X * std + mean
    e = X.new_zeros(())
    for b in torch.unique(batch_ids):
        g = gmask & (batch_ids == b)
        if g.sum() < 3:
            continue
        c = Xr[g]
        rg = (c - c.mean(dim=0, keepdim=True)).norm(dim=-1).mean()   # radius of gyration proxy
        e = e + rg                                                   # reward compaction (lower Rg → PSA burial)
    return e


_TERMS = {
    'affinity':     (_affinity_term,     G_AFFINITY),
    'sa':           (_sa_term,           G_SA),
    'permeability': (_permeability_term, G_PERM),
}


def developability_energy(X, mask_generate, batch_ids, mean, std,
                          weights=None, schedule_t=None, tolerance=1.0, verbose=False):
    """PepGLAD energy_func: base dist_energy + Σ_k w_k(t)·G_k·term_k(X).
    Signature matches cyclic_closure_energy / ph_closure_energy so it drops into sample_opt['energy_func'].

    weights: dict of Pareto weights per objective (customer target product profile), e.g.
             {'affinity':1.0, 'sa':0.5, 'permeability':0.7}. Missing keys default to 0 (term off)."""
    weights = weights or {'affinity': 1.0}
    base = dist_energy(X, mask_generate, batch_ids, mean, std, tolerance=tolerance)
    gmask = _generated_mask(mask_generate)
    total = base
    for name, (fn, gscale) in _TERMS.items():
        w = float(weights.get(name, 0.0))
        if w == 0.0:
            continue
        try:
            term = fn(X, gmask, batch_ids, mean, std)
            if not torch.isfinite(term):
                if verbose:
                    print(f"[developability] term '{name}' non-finite -> skipped this step")
                continue
            total = total + w * _time_weight(schedule_t, name) * gscale * term
        except Exception as exc:   # never NaN/crash a sampling run for a guidance term
            if verbose:
                print(f"[developability] term '{name}' FAILED -> 0 this step ({exc})")
            continue
    return total
