from pathlib import Path
import sys
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from audit_unimomo_run import read_targets, audit


def write_log(path, ids=('A', 'B'), n=2):
    path.write_text('\n'.join(f"Finished {i+1}/2, " + repr({'id': key, 'DockQ': {'individual': [.1] * n}})
                              for i, key in enumerate(ids)))


def test_rejects_missing_candidates_and_duplicate_targets(tmp_path):
    path = tmp_path / 'eval.log'
    write_log(path, n=1)
    with pytest.raises(ValueError, match='expected 2'): read_targets(path, 2)
    write_log(path, ids=('A', 'A'))
    with pytest.raises(ValueError, match='Duplicate'): read_targets(path, 2)


def test_rejects_unmatched_targets(tmp_path):
    write_log(tmp_path / 'eval_base.log')
    write_log(tmp_path / 'eval_ft.log', ids=('A', 'C'))
    with pytest.raises(ValueError, match='target sets'): audit(tmp_path, targets=2, candidates=2)


def test_oom_run_is_unqualified_even_with_update_evidence(tmp_path):
    for label in ('base', 'ft'): write_log(tmp_path / f'eval_{label}.log')
    (tmp_path / 'train.log').write_text('UPDATE_EVIDENCE step=0\nOut of memory\n')
    result = audit(tmp_path, targets=2, candidates=2)
    assert not result['training_qualified']
    assert result['paired_target_bootstrap_95pct_ci'] == [0, 0]
