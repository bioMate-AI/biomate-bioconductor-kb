"""Dep-free unit tests for the single-cell expression-diffusion path
(model_type=scrna_diffusion, framework scDiffusion/CFGen).

These exercise config validation, param-form, CLI arg mapping, routing, and
executor image selection WITHOUT importing torch/scanpy/scDiffusion (the real
fit runs in the separate sc-diffusion-training GPU image — a deferred step)."""
import pytest

from galaxy.ai.ml_training.config import (
    TrainingConfig, DatasetSpec, SCDiffusionSpec, ConfigError,
    MODEL_TYPES, TASK_TYPES, DIFFUSION_MODEL_TYPES, LLM_MODEL_TYPES,
    SC_DIFFUSION_FRAMEWORKS, NOISE_SCHEDULES,
)
from galaxy.ai.ml_training.routing import (
    detect_training_intent, extract_training_config, route_ml_training,
)
from galaxy.ai.ml_training.cli import _build_parser, build_config_from_args
from galaxy.ai.ml_training.executor_payload import _resolve_container, build_execute_request


def _sc_cfg(**over):
    base = dict(name="sc gen", task_type="expression_generation",
                model_type="scrna_diffusion",
                dataset=DatasetSpec(name="fixture:pbmc_h5ad", split="random"),
                sc=SCDiffusionSpec(finetune=False))
    base.update(over)
    return TrainingConfig(**base)


# --- config ---------------------------------------------------------------
def test_diffusion_type_registered():
    assert "scrna_diffusion" in MODEL_TYPES
    assert "expression_generation" in TASK_TYPES
    # scrna_diffusion is a member of the diffusion family; the family also carries
    # the sibling protein_diffusion type — assert membership, not sole occupancy.
    assert "scrna_diffusion" in DIFFUSION_MODEL_TYPES
    # distinct family from the LLM/TRL family (clean merge)
    assert not (set(DIFFUSION_MODEL_TYPES) & set(LLM_MODEL_TYPES))


def test_scrna_config_validates_from_scratch():
    _sc_cfg().validate()


def test_scrna_config_validates_finetune_with_checkpoint():
    _sc_cfg(sc=SCDiffusionSpec(finetune=True, base_model="scimilarity_v1")).validate()


def test_scrna_requires_sc_spec():
    with pytest.raises(ConfigError):
        TrainingConfig(name="x", task_type="expression_generation",
                       model_type="scrna_diffusion",
                       dataset=DatasetSpec(name="fixture:pbmc_h5ad"), sc=None).validate()


def test_scrna_requires_expression_generation_task():
    with pytest.raises(ConfigError):
        _sc_cfg(task_type="classification").validate()


def test_finetune_without_checkpoint_rejected():
    # finetune=True but no base_checkpoint/base_model → invalid
    with pytest.raises(ConfigError):
        SCDiffusionSpec(finetune=True, base_checkpoint="", base_model="").validate()


def test_scdiffusion_spec_field_validation():
    with pytest.raises(ConfigError):
        SCDiffusionSpec(finetune=False, framework="not-a-fw").validate()
    with pytest.raises(ConfigError):
        SCDiffusionSpec(finetune=False, n_cells_to_generate=0).validate()
    with pytest.raises(ConfigError):
        SCDiffusionSpec(finetune=False, guidance_scale=0).validate()
    with pytest.raises(ConfigError):
        SCDiffusionSpec(finetune=False, diffusion_steps=0).validate()
    with pytest.raises(ConfigError):
        SCDiffusionSpec(finetune=False, noise_schedule="triangle").validate()
    for fw in SC_DIFFUSION_FRAMEWORKS:
        SCDiffusionSpec(finetune=False, framework=fw).validate()
    for ns in NOISE_SCHEDULES:
        SCDiffusionSpec(finetune=False, noise_schedule=ns).validate()


