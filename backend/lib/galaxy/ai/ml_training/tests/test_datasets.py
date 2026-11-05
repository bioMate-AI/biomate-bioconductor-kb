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
    # Idempotent per-URI: a second call for the SAME uri reuses the staged file
    # (whose name is URI-hashed), with no second download.
    from galaxy.ai.ml_training import datasets as _ds
    monkeypatch.chdir(tmp_path)
    calls = {"n": 0}
    def fake_run(cmd, **k):
        calls["n"] += 1
        Path(cmd[4]).write_text("sample_id,GENE0,label\nS0,1.0,A\n")
        class R: returncode = 0
        return R()
    monkeypatch.setattr(_ds.subprocess, "run", fake_run)
    out1 = _ds.stage_s3_to_local("s3://b/k/m.csv")
    out2 = _ds.stage_s3_to_local("s3://b/k/m.csv")
    assert out1 == out2 and out1.endswith("m.csv") and calls["n"] == 1   # downloaded once, reused


def test_stage_s3_no_basename_collision_across_uris(tmp_path, monkeypatch):
    # Two different objects that share a basename must NOT collide / reuse each other.
    from galaxy.ai.ml_training import datasets as _ds
    monkeypatch.chdir(tmp_path)
    def fake_run(cmd, **k):
        Path(cmd[4]).write_text("from:" + cmd[3])
        class R: returncode = 0
        return R()
    monkeypatch.setattr(_ds.subprocess, "run", fake_run)
    a = _ds.stage_s3_to_local("s3://bucketA/train.csv")
    b = _ds.stage_s3_to_local("s3://bucketB/train.csv")
    assert a != b
    assert Path(a).read_text().endswith("bucketA/train.csv")
    assert Path(b).read_text().endswith("bucketB/train.csv")


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
    assert out.endswith("m.csv") and Path(out).exists()


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


# ── id-column auto-drop (added 2026-11-05 after a Batch smoke showed a string
#    sample_id column leaked in as a junk 0.0 feature: n_features=21 for 20 genes). ──
def test_tabular_drops_non_numeric_id_column(tmp_path):
    from galaxy.ai.ml_training.datasets import load_tabular_dataset
    csv_p = tmp_path / "expr.csv"
    csv_p.write_text(
        "sample_id,GENE0,GENE1,label\n"
        "S0,8.0,1.0,A\nS1,1.0,8.0,B\nS2,8.1,1.1,A\nS3,0.9,7.9,B\n"
    )
    ds = load_tabular_dataset(str(csv_p), "label")
    assert ds.feature_names == ["GENE0", "GENE1"]        # sample_id dropped
    assert all(len(row) == 2 for row in ds.X)            # no junk 0.0 column
    assert ds.task == "classification"


def test_tabular_keeps_numeric_features_and_respects_id_cols(tmp_path):
    from galaxy.ai.ml_training.datasets import load_tabular_dataset
    csv_p = tmp_path / "expr.csv"
    csv_p.write_text("id,GENE0,GENE1,y\n1,8.0,1.0,A\n2,1.0,8.0,B\n3,7.9,1.2,A\n")
    # `id` here is numeric but semantically an identifier → caller names it.
    ds = load_tabular_dataset(str(csv_p), "y", id_cols=["id"])
    assert ds.feature_names == ["GENE0", "GENE1"]


def test_tabular_all_non_numeric_features_errors(tmp_path):
    from galaxy.ai.ml_training.datasets import load_tabular_dataset
    from galaxy.ai.ml_training.config import ConfigError
    csv_p = tmp_path / "bad.csv"
    csv_p.write_text("name,note,label\nalice,hi,A\nbob,yo,B\n")
    with pytest.raises(ConfigError):
        load_tabular_dataset(str(csv_p), "label")       # no numeric features


def test_tabular_keeps_gene_column_with_NA_and_imputes(tmp_path):
    # A numeric gene column with an "NA" cell must be KEPT (not dropped as id/metadata)
    # and the missing cell imputed with the column mean (committee finding).
    from galaxy.ai.ml_training.datasets import load_tabular_dataset
    csv_p = tmp_path / "expr.csv"
    csv_p.write_text(
        "sample_id,GENE0,GENE1,label\n"
        "S0,8.0,1.0,A\nS1,1.0,NA,B\nS2,8.1,1.2,A\nS3,0.9,7.9,B\n")
    ds = load_tabular_dataset(str(csv_p), "label")
    assert "GENE1" in ds.feature_names                 # NOT dropped for the NA
    gi = ds.feature_names.index("GENE1")
    assert all(x == x for x in (row[gi] for row in ds.X))  # no NaN survived
    assert abs(ds.X[1][gi] - (1.0 + 1.2 + 7.9) / 3) < 1e-6  # imputed with column mean
