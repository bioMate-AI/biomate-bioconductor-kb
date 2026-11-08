#!/usr/bin/env python3
"""m2c_train_ldm.py — M2 stage-2c entrypoint: TARGET-CONDITIONED fine-tune of the PepGLAD LATENT-DIFFUSION
generator on REAL bound cyclic-peptide COMPLEXES (D2), warm-started from the epoch-221 linear-complex
diffusion, with the FROZEN v1 AE (M1). Drives the OFFICIAL PepGLAD LDMTrainer (train.py's machinery).

============================================================================================================
2c vs 2b (the pivot — see docs/20260927_PEPTIDE_PARALLEL_WORK_PLAN.md, M2 section)
============================================================================================================
2b (m2_train_ldm.py + m2_peptide_ldm.PeptideOnlyLDMPepDesign) was ABANDONED: PepGLAD's diffusion is
CONDITIONAL by design (receptor-centered frame + receptor-CA covariance + inter-molecular edges). Training it
UNCONDITIONALLY on receptor-free CREMP fought the framework (position-centering, covariance, AND
dpm_full.py:223 inter-edge reshape all assume a receptor).

2c trains on REAL COMPLEXES (a receptor IS present per record), so:
  * the peptide-only patches DO NOT trigger — the STOCK receptor code path runs unchanged. We use STOCK
    LDMPepDesign (NOT PeptideOnlyLDMPepDesign) and STOCK CoDesignDataset (NOT PeptideOnlyCoDesignDataset).
  * use_covariance_matrix: TRUE is now valid (receptor CA exists -> covariance computable), matching the
    stock configs/pepbench/ldm/train_codesign.yaml that trained epoch-221. This keeps 2c on the identical
    normalization the warm-started diffusion was trained under -> minimal distribution shift.

WHAT IS REUSED FROM m2_train_ldm.py (the 2b entrypoint — ~90% reuse, verified correct in M2 construction):
  * warm_start_diffusion(model, ldm_ckpt): loads ONLY the epoch-221 diffusion.* / hidden2latent.* /
    abs_position_encoding.* keys, DROPS every autoencoder.* key so the freshly-loaded v1 AE survives. (In the
    validated 2b run this loaded 84/84 diffusion tensors + dropped 202 autoencoder.* keys.)
  * _assert_ae_frozen(model): verifies 0 AE params are trainable (LDMPepDesign.__init__ froze them).
We IMPORT both from m2_train_ldm to avoid divergence. We do NOT import m2_peptide_ldm (no peptide-only class),
so R.construct(config['model'] class=LDMPepDesign) resolves to the STOCK model.

FROZEN v1 AE: config `model.autoencoder_ckpt` = the M1 v1 AE (epoch39_step3520.ckpt). LDMPepDesign.__init__
torch.load's it, sets requires_grad=False + eval. m1_closure_ae is imported so torch.load can unpickle the v1
AE's custom class (ClosureAwareAutoEncoder).

SMALL-DATA FINE-TUNE (235 complexes -> a real held-out test; guard overfitting + catastrophic forgetting):
  * LOW lr (1e-5, half the 2b mid-train lr, 10x below the from-scratch 1e-4) — nudge the binding prior toward
    cyclic complexes, don't wreck the epoch-221 linear-complex prior.
  * FEW epochs + early stop on held-out VAL loss (patience) — the denoising MSE on a disjoint val split is the
    catastrophic-forgetting / overfitting guard.
  * criterion: Loss (val denoising MSE) is the selection signal (matches stock train_codesign.yaml). With a
    receptor + reference pose present, RMSD/AAR are ALSO logged by the trainer, but val-LOSS is the stable
    early-stop signal on a tiny set.

The config lives in m2c_ldm_finetune.yaml; the spot launcher run_m2c_ldm_finetune.sh fills paths + knobs.

USAGE
  python3 m2c_train_ldm.py --gpus 0 --config m2c_ldm_finetune.yaml \
    --warm_start_ldm_ckpt=./data/epoch221.ckpt \
    --model.autoencoder_ckpt=./data/v1_ae.ckpt \
    --dataset.train.mmap_dir=./data/bound_cyclic_pepglad \
    --dataset.train.specify_index=./data/bound_cyclic_pepglad/train_index.txt \
    --dataset.valid.mmap_dir=./data/bound_cyclic_pepglad \
    --dataset.valid.specify_index=./data/bound_cyclic_pepglad/valid_index.txt
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

# Reduce CUDA fragmentation (LDM validation runs a full reverse-diffusion sample each val epoch). Must be set
# BEFORE torch initializes the CUDA allocator — same fix that cured the M1/M2 OOM.
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")

import yaml
import torch

# Register M1's AE class so torch.load can UNPICKLE the v1 AE checkpoint (ClosureAwareAutoEncoder). We do NOT
# import m2_peptide_ldm here — 2c uses the STOCK LDMPepDesign (receptor present).
import m1_closure_ae  # noqa: F401  registers ClosureAwareAutoEncoder for unpickling the v1 AE

# Official PepGLAD machinery — reused as-is (registers AutoEncoder / LDMPepDesign / CoDesignDataset).
import models  # noqa: F401
from utils import register as R
from utils.logger import print_log
from utils.random_seed import setup_seed, SEED
from utils.config_utils import overwrite_values
from utils.nn_utils import count_parameters
from data import create_dataset, create_dataloader
from trainer import create_trainer

# REUSE the verified warm-start + freeze-check from the 2b entrypoint (identical construction; the ONLY 2c
# difference is stock classes + covariance-on, which are config choices, not code changes to warm-start).
from m2_train_ldm import warm_start_diffusion, _assert_ae_frozen


def parse():
    parser = argparse.ArgumentParser(description="M2 stage-2c: target-conditioned fine-tune on bound cyclic complexes")
    parser.add_argument("--gpus", type=int, nargs="+", required=True, help="gpu ids, -1 for cpu")
    parser.add_argument("--local_rank", type=int, default=-1)
    parser.add_argument("--config", type=str, required=True, help="path to the 2c yaml")
    parser.add_argument("--seed", type=int, default=SEED)
    return parser.parse_known_args()


def _assert_stock_ldm(model):
    """2c must use the STOCK LDMPepDesign (receptor-present path), NOT the peptide-only 2b subclass. Verify the
    diffusion is a plain FullDPM (peptide-only override retypes it to PeptideOnlyFullDPM) — CLAUDE.md: verify."""
    from models.LDM.ldm import LDMPepDesign
    from models.LDM.diffusion.dpm_full import FullDPM
    if not isinstance(model, LDMPepDesign):
        raise RuntimeError(f"2c expects an LDMPepDesign, got {type(model).__name__}")
    if type(model.diffusion) is not FullDPM:
        raise RuntimeError(
            f"2c expects a STOCK FullDPM diffusion (receptor path), got {type(model.diffusion).__name__}. "
            f"Did the config set class: PeptideOnlyLDMPepDesign by mistake? Use LDMPepDesign for complexes."
        )
    print_log("[stock-check] LDMPepDesign + stock FullDPM (receptor-conditioned path) confirmed")


def main(args, opt_args):
    config = yaml.safe_load(open(args.config, "r"))
    config = overwrite_values(config, opt_args)

    # constructing the model loads + FREEZES the v1 AE (model.autoencoder_ckpt) inside __init__.
    model = R.construct(config["model"])
    _assert_stock_ldm(model)
    _assert_ae_frozen(model)

    warm_ckpt = config.get("warm_start_ldm_ckpt")
    if warm_ckpt:
        model = warm_start_diffusion(model, warm_ckpt)
        _assert_ae_frozen(model)  # re-verify: warm-start must NOT have touched/unfrozen the AE
    else:
        print_log("[warm-start] no warm_start_ldm_ckpt in config — diffusion trained from scratch (NOT 2c)")

    train_set, valid_set, _ = create_dataset(config["dataset"])
    print_log(f"[data] train={len(train_set)} valid={len(valid_set)} bound cyclic complexes")

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
