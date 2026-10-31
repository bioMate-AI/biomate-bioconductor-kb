"""
Ludwig training entrypoint — real declarative DL, CPU-runnable.

Trains a Ludwig neural network over RDKit descriptors. Lazy-imports ludwig so
the module loads without it; the unit tests monkeypatch or importorskip.
Produces the same TrainingResult contract + manifest as the other trainers, so
it plugs into the orchestrator, QC gate, registry, and serving unchanged.
"""
from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from .config import TrainingConfig
from .datasets import LoadedDataset
from .chemprop_trainer import TrainingResult
from .ludwig_adapter import (to_ludwig_config, featurize_smiles_df, add_split_column,
                             FEATURE_COLUMNS)

log = logging.getLogger(__name__)


def train_ludwig(cfg: TrainingConfig, ds: LoadedDataset, artifact_dir: str) -> TrainingResult:
    try:
        from ludwig.api import LudwigModel
    except ImportError as e:
        raise ImportError(
            "ludwig is required for model_type=ludwig_tabular. "
            "`pip install ludwig`. This is the low-code DL engine (design §2)."
        ) from e

    target = cfg.dataset.target_col or "y"
    df = featurize_smiles_df(ds.smiles, ds.labels, target_col=target)
    if len(df) < 4:
        raise ValueError(f"too few valid molecules to train ({len(df)})")

    config = to_ludwig_config(cfg, target_col=target)
    split_meta = add_split_column(df, cfg)
    log.info("[ludwig] training %s: %d mols, %d epochs, split=%s",
             cfg.name, len(df), cfg.hyperparams.epochs, split_meta["method"])

    model = LudwigModel(config, logging_level=logging.ERROR)
    # Split per config.preprocessing: Ludwig's own random split, or the fixed
    # scaffold partitions written by add_split_column.
    train_stats, _, _ = model.train(
        dataset=df.drop(columns=["_smiles"]),
        output_directory=str(Path(artifact_dir) / "ludwig_run"),
        skip_save_processed_input=True,
    )

    metrics = _extract_metrics(cfg, train_stats, target)

    model_dir = str(Path(artifact_dir) / "ludwig_model")
    model.save(model_dir)

    import ludwig as _lud
    counts = split_meta if "n_train" in split_meta else {}
    result = TrainingResult(
        model_type="ludwig_tabular", artifact_dir=artifact_dir, metrics=metrics,
        n_train=counts.get("n_train", len(df)), n_val=counts.get("n_val", 0),
        n_test=counts.get("n_test", 0),
        framework_version=f"ludwig=={_lud.globals.LUDWIG_VERSION if hasattr(_lud,'globals') else getattr(_lud,'__version__','?')}",
        extra={"model_dir": model_dir, "feature_columns": FEATURE_COLUMNS,
               "target_col": target, "split": split_meta},
    )
    _write_manifest(artifact_dir, cfg, result)
    return result


def _extract_metrics(cfg: TrainingConfig, train_stats: Any, target: str) -> dict[str, float]:
    """Pull the primary metric out of Ludwig's TrainingStats.

    train_stats is a ludwig.api.TrainingStats object with .training/.validation/
    .test attributes, each {feature: {metric: [per-epoch values]}}. We take the
    last epoch of the held-out split (test → else validation).
    """
    metrics: dict[str, float] = {}

    def _split(name: str) -> dict:
        sub = getattr(train_stats, name, None)
        if sub is None and isinstance(train_stats, dict):
            sub = train_stats.get(name)
        return (sub or {}).get(target, {}) if sub else {}

    try:
        for split_name, prefix in (("test", "test"), ("validation", "val")):
            s = _split(split_name)
            if not s:
                continue
            if cfg.task_type == "classification":
                if s.get("roc_auc"):
                    metrics[f"{prefix}_auc"] = float(s["roc_auc"][-1])
                if s.get("accuracy"):
                    metrics[f"{prefix}_accuracy"] = float(s["accuracy"][-1])
            else:
                seq = s.get("mean_absolute_error") or s.get("loss")
                if seq:
                    metrics[f"{prefix}_mae"] = float(seq[-1])
    except Exception as e:  # metrics extraction must never crash a good run
        log.warning("[ludwig] metric extraction failed: %s", e)
    return metrics


def _write_manifest(artifact_dir: str, cfg: TrainingConfig, result: TrainingResult) -> None:
    (Path(artifact_dir) / "manifest.json").write_text(json.dumps({
        "name": cfg.name, "model_type": result.model_type, "task_type": cfg.task_type,
        "metrics": result.metrics, "framework_version": result.framework_version,
        "extra": result.extra,
    }, indent=2))
