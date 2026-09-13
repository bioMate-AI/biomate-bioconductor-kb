"""Three-attempt development smoke test; preserves raw samples and failures.

Run from the pinned PepGLAD checkout. Uses validation examples, not held-out LNR.
"""
import argparse
import hashlib
import json
import math
import pickle
from pathlib import Path

import numpy as np
import torch
from data.codesign import CoDesignDataset
from generate import generate_wrapper, to_device, overwrite_blocks
from data.converter.pdb_to_list_blocks import pdb_to_list_blocks
from data.converter.list_blocks_to_pdb import list_blocks_to_pdb
from data.format import VOCAB
from utils.random_seed import setup_seed

parser = argparse.ArgumentParser()
parser.add_argument('--checkpoint', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
setup_seed(20260912)
torch.set_num_threads(1)
model = torch.load(args.checkpoint, map_location='cpu').to('cuda:0').eval()
dataset = CoDesignDataset(mmap_dir='datasets/train_valid/processed',
                         specify_index='datasets/train_valid/processed/valid_index.txt',
                         backbone_only=False, use_covariance_matrix=True)
records = []
for index in range(min(3, len(dataset))):
    identity, reference, receptor_chain, peptide_chain = dataset.get_summary(index)
    record = {'sample_id': str(index), 'complex_id': identity, 'status': 'attempted'}
    records.append(record)
    try:
        batch = to_device(dataset.collate_fn([dataset[index]]), torch.device('cuda:0'))
        with torch.no_grad():
            Xs, Ss, metrics = generate_wrapper(model, {'energy_func': 'default', 'energy_lambda': 0.8})(batch)
        X, S, metric = Xs[0], Ss[0], metrics[0]
        with (args.output / (str(index) + '_raw.pkl')).open('wb') as f:
            pickle.dump({'X': X, 'S': S, 'metric': metric}, f)
        coordinates = np.asarray(X, dtype=float)
        if not np.isfinite(coordinates).all() or np.abs(coordinates).max() >= 1000:
            raise ValueError('Nonfinite or out-of-range coordinates; no coordinate clamping applied')
        receptor, peptide = pdb_to_list_blocks(reference, selected_chains=[receptor_chain, peptide_chain])
        generated = overwrite_blocks(peptide, S, X)
        seq = ''.join(VOCAB.abrv_to_symbol(block.abrv) for block in generated)
        path = args.output / (str(index) + '_generated.pdb')
        list_blocks_to_pdb([receptor, generated], [receptor_chain, peptide_chain], str(path))
        record.update(status='serialized', sequence=seq, pdb=path.name, residues=len(generated),
                      reference_sequence=''.join(VOCAB.abrv_to_symbol(block.abrv) for block in peptide))
    except Exception as exc:
        record.update(status='failed', error=type(exc).__name__ + ': ' + str(exc))
    finally:
        (args.output / 'attempts.json').write_text(json.dumps(records, indent=2) + '\n')
summary = {'checkpoint': str(args.checkpoint),
           'checkpoint_sha256': hashlib.sha256(args.checkpoint.read_bytes()).hexdigest(),
           'seed': 20260912, 'attempt_count': len(records),
           'serialized_count': sum(r['status'] == 'serialized' for r in records),
           'scope': 'Development I/O smoke from first available LDM checkpoint; first three validation entries, one attempt each. No test-set performance or chemical-validity claim.'}
(args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary))
