#!/usr/bin/env python3
"""m1_closure_ae.py — ClosureAwareAutoEncoder + ClosureAETrainer.

M4 co-development with M1 (docs/20260927_PEPTIDE_PARALLEL_WORK_PLAN.md: "M0 finding — bring M4
forward ... M1's acceptance includes ring-closure recovery"). Two pieces, both minimal + clearly
flagged, both subclasses of the vendored classes (no production file is edited):

  1. ClosureAwareAutoEncoder(AutoEncoder)
     Adds ONE optional loss term: the head-to-tail macrocycle closing bond length, i.e. for each
     peptide in the batch the distance between the LAST residue's backbone C (channel 2) and the FIRST
     residue's backbone N (channel 0), regressed toward a target amide length (~1.33 A) with L1.
     WHY A NEW TERM (verified, not assumed): the stock struct-profile `bb_bond_lengths` term
     (models/dyMEAN/nn_utils.py:_cal_backbone_bond_lengths) only supervises SEQUENTIAL i->i+1 amides
     (`X[1:,0] - X[:-1,2]`). It never includes the C_last->N_first closing bond, so it cannot teach
     ring closure — which is exactly why the M0 linear AE reconstructs only 32% closed rings. This term
     is the smallest change that makes closure a supervised objective.
     Controlled by `ring_closure_loss_weight` (config; default 0.0 => behaves EXACTLY like the stock
     AutoEncoder Option-B mid-train). Set > 0 to enable the M4 closure objective.

  2. ClosureAETrainer(AutoEncoderTrainer)
     Adds ring-closure VALIDATION METRICS (always tracked, regardless of the loss weight), logged each
     validation epoch via TensorBoard + printed, using the SAME closing-bond geometry definition M0's
     ring_closed() uses (a non-sequential C..N within amide range = closed). This is the leakage-honest
     acceptance signal: does the reconstruction keep the macrocycle closed on the frozen hold-out?
     The trainer's selection metric is UNCHANGED (validation loss) so warm-start behaviour is stable;
     closure is reported alongside, not optimized-for by the checkpoint selector.

WARM-START: this class shares AutoEncoder's __init__ signature and parameter names exactly (it only
adds attributes), so the epoch-221 .autoencoder state_dict loads into it 1:1 (see m1_train_ae.py).

IMPORT-TO-REGISTER: importing this module registers 'ClosureAwareAutoEncoder' + 'ClosureAETrainer'.
"""
from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent / "runtime" / "PepGLAD"
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import torch
import torch.nn.functional as F

from utils import register as R
from models.autoencoder.model import AutoEncoder
from trainer.autoencoder_trainer import AutoEncoderTrainer

AMIDE_TARGET = 1.33   # ideal peptide C-N amide bond length (A)
# Ring-closure validity window for the METRIC — mirrors m0_frozen_probe.AMIDE_BOND_LO/HI so the M1
# training-time closure metric is directly comparable to the M0 baseline (0.32).
RING_LO, RING_HI = 1.0, 2.0


def _peptide_bounds(batch_ids: torch.Tensor):
    """Given per-residue batch ids (contiguous, ascending) for the MASKED/generated residues, return
    (first_idx, last_idx) row indices of each peptide. Assumes residues of a peptide are contiguous,
    which holds: dataset emits residues in order and collate cats per-item tensors in batch order."""
    n = batch_ids.shape[0]
    if n == 0:
        return batch_ids.new_zeros(0), batch_ids.new_zeros(0)
    change = torch.ones(n, dtype=torch.bool, device=batch_ids.device)
    change[1:] = batch_ids[1:] != batch_ids[:-1]
    firsts = torch.nonzero(change, as_tuple=False).squeeze(-1)
    lasts = torch.cat([firsts[1:] - 1, torch.tensor([n - 1], device=batch_ids.device)])
    return firsts, lasts


