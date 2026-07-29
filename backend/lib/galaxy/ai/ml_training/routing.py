"""
Intent → ml_training workflow routing (rule-first, LLM-fallback).

Detects when a chat request is asking to TRAIN a molecular model and turns it
into a `workflow_ga` (via TrainingConfig) that the existing workflow panel
renders — the seam for design-doc §5 / runbook Step 6.

Per CLAUDE.md "hybrid rule + LLM" extraction discipline: deterministic rules
handle intent detection, task-type mapping, and canonical dataset aliasing
(exact, zero-cost, testable). An optional `llm_fill` callback is the fallback
for free-text the rules can't resolve (model name, ambiguous targets) — the
rules always run first and the LLM only fills gaps.

This module is intentionally standalone (no ai_assistant import) so it is
unit-testable without the heavy galaxy.ai stack. Wiring it into the router is
a reviewed one-line hook (see runbook Step 6), NOT an edit here.
"""
from __future__ import annotations

import os
import re
from typing import Any, Callable, Optional

from .config import TrainingConfig, DatasetSpec, Hyperparams

# Verbs/objects that signal a *training* request (vs. "predict"/"screen" which
# route to inference on an existing model).
_TRAIN_VERBS = r"(train|build|fit|re-?train|fine-?tune|instruction[- ]?tune)"
_MODEL_NOUNS = r"(model|classifier|regressor|predictor|qsar|gnn|network|llm|language\s*model)"
_TRAIN_RE = re.compile(rf"\b{_TRAIN_VERBS}\b.*\b{_MODEL_NOUNS}\b", re.I | re.S)

# Explicit LLM fine-tuning signals → route to ludwig_llm (text-generation).
_LLM_HINTS = re.compile(
    r"\b(llm|large\s*language\s*model|language\s*model|instruction[- ]?tun\w*|"
    r"chat\s*model|fine-?tune\w*\s+(a|an|the)?\s*(llm|language|gpt|chat)|"
    r"gpt|smol\w*|llama|mistral|qwen|phi-?\d|dpo|grpo|rlhf|"
    r"preference\s*(optim\w*|tun\w*|data)|reinforcement\s*learning|reward\s*model)\b",
    re.I)
# Preference-optimization (DPO) vs. RL (GRPO) sub-intents within the LLM branch.
_DPO_HINTS = re.compile(
    r"\b(dpo|direct\s*preference|preference\s*(optim\w*|tun\w*|pair|data)|"
    r"chosen[/ ]?rejected|rlhf(?!.*grpo))\b", re.I)
_GRPO_HINTS = re.compile(
    r"\b(grpo|group\s*relative|reinforcement\s*learning|reward\s*(function|model|signal)|"
    r"\brl\b\s*fine)\b", re.I)

# Canonical public-dataset aliases (TDC single-pred names). Extend as needed.
# key = lowercase phrase found in the request → (tdc_name, task_type, target_col)
_DATASET_ALIASES: dict[str, tuple[str, str, str]] = {
    "herg":  ("hERG", "classification", "Y"),
    "bbb":   ("BBB_Martins", "classification", "Y"),
    "blood-brain": ("BBB_Martins", "classification", "Y"),
    "ames":  ("AMES", "classification", "Y"),
    "cyp2d6": ("CYP2D6_Veith", "classification", "Y"),
    "cyp3a4": ("CYP3A4_Veith", "classification", "Y"),
    "caco2": ("Caco2_Wang", "regression", "Y"),
    "lipophilicity": ("Lipophilicity_AstraZeneca", "regression", "Y"),
    "solubility": ("Solubility_AqSolDB", "regression", "Y"),
    "ppbr":  ("PPBR_AZ", "regression", "Y"),
}

# Words that flip the default to a regression task when no dataset alias decides.
_REGRESSION_HINTS = re.compile(r"\b(ic50|ec50|value|potency|affinity|continuous|regress)\b", re.I)
# Words that ask for a cheap non-GNN baseline.
_BASELINE_HINTS = re.compile(r"\b(baseline|quick|fast|sklearn|gradient boost|simple)\b", re.I)


def detect_training_intent(text: str) -> bool:
    """True when the text asks to train/build a model (rule-based)."""
    if not text:
        return False
    return bool(_TRAIN_RE.search(text))


def _match_dataset(text: str) -> Optional[tuple[str, str, str]]:
    low = text.lower()
    for phrase, spec in _DATASET_ALIASES.items():
        if phrase in low:
            return spec
    return None


