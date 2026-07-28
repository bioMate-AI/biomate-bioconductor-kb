"""
BioMate ML Training Platform (PoC skeleton).

A low-code, declarative training → validate → track → register → serve loop
for molecular / drug-discovery deep-learning models.

Design principle (see docs/20260717_DL_TRAINING_PLATFORM_SELECTION_AND_ARCHITECTURE.md):
this package REUSES the existing drug_discovery model abstractions rather than
building a parallel silo:

  - `drug_discovery.custom_model_wrapper.BaseModelWrapper`  — model interface
  - `drug_discovery.custom_model_registry.CustomModelRegistry` — model registry
  - `drug_discovery.model_validation`                       — eval/validation metrics

What this package ADDS (the genuinely missing pieces):
  - declarative low-code training config (`config.TrainingConfig`)
  - Chemprop molecular-DL training entrypoint (`chemprop_trainer`)
  - MLflow experiment tracking (`mlflow_tracker`)
  - a trained-model → BaseModelWrapper bridge (`chemprop_wrapper`)
  - a BentoML serving scaffold (`bento_service`)
  - an orchestrator that ties them together (`training_job`)

All heavy third-party deps (chemprop, torch, mlflow, bentoml, tdc, rdkit) are
LAZY-IMPORTED and guarded, so the pure-Python config/orchestration layer and
its unit tests run without any of them installed.
"""

from .config import TrainingConfig, DatasetSpec, Hyperparams  # noqa: F401

__all__ = ["TrainingConfig", "DatasetSpec", "Hyperparams"]
