#!/usr/bin/env python3
"""m2_train_ldm.py — M2 stage-2b entrypoint: cyclic mid-train of the PepGLAD LATENT-DIFFUSION generator
over the v1-AE latent, warm-started from the epoch-221 diffusion. Drives the OFFICIAL PepGLAD LDMTrainer
(train.py's machinery), not a custom loop.

============================================================================================================
THE CORE ARCHITECTURAL ANSWER (verified against the code — see m2_peptide_ldm.py for the peptide-only fix)
============================================================================================================
PepGLAD = latent diffusion OVER an AE latent. An LDMPepDesign bundles {autoencoder (FROZEN) + diffusion}:
  * LDMPepDesign.__init__(autoencoder_ckpt=...) does `self.autoencoder = torch.load(autoencoder_ckpt)`
    then sets every AE param requires_grad=False and .eval(). So the AE is ALWAYS frozen and loaded from a
    checkpoint FILE at construction. (models/LDM/ldm.py:39-42, verified.)
  * LDMPepDesign.forward encodes X->(H,Z) with the frozen AE under no_grad, then trains ONLY the diffusion
    to denoise that latent. The optimizer trains only requires_grad params (abs_trainer.py:281), so the AE
    never updates. (ldm.py:76-132, verified.)

M1 produced a NEW v1 AE whose latent distribution DIFFERS from the epoch-221 AE. The epoch-221 diffusion was
trained over the OLD latent, so it will not match the v1 latent. The correct M2-2b construction is therefore:

  autoencoder = v1 AE (FROZEN — the AE is done)         <- config `autoencoder_ckpt: <v1 AE ckpt>`
  diffusion   = epoch-221 diffusion weights (warm start) <- WARM-START only the diffusion sub-tree, NOT the AE
              -> CONTINUE-train (mid-train) the diffusion to diffuse over the v1 latent on CREMP peptide-only.

WHY WE CANNOT USE STOCK train.py's load_ckpt FOR THE WARM-START (the trap this file avoids):
  train.py:load_ckpt does `model.load_state_dict(trained.state_dict())`. For the LDM, `trained` is the
  epoch-221 LDMPepDesign, whose state_dict INCLUDES `autoencoder.*` keys (the OLD AE). Loading the full
  state_dict would OVERWRITE the freshly-loaded v1 AE with the epoch-221 AE — silently reverting M1. So this
  entrypoint loads ONLY the non-`autoencoder.*` keys (diffusion + hidden2latent + abs_position_encoding),
  strict=False, and prints a loaded/total report as the honest guard.

LATENT-STAT HANDLING (verified — no recompute needed for 2b):
  The diffusion does NOT depend on any global latent-normalization statistic that would need recomputing for
  the v1 latent. Two per-sample geometric normalizations exist, both computed on-the-fly from coordinates:
    (a) coordinate frame: FullDPM._normalize_position centers + scales the latent COORDINATE (Z) channel.
        Stock centers on the receptor; for peptide-only that region is empty and crashes -> we center on the
        peptide (m2_peptide_ldm.PeptideOnlyFullDPM) and use the FIXED scalar `std` (buffer, part of the
        warm-started diffusion state, carried over unchanged). No per-dataset stat.
    (b) covariance L (data): receptor-CA covariance; impossible peptide-only -> `use_covariance_matrix:false`
        -> L=None -> fixed-`std` path. No per-dataset stat.
  The latent CONTENT statistics (the v1 AE's H/Z distribution) are exactly what the diffusion RE-LEARNS during
  mid-train — that is the point of 2b. `set_consec_dist` (setup_latent_guidance.py) computes a consecutive-
  latent-distance mean/std used ONLY for OPTIONAL sampling-time geometry guidance; it is NOT used in training
  and is (re)computed AFTER training over the v1 latent in the eval step. So there is no training-time latent
  stat to recompute.

PEPTIDE-ONLY LDM TRAINING — DOES IT WORK? YES, WITH THE m2_peptide_ldm FIX.
  The stock LDM diffusion strictly requires a receptor (position normalization + covariance both key on
  ~mask_generate). CREMP is receptor-free. Without the fix, 2b would crash at _normalize_position (the M2
  analog of the M1 peptide-only bug). m2_peptide_ldm.PeptideOnlyLDMPepDesign centers the diffusion frame on
  the peptide instead, so unconditional cyclic mid-train trains cleanly. The AE already handles peptide-only
  (M1 proved this). Flagged loudly in the review note.

USAGE
  python3 m2_train_ldm.py --gpus 0 --config m2_ldm_midtrain.yaml \
    --warm_start_ldm_ckpt=./data/epoch221.ckpt \
    --model.autoencoder_ckpt=./data/v1_ae.ckpt \
    --dataset.train.mmap_dir=./data/cremp_pepglad/train \
    --dataset.valid.mmap_dir=./data/cremp_pepglad/valid
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "runtime" / "PepGLAD"
for p in (str(RUNTIME), str(ROOT)):
    if p not in sys.path:
        sys.path.insert(0, p)

# Reduce CUDA fragmentation (the LDM validation runs a full reverse-diffusion sample each val epoch, raising
# peak memory). Must be set BEFORE torch initializes the CUDA allocator. Same fix that cured the M1 OOM.
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")

import yaml
import torch

# Register M2 + M1 classes (side-effect imports) BEFORE the official builders run.
import m1_peptide_dataset  # noqa: F401  registers PeptideOnlyCoDesignDataset (reused verbatim for CREMP)
import m1_closure_ae       # noqa: F401  registers ClosureAwareAutoEncoder so torch.load can unpickle the v1 AE
import m2_peptide_ldm      # noqa: F401  registers PeptideOnlyLDMPepDesign

# Official PepGLAD machinery — reused as-is.
import models  # noqa: F401  registers AutoEncoder / LDMPepDesign
from utils import register as R
from utils.logger import print_log
from utils.random_seed import setup_seed, SEED
from utils.config_utils import overwrite_values
from utils.nn_utils import count_parameters
from data import create_dataset, create_dataloader
from trainer import create_trainer


def parse():
    parser = argparse.ArgumentParser(description="M2 LDM cyclic mid-train (2b, warm-started diffusion)")
    parser.add_argument("--gpus", type=int, nargs="+", required=True, help="gpu ids, -1 for cpu")
    parser.add_argument("--local_rank", type=int, default=-1)
    parser.add_argument("--config", type=str, required=True, help="path to the M2 yaml")
    parser.add_argument("--seed", type=int, default=SEED)
    return parser.parse_known_args()


def warm_start_diffusion(model, ldm_ckpt_path: str):
    """Copy the epoch-221 DIFFUSION weights into `model`, leaving the (v1) autoencoder untouched.

    Loads ONLY the non-`autoencoder.*` keys from the epoch-221 LDMPepDesign state_dict (diffusion.*,
    hidden2latent.*, abs_position_encoding.*). strict=False; prints a loaded/total report. Any
    `autoencoder.*` key in the source is DROPPED so the v1 AE (already loaded + frozen by __init__) survives.
    """
    import models as _m

    obj = torch.load(ldm_ckpt_path, map_location="cpu", weights_only=False)
    if isinstance(obj, _m.LDMPepDesign):
        src_full = obj.state_dict()
    else:
        raise TypeError(
            f"warm_start_ldm_ckpt is a {type(obj).__name__}; expected LDMPepDesign (the epoch-221 release). "
            f"Cannot extract diffusion weights for warm-start."
        )

    # keep everything EXCEPT the frozen autoencoder sub-tree (that stays the v1 AE)
    src_diff = {k: v for k, v in src_full.items() if not k.startswith("autoencoder.")}
    dropped_ae = [k for k in src_full if k.startswith("autoencoder.")]

    result = model.load_state_dict(src_diff, strict=False)
    missing = list(getattr(result, "missing_keys", []))
    unexpected = list(getattr(result, "unexpected_keys", []))

    # missing_keys will legitimately include every `autoencoder.*` key of the TARGET (we chose not to load
    # them). Separate those from any UNEXPECTED diffusion-side gap, which would be a real problem.
    missing_ae = [k for k in missing if k.startswith("autoencoder.")]
    missing_non_ae = [k for k in missing if not k.startswith("autoencoder.")]

    n_loaded = len(src_diff) - len(unexpected)
    print_log(
        f"[warm-start] loaded {n_loaded}/{len(src_diff)} diffusion tensors from {ldm_ckpt_path} "
        f"(dropped {len(dropped_ae)} autoencoder.* keys — v1 AE preserved)"
    )
    if missing_non_ae:
        print_log(f"[warm-start] WARNING missing non-AE keys (fresh-init, NOT warm-started): {missing_non_ae}")
    if unexpected:
        print_log(f"[warm-start] WARNING unexpected keys (in ckpt, no target param): {unexpected}")
    print_log(
        f"[warm-start] (expected) {len(missing_ae)} autoencoder.* target keys left at the v1 AE weights"
    )
    # Healthy warm-start: unexpected == [] and missing_non_ae == []. Loud if not.
    return model


def _assert_ae_frozen(model):
    """Verify the AE really is frozen (no AE param will be updated). CLAUDE.md: verify, don't assume."""
    trainable_ae = [n for n, p in model.autoencoder.named_parameters() if p.requires_grad]
    if trainable_ae:
        raise RuntimeError(
            f"v1 AE is NOT frozen — {len(trainable_ae)} AE params have requires_grad=True "
            f"(e.g. {trainable_ae[:3]}). LDMPepDesign.__init__ should have frozen it."
        )
    n_ae = sum(p.numel() for p in model.autoencoder.parameters())
    n_diff = sum(p.numel() for p in model.diffusion.parameters() if p.requires_grad)
    print_log(f"[freeze-check] AE frozen ({n_ae/1e6:.3f}M params, 0 trainable); "
              f"diffusion trainable ({n_diff/1e6:.3f}M params)")


