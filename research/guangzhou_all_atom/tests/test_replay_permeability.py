import importlib.util
from pathlib import Path
import numpy as np

spec = importlib.util.spec_from_file_location('replay', Path(__file__).parents[1] / 'replay_permeability.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_untouched_test_outcomes_cannot_change_acquisitions():
    x = np.random.default_rng(7).normal(size=(100, 8))
    y = x[:, 0] + .1 * x[:, 1]
    ids = [str(i) for i in range(100)]
    seed = 11
    test = np.random.default_rng(seed).permutation(100)[:20]
    first = module.replay(x, y, ids, seed, 'ucb', rounds=2)
    changed = y.copy()
    changed[test] += 1000
    second = module.replay(x, changed, ids, seed, 'ucb', rounds=2)
    assert [r['revealed_ids'] for r in first['history']] == [r['revealed_ids'] for r in second['history']]
    chosen = first['history'][-1]['revealed_ids']
    assert len(chosen) == len(set(chosen)) == 40
    assert not set(chosen) & {str(i) for i in test}
    assert first['history'][-1]['held_out_mae'] != second['history'][-1]['held_out_mae']
