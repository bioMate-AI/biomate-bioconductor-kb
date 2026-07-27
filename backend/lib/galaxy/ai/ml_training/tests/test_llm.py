"""Unit tests for the LLM fine-tuning path (ludwig_llm)."""
import json

import pytest

from galaxy.ai.ml_training.config import (
    TrainingConfig, DatasetSpec, LLMSpec, Hyperparams, ConfigError, MODEL_TYPES, ADAPTERS,
)
from galaxy.ai.ml_training.ludwig_adapter import to_ludwig_llm_config
from galaxy.ai.ml_training.datasets import load_instruction_rows, INSTRUCT_FIXTURE
from galaxy.ai.ml_training.routing import extract_training_config, route_ml_training
from galaxy.ai.ml_training.cli import _build_parser, build_config_from_args


def _llm_cfg(**over):
    base = dict(name="instruct LLM", task_type="text_generation", model_type="ludwig_llm",
                dataset=DatasetSpec(name="fixture:instruct", split="random"), llm=LLMSpec())
    base.update(over)
    return TrainingConfig(**base)


# --- config ---------------------------------------------------------------
def test_ludwig_llm_is_valid_model_type():
    assert "ludwig_llm" in MODEL_TYPES
    _llm_cfg().validate()


def test_ludwig_llm_requires_llm_spec():
    with pytest.raises(ConfigError):
        TrainingConfig(name="x", task_type="text_generation", model_type="ludwig_llm",
                       dataset=DatasetSpec(name="fixture:instruct", split="random")).validate()


def test_ludwig_llm_requires_text_generation_task():
    with pytest.raises(ConfigError):
        _llm_cfg(task_type="classification").validate()


def test_llmspec_validation():
    with pytest.raises(ConfigError):
        LLMSpec(base_model=" ").validate()
    with pytest.raises(ConfigError):
        LLMSpec(adapter="magic").validate()
    with pytest.raises(ConfigError):
        LLMSpec(quantization_bits=3).validate()


def test_config_roundtrip_with_llm():
    cfg = _llm_cfg()
    d = cfg.to_dict()
    cfg2 = TrainingConfig.from_dict(d)
    cfg2.validate()
    assert isinstance(cfg2.llm, LLMSpec)
    assert cfg2.to_dict() == d


def test_workflow_ga_params_llm_shows_base_model_and_text_cols():
    params = _llm_cfg().to_workflow_ga_params()
    req = {p["name"] for p in params["required_params"]}
    assert req == {"dataset", "base_model"}
    opt = {p["name"] for p in params["optional_params"]}
    assert {"adapter", "instruction_col", "output_col", "max_sequence_length"} <= opt
    adapter = next(p for p in params["optional_params"] if p["name"] == "adapter")
    assert set(ADAPTERS) <= set(adapter["allowed_values"])


# --- adapter --------------------------------------------------------------
def test_to_ludwig_llm_config_shape():
    lc = to_ludwig_llm_config(_llm_cfg())          # default adapter = lora (CPU)
    assert lc["model_type"] == "llm"
    assert lc["base_model"] == "HuggingFaceTB/SmolLM2-135M-Instruct"
    assert lc["input_features"] == [{"name": "instruction", "type": "text"}]
    assert lc["output_features"] == [{"name": "output", "type": "text"}]
    assert lc["adapter"] == {"type": "lora"}
    assert "quantization" not in lc                 # lora default = no quant (CPU)


def test_qlora_adds_quantization():
    lc = to_ludwig_llm_config(_llm_cfg(llm=LLMSpec(adapter="qlora", quantization_bits=4)))
    assert lc["adapter"] == {"type": "lora"}
    assert lc["quantization"] == {"bits": 4}


def test_no_adapter_full_finetune():
    lc = to_ludwig_llm_config(_llm_cfg(llm=LLMSpec(adapter="none")))
    assert "adapter" not in lc


def test_llm_config_validates_against_ludwig_schema():
    pytest.importorskip("ludwig")
    from ludwig.schema.model_config import ModelConfig
    mc = ModelConfig.from_dict(to_ludwig_llm_config(_llm_cfg()))
    assert mc.model_type == "llm"


# --- instruction dataset --------------------------------------------------
def test_instruction_fixture_loads():
    rows = load_instruction_rows(DatasetSpec(name="fixture:instruct", split="random"))
    assert len(rows) == len(INSTRUCT_FIXTURE)
    assert all("instruction" in r and "output" in r for r in rows)


def test_instruction_jsonl_load(tmp_path):
    p = tmp_path / "d.jsonl"
    p.write_text('{"instruction":"hi","output":"hello"}\n{"instruction":"bye","output":"ciao"}\n')
    rows = load_instruction_rows(DatasetSpec(path=str(p), split="random"))
    assert rows == [{"instruction": "hi", "output": "hello"},
                    {"instruction": "bye", "output": "ciao"}]


def test_instruction_unknown_named_rejected():
    with pytest.raises(ConfigError):
        load_instruction_rows(DatasetSpec(name="nonsense:x", split="random"))


# --- routing --------------------------------------------------------------
@pytest.mark.parametrize("text", [
    "fine-tune an LLM on my instructions",
    "train a language model",
    "instruction-tune a chat model",
    "fine-tune llama on my data",
])
def test_llm_intent_routes_to_ludwig_llm(text):
    cfg = extract_training_config(text)
    assert cfg.model_type == "ludwig_llm"
    assert cfg.task_type == "text_generation"
    assert cfg.llm is not None


def test_molecular_training_still_not_llm():
    cfg = extract_training_config("train a classifier for hERG blockers")
    assert cfg.model_type == "ludwig_tabular"


def test_route_llm_returns_workflow_ga():
    ga = route_ml_training("fine-tune an LLM on my instruction data")
    assert ga is not None and ga["domain"] == "ml_training"
    assert any(p["name"] == "base_model" for p in ga["required_params"])


# --- CLI ------------------------------------------------------------------
def test_cli_llm_args_build_llmspec():
    args = _build_parser().parse_args([
        "--dataset", "fixture:instruct", "--model-type", "ludwig_llm",
        "--base-model", "HuggingFaceTB/SmolLM2-135M-Instruct", "--adapter", "qlora",
    ])
    cfg = build_config_from_args(args)
    assert cfg.model_type == "ludwig_llm"
    assert cfg.task_type == "text_generation"     # coerced
    assert cfg.llm.base_model.endswith("SmolLM2-135M-Instruct")
    assert cfg.dataset.split == "random"
