"""Exact sequence overlap audit across UniMoMo train/valid and PepGLAD test indexes.

Reports rather than alters published test membership. This cannot establish
family/pocket/temporal separation or absence of base-pretraining contamination.
"""
import argparse
import json
from pathlib import Path


def read_index(path, pepglad=False):
    result = {}
    for line in Path(path).read_text().splitlines():
        if not line.strip(): continue
        fields = line.split('\t')
        if pepglad:
            if len(fields) != 13: raise ValueError('Expected 13-column PepGLAD index')
            key, receptor, peptide = fields[0], (fields[9],), (fields[10],)
        else:
            if len(fields) != 4: raise ValueError('Expected 4-column UniMoMo index')
            props = json.loads(fields[3])
            key = fields[0]
            receptor, peptide = tuple(props['target_sequences']), tuple(props['ligand_sequences'])
        if key in result: raise ValueError(f'Duplicate complex ID: {key}')
        result[key] = {'receptor': receptor, 'peptide': peptide,
                       'complex_sequence': (receptor, peptide)}
    if not result: raise ValueError(f'Empty index: {path}')
    return result


def compare(a, b):
    result = {'shared_pdb_ids': sorted({x.split('_')[0].upper() for x in a} & {x.split('_')[0].upper() for x in b})}
    def known(value):
        if isinstance(value, tuple): return bool(value) and all(known(x) for x in value)
        return bool(value) and not any(c in value.upper() for c in ('?', 'X'))
    for kind in ('receptor', 'peptide', 'complex_sequence'):
        left = {r[kind] for r in a.values() if known(r[kind])}
        right = {r[kind] for r in b.values() if known(r[kind])}
        result[kind] = {
            'shared_unique_sequences': len(left & right),
            'right_complex_ids_matching_left': sorted(k for k, r in b.items() if known(r[kind]) and r[kind] in left),
            'unknown_sequences': {'left': sum(not known(r[kind]) for r in a.values()),
                                  'right': sum(not known(r[kind]) for r in b.values())},
        }
    return result


def audit(train, valid, test):
    splits = {'train': read_index(train), 'valid': read_index(valid), 'test': read_index(test, pepglad=True)}
    return {'counts': {k: len(v) for k, v in splits.items()},
            'train_vs_valid': compare(splits['train'], splits['valid']),
            'train_vs_test': compare(splits['train'], splits['test']),
            'valid_vs_test': compare(splits['valid'], splits['test']),
            'limitation': 'Exact sequences only, excluding unknown X/? sequences; family/pocket/temporal and base-pretraining leakage remain unverified.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('train', 'valid', 'test', 'out'): parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    result = audit(args.train, args.valid, args.test)
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
