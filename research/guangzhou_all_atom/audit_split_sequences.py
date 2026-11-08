"""Audit exact sequence overlap in pinned PepGLAD processed split indexes.

This does not establish sequence-family, pocket-homology, or temporal separation.
"""
import argparse
import json
from pathlib import Path


def audit(processed):
    rows = {}
    for split in ('train', 'valid'):
        rows[split] = [line.rstrip('\n').split('\t') for line in
                       (processed / (split + '_index.txt')).read_text().splitlines() if line.strip()]
        if not rows[split] or any(len(row) != 13 for row in rows[split]):
            raise ValueError('Empty split or unexpected pinned index schema: ' + split)
        if len({r[0] for r in rows[split]}) != len(rows[split]):
            raise ValueError('Duplicate complex ID in ' + split)
    result = {'complex_counts': {k: len(v) for k, v in rows.items()},
              'exact_complex_overlap': len({r[0] for r in rows['train']} & {r[0] for r in rows['valid']}),
              'sequence_comparisons': {}}
    for label, cols in [('receptor', (9,)), ('peptide', (10,)), ('receptor_peptide_pair', (9, 10))]:
        def key(row):
            return tuple(row[col] for col in cols)
        known = {split: [r for r in rr if all(r[c] and '?' not in r[c] for c in cols)]
                 for split, rr in rows.items()}
        seqs = {split: {key(r) for r in rr} for split, rr in known.items()}
        result['sequence_comparisons'][label] = {
            'unique_sequences': {split: len(s) for split, s in seqs.items()},
            'shared_unique_sequences': len(seqs['train'] & seqs['valid']),
            'validation_complexes_matching_train': sum(key(r) in seqs['train'] for r in known['valid']),
            'unknown_sequence_complexes': {split: len(rows[split])-len(rr) for split, rr in known.items()}}
    result['limitation'] = 'Exact sequence identity only; family/pocket/temporal separation remains unverified. Published split is unchanged.'
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--processed', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.processed)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
