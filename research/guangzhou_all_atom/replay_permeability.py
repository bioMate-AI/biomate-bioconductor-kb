"""Retrospective batch-selection replay against hidden experimental PAMPA labels.

Within-publication finite-library benchmark, not a prospective wet-lab experiment.
No pretrained endpoint model is used, avoiding unknown prior label exposure.
"""
import argparse
import csv
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
from rdkit import Chem, rdBase
from rdkit.Chem import rdFingerprintGenerator
from sklearn.ensemble import RandomForestRegressor


def select_batch(model, features, pool, count, policy, rng):
    # No unobserved outcome is available to this acquisition function.
    if policy == 'random':
        return rng.choice(pool, size=min(count, len(pool)), replace=False)
    predictions = np.stack([tree.predict(features[pool]) for tree in model.estimators_])
    score = predictions.mean(0) + predictions.std(0)
    order = np.argsort(-score, kind='stable')
    return pool[order[:count]]


def replay(features, outcomes, ids, seed, policy, initial=20, rounds=5, batch_size=10):
    rng = np.random.default_rng(seed)
    order = rng.permutation(len(outcomes))
    test = order[:max(20, len(order)//5)]
    candidates = order[len(test):]
    observed = candidates[:initial].tolist()
    remaining = candidates[initial:]
    # Metrics only: never supplied to acquisition/model fitting.
    hit_threshold = float(np.quantile(outcomes[candidates], .9))
    history = []
    for round_id in range(rounds + 1):
        model = RandomForestRegressor(n_estimators=64, min_samples_leaf=2,
                                      max_features=.5, random_state=seed+round_id, n_jobs=1)
        model.fit(features[observed], outcomes[observed])
        history.append({'round': round_id, 'revealed': len(observed),
                        'best_measured_pampa': float(outcomes[observed].max()),
                        'top_decile_hits': int((outcomes[observed] >= hit_threshold).sum()),
                        'held_out_mae': float(np.abs(model.predict(features[test])-outcomes[test]).mean()),
                        'revealed_ids': [ids[i] for i in observed]})
        if round_id == rounds or not len(remaining):
            break
        chosen = select_batch(model, features, remaining, batch_size, policy, rng)
        observed.extend(chosen.tolist())
        remaining = remaining[~np.isin(remaining, chosen)]
    return {'seed': seed, 'policy': policy, 'test_count': len(test),
            'candidate_count': len(candidates), 'history': history}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--csv', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    sources = ['2020_Townsend', '2021_Kelly', '2024_Faris']
    grouped = {s: defaultdict(list) for s in sources}
    exclusions = Counter()
    with args.csv.open(encoding='utf-8-sig') as f:
        for row in csv.DictReader(f):
            if row['Source'] not in grouped:
                continue
            try:
                value = float(row['PAMPA'])
            except ValueError:
                exclusions['missing_or_nonnumeric_pampa'] += 1
                continue
            if not np.isfinite(value) or value <= -9.99 or row['Detection_Limit_1'] or row['Detection_Limit_2']:
                exclusions['censoring_notes_or_floor_or_nonfinite'] += 1
                continue
            mol = Chem.MolFromSmiles(row['SMILES'])
            if mol is None:
                exclusions['invalid_smiles'] += 1
                continue
            identity = Chem.MolToSmiles(mol, canonical=True, isomericSmiles=True)
            grouped[row['Source']][identity].append((row['ID'], value))
    fp = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=1024, includeChirality=True)
    result = {'source_sha256': hashlib.sha256(args.csv.read_bytes()).hexdigest(),
              'rdkit_version': rdBase.rdkitVersion, 'endpoint': 'PAMPA log permeability, higher is better',
              'protocol': {'initial_labels': 20, 'rounds': 5, 'batch_size': 10, 'seeds': [11, 29, 47],
                           'acquisition': 'random versus forest mean + one tree-prediction SD (uncalibrated)',
                           'split': '80% finite candidate pool / 20% untouched predictive test, molecule-disjoint within source'},
              'exclusions': dict(exclusions), 'campaigns': {},
              'limitations': ['Retrospective finite-library replay; no new synthesis or measurement.',
                              'Not a test of the PepGLAD generator, which supports different chemistry.',
                              'Source grouping is not proof of identical assay conditions within each publication.',
                              'Conservative censoring exclusion can bias the candidate pool toward measurable compounds.',
                              'No sequence/scaffold/time extrapolation claim; three seeds are preliminary.',
                              'Only measured library members can be queried; novel generated peptides have no experimental oracle.']}
    for source, groups in grouped.items():
        identities = sorted(groups)
        if len(identities) < 120:
            result['campaigns'][source] = {'status': 'insufficient_clean_unique_molecules', 'count': len(identities)}
            continue
        features = np.stack([fp.GetFingerprintAsNumPy(Chem.MolFromSmiles(s)) for s in identities])
        outcomes = np.array([np.median([value for _, value in groups[s]]) for s in identities])
        ids = ['|'.join(i for i, _ in groups[s]) for s in identities]
        runs = [replay(features, outcomes, ids, seed, policy)
                for seed in [11, 29, 47] for policy in ['random', 'ucb']]
        summaries = {}
        for policy in ['random', 'ucb']:
            final = [r['history'][-1] for r in runs if r['policy'] == policy]
            summaries[policy] = {key: {'mean': float(np.mean([x[key] for x in final])),
                                      'std': float(np.std([x[key] for x in final], ddof=1))}
                                 for key in ['best_measured_pampa', 'top_decile_hits', 'held_out_mae']}
        result['campaigns'][source] = {'unique_molecules': len(identities),
                                       'duplicate_rows_collapsed': sum(len(v)-1 for v in groups.values()),
                                       'summary': summaries, 'runs': runs}
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps({'source': source, 'unique_molecules': len(identities), 'summary': summaries}), flush=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