def extract_training_config(
    text: str,
    *,
    default_name: Optional[str] = None,
    dataset_s3_uri: Optional[str] = None,
    llm_fill: Optional[Callable[[str], dict[str, Any]]] = None,
) -> TrainingConfig:
    """Rule-first extraction of a TrainingConfig from a free-text request.

    dataset resolution order: explicit user-provided S3 data → recognised public
    alias → (gap) LLM fallback. Task/model type inferred by rules.
    """
    # LLM fine-tuning branch — explicit LLM signal → ludwig_llm SFT, or a TRL
    # preference/RL method (DPO/GRPO) when the request names one.
    if _LLM_HINTS.search(text):
        from .config import LLMSpec
        if _GRPO_HINTS.search(text):
            model_type, default_ds, name = "trl_grpo", "fixture:prompts", "GRPO-tuned LLM"
        elif _DPO_HINTS.search(text):
            model_type, default_ds, name = "trl_dpo", "fixture:preference", "DPO-tuned LLM"
        else:
            model_type, default_ds, name = "ludwig_llm", "fixture:instruct", "instruction-tuned LLM"
        # data: user S3 → else the tiny offline fixture (card is editable so the
        # user points at their JSONL / hf:<dataset>).
        if dataset_s3_uri:
            dataset = DatasetSpec(s3_uri=dataset_s3_uri, split="random")
        else:
            dataset = DatasetSpec(name=default_ds, split="random")
        return TrainingConfig(
            name=default_name or name, task_type="text_generation", model_type=model_type,
            dataset=dataset, hyperparams=Hyperparams(epochs=3, learning_rate=1e-4),
            metric="loss", llm=LLMSpec(),
        ).validate()

    alias = _match_dataset(text)

    # task type: alias decides; else regression hint; else classification
    if alias:
        task_type = alias[1]
    elif _REGRESSION_HINTS.search(text):
        task_type = "regression"
    else:
        task_type = "classification"

    # Default DL model = ludwig_tabular: the CPU-runnable low-code DL path that
    # is implemented + validated today. chemprop_gnn is GPU-only and still a
    # stub, so it is opt-in via an explicit "chemprop"/"graph"/"gnn" mention.
    if _BASELINE_HINTS.search(text):
        model_type = "sklearn_gbr"
    elif re.search(r"\b(chemprop|graph\s*neural|gnn|message[- ]passing)\b", text, re.I):
        model_type = "chemprop_gnn"
    else:
        model_type = "ludwig_tabular"
    metric = "auc" if task_type == "classification" else "mae"

    # dataset spec
    if dataset_s3_uri:
        target = alias[2] if alias else "y"
        dataset = DatasetSpec(s3_uri=dataset_s3_uri, target_col=target)
    elif alias:
        dataset = DatasetSpec(name=f"tdc:{alias[0]}", target_col=alias[2])
    else:
        # No data + no recognised alias → LLM fallback for the dataset (gap only).
        filled = llm_fill(text) if llm_fill else {}
        ds_name = filled.get("dataset")
        if not ds_name:
            raise ValueError(
                "could not resolve a dataset from the request; provide data "
                "(S3) or name a known assay (e.g. hERG, BBB, Caco2)."
            )
        dataset = DatasetSpec(name=ds_name, target_col=filled.get("target_col", "y"))
        task_type = filled.get("task_type", task_type)

    name = default_name or _derive_name(text, alias)
    return TrainingConfig(
        name=name, task_type=task_type, model_type=model_type,
        dataset=dataset, hyperparams=Hyperparams(), metric=metric,
    ).validate()


def route_ml_training(
    text: str,
    *,
    dataset_s3_uri: Optional[str] = None,
    llm_fill: Optional[Callable[[str], dict[str, Any]]] = None,
) -> Optional[dict[str, Any]]:
    """Router hook: return a workflow_ga for a training request, else None.

    Returning None means "not a training intent — fall through to the normal
    workflow search". This is what the reviewed ai_assistant hook calls.
    """
    if not detect_training_intent(text):
        return None
    try:
        cfg = extract_training_config(text, dataset_s3_uri=dataset_s3_uri, llm_fill=llm_fill)
    except ValueError:
        return None  # ambiguous → let the normal router try
    ga = cfg.to_workflow_ga()
    ga["scientific_rationale"] = (
        f"Detected a model-training request; routing to the ml_training pipeline "
        f"({cfg.model_type}, {cfg.task_type}) on dataset "
        f"{cfg.dataset.name or cfg.dataset.s3_uri}."
    )
    return ga


def route_ml_training_result(
    text: str,
    *,
    enabled: Optional[bool] = None,
    dataset_s3_uri: Optional[str] = None,
    llm_fill: Optional[Callable[[str], dict[str, Any]]] = None,
) -> Optional[dict[str, Any]]:
    """Feature-flagged router entry used by ai_assistant.generate_workflow_unified.

    Returns a full generate_workflow_unified-shaped result dict when the flag is
    on AND the text is a resolvable training request; otherwise None (→ caller
    falls through to normal workflow search). `enabled=None` reads the
    ML_TRAINING_ROUTING env flag (default OFF), so wiring this in is inert until
    explicitly turned on.
    """
    if enabled is None:
        enabled = os.environ.get("ML_TRAINING_ROUTING") == "1"
    if not enabled:
        return None
    ga = route_ml_training(text, dataset_s3_uri=dataset_s3_uri, llm_fill=llm_fill)
    if ga is None:
        return None
    return {
        "success": True,
        "workflow_ga": ga,
        "source": "ml_training",
        "confidence": 1.0,
        "message": ga.get("scientific_rationale", "Model training workflow"),
        "datasets_assigned": False,
    }


def _derive_name(text: str, alias: Optional[tuple[str, str, str]]) -> str:
    if alias:
        kind = "classifier" if alias[1] == "classification" else "regressor"
        return f"{alias[0]} {kind}"
    return "molecular model"
