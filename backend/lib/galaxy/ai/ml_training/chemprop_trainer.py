"""
Chemprop molecular-DL training entrypoint (A-layer).

Dispatches a TrainingConfig to its trainer and emits an artifact + validation
metrics. model_type=chemprop_gnn is NOT implemented yet and raises
NotImplementedError; the sklearn baseline (RDKit descriptors + gradient
boosting, scaffold or random split) and the Ludwig trainers are real.

Heavy deps (rdkit, numpy, scikit-learn) are lazy-imported and guarded, so the
orchestration tests can monkeypatch `train()` without any ML stack installed.
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
    # No Chemprop training loop exists yet. Fail before any artifact, manifest
    # or registration can be produced, whether or not chemprop is installed.
    raise NotImplementedError(
        "model_type=chemprop_gnn is not implemented: there is no Chemprop training "
        "loop, so no model was trained. Use model_type=ludwig_tabular or sklearn_gbr."
    )


def _train_sklearn(cfg: TrainingConfig, ds: LoadedDataset, artifact_dir: str) -> TrainingResult:
    """Cheap RDKit-2D + GradientBoosting baseline (mirrors ppbr_predictor.py)."""
    try:
        import numpy as np
        from sklearn.ensemble import GradientBoostingClassifier, GradientBoostingRegressor
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

    from .splits import split_dataset

    feats, ys, smis = [], [], []
    for smi, y in ds.rows:
        f = featurize(smi)
        if f is not None:
            feats.append(f)
            ys.append(y)
            smis.append(smi)
    X = np.array(feats)
    y = np.array(ys)
    spec = cfg.dataset
    split = split_dataset(smis, spec.split, spec.val_frac, spec.test_frac, cfg.hyperparams.seed)
    if not split.train or not split.test:
        raise ValueError(
            f"{split.method} split left an empty train or test partition "
            f"({split.metadata()}); provide more molecules or adjust val_frac/test_frac")
    Xtr, ytr = X[split.train], y[split.train]

    unavailable: dict[str, str] = {}
    if cfg.task_type == "classification":
        model = GradientBoostingClassifier(random_state=cfg.hyperparams.seed)
        model.fit(Xtr, ytr)
    else:
        model = GradientBoostingRegressor(random_state=cfg.hyperparams.seed)
        model.fit(Xtr, ytr)

    metrics: dict[str, float] = {}
    for prefix, idx in (("val", split.val), ("test", split.test)):
        if not idx:
            continue
        Xp, yp = X[idx], y[idx]
        if cfg.task_type == "classification":
            if len(set(yp.tolist())) > 1:
                metrics[f"{prefix}_auc"] = float(roc_auc_score(yp, model.predict_proba(Xp)[:, 1]))
            else:
                unavailable[f"{prefix}_auc"] = f"{prefix} partition contains a single class"
        else:
            metrics[f"{prefix}_mae"] = float(mean_absolute_error(yp, model.predict(Xp)))

    model_path = str(Path(artifact_dir) / "model.pkl")
    joblib.dump(model, model_path)
    import sklearn
    return TrainingResult(
        model_type="sklearn_gbr", artifact_dir=artifact_dir, metrics=metrics,
        n_train=len(split.train), n_val=len(split.val), n_test=len(split.test),
        framework_version=f"sklearn=={sklearn.__version__}",
        extra={"featurizer": "rdkit_2d_6desc", "model_path": model_path,
               "split": split.metadata(), "metrics_unavailable": unavailable},
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
