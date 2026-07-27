"""
Training-job orchestrator — the end-to-end low-code loop.

    load dataset → train → evaluate/QC-gate → track (MLflow) → register (registry)

Every heavy step is injectable (load_fn / train_fn / registry) so this
orchestration is fully unit-testable without chemprop/mlflow/rdkit installed:
the tests pass stub functions and assert on the wiring (MLflow logged the right
params/metrics, the QC gate fired correctly, the model was registered).

The QC gate result is shaped to match the existing `qc_gate_results` SSE event
(design doc §4.3), so training reuses the workflow panel's auto-loop UX.
"""
from __future__ import annotations

import logging
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Optional

from .config import TrainingConfig
from .datasets import LoadedDataset, load_dataset as _default_load
from .chemprop_trainer import TrainingResult, train as _default_train
from .mlflow_tracker import MLflowTracker

log = logging.getLogger(__name__)

# Metrics where a *higher* value is better (else lower is better).
_HIGHER_IS_BETTER_METRICS = {"auc", "accuracy", "f1", "r2", "prc_auc"}

_ARTIFACT_ROOT_ENV = "ML_TRAINING_ARTIFACT_ROOT"


def _default_artifact_root() -> Path:
    """Where trained artifacts land, computed lazily & layout-independently.

    Order: ML_TRAINING_ARTIFACT_ROOT env → the galaxy backend repo's data/
    dir (when running inside it) → cwd/data/ml_training (standalone / training
    container). Computed at call time so importing this module never depends on
    a specific on-disk depth — the training container copies the package to a
    shallow path where parents[5] would not exist.
    """
    env = os.environ.get(_ARTIFACT_ROOT_ENV)
    if env:
        return Path(env)
    p = Path(__file__).resolve()
    try:
        return p.parents[5] / "data" / "ml_training"      # backend/lib/galaxy/ai/ml_training/..
    except IndexError:
        return Path.cwd() / "data" / "ml_training"


@dataclass
class GateResult:
    metric: str
    value: Optional[float]
    threshold: Optional[float]
    passed: bool
    direction: str            # "higher_is_better" | "lower_is_better"

    def to_sse_payload(self) -> dict[str, Any]:
        """Shape compatible with the frontend qc_gate_results SSE event."""
        return {
            "gates": [{
                "name": self.metric,
                "measured": self.value,
                "threshold": self.threshold,
                "status": "pass" if self.passed else "halt",
                "direction": self.direction,
            }]
        }


@dataclass
class JobResult:
    config: TrainingConfig
    training: Optional[TrainingResult]
    gate: Optional[GateResult]
    mlflow_run_id: Optional[str]
    mlflow_model_uri: Optional[str]
    registered: bool
    artifact_dir: str
    dataset_source: str = ""
    error: Optional[str] = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.config.name,
            "metrics": self.training.metrics if self.training else {},
            "gate": self.gate.to_sse_payload() if self.gate else None,
            "mlflow_run_id": self.mlflow_run_id,
            "mlflow_model_uri": self.mlflow_model_uri,
            "registered": self.registered,
            "artifact_dir": self.artifact_dir,
            "dataset_source": self.dataset_source,
            "error": self.error,
        }


def _metric_direction(metric: str) -> str:
    return "higher_is_better" if metric.lower() in _HIGHER_IS_BETTER_METRICS else "lower_is_better"


def _evaluate_gate(cfg: TrainingConfig, result: TrainingResult) -> GateResult:
    value = result.primary_metric(cfg.metric)
    direction = _metric_direction(cfg.metric)
    thr = cfg.gate_threshold
    if thr is None or value is None:
        passed = True  # no gate configured, or metric unavailable → don't block
    elif direction == "higher_is_better":
        passed = value >= thr
    else:
        passed = value <= thr
    return GateResult(cfg.metric, value, thr, passed, direction)


def run_training_job(
    cfg: TrainingConfig,
    *,
    artifact_dir: Optional[str] = None,
    registry: Any = None,                    # CustomModelRegistry (optional)
    load_fn: Optional[Callable[[Any], LoadedDataset]] = None,
    train_fn: Optional[Callable[..., TrainingResult]] = None,
    tracker: Optional[MLflowTracker] = None,
) -> JobResult:
    """Run the full training loop. Returns a JobResult; never raises for the
    expected failure modes (bad config surfaces as JobResult.error).

    load_fn/train_fn resolve at call time (default None → module defaults) so
    they stay monkeypatchable via `training_job._default_load/_default_train`.
    """
    load_fn = load_fn or _default_load
    train_fn = train_fn or _default_train
    cfg.validate()
    artifact_dir = artifact_dir or str(_default_artifact_root() / cfg.campaign_id / _slug(cfg.name))
    Path(artifact_dir).mkdir(parents=True, exist_ok=True)

    # 1. Load data. LLM fine-tuning uses instruction/response text, not the
    # molecular (smiles,label) loader — the LLM trainer loads its own rows from
    # cfg.dataset, so pass a placeholder here.
    if cfg.model_type == "ludwig_llm":
        dataset = LoadedDataset([], "instruction", "output", source="llm (loaded in trainer)")
    else:
        dataset = load_fn(cfg.dataset)
    log.info("[ml_training] loaded %d rows from %s", len(dataset), dataset.source)

    # 2/3/4. Train + track + evaluate under one MLflow run
    tracker = tracker or MLflowTracker(experiment=cfg.mlflow_experiment, run_name=cfg.name)
    with tracker as t:
        t.log_params(cfg.to_dict())
        t.log_params({"dataset_source": dataset.source, "n_rows": len(dataset)})
        result = train_fn(cfg, dataset, artifact_dir)
        t.log_metrics(result.metrics)
        t.log_artifact(artifact_dir)
        gate = _evaluate_gate(cfg, result)
        t.log_metrics({"gate_passed": 1.0 if gate.passed else 0.0})
        model_uri = t.register_model(artifact_dir, registered_name=cfg.name)

    # 5. Register into the existing per-campaign model registry (only if the
    #    QC gate passed — a failed model must not silently become scorable).
    registered = False
    if registry is not None and gate.passed:
        from .chemprop_wrapper import ChempropModelWrapper
        wrapper = ChempropModelWrapper(
            name=cfg.name, campaign_id=cfg.campaign_id, artifact_dir=artifact_dir,
            higher_is_better=cfg.higher_is_better,
        )
        registry.register(wrapper, config={"source": "ml_training", "model_uri": model_uri})
        registered = True
        log.info("[ml_training] registered '%s' into campaign %s", cfg.name, cfg.campaign_id)
    elif registry is not None and not gate.passed:
        log.warning("[ml_training] '%s' failed QC gate (%s=%s vs %s) — NOT registered",
                    cfg.name, cfg.metric, gate.value, gate.threshold)

    return JobResult(
        config=cfg, training=result, gate=gate,
        mlflow_run_id=t.run_id, mlflow_model_uri=model_uri,
        registered=registered, artifact_dir=artifact_dir,
        dataset_source=dataset.source,
    )


def _slug(name: str) -> str:
    return "".join(c if c.isalnum() or c in "-_" else "-" for c in name.strip().lower())
