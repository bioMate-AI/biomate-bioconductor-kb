"""
Structured training plan — the Models-panel launch path.

The chat path re-extracts a TrainingConfig from prose (lossy, flag-gated). The
Models panel already HAS every field structurally (dataset file, target column,
model type, metric, gate), so it calls this instead:

    build_training_plan(request) -> {workflow_ga, nextflow_path, compute_config, config}

The result is the exact workflow_ga the chat path would render, with the
dataset bound to a staged s3:// URI, the Nextflow wrapper chosen by
``routing.nextflow_path_for`` and the container chosen by
``executor_payload._resolve_container`` (the single source of truth for which
image runs which model type). Node then submits it through the ordinary
POST /api/workflows/execute path so the run gets a run record, SSE status,
billing and Run Manager visibility — no separate execution machinery.

Every rejection is a ConfigError whose message is shown to the user verbatim.
Pure module: no FastAPI / network, unit-testable offline.
"""
from __future__ import annotations

import math
from typing import Any, Callable, Optional

from .config import (
    ConfigError, DatasetSpec, DiffusionSpec, Hyperparams, LLMSpec, SCDiffusionSpec,
    TrainingConfig, LLM_MODEL_TYPES,
)
from .executor_payload import _resolve_container
from .routing import nextflow_path_for

# Supervised learners over a labelled table. featurizer="none" = generic table
# (no SMILES); "rdkit_2d" = molecular descriptors computed from a SMILES column.
SUPERVISED_TYPES = ("sklearn_tabular", "ludwig_tabular", "sklearn_gbr")
GENERATIVE_TYPES = LLM_MODEL_TYPES + ("scrna_diffusion", "protein_diffusion")
PLANNABLE_TYPES = SUPERVISED_TYPES + GENERATIVE_TYPES

# Model types the config knows but the panel cannot launch, with the honest reason.
UNAVAILABLE_TYPES = {
    "chemprop_gnn": "chemprop_gnn has no training loop yet; use ludwig_tabular "
                    "(featurizer=rdkit_2d) or sklearn_gbr for molecular models.",
    "tabular_diffusion": "tabular_diffusion has no Nextflow wrapper that forwards its "
                         "parameters yet, so it cannot be launched.",
}

# Metrics each learner actually emits (see tabular_trainer._score,
# ludwig_trainer._extract_metrics, chemprop_trainer._train_sklearn). Offering a
# metric the trainer never reports would make a configured gate fail closed.
_SUPERVISED_METRICS: dict[tuple[str, str, str], tuple[str, ...]] = {
    ("sklearn_tabular", "none", "classification"): ("accuracy", "macro_f1", "auc"),
    ("sklearn_tabular", "none", "regression"): ("r2", "mae"),
    ("ludwig_tabular", "none", "classification"): ("accuracy",),
    ("ludwig_tabular", "none", "regression"): ("mae",),
    ("ludwig_tabular", "rdkit_2d", "classification"): ("auc", "accuracy"),
    ("ludwig_tabular", "rdkit_2d", "regression"): ("mae",),
    ("sklearn_gbr", "rdkit_2d", "classification"): ("auc",),
    ("sklearn_gbr", "rdkit_2d", "regression"): ("mae",),
}
# Generative / LLM types report one fixed primary metric.
_GENERATIVE_METRIC = {
    "ludwig_llm": "loss", "trl_dpo": "train_loss", "trl_grpo": "train_loss",
    "scrna_diffusion": "marker_fidelity_frac", "protein_diffusion": "scrmsd",
}
_GENERATIVE_TASK = {
    "ludwig_llm": "text_generation", "trl_dpo": "text_generation", "trl_grpo": "text_generation",
    "scrna_diffusion": "expression_generation", "protein_diffusion": "structure_generation",
}


def supported_metrics(model_type: str, featurizer: str, task_type: str) -> tuple[str, ...]:
    if model_type in _GENERATIVE_METRIC:
        return (_GENERATIVE_METRIC[model_type],)
    return _SUPERVISED_METRICS.get((model_type, featurizer, task_type), ())


def _text(req: dict, key: str) -> str:
    v = req.get(key)
    return v.strip() if isinstance(v, str) else ""