def main(args, opt_args):
    config = yaml.safe_load(open(args.config, "r"))
    config = overwrite_values(config, opt_args)

    # constructing the model loads + FREEZES the v1 AE (model.autoencoder_ckpt path) inside __init__.
    model = R.construct(config["model"])
    _assert_ae_frozen(model)

    warm_ckpt = config.get("warm_start_ldm_ckpt")
    if warm_ckpt:
        model = warm_start_diffusion(model, warm_ckpt)
        _assert_ae_frozen(model)  # re-verify: warm-start must NOT have touched/unfrozen the AE
    else:
        print_log("[warm-start] no warm_start_ldm_ckpt in config — diffusion trained from scratch (NOT 2a)")

    train_set, valid_set, _ = create_dataset(config["dataset"])

    if len(args.gpus) > 1:
        args.local_rank = int(os.environ["LOCAL_RANK"])
        torch.cuda.set_device(args.local_rank)
        torch.distributed.init_process_group(backend="nccl", world_size=len(args.gpus))
    else:
        args.local_rank = -1

    if args.local_rank <= 0:
        print_log(f"Number of parameters (trainable): {count_parameters(model) / 1e6} M")

    train_loader = create_dataloader(train_set, config["dataloader"], len(args.gpus))
    valid_loader = create_dataloader(valid_set, config["dataloader"], validation=True)

    trainer = create_trainer(config, model, train_loader, valid_loader)
    trainer.train(args.gpus, args.local_rank)


if __name__ == "__main__":
    args, opt_args = parse()
    print_log(f"Overwriting args: {opt_args}")
    setup_seed(args.seed)
    main(args, opt_args)
