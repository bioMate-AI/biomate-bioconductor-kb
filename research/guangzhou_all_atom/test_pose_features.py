"""Tests for the dependency-free designed-pose geometric featurizer (pose_features.py).

Covers: mmCIF atom_site parsing, peptide-chain selection (shortest / by expected length), and the
geometry features on known coordinates. (The empirical finding that these features do NOT predict
designability is recorded in docs/20261004_SPEED_SURROGATE_DESIGNABILITY.md, not asserted here.)
"""
import importlib.util
import math
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


pf = _load("pose_features")

_MINI_CIF = """data_test
loop_
_atom_site.group_PDB
_atom_site.id
_atom_site.type_symbol
_atom_site.label_atom_id
_atom_site.label_alt_id
_atom_site.label_comp_id
_atom_site.label_asym_id
_atom_site.label_entity_id
_atom_site.label_seq_id
_atom_site.pdbx_PDB_ins_code
_atom_site.Cartn_x
_atom_site.Cartn_y
_atom_site.Cartn_z
_atom_site.occupancy
_atom_site.B_iso_or_equiv
_atom_site.pdbx_formal_charge
_atom_site.auth_seq_id
ATOM 1 C CA . ALA A 1 1 ? 0.000 0.000 0.000 1.0 0.0 ? 1
ATOM 2 C CA . ALA A 1 2 ? 3.800 0.000 0.000 1.0 0.0 ? 2
ATOM 3 C CA . ALA A 1 3 ? 3.800 3.800 0.000 1.0 0.0 ? 3
ATOM 4 C CA . ALA A 1 4 ? 0.000 3.800 0.000 1.0 0.0 ? 4
ATOM 5 C CA . ALA B 1 1 ? 50.000 0.000 0.000 1.0 0.0 ? 1
ATOM 6 C CA . ALA B 1 2 ? 53.000 0.000 0.000 1.0 0.0 ? 2
ATOM 7 C CA . ALA B 1 3 ? 56.000 0.000 0.000 1.0 0.0 ? 3
ATOM 8 C CA . ALA B 1 4 ? 59.000 0.000 0.000 1.0 0.0 ? 4
ATOM 9 C CA . ALA B 1 5 ? 62.000 0.000 0.000 1.0 0.0 ? 5
#
"""


def test_parse_two_chains(tmp_path):
    p = tmp_path / "x.cif"
    p.write_text(_MINI_CIF)
    chains = pf.parse_ca_by_chain(str(p))
    assert set(chains) == {"A", "B"}
    assert len(chains["A"]) == 4 and len(chains["B"]) == 5


def test_peptide_chain_shortest_and_by_len(tmp_path):
    p = tmp_path / "x.cif"
    p.write_text(_MINI_CIF)
    chains = pf.parse_ca_by_chain(str(p))
    assert len(pf.peptide_chain(chains)) == 4            # shortest
    assert len(pf.peptide_chain(chains, expected_len=5)) == 5  # by expected length


def test_geom_features_square():
    # 4 CA at corners of a 3.8 A square -> known Rg, closed (end2end = one bond)
    ca = [(0, 0, 0), (3.8, 0, 0), (3.8, 3.8, 0), (0, 3.8, 0)]
    f = pf.geom_features(ca)
    assert f["pose_n"] == 4.0
    assert abs(f["pose_end2end"] - 3.8) < 1e-6
    assert f["pose_frac_in_contact"] == 1.0
    assert set(f) == set(pf.POSE_FEATURE_NAMES)


def test_too_short_returns_zeros():
    f = pf.geom_features([(0, 0, 0), (1, 0, 0)])
    assert all(v == 0.0 for v in f.values())


def test_features_for_cif_end_to_end(tmp_path):
    p = tmp_path / "x.cif"
    p.write_text(_MINI_CIF)
    f = pf.features_for_cif(str(p), expected_len=4)
    assert f is not None and f["pose_n"] == 4.0
