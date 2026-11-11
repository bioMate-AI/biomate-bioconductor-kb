"""Dep-free unit tests for the generic tabular-diffusion path
(model_type=tabular_diffusion, framework TabDDPM/TabSyn).

These exercise config validation, param-form, CLI arg mapping, and executor image
selection WITHOUT importing torch/pandas/tab-ddpm (the real fit runs in the
separate tabular-diffusion-training GPU image — a deferred step).

Routing (chat NLP → tabular_diffusion) is intentionally NOT wired for this type
(see the session hand-back): the generative tabular entry point is the Models UI
SpecSetup panel, and a dedicated Nextflow wrapper under nextflow_nfcore/** is
out of scope here. So there are no routing assertions below (unlike
test_scrna_diffusion.py)."""
import pytest

from galaxy.ai.ml_training.config import (
    TrainingConfig, DatasetSpec, TabularDiffusionSpec, ConfigError,
    MODEL_TYPES, TASK_TYPES, DIFFUSION_MODEL_TYPES, LLM_MODEL_TYPES,
    TABULAR_DIFFUSION_FRAMEWORKS, NOISE_SCHEDULES,
)
from galaxy.ai.ml_training.cli import _build_parser, build_config_from_args
from galaxy.ai.ml_training.executor_payload import _resolve_container, build_execute_request


def _tab_cfg(**over):
    base = dict(name="tab gen", task_type="tabular_generation",
                model_type="tabular_diffusion",
                dataset=DatasetSpec(name="fixture:features_csv", split="random"),
                tabular=TabularDiffusionSpec(finetune=False))
    base.update(over)
    return TrainingConfig(**base)


# --- config ---------------------------------------------------------------
def test_tabular_diffusion_type_registered():
    assert "tabular_diffusion" in MODEL_TYPES
    assert "tabular_generation" in TASK_TYPES
    # tabular_diffusion is a member of the diffusion family alongside the
    # protein/scrna siblings — assert membership, not sole occupancy.
    assert "tabular_diffusion" in DIFFUSION_MODEL_TYPES
    # distinct family from the LLM/TRL family (clean merge)
    assert not (set(DIFFUSION_MODEL_TYPES) & set(LLM_MODEL_TYPES))


def test_tabular_config_validates_from_scratch():
    _tab_cfg().validate()


def test_tabular_config_validates_finetune_with_checkpoint():
    _tab_cfg(tabular=TabularDiffusionSpec(finetune=True, base_checkpoint="tabddpm_v1")).validate()


def test_tabular_requires_tabular_spec():
    with pytest.raises(ConfigError):
        TrainingConfig(name="x", task_type="tabular_generation",
                       model_type="tabular_diffusion",
                       dataset=DatasetSpec(name="fixture:features_csv"), tabular=None).validate()


def test_tabular_requires_tabular_generation_task():
    with pytest.raises(ConfigError):
        _tab_cfg(task_type="classification").validate()


def test_finetune_without_checkpoint_rejected():
    # finetune=True but no base_checkpoint → invalid
    with pytest.raises(ConfigError):
        TabularDiffusionSpec(finetune=True, base_checkpoint="").validate()


def test_tabular_spec_field_validation():
    with pytest.raises(ConfigError):
        TabularDiffusionSpec(finetune=False, framework="not-a-fw").validate()
    with pytest.raises(ConfigError):
        TabularDiffusionSpec(finetune=False, n_rows_to_generate=0).validate()
    with pytest.raises(ConfigError):
        TabularDiffusionSpec(finetune=False, guidance_scale=0).validate()
    with pytest.raises(ConfigError):
        TabularDiffusionSpec(finetune=False, diffusion_steps=0).validate()
    with pytest.raises(ConfigError):
        TabularDiffusionSpec(finetune=False, noise_schedule="triangle").validate()
    for fw in TABULAR_DIFFUSION_FRAMEWORKS:
        TabularDiffusionSpec(finetune=False, framework=fw).validate()
    for ns in NOISE_SCHEDULES:
        TabularDiffusionSpec(finetune=False, noise_schedule=ns).validate()


def test_roundtrip_preserves_tabular_spec():
    cfg = _tab_cfg(tabular=TabularDiffusionSpec(finetune=True, base_checkpoint="tabddpm_v1",
                                                target_column="label", guidance_scale=2.0))
    d = cfg.to_dict()
    cfg2 = TrainingConfig.from_dict(d)
    cfg2.validate()
    assert cfg2.to_dict() == d
    assert isinstance(cfg2.tabular, TabularDiffusionSpec)
    assert cfg2.tabular.target_column == "label"


# --- param form (params_schema presence) ----------------------------------
def test_ga_params_render_tabular_card():
    ga = _tab_cfg().to_workflow_ga_params()
    req = {p["name"] for p in ga["required_params"]}
    assert "dataset" in req
    ds = next(p for p in ga["required_params"] if p["name"] == "dataset")
    assert "tabular" in ds["label"].lower() or "csv" in ds["label"].lower()
    opt = {p["name"] for p in ga["optional_params"]}
    assert {"framework", "finetune", "base_checkpoint", "target_column",
            "n_rows_to_generate", "guidance_scale", "diffusion_steps",
            "noise_schedule"} <= opt
    fw = next(p for p in ga["optional_params"] if p["name"] == "framework")
    assert set(TABULAR_DIFFUSION_FRAMEWORKS) <= set(fw["allowed_values"])
    ft = next(p for p in ga["optional_params"] if p["name"] == "finetune")
    assert ft["type"] == "boolean"