def _number(req: dict, key: str, kind=float) -> Optional[Any]:
    v = req.get(key)
    if v is None or (isinstance(v, str) and not v.strip()):
        return None
    try:
        n = kind(v)
    except (TypeError, ValueError):
        raise ConfigError(f"{key} must be a number, got {v!r}")
    if isinstance(n, float) and not math.isfinite(n):
        raise ConfigError(f"{key} must be finite, got {v!r}")
    return n


def _spec(cls, raw: Any, allowed_name: str):
    if raw is None:
        return cls()
    if not isinstance(raw, dict):
        raise ConfigError(f"{allowed_name} must be an object")
    fields = set(cls.__dataclass_fields__)
    unknown = sorted(set(raw) - fields)
    if unknown:
        raise ConfigError(f"unknown {allowed_name} field(s): {', '.join(unknown)}")
    return cls(**raw)


def build_training_config(req: dict) -> TrainingConfig:
    """Map a structured panel request to a validated TrainingConfig."""
    if not isinstance(req, dict):
        raise ConfigError("request body must be an object")
    model_type = _text(req, "model_type")
    if model_type in UNAVAILABLE_TYPES:
        raise ConfigError(UNAVAILABLE_TYPES[model_type])
    if model_type not in PLANNABLE_TYPES:
        raise ConfigError(f"model_type must be one of {PLANNABLE_TYPES}")
    s3_uri = _text(req, "dataset_s3_uri")
    if not s3_uri.startswith("s3://") or len(s3_uri) <= len("s3://"):
        raise ConfigError("dataset_s3_uri must be an s3:// URI of a project file")
    dataset_name = _text(req, "dataset_name") or s3_uri.rsplit("/", 1)[-1]
    # When set, this run adapts an existing registered model: its artifact registers
    # as that model's NEXT VERSION (lineage) rather than a fresh model. Applies to any
    # model_type; the registration step resolves the base and stamps priorVersions.
    adapt_of = _text(req, "adapt_of") or None

    hp = Hyperparams()
    epochs = _number(req, "epochs", int)
    lr = _number(req, "learning_rate", float)
    gate = _number(req, "gate_threshold", float)

    if model_type in SUPERVISED_TYPES:
        target = _text(req, "target_col")
        if not target:
            raise ConfigError("target_col is required: choose the column to predict")
        task_type = _text(req, "task_type")
        if task_type not in ("classification", "regression"):
            raise ConfigError("task_type must be classification or regression")
        if model_type == "sklearn_tabular":
            featurizer = "none"
        elif model_type == "sklearn_gbr":
            featurizer = "rdkit_2d"
        else:
            featurizer = _text(req, "featurizer") or "none"
            if featurizer not in ("none", "rdkit_2d"):
                raise ConfigError("featurizer for ludwig_tabular must be none or rdkit_2d")
        smiles_col = _text(req, "smiles_col")
        if featurizer == "rdkit_2d":
            if not smiles_col:
                raise ConfigError(f"{model_type} with molecular features needs smiles_col "
                                  "(the column holding SMILES strings)")
            if smiles_col == target:
                raise ConfigError("smiles_col and target_col must be different columns")
            split = "scaffold"
        else:
            smiles_col = smiles_col or "smiles"   # unused by generic learners
            split = "kfold" if model_type == "sklearn_tabular" else "random"
        allowed = supported_metrics(model_type, featurizer, task_type)
        metric = _text(req, "metric") or allowed[0]
        if metric not in allowed:
            raise ConfigError(f"metric for {model_type} {task_type} must be one of {allowed}")
        if epochs is not None:
            hp.epochs = epochs
        if lr is not None:
            hp.learning_rate = lr
        dataset = DatasetSpec(s3_uri=s3_uri, smiles_col=smiles_col, target_col=target,
                              split=split, cv_folds=5)
        name = _text(req, "model_name") or f"{target} {task_type} model"
        return TrainingConfig(
            name=name, task_type=task_type, model_type=model_type, featurizer=featurizer,
            dataset=dataset, hyperparams=hp, metric=metric, gate_threshold=gate,
            adapt_of=adapt_of,
        ).validate()

    # Generative / LLM families.
    task_type = _GENERATIVE_TASK[model_type]
    metric = _GENERATIVE_METRIC[model_type]
    defaults = {"ludwig_llm": (3, 1e-4), "trl_dpo": (3, 1e-4), "trl_grpo": (3, 1e-4),
                "scrna_diffusion": (50, 1e-4), "protein_diffusion": (5, 1e-4)}[model_type]
    hp.epochs = epochs if epochs is not None else defaults[0]
    hp.learning_rate = lr if lr is not None else defaults[1]
    llm = diffusion = sc = None
    if model_type in LLM_MODEL_TYPES:
        llm = _spec(LLMSpec, req.get("llm"), "llm")
        if llm.reward == "composite":
            raise ConfigError("a composite GRPO reward needs a reward_spec; choose a built-in "
                              "reward (length / keyword / numeric_answer)")
    elif model_type == "scrna_diffusion":
        sc = _spec(SCDiffusionSpec, req.get("sc"), "sc")
    else:
        diffusion = _spec(DiffusionSpec, req.get("diffusion"), "diffusion")
    name = _text(req, "model_name") or f"{model_type} · {dataset_name}"
    return TrainingConfig(
        name=name, task_type=task_type, model_type=model_type, featurizer="none",
        dataset=DatasetSpec(s3_uri=s3_uri, split="random"), hyperparams=hp,
        metric=metric, gate_threshold=gate, llm=llm, diffusion=diffusion, sc=sc,
        adapt_of=adapt_of,
    ).validate()


