"""Held-out validation generation benchmark for the trained PepGLAD co-design model.

Generalizes generation_smoke.py (the calibrated path that serialized 3/3) to the full
validation split with a configurable number of stochastic attempts per complex. Every
attempt is retained, including failures; raw samples are preserved.

The checkpoint MUST already carry latent-guidance calibration (run setup_latent_guidance.py
on it first, exactly as qualify_checkpoint.sh does) or guided sampling degrades — the
uncalibrated smoke serialized 0/3, the calibrated one 3/3.

Reported metrics are structure-based-design appropriate, NOT a binding/potency assay:
  * serialized_rate         - fraction of attempts that produced finite, in-range coords
  * mean_aar                - amino-acid recovery vs the reference peptide (per-residue
                              identity match; peptide length is conditioned on the reference)
  * sequence_diversity      - unique generated sequences / serialized attempts
  * novel_sequence_rate     - serialized sequences not present in the training peptides
                              (only when --training-sequences is supplied)
No 3D geometry quality, potency, stability, synthesis or safety is evaluated here.
"""
import argparse
import hashlib
import json
import os
import pickle
import sys
from collections import defaultdict
from pathlib import Path

# This script lives outside the PepGLAD checkout, so Python puts its own dir on sys.path
# (not the repo). The run script invokes it with cwd = the PepGLAD checkout; put that on the
# path so `data`, `generate`, `utils` resolve without relying on PYTHONPATH being set.
sys.path.insert(0, os.getcwd())


def slide_aar(candidate, reference):
    """PepGLAD's amino-acid recovery: max exact-match rate over all registration offsets.
    Mirrors evaluation/seq_metric.py:slide_aar. Note the random baseline for this metric is
    ~0.14-0.16 for short peptides (max over ~2L offsets), NOT ~0.05 -- report a baseline too."""
    if not reference:
        return None
    L = len(reference)
    padded = ' ' * (L - 1) + candidate + ' ' * (L - 1)
    best = 0.0
    for s in range(len(padded) - L + 1):
        window = padded[s:s + L]
        best = max(best, sum(a == b for a, b in zip(window, reference)) / L)
    return best


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
parser.add_argument('--attempts', type=int, default=4, help='stochastic samples per complex')
parser.add_argument('--limit', type=int, default=None, help='cap complexes (debug)')
parser.add_argument('--seed', type=int, default=20260912)
parser.add_argument('--energy-lambda', type=float, default=0.8)
parser.add_argument('--training-sequences', type=Path, default=None,
                    help='one peptide sequence per nonblank line; enables novelty rate')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
setup_seed(args.seed)
torch.set_num_threads(1)

model = torch.load(args.checkpoint, map_location='cpu').to('cuda:0').eval()
dataset = CoDesignDataset(mmap_dir='datasets/train_valid/processed',
                          specify_index='datasets/train_valid/processed/valid_index.txt',
                          backbone_only=False, use_covariance_matrix=True)

training_seqs = None
if args.training_sequences is not None:
    training_seqs = {s.strip() for s in args.training_sequences.read_text().splitlines() if s.strip()}

n_complexes = len(dataset) if args.limit is None else min(args.limit, len(dataset))
records = []
sample_pdbs = args.output / 'samples'
sample_pdbs.mkdir(exist_ok=True)

