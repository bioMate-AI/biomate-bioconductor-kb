"""Tests for the GENERAL (non-molecule) tabular training path:
stratified k-fold CV + feature-matrix loader + the sklearn_tabular trainer.

These prove "train a subtype predictor on an expression matrix with k-fold CV"
is a real, general capability — not a SMILES special case.
"""
import csv
import random

import pytest

from galaxy.ai.ml_training.splits import kfold_split
from galaxy.ai.ml_training.datasets import load_tabular_dataset
from galaxy.ai.ml_training.config import TrainingConfig, DatasetSpec, Hyperparams


def test_kfold_is_a_partition():
    r = kfold_split(20, 5, seed=1)
    assert r.k == 5 and len(r.folds) == 5
    all_val = sorted(i for f in r.folds for i in f.val)
    assert all_val == list(range(20))                      # every row validated once
    for f in r.folds:
        assert set(f.train).isdisjoint(f.val)              # no leakage
        assert sorted(f.train + f.val) == list(range(20))  # train ∪ val = all


def test_kfold_is_stratified():
    # 12 of class "A", 8 of class "B"; each of 4 folds should keep ~3:2 balance.
    labels = ["A"] * 12 + ["B"] * 8
    r = kfold_split(len(labels), 4, seed=7, labels=labels)
    assert r.stratified
    for f in r.folds:
        a = sum(labels[i] == "A" for i in f.val)
        b = sum(labels[i] == "B" for i in f.val)
        assert a == 3 and b == 2                           # exact round-robin split


def test_kfold_deterministic():
    assert ([f.val for f in kfold_split(15, 3, seed=42).folds]
            == [f.val for f in kfold_split(15, 3, seed=42).folds])


def _write_expression_csv(path, n=60, n_genes=8, seed=0):
    """Synthetic expression matrix: subtype label separable from gene features."""
    rng = random.Random(seed)
    header = ["sample_id"] + [f"gene{i}" for i in range(n_genes)] + ["subtype"]
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(header)
        for s in range(n):
            sub = "LumA" if s % 2 == 0 else "Basal"
            shift = 2.0 if sub == "LumA" else -2.0
            feats = [round(rng.gauss(shift, 1.0), 3) for _ in range(n_genes)]
            w.writerow([f"S{s}"] + feats + [sub])


def test_tabular_loader_reads_expression_matrix(tmp_path):
    csv_path = tmp_path / "expr.csv"
    _write_expression_csv(csv_path)
    ds = load_tabular_dataset(str(csv_path), target_col="subtype", id_cols=["sample_id"])
    assert ds.task == "classification"
    assert ds.feature_names == [f"gene{i}" for i in range(8)]   # sample_id/subtype excluded
    assert len(ds) == 60 and len(ds.X[0]) == 8
    assert set(ds.y) == {"LumA", "Basal"}


def test_sklearn_tabular_trainer_runs_kfold_cv(tmp_path):
    pytest.importorskip("sklearn")
    from galaxy.ai.ml_training.tabular_trainer import train
    csv_path = tmp_path / "expr.csv"
    _write_expression_csv(csv_path, n=60)
    cfg = TrainingConfig(
        name="subtype-model", task_type="classification", model_type="sklearn_tabular",
        featurizer="none",
        dataset=DatasetSpec(path=str(csv_path), target_col="subtype", split="kfold", cv_folds=5),
        hyperparams=Hyperparams(seed=42), metric="accuracy",
    )
    result = train(cfg, str(tmp_path / "artifacts"))
    assert result.model_type == "sklearn_tabular"
    # cross-validation metrics are present and sane
    assert "cv_accuracy_mean" in result.metrics and "cv_accuracy_std" in result.metrics
    assert "accuracy" in result.metrics                     # bare name = CV mean (gate lookup)
    assert 0.0 <= result.metrics["cv_accuracy_mean"] <= 1.0
    assert result.metrics["cv_accuracy_mean"] > 0.8          # separable synthetic data
    assert result.extra["cv_folds"] == 5 and result.extra["stratified"] is True
    assert (tmp_path / "artifacts" / "model.pkl").exists()


def test_config_accepts_kfold_split():
    cfg = TrainingConfig(
        name="m", task_type="classification", model_type="sklearn_tabular",
        dataset=DatasetSpec(path="/tmp/x.csv", target_col="y", split="kfold", cv_folds=5),
    )
    cfg.validate()                                          # should not raise
    with pytest.raises(Exception):
        DatasetSpec(path="/tmp/x.csv", split="kfold", cv_folds=1).validate()