def test_roundtrip_preserves_sc_spec():
    cfg = _sc_cfg(sc=SCDiffusionSpec(finetune=True, base_model="scimilarity_v1",
                                     cell_type="B cell", guidance_scale=2.0))
    d = cfg.to_dict()
    cfg2 = TrainingConfig.from_dict(d)
    cfg2.validate()
    assert cfg2.to_dict() == d
    assert isinstance(cfg2.sc, SCDiffusionSpec)
    assert cfg2.sc.cell_type == "B cell"


# --- param form -----------------------------------------------------------
def test_ga_params_render_diffusion_card():
    ga = _sc_cfg().to_workflow_ga_params()
    req = {p["name"] for p in ga["required_params"]}
    assert "dataset" in req
    ds = next(p for p in ga["required_params"] if p["name"] == "dataset")
    assert "h5ad" in ds["label"].lower()
    opt = {p["name"] for p in ga["optional_params"]}
    assert {"framework", "finetune", "base_checkpoint", "base_model", "cell_type",
            "n_cells_to_generate", "guidance_scale", "diffusion_steps",
            "noise_schedule"} <= opt
    fw = next(p for p in ga["optional_params"] if p["name"] == "framework")
    assert set(SC_DIFFUSION_FRAMEWORKS) <= set(fw["allowed_values"])
    ft = next(p for p in ga["optional_params"] if p["name"] == "finetune")
    assert ft["type"] == "boolean"


def test_ga_stub_uses_diffusion_nf_path():
    ga = _sc_cfg().to_workflow_ga(nextflow_path="ml_training/scrna_diffusion_train.nf")
    assert ga["domain"] == "ml_training"
    assert ga["nextflow_path"] == "ml_training/scrna_diffusion_train.nf"


# --- routing --------------------------------------------------------------
@pytest.mark.parametrize("text", [
    "fine-tune a scRNA diffusion model to augment my lupus dataset",
    "train a single-cell diffusion model with scDiffusion",
    "generate cells with CFGen for rare cell type augmentation",
    "augment single-cell data using diffusion",
])
def test_diffusion_intent_detected(text):
    assert detect_training_intent(text) is True


def test_routing_maps_lupus_augment_to_scrna_diffusion():
    cfg = extract_training_config(
        "fine-tune a scRNA diffusion model to augment my lupus dataset")
    assert cfg.model_type == "scrna_diffusion"
    assert cfg.task_type == "expression_generation"
    assert cfg.sc is not None and cfg.sc.finetune is True
    assert cfg.sc.framework == "scdiffusion"


def test_routing_cfgen_selects_framework():
    cfg = extract_training_config("generate cells with CFGen to augment single-cell data")
    assert cfg.model_type == "scrna_diffusion"
    assert cfg.sc.framework == "cfgen"


def test_routing_from_scratch_when_no_finetune_signal():
    cfg = extract_training_config("generate single-cells with a diffusion model to augment single-cell data")
    assert cfg.model_type == "scrna_diffusion"
    assert cfg.sc.finetune is False


def test_route_ml_training_scrna_ga_uses_gpu_wrapper():
    ga = route_ml_training("fine-tune a scRNA diffusion model to augment my lupus dataset")
    assert ga is not None
    assert ga["nextflow_path"] == "ml_training/scrna_diffusion_train.nf"
    assert "scrna_diffusion" in ga["scientific_rationale"]


def test_non_diffusion_training_still_molecular_wrapper():
    ga = route_ml_training("train a classifier for hERG blockers")
    assert ga is not None
    assert ga["nextflow_path"] == "ml_training/chemprop_train.nf"


