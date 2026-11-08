#!/usr/bin/env python3
"""m2_peptide_ldm.py — PeptideOnlyLDMPepDesign + PeptideOnlyFullDPM: the root-cause fix that lets the
vendored PepGLAD latent-diffusion model TRAIN + SAMPLE on PEPTIDE-ONLY (no-receptor) records like CREMP.

============================================================================================================
THE VERIFIED M2 BLOCKER (the M2 analog of the M1 peptide-only bug — traced, not assumed)
============================================================================================================
PepGLAD's diffusion operates in a RECEPTOR-CENTERED, RECEPTOR-SCALED coordinate frame. Two places in the
stock code hard-require a receptor (the `~mask_generate` region), and BOTH break on a peptide-only batch
where every residue is the generated peptide (mask == 1 everywhere):

  1. FullDPM._normalize_position (models/LDM/diffusion/dpm_full.py:138-152):
         ctx_mask = (~mask_generate[:,None].expand_as(atom_mask)) & atom_mask   # <- receptor CA only
         ctx_mask[:,0]=0; ctx_mask[:,2:]=0
         centers = scatter_mean(X[ctx_mask], batch_ids[...][ctx_mask], dim=0)    # X[ctx_mask] is EMPTY
         centers = centers[batch_ids].unsqueeze(1)                               # -> index into size-0 -> CRASH
     For peptide-only, ~mask_generate is all-False, so ctx_mask is all-False, X[ctx_mask] is [0,3], and
     scatter_mean over zero rows returns a [0,3] tensor; `centers[batch_ids]` then indexes a size-0 dim ->
     IndexError on CPU / device-side assert on CUDA. The diffusion CANNOT center a peptide-only batch.

  2. The covariance matrix L (data/codesign.py:125-129):
         cov = calculate_covariance_matrix(X[~mask][:,1][atom_mask[~mask][:,1]].numpy())  # RECEPTOR CA only
     For peptide-only, X[~mask] is empty -> np.cov of an empty array -> nan/ValueError. So
     `use_covariance_matrix: true` is impossible peptide-only; L MUST be None (fixed `std` scaling instead).

Neither is a bug in PepGLAD — they are correct for the peptide-PROTEIN co-design task it ships for. But for
the M2 stage-2b UNCONDITIONAL cyclic mid-train (CREMP has no receptor), the diffusion needs a peptide-frame.

============================================================================================================
THE FIX (faithful to the architecture, no production file edited — CLAUDE.md: fix root cause, subclass)
============================================================================================================
Center the diffusion coordinate frame on the PEPTIDE itself (the generated region) instead of the receptor,
and use the fixed `std` scaling (L=None). This is the minimal, geometry-consistent change:

  * PeptideOnlyFullDPM(FullDPM) overrides ONLY _normalize_position: when the context (receptor) region is
    empty for a sample, fall back to centering on that sample's generated (peptide) CA atoms. When a
    receptor IS present it behaves EXACTLY like the stock FullDPM (so a future 2c target-SFT that mixes in
    bound complexes still works unchanged). L=None path (fixed std) is used throughout for 2b.
  * PeptideOnlyLDMPepDesign(LDMPepDesign) swaps in the peptide-only diffusion. Everything else — the frozen
    AE, aa_feature, abs_position_encoding, hidden2latent, the forward/sample flow, the loss — is inherited
    verbatim from LDMPepDesign. The AE is still loaded + frozen by the parent __init__ (torch.load +
    requires_grad=False + eval), so the v1 AE remains the fixed autoencoder.

WHY CENTER-ON-PEPTIDE IS CORRECT (not a hack): _normalize_position only removes a per-sample translation
(equivariance) and divides by a scalar std. The diffusion is SE(3)-equivariant; the choice of center is a
gauge. For an unconditional peptide, the peptide's own centroid is the natural, well-defined origin — this
is exactly what an unconditional macrocycle diffusion (e.g. RINGER-style) does. The receptor center only
matters when the peptide must be placed RELATIVE to a binding site (2c), which 2b does not do.

WARM-START COMPATIBILITY: PeptideOnlyFullDPM / PeptideOnlyLDMPepDesign add ZERO parameters (only override a
method), so the epoch-221 diffusion state_dict loads into them 1:1 (see m2_train_ldm.warm_start_diffusion).

IMPORT-TO-REGISTER: importing this module registers 'PeptideOnlyLDMPepDesign'. The M2 entrypoint imports it
before train.create_dataset / R.construct run so the M2 config's class name resolves.
"""
from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent / "runtime" / "PepGLAD"
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import torch
from torch_scatter import scatter_mean

from utils import register as R
from models.LDM.ldm import LDMPepDesign
from models.LDM.diffusion.dpm_full import FullDPM, low_trianguler_inv