for index in range(n_complexes):
    identity, reference, receptor_chain, peptide_chain = dataset.get_summary(index)
    try:
        _, peptide_ref = pdb_to_list_blocks(reference, selected_chains=[receptor_chain, peptide_chain])
        ref_seq = ''.join(VOCAB.abrv_to_symbol(b.abrv) for b in peptide_ref)
    except Exception as exc:  # keep going; record the reference failure
        ref_seq = None
    for attempt in range(args.attempts):
        sample_id = f'{index}_{attempt}'
        record = {'sample_id': sample_id, 'complex_id': identity, 'attempt': attempt,
                  'reference_sequence': ref_seq, 'status': 'attempted'}
        records.append(record)
        try:
            batch = to_device(dataset.collate_fn([dataset[index]]), torch.device('cuda:0'))
            with torch.no_grad():
                Xs, Ss, metrics = generate_wrapper(
                    model, {'energy_func': 'default', 'energy_lambda': args.energy_lambda})(batch)
            X, S, metric = Xs[0], Ss[0], metrics[0]
            with (sample_pdbs / (sample_id + '_raw.pkl')).open('wb') as f:
                pickle.dump({'X': X, 'S': S, 'metric': metric}, f)
            coords = np.asarray(X, dtype=float)
            if not np.isfinite(coords).all() or np.abs(coords).max() >= 1000:
                raise ValueError('Nonfinite or out-of-range coordinates; no clamping applied')
            receptor, peptide = pdb_to_list_blocks(reference, selected_chains=[receptor_chain, peptide_chain])
            generated = overwrite_blocks(peptide, S, X)
            seq = ''.join(VOCAB.abrv_to_symbol(b.abrv) for b in generated)
            pdb_path = sample_pdbs / (sample_id + '_generated.pdb')
            list_blocks_to_pdb([receptor, generated], [receptor_chain, peptide_chain], str(pdb_path))
            # PepGLAD's official recovery metric is slide_aar (max AAR over registration
            # offsets), NOT raw positional match — raw reads near-random on frame-shifts.
            aar = slide_aar(seq, ref_seq) if ref_seq else None
            raw_aar = (sum(a == b for a, b in zip(seq, ref_seq)) / len(ref_seq)
                       if ref_seq else None)
            record.update(status='serialized', sequence=seq, residues=len(generated),
                          pdb=str(pdb_path.relative_to(args.output)), aar=aar, raw_aar=raw_aar)
        except Exception as exc:
            record.update(status='failed', error=type(exc).__name__ + ': ' + str(exc))
        finally:
            (args.output / 'attempts.json').write_text(json.dumps(records, indent=2) + '\n')

# ---- aggregate ----
serialized = [r for r in records if r['status'] == 'serialized']
aars = [r['aar'] for r in serialized if r.get('aar') is not None]
seqs = [r['sequence'] for r in serialized]
per_complex_best_aar = defaultdict(float)
for r in serialized:
    if r.get('aar') is not None:
        per_complex_best_aar[r['complex_id']] = max(per_complex_best_aar[r['complex_id']], r['aar'])

novel_rate = None
if training_seqs is not None and seqs:
    novel_rate = sum(s not in training_seqs for s in seqs) / len(seqs)

# Composition-matched random baseline for slide_aar (the metric's floor is NOT ~0.05).
import random as _random
_random.seed(args.seed)
_refs = [r['reference_sequence'] for r in serialized if r.get('reference_sequence')]
_pool = ''.join(_refs) or 'ACDEFGHIKLMNPQRSTVWY'
baseline_aar = None
if _refs:
    trials = []
    for _ in range(5):
        trials.append(sum(slide_aar(''.join(_random.choice(_pool) for _ in ref), ref)
                          for ref in _refs) / len(_refs))
    baseline_aar = sum(trials) / len(trials)

summary = {
    'checkpoint': str(args.checkpoint),
    'checkpoint_sha256': hashlib.sha256(args.checkpoint.read_bytes()).hexdigest(),
    'seed': args.seed,
    'energy_lambda': args.energy_lambda,
    'n_complexes': n_complexes,
    'attempts_per_complex': args.attempts,
    'n_attempts': len(records),
    'n_serialized': len(serialized),
    'serialized_rate': len(serialized) / len(records) if records else None,
    'aar_metric': 'slide_aar (PepGLAD official); compare against random_baseline_aar, not 0.05',
    'mean_aar': sum(aars) / len(aars) if aars else None,
    'random_baseline_aar': baseline_aar,
    'mean_aar_over_baseline': (sum(aars) / len(aars) - baseline_aar
                               if (aars and baseline_aar is not None) else None),
    'mean_best_aar_per_complex': (sum(per_complex_best_aar.values()) / len(per_complex_best_aar)
                                  if per_complex_best_aar else None),
    'n_aar_scored': len(aars),
    'sequence_diversity': len(set(seqs)) / len(seqs) if seqs else None,
    'novel_sequence_rate': novel_rate,
    'training_sequences_provided': None if training_seqs is None else len(training_seqs),
    'scope': ('Held-out validation (PepBench valid split, not LNR). Structure-based-design '
              'metrics only: recovery, validity, diversity. No potency, stability, geometry '
              'quality, synthesis or safety claim; peptide length is conditioned on the reference.'),
}
(args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