# --- cli ------------------------------------------------------------------
def test_cli_maps_scrna_diffusion_args():
    args = _build_parser().parse_args([
        "--dataset", "fixture:pbmc_h5ad", "--model-type", "scrna_diffusion",
        "--sc-framework", "scdiffusion", "--no-sc-finetune",
        "--sc-cell-type", "B cell", "--sc-guidance-scale", "2.5",
        "--sc-n-cells-to-generate", "500", "--sc-noise-schedule", "linear",
    ])
    cfg = build_config_from_args(args)
    assert cfg.model_type == "scrna_diffusion"
    assert cfg.task_type == "expression_generation"
    assert cfg.sc.finetune is False
    assert cfg.sc.cell_type == "B cell"
    assert cfg.sc.guidance_scale == 2.5
    assert cfg.sc.n_cells_to_generate == 500
    assert cfg.sc.noise_schedule == "linear"


def test_cli_finetune_default_true_needs_checkpoint():
    # default --sc-finetune True; a base_model is required or validate() raises
    args = _build_parser().parse_args([
        "--dataset", "fixture:pbmc_h5ad", "--model-type", "scrna_diffusion",
        "--sc-base-model", "scimilarity_v1",
    ])
    cfg = build_config_from_args(args)
    assert cfg.sc.finetune is True
    assert cfg.sc.base_model == "scimilarity_v1"


# --- executor image selection --------------------------------------------
def test_scrna_selects_sc_diffusion_image(monkeypatch):
    monkeypatch.delenv("SC_DIFFUSION_TRAINING_IMAGE", raising=False)
    assert "sc-diffusion-training" in _resolve_container(_sc_cfg())
    # other types don't get the sc image
    from galaxy.ai.ml_training.config import LLMSpec
    assert "sc-diffusion-training" not in _resolve_container(
        TrainingConfig(name="x", task_type="text_generation", model_type="ludwig_llm",
                       dataset=DatasetSpec(name="fixture:instruct", split="random"),
                       llm=LLMSpec()))


def test_sc_diffusion_image_env_override(monkeypatch):
    monkeypatch.setenv("SC_DIFFUSION_TRAINING_IMAGE", "myregistry/custom-sc:v1")
    assert _resolve_container(_sc_cfg()) == "myregistry/custom-sc:v1"


def test_execute_request_carries_sc_params():
    req = build_execute_request(_sc_cfg(), user_id="u1",
                                s3_dataset_uri="s3://b/cells.h5ad")
    p = req["parameters"]
    assert p["dataset"] == "s3://b/cells.h5ad"
    assert p["model_type"] == "scrna_diffusion"
    assert p["sc_framework"] == "scdiffusion"
    assert p["sc_finetune"] is False
    assert p["sc_n_cells_to_generate"] == 1000
    assert p["sc_noise_schedule"] == "cosine"
    assert "sc-diffusion-training" in req["compute_config"]["container"]
    # all params remain flat scalars (executor JSON-serializes lists/dicts)
    assert all(not isinstance(v, (list, dict)) for v in p.values())


# --- trainer harness (imports without torch/scanpy; real integration point) --
def test_trainer_imports_without_framework():
    # the module must import with zero heavy deps (lazy-import guard)
    from galaxy.ai.ml_training import scrna_diffusion_trainer as t
    assert hasattr(t, "train_scrna_diffusion")
    assert hasattr(t, "load_h5ad")
    assert hasattr(t, "marker_gene_fidelity")


def test_marker_gene_fidelity_computes_on_fake_anndata():
    np = pytest.importorskip("numpy")
    from galaxy.ai.ml_training.scrna_diffusion_trainer import marker_gene_fidelity

    class _Fake:
        def __init__(self, X, genes):
            self.X = np.asarray(X, dtype=float)
            self.var_names = list(genes)

    real = _Fake([[1.0, 2.0], [3.0, 4.0]], ["g1", "g2"])
    gen = _Fake([[1.1, 2.1], [2.9, 3.9]], ["g1", "g2"])
    m = marker_gene_fidelity(real, gen)
    assert "marker_fidelity_frac" in m and "marker_mean_abs_diff" in m
    assert 0.0 <= m["marker_fidelity_frac"] <= 1.0
    assert m["marker_mean_abs_diff"] < 0.5
