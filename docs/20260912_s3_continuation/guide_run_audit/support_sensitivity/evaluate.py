"""Predefined descriptive cell-support sensitivity; no threshold optimization."""
import hashlib
import json
from pathlib import Path
import numpy as np

P = Path(__file__).resolve().parent
SOURCE = P.parent.parent / 'full_readout_reliability'
THRESHOLDS = [0, 10, 25, 50, 100]
PANELS = ['all_genes', 'control_expressed']
ORIENTATIONS = ['disjoint_forward', 'disjoint_swapped']

def main():
    with np.load(SOURCE / 'targets.npz', allow_pickle=False) as z:
        t = {k: z[k] for k in z.files}
    prior = json.loads((SOURCE / 'results.json').read_text())
    support = {}
    for target, donor, condition in zip(t['perturbed_gene_name'], t['donor_id'], t['culture_condition']):
        key = (str(target), str(donor), str(condition))
        ix = (t['perturbed_gene_name'] == target) & (t['donor_id'] == donor) & (t['culture_condition'] == condition)
        assert ix.sum() == 2 and len(set(t['guide_id'][ix])) == 2
        support[key] = {'cells': t['n_cells'][ix].tolist(), 'minimum_cells': int(t['n_cells'][ix].min())}
    output = {'protocol': {'thresholds': THRESHOLDS, 'zero': 'unfiltered baseline', 'eligibility': 'Both guide profiles must have n_cells >= threshold within target/donor/condition', 'panels': prior['protocol']['control_expressed'], 'unit': 'Equal-weight guide-pair means; repeated donors and targets, not independent samples', 'limitations': 'Descriptive on the same outcome-selected subset. Control references remain unchanged. No threshold selection, confidence intervals, or causal interpretation.'}, 'thresholds': {}}
    for threshold in THRESHOLDS:
        keys = {k for k, v in support.items() if v['minimum_cells'] >= threshold}
        coverage = {'pairs': len(keys), 'profiles': 2 * len(keys), 'targets': len({k[0] for k in keys}), 'donors': len({k[1] for k in keys}), 'conditions': len({k[2] for k in keys}), 'by_target': {}, 'by_donor': {}, 'by_condition': {}}
        for axis, name in enumerate(['target', 'donor', 'condition']):
            coverage['by_' + name] = {v: sum(k[axis] == v for k in keys) for v in sorted({k[axis] for k in support})}
        coverage['complete_targets_all_12_groups'] = sum(v == 12 for v in coverage['by_target'].values())
        result = {'coverage': coverage, 'panels': {}}
        for panel in PANELS:
            rows = [dict(r, support=support[(r['target'], r['donor'], r['condition'])]) for r in prior['panels'][panel]['rows'] if (r['target'], r['donor'], r['condition']) in keys]
            means = {}
            for orientation in ORIENTATIONS:
                means[orientation] = {}
                for metric in ['pearson', 'spearman']:
                    vals = [r[orientation][metric] for r in rows if r[orientation][metric] is not None]
                    means[orientation][metric] = {'mean': float(np.mean(vals)) if vals else None, 'valid_pairs': len(vals)}
            result['panels'][panel] = {'genes_before_target_exclusion': prior['panels'][panel]['genes_before_target_exclusion'], 'mean_metrics': means, 'rows': rows}
        output['thresholds'][str(threshold)] = result
    output['input_sha256'] = {name: hashlib.sha256((SOURCE / name).read_bytes()).hexdigest() for name in ['targets.npz', 'controls.npz', 'results.json']}
    (P / 'results.json').write_text(json.dumps(output, indent=2, allow_nan=False) + '\n')
    print(json.dumps({k: {'coverage': v['coverage'], 'metrics': {p: d['mean_metrics'] for p,d in v['panels'].items()}} for k,v in output['thresholds'].items()}, indent=2))

if __name__ == '__main__':
    main()