# Fewest rows any training split can work with. k-fold needs at least two rows
# per fold on top of that. Below this the Batch job can only fail (dev run
# c0d27792: a 1-row DESeq2 contrasts.csv → "cannot make 5 folds from 1 rows").
MIN_TRAIN_ROWS = 10


def required_rows(cfg: TrainingConfig) -> int:
    if cfg.dataset.split == "kfold":
        return max(MIN_TRAIN_ROWS, 2 * int(cfg.dataset.cv_folds or 0))
    return MIN_TRAIN_ROWS


def check_dataset_rows(cfg: TrainingConfig, rows: Optional[int]) -> None:
    """Refuse a dataset too small to train on before a Batch job is spent on it.
    `rows=None` (row count unknown) is not a refusal: the training job reports it.
    The message starts with a stable code the panel localises."""
    if rows is None:
        return
    need = required_rows(cfg)
    if rows < need:
        raise ConfigError(
            f"dataset_too_small:{rows}:{need}: the dataset has {rows} row(s); training needs "
            f"at least {need} (one row per sample, with feature columns and the target column)")


def build_training_plan(req: dict, rows_of: Optional[Callable[[str], Optional[int]]] = None) -> dict[str, Any]:
    """Validated config → the workflow_ga + compute config Node submits to /api/workflows/execute.

    `rows_of(s3_uri)` returns the dataset's row count (None when it cannot be read);
    the endpoint wires it to the perception profiler."""
    cfg = build_training_config(req)
    if rows_of is not None and cfg.dataset.s3_uri:
        check_dataset_rows(cfg, rows_of(cfg.dataset.s3_uri))
    nf_path = nextflow_path_for(cfg.model_type)
    ga = cfg.to_workflow_ga(nextflow_path=nf_path)
    dataset_name = _text(req, "dataset_name") or (cfg.dataset.s3_uri or "").rsplit("/", 1)[-1]
    ga["source_dataset_name"] = dataset_name
    ga["featurizer"] = cfg.featurizer
    return {
        "workflow_ga": ga,
        "nextflow_path": nf_path,
        # Surfaced top-level so Node tags the run (workflow_type) and registration
        # versions the base model without re-parsing the ga. None ⇒ ordinary training.
        "adapt_of": cfg.adapt_of,
        "workflow_type": "adaptation" if cfg.adapt_of else "training",
        # The container is chosen here (per model type) and forwarded as
        # executionConfig.computeConfig.container; the executor's path-based
        # fallback cannot tell the diffusion images apart.
        "compute_config": {"container": _resolve_container(cfg)},
        "config": cfg.to_dict(),
    }
