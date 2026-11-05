"""
Generic tabular trainer — the GENERAL counterpart to the SMILES-only paths.

Trains a model on any numeric feature matrix + label column (e.g. a gene-
expression matrix with a subtype/outcome label), using STRATIFIED K-FOLD
cross-validation. No molecules, no SMILES, no RDKit — so "train a subtype
predictor on an expression matrix with 5-fold CV" is a real capability rather
than a drug-discovery special case.

Like the LLM trainer, this loads its own data from ``cfg.dataset`` (a feature
matrix), so ``training_job`` passes it a placeholder LoadedDataset. It returns
the same ``TrainingResult`` contract the executor's step parser consumes, with
cross-validation mean±std for the configured metric plus a final model fit on
all rows.

sklearn is imported lazily and guarded: if it is unavailable the result carries
``metrics_unavailable`` and an empty metric set rather than crashing, matching
`chemprop_trainer`'s degrade-soft behaviour.
"""
from __future__ import annotations

import json
import logging
import statistics
from pathlib import Path
from typing import Any

from .config import TrainingConfig
from .datasets import load_tabular_dataset, LoadedTabularDataset
from .splits import kfold_split
from .chemprop_trainer import TrainingResult

log = logging.getLogger(__name__)


def _resolve_path(cfg: TrainingConfig) -> str:
    """Local CSV path for the feature matrix. The executor stages s3_uri inputs
    to a local work dir before the container runs, so a staged run also ends up
    here as a path."""
    spec = cfg.dataset
    if spec.path:
        return spec.path
    if spec.s3_uri:
        # The ml_training .nf passes the dataset as a plain param (no Nextflow
        # `path` staging), so stage the s3 object ourselves via the AWS CLI the
        # Batch image ships. Reuses a genuinely-staged local copy if present.
        from .datasets import stage_s3_to_local
        return stage_s3_to_local(spec.s3_uri)
    raise ValueError("tabular training needs dataset.path or dataset.s3_uri")


def _make_model(task: str, seed: int):
    if task == "classification":
        from sklearn.ensemble import GradientBoostingClassifier
        return GradientBoostingClassifier(random_state=seed)
    from sklearn.ensemble import GradientBoostingRegressor
    return GradientBoostingRegressor(random_state=seed)


def _score(task: str, y_true, y_pred, model=None, X_val=None, classes=None) -> dict[str, float]:
    out: dict[str, float] = {}
    if task == "classification":
        from sklearn.metrics import accuracy_score, f1_score
        out["accuracy"] = float(accuracy_score(y_true, y_pred))
        out["macro_f1"] = float(f1_score(y_true, y_pred, average="macro"))
        # AUC only when binary and the model exposes probabilities.
        if classes is not None and len(classes) == 2 and model is not None and X_val is not None:
            try:
                from sklearn.metrics import roc_auc_score
                proba = model.predict_proba(X_val)[:, 1]
                pos = classes[1]
                out["auc"] = float(roc_auc_score([1 if y == pos else 0 for y in y_true], proba))
            except Exception:  # noqa: BLE001 — AUC is best-effort
                pass
    else:
        from sklearn.metrics import mean_absolute_error, r2_score
        out["mae"] = float(mean_absolute_error(y_true, y_pred))
        out["r2"] = float(r2_score(y_true, y_pred))
    return out


def train(cfg: TrainingConfig, artifact_dir: str) -> TrainingResult:
    """Train a generic tabular model with stratified k-fold CV."""
    Path(artifact_dir).mkdir(parents=True, exist_ok=True)
    task = cfg.task_type if cfg.task_type in ("classification", "regression") else "classification"
    path = _resolve_path(cfg)
    ds: LoadedTabularDataset = load_tabular_dataset(path, cfg.dataset.target_col, task=task)
    k = max(2, int(cfg.dataset.cv_folds))
    seed = cfg.hyperparams.seed
    log.info("[ml_training] tabular: %d rows x %d features, task=%s, %d-fold CV",
             len(ds), len(ds.feature_names), task, k)

    try:
        import sklearn  # noqa: F401
    except ImportError:
        log.warning("[ml_training] sklearn unavailable — tabular metrics not computed")
        _dump(artifact_dir, {"model_type": "sklearn_tabular", "metrics": {},
                             "metrics_unavailable": True, "n_rows": len(ds),
                             "n_features": len(ds.feature_names)})
        return TrainingResult(
            model_type="sklearn_tabular", artifact_dir=artifact_dir, metrics={},
            n_train=len(ds), n_val=0, n_test=0,
            framework_version="sklearn-unavailable",
            extra={"task": task, "metrics_unavailable": True,
                   "n_features": len(ds.feature_names)},
        )

    labels = ds.y if task == "classification" else None
    # Stratified k-fold needs >= k members per class; fall back to plain k-fold.
    if labels is not None:
        from collections import Counter
        if min(Counter(labels).values()) < k:
            labels = None
    folds = kfold_split(len(ds), k, seed, labels=labels)

    per_fold: list[dict[str, float]] = []
    classes = sorted(set(ds.y)) if task == "classification" else None
    for fr in folds.folds:
        Xtr = [ds.X[i] for i in fr.train]; ytr = [ds.y[i] for i in fr.train]
        Xva = [ds.X[i] for i in fr.val];   yva = [ds.y[i] for i in fr.val]
        model = _make_model(task, seed)
        model.fit(Xtr, ytr)
        per_fold.append(_score(task, yva, model.predict(Xva), model=model,
                               X_val=Xva, classes=classes))

    # Aggregate CV mean±std per metric.
    metrics: dict[str, float] = {}
    metric_names = sorted({m for f in per_fold for m in f})
    for m in metric_names:
        vals = [f[m] for f in per_fold if m in f]
        metrics[f"cv_{m}_mean"] = float(statistics.mean(vals))
        metrics[f"cv_{m}_std"] = float(statistics.pstdev(vals)) if len(vals) > 1 else 0.0
        metrics[m] = metrics[f"cv_{m}_mean"]  # bare name = CV mean, for gate lookup

    # Final model on all rows (the artifact that gets registered).
    final = _make_model(task, seed)
    final.fit(ds.X, ds.y)
    try:
        import pickle
        with open(Path(artifact_dir) / "model.pkl", "wb") as fh:
            pickle.dump({"model": final, "feature_names": ds.feature_names,
                         "task": task, "classes": classes}, fh)
    except Exception as e:  # noqa: BLE001 — artifact write is best-effort
        log.warning("[ml_training] could not pickle tabular model: %s", e)

    import sklearn as _sk
    _dump(artifact_dir, {"model_type": "sklearn_tabular", "task": task,
                         "metrics": metrics, "cv_folds": k,
                         "stratified": folds.stratified, "n_rows": len(ds),
                         "n_features": len(ds.feature_names),
                         "split": folds.metadata()})
    avg_val = round(statistics.mean(len(f.val) for f in folds.folds))
    return TrainingResult(
        model_type="sklearn_tabular", artifact_dir=artifact_dir, metrics=metrics,
        n_train=len(ds), n_val=avg_val, n_test=0,
        framework_version=f"scikit-learn {_sk.__version__}",
        extra={"task": task, "cv_folds": k, "stratified": folds.stratified,
               "n_features": len(ds.feature_names), "split": folds.metadata(),
               "classes": classes},
    )


def _dump(artifact_dir: str, payload: dict[str, Any]) -> None:
    d = Path(artifact_dir)
    d.mkdir(parents=True, exist_ok=True)
    (d / "metrics.json").write_text(json.dumps(payload, indent=2))
