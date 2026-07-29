"""Dep-free unit tests for the TRL preference/RL path (trl_dpo, trl_grpo).

These exercise config validation, dataset loaders, reward functions, routing,
CLI arg mapping, and executor image selection WITHOUT importing trl/torch (the
real training runs in the separate trl-training image, validated on Batch)."""
import pytest

from galaxy.ai.ml_training.config import (
    TrainingConfig, DatasetSpec, LLMSpec, ConfigError,
    MODEL_TYPES, LLM_MODEL_TYPES, TRL_MODEL_TYPES, REWARD_KINDS,
)
from galaxy.ai.ml_training.datasets import (
    load_preference_rows, load_prompt_rows, PREFERENCE_FIXTURE, PROMPT_FIXTURE,
)
from galaxy.ai.ml_training.routing import extract_training_config, route_ml_training
from galaxy.ai.ml_training.cli import _build_parser, build_config_from_args
from galaxy.ai.ml_training.executor_payload import _resolve_container, build_execute_request


def _dpo_cfg(**over):
    base = dict(name="dpo", task_type="text_generation", model_type="trl_dpo",
                dataset=DatasetSpec(name="fixture:preference", split="random"), llm=LLMSpec())
    base.update(over)
    return TrainingConfig(**base)


def _grpo_cfg(**over):
    base = dict(name="grpo", task_type="text_generation", model_type="trl_grpo",
                dataset=DatasetSpec(name="fixture:prompts", split="random"), llm=LLMSpec())
    base.update(over)
    return TrainingConfig(**base)


# --- config ---------------------------------------------------------------
def test_trl_types_registered():
    assert {"trl_dpo", "trl_grpo"} <= set(MODEL_TYPES)
    assert {"trl_dpo", "trl_grpo"} == set(TRL_MODEL_TYPES)
    assert set(TRL_MODEL_TYPES) <= set(LLM_MODEL_TYPES)


def test_dpo_grpo_configs_validate():
    _dpo_cfg().validate()
    _grpo_cfg().validate()


def test_trl_requires_llm_spec():
    with pytest.raises(ConfigError):
        TrainingConfig(name="x", task_type="text_generation", model_type="trl_dpo",
                       dataset=DatasetSpec(name="fixture:preference"), llm=None).validate()


def test_trl_requires_text_generation_task():
    with pytest.raises(ConfigError):
        _dpo_cfg(task_type="classification").validate()


def test_llmspec_rl_field_validation():
    with pytest.raises(ConfigError):
        LLMSpec(beta=0).validate()
    with pytest.raises(ConfigError):
        LLMSpec(num_generations=1).validate()
    with pytest.raises(ConfigError):
        LLMSpec(reward="not-a-reward").validate()
    for r in REWARD_KINDS:
        LLMSpec(reward=r).validate()


def test_ga_params_show_dpo_beta_and_grpo_reward():
    dpo_ga = _dpo_cfg().to_workflow_ga_params()
    opt_names = {p["name"] for p in dpo_ga["optional_params"]}
    assert "beta" in opt_names
    grpo_ga = _grpo_cfg().to_workflow_ga_params()
    grpo_names = {p["name"] for p in grpo_ga["optional_params"]}
    assert {"num_generations", "reward"} <= grpo_names


# --- datasets -------------------------------------------------------------
def test_preference_fixture_loads():
    rows = load_preference_rows(DatasetSpec(name="fixture:preference"))
    assert rows and rows == PREFERENCE_FIXTURE
    assert all({"prompt", "chosen", "rejected"} <= set(r) for r in rows)


def test_prompt_fixture_loads():
    rows = load_prompt_rows(DatasetSpec(name="fixture:prompts"))
    assert rows and rows == PROMPT_FIXTURE
    assert all("prompt" in r for r in rows)


def test_preference_jsonl_roundtrip(tmp_path):
    import json
    p = tmp_path / "pref.jsonl"
    p.write_text("\n".join(json.dumps(r) for r in PREFERENCE_FIXTURE))
    rows = load_preference_rows(DatasetSpec(path=str(p)))
    assert len(rows) == len(PREFERENCE_FIXTURE)


