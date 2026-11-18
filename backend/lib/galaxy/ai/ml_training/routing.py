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


# Measured LABEL columns a molecular training table carries, in the words a request uses for them.
# Ordered most-specific first ("pIC50" before "IC50"); the matched token is the column name, so the
# card shows the user's own column instead of a neutral "y" they would have to correct by hand.
_TARGET_COL_TOKENS = (
    "pic50", "pec50", "pki", "pkd", "pxc50",
    "ic50_nm", "ec50_nm", "ic50", "ec50", "ki", "kd",
    "logp", "logd", "logs", "solubility", "permeability", "clearance",
    "potency", "activity", "label",
)
# "train on <col>" / "using SMILES and <col>" style mentions are the reliable ones; a bare mention
# of the assay in prose is not (that is what the public-dataset aliases are for).
_TARGET_COL_RE = re.compile(
    r"\b(" + "|".join(_TARGET_COL_TOKENS) + r")\b", re.I)


def _infer_target_col(text: str) -> Optional[str]:
    """The label column a molecular training request names, in the request's own spelling.

    Rules-first (CLAUDE.md): a deterministic scan for known assay/endpoint column tokens, longest
    match first so "pIC50" never degrades to "IC50". Returns None when the request names none —
    the caller then falls back to the public-dataset alias column, else "y".
    """
    best: Optional[str] = None
    best_rank = len(_TARGET_COL_TOKENS)
    for m in _TARGET_COL_RE.finditer(text or ""):
        tok = m.group(1)
        rank = _TARGET_COL_TOKENS.index(tok.lower())
        if rank < best_rank:
            best, best_rank = tok, rank
    return best


# Extensions whose contents a training job can actually read (a training table / corpus). An
# attached FASTQ or BAM is NOT training data, so a "train a model" request with only raw reads
# attached still falls through to the normal workflow search instead of inventing a training job.
_TRAINING_DATA_EXTS = (
    ".csv", ".tsv", ".parquet", ".xlsx", ".jsonl", ".json", ".h5ad", ".smi", ".sdf", ".txt",
)


def select_training_dataset(datasets: Optional[Any]) -> Optional[str]:
    """The URI/path of the attached dataset a training job should train on, or None.

    ``datasets`` is the session-dataset list threaded into generate_workflow (dicts with
    name/s3_uri/path fields) — the SAME list routing already grounds input kinds in. First
    attachment with a readable training-data extension wins; ``.txt`` is accepted last so a
    gene-list sidecar never outranks a real table. NEVER raises: routing must not break on a
    malformed dataset entry.
    """
    best: Optional[str] = None
    best_rank = len(_TRAINING_DATA_EXTS)
    for ds in (datasets or []):
        try:
            if isinstance(ds, str):
                name, uri = ds, ds
            elif isinstance(ds, dict):
                name = str(ds.get("name") or ds.get("filename") or ds.get("s3_uri")
                           or ds.get("path") or ds.get("file_path") or "")
                uri = str(ds.get("s3_uri") or ds.get("s3Uri") or ds.get("uri")
                          or ds.get("path") or ds.get("file_path") or name)
            else:
                continue
            if not name or not uri:
                continue
            low = name.lower()
            for rank, ext in enumerate(_TRAINING_DATA_EXTS):
                if low.endswith(ext) and rank < best_rank:
                    best, best_rank = uri, rank
                    break
        except Exception:  # noqa: BLE001 — one bad entry must not drop the rest
            continue
    return best


def _infer_tabular_target(text: str) -> str:
    m = _TABULAR_TARGET.search(text)
    if m:
        return m.group(1).lower()
    for zh, en in _TABULAR_TARGET_ZH.items():
        if zh in text:
            return en
    return "label"


# Cold-start / chat scaffolding the UI appends after the user's real ask. These
# blocks often said "For protein backbone design / diffusion train set dataset=…"
# so a bare design prompt would otherwise re-arm training intent via the
# incidental "train" token (remeasure 2026-11-15: design-generate-bio-1/2).
_SCAFFOLD_BLOCKS_RE = re.compile(
    r"\[(?:Prepared inputs|Attached files|Uploaded datasets|Routing hint)[^\]]*\]",
    re.I | re.S,
)


def _intent_text(text: str) -> str:
    """User-authored ask only — drop UI scaffolding before intent detection."""
    if not text:
        return ""
    return _SCAFFOLD_BLOCKS_RE.sub(" ", text)


def detect_training_intent(text: str) -> bool:
    """True when the text asks to train/build a model (rule-based).

    Structure-diffusion *design* phrasings ("design a de novo binder", "peptide
    structure design") are NOT training intents on their own — those must fall
    through to the indexed design/fold workflows (antibody co-fold, cyclic
    peptide, ProteinMPNN, …). Only escalate to ml_training when a train/fine-tune
    verb co-occurs with a diffusion hint (coldstart 2026-11-14: bare design
    prompts were hijacked into TRAIN → NotImplementedError without the
    diffusion-training GPU image).

    UI `[Prepared inputs: …]` / `[Attached files: …]` blocks are stripped first so
    binding hints that mention "diffusion train" cannot re-arm this gate.
    """
    text = _intent_text(text)
    if not text:
        return False
    # Single-cell diffusion phrasings ("generate cells", "augment single-cell
    # data") are training intents even without a "model" noun.
    if _TRAIN_RE.search(text) or _SC_DIFFUSION_HINTS.search(text):
        return True
    if _DIFFUSION_HINTS.search(text) and re.search(rf"\b{_TRAIN_VERBS}\b", text, re.I):
        return True
    return False


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
        # The user's own attached table wins over a public alias: "train an hERG classifier on
        # THIS file" must train on their file. The label column is read from the request when it
        # names one (pIC50 / IC50 / activity / …); the alias column is the fallback for a public
        # assay; "y" only when nothing says otherwise. The card is editable either way.
        target = _infer_target_col(text) or (alias[2] if alias else "y")
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

    name = default_name or _derive_name(text, alias, own_data=bool(dataset_s3_uri))
    return TrainingConfig(
        name=name, task_type=task_type, model_type=model_type,
        dataset=dataset, hyperparams=Hyperparams(), metric=metric,
    ).validate()


