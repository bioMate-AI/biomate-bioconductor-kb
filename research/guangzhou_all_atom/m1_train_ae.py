#!/usr/bin/env python3
"""m1_train_ae.py — M1 geometry-AE mid-train entrypoint (Option B), warm-started from the epoch-221
linear/protein AE. Drives the OFFICIAL PepGLAD trainer (train.py's machinery), not a custom loop.

WHAT IT DOES (thin wrapper over runtime/PepGLAD/train.py:main — reuses create_dataset /
create_dataloader / create_trainer / R.construct verbatim). The ONLY thing it changes vs. stock
train.py is HOW the model is warm-started:

  Stock train.py `load_ckpt(model, ckpt)` does `model.load_state_dict(torch.load(ckpt).state_dict())`.
  That assumes the checkpoint IS the model being trained. Our warm-start source (epoch-221) is an
  LDMPepDesign whose TRAINED AE lives at `.autoencoder`; loading its full state_dict into a bare
  AutoEncoder would KeyError. So this entrypoint:
    1. constructs the AutoEncoder (or ClosureAwareAutoEncoder) from the M1 config (same architecture as
       train_codesign.yaml — verified: embed/hidden/latent sizes, n_channel=14, anchor_at_ca, mask_ratio),
    2. loads the epoch-221 checkpoint, extracts `.autoencoder` (exactly as m0_frozen_probe does),
    3. copies its state_dict into the fresh model with strict=False (ClosureAwareAutoEncoder adds NO
       parameters, only scalar attributes, so this is a 1:1 load; strict=False + a printed report of
       any missing/unexpected keys is the honest guard),
    4. hands the warm-started model to the official trainer to CONTINUE training (mid-train), NOT from
       scratch.

  The `warm_start_ckpt` path is read from config (`warm_start_ckpt:`), NOT the stock `load_ckpt:` key
  (which would trigger the wrong full-model load). If a bare AutoEncoder checkpoint is given instead of
  an LDM, it is loaded directly.

REGISTRATION: this module imports m1_peptide_dataset (PeptideOnlyCoDesignDataset) and m1_closure_ae
(ClosureAwareAutoEncoder / ClosureAETrainer) BEFORE create_dataset/create_trainer run, so R.construct
can resolve the M1 config's class names.

USAGE
  python3 m1_train_ae.py --gpus 0 --config m1_ae_midtrain.yaml
  # (mirrors train.py's arg surface; extra key=value opt-args are passed to overwrite_values too.)
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

import yaml
import torch

# Register M1 classes (side-effect imports) BEFORE the official builders run.
import m1_peptide_dataset  # noqa: F401  registers PeptideOnlyCoDesignDataset
import m1_closure_ae       # noqa: F401  registers ClosureAwareAutoEncoder / ClosureAETrainer

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
    parser = argparse.ArgumentParser(description="M1 AE mid-train (warm-started)")
    parser.add_argument("--gpus", type=int, nargs="+", required=True, help="gpu ids, -1 for cpu")
    parser.add_argument("--local_rank", type=int, default=-1)
    parser.add_argument("--config", type=str, required=True, help="path to the M1 yaml")
    parser.add_argument("--seed", type=int, default=SEED)
    return parser.parse_known_args()


def _extract_autoencoder_state(ckpt_path: str):
    """Load epoch-221 (LDMPepDesign) or a bare AutoEncoder checkpoint and return the AE state_dict."""
    import models as _m

    obj = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    if isinstance(obj, _m.LDMPepDesign):
        ae = obj.autoencoder
    elif isinstance(obj, _m.AutoEncoder):
        ae = obj
    else:
        raise TypeError(
            f"warm_start_ckpt is a {type(obj).__name__}; expected LDMPepDesign (with .autoencoder) "
            f"or AutoEncoder. Cannot extract AE weights for warm-start."
        )
    return ae.state_dict()


def warm_start(model, ckpt_path: str):
    """Copy the epoch-221 AE weights into `model` (strict=False; print any key mismatches)."""
    src_sd = _extract_autoencoder_state(ckpt_path)
    result = model.load_state_dict(src_sd, strict=False)
    missing = list(getattr(result, "missing_keys", []))
    unexpected = list(getattr(result, "unexpected_keys", []))
    n_loaded = len(src_sd) - len(unexpected)
    print_log(f"[warm-start] loaded {n_loaded}/{len(src_sd)} AE tensors from {ckpt_path}")
    if missing:
        print_log(f"[warm-start] missing keys (NOT in checkpoint, kept fresh-init): {missing}")
    if unexpected:
        print_log(f"[warm-start] unexpected keys (in checkpoint, no target param): {unexpected}")
    # A healthy warm-start of the SAME architecture should have zero unexpected keys and only the
    # scalar-attribute additions (which are not parameters) absent. Loud if that's not the case.
    return model


def main(args, opt_args):
    config = yaml.safe_load(open(args.config, "r"))
    config = overwrite_values(config, opt_args)

    model = R.construct(config["model"])

    warm_ckpt = config.get("warm_start_ckpt")
    if warm_ckpt:
        model = warm_start(model, warm_ckpt)
    elif "load_ckpt" in config:
        # Fall back to stock full-model load if a same-class checkpoint is provided.
        from train import load_ckpt
        model = load_ckpt(model, config["load_ckpt"])
    else:
        print_log("[warm-start] no warm_start_ckpt / load_ckpt in config — training from scratch")

    train_set, valid_set, _ = create_dataset(config["dataset"])

    if len(args.gpus) > 1:
        args.local_rank = int(os.environ["LOCAL_RANK"])
        torch.cuda.set_device(args.local_rank)
        torch.distributed.init_process_group(backend="nccl", world_size=len(args.gpus))
    else:
        args.local_rank = -1

    if args.local_rank <= 0:
        print_log(f"Number of parameters: {count_parameters(model) / 1e6} M")

    train_loader = create_dataloader(train_set, config["dataloader"], len(args.gpus))
    valid_loader = create_dataloader(valid_set, config["dataloader"], validation=True)

    trainer = create_trainer(config, model, train_loader, valid_loader)
    trainer.train(args.gpus, args.local_rank)


if __name__ == "__main__":
    args, opt_args = parse()
    print_log(f"Overwriting args: {opt_args}")
    setup_seed(args.seed)
    main(args, opt_args)
