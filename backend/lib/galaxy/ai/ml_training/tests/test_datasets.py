"""Unit tests for dataset loading (offline paths only — no network / no TDC)."""
from pathlib import Path

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


# ── s3 staging helper (added 2026-11-05 after a Batch smoke found s3:// datasets
#    were never staged for ml_training — the .nf passes params.dataset as a plain
#    value, so the loader must stage the object itself via the image's AWS CLI). ──
def test_stage_s3_reuses_existing_local(tmp_path, monkeypatch):
    from galaxy.ai.ml_training import datasets as _ds
    monkeypatch.chdir(tmp_path)
    (tmp_path / "m.csv").write_text("sample_id,GENE0,label\nS0,1.0,A\n")
    called = {"n": 0}
    monkeypatch.setattr(_ds.subprocess, "run", lambda *a, **k: called.__setitem__("n", called["n"] + 1))
    out = _ds.stage_s3_to_local("s3://b/k/m.csv")
    assert out == "m.csv" and called["n"] == 0          # reused, no download


def test_stage_s3_downloads_via_cli(tmp_path, monkeypatch):
    from galaxy.ai.ml_training import datasets as _ds
    monkeypatch.chdir(tmp_path)
    def fake_run(cmd, **k):
        assert cmd[:3] == ["aws", "s3", "cp"] and cmd[3] == "s3://b/k/m.csv"
        Path(cmd[4]).write_text("sample_id,GENE0,label\nS0,1.0,A\n")
        class R: returncode = 0
        return R()
    monkeypatch.setattr(_ds.subprocess, "run", fake_run)
    out = _ds.stage_s3_to_local("s3://b/k/m.csv")
    assert out == "m.csv" and Path(out).exists()


def test_stage_s3_download_failure_raises(tmp_path, monkeypatch):
    from galaxy.ai.ml_training import datasets as _ds
    monkeypatch.chdir(tmp_path)
    def boom(cmd, **k):
        raise _ds.subprocess.CalledProcessError(1, cmd, stderr="AccessDenied")
    monkeypatch.setattr(_ds.subprocess, "run", boom)
    with pytest.raises(FileNotFoundError):
        _ds.stage_s3_to_local("s3://b/k/missing.csv")


def test_stage_s3_rejects_non_s3():
    from galaxy.ai.ml_training.datasets import stage_s3_to_local
    with pytest.raises(ValueError):
        stage_s3_to_local("/local/path.csv")
