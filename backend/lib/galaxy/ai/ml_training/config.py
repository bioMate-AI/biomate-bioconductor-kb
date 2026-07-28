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

from dataclasses import dataclass, field, asdict
from typing import Any, Optional

# --- Supported enums (validated; keeps the low-code surface constrained) -----

TASK_TYPES = ("classification", "regression", "text_generation")
# ludwig_tabular = low-code DL (Ludwig NN over RDKit descriptors, CPU-runnable);
# chemprop_gnn = molecular graph DL (GPU); sklearn_gbr = cheap non-DL baseline;
# ludwig_llm = low-code LLM fine-tuning (Ludwig LoRA/QLoRA over a base model).
MODEL_TYPES = ("chemprop_gnn", "ludwig_tabular", "sklearn_gbr", "ludwig_llm")
FEATURIZERS = ("rdkit_2d", "morgan", "none")
ADAPTERS = ("lora", "qlora", "none")


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
    split: str = "scaffold"        # scaffold | random
    val_frac: float = 0.1
    test_frac: float = 0.1

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
        if self.split not in ("scaffold", "random"):
            raise ConfigError(f"unknown split '{self.split}'")
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

    def validate(self) -> None:
        if not self.base_model or not self.base_model.strip():
            raise ConfigError("llm.base_model is required for ludwig_llm")
        if self.adapter not in ADAPTERS:
            raise ConfigError(f"llm.adapter must be one of {ADAPTERS}")
        if self.max_sequence_length <= 0:
            raise ConfigError("llm.max_sequence_length must be > 0")
        if self.quantization_bits not in (None, 4, 8):
            raise ConfigError("llm.quantization_bits must be None, 4, or 8")


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
    higher_is_better: bool = False              # for hERG, lower risk = better
    metric: str = "auc"                         # primary metric to track/gate
    gate_threshold: Optional[float] = None      # e.g. min AUC to pass QC gate
    llm: Optional[LLMSpec] = None               # required when model_type=ludwig_llm

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
        if self.model_type == "ludwig_llm":
            if self.llm is None:
                raise ConfigError("model_type=ludwig_llm requires an `llm` spec")
            self.llm.validate()
            if self.task_type != "text_generation":
                raise ConfigError("ludwig_llm requires task_type=text_generation")
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
        cfg = cls(
            dataset=DatasetSpec(**ds) if isinstance(ds, dict) else ds,
            hyperparams=Hyperparams(**hp) if isinstance(hp, dict) else hp,
            llm=LLMSpec(**llm) if isinstance(llm, dict) else llm,
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
        if self.model_type == "ludwig_llm":
            llm = self.llm or LLMSpec()
            required = [
                {"name": "dataset", "type": "file",
                 "label": "Training data (JSONL/CSV: instruction, output)",
                 "value": self.dataset.name or self.dataset.path or self.dataset.s3_uri or "",
                 "required": True},
                {"name": "base_model", "type": "string", "label": "Base model (HF id)",
                 "value": llm.base_model, "required": True},
            ]
            optional = [
                {"name": "model_type", "type": "select", "label": "Model type",
                 "allowed_values": list(MODEL_TYPES), "value": self.model_type, "default": "ludwig_tabular"},
                {"name": "adapter", "type": "select", "label": "Adapter",
                 "allowed_values": list(ADAPTERS), "value": llm.adapter, "default": "lora"},
                {"name": "instruction_col", "type": "string", "label": "Instruction column",
                 "value": llm.instruction_col, "default": "instruction"},
                {"name": "output_col", "type": "string", "label": "Output column",
                 "value": llm.output_col, "default": "output"},
                {"name": "max_sequence_length", "type": "number", "label": "Max sequence length",
                 "value": llm.max_sequence_length, "default": 256},
                {"name": "epochs", "type": "number", "label": "Epochs",
                 "value": self.hyperparams.epochs, "default": 3},
                {"name": "learning_rate", "type": "number", "label": "Learning rate",
                 "value": self.hyperparams.learning_rate, "default": 1e-4},
            ]
            return {"required_params": required, "optional_params": optional}

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
        return {"required_params": required, "optional_params": optional}

    def to_workflow_ga(self, nextflow_path: str = "ml_training/chemprop_train.nf") -> dict[str, Any]:
        """Full workflow_ga stub for routing/rendering a training job."""
        params = self.to_workflow_ga_params()
        return {
            "name": self.name,
            "domain": "ml_training",
            "format": "nextflow",
            "nextflow_path": nextflow_path,
            "description": f"Train a {self.model_type} {self.task_type} model: {self.name}",
            "execution_engine": "awsbatch",
            **params,
        }
