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
_MODEL_NOUNS = r"(model|classifier|regressor|predictor|qsar|gnn|network|llm|language\s*model|diffusion)"
_TRAIN_RE = re.compile(rf"\b{_TRAIN_VERBS}\b.*\b{_MODEL_NOUNS}\b", re.I | re.S)

# Protein/peptide structure-diffusion signals → route to protein_diffusion
# (structure_generation). These fire the training intent on their own (a "design
# a de novo binder" request has no explicit "train … model" phrasing), and select
# the diffusion branch below.
_DIFFUSION_HINTS = re.compile(
    r"\b(rf-?diffusion|protein\s*(backbone|diffusion|structure\s*diffusion)|"
    r"peptide\s*(scaffold|backbone|structure|diffusion|design)|"
    r"(de[-\s]?novo)\s*(protein|peptide|binder|backbone)|"
    r"binder\s*design|design\s+(a\s+|an\s+|de[-\s]?novo\s+)?binder\w*|"
    r"backbone\s*(generation|design)|scaffold\w*\s*(a\s*)?motif|"
    r"motif\s*scaffold\w*|structure\s*(generation|diffusion)|"
    r"hotspot\s*residues?|protein\s*design|chroma|genie)\b",
    re.I)

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

# Single-cell expression diffusion signals → route to scrna_diffusion
# (expression_generation). Also acts as a training-intent trigger on its own
# (e.g. "generate cells" / "augment single-cell data" have no "model" noun).
_SC_DIFFUSION_HINTS = re.compile(
    r"\b(sc[- ]?diffusion|scdiffusion|cfgen|"
    r"single[- ]?cell\s+diffusion|scrna\s+diffusion|"
    r"generate\s+(cells|single[- ]?cells)|synthes\w*\s+(cells|single[- ]?cells)|"
    r"augment(ing)?\s+(single[- ]?cell|scrna|sc[- ]?rna)\b\w*|"
    r"in[- ]?silico\s+perturbation.*diffusion|"
    r"diffusion\s+(model\s+)?(for|of|to\s+generate)\s+(cells|single[- ]?cell|scrna|expression))\b",
    re.I)
# CFGen is flow-matching, not diffusion; scDiffusion is the default.
_CFGEN_HINTS = re.compile(r"\bcfgen\b", re.I)

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

# Generic NON-MOLECULAR tabular signal: an expression-matrix / feature-table
# model (e.g. subtype prediction from gene expression), trained with k-fold CV.
# This is the general path; it must NOT hijack molecular requests, so the caller
# only consults it when no molecular dataset alias matched. English + Chinese.
_TABULAR_HINTS = re.compile(
    r"(expression\s*(matrix|data|profile)|gene\s*expression|feature\s*matrix|"
    r"\bsubtype\b|\btabular\b|\bomics\b|microarray|transcriptom\w*|rna[- ]?seq\s*matrix|"
    r"biomarker\s*panel|clinical\s*features?|"
    r"表达矩阵|基因表达|亚型|分型|预后分组|特征矩阵|组学数据|交叉验证)",
    re.I)
# Infer the label column name from the request (else a neutral default).
_TABULAR_TARGET = re.compile(
    r"\b(subtype|outcome|response|label|class|group|status|grade|stage|prognosis)\b", re.I)
_TABULAR_TARGET_ZH = {"亚型": "subtype", "分型": "subtype", "预后": "prognosis",
                      "响应": "response", "分组": "group", "分级": "grade", "分期": "stage"}


def _infer_tabular_target(text: str) -> str:
    m = _TABULAR_TARGET.search(text)
    if m:
        return m.group(1).lower()
    for zh, en in _TABULAR_TARGET_ZH.items():
        if zh in text:
            return en
    return "label"


