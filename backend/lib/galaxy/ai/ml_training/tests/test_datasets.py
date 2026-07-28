"""Unit tests for dataset loading (offline paths only — no network / no TDC)."""
import pytest

from galaxy.ai.ml_training.config import DatasetSpec, ConfigError
from galaxy.ai.ml_training.datasets import load_dataset, HERG_FIXTURE


def test_offline_fixture_loads():
    ds = load_dataset(DatasetSpec(name="fixture:herg", target_col="y"))
    assert len(ds) == len(HERG_FIXTURE)
    assert all(isinstance(s, str) for s in ds.smiles)
    assert set(ds.labels) <= {0.0, 1.0}
    assert "HERG_FIXTURE" in ds.source


def test_unknown_named_dataset_rejected():
    with pytest.raises(ConfigError):
        load_dataset(DatasetSpec(name="tdc"))          # no ':' → not a valid tdc:<name>
    with pytest.raises(ConfigError):
        load_dataset(DatasetSpec(name="nonsense:foo"))


def test_csv_load(tmp_path):
    csv = tmp_path / "herg.csv"
    csv.write_text("smiles,y\nCCO,0\nc1ccccc1,1\n")
    ds = load_dataset(DatasetSpec(path=str(csv), smiles_col="smiles", target_col="y"))
    assert ds.rows == [("CCO", 0.0), ("c1ccccc1", 1.0)]
    assert ds.source.startswith("csv:")


def test_csv_missing_column_rejected(tmp_path):
    csv = tmp_path / "bad.csv"
    csv.write_text("mol,label\nCCO,0\n")
    with pytest.raises(ConfigError):
        load_dataset(DatasetSpec(path=str(csv), smiles_col="smiles", target_col="y"))


def test_missing_csv_path_rejected():
    with pytest.raises(ConfigError):
        load_dataset(DatasetSpec(path="/no/such/file.csv"))


def test_s3_source_is_execution_time_stub():
    with pytest.raises(NotImplementedError):
        load_dataset(DatasetSpec(s3_uri="s3://bucket/herg.csv"))
