"""
BentoML serving scaffold (D-layer).

Packages a registered, platform-trained model as an inference service. BentoML
is lazy-imported and guarded so importing this module never requires bentoml.

Two entry points:
  - `build_bento_service(wrapper)`  — wrap a loaded ChempropModelWrapper /
    BaseModelWrapper as a BentoML Service exposing POST /predict.
  - `PredictRequest` / `PredictResponse` — the plain-dict API contract, defined
    here (no bentoml needed) so callers and tests can assert on the shape.

The resulting service is `bentoml build`-able into a container and deployed
without Kubernetes (ECS / EC2 / Batch endpoint), per design doc §4.5.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any, Optional

log = logging.getLogger(__name__)


@dataclass
class PredictRequest:
    smiles: list[str]


@dataclass
class PredictResponse:
    model: str
    scores: dict[str, float]

    def to_dict(self) -> dict[str, Any]:
        return {"model": self.model, "scores": self.scores}


def predict_with_wrapper(wrapper, smiles: list[str]) -> PredictResponse:
    """Framework-agnostic prediction path — the core the Bento service calls.

    Works with any BaseModelWrapper (score() -> {smiles: float}); fully testable
    without bentoml installed.
    """
    scores = wrapper.score(smiles)
    return PredictResponse(model=wrapper.name, scores=scores)


def _bentoml_available() -> bool:
    try:
        import bentoml  # noqa: F401
        return True
    except ImportError:
        return False


def build_bento_service(wrapper, service_name: Optional[str] = None):
    """Build a BentoML Service around a loaded model wrapper.

    Returns a bentoml.Service. Raises a clear error if bentoml is absent so the
    deploy step fails loudly rather than at import time.
    """
    if not _bentoml_available():
        raise ImportError(
            "bentoml is required to build a serving Service. "
            "`pip install bentoml`; the model logic itself is bentoml-free "
            "(see predict_with_wrapper)."
        )
    import bentoml

    name = service_name or f"biomate-{_slug(wrapper.name)}"
    svc = bentoml.Service(name)

    @svc.api(input=bentoml.io.JSON(), output=bentoml.io.JSON())  # type: ignore[attr-defined]
    def predict(payload: dict) -> dict:
        req = PredictRequest(smiles=list(payload.get("smiles", [])))
        return predict_with_wrapper(wrapper, req.smiles).to_dict()

    return svc


def _slug(name: str) -> str:
    return "".join(c if c.isalnum() or c in "-_" else "-" for c in name.strip().lower())