def test_prompt_csv_roundtrip(tmp_path):
    p = tmp_path / "prompts.csv"
    p.write_text("prompt\nhello world\nfoo bar\n")
    rows = load_prompt_rows(DatasetSpec(path=str(p)))
    assert [r["prompt"] for r in rows] == ["hello world", "foo bar"]


# --- reward functions (importing trl_trainer must not require trl) --------
def test_reward_functions():
    from galaxy.ai.ml_training.trl_trainer import make_reward_fn
    kw = make_reward_fn("keyword", "herg")
    assert kw(["hERG blocks the channel", "no match here"]) == [1.0, 0.0]
    num = make_reward_fn("numeric_answer")
    assert num(["the answer is 42", "no digits"]) == [1.0, 0.0]
    length = make_reward_fn("length")
    scores = length(["word " * 20, ""])
    assert scores[0] > scores[1]  # ~20 words scores higher than empty


# --- routing --------------------------------------------------------------
def test_routing_dpo_intent():
    cfg = extract_training_config("fine-tune an LLM with DPO on preference data")
    assert cfg.model_type == "trl_dpo"
    assert cfg.dataset.name == "fixture:preference"


def test_routing_grpo_intent():
    cfg = extract_training_config("train a language model with GRPO reinforcement learning")
    assert cfg.model_type == "trl_grpo"
    assert cfg.dataset.name == "fixture:prompts"


def test_routing_plain_llm_still_sft():
    cfg = extract_training_config("fine-tune an LLM on my instructions")
    assert cfg.model_type == "ludwig_llm"


def test_route_ml_training_dpo_ga():
    ga = route_ml_training("train an llm with dpo")
    assert ga is not None
    assert "trl_dpo" in ga["scientific_rationale"]


# --- cli ------------------------------------------------------------------
def test_cli_maps_trl_dpo_args():
    args = _build_parser().parse_args([
        "--dataset", "fixture:preference", "--model-type", "trl_dpo",
        "--base-model", "HuggingFaceTB/SmolLM2-135M-Instruct", "--beta", "0.2",
    ])
    cfg = build_config_from_args(args)
    assert cfg.model_type == "trl_dpo"
    assert cfg.task_type == "text_generation"
    assert cfg.llm.beta == 0.2


def test_cli_maps_trl_grpo_args():
    args = _build_parser().parse_args([
        "--dataset", "fixture:prompts", "--model-type", "trl_grpo",
        "--num-generations", "6", "--reward", "numeric_answer",
    ])
    cfg = build_config_from_args(args)
    assert cfg.model_type == "trl_grpo"
    assert cfg.llm.num_generations == 6
    assert cfg.llm.reward == "numeric_answer"


# --- executor image selection --------------------------------------------
def test_trl_types_select_trl_image(monkeypatch):
    monkeypatch.delenv("TRL_TRAINING_IMAGE", raising=False)
    assert "trl-training" in _resolve_container(_dpo_cfg())
    assert "trl-training" in _resolve_container(_grpo_cfg())
    assert "trl-training" not in _resolve_container(
        _dpo_cfg(model_type="ludwig_llm",
                 dataset=DatasetSpec(name="fixture:instruct", split="random")))


def test_trl_image_env_override(monkeypatch):
    monkeypatch.setenv("TRL_TRAINING_IMAGE", "myregistry/custom-trl:v1")
    assert _resolve_container(_grpo_cfg()) == "myregistry/custom-trl:v1"


def test_execute_request_carries_rl_params():
    req = build_execute_request(_grpo_cfg(), user_id="u1", s3_dataset_uri="s3://b/prompts.csv")
    params = req["parameters"]
    assert params["model_type"] == "trl_grpo"
    assert params["num_generations"] == 4
    assert params["reward"] == "length"
    assert "trl-training" in req["compute_config"]["container"]
