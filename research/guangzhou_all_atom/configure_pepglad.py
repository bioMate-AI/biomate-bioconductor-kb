"""Create a bounded initial training configuration; preserve published split files."""
import argparse
import json
from pathlib import Path

import yaml

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, required=True)
parser.add_argument('--stage', choices=['autoencoder', 'ldm'], required=True)
parser.add_argument('--checkpoint')
args = parser.parse_args()
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
config['dataloader']['wrapper']['ubound_per_batch'] = 30000
config['trainer']['config'].update(max_epoch=5, patience=5, save_topk=2, val_freq=1,
                                   save_dir=str(root / 'run_outputs' / args.stage), grad_clip=1.0)
out = root / 'run_outputs' / (args.stage + '.yaml')
out.parent.mkdir(exist_ok=True)
out.write_text(yaml.safe_dump(config, sort_keys=False))
print(out)