def test_ga_stub_passes_nextflow_path():
    ga = _tab_cfg().to_workflow_ga(nextflow_path="ml_training/chemprop_train.nf")
    assert ga["domain"] == "ml_training"
    assert ga["nextflow_path"] == "ml_training/chemprop_train.nf"


# --- cli ------------------------------------------------------------------
def test_cli_maps_tabular_diffusion_args():
    args = _build_parser().parse_args([
        "--dataset", "fixture:features_csv", "--model-type", "tabular_diffusion",
        "--tab-framework", "tabddpm", "--no-tab-finetune",
        "--tab-target-column", "subtype", "--tab-guidance-scale", "2.5",
        "--tab-n-rows-to-generate", "500", "--tab-noise-schedule", "linear",
    ])
    cfg = build_config_from_args(args)
    assert cfg.model_type == "tabular_diffusion"
    assert cfg.task_type == "tabular_generation"
    assert cfg.tabular.finetune is False
    assert cfg.tabular.target_column == "subtype"
    assert cfg.tabular.guidance_scale == 2.5
    assert cfg.tabular.n_rows_to_generate == 500
    assert cfg.tabular.noise_schedule == "linear"


def test_cli_finetune_default_true_needs_checkpoint():
    # default --tab-finetune True; a base_checkpoint is required or validate() raises
    args = _build_parser().parse_args([
        "--dataset", "fixture:features_csv", "--model-type", "tabular_diffusion",
        "--tab-base-checkpoint", "tabddpm_v1",
    ])
    cfg = build_config_from_args(args)
    assert cfg.tabular.finetune is True
    assert cfg.tabular.base_checkpoint == "tabddpm_v1"


# --- executor image selection --------------------------------------------
def test_tabular_selects_tabular_diffusion_image(monkeypatch):
    monkeypatch.delenv("TABULAR_DIFFUSION_TRAINING_IMAGE", raising=False)
    assert "tabular-diffusion-training" in _resolve_container(_tab_cfg())
    # other types don't get the tabular image
    from galaxy.ai.ml_training.config import LLMSpec
    assert "tabular-diffusion-training" not in _resolve_container(
        TrainingConfig(name="x", task_type="text_generation", model_type="ludwig_llm",
                       dataset=DatasetSpec(name="fixture:instruct", split="random"),
                       llm=LLMSpec()))


def test_tabular_diffusion_image_env_override(monkeypatch):
    monkeypatch.setenv("TABULAR_DIFFUSION_TRAINING_IMAGE", "myregistry/custom-tab:v1")
    assert _resolve_container(_tab_cfg()) == "myregistry/custom-tab:v1"


def test_execute_request_carries_tabular_params():
    req = build_execute_request(_tab_cfg(), user_id="u1",
                                s3_dataset_uri="s3://b/rows.csv")
    p = req["parameters"]
    assert p["dataset"] == "s3://b/rows.csv"
    assert p["model_type"] == "tabular_diffusion"
    assert p["tab_framework"] == "tabddpm"
    assert p["tab_finetune"] is False
    assert p["tab_n_rows_to_generate"] == 1000
    assert p["tab_noise_schedule"] == "cosine"
    assert "tabular-diffusion-training" in req["compute_config"]["container"]
    # all params remain flat scalars (executor JSON-serializes lists/dicts)
    assert all(not isinstance(v, (list, dict)) for v in p.values())


# --- trainer harness (imports without torch/pandas; real integration point) --
def test_trainer_imports_without_framework():
    # the module must import with zero heavy deps (lazy-import guard)
    from galaxy.ai.ml_training import tabular_diffusion_trainer as t
    assert hasattr(t, "train_tabular_diffusion")
    assert hasattr(t, "load_table")
    assert hasattr(t, "column_distribution_fidelity")
    # the required GPU image is named for ops (no crash-stub)
    assert t.TABULAR_DIFFUSION_IMAGE == "biomate/tabular-diffusion-training:latest"


def test_run_tabddpm_raises_named_error_when_framework_absent():
    # With tab-ddpm not installed, the integration point must raise an informative
    # error naming the required image — NOT a bare NotImplementedError, NOT a crash
    # at module load.
    from galaxy.ai.ml_training.tabular_diffusion_trainer import _run_tabddpm
    with pytest.raises((ImportError, NotImplementedError)) as exc:
        _run_tabddpm(_tab_cfg(), TabularDiffusionSpec(finetune=False), object(), 3, "/tmp/x")
    assert "tabular-diffusion-training" in str(exc.value)


def test_column_distribution_fidelity_computes_on_fake_frame():
    # numpy-only fake frame (no real pandas) — mirrors test_scrna_diffusion's _Fake
    # AnnData so the metric is exercised without the heavy/ABI-sensitive pandas.
    np = pytest.importorskip("numpy")
    from galaxy.ai.ml_training.tabular_diffusion_trainer import column_distribution_fidelity

    class _FakeFrame:
        def __init__(self, cols):
            self._cols = {k: np.asarray(v, dtype=float) for k, v in cols.items()}
            self.columns = list(cols)

        def __getitem__(self, key):
            return self._cols[key]

    real = _FakeFrame({"a": [1.0, 3.0], "b": [2.0, 4.0]})
    gen = _FakeFrame({"a": [1.1, 2.9], "b": [2.1, 3.9]})
    m = column_distribution_fidelity(real, gen)
    assert "column_fidelity_frac" in m and "column_mean_abs_diff" in m
    assert 0.0 <= m["column_fidelity_frac"] <= 1.0
    assert m["column_mean_abs_diff"] < 0.5
