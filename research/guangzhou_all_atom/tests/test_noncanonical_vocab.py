"""Unit tests for the B1 native-non-canonical representation stub (noncanonical_vocab.py).

GPU-free, torch-free. Mirrors the importlib pattern of the other tests in this dir so it runs under a
plain `pytest` with only stdlib (+ optional RDKit). These tests LOCK the load-bearing facts of the
feasibility report: the 14-channel saturation collision, the +1-donor-removed permeability lever, and
Pro ineligibility. If someone changes the representation later, these tests tell them what breaks.
"""
import importlib.util
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location(
    'noncanonical_vocab', Path(__file__).parents[1] / 'noncanonical_vocab.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def test_enumerates_all_eligible_aas_except_pro():
    monomers = mod.enumerate_n_methyl_monomers()
    # 20 canonical minus Pro (already tertiary N) = 19 N-Me monomers
    assert len(monomers) == 19
    parents = {m.parent_symbol for m in monomers}
    assert 'P' not in parents
    assert parents == set('GAVLIFWYDHNEKQMRSTC')


def test_every_n_methyl_removes_exactly_one_backbone_donor():
    # This is the whole point: N-Me is the permeability lever precisely because it deletes a backbone NH.
    for m in mod.enumerate_n_methyl_monomers():
        assert m.removed_donor_h is True
        assert m.added_atoms == ['CN']
        assert m.kind == 'n_methyl'


def test_trp_n_methyl_exceeds_the_14_channel_cap():
    # The single most important architectural constraint for B1: TRP saturates 14 channels,
    # so N-Me-TRP needs 15 -> the AE's MAX_ATOM_NUMBER / n_channel must grow (retrain), not guidance.
    monomers = {m.parent_symbol: m for m in mod.enumerate_n_methyl_monomers()}
    trp = monomers['W']
    assert trp.total_atoms == 15
    assert trp.exceeds_channel_cap is True


def test_only_trp_exceeds_cap_others_fit():
    over = [m.parent_symbol for m in mod.enumerate_n_methyl_monomers() if m.exceeds_channel_cap]
    assert over == ['W'], f'expected only TRP to overflow, got {over}'


def test_representation_delta_is_self_consistent():
    d = mod.representation_delta()
    assert d['current_channel_cap'] == 14
    assert d['max_atoms_needed'] == 15            # driven by N-Me-TRP
    assert d['monomers_exceeding_cap'] == ['nW']
    assert d['new_residue_tokens'] == 19          # token-doubling route
    assert d['alt_orthogonal_flag_bits'] == 1     # preferred orthogonal-flag route
    assert d['seq_decoder_classes_current'] == 21
    assert d['requires_ae_retrain'] is True       # any token/atom-space change forces an AE (+LDM) retrain


def test_nme_ideal_geometry_frame_atoms_exist_in_every_residue():
    # CN is built off (N, CA, C) -- all backbone atoms present in every block, so the z-matrix build is valid
    # for every residue type (no dependence on a variable sidechain atom).
    g = mod.NME_IDEAL_GEOMETRY
    assert set(g['parents']).issubset(set(mod.BACKBONE_ATOMS))
    assert g['atom'] == 'CN' and g['element'] == 'C'
    assert 1.3 < g['z-length'] < 1.6              # physical N-CH3 bond length


@pytest.mark.skipif(
    importlib.util.find_spec('rdkit') is None, reason='RDKit not installed')
def test_nme_smarts_matches_an_actual_n_methyl_amide():
    from rdkit import Chem
    patt = Chem.MolFromSmarts(mod.n_methylated_backbone_smarts())
    # N-methylacetamide: CC(=O)N(C)  -- the canonical N-methyl amide
    nma = Chem.MolFromSmiles('CC(=O)NC')
    assert nma is not None and patt is not None
    assert nma.HasSubstructMatch(patt)
    # a plain (non-methylated) amide must NOT match
    acetamide = Chem.MolFromSmiles('CC(=O)N')
    assert not acetamide.HasSubstructMatch(patt)
