"""
MLflow experiment-tracking wrapper (C-layer of the platform).

MLflow is lazy-imported and guarded. When MLflow is not installed (or
`BIOMATE_MLFLOW_DISABLED=1`), the tracker degrades to a no-op that records
params/metrics/artifacts in memory — so the orchestration layer and its unit
tests run identically with or without a live tracking server, and callers can
still assert on what *would* have been logged.

Usage:
    with MLflowTracker(experiment="biomate-ml-training", run_name=cfg.name) as t:
        t.log_params(cfg.to_dict())
        t.log_metrics({"val_auc": 0.83})
        t.log_artifact(artifact_dir)
        model_uri = t.register_model(artifact_dir, registered_name=cfg.name)
"""
from __future__ import annotations

import logging
import os
from typing import Any, Optional

log = logging.getLogger(__name__)


def _mlflow_available() -> bool:
    if os.environ.get("BIOMATE_MLFLOW_DISABLED") == "1":
        return False
    try:
        import mlflow  # noqa: F401
        return True
    except ImportError:
        return False


class MLflowTracker:
    """Thin context-manager over mlflow with an in-memory no-op fallback."""

    def __init__(self, experiment: str = "biomate-ml-training",
                 run_name: Optional[str] = None,
                 tracking_uri: Optional[str] = None):
        self.experiment = experiment
        self.run_name = run_name
        self.tracking_uri = tracking_uri or os.environ.get("MLFLOW_TRACKING_URI")
        self.active = _mlflow_available()
        # Recorded regardless of backend, so callers/tests can inspect.
        self.logged_params: dict[str, Any] = {}
        self.logged_metrics: dict[str, float] = {}
        self.logged_artifacts: list[str] = []
        self.run_id: Optional[str] = None
        self.registered_model_uri: Optional[str] = None
        self._run_ctx = None

    # -- context management ---------------------------------------------------
    def __enter__(self) -> "MLflowTracker":
        if not self.active:
            log.info("[mlflow] not available — tracking to in-memory no-op")
            self.run_id = "noop-run"
            return self
        import mlflow
        if self.tracking_uri:
            mlflow.set_tracking_uri(self.tracking_uri)
        mlflow.set_experiment(self.experiment)
        self._run_ctx = mlflow.start_run(run_name=self.run_name)
        run = self._run_ctx.__enter__()
        self.run_id = run.info.run_id
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        if self.active and self._run_ctx is not None:
            self._run_ctx.__exit__(exc_type, exc, tb)

    # -- logging --------------------------------------------------------------
    def log_params(self, params: dict[str, Any]) -> None:
        flat = _flatten(params)
        self.logged_params.update(flat)
        if self.active:
            import mlflow
            # MLflow params must be str-able scalars; skip nested leftovers.
            mlflow.log_params({k: v for k, v in flat.items() if _scalar(v)})

    def log_metrics(self, metrics: dict[str, float], step: Optional[int] = None) -> None:
        clean = {k: float(v) for k, v in metrics.items() if v is not None}
        self.logged_metrics.update(clean)
        if self.active:
            import mlflow
            mlflow.log_metrics(clean, step=step)

    def log_artifact(self, path: str) -> None:
        self.logged_artifacts.append(path)
        if self.active:
            import mlflow
            mlflow.log_artifacts(path) if os.path.isdir(path) else mlflow.log_artifact(path)

    def register_model(self, artifact_path: str, registered_name: str) -> Optional[str]:
        """Register the artifact into the MLflow Model Registry.

        Returns a model URI (runs:/...) or None in no-op mode. The registry
        promotion (Staging→Production) is done out of band by the deploy step.
        """
        uri = f"runs:/{self.run_id}/{os.path.basename(artifact_path.rstrip('/'))}"
        self.registered_model_uri = uri
        if self.active:
            import mlflow
            try:
                mlflow.register_model(uri, registered_name)
            except Exception as e:  # registry may be disabled on a file backend
                log.warning("[mlflow] register_model failed (%s); artifact still logged", e)
        return uri


# --- helpers -----------------------------------------------------------------

def _scalar(v: Any) -> bool:
    return isinstance(v, (str, int, float, bool)) or v is None


def _flatten(d: dict[str, Any], prefix: str = "") -> dict[str, Any]:
    out: dict[str, Any] = {}
    for k, v in (d or {}).items():
        key = f"{prefix}{k}"
        if isinstance(v, dict):
            out.update(_flatten(v, prefix=f"{key}."))
        else:
            out[key] = v
    return out
