"""
Ludwig integration — the low-code DL engine.

Ludwig (LF AI & Data, open source) is a declarative deep-learning framework:
you describe input/output features + a trainer in a config dict, and Ludwig
assembles, trains, and serves a real neural network with zero model code.

This module maps our `TrainingConfig` → a Ludwig config dict, and centralises
the RDKit descriptor featurization so training and inference use identical
feature columns. Pure-Python (no ludwig/rdkit import at module load) so the
adapter is unit-testable without the ML stack — only `featurize_smiles_df`
touches rdkit, lazily.

Molecular data isn't natively featurized by Ludwig, so we turn each SMILES into
a fixed vector of RDKit 2D descriptors (a real, standard QSAR featurization) and
let Ludwig train a neural net over those `number` features. This keeps it
CPU-runnable and genuinely "low-code DL": the model is Ludwig's, config-driven.
"""
from __future__ import annotations

from typing import Any

from .config import TrainingConfig

# The descriptor feature set (named columns Ludwig will consume as `number`).
# Same six descriptors as the sklearn baseline, so results are comparable.
FEATURE_COLUMNS = [
    "MolWt", "MolLogP", "NumHDonors", "NumHAcceptors", "TPSA", "NumRotatableBonds",
]


def _output_feature(cfg: TrainingConfig, target_col: str) -> dict[str, Any]:
    if cfg.task_type == "classification":
        return {"name": target_col, "type": "binary"}
    return {"name": target_col, "type": "number"}


def to_ludwig_config(cfg: TrainingConfig, target_col: str = "y") -> dict[str, Any]:
    """Build a Ludwig config dict from the declarative TrainingConfig.

    Uses Ludwig's `number` input features over RDKit descriptors + a dense
    combiner. Trainer hyperparams come straight from cfg.hyperparams so the
    low-code knobs (epochs / batch_size / learning_rate) flow through.
    """
    hp = cfg.hyperparams
    return {
        "input_features": [
            {"name": c, "type": "number",
             "encoder": {"type": "dense", "output_size": hp.hidden_size,
                         "num_layers": max(1, hp.depth), "dropout": hp.dropout}}
            for c in FEATURE_COLUMNS
        ],
        "output_features": [_output_feature(cfg, target_col)],
        "combiner": {"type": "concat", "output_size": hp.hidden_size},
        "trainer": {
            "epochs": hp.epochs,
            "batch_size": hp.batch_size,
            "learning_rate": hp.learning_rate,
            "early_stop": 5,
        },
        "preprocessing": {"split": _split_config(cfg)},
    }


# Column holding precomputed partition ids for Ludwig's `fixed` split
# (0 = train, 1 = validation, 2 = test).
SPLIT_COLUMN = "split"


def _split_config(cfg: TrainingConfig) -> dict[str, Any]:
    if cfg.dataset.split == "scaffold":
        # Ludwig has no scaffold splitter; the trainer computes Bemis–Murcko
        # partitions (splits.scaffold_split) into SPLIT_COLUMN.
        return {"type": "fixed", "column": SPLIT_COLUMN}
    if cfg.dataset.split == "random":
        return {"type": "random",
                "probabilities": [1 - cfg.dataset.val_frac - cfg.dataset.test_frac,
                                  cfg.dataset.val_frac, cfg.dataset.test_frac]}
    raise ValueError(f"unsupported split '{cfg.dataset.split}'")


def add_split_column(df, cfg: TrainingConfig) -> dict[str, Any]:
    """Write SPLIT_COLUMN for a scaffold split; return the split metadata.

    For split='random' Ludwig performs the split itself, so only the method
    and requested fractions are recorded.
    """
    spec = cfg.dataset
    if spec.split == "random":
        return {"requested": "random", "method": "ludwig_random",
                "seed": cfg.hyperparams.seed, "fractions":
                [1 - spec.val_frac - spec.test_frac, spec.val_frac, spec.test_frac]}
    from .splits import scaffold_split
    result = scaffold_split(list(df["_smiles"]), spec.val_frac, spec.test_frac,
                            cfg.hyperparams.seed)
    part = [0] * len(df)
    for i in result.val:
        part[i] = 1
    for i in result.test:
        part[i] = 2
    df[SPLIT_COLUMN] = part
    return result.metadata()


def to_ludwig_llm_config(cfg: TrainingConfig) -> dict[str, Any]:
    """Build a Ludwig LLM fine-tuning config (model_type=ludwig_llm).

    Ludwig natively supports LLM fine-tuning declaratively: a text input feature
    (the instruction) → a text output feature (the response), fine-tuned on a
    base model with a LoRA/QLoRA adapter. This is the same low-code contract as
    the tabular path — the user names a base model + points at instruction/output
    columns, and Ludwig does the training. QLoRA (4-bit) keeps it feasible on
    modest hardware; LoRA/full-finetune scale up with GPU.
    """
    llm = cfg.llm
    if llm is None:
        raise ValueError("to_ludwig_llm_config requires cfg.llm (LLMSpec)")
    hp = cfg.hyperparams
    config: dict[str, Any] = {
        "model_type": "llm",
        "base_model": llm.base_model,
        "input_features": [{"name": llm.instruction_col, "type": "text"}],
        "output_features": [{"name": llm.output_col, "type": "text"}],
        "prompt": {"template": "{" + llm.instruction_col + "}"},
        "trainer": {
            "type": "finetune",
            "epochs": hp.epochs,
            "batch_size": hp.batch_size,
            "learning_rate": hp.learning_rate,
        },
        "preprocessing": {"global_max_sequence_length": llm.max_sequence_length,
                          "split": _split_config(cfg)},
    }
    if llm.adapter in ("lora", "qlora"):
        config["adapter"] = {"type": "lora"}
    if llm.adapter == "qlora" and llm.quantization_bits:
        config["quantization"] = {"bits": llm.quantization_bits}
    return config


def featurize_smiles_df(smiles: list[str], labels: list[float] | None,
                        target_col: str = "y"):
    """SMILES → pandas DataFrame of RDKit descriptors (+ optional target).

    Lazy-imports rdkit/pandas so importing this module stays dependency-free.
    Invalid SMILES are dropped (with their label) to keep rows aligned.
    """
    import pandas as pd
    from rdkit import Chem
    from rdkit.Chem import Descriptors

    def _feat(smi: str):
        mol = Chem.MolFromSmiles(smi)
        if mol is None:
            return None
        return {
            "MolWt": Descriptors.MolWt(mol),
            "MolLogP": Descriptors.MolLogP(mol),
            "NumHDonors": Descriptors.NumHDonors(mol),
            "NumHAcceptors": Descriptors.NumHAcceptors(mol),
            "TPSA": Descriptors.TPSA(mol),
            "NumRotatableBonds": Descriptors.NumRotatableBonds(mol),
        }

    rows = []
    for i, smi in enumerate(smiles):
        f = _feat(smi)
        if f is None:
            continue
        if labels is not None:
            f[target_col] = labels[i]
        f["_smiles"] = smi
        rows.append(f)
    return pd.DataFrame(rows)
