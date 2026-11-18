"""
Declarative low-code training configuration.

This is the "low-code" surface of the ML training platform: a user (or the LLM
param-prefill layer) fills a small config — task type, dataset, target column,
model type, a handful of hyperparameters — and the platform assembles, trains,
validates, tracks and registers the model with zero boilerplate.

The config is a plain dataclass (no pydantic/version risk, matching the
`drug_discovery.custom_model_wrapper.ModelRunRecord` /
`regulatory_training_jobs.TrainingJob` dataclass style) so it is trivially
serializable and unit-testable.

`to_workflow_ga_params()` maps the config to the existing `workflow_ga`
required/optional param contract consumed by the frontend
`NextflowWorkflowViewer`, so a training job renders as an ordinary workflow
card with a parameter form — no new frontend code.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field, asdict
from typing import Any, Optional

# --- Supported enums (validated; keeps the low-code surface constrained) -----

TASK_TYPES = ("classification", "regression", "text_generation",
              "structure_generation",
              # scrna_diffusion: generate/augment single-cell expression profiles.
              "expression_generation",
              # tabular_diffusion: generate/augment synthetic rows of a generic
              # numeric/categorical feature matrix (TabDDPM / TabSyn).
              "tabular_generation")
# ludwig_tabular = low-code DL (Ludwig NN over RDKit descriptors, CPU-runnable);
# chemprop_gnn = molecular graph DL (GPU); sklearn_gbr = cheap non-DL baseline;
# ludwig_llm = low-code LLM fine-tuning (Ludwig LoRA/QLoRA over a base model).
# trl_dpo = LLM preference optimization (DPO, TRL); trl_grpo = LLM reinforcement
# learning (GRPO, TRL). Both run in the separate trl-training image (modern
# torch+trl, no Ludwig) since TRL's deps conflict with Ludwig's pins.
# sklearn_tabular = generic numeric feature-matrix learner (e.g. a gene-expression
# matrix + a subtype/outcome label), with stratified k-fold cross-validation.
# NOT molecule-specific — the general counterpart to the SMILES-only paths.
# protein_diffusion = protein/peptide backbone structure diffusion (RFdiffusion /
# Chroma / Genie): fine-tune a released checkpoint OR train from scratch on a set
# of PDB/mmCIF structures. Runs in the separate diffusion-training image (SE(3)
# torch-cuda stack, no Ludwig/TRL) — its deps conflict with both.
# scrna_diffusion = single-cell expression structure-diffusion (scDiffusion/CFGen):
# fine-tune a pretrained checkpoint OR train from scratch to generate/augment
# scRNA-seq cells. Runs in the separate sc-diffusion-training image (torch-cuda +
# scanpy/anndata), GPU-only for real runs.
# tabular_diffusion = GENERIC tabular-data diffusion (TabDDPM/TabSyn): fine-tune a
# pretrained checkpoint OR train from scratch to synthesize/augment rows of a
# numeric+categorical feature matrix (CSV/parquet). The domain-agnostic sibling of
# scrna_diffusion (h5ad) and protein_diffusion (PDB). Runs in the separate
# tabular-diffusion-training image (torch-cuda), GPU-only for real runs.
MODEL_TYPES = ("chemprop_gnn", "ludwig_tabular", "sklearn_gbr", "sklearn_tabular",
               "ludwig_llm", "trl_dpo", "trl_grpo",
               "protein_diffusion", "scrna_diffusion", "tabular_diffusion")
LLM_MODEL_TYPES = ("ludwig_llm", "trl_dpo", "trl_grpo")   # text-generation family
TRL_MODEL_TYPES = ("trl_dpo", "trl_grpo")                 # run in trl-training image
# Diffusion family runs in a dedicated GPU image (dispatch is per model_type in
# executor_payload._resolve_container). protein_diffusion → diffusion-training;
# scrna_diffusion → sc-diffusion-training; tabular_diffusion → tabular-diffusion-training.
DIFFUSION_MODEL_TYPES = ("protein_diffusion", "scrna_diffusion", "tabular_diffusion")
FEATURIZERS = ("rdkit_2d", "morgan", "none")
# Model types that featurize a SMILES column (and therefore require one).
MOLECULAR_MODEL_TYPES = ("chemprop_gnn", "sklearn_gbr")
ADAPTERS = ("lora", "qlora", "none")
# Built-in reward functions for GRPO (a real reward fn or a named built-in).
# "composite" = a user-declared, weighted multi-component reward (reward_spec),
# letting a domain expert inject knowledge/rules into the RL run without code —
# the same lever REINVENT4's multi-objective reward provides for generative RL.
REWARD_KINDS = ("length", "keyword", "numeric_answer", "composite")

# Declarative scoring components for reward="composite". Each component scores a
# completion in [-1, 1] and is combined as a weighted sum. These are evaluated
# by a fixed interpreter (no arbitrary code) so a reward spec is safe to accept
# from a user / project rule.
COMPOSITE_COMPONENT_KINDS = (
    "contains_any",    # terms: [..]   → 1 if any term present      (desired content)
    "contains_all",    # terms: [..]   → 1 only if all present
    "banned",          # terms: [..]   → -1 if any present          (rule / guardrail)
    "regex",           # pattern: str  → 1 if regex matches (case-insensitive)
    "length_target",   # target: int   → peaks at target word count, negative away
    "numeric",         #               → 1 if the completion contains a digit
    "json_valid",      #               → 1 if the completion parses as JSON
    # Gate-family extensions (docs/20261027_EXPERT_FEEDBACK_RULES_GUARDRAILS_RSI.md):
    "numeric_threshold",  # value,op[,near] → +1 if a parsed number satisfies the op vs value,
                          #                   -1 if it violates, 0 if no number found     (G1 threshold)
    "implies",            # if_terms,then_terms → if any if_term present then all then_terms
                          #                   must be present (+1), else -1; 0 if untriggered (G6 relational)
    "order",              # before,after  → +1 if `before` precedes `after`, -1 if reversed,
                          #                   0 if either absent                            (G7 ordering)
)

# Comparison operators accepted by the numeric_threshold component.
NUMERIC_THRESHOLD_OPS = ("<", "<=", ">", ">=", "==", "!=")

# Structure-diffusion frameworks. rfdiffusion is the concrete implemented default
# (BSD-licensed, released weights, documented fine-tune harness on the RF2 SE(3)
# transformer); chroma/genie are accepted names for the same model_type/wrapper.
DIFFUSION_FRAMEWORKS = ("rfdiffusion", "chroma", "genie")
# Noise schedules supported by the diffusion sampler/backbone. Union of both
# diffusion families: protein_diffusion uses linear|cosine; scrna_diffusion adds
# sqrt (scDiffusion's train-from-scratch backbone supports it).
NOISE_SCHEDULES = ("linear", "cosine", "sqrt")


class ConfigError(ValueError):
    """Raised when a TrainingConfig fails validation."""


@dataclass
class Hyperparams:
    epochs: int = 50
    batch_size: int = 50
    depth: int = 3                 # message-passing steps (Chemprop)
    hidden_size: int = 300
    dropout: float = 0.0
    learning_rate: float = 1e-3
    ensemble_size: int = 1
    seed: int = 42

    def validate(self) -> None:
        if self.epochs <= 0:
            raise ConfigError("epochs must be > 0")
        if self.batch_size <= 0:
            raise ConfigError("batch_size must be > 0")
        if not (0.0 <= self.dropout < 1.0):
            raise ConfigError("dropout must be in [0, 1)")
        if self.learning_rate <= 0:
            raise ConfigError("learning_rate must be > 0")
        if self.ensemble_size <= 0:
            raise ConfigError("ensemble_size must be > 0")


@dataclass
class DatasetSpec:
    """Where the training data comes from.

    Exactly one of {`name`, `path`, `s3_uri`} identifies the source:
      - name   : a known public dataset shortcut (e.g. "tdc:hERG")
      - path   : a local CSV/SDF path
      - s3_uri : an s3:// path staged by the executor (production path)
    """
    name: Optional[str] = None
    path: Optional[str] = None
    s3_uri: Optional[str] = None
    smiles_col: str = "smiles"
    target_col: str = "y"
    split: str = "scaffold"        # scaffold | random | kfold
    val_frac: float = 0.1
    test_frac: float = 0.1
    cv_folds: int = 5              # k for split="kfold" (generic tabular path)

    def source_kind(self) -> str:
        provided = [k for k, v in (("name", self.name), ("path", self.path),
                                   ("s3_uri", self.s3_uri)) if v]
        if len(provided) != 1:
            raise ConfigError(
                f"DatasetSpec needs exactly one of name/path/s3_uri, got {provided or 'none'}"
            )
        return provided[0]

    def validate(self) -> None:
        self.source_kind()  # raises if not exactly one source
        if self.split not in ("scaffold", "random", "kfold"):
            raise ConfigError(f"unknown split '{self.split}'")
        if self.split == "kfold" and self.cv_folds < 2:
            raise ConfigError("cv_folds must be >= 2 for split='kfold'")
        if not (0.0 <= self.val_frac < 1.0) or not (0.0 <= self.test_frac < 1.0):
            raise ConfigError("val_frac/test_frac must be in [0, 1)")
        if self.val_frac + self.test_frac >= 1.0:
            raise ConfigError("val_frac + test_frac must leave room for training data")


@dataclass
class LLMSpec:
    """LLM fine-tuning knobs (model_type == 'ludwig_llm').

    The dataset for LLM tuning is instruction/response text (JSONL or CSV with
    `instruction_col` + `output_col`), NOT molecules — so it uses these columns
    instead of DatasetSpec.smiles_col/target_col.
    """
    base_model: str = "HuggingFaceTB/SmolLM2-135M-Instruct"   # small default; CPU-feasible
    instruction_col: str = "instruction"
    output_col: str = "output"
    max_sequence_length: int = 256
    # Default LoRA (no quantization) is CPU-feasible on a small base model,
    # matching the platform's CPU-first story. QLoRA (4-bit bitsandbytes) is
    # opt-in and effectively needs a GPU.
    adapter: str = "lora"                       # lora | qlora | none
    quantization_bits: Optional[int] = None     # set 4 for QLoRA (GPU)
    # --- preference optimization (trl_dpo) / reinforcement learning (trl_grpo) ---
    beta: float = 0.1                           # DPO KL regularization strength
    num_generations: int = 4                    # GRPO: samples per prompt (group size)
    reward: str = "length"                      # GRPO reward: length|keyword|numeric_answer|composite
    reward_keyword: str = ""                    # for reward=keyword
    # For reward="composite": a list of weighted scoring components that encode
    # domain knowledge + rules, e.g.
    #   [{"kind":"contains_all","terms":["dose","mg"],"weight":1.0},
    #    {"kind":"banned","terms":["as an ai"],"weight":2.0},
    #    {"kind":"numeric","weight":0.5}]
    reward_spec: Optional[list] = None

    def validate(self) -> None:
        if not self.base_model or not self.base_model.strip():
            raise ConfigError("llm.base_model is required for LLM training")
        if self.adapter not in ADAPTERS:
            raise ConfigError(f"llm.adapter must be one of {ADAPTERS}")
        if self.max_sequence_length <= 0:
            raise ConfigError("llm.max_sequence_length must be > 0")
        if self.quantization_bits not in (None, 4, 8):
            raise ConfigError("llm.quantization_bits must be None, 4, or 8")
        if self.beta <= 0:
            raise ConfigError("llm.beta (DPO) must be > 0")
        if self.num_generations < 2:
            raise ConfigError("llm.num_generations (GRPO) must be >= 2")
        if self.reward not in REWARD_KINDS:
            raise ConfigError(f"llm.reward must be one of {REWARD_KINDS}")
        if self.reward == "composite":
            spec = self.reward_spec
            if not isinstance(spec, list) or not spec:
                raise ConfigError("llm.reward='composite' requires a non-empty reward_spec list")
            for i, comp in enumerate(spec):
                if not isinstance(comp, dict):
                    raise ConfigError(f"reward_spec[{i}] must be an object")
                kind = comp.get("kind")
                if kind not in COMPOSITE_COMPONENT_KINDS:
                    raise ConfigError(f"reward_spec[{i}].kind must be one of {COMPOSITE_COMPONENT_KINDS}")
                if kind in ("contains_any", "contains_all", "banned"):
                    if not isinstance(comp.get("terms"), list) or not comp["terms"]:
                        raise ConfigError(f"reward_spec[{i}] ({kind}) requires a non-empty 'terms' list")
                if kind == "regex" and not comp.get("pattern"):
                    raise ConfigError(f"reward_spec[{i}] (regex) requires a 'pattern'")
                if kind == "numeric_threshold":
                    if comp.get("op") not in NUMERIC_THRESHOLD_OPS:
                        raise ConfigError(
                            f"reward_spec[{i}] (numeric_threshold) requires 'op' in {NUMERIC_THRESHOLD_OPS}")
                    try:
                        float(comp.get("value"))
                    except (TypeError, ValueError):
                        raise ConfigError(f"reward_spec[{i}] (numeric_threshold) requires a numeric 'value'")
                if kind == "implies":
                    if not isinstance(comp.get("if_terms"), list) or not comp["if_terms"] \
                       or not isinstance(comp.get("then_terms"), list) or not comp["then_terms"]:
                        raise ConfigError(
                            f"reward_spec[{i}] (implies) requires non-empty 'if_terms' and 'then_terms' lists")
                if kind == "order" and (not comp.get("before") or not comp.get("after")):
                    raise ConfigError(f"reward_spec[{i}] (order) requires 'before' and 'after'")
                try:
                    float(comp.get("weight", 1.0))
                except (TypeError, ValueError):
                    raise ConfigError(f"reward_spec[{i}].weight must be numeric")


@dataclass
class DiffusionSpec:
    """Protein/peptide structure-diffusion knobs (model_type == 'protein_diffusion').

    Mirrors LLMSpec: a small typed block of the conditioning + sampling knobs the
    structure-diffusion framework needs. The *dataset* for structure diffusion is
    a set of PDB/mmCIF backbones (a directory or manifest), not molecules or text,
    so it uses cfg.dataset.path/s3_uri as a structure-set pointer (parsed in the
    trainer), NOT smiles_col/target_col.

    Supports BOTH modes:
      - finetune=True  → warm-start from `base_checkpoint` (the released RFdiffusion
        weights) and adapt on the user's structure set.
      - finetune=False → train the diffusion model from scratch on the structure set.

    Conditioning fields map onto RFdiffusion's contig / hotspot / motif inputs so a
    binder/scaffold design request renders as an ordinary parameter form.
    """
    framework: str = "rfdiffusion"                # rfdiffusion | chroma | genie
    # Warm-start checkpoint for fine-tuning (framework-native id/path). The empty
    # default + finetune=False means "train from scratch".
    base_checkpoint: str = "rfdiffusion/Base_ckpt.pt"
    finetune: bool = True                         # fine-tune a checkpoint vs. from-scratch
    # --- conditioning ---
    target_pdb: str = ""                          # target/receptor PDB for binder design (path/id)
    hotspot_residues: str = ""                    # e.g. "A30,A33,A34" — target residues to engage
    motif_pdb: str = ""                           # scaffolding motif structure (motif-scaffolding)
    contig: str = ""                              # RFdiffusion contig/scaffold spec, e.g. "10-40/A20-30/10-40"
    # --- length + sampling ---
    length_min: int = 60                          # designed chain length range (residues)
    length_max: int = 100
    num_designs: int = 8                          # how many backbones to generate
    diffusion_steps: int = 50                     # reverse-diffusion (T) steps at sampling
    noise_schedule: str = "linear"                # linear | cosine

    def validate(self) -> None:
        if self.framework not in DIFFUSION_FRAMEWORKS:
            raise ConfigError(f"diffusion.framework must be one of {DIFFUSION_FRAMEWORKS}")
        if self.finetune and not (self.base_checkpoint or "").strip():
            raise ConfigError("diffusion.base_checkpoint is required when finetune=True")
        if self.length_min <= 0 or self.length_max <= 0:
            raise ConfigError("diffusion.length_min/length_max must be > 0")
        if self.length_min > self.length_max:
            raise ConfigError("diffusion.length_min must be <= length_max")
        if self.num_designs <= 0:
            raise ConfigError("diffusion.num_designs must be > 0")
        if self.diffusion_steps <= 0:
            raise ConfigError("diffusion.diffusion_steps must be > 0")
        if self.noise_schedule not in NOISE_SCHEDULES:
            raise ConfigError(f"diffusion.noise_schedule must be one of {NOISE_SCHEDULES}")


# Supported single-cell diffusion frameworks. scDiffusion (EperLuo/scDiffusion)
# is the default: it is a genuine denoising-diffusion model over scRNA-seq
# embeddings, operates on h5ad, ships a fine-tunable pretrained autoencoder
# (SCimilarity) and supports classifier-guided conditional generation
# (cell_type, guidance_scale). CFGen (theislab/CFGen) is a flow-matching
# alternative kept as a supported value.
SC_DIFFUSION_FRAMEWORKS = ("scdiffusion", "cfgen")


@dataclass
class SCDiffusionSpec:
    """Single-cell expression-diffusion knobs (model_type == 'scrna_diffusion').

    The dataset for expression diffusion is an **h5ad** AnnData of single cells
    (genes × cells count matrix + obs metadata), NOT molecules or text — so it
    ignores DatasetSpec.smiles_col/target_col and reads the AnnData directly.

    Two modes, both supported:
      * finetune=True  → warm-start from `base_checkpoint`/`base_model` (a
        pretrained scDiffusion/CFGen weight) and adapt to the user's h5ad.
      * finetune=False → train the diffusion backbone from scratch on the h5ad.

    Conditioning (cell_type / condition_label) + guidance_scale drive
    classifier-guided conditional generation of `n_cells_to_generate` new cells.
    """
    framework: str = "scdiffusion"                 # scdiffusion | cfgen
    # Pretrained warm-start. base_checkpoint = a diffusion/backbone weight;
    # base_model = the (fine-tunable) autoencoder/foundation weight (e.g.
    # SCimilarity for scDiffusion). Either may be empty for train-from-scratch.
    base_checkpoint: str = ""
    base_model: str = ""
    finetune: bool = True                          # fine-tune vs. train-from-scratch
    # --- conditioning / generation ---
    cell_type: str = ""                            # obs cell-type to condition on ("" = unconditional)
    condition_label: str = ""                      # obs column for perturbation/condition (e.g. "perturbation")
    n_cells_to_generate: int = 1000
    n_genes: int = 0                               # 0 = infer from the h5ad var axis
    guidance_scale: float = 1.0                    # classifier-free guidance strength
    # --- diffusion backbone ---
    diffusion_steps: int = 1000
    noise_schedule: str = "cosine"                 # cosine | linear | sqrt

    def validate(self) -> None:
        if self.framework not in SC_DIFFUSION_FRAMEWORKS:
            raise ConfigError(f"sc.framework must be one of {SC_DIFFUSION_FRAMEWORKS}")
        if self.finetune and not (self.base_checkpoint.strip() or self.base_model.strip()):
            raise ConfigError(
                "sc.finetune=True requires a base_checkpoint or base_model to warm-start from "
                "(set finetune=False to train the diffusion backbone from scratch)."
            )
        if self.n_cells_to_generate <= 0:
            raise ConfigError("sc.n_cells_to_generate must be > 0")
        if self.n_genes < 0:
            raise ConfigError("sc.n_genes must be >= 0 (0 = infer from the h5ad)")
        if self.guidance_scale <= 0:
            raise ConfigError("sc.guidance_scale must be > 0")
        if self.diffusion_steps <= 0:
            raise ConfigError("sc.diffusion_steps must be > 0")
        if self.noise_schedule not in NOISE_SCHEDULES:
            raise ConfigError(f"sc.noise_schedule must be one of {NOISE_SCHEDULES}")


# Supported generic tabular-diffusion frameworks. tabddpm (rotot0/tab-ddpm) is the
# default: a genuine denoising-diffusion model over a mixed numeric/categorical
# feature matrix with class-conditional synthesis. tabsyn (amazon-science/tabsyn)
# is a latent-diffusion alternative kept as a supported value.
TABULAR_DIFFUSION_FRAMEWORKS = ("tabddpm", "tabsyn")


@dataclass
class TabularDiffusionSpec:
    """Generic tabular-data diffusion knobs (model_type == 'tabular_diffusion').

    The dataset for tabular diffusion is a **CSV/parquet numeric+categorical
    feature matrix** (rows = samples, columns = features), NOT molecules, text,
    structures or h5ad — so it ignores DatasetSpec.smiles_col/target_col and reads
    cfg.dataset.path/s3_uri directly as the feature table (parsed in the trainer).

    Two modes, both supported:
      * finetune=True  → warm-start from `base_checkpoint` (a pretrained
        TabDDPM/TabSyn weight) and adapt to the user's feature matrix.
      * finetune=False → train the diffusion backbone from scratch on the matrix.

    `target_column` (a categorical column) drives class-conditional synthesis;
    "" = unconditional generation of `n_rows_to_generate` new rows, with
    classifier-free guidance strength `guidance_scale`.
    """
    framework: str = "tabddpm"                     # tabddpm | tabsyn
    # Pretrained warm-start checkpoint (framework-native id/path). Empty default
    # + finetune=False means "train from scratch".
    base_checkpoint: str = ""
    finetune: bool = True                          # fine-tune vs. train-from-scratch
    # --- conditioning / generation ---
    target_column: str = ""                        # categorical column to condition on ("" = unconditional)
    n_rows_to_generate: int = 1000
    guidance_scale: float = 1.0                    # classifier-free guidance strength
    # --- diffusion backbone ---
    diffusion_steps: int = 1000
    noise_schedule: str = "cosine"                 # cosine | linear | sqrt

    def validate(self) -> None:
        if self.framework not in TABULAR_DIFFUSION_FRAMEWORKS:
            raise ConfigError(f"tabular.framework must be one of {TABULAR_DIFFUSION_FRAMEWORKS}")
        if self.finetune and not (self.base_checkpoint or "").strip():
            raise ConfigError(
                "tabular.finetune=True requires a base_checkpoint to warm-start from "
                "(set finetune=False to train the diffusion backbone from scratch)."
            )
        if self.n_rows_to_generate <= 0:
            raise ConfigError("tabular.n_rows_to_generate must be > 0")
        if self.guidance_scale <= 0:
            raise ConfigError("tabular.guidance_scale must be > 0")
        if self.diffusion_steps <= 0:
            raise ConfigError("tabular.diffusion_steps must be > 0")
        if self.noise_schedule not in NOISE_SCHEDULES:
            raise ConfigError(f"tabular.noise_schedule must be one of {NOISE_SCHEDULES}")


@dataclass
class TrainingConfig:
    """The full declarative spec for one training run."""
    name: str                                   # human-readable model name
    task_type: str = "classification"
    model_type: str = "chemprop_gnn"
    featurizer: str = "rdkit_2d"
    dataset: DatasetSpec = field(default_factory=DatasetSpec)
    hyperparams: Hyperparams = field(default_factory=Hyperparams)
    # Where the trained artifact + MLflow experiment land.
    mlflow_experiment: str = "biomate-ml-training"
    campaign_id: str = "default"                # registry is per-campaign
    adapt_of: Optional[str] = None              # registry model id this run ADAPTS; its
                                                # artifact registers as that model's next
                                                # version (lineage), not a fresh model
    higher_is_better: bool = False              # for hERG, lower risk = better
    metric: str = "auc"                         # primary metric to track/gate
    gate_threshold: Optional[float] = None      # e.g. min AUC to pass QC gate
    llm: Optional[LLMSpec] = None               # required when model_type=ludwig_llm
    diffusion: Optional[DiffusionSpec] = None   # required when model_type=protein_diffusion
    sc: Optional[SCDiffusionSpec] = None        # required when model_type=scrna_diffusion
    tabular: Optional[TabularDiffusionSpec] = None  # required when model_type=tabular_diffusion

    # -- validation -----------------------------------------------------------
    def validate(self) -> "TrainingConfig":
        if not self.name or not self.name.strip():
            raise ConfigError("name is required")
        if self.task_type not in TASK_TYPES:
            raise ConfigError(f"task_type must be one of {TASK_TYPES}")
        if self.model_type not in MODEL_TYPES:
            raise ConfigError(f"model_type must be one of {MODEL_TYPES}")
        if self.featurizer not in FEATURIZERS:
            raise ConfigError(f"featurizer must be one of {FEATURIZERS}")
        self.dataset.validate()
        self.hyperparams.validate()
        if self.gate_threshold is not None:
            try:
                thr = float(self.gate_threshold)
            except (TypeError, ValueError):
                raise ConfigError(f"gate_threshold must be numeric, got {self.gate_threshold!r}")
            if not math.isfinite(thr):
                raise ConfigError(f"gate_threshold must be finite, got {self.gate_threshold!r}")
        # Molecular featurizers need a SMILES column; generic learners must not.
        if self.model_type in MOLECULAR_MODEL_TYPES and self.featurizer == "none":
            raise ConfigError(
                f"{self.model_type} featurizes SMILES; featurizer='none' is only valid for "
                "generic tabular learners (sklearn_tabular / ludwig_tabular)")
        if self.model_type == "ludwig_tabular" and self.featurizer == "none":
            if self.dataset.split == "scaffold":
                raise ConfigError("a scaffold split needs SMILES; use split='random' for a "
                                  "generic (featurizer='none') Ludwig table")
            if self.dataset.split == "kfold":
                raise ConfigError("Ludwig supports split='random' or 'scaffold', not 'kfold'")
        if self.model_type in LLM_MODEL_TYPES:
            if self.llm is None:
                raise ConfigError(f"model_type={self.model_type} requires an `llm` spec")
            self.llm.validate()
            if self.task_type != "text_generation":
                raise ConfigError(f"{self.model_type} requires task_type=text_generation")
            if self.dataset.split == "scaffold":
                raise ConfigError(
                    f"{self.model_type} trains on text; a Bemis-Murcko scaffold split "
                    "cannot be applied. Use split='random'.")
        if self.model_type == "protein_diffusion":
            if self.diffusion is None:
                raise ConfigError(f"model_type={self.model_type} requires a `diffusion` spec")
            self.diffusion.validate()
            if self.task_type != "structure_generation":
                raise ConfigError(f"{self.model_type} requires task_type=structure_generation")
        if self.model_type == "scrna_diffusion":
            if self.sc is None:
                raise ConfigError(f"model_type={self.model_type} requires an `sc` spec")
            self.sc.validate()
            if self.task_type != "expression_generation":
                raise ConfigError(f"{self.model_type} requires task_type=expression_generation")
        if self.model_type == "tabular_diffusion":
            if self.tabular is None:
                raise ConfigError(f"model_type={self.model_type} requires a `tabular` spec")
            self.tabular.validate()
            if self.task_type != "tabular_generation":
                raise ConfigError(f"{self.model_type} requires task_type=tabular_generation")
        return self

    # -- (de)serialization ----------------------------------------------------
    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "TrainingConfig":
        d = dict(d or {})
        ds = d.pop("dataset", {}) or {}
        hp = d.pop("hyperparams", {}) or {}
        llm = d.pop("llm", None)
        diff = d.pop("diffusion", None)
        sc = d.pop("sc", None)
        tabular = d.pop("tabular", None)
        cfg = cls(
            dataset=DatasetSpec(**ds) if isinstance(ds, dict) else ds,
            hyperparams=Hyperparams(**hp) if isinstance(hp, dict) else hp,
            llm=LLMSpec(**llm) if isinstance(llm, dict) else llm,
            diffusion=DiffusionSpec(**diff) if isinstance(diff, dict) else diff,
            sc=SCDiffusionSpec(**sc) if isinstance(sc, dict) else sc,
            tabular=TabularDiffusionSpec(**tabular) if isinstance(tabular, dict) else tabular,
            **d,
        )
        return cfg

    # -- frontend integration -------------------------------------------------
    def to_workflow_ga_params(self) -> dict[str, list[dict[str, Any]]]:
        """Map to the workflow_ga required/optional param contract.

        Consumed as-is by the existing frontend NextflowWorkflowViewer form
        renderer (file/select/number/string types), so a training job shows up
        as an ordinary workflow card. See §4.2 of the design doc.
        """
        common = [
            {"name": "model_name", "type": "string", "label": "Model name", "value": self.name},
            {"name": "metric", "type": "string", "label": "Evaluation metric", "value": self.metric},
            {"name": "gate_threshold", "type": "number", "label": "Quality gate threshold", "value": self.gate_threshold},
        ]
        if self.model_type == "tabular_diffusion":
            tab = self.tabular or TabularDiffusionSpec()
            required = [
                {"name": "dataset", "type": "file",
                 "label": "Tabular data (CSV/parquet numeric+categorical feature matrix)",
                 "value": self.dataset.name or self.dataset.path or self.dataset.s3_uri or "",
                 "required": True},
            ]
            optional = [
                {"name": "framework", "type": "select", "label": "Diffusion framework",
                 "allowed_values": list(TABULAR_DIFFUSION_FRAMEWORKS), "value": tab.framework,
                 "default": "tabddpm"},
                {"name": "finetune", "type": "boolean", "label": "Fine-tune pretrained checkpoint",
                 "value": tab.finetune, "default": True},
                {"name": "base_checkpoint", "type": "string",
                 "label": "Pretrained diffusion checkpoint (fine-tune warm-start)",
                 "value": tab.base_checkpoint, "default": ""},
                {"name": "target_column", "type": "string",
                 "label": "Condition on column (categorical; blank = unconditional)",
                 "value": tab.target_column, "default": ""},
                {"name": "n_rows_to_generate", "type": "number", "label": "Rows to generate",
                 "value": tab.n_rows_to_generate, "default": 1000},
                {"name": "guidance_scale", "type": "number", "label": "Guidance scale",
                 "value": tab.guidance_scale, "default": 1.0},
                {"name": "diffusion_steps", "type": "number", "label": "Diffusion steps",
                 "value": tab.diffusion_steps, "default": 1000},
                {"name": "noise_schedule", "type": "select", "label": "Noise schedule",
                 "allowed_values": list(NOISE_SCHEDULES), "value": tab.noise_schedule,
                 "default": "cosine"},
                {"name": "epochs", "type": "number", "label": "Epochs",
                 "value": self.hyperparams.epochs, "default": 50},
                {"name": "learning_rate", "type": "number", "label": "Learning rate",
                 "value": self.hyperparams.learning_rate, "default": 1e-4},
            ]
            return {"required_params": required, "optional_params": common + optional}

        if self.model_type == "scrna_diffusion":
            sc = self.sc or SCDiffusionSpec()
            required = [
                {"name": "dataset", "type": "file",
                 "label": "Single-cell data (h5ad AnnData)",
                 "value": self.dataset.name or self.dataset.path or self.dataset.s3_uri or "",
                 "required": True},
            ]
            optional = [
                {"name": "framework", "type": "select", "label": "Diffusion framework",
                 "allowed_values": list(SC_DIFFUSION_FRAMEWORKS), "value": sc.framework,
                 "default": "scdiffusion"},
                {"name": "finetune", "type": "boolean", "label": "Fine-tune pretrained checkpoint",
                 "value": sc.finetune, "default": True},
                {"name": "base_checkpoint", "type": "string",
                 "label": "Pretrained diffusion checkpoint (fine-tune warm-start)",
                 "value": sc.base_checkpoint, "default": ""},
                {"name": "base_model", "type": "string",
                 "label": "Pretrained autoencoder/foundation weight (e.g. SCimilarity)",
                 "value": sc.base_model, "default": ""},
                {"name": "cell_type", "type": "string", "label": "Condition on cell type",
                 "value": sc.cell_type, "default": ""},
                {"name": "condition_label", "type": "string",
                 "label": "Condition/perturbation obs column", "value": sc.condition_label,
                 "default": ""},
                {"name": "n_cells_to_generate", "type": "number", "label": "Cells to generate",
                 "value": sc.n_cells_to_generate, "default": 1000},
                {"name": "n_genes", "type": "number", "label": "Number of genes (0 = infer)",
                 "value": sc.n_genes, "default": 0},
                {"name": "guidance_scale", "type": "number", "label": "Guidance scale",
                 "value": sc.guidance_scale, "default": 1.0},
                {"name": "diffusion_steps", "type": "number", "label": "Diffusion steps",
                 "value": sc.diffusion_steps, "default": 1000},
                {"name": "noise_schedule", "type": "select", "label": "Noise schedule",
                 "allowed_values": list(NOISE_SCHEDULES), "value": sc.noise_schedule,
                 "default": "cosine"},
                {"name": "epochs", "type": "number", "label": "Epochs",
                 "value": self.hyperparams.epochs, "default": 50},
                {"name": "learning_rate", "type": "number", "label": "Learning rate",
                 "value": self.hyperparams.learning_rate, "default": 1e-4},
            ]
            return {"required_params": required, "optional_params": common + optional}

        if self.model_type == "protein_diffusion":
            diff = self.diffusion or DiffusionSpec()
            required = [
                {"name": "dataset", "type": "file",
                 "label": "Structure set (dir/manifest of PDB/mmCIF backbones, or s3://…)",
                 "value": self.dataset.path or self.dataset.s3_uri or self.dataset.name or "",
                 "required": True},
                {"name": "framework", "type": "select", "label": "Diffusion framework",
                 "allowed_values": list(DIFFUSION_FRAMEWORKS), "value": diff.framework,
                 "required": True},
            ]
            optional = [
                {"name": "finetune", "type": "boolean", "label": "Fine-tune checkpoint (vs. from scratch)",
                 "value": diff.finetune, "default": True},
                {"name": "base_checkpoint", "type": "string", "label": "Base checkpoint (fine-tune)",
                 "value": diff.base_checkpoint, "default": "rfdiffusion/Base_ckpt.pt"},
                {"name": "target_pdb", "type": "string", "label": "Target PDB (binder design)",
                 "value": diff.target_pdb, "default": ""},
                {"name": "hotspot_residues", "type": "string", "label": "Hotspot residues (e.g. A30,A33)",
                 "value": diff.hotspot_residues, "default": ""},
                {"name": "motif_pdb", "type": "string", "label": "Motif PDB (scaffolding)",
                 "value": diff.motif_pdb, "default": ""},
                {"name": "contig", "type": "string", "label": "Contig / scaffold spec",
                 "value": diff.contig, "default": ""},
                {"name": "length_min", "type": "number", "label": "Length min (residues)",
                 "value": diff.length_min, "default": 60},
                {"name": "length_max", "type": "number", "label": "Length max (residues)",
                 "value": diff.length_max, "default": 100},
                {"name": "num_designs", "type": "number", "label": "Number of designs",
                 "value": diff.num_designs, "default": 8},
                {"name": "diffusion_steps", "type": "number", "label": "Diffusion steps (T)",
                 "value": diff.diffusion_steps, "default": 50},
                {"name": "noise_schedule", "type": "select", "label": "Noise schedule",
                 "allowed_values": list(NOISE_SCHEDULES), "value": diff.noise_schedule,
                 "default": "linear"},
                {"name": "epochs", "type": "number", "label": "Fine-tune epochs",
                 "value": self.hyperparams.epochs, "default": 5},
                {"name": "learning_rate", "type": "number", "label": "Learning rate",
                 "value": self.hyperparams.learning_rate, "default": 1e-4},
            ]
            return {"required_params": required, "optional_params": common + optional}

        if self.model_type in LLM_MODEL_TYPES:
            llm = self.llm or LLMSpec()
            is_dpo = self.model_type == "trl_dpo"
            is_grpo = self.model_type == "trl_grpo"
            data_label = ("Preference data (JSONL/CSV: prompt, chosen, rejected)" if is_dpo
                          else "Prompts (JSONL/CSV: prompt)" if is_grpo
                          else "Training data (JSONL/CSV: instruction, output)")
            required = [
                {"name": "dataset", "type": "file", "label": data_label,
                 "value": self.dataset.name or self.dataset.path or self.dataset.s3_uri or "",
                 "required": True},
                {"name": "base_model", "type": "string", "label": "Base model (HF id)",
                 "value": llm.base_model, "required": True},
            ]
            optional = [
                {"name": "task_type", "type": "select", "label": "Task",
                 "allowed_values": list(TASK_TYPES), "value": self.task_type},
                {"name": "model_type", "type": "select", "label": "Training method",
                 "allowed_values": list(MODEL_TYPES), "value": self.model_type, "default": "ludwig_llm"},
                {"name": "adapter", "type": "select", "label": "Adapter",
                 "allowed_values": list(ADAPTERS), "value": llm.adapter, "default": "lora"},
                {"name": "max_sequence_length", "type": "number", "label": "Max sequence length",
                 "value": llm.max_sequence_length, "default": 256},
                {"name": "epochs", "type": "number", "label": "Epochs",
                 "value": self.hyperparams.epochs, "default": 3},
                {"name": "learning_rate", "type": "number", "label": "Learning rate",
                 "value": self.hyperparams.learning_rate, "default": 1e-4},
            ]
            if is_dpo:
                optional.append({"name": "beta", "type": "number", "label": "DPO beta (KL)",
                                 "value": llm.beta, "default": 0.1})
            elif is_grpo:
                optional += [
                    {"name": "num_generations", "type": "number", "label": "GRPO samples/prompt",
                     "value": llm.num_generations, "default": 4},
                    {"name": "reward", "type": "select", "label": "Reward function",
                     "allowed_values": list(REWARD_KINDS), "value": llm.reward, "default": "length"},
                ]
            else:  # ludwig_llm SFT
                optional += [
                    {"name": "instruction_col", "type": "string", "label": "Instruction column",
                     "value": llm.instruction_col, "default": "instruction"},
                    {"name": "output_col", "type": "string", "label": "Output column",
                     "value": llm.output_col, "default": "output"},
                ]
            return {"required_params": required, "optional_params": common + optional}

        required = [
            {"name": "dataset", "type": "file",
             "label": "Training data (CSV/SDF or tdc:<name>)",
             "value": self.dataset.name or self.dataset.path or self.dataset.s3_uri or "",
             "required": True},
            {"name": "target_col", "type": "string", "label": "Target column",
             "value": self.dataset.target_col, "required": True},
        ]
        optional = [
            {"name": "model_type", "type": "select", "label": "Model type",
             "allowed_values": list(MODEL_TYPES), "value": self.model_type, "default": "chemprop_gnn"},
            {"name": "task_type", "type": "select", "label": "Task",
             "allowed_values": list(TASK_TYPES), "value": self.task_type, "default": "classification"},
            {"name": "epochs", "type": "number", "label": "Epochs",
             "value": self.hyperparams.epochs, "default": 50},
            {"name": "learning_rate", "type": "number", "label": "Learning rate",
             "value": self.hyperparams.learning_rate, "default": 1e-3},
            {"name": "ensemble_size", "type": "number", "label": "Ensemble size",
             "value": self.hyperparams.ensemble_size, "default": 1},
        ]
        return {"required_params": required, "optional_params": common + optional}

    def to_workflow_ga(self, nextflow_path: str = "ml_training/chemprop_train.nf") -> dict[str, Any]:
        """Full workflow_ga stub for routing/rendering a training job."""
        params = self.to_workflow_ga_params()
        from .executor_payload import training_launch_parameters
        is_adapt = bool(self.adapt_of)
        verb = "Adapt" if is_adapt else "Train"
        desc = f"{verb} a {self.model_type} {self.task_type} model: {self.name}"
        if is_adapt:
            desc += f" (new version of {self.adapt_of})"
        return {
            "name": self.name,
            "domain": "ml_training",
            "format": "nextflow",
            "nextflow_path": nextflow_path,
            "description": desc,
            "execution_engine": "awsbatch",
            # Tags the run + tells registration to version the base model rather than
            # register a fresh one. Absent/None ⇒ an ordinary training run.
            "workflow_type": "adaptation" if is_adapt else "training",
            "adapt_of": self.adapt_of,
            "parameters": training_launch_parameters(self, allow_unresolved_dataset=True),
            **params,
        }