def detect_training_intent(text: str) -> bool:
    """True when the text asks to train/build a model (rule-based).

    Includes structure-diffusion design requests ("design a de novo binder"),
    which don't use the "train … model" phrasing but are training/generation jobs.
    """
    if not text:
        return False
    # Single-cell diffusion phrasings ("generate cells", "augment single-cell
    # data") are training intents even without a "model" noun.
    return bool(_TRAIN_RE.search(text) or _DIFFUSION_HINTS.search(text)
                or _SC_DIFFUSION_HINTS.search(text))


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
    # Single-cell expression-diffusion branch — checked FIRST (more specific):
    # scDiffusion/CFGen generate/augment scRNA-seq cells. The card is editable so
    # the user points sc_base_model/sc_base_checkpoint at staged weights and the
    # dataset at their h5ad.
    if _SC_DIFFUSION_HINTS.search(text):
        from .config import SCDiffusionSpec
        framework = "cfgen" if _CFGEN_HINTS.search(text) else "scdiffusion"
        # fine-tune iff the request says so or names scDiffusion (ships a
        # pretrained SCimilarity/diffusion checkpoint); else train-from-scratch.
        wants_ft = bool(re.search(r"\bfine-?tune|pretrained|scdiffusion\b", text, re.I))
        if wants_ft:
            # a named default warm-start keeps validate() happy; card is editable.
            sc = SCDiffusionSpec(framework=framework, finetune=True,
                                 base_model="scdiffusion:pretrained")
        else:
            sc = SCDiffusionSpec(framework=framework, finetune=False)
        if dataset_s3_uri:
            dataset = DatasetSpec(s3_uri=dataset_s3_uri, split="random")
        else:
            dataset = DatasetSpec(name="fixture:pbmc_h5ad", split="random")
        return TrainingConfig(
            name=default_name or "single-cell diffusion generator",
            task_type="expression_generation", model_type="scrna_diffusion",
            dataset=dataset, hyperparams=Hyperparams(epochs=50, learning_rate=1e-4),
            metric="marker_fidelity_frac", higher_is_better=True, sc=sc,
        ).validate()

    # Structure-diffusion branch — protein/peptide backbone design/diffusion →
    # protein_diffusion (structure_generation). Checked BEFORE the LLM branch so a
    # "protein diffusion" request never gets mis-routed to an LLM. Rules-first,
    # mirroring the LLM branch: fine-tune vs. from-scratch, framework, and
    # hotspot/target conditioning are inferred deterministically from the text.
    if _DIFFUSION_HINTS.search(text):
        from .config import DiffusionSpec
        framework = ("chroma" if re.search(r"\bchroma\b", text, re.I)
                     else "genie" if re.search(r"\bgenie\b", text, re.I)
                     else "rfdiffusion")
        # from-scratch only when explicitly asked; default is fine-tune a checkpoint.
        finetune = not bool(re.search(r"\b(from[-\s]?scratch|de[-\s]?novo\s+train)\b", text, re.I))
        hotspots = _extract_hotspots(text)
        dataset = (DatasetSpec(s3_uri=dataset_s3_uri, split="random") if dataset_s3_uri
                   else DatasetSpec(name="fixture:structures", split="random"))
        diff = DiffusionSpec(framework=framework, finetune=finetune,
                             hotspot_residues=hotspots)
        return TrainingConfig(
            name=default_name or _derive_diffusion_name(text),
            task_type="structure_generation", model_type="protein_diffusion",
            dataset=dataset, hyperparams=Hyperparams(epochs=5, learning_rate=1e-4),
            metric="scrmsd", diffusion=diff,
        ).validate()

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

    # Generic TABULAR branch — a feature-matrix model (e.g. gene-expression →
    # subtype) with stratified k-fold CV. Fires only when no molecular dataset
    # alias matched, so it never hijacks a drug-discovery request.
    if alias is None and _TABULAR_HINTS.search(text):
        task_type = "regression" if _REGRESSION_HINTS.search(text) else "classification"
        target = _infer_tabular_target(text)
        if dataset_s3_uri:
            dataset = DatasetSpec(s3_uri=dataset_s3_uri, target_col=target,
                                  split="kfold", cv_folds=5)
        else:
            # No data yet — propose an editable card the user points at their matrix.
            dataset = DatasetSpec(path="EXPRESSION_MATRIX.csv", target_col=target,
                                  split="kfold", cv_folds=5)
        return TrainingConfig(
            name=default_name or f"{target} predictor", task_type=task_type,
            model_type="sklearn_tabular", featurizer="none", dataset=dataset,
            hyperparams=Hyperparams(),
            metric="accuracy" if task_type == "classification" else "mae",
        ).validate()

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
    # Each diffusion family runs in its own Nextflow wrapper (distinct GPU image);
    # other model types share the molecular wrapper (dispatch is by --model-type
    # in the CLI).
    if cfg.model_type == "protein_diffusion":
        nf_path = "ml_training/diffusion_train.nf"
    elif cfg.model_type == "scrna_diffusion":
        nf_path = "ml_training/scrna_diffusion_train.nf"
    else:
        nf_path = "ml_training/chemprop_train.nf"
    ga = cfg.to_workflow_ga(nextflow_path=nf_path)
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


# Chain-position residue tokens like "A30", "B12" (chain letter + number) — the
# RFdiffusion hotspot format. Also picks up a bare "residues 30,33,34" list which
# we default to chain A.
_HOTSPOT_TOK = re.compile(r"\b([A-Za-z])\s?(\d{1,4})\b")
_RESIDUES_PHRASE = re.compile(r"\bresidues?\s+([\d,\s]+)", re.I)
# A named target to design a binder against (e.g. "FcRn binders", "against PD-L1").
_TARGET_PHRASE = re.compile(
    r"\b(?:for|against|to|targeting)\s+([A-Z][A-Za-z0-9-]{1,15})\s*(?:binders?|target)?\b")


def _extract_hotspots(text: str) -> str:
    """Deterministically pull hotspot residues from the request → 'A30,A33'.

    Prefers explicit chain-residue tokens (A30); falls back to a 'residues 30,33'
    phrase (defaulting to chain A). Returns '' when none are stated (the card is
    editable so the user can add them)."""
    toks = [f"{c.upper()}{n}" for c, n in _HOTSPOT_TOK.findall(text)
            if c.upper() in "ABCDEFGH"]
    if toks:
        return ",".join(dict.fromkeys(toks))   # dedupe, keep order
    m = _RESIDUES_PHRASE.search(text)
    if m:
        nums = [n.strip() for n in m.group(1).split(",") if n.strip().isdigit()]
        return ",".join(f"A{n}" for n in nums)
    return ""


def _derive_diffusion_name(text: str) -> str:
    m = _TARGET_PHRASE.search(text)
    if m and m.group(1).lower() not in ("the", "a", "an", "my"):
        return f"{m.group(1)} binder design"
    if re.search(r"\bpeptide\b", text, re.I):
        return "peptide structure design"
    return "protein backbone design"
