import importlib.util
from pathlib import Path
import pytest

spec = importlib.util.spec_from_file_location('split_audit', Path(__file__).parents[1] / 'audit_split_sequences.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def row(name, receptor, peptide):
    return '\t'.join([name, '0', '10', '4', '3', '20', '15', 'A', 'B', receptor, peptide, '0', '0,1']) + '\n'


def test_counts_matching_complexes_and_excludes_unknown_receptors(tmp_path):
    (tmp_path / 'train_index.txt').write_text(row('t1', 'ACDE', 'GGG') + row('t2', '?CDE', 'AAA'))
    (tmp_path / 'valid_index.txt').write_text(row('v1', 'VVVV', 'GGG') + row('v2', '?CDE', 'GGG'))
    result = module.audit(tmp_path)
    assert result['exact_complex_overlap'] == 0
    peptide = result['sequence_comparisons']['peptide']
    assert peptide['shared_unique_sequences'] == 1
    assert peptide['validation_complexes_matching_train'] == 2
    receptor = result['sequence_comparisons']['receptor']
    assert receptor['shared_unique_sequences'] == 0
    assert receptor['unknown_sequence_complexes'] == {'train': 1, 'valid': 1}


def test_duplicate_complex_ids_are_rejected(tmp_path):
    (tmp_path / 'train_index.txt').write_text(row('same', 'ACDE', 'GGG') * 2)
    (tmp_path / 'valid_index.txt').write_text(row('v', 'VVVV', 'AAA'))
    with pytest.raises(ValueError, match='Duplicate'):
        module.audit(tmp_path)
