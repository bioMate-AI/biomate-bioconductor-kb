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
# protein_diffusion (RFdiffusion/Chroma/Genie) needs the SE(3)-transformer
# torch-cuda stack (dgl/e3nn/hydra) which conflicts with both Ludwig and TRL
# pins, so it ships in its own diffusion-training image.
_DEFAULT_DIFFUSION_IMAGE = "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/diffusion-training:latest"
# scrna_diffusion ships in its own GPU image (torch-cuda + scDiffusion/CFGen +
# scanpy/anndata), separate from the protein diffusion (SE(3)) image.
_DEFAULT_SC_DIFFUSION_IMAGE = "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/sc-diffusion-training:latest"
# tabular_diffusion ships in its own GPU image (torch-cuda + TabDDPM/TabSyn +
# pandas), separate from the single-cell and protein diffusion images.
_DEFAULT_TABULAR_DIFFUSION_IMAGE = "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/tabular-diffusion-training:latest"


def resolve_ml_training_container(model_type: str = "", nextflow_path: str = "") -> str:
    """Pick the ECR image for an ml_training run from model_type and/or .nf path.

    Single source of truth for executor_payload, Models-panel plan, and the
    nextflow_executor fallback (chat Confirm & Run often omits compute_config.container).
    Path heuristics cover diffusion wrappers when model_type is missing from params.
    """
    mt = (model_type or "").strip()
    nf = (nextflow_path or "").replace("\\", "/")
    from .config import TRL_MODEL_TYPES
    if mt == "protein_diffusion" or (
        "ml_training/diffusion_train.nf" in nf and "scrna_diffusion" not in nf
    ):
        return os.environ.get("DIFFUSION_TRAINING_IMAGE", _DEFAULT_DIFFUSION_IMAGE)
    if mt == "scrna_diffusion" or "ml_training/scrna_diffusion_train.nf" in nf:
        return os.environ.get("SC_DIFFUSION_TRAINING_IMAGE", _DEFAULT_SC_DIFFUSION_IMAGE)
    if mt == "tabular_diffusion" or "ml_training/tabular_diffusion_train.nf" in nf:
        return os.environ.get("TABULAR_DIFFUSION_TRAINING_IMAGE", _DEFAULT_TABULAR_DIFFUSION_IMAGE)
    if mt in TRL_MODEL_TYPES:
        return os.environ.get("TRL_TRAINING_IMAGE", _DEFAULT_TRL_IMAGE)
    if mt == "chemprop_gnn":
        return os.environ.get("ML_TRAINING_GPU_IMAGE") \
            or os.environ.get("ML_TRAINING_IMAGE", _DEFAULT_CPU_IMAGE)
    return os.environ.get("ML_TRAINING_IMAGE", _DEFAULT_CPU_IMAGE)


def _resolve_container(cfg: TrainingConfig) -> str:
    return resolve_ml_training_container(cfg.model_type)


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


def training_launch_parameters(cfg: TrainingConfig, s3_dataset_uri: Optional[str] = None, *,
                               allow_unresolved_dataset: bool = False) -> dict[str, Any]:
    """One selected-config parameter map for workflow cards and executor launch.

    Cards can show an unresolved required dataset; execution still validates it.
    """
    hp = cfg.hyperparams
    parameters: dict[str, Any] = {
        "dataset": ((s3_dataset_uri or cfg.dataset.s3_uri or cfg.dataset.name or cfg.dataset.path or "")
                    if allow_unresolved_dataset else resolve_dataset_param(cfg, s3_dataset_uri)),
        "smiles_col": cfg.dataset.smiles_col,
        "target_col": cfg.dataset.target_col,
        "split": cfg.dataset.split,
        "cv_folds": cfg.dataset.cv_folds,
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
        "gate_threshold": cfg.gate_threshold,
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
    # Structure-diffusion params (protein_diffusion) — passed to the CLI, ignored
    # otherwise. Flat scalars (executor serializes dict/list as JSON; we avoid it).
    diff = cfg.diffusion
    parameters.update({
        "framework": diff.framework if diff else "rfdiffusion",
        "base_checkpoint": diff.base_checkpoint if diff else "",
        "finetune": diff.finetune if diff else True,
        "target_pdb": diff.target_pdb if diff else "",
        "hotspot_residues": diff.hotspot_residues if diff else "",
        "motif_pdb": diff.motif_pdb if diff else "",
        "contig": diff.contig if diff else "",
        "length_min": diff.length_min if diff else 60,
        "length_max": diff.length_max if diff else 100,
        "num_designs": diff.num_designs if diff else 8,
        "diffusion_steps": diff.diffusion_steps if diff else 50,
        "noise_schedule": diff.noise_schedule if diff else "linear",
    })
    # Single-cell diffusion params (scrna_diffusion) — passed to the CLI with an
    # `sc_` prefix so they never collide with the llm base_model / protein
    # diffusion_steps/noise_schedule above; ignored by other model types. Flat
    # scalars only (executor JSON-serializes lists/dicts — CLAUDE.md).
    sc = cfg.sc
    parameters.update({
        "sc_framework": sc.framework if sc else "scdiffusion",
        "sc_base_checkpoint": sc.base_checkpoint if sc else "",
        "sc_base_model": sc.base_model if sc else "",
        "sc_finetune": sc.finetune if sc else True,
        "sc_cell_type": sc.cell_type if sc else "",
        "sc_condition_label": sc.condition_label if sc else "",
        "sc_n_cells_to_generate": sc.n_cells_to_generate if sc else 1000,
        "sc_n_genes": sc.n_genes if sc else 0,
        "sc_guidance_scale": sc.guidance_scale if sc else 1.0,
        "sc_diffusion_steps": sc.diffusion_steps if sc else 1000,
        "sc_noise_schedule": sc.noise_schedule if sc else "cosine",
    })
    # Generic tabular diffusion params (tabular_diffusion) — passed to the CLI with
    # a `tab_` prefix so they never collide with the sc_/protein framework,
    # diffusion_steps/noise_schedule above; ignored by other model types. Flat
    # scalars only (executor JSON-serializes lists/dicts — CLAUDE.md).
    tab = cfg.tabular
    parameters.update({
        "tab_framework": tab.framework if tab else "tabddpm",
        "tab_base_checkpoint": tab.base_checkpoint if tab else "",
        "tab_finetune": tab.finetune if tab else True,
        "tab_target_column": tab.target_column if tab else "",
        "tab_n_rows_to_generate": tab.n_rows_to_generate if tab else 1000,
        "tab_guidance_scale": tab.guidance_scale if tab else 1.0,
        "tab_diffusion_steps": tab.diffusion_steps if tab else 1000,
        "tab_noise_schedule": tab.noise_schedule if tab else "cosine",
    })

    return parameters


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
    parameters = training_launch_parameters(cfg, s3_dataset_uri)

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
