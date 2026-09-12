"""Warm-start the initial AE from its latest completed epoch (optimizer resets)."""
import argparse
import json
import re
from pathlib import Path
import yaml

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, required=True)
parser.add_argument('--stage', choices=['autoencoder'], required=True)
args = parser.parse_args()
checkpoints = list((args.root / 'previous_outputs' / args.stage).glob('version_*/checkpoint/epoch*_step*.ckpt'))
def epoch(path):
    return int(re.search(r'epoch(\d+)_step', path.name).group(1))
if not checkpoints:
    raise RuntimeError('Migration requires a saved autoencoder checkpoint')
checkpoint = max(checkpoints, key=epoch)
config_path = args.root / 'run_outputs' / (args.stage + '.yaml')
config = yaml.safe_load(config_path.read_text())
config['load_ckpt'] = str(checkpoint)
# This migration is performed before the initial five AE epochs finish.
remaining = 5 - epoch(checkpoint) - 1
if remaining <= 0:
    raise RuntimeError('AE already completed; select its best checkpoint and skip AE instead')
config['trainer']['config']['max_epoch'] = remaining
config_path.write_text(yaml.safe_dump(config, sort_keys=False))
evidence = {'checkpoint': str(checkpoint), 'completed_epochs': epoch(checkpoint) + 1,
            'remaining_epochs': remaining, 'optimizer_state': 'reset; upstream saves model only'}
(args.root / 'run_outputs' / 'warm_start.json').write_text(json.dumps(evidence, indent=2) + '\n')
print(json.dumps(evidence))