class PeptideOnlyFullDPM(FullDPM):
    """FullDPM whose position normalization does NOT crash when a sample has no receptor/context region.

    THE ONLY CHANGE vs stock FullDPM: pass an explicit dim_size to scatter_mean so a sample with zero
    context CA atoms yields a proper zero-center (shape [n_samples,3]) instead of an empty [0,3] tensor that
    then crashes at `centers[batch_ids]` (IndexError on CPU / device assert on CUDA). This is the M2 analog
    of the M1 peptide-only fix. When a receptor IS present (mixed batch / future 2c), behaviour is IDENTICAL
    to stock (receptor-CA center).

    NOTE ON THE PEPTIDE-ONLY FRAME (verified against ldm.py:100-107,174-182): for the generated (peptide)
    region PepGLAD zeroes the coords (X[mask]=0) and sets the generated atom_mask so ONLY the latent channel
    (channel 0) is present and CA (channel 1) is masked OFF. So both the receptor-CA mask AND the peptide-CA
    mask are empty for a peptide-only sample -> the center resolves to the ORIGIN (0). That is exactly right
    for UNCONDITIONAL generation: the diffusion runs in an origin-centered, std-scaled frame. The fallback
    peptide-CA branch below is retained for robustness / any future variant that keeps CA visible; today it
    is a no-op that also resolves to 0. The point of this class is solely: DO NOT CRASH on an empty context.
    """

    def _normalize_position(self, X, batch_ids, mask_generate, atom_mask, L=None):
        # --- context (receptor) CA mask, exactly as stock ---
        ctx_mask = (~mask_generate[:, None].expand_as(atom_mask)) & atom_mask
        ctx_mask[:, 0] = 0
        ctx_mask[:, 2:] = 0  # only retain CA

        n_samples = int(batch_ids.max().item()) + 1 if batch_ids.numel() > 0 else 0

        # per-sample count of context CA atoms -> which samples lack a receptor
        ctx_counts = scatter_mean(
            ctx_mask.any(dim=-1).float(), batch_ids, dim=0, dim_size=n_samples
        )  # >0 for samples that have >=1 context CA, 0 for peptide-only samples

        if (ctx_counts > 0).all():
            # every sample has a receptor -> stock behaviour, unchanged
            centers = scatter_mean(X[ctx_mask], batch_ids[:, None].expand_as(ctx_mask)[ctx_mask], dim=0)
            centers = centers[batch_ids].unsqueeze(1)
        else:
            # >=1 peptide-only sample: center each sample on its CA atoms. Prefer receptor CA where present
            # (keeps stock frame for mixed batches / future 2c); else use the peptide (generated) CA atoms.
            pep_ca_mask = mask_generate[:, None].expand_as(atom_mask) & atom_mask
            pep_ca_mask = pep_ca_mask.clone()
            pep_ca_mask[:, 0] = 0
            pep_ca_mask[:, 2:] = 0  # only CA
            # union: receptor CA for samples that have one, peptide CA for the rest
            has_ctx_row = (ctx_counts[batch_ids] > 0)[:, None].expand_as(atom_mask)
            center_mask = torch.where(has_ctx_row, ctx_mask, pep_ca_mask)
            centers = scatter_mean(
                X[center_mask], batch_ids[:, None].expand_as(center_mask)[center_mask],
                dim=0, dim_size=n_samples,
            )
            centers = centers[batch_ids].unsqueeze(1)

        if L is None:
            X = (X - centers) / self.std
        else:
            with torch.no_grad():
                L_inv = low_trianguler_inv(L)
            X = X - centers
            X = torch.matmul(L_inv[batch_ids][..., None, :, :], X.unsqueeze(-1)).squeeze(-1)
        return X, centers


@R.register("PeptideOnlyLDMPepDesign")
class PeptideOnlyLDMPepDesign(LDMPepDesign):
    """LDMPepDesign with a peptide-only-aware diffusion. AE handling (frozen v1 AE) is inherited unchanged."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # RETYPE the constructed diffusion to the peptide-only variant. PeptideOnlyFullDPM adds NO __init__,
        # NO parameters, NO state — it ONLY overrides _normalize_position (the one method that assumes a
        # receptor). Reassigning __class__ is therefore safe and total: it swaps the method-resolution
        # without touching any weight/buffer, so:
        #   * the epoch-221 diffusion state_dict still loads into self.diffusion 1:1 during warm-start
        #     (same parameters/buffers, same names);
        #   * the override survives torch.save/torch.load of the whole LDM object (pickle records the class
        #     PeptideOnlyFullDPM, which m2_eval/m2_train import before unpickling);
        #   * add_noise/denoise/sample/eps_net and every other diffusion method are inherited verbatim.
        # We assert the parent built a plain FullDPM (not something unexpected) before retyping.
        assert type(self.diffusion) is FullDPM, (
            f"expected LDMPepDesign to build a FullDPM, got {type(self.diffusion).__name__}"
        )
        self.diffusion.__class__ = PeptideOnlyFullDPM