def nextflow_path_for(model_type: str) -> str:
    """The Nextflow wrapper that runs a model_type.

    Each diffusion family runs in its own wrapper (distinct GPU image); every
    other model type shares the generic training wrapper (dispatch is by
    --model-type in the CLI). Single source of truth for chat routing and the
    Models-panel plan endpoint.
    """
    if model_type == "protein_diffusion":
        return "ml_training/diffusion_train.nf"
    if model_type == "scrna_diffusion":
        return "ml_training/scrna_diffusion_train.nf"
    # GPU tier for LLM preference/RL fine-tuning (DPO/GRPO). OFF BY DEFAULT: these
    # run on the verified CPU path (chemprop_train.nf dispatches by --model-type,
    # small models). Set ML_TRAINING_GPU_LLM=1 only AFTER the CUDA trl-training image
    # is built and a GPU Batch queue sized for real models is provisioned — then they
    # route to the process_gpu wrapper. See docs/20261118_ML_TRAINING_GPU_TIER.md.
    if model_type in ("trl_dpo", "trl_grpo") and _gpu_llm_enabled():
        return "ml_training/trl_train.nf"
    return "ml_training/chemprop_train.nf"


def _gpu_llm_enabled() -> bool:
    """True only when the GPU LLM tier is explicitly turned on AND its infra exists."""
    return os.environ.get("ML_TRAINING_GPU_LLM", "").strip().lower() in ("1", "true", "yes", "on")


def route_ml_training(
    text: str,
    *,
    dataset_s3_uri: Optional[str] = None,
    uploaded_datasets: Optional[Any] = None,
    llm_fill: Optional[Callable[[str], dict[str, Any]]] = None,
) -> Optional[dict[str, Any]]:
    """Router hook: return a workflow_ga for a training request, else None.

    Returning None means "not a training intent — fall through to the normal
    workflow search". This is what the reviewed ai_assistant hook calls.

    ``uploaded_datasets`` is the user's attached session data: when the request says "train a
    model on THIS data", that attachment IS the dataset, and without it the extraction used to
    fail to resolve one and fall through to the catalog search — which answered a model-TRAINING
    request with a molecule-DESIGN workflow (dev 2026-11-11, "Train a potency predictor on our
    in-house assay data." + bace_assays.csv → a scaffold-hopping card asking for `input_smiles`).
    """
    if not detect_training_intent(text):
        return None
    if not dataset_s3_uri:
        dataset_s3_uri = select_training_dataset(uploaded_datasets)
    try:
        cfg = extract_training_config(text, dataset_s3_uri=dataset_s3_uri, llm_fill=llm_fill)
    except ValueError:
        return None  # ambiguous → let the normal router try
    nf_path = nextflow_path_for(cfg.model_type)
    ga = cfg.to_workflow_ga(nextflow_path=nf_path)
    ga["scientific_rationale"] = (
        f"Detected a model-training request; routing to the ml_training pipeline "
        f"({cfg.model_type}, {cfg.task_type}) on dataset "
        f"{cfg.dataset.name or cfg.dataset.s3_uri}."
    )
    # Attach compute_config so Confirm & Run can forward the right GPU image
    # without relying solely on nextflow_executor's path fallback.
    from .executor_payload import resolve_ml_training_container
    ga["compute_config"] = {
        "executor": "awsbatch",
        "container": resolve_ml_training_container(cfg.model_type, nf_path),
    }
    return ga


def route_ml_training_result(
    text: str,
    *,
    enabled: Optional[bool] = None,
    dataset_s3_uri: Optional[str] = None,
    uploaded_datasets: Optional[Any] = None,
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
    ga = route_ml_training(text, dataset_s3_uri=dataset_s3_uri,
                           uploaded_datasets=uploaded_datasets, llm_fill=llm_fill)
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


# "Train a potency predictor", "build a solubility classifier", "fit a hERG regression model" — the
# model the user asked for, in their own words. The card title and the chat text both come from this
# name, so a generic "molecular model" makes the reply unable to say what was built.
_MODEL_NAME_RE = re.compile(
    r"\b(?:a|an|the)?\s*([a-z0-9][\w+-]{2,30})\s+(predictor|classifier|regressor|model)\b", re.I)


def _derive_name(
    text: str,
    alias: Optional[tuple[str, str, str]],
    *,
    own_data: bool = False,
) -> str:
    """Card title. Prefer the user's wording ("solubility model") when they attached
    their own table; only use TDC-style alias names (Solubility_AqSolDB) when the
    job actually trains on that public alias."""
    m = _MODEL_NAME_RE.search(text or "")
    if m and m.group(1).lower() not in ("a", "an", "the", "new", "our", "my", "this", "that"):
        return f"{m.group(1)} {m.group(2).lower()}"
    if alias and not own_data:
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
