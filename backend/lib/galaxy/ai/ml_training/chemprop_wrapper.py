"""
Trained-model → BaseModelWrapper bridge.

This is the reuse seam: a model trained by this platform is exposed through the
EXISTING `drug_discovery.custom_model_wrapper.BaseModelWrapper` interface, so it
drops straight into the existing `CustomModelRegistry`, run-log, and REST API
(`POST /api/drug-discovery/{campaign_id}/models/{name}/run`) with no new
serving contract.

A `predict_fn` can be injected (used by tests and by an already-loaded model);
otherwise the wrapper lazily loads the artifact written by `chemprop_trainer`.
"""
from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Callable, Optional

from ..drug_discovery.custom_model_wrapper import BaseModelWrapper

log = logging.getLogger(__name__)


class ChempropModelWrapper(BaseModelWrapper):
    """Expose a platform-trained model as a scorable, registry-compatible model."""

    def __init__(self, name: str, campaign_id: str, artifact_dir: str,
                 predict_fn: Optional[Callable[[list[str]], dict[str, float]]] = None,
                 weight: float = 1.0, higher_is_better: bool = False):
        super().__init__(name, campaign_id, weight, higher_is_better)
        self.artifact_dir = artifact_dir
        self._predict_fn = predict_fn
        self._loaded = predict_fn is not None
        self._model = None
        self._model_type: Optional[str] = None

    # -- BaseModelWrapper contract -------------------------------------------
    def score(self, smiles_list: list[str]) -> dict[str, float]:
        if not self._loaded:
            self._load()
        result = self._predict_fn(smiles_list)  # type: ignore[misc]
        if not isinstance(result, dict):
            raise ValueError(f"{self.name}: predict_fn must return dict, got {type(result)}")
        return {str(k): float(v) for k, v in result.items()}

    def _mode(self) -> str:
        return "python"

    # -- artifact loading -----------------------------------------------------
    def _load(self) -> None:
        manifest_path = Path(self.artifact_dir) / "manifest.json"
        if not manifest_path.exists():
            raise FileNotFoundError(
                f"no manifest.json in {self.artifact_dir}; was the model trained?"
            )
        manifest = json.loads(manifest_path.read_text())
        self._model_type = manifest.get("model_type")
        if self._model_type == "sklearn_gbr":
            self._predict_fn = self._make_sklearn_predict(manifest)
        elif self._model_type == "ludwig_tabular":
            self._predict_fn = self._make_ludwig_predict(manifest)
        elif self._model_type == "chemprop_gnn":
            self._predict_fn = self._make_chemprop_predict(manifest)
        else:
            raise ValueError(f"cannot load model_type={self._model_type}")
        self._loaded = True

    def _make_sklearn_predict(self, manifest: dict) -> Callable[[list[str]], dict[str, float]]:
        import joblib
        import numpy as np
        from rdkit import Chem
        from rdkit.Chem import Descriptors
        model = joblib.load(manifest["extra"]["model_path"])

        def _feat(smi: str):
            mol = Chem.MolFromSmiles(smi)
            if mol is None:
                return None
            return [Descriptors.MolWt(mol), Descriptors.MolLogP(mol),
                    Descriptors.NumHDonors(mol), Descriptors.NumHAcceptors(mol),
                    Descriptors.TPSA(mol), Descriptors.NumRotatableBonds(mol)]

        is_clf = hasattr(model, "predict_proba")

        def predict(smiles_list: list[str]) -> dict[str, float]:
            out: dict[str, float] = {}
            for smi in smiles_list:
                f = _feat(smi)
                if f is None:
                    out[smi] = float("nan")
                    continue
                X = np.array([f])
                out[smi] = float(model.predict_proba(X)[0, 1] if is_clf else model.predict(X)[0])
            return out

        return predict

    def _make_ludwig_predict(self, manifest: dict) -> Callable[[list[str]], dict[str, float]]:
        """Load the saved LudwigModel and predict over RDKit descriptors."""
        from ludwig.api import LudwigModel
        from .ludwig_adapter import featurize_smiles_df
        model = LudwigModel.load(manifest["extra"]["model_dir"])
        target = manifest["extra"].get("target_col", "y")

        def predict(smiles_list: list[str]) -> dict[str, float]:
            df = featurize_smiles_df(smiles_list, None)
            if df.empty:
                return {s: float("nan") for s in smiles_list}
            preds, _ = model.predict(dataset=df.drop(columns=["_smiles"]))
            # Ludwig returns a df with '<target>_probabilities_True' (binary) or
            # '<target>_predictions' (regression); pick the score column.
            col = next((c for c in preds.columns
                        if c.endswith("probabilities_True") or c.endswith("_predictions")), None)
            vals = preds[col].tolist() if col else [float("nan")] * len(df)
            return {s: float(v) for s, v in zip(df["_smiles"].tolist(), vals)}

        return predict

    def _make_chemprop_predict(self, manifest: dict) -> Callable[[list[str]], dict[str, float]]:
        # Concrete chemprop inference is wired on the serving image; the PoC
        # exercises the sklearn path + injected predict_fn end-to-end.
        raise NotImplementedError(
            "chemprop artifact loading is implemented on the serving image; "
            "inject predict_fn for tests / use sklearn_gbr for the local PoC."
        )
