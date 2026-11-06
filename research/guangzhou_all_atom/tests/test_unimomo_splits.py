import json
from pathlib import Path
import sys
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from audit_unimomo_splits import audit, read_index


def write(path, key, rec, pep):
    path.write_text(f'{key}\t0\t10\t' + json.dumps({'target_sequences': [rec], 'ligand_sequences': [pep]}) + '\n')


def test_sequence_leakage_detected_with_different_pdb_ids(tmp_path):
    train, valid, test = [tmp_path / name for name in ('train', 'valid', 'test')]
    write(train, 'aaaa', 'ACDE', 'GGG')
    write(valid, 'bbbb', 'ACDE', 'GGG')
    test.write_text('\t'.join(['cccc_A_B', '0', '10', '1', '1', '1', '1', 'A', 'B', 'VVVV', 'GGG', '0', '1']) + '\n')
    result = audit(train, valid, test)
    assert result['train_vs_valid']['complex_sequence']['shared_unique_sequences'] == 1
    assert result['train_vs_test']['shared_pdb_ids'] == []
    assert result['train_vs_test']['peptide']['right_complex_ids_matching_left'] == ['cccc_A_B']


def test_duplicate_and_empty_indexes_fail(tmp_path):
    path = tmp_path / 'index'
    path.write_text('')
    with pytest.raises(ValueError, match='Empty'): read_index(path)
    write(path, 'aaaa', 'ACDE', 'GGG')
    path.write_text(path.read_text() * 2)
    with pytest.raises(ValueError, match='Duplicate'): read_index(path)
