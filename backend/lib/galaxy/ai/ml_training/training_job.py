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
import math
import os
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
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
    reason: str = ""

    def to_sse_payload(self) -> dict[str, Any]:
        """Shape compatible with the frontend qc_gate_results SSE event."""
        measured = self.value if self.value is not None and math.isfinite(self.value) else None
        return {
            "gates": [{
                "name": self.metric,
                "measured": measured,
                "threshold": self.threshold,
                "status": "pass" if self.passed else "halt",
                "direction": self.direction,
                "reason": self.reason,
            }]
        }

    def to_record(self) -> dict[str, Any]:
        """JSON-safe gate result persisted with a model version."""
        finite = self.value is not None and math.isfinite(self.value)
        return {"metric": self.metric, "value": self.value if finite else None,
                "threshold": self.threshold, "passed": self.passed,
                "direction": self.direction, "reason": self.reason}


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
    model_version: Optional[int] = None
    model_status: Optional[str] = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.config.name,
            "model_version": self.model_version,
            "model_status": self.model_status,
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
    """Apply the configured QC gate. Fails closed: when a threshold is
    configured, a missing, non-numeric, NaN or infinite metric fails."""
    raw = result.primary_metric(cfg.metric)
    direction = _metric_direction(cfg.metric)
    thr = cfg.gate_threshold
    try:
        value = None if raw is None else float(raw)
    except (TypeError, ValueError):
        value = None
    if thr is None:
        return GateResult(cfg.metric, value, thr, True, direction, reason="no_gate_configured")
    if not math.isfinite(thr):
        return GateResult(cfg.metric, value, thr, False, direction,
                          reason=f"gate threshold {thr!r} is not finite")
    if raw is None:
        return GateResult(cfg.metric, None, thr, False, direction,
                          reason=f"metric '{cfg.metric}' missing from training metrics "
                                 f"{sorted(result.metrics)}")
    if value is None:
        return GateResult(cfg.metric, None, thr, False, direction,
                          reason=f"metric '{cfg.metric}' is not numeric: {raw!r}")
    if not math.isfinite(value):
        return GateResult(cfg.metric, value, thr, False, direction,
                          reason=f"metric '{cfg.metric}' is not finite: {value!r}")
    if direction == "higher_is_better":
        passed = value >= thr
        op = ">=" if passed else "<"
    else:
        passed = value <= thr
        op = "<=" if passed else ">"
    return GateResult(cfg.metric, value, thr, passed, direction,
                      reason=f"{cfg.metric}={value:.4g} {op} threshold {thr:.4g}")


def run_training_job(
    cfg: TrainingConfig,
    *,
    artifact_dir: Optional[str] = None,
    registry: Any = None,                    # CustomModelRegistry (optional)
    load_fn: Optional[Callable[[Any], LoadedDataset]] = None,
    train_fn: Optional[Callable[..., TrainingResult]] = None,
    tracker: Optional[MLflowTracker] = None,
) -> JobResult:
    """Run the full training loop and return a JobResult.

    Config errors and training failures raise; a version reserved for the run
    is then recorded as rejected with the failure reason.

    load_fn/train_fn resolve at call time (default None → module defaults) so
    they stay monkeypatchable via `training_job._default_load/_default_train`.
    """
    load_fn = load_fn or _default_load
    train_fn = train_fn or _default_train
    cfg.validate()
    # With a registry, the next version is reserved up front and its artifact
    # directory is keyed by that version; without one, each run gets a fresh
    # directory. Either way a run never overwrites an earlier artifact.
    version: Optional[int] = None
    if registry is not None and artifact_dir is None:
        version, artifact_dir = registry.reserve_version(
            cfg.campaign_id, cfg.name, str(_default_artifact_root()))
    elif artifact_dir is None:
        run_id = f"run-{datetime.now(timezone.utc):%Y%m%dT%H%M%S}-{uuid.uuid4().hex[:8]}"
        artifact_dir = str(_default_artifact_root() / cfg.campaign_id / _slug(cfg.name) / run_id)
    Path(artifact_dir).mkdir(parents=True, exist_ok=True)
    try:
        return _run(cfg, artifact_dir, registry, version, load_fn, train_fn, tracker)
    except Exception as exc:
        if version is not None:
            registry.fail_version(cfg.campaign_id, cfg.name, version,
                                  f"{type(exc).__name__}: {exc}")
        raise


def _run(cfg, artifact_dir, registry, version, load_fn, train_fn, tracker) -> JobResult:
    # 1. Load data. LLM fine-tuning uses instruction/response text, not the
    # molecular (smiles,label) loader — the LLM trainer loads its own rows from
    # cfg.dataset, so pass a placeholder here.
    from .config import LLM_MODEL_TYPES
    if cfg.model_type in LLM_MODEL_TYPES:
        dataset = LoadedDataset([], "instruction", "output", source="llm/text (loaded in trainer)")
    elif cfg.model_type == "protein_diffusion":
        # Structure diffusion loads a set of PDB/mmCIF backbones inside its own
        # trainer (not the molecular smiles/label loader) — pass a placeholder.
        dataset = LoadedDataset([], "structure", "none",
                                source="structure/pdb (loaded in trainer)")
    elif cfg.model_type == "scrna_diffusion":
        dataset = LoadedDataset([], "gene", "expr", source="scrna/h5ad (loaded in trainer)")
    elif cfg.model_type == "sklearn_tabular":
        # Generic feature-matrix trainer loads its own CSV (not the SMILES loader).
        dataset = LoadedDataset([], "features", cfg.dataset.target_col,
                                source="tabular (loaded in trainer)")
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

    # 5. Record an immutable version in the per-campaign registry. A passed
    #    gate yields a `candidate` that a reviewer may promote; a failed gate
    #    yields a `rejected` version that can never be served.
    registered = False
    model_version = model_status = None
    if registry is not None:
        mv = registry.register_trained_version(
            cfg.campaign_id, cfg.name, artifact_dir, version=version,
            metrics=result.metrics, gate=gate.to_record(), task_type=cfg.task_type,
            higher_is_better=cfg.higher_is_better, dataset_rows=dataset.rows or None,
            split=result.extra.get("split"),
            extra_spec={"model_type": result.model_type,
                        "framework_version": result.framework_version,
                        "dataset_source": dataset.source, "mlflow_model_uri": model_uri,
                        "config": cfg.to_dict()},
        )
        model_version, model_status = mv.version, mv.status
        registered = mv.status == "candidate"
        if registered:
            log.info("[ml_training] '%s' v%d recorded as candidate in campaign %s",
                     cfg.name, mv.version, cfg.campaign_id)
        else:
            log.warning("[ml_training] '%s' v%d failed QC gate (%s) — rejected",
                        cfg.name, mv.version, gate.reason)

    return JobResult(
        config=cfg, training=result, gate=gate,
        mlflow_run_id=t.run_id, mlflow_model_uri=model_uri,
        registered=registered, artifact_dir=artifact_dir,
        dataset_source=dataset.source,
        model_version=model_version, model_status=model_status,
    )


def _slug(name: str) -> str:
    return "".join(c if c.isalnum() or c in "-_" else "-" for c in name.strip().lower())
