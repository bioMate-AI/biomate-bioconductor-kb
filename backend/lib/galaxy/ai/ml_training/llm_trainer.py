"""
LLM fine-tuning entrypoint — real Ludwig LoRA/QLoRA, declarative.

Fine-tunes a base LLM on an instruction/response dataset via Ludwig's native
LLM support (model_type=llm + LoRA adapter). Lazy-imports ludwig so the module
loads without it; the unit tests validate the config against Ludwig's schema
(no training) and monkeypatch the trainer. Real fine-tuning needs the LLM
extras (peft/bitsandbytes/transformers/accelerate — shipped in the ml-training
image) and, for anything beyond a tiny model, a GPU.

Produces the same TrainingResult contract + manifest as the other trainers, so
it plugs into the orchestrator, QC gate, and serving unchanged.
"""
from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from .config import TrainingConfig
from .datasets import LoadedDataset
from .chemprop_trainer import TrainingResult
from .ludwig_adapter import to_ludwig_llm_config

log = logging.getLogger(__name__)


def train_ludwig_llm(cfg: TrainingConfig, ds: LoadedDataset, artifact_dir: str) -> TrainingResult:
    """Fine-tune an LLM with Ludwig. `ds` is ignored — LLM data is loaded here
    from cfg.dataset via load_instruction_rows (instruction/output text)."""
    try:
        from ludwig.api import LudwigModel
    except ImportError as e:
        raise ImportError(
            "ludwig (with LLM extras: peft/bitsandbytes/transformers) is required "
            "for model_type=ludwig_llm. Runs in the ml-training image."
        ) from e
    import pandas as pd
    from .datasets import load_instruction_rows

    llm = cfg.llm
    rows = load_instruction_rows(cfg.dataset, llm.instruction_col, llm.output_col)
    if len(rows) < 2:
        raise ValueError(f"too few instruction rows to fine-tune ({len(rows)})")
    df = pd.DataFrame(rows)

    config = to_ludwig_llm_config(cfg)
    log.info("[ludwig-llm] fine-tuning %s on %s: %d rows, %d epochs, adapter=%s",
             cfg.name, llm.base_model, len(df), cfg.hyperparams.epochs, llm.adapter)

    model = LudwigModel(config, logging_level=logging.ERROR)
    train_stats, _, _ = model.train(
        dataset=df,
        output_directory=str(Path(artifact_dir) / "ludwig_llm_run"),
        skip_save_processed_input=True,
    )

    metrics = _extract_llm_metrics(train_stats, llm.output_col)

    model_dir = str(Path(artifact_dir) / "llm_model")
    model.save(model_dir)

    import ludwig as _lud
    result = TrainingResult(
        model_type="ludwig_llm", artifact_dir=artifact_dir, metrics=metrics,
        n_train=len(df), n_val=0, n_test=0,
        framework_version=f"ludwig=={getattr(getattr(_lud,'globals',None),'LUDWIG_VERSION', getattr(_lud,'__version__','?'))}",
        extra={"model_dir": model_dir, "base_model": llm.base_model,
               "adapter": llm.adapter, "task": "text_generation"},
    )
    _write_manifest(artifact_dir, cfg, result)
    return result


def _extract_llm_metrics(train_stats: Any, output_col: str) -> dict[str, float]:
    """Pull the last-epoch loss/perplexity from Ludwig's TrainingStats."""
    metrics: dict[str, float] = {}

    def _split(name: str) -> dict:
        sub = getattr(train_stats, name, None)
        if sub is None and isinstance(train_stats, dict):
            sub = train_stats.get(name)
        return (sub or {}).get(output_col, {}) if sub else {}

    try:
        for split_name, prefix in (("test", "test"), ("validation", "val"), ("training", "train")):
            s = _split(split_name)
            for key in ("loss", "perplexity", "next_token_perplexity"):
                if s.get(key):
                    metrics[f"{prefix}_{key}"] = float(s[key][-1])
            if metrics:
                break
    except Exception as e:  # metrics extraction must never crash a good run
        log.warning("[ludwig-llm] metric extraction failed: %s", e)
    return metrics


def _write_manifest(artifact_dir: str, cfg: TrainingConfig, result: TrainingResult) -> None:
    (Path(artifact_dir) / "manifest.json").write_text(json.dumps({
        "name": cfg.name, "model_type": result.model_type, "task_type": cfg.task_type,
        "metrics": result.metrics, "framework_version": result.framework_version,
        "extra": result.extra,
    }, indent=2))