@R.register("ClosureAwareAutoEncoder")
class ClosureAwareAutoEncoder(AutoEncoder):
    def __init__(self, *args, ring_closure_loss_weight: float = 0.0,
                 ring_closure_target: float = AMIDE_TARGET, **kwargs):
        super().__init__(*args, **kwargs)
        self.ring_closure_loss_weight = float(ring_closure_loss_weight)
        self.ring_closure_target = float(ring_closure_target)

    def forward(self, X, S, mask, position_ids, lengths, atom_mask, teacher_forcing=True):
        # Reuse the entire stock forward for the base losses. It returns:
        #   recon_loss, (seq_recon_loss, aar), (struct_recon_loss, loss_profile), (h_kl, z_kl, coord_reg)
        base = super().forward(X, S, mask, position_ids, lengths, atom_mask, teacher_forcing)
        if self.ring_closure_loss_weight <= 0.0 or self.mode == "fixseq":
            return base  # pure Option-B mid-train (or fixseq): identical to stock AutoEncoder

        recon_loss, seq_detail, structure_detail, kl_detail = base
        struct_recon_loss, loss_profile = structure_detail

        # Recompute the masked-region reconstruction to get recon_X for the closing bond. This mirrors
        # the stock forward's encode/decode path exactly (teacher_forcing kept as passed). Cheap: one
        # extra decode; we do it under no_grad-free so the term trains the decoder.
        if self.mask_ratio > 0:
            input_S, input_atom_mask = self._mask_pep(S, atom_mask, mask)
        else:
            input_S, input_atom_mask = S, atom_mask
        H, Z, _, _ = self.encode(X, input_S, mask, position_ids, lengths, input_atom_mask)
        _, recon_X = self.decode(X, S, H, Z, mask, position_ids, lengths, atom_mask, teacher_forcing)
        # recon_X: [Nmask, 14, 3] over the generated (peptide) residues, in dataset order.
        batch_ids = self.get_batch_ids(S, lengths)[mask]
        firsts, lasts = _peptide_bounds(batch_ids)
        # closing bond = C of last residue (channel 2) -> N of first residue (channel 0)
        c_last = recon_X[lasts, 2]     # [B, 3]
        n_first = recon_X[firsts, 0]   # [B, 3]
        close_len = torch.norm(c_last - n_first, dim=-1)  # [B]
        ring_closure_loss = F.l1_loss(close_len, torch.full_like(close_len, self.ring_closure_target))

        loss_profile = dict(loss_profile)
        loss_profile["ring_closure_loss"] = ring_closure_loss
        # Fold into the coord side of the objective, same coord_loss_ratio scaling the other coord terms use.
        recon_loss = recon_loss + self.coord_loss_ratio * self.ring_closure_loss_weight * ring_closure_loss
        return recon_loss, seq_detail, (struct_recon_loss, loss_profile), kl_detail


@R.register("ClosureAETrainer")
class ClosureAETrainer(AutoEncoderTrainer):
    """AutoEncoderTrainer + ring-closure validation metrics (reconstruction closed-ring rate + mean
    closing-bond length + input closed-ring rate for reference). Selection metric unchanged (val loss)."""

    def _valid_epoch_begin(self, device):
        self._closure_acc = {"recon_closed": 0, "input_closed": 0, "n": 0, "close_len_sum": 0.0}
        return super()._valid_epoch_begin(device)

    @torch.no_grad()
    def _closing_bond_lengths(self, X_mask, batch_ids):
        """Return per-peptide closing C_last..N_first distances from a [Nmask,14,3] coord tensor."""
        firsts, lasts = _peptide_bounds(batch_ids)
        c_last = X_mask[lasts, 2]
        n_first = X_mask[firsts, 0]
        return torch.norm(c_last - n_first, dim=-1)  # [B]

    @torch.no_grad()
    def valid_step(self, batch, batch_idx):
        # Base loss (drives selection + LR schedule) — unchanged.
        loss = super().valid_step(batch, batch_idx)

        # Extra: reconstruct deterministically and measure closure the same way M0 does.
        model = self.model.module if hasattr(self.model, "module") else self.model
        X, S, mask = batch["X"], batch["S"], batch["mask"]
        position_ids, lengths, atom_mask = batch["position_ids"], batch["lengths"], batch["atom_mask"]
        # DETERMINISTIC reconstruction (posterior mean, no VAE resampling) — matches M0's probe path so
        # the closure metric is directly comparable to the M0 baseline (0.32). encode(no_randomness=True)
        # then test(given latents) makes test() skip re-encoding and take the fixed latents.
        H, Z, _, _ = model.encode(X, S, mask, position_ids, lengths, atom_mask, no_randomness=True)
        rec_X, _rec_S, _ppls = model.test(
            X, S, mask, position_ids, lengths, atom_mask,
            given_laten_H=H, given_latent_X=Z, return_tensor=True,
        )  # rec_X: [Nmask, 14, 3]
        batch_ids = model.get_batch_ids(S, lengths)[mask]
        true_X_mask = X[mask]

        rec_close = self._closing_bond_lengths(rec_X, batch_ids)
        in_close = self._closing_bond_lengths(true_X_mask, batch_ids)
        recon_closed = ((rec_close >= RING_LO) & (rec_close <= RING_HI)).sum().item()
        input_closed = ((in_close >= RING_LO) & (in_close <= RING_HI)).sum().item()
        self._closure_acc["recon_closed"] += recon_closed
        self._closure_acc["input_closed"] += input_closed
        self._closure_acc["n"] += rec_close.shape[0]
        self._closure_acc["close_len_sum"] += rec_close.sum().item()
        return loss

    def _valid_epoch_end(self, device):
        acc = getattr(self, "_closure_acc", None)
        if acc and acc["n"] > 0 and self._is_main_proc():
            recon_rate = acc["recon_closed"] / acc["n"]
            input_rate = acc["input_closed"] / acc["n"]
            mean_len = acc["close_len_sum"] / acc["n"]
            from utils.logger import print_log
            print_log(
                f"[RING-CLOSURE val] recon_closed_rate={recon_rate:.4f} "
                f"input_closed_rate={input_rate:.4f} mean_close_bond={mean_len:.3f}A "
                f"(M0 baseline recon=0.32) n={acc['n']}"
            )
            self.log("Ring/ReconClosedRate", recon_rate, self.epoch)
            self.log("Ring/InputClosedRate", input_rate, self.epoch)
            self.log("Ring/MeanClosingBond", mean_len, self.epoch)
        return super()._valid_epoch_end(device)
