"""Audit persisted UniMoMo logs; report paired target uncertainty, never promote OOM runs."""
import argparse
import ast
import json
import math
from pathlib import Path
import random
import re
import statistics


def read_targets(path, candidates=100):
    records = {}
    for line in Path(path).read_text().splitlines():
        match = re.search(r'Finished \d+/\d+, (\{.*\})', line)
        if not match:
            continue
        tree = ast.parse(match[1], mode='eval')
        # Upstream emits repr(float('nan')); literal_eval deliberately cannot execute names.
        class Missing(ast.NodeTransformer):
            def visit_Name(self, node):
                if node.id == 'nan': return ast.copy_location(ast.Constant(None), node)
                raise ValueError(f'Unexpected token: {node.id}')
        record = ast.literal_eval(Missing().visit(tree))
        key = record['id']
        if key in records: raise ValueError(f'Duplicate target: {key}')
        values = record['DockQ']['individual']
        if len(values) != candidates or any(v is None or not math.isfinite(v) or not 0 <= v <= 1 for v in values):
            raise ValueError(f'{key}: expected {candidates} finite DockQ scores in [0,1]')
        records[key] = record
    if not records: raise ValueError('No per-target evaluation records')
    return records


def audit(root, targets=88, candidates=100):
    root = Path(root)
    base, ft = [read_targets(root / f'eval_{label}.log', candidates) for label in ('base', 'ft')]
    if base.keys() != ft.keys() or len(base) != targets:
        raise ValueError('Base/FT target sets do not match the expected benchmark')
    ids = sorted(base)
    deltas = [max(ft[k]['DockQ']['individual']) - max(base[k]['DockQ']['individual']) for k in ids]
    rng = random.Random(0)
    boot = sorted(statistics.mean(rng.choices(deltas, k=len(deltas))) for _ in range(10000))
    train = (root / 'train.log').read_text()
    ooms = len(re.findall(r'out of memory', train, re.I))
    evidence = re.findall(r'UPDATE_EVIDENCE step=(\d+)', train)
    issues = []
    if ooms: issues.append(f'{ooms} OOM events in training log')
    if not evidence: issues.append('No explicit successful-update evidence in training log')
    result = {
        'training_qualified': not issues, 'training_issues': issues,
        'targets': targets, 'candidates_per_target': candidates,
        'aggregation': 'mean of per-target oracle maximum DockQ',
        'base_dockq': statistics.mean(max(base[k]['DockQ']['individual']) for k in ids),
        'ft_dockq': statistics.mean(max(ft[k]['DockQ']['individual']) for k in ids),
        'delta': statistics.mean(deltas),
        'paired_target_bootstrap_95pct_ci': [boot[249], boot[9749]],
        'bootstrap_replicates': 10000, 'bootstrap_seed': 0,
        'improved_targets': sum(d > 0 for d in deltas),
        'worsened_targets': sum(d < 0 for d in deltas),
        'tied_targets': sum(d == 0 for d in deltas),
        'limitation': 'Target resampling measures this run only; not training-seed uncertainty, leakage clearance, or wet-lab validation.',
    }
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run_dir', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.run_dir)
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
