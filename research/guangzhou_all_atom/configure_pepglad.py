"""Create a bounded training configuration; preserve published split files.

The epoch budget defaults to the original bounded value (5) but can be raised per
stage via --max-epoch (or the AE_MAX_EPOCH / LDM_MAX_EPOCH environment variables) for
a longer run. save_topk scales with the budget so the best checkpoint survives.
"""
import argparse
import json
import os
from pathlib import Path

import yaml

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, required=True)
parser.add_argument('--stage', choices=['autoencoder', 'ldm'], required=True)
parser.add_argument('--checkpoint')
parser.add_argument('--max-epoch', type=int, default=None,
                    help='Override epoch budget; falls back to AE_MAX_EPOCH/LDM_MAX_EPOCH env, then 5')
args = parser.parse_args()
env_epoch = os.environ.get('AE_MAX_EPOCH' if args.stage == 'autoencoder' else 'LDM_MAX_EPOCH')
max_epoch = args.max_epoch if args.max_epoch is not None else (int(env_epoch) if env_epoch else 5)
if max_epoch < 1:
    raise ValueError('max_epoch must be >= 1')
root = args.root
cfg_path = root / 'configs/pepbench' / ('autoencoder' if args.stage == 'autoencoder' else 'ldm') / 'train_codesign.yaml'
config = yaml.safe_load(cfg_path.read_text())
if args.stage == 'autoencoder':
    # Initial training stage uses full supervised train split; no ProtFrag augmentation yet.
    config['dataset']['train'] = config['dataset']['train'][0]
else:
    if not args.checkpoint or not Path(args.checkpoint).is_file():
        raise ValueError('LDM requires an actual trained autoencoder checkpoint')
    config['model']['autoencoder_ckpt'] = args.checkpoint
config['dataloader']['num_workers'] = 0
# Dynamic batch cap (n**2 complexity). Upstream default is 60000; the first bounded run used
# 30000 (half batch), which under-trained the LDM. Env-overridable; default preserves 30000.
config['dataloader']['wrapper']['ubound_per_batch'] = int(os.environ.get('UBOUND_PER_BATCH', 30000))
config['trainer']['config'].update(max_epoch=max_epoch, patience=max(5, max_epoch // 4),
                                   save_topk=3, val_freq=1,
                                   save_dir=str(root / 'run_outputs' / args.stage), grad_clip=1.0)
out = root / 'run_outputs' / (args.stage + '.yaml')
out.parent.mkdir(exist_ok=True)
out.write_text(yaml.safe_dump(config, sort_keys=False))
print(out)
