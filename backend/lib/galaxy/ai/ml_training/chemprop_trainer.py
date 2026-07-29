"""
Chemprop molecular-DL training entrypoint (A-layer).

This is the genuinely-new piece: train a Chemprop graph-neural-network on a
molecular dataset and emit a versioned artifact + validation metrics. A cheap
sklearn baseline path is included for quick smoke runs / capability comparison.

Heavy deps (chemprop, torch, rdkit, numpy, scikit-learn) are lazy-imported and
guarded. The unit tests never call `train()`; they monkeypatch it, so the suite
runs without any ML stack installed. On a real training worker (AWS Batch GPU
tier `process_gpu`, see design doc §4.1) the imports resolve and training runs.
"""
from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any, Optional

from .config import TrainingConfig
from .datasets import LoadedDataset

log = logging.getLogger(__name__)


@dataclass
class TrainingResult:
    model_type: str
    artifact_dir: str
    metrics: dict[str, float]           # e.g. {"val_auc": .., "test_auc": ..}
    n_train: int
    n_val: int
    n_test: int
    framework_version: str = ""
    extra: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    def primary_metric(self, name: str) -> Optional[float]:
        for key in (f"val_{name}", f"test_{name}", name):
            if key in self.metrics:
                return self.metrics[key]
        return None


def train(cfg: TrainingConfig, dataset: LoadedDataset, artifact_dir: str) -> TrainingResult:
    """Dispatch to the configured trainer. Writes the artifact to artifact_dir."""
    Path(artifact_dir).mkdir(parents=True, exist_ok=True)
    if cfg.model_type == "chemprop_gnn":
        result = _train_chemprop(cfg, dataset, artifact_dir)
    elif cfg.model_type == "ludwig_tabular":
        from .ludwig_trainer import train_ludwig
        result = train_ludwig(cfg, dataset, artifact_dir)
    elif cfg.model_type == "ludwig_llm":
        from .llm_trainer import train_ludwig_llm
        result = train_ludwig_llm(cfg, dataset, artifact_dir)
    elif cfg.model_type in ("trl_dpo", "trl_grpo"):
        from .trl_trainer import train_trl
        result = train_trl(cfg, dataset, artifact_dir)
    elif cfg.model_type == "sklearn_gbr":
        result = _train_sklearn(cfg, dataset, artifact_dir)
    else:  # pragma: no cover - guarded by config.validate()
        raise ValueError(f"unsupported model_type {cfg.model_type}")
    # Persist a small manifest next to the artifact for the wrapper to load.
    _write_manifest(artifact_dir, cfg, result)
    return result


def _train_chemprop(cfg: TrainingConfig, ds: LoadedDataset, artifact_dir: str) -> TrainingResult:
    try:
        import chemprop  # noqa: F401
    except ImportError as e:
        raise ImportError(
            "chemprop is required for model_type=chemprop_gnn. Install with "
            "`pip install chemprop`, or use model_type=sklearn_gbr for a baseline. "
            "On production this runs in the training container image."
        ) from e

    # NOTE: kept deliberately high-level for the PoC skeleton. The concrete
    # chemprop>=2.0 training loop (MoleculeDatapoint -> MoleculeDataset ->
    # data splits -> MPNN -> Trainer.fit) is wired on the training worker.
    from .datasets import LoadedDataset  # local import for clarity
    hp = cfg.hyperparams
    log.info("[chemprop] training %s: %d rows, %d epochs, depth=%d",
             cfg.name, len(ds), hp.epochs, hp.depth)
    # --- placeholder for the real fit; the worker fills this in. ---
    raise NotImplementedError(
        "Concrete chemprop training loop is implemented on the training worker "
        "image. This skeleton validates config/orchestration; see design doc §8."
    )


def _train_sklearn(cfg: TrainingConfig, ds: LoadedDataset, artifact_dir: str) -> TrainingResult:
    """Cheap RDKit-2D + GradientBoosting baseline (mirrors ppbr_predictor.py)."""
    try:
        import numpy as np
        from sklearn.ensemble import GradientBoostingClassifier, GradientBoostingRegressor
        from sklearn.model_selection import train_test_split
        from sklearn.metrics import roc_auc_score, mean_absolute_error
        from rdkit import Chem
        from rdkit.Chem import Descriptors
    except ImportError as e:
        raise ImportError(
            "sklearn_gbr baseline needs scikit-learn + rdkit + numpy. "
            "Install them or use the offline fixture path in tests."
        ) from e
    import joblib

    def featurize(smiles: str):
        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            return None
        return [Descriptors.MolWt(mol), Descriptors.MolLogP(mol),
                Descriptors.NumHDonors(mol), Descriptors.NumHAcceptors(mol),
                Descriptors.TPSA(mol), Descriptors.NumRotatableBonds(mol)]

    feats, ys = [], []
    for smi, y in ds.rows:
        f = featurize(smi)
        if f is not None:
            feats.append(f)
            ys.append(y)
    X = np.array(feats)
    y = np.array(ys)
    Xtr, Xte, ytr, yte = train_test_split(
        X, y, test_size=cfg.dataset.test_frac or 0.2, random_state=cfg.hyperparams.seed)

    if cfg.task_type == "classification":
        model = GradientBoostingClassifier(random_state=cfg.hyperparams.seed)
        model.fit(Xtr, ytr)
        proba = model.predict_proba(Xte)[:, 1]
        metrics = {"test_auc": float(roc_auc_score(yte, proba))} if len(set(yte)) > 1 else {}
    else:
        model = GradientBoostingRegressor(random_state=cfg.hyperparams.seed)
        model.fit(Xtr, ytr)
        metrics = {"test_mae": float(mean_absolute_error(yte, model.predict(Xte)))}

    model_path = str(Path(artifact_dir) / "model.pkl")
    joblib.dump(model, model_path)
    import sklearn
    return TrainingResult(
        model_type="sklearn_gbr", artifact_dir=artifact_dir, metrics=metrics,
        n_train=len(Xtr), n_val=0, n_test=len(Xte),
        framework_version=f"sklearn=={sklearn.__version__}",
        extra={"featurizer": "rdkit_2d_6desc", "model_path": model_path},
    )


def _write_manifest(artifact_dir: str, cfg: TrainingConfig, result: TrainingResult) -> None:
    manifest = {
        "name": cfg.name,
        "model_type": result.model_type,
        "task_type": cfg.task_type,
        "metrics": result.metrics,
        "framework_version": result.framework_version,
        "extra": result.extra,
    }
    (Path(artifact_dir) / "manifest.json").write_text(json.dumps(manifest, indent=2))
