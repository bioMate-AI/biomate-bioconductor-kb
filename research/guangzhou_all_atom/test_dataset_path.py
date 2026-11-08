"""Unit tests for G8 shared dataset-path resolver (dataset_path.py).

Contract: resolve(name) routes through cyclic_data_registry and returns the committed local path;
with a fallback it never raises when the registry is unavailable; without a fallback it re-raises
(a genuinely-missing dataset is not silently masked).
"""
import importlib.util
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


dp = _load("dataset_path")


def test_resolves_known_dataset_to_committed_path():
    p = dp.resolve("cycpeptmpdb", "data/raw/CycPeptMPDB_Peptide_All.csv")
    assert p == HERE / "data/raw/CycPeptMPDB_Peptide_All.csv"


def test_resolves_stability_folds():
    p = dp.resolve("pepmsnd_stability_folds", "data/processed/pepmsnd_stability_folds.csv")
    assert p == HERE / "data/processed/pepmsnd_stability_folds.csv"


def test_unknown_dataset_with_fallback_returns_fallback():
    p = dp.resolve("does_not_exist_xyz", "some/committed/path.csv")
    assert p == HERE / "some/committed/path.csv"


def test_unknown_dataset_without_fallback_raises():
    with pytest.raises(Exception):
        dp.resolve("does_not_exist_xyz", None)
