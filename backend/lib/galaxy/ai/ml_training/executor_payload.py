"""
Bridge: TrainingConfig → `/api/nextflow/execute` request payload.

Turns a declarative TrainingConfig into the exact dict the existing Nextflow
executor accepts (`NextflowExecuteRequest`), so a training run is submitted
through the SAME code path as every other workflow — AWS Batch, RunStateStore
persistence, SSE status, billing — with zero new execution machinery.

GPU selection is NOT set here: the training process in the `.nf` wrapper carries
`label 'process_gpu'`, which the executor routes to the GPU Batch queue
(nextflow_executor.py:2388). The payload only picks the awsbatch executor.

All params are scalars — deliberately: the executor serializes list/dict params
as JSON (CLAUDE.md root-cause note), but a training run needs none, so we keep
the param map flat and unambiguous.
"""
from __future__ import annotations

import os
from typing import Any, Optional

from .config import TrainingConfig

DEFAULT_NEXTFLOW_PATH = "ml_training/chemprop_train.nf"

# ECR images that carry the training CLI + framework deps. Overridable by env so
# ops can repoint them without a code change. The CPU image (Ludwig/sklearn +
# RDKit + PyTDC + the ml_training package) is built by ml-training-image.yml; the
# GPU image (adds chemprop/torch-cuda) is a later step.
_DEFAULT_CPU_IMAGE = "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ml-training:latest"
# TRL (DPO/GRPO) needs newer torch/transformers/pyarrow that conflict with
# Ludwig's pins, so it ships in a separate image.
_DEFAULT_TRL_IMAGE = "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/trl-training:latest"


def _resolve_container(cfg: TrainingConfig) -> str:
    from .config import TRL_MODEL_TYPES
    if cfg.model_type in TRL_MODEL_TYPES:
        return os.environ.get("TRL_TRAINING_IMAGE", _DEFAULT_TRL_IMAGE)
    if cfg.model_type == "chemprop_gnn":
        return os.environ.get("ML_TRAINING_GPU_IMAGE") \
            or os.environ.get("ML_TRAINING_IMAGE", _DEFAULT_CPU_IMAGE)
    return os.environ.get("ML_TRAINING_IMAGE", _DEFAULT_CPU_IMAGE)


def resolve_dataset_param(cfg: TrainingConfig, s3_dataset_uri: Optional[str] = None) -> str:
    """The single string the wrapper receives as --dataset.

    Prefers an explicit staged S3 URI (production), then the spec's own
    s3_uri / name / path. Batch workers cannot see local paths, so callers
    should stage local/named datasets to S3 and pass s3_dataset_uri.
    """
    ds = cfg.dataset
    value = s3_dataset_uri or ds.s3_uri or ds.name or ds.path
    if not value:
        raise ValueError("no dataset source resolvable for execution payload")
    return str(value)


def build_execute_request(
    cfg: TrainingConfig,
    *,
    user_id: str,
    nextflow_path: str = DEFAULT_NEXTFLOW_PATH,
    s3_dataset_uri: Optional[str] = None,
    aws_batch_queue: Optional[str] = None,
    is_pilot: bool = False,
) -> dict[str, Any]:
    """Build a NextflowExecuteRequest-compatible dict for POST /api/nextflow/execute."""
    cfg.validate()
    hp = cfg.hyperparams
    parameters: dict[str, Any] = {
        "dataset": resolve_dataset_param(cfg, s3_dataset_uri),
        "smiles_col": cfg.dataset.smiles_col,
        "target_col": cfg.dataset.target_col,
        "split": cfg.dataset.split,
        "val_frac": cfg.dataset.val_frac,
        "test_frac": cfg.dataset.test_frac,
        "model_type": cfg.model_type,
        "task_type": cfg.task_type,
        "featurizer": cfg.featurizer,
        "epochs": hp.epochs,
        "batch_size": hp.batch_size,
        "depth": hp.depth,
        "hidden_size": hp.hidden_size,
        "dropout": hp.dropout,
        "learning_rate": hp.learning_rate,
        "ensemble_size": hp.ensemble_size,
        "seed": hp.seed,
        "metric": cfg.metric,
        "model_name": cfg.name,
        "campaign_id": cfg.campaign_id,
        "mlflow_experiment": cfg.mlflow_experiment,
    }
    # LLM fine-tuning params (ludwig_llm) — passed to the CLI, ignored otherwise.
    llm = cfg.llm
    parameters.update({
        "base_model": llm.base_model if llm else "",
        "instruction_col": llm.instruction_col if llm else "instruction",
        "output_col": llm.output_col if llm else "output",
        "adapter": llm.adapter if llm else "qlora",
        "max_sequence_length": llm.max_sequence_length if llm else 256,
        # Preference optimization (trl_dpo) / RL (trl_grpo) params.
        "beta": llm.beta if llm else 0.1,
        "num_generations": llm.num_generations if llm else 4,
        "reward": llm.reward if llm else "length",
        "reward_keyword": llm.reward_keyword if llm else "",
    })

    compute_config: dict[str, Any] = {
        "executor": "awsbatch",
        # The executor injects this as the Nextflow process container, so the
        # TRAIN process runs in the image that has the training CLI + deps.
        "container": _resolve_container(cfg),
    }
    if aws_batch_queue:
        compute_config["aws_batch_queue"] = aws_batch_queue

    # A configured metric gate rides through as a qc_override so the executor's
    # QC-gate/auto-loop path can halt registration on a bad model (design §4.3).
    qc_overrides: dict[str, Any] = {}
    if cfg.gate_threshold is not None:
        qc_overrides["ml_gate"] = {"metric": cfg.metric, "threshold": cfg.gate_threshold}

    request: dict[str, Any] = {
        "nextflow_path": nextflow_path,
        "parameters": parameters,
        "compute_config": compute_config,
        "workflow_domain": "ml_training",
        "user_id": user_id,
        "is_pilot": is_pilot,
    }
    if qc_overrides:
        request["qc_overrides"] = qc_overrides
    return request
