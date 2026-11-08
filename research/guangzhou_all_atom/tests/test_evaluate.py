import importlib.util
from pathlib import Path

import pytest
from rdkit import Chem

spec = importlib.util.spec_from_file_location('evaluate', Path(__file__).parents[1] / 'evaluate.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def batch(*smiles):
    return {'attempts': [{'sample_id': str(i), 'smiles': s} for i, s in enumerate(smiles)]}


def test_failed_samples_remain_in_denominator():
    r = module.audit(batch('CCO', 'OCC', None, 'not_a_molecule'), ['CCO'])
    assert r['chemical_validity_per_attempt'] == 0.5
    assert r['unique_valid_per_attempt'] == 0.25
    assert r['exact_unseen_valid_per_attempt'] == 0


def test_stereo_and_atom_maps():
    r = module.audit(batch('N[C@@H](C)C(=O)O', 'N[C@H](C)C(=O)O',
                           '[CH3:8][CH2:2][OH:1]'), ['N[C@@H](C)C(=O)O', 'CCO'])
    assert [s['exact_training_match'] for s in r['samples']] == [True, False, True]


def test_unspecified_stereo_and_disconnected_salt():
    r = module.audit(batch('NC(C)C(=O)O', 'CCO.[Na+]'))
    assert r['samples'][0]['unspecified_stereo_elements'] == 1
    assert r['connected_valid_per_attempt'] == 0.5
    assert r['exact_unseen_valid_per_attempt'] is None


def test_cyclic_identity_independent_of_start_atom():
    s = 'O=C1NCC(=O)NC1'
    mol = Chem.MolFromSmiles(s)
    alternate = Chem.MolToSmiles(mol, canonical=False, rootedAtAtom=3)
    assert module.audit(batch(s, alternate))['n_unique_valid'] == 1


def test_peptide_identity_and_explicit_hydrogens():
    mol = Chem.MolFromSequence('AGF')
    a = Chem.MolToSmiles(mol)
    b = Chem.MolToSmiles(Chem.AddHs(mol))
    assert module.audit(batch(a, b))['n_unique_valid'] == 1


@pytest.mark.parametrize('training', [[], ['invalid']])
def test_bad_reference_fails(training):
    with pytest.raises(ValueError):
        module.audit(batch('CCO'), training)


def test_duplicate_ids_fail():
    with pytest.raises(ValueError):
        module.audit({'attempts': [{'sample_id': 'a'}, {'sample_id': 'a'}]})


def test_no_valid_samples_has_no_conditional_rate():
    r = module.audit(batch(None))
    assert r['uniqueness_among_valid'] is None
    assert r['chemical_validity_per_attempt'] == 0
