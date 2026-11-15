"""Dep-free unit tests for the protein/peptide structure-diffusion path.

These exercise config validation, the DiffusionSpec, the structure-set loader,
conditioning assembly, routing, CLI arg mapping, param-form, weight staging,
and executor image selection WITHOUT importing rfdiffusion/torch (the real
design loop runs in the diffusion-training GPU image)."""
from pathlib import Path
from unittest.mock import patch

import pytest

from galaxy.ai.ml_training.config import (
    TrainingConfig, DatasetSpec, DiffusionSpec, ConfigError,
    MODEL_TYPES, TASK_TYPES, DIFFUSION_MODEL_TYPES, DIFFUSION_FRAMEWORKS,
    NOISE_SCHEDULES,
)
from galaxy.ai.ml_training.routing import (
    detect_training_intent, extract_training_config, route_ml_training,
)
from galaxy.ai.ml_training.cli import _build_parser, build_config_from_args
from galaxy.ai.ml_training.executor_payload import (
    _resolve_container, build_execute_request, resolve_ml_training_container,
)


def _diff_cfg(**over):
    base = dict(name="FcRn binder", task_type="structure_generation",
                model_type="protein_diffusion",
                dataset=DatasetSpec(name="fixture:structures", split="random"),
                diffusion=DiffusionSpec())
    base.update(over)
    return TrainingConfig(**base)


# --- config ---------------------------------------------------------------
def test_diffusion_type_registered():
    assert "protein_diffusion" in MODEL_TYPES
    assert "structure_generation" in TASK_TYPES
    # protein_diffusion is a member of the diffusion family; the family may also
    # carry a sibling type (scrna_diffusion) — assert membership, not sole occupancy.
    assert "protein_diffusion" in DIFFUSION_MODEL_TYPES


def test_diffusion_config_validates():
    _diff_cfg().validate()


def test_diffusion_requires_diffusion_spec():
    with pytest.raises(ConfigError):
        TrainingConfig(name="x", task_type="structure_generation",
                       model_type="protein_diffusion",
                       dataset=DatasetSpec(name="fixture:structures"),
                       diffusion=None).validate()


def test_diffusion_requires_structure_generation_task():
    with pytest.raises(ConfigError):
        _diff_cfg(task_type="classification").validate()


def test_diffusionspec_field_validation():
    with pytest.raises(ConfigError):
        DiffusionSpec(framework="alphafold").validate()
    with pytest.raises(ConfigError):
        DiffusionSpec(length_min=100, length_max=50).validate()
    with pytest.raises(ConfigError):
        DiffusionSpec(num_designs=0).validate()
    with pytest.raises(ConfigError):
        DiffusionSpec(diffusion_steps=0).validate()
    with pytest.raises(ConfigError):
        DiffusionSpec(noise_schedule="quadratic").validate()
    with pytest.raises(ConfigError):
        DiffusionSpec(finetune=True, base_checkpoint="  ").validate()
    # from-scratch does not require a checkpoint
    DiffusionSpec(finetune=False, base_checkpoint="").validate()
    for fw in DIFFUSION_FRAMEWORKS:
        DiffusionSpec(framework=fw).validate()
    for ns in NOISE_SCHEDULES:
        DiffusionSpec(noise_schedule=ns).validate()


def test_diffusion_roundtrip_to_from_dict():
    cfg = _diff_cfg()
    d = cfg.to_dict()
    cfg2 = TrainingConfig.from_dict(d)
    cfg2.validate()
    assert cfg2.to_dict() == d
    assert isinstance(cfg2.diffusion, DiffusionSpec)


def test_ga_params_show_diffusion_fields():
    ga = _diff_cfg().to_workflow_ga_params()
    req_names = {p["name"] for p in ga["required_params"]}
    assert {"dataset", "framework"} <= req_names
    opt_names = {p["name"] for p in ga["optional_params"]}
    assert {"finetune", "base_checkpoint", "hotspot_residues", "contig",
            "num_designs", "diffusion_steps", "noise_schedule"} <= opt_names
    # framework is a select exposing allowed_values for the dropdown
    fw = next(p for p in ga["required_params"] if p["name"] == "framework")
    assert fw["type"] == "select"
    assert set(DIFFUSION_FRAMEWORKS) <= set(fw["allowed_values"])


# --- structure-set loader + conditioning ----------------------------------
def test_load_structure_set_fixture():
    from galaxy.ai.ml_training.diffusion_trainer import load_structure_set
    files = load_structure_set("fixture:structures")
    assert len(files) == 1 and files[0].endswith(".pdb")
    from pathlib import Path
    assert "ATOM" in Path(files[0]).read_text()


def test_load_structure_set_directory(tmp_path):
    from galaxy.ai.ml_training.diffusion_trainer import load_structure_set
    (tmp_path / "a.pdb").write_text("ATOM\nEND\n")
    (tmp_path / "b.cif").write_text("data_x\n")
    (tmp_path / "notes.md").write_text("ignore me")
    files = load_structure_set(str(tmp_path))
    assert len(files) == 2
    assert all(f.endswith((".pdb", ".cif")) for f in files)


def test_load_structure_set_manifest(tmp_path):
    from galaxy.ai.ml_training.diffusion_trainer import load_structure_set
    (tmp_path / "s1.pdb").write_text("ATOM\n")
    manifest = tmp_path / "set.txt"
    manifest.write_text(f"{tmp_path/'s1.pdb'}\n")
    files = load_structure_set(str(manifest))
    assert files == [str(tmp_path / "s1.pdb")]


def test_load_structure_set_missing_raises():
    from galaxy.ai.ml_training.diffusion_trainer import load_structure_set
    with pytest.raises(ValueError):
        load_structure_set("/no/such/path/here")


def test_conditioning_assembly_maps_spec_to_rfdiffusion():
    from galaxy.ai.ml_training.diffusion_trainer import _build_rfdiffusion_conditioning
    cfg = _diff_cfg(diffusion=DiffusionSpec(
        contig="10-40/A20-30/10-40", hotspot_residues="A30,A33,A34",
        target_pdb="target.pdb", diffusion_steps=25, num_designs=4,
        noise_schedule="cosine"))
    cond = _build_rfdiffusion_conditioning(cfg)
    assert cond["contigmap.contigs"] == ["10-40/A20-30/10-40"]
    assert cond["ppi.hotspot_res"] == ["A30", "A33", "A34"]
    assert cond["inference.input_pdb"] == "target.pdb"
    assert cond["diffuser.T"] == 25
    assert cond["inference.num_designs"] == 4
    assert cond["diffuser.schedule_type"] == "cosine"


def test_train_diffusion_defers_without_framework(tmp_path, monkeypatch):
    """HONESTY: absent rfdiffusion+weights, the trainer raises an informative
    NotImplementedError — it does NOT fabricate a trained checkpoint/metrics."""
    import builtins
    from galaxy.ai.ml_training.diffusion_trainer import train_diffusion
    from galaxy.ai.ml_training.datasets import LoadedDataset
    # Host may have a broken torch that aborts on import; force ImportError so
    # this unit test exercises the lazy-import deferral path only.
    real_import = builtins.__import__

    def _deny_gpu_stack(name, globals=None, locals=None, fromlist=(), level=0):
        if name == "torch" or name == "rfdiffusion" or name.startswith(
            ("torch.", "rfdiffusion.")
        ):
            raise ImportError(f"blocked {name} for deferral unit test")
        return real_import(name, globals, locals, fromlist, level)

    monkeypatch.setattr(builtins, "__import__", _deny_gpu_stack)
    cfg = _diff_cfg(dataset=DatasetSpec(name="fixture:structures", split="random"))
    ph = LoadedDataset([], "structure", "none", source="ph")
    with pytest.raises(NotImplementedError) as ei:
        train_diffusion(cfg, ph, str(tmp_path))
    assert "diffusion-training" in str(ei.value)


def test_ensure_weights_uses_existing_file(tmp_path, monkeypatch):
    from galaxy.ai.ml_training import diffusion_trainer as dt
    monkeypatch.setenv("DIFFUSION_WEIGHTS_DIR", str(tmp_path))
    ckpt = tmp_path / "Base_ckpt.pt"
    ckpt.write_bytes(b"fake-ckpt-bytes")
    assert dt.ensure_rfdiffusion_weights("Base_ckpt.pt") == ckpt.resolve()


def test_ensure_weights_downloads_when_missing(tmp_path, monkeypatch):
    from galaxy.ai.ml_training import diffusion_trainer as dt
    monkeypatch.setenv("DIFFUSION_WEIGHTS_DIR", str(tmp_path))

    def fake_retrieve(url, dest):
        Path(dest).write_bytes(b"downloaded")

    with patch.object(dt.urllib.request, "urlretrieve", side_effect=fake_retrieve):
        got = dt.ensure_rfdiffusion_weights("Base_ckpt.pt")
    assert got.is_file() and got.read_bytes() == b"downloaded"


def test_from_scratch_raises_even_with_rfdiffusion(tmp_path, monkeypatch):
    """Open RFdiffusion has no from-scratch trainer — must not invent metrics."""
    from galaxy.ai.ml_training import diffusion_trainer as dt
    from galaxy.ai.ml_training.datasets import LoadedDataset
    cfg = _diff_cfg(
        dataset=DatasetSpec(name="fixture:structures", split="random"),
        diffusion=DiffusionSpec(finetune=False, base_checkpoint=""),
    )
    ph = LoadedDataset([], "structure", "none", source="ph")
    import sys
    import types
    monkeypatch.setitem(sys.modules, "torch", types.ModuleType("torch"))
    monkeypatch.setitem(sys.modules, "rfdiffusion", types.ModuleType("rfdiffusion"))
    with pytest.raises(NotImplementedError) as ei:
        dt.train_diffusion(cfg, ph, str(tmp_path))
    assert "from-scratch" in str(ei.value).lower() or "open" in str(ei.value).lower()


def test_finetune_runs_when_deps_present(tmp_path, monkeypatch):
    """When torch+rfdiffusion import, finetune path stages ckpt + calls inference."""
    from galaxy.ai.ml_training import diffusion_trainer as dt
    from galaxy.ai.ml_training.datasets import LoadedDataset
    import sys
    import types
    monkeypatch.setitem(sys.modules, "torch", types.ModuleType("torch"))
    monkeypatch.setitem(sys.modules, "rfdiffusion", types.ModuleType("rfdiffusion"))
    monkeypatch.setenv("DIFFUSION_WEIGHTS_DIR", str(tmp_path / "weights"))
    (tmp_path / "weights").mkdir()
    ckpt = tmp_path / "weights" / "Base_ckpt.pt"
    ckpt.write_bytes(b"ckpt")

    design = tmp_path / "out_design.pdb"
    design.write_text("ATOM      1  CA  ALA A   1       0.000   0.000   0.000  1.00  0.00           C\nEND\n")

    def fake_infer(cfg, structures, conditioning, checkpoint, designs_dir):
        dest = Path(designs_dir) / "design_0.pdb"
        dest.write_text(design.read_text())
        return [dest], {"mean_plddt": 0.71, "ca_rmsd_to_ref": 2.5}

    monkeypatch.setattr(dt, "run_rfdiffusion_inference", fake_infer)
    cfg = _diff_cfg(dataset=DatasetSpec(name="fixture:structures", split="random"))
    ph = LoadedDataset([], "structure", "none", source="ph")
    result = dt.train_diffusion(cfg, ph, str(tmp_path / "art"))
    assert result.metrics["n_designs"] == 1.0
    assert result.metrics["mean_plddt"] == 0.71
    assert result.metrics["scrmsd"] == 2.5
    assert result.extra["weight_update"] is False
    assert "train_loss" not in result.metrics  # never fabricate
    assert (tmp_path / "art" / "conditioning.json").is_file()
    assert (tmp_path / "art" / "rfdiffusion_model" / "Base_ckpt.pt").is_file()


# --- routing --------------------------------------------------------------
@pytest.mark.parametrize("text,expected", [
    ("fine-tune a protein diffusion model for FcRn binders", True),
    # Bare design/sample phrasing → catalog (antibody fold / cyclic / MPNN), NOT TRAIN.
    ("design a de novo protein binder against PD-L1", False),
    ("use RFdiffusion to generate a peptide scaffold", False),
    ("peptide structure design for a BCL-XL binder", False),
    ("train a protein backbone generation model", True),
])
def test_diffusion_intent_detected(text, expected):
    assert detect_training_intent(text) is expected


def test_design_without_train_falls_through_to_catalog():
    assert route_ml_training("design a de novo protein binder against PD-L1") is None
    assert route_ml_training("optimise this peptide structure for solubility") is None


def test_prepared_inputs_diffusion_train_note_does_not_hijack():
    # Cold-start Prepared notes used to say "diffusion train set dataset=…"
    # which re-armed detect_training_intent via the incidental "train" token.
    text = (
        "Graft these CDRs onto a stable human framework. (protein design)\n"
        "[Prepared inputs: For protein backbone design / diffusion train "
        "set dataset=6Z43.pdb (never nanobody_constraints.json).]\n"
        "[Attached files: 6Z43.pdb, nanobody_constraints.json]"
    )
    assert detect_training_intent(text) is False
    assert route_ml_training(text) is None


def test_routing_diffusion_intent():
    cfg = extract_training_config("fine-tune a protein diffusion model for FcRn binders")
    assert cfg.model_type == "protein_diffusion"
    assert cfg.task_type == "structure_generation"
    assert cfg.diffusion.framework == "rfdiffusion"
    assert cfg.diffusion.finetune is True
    assert cfg.dataset.name == "fixture:structures"


def test_routing_diffusion_from_scratch_and_framework():
    cfg = extract_training_config("train a peptide structure diffusion model from scratch with chroma")
    assert cfg.model_type == "protein_diffusion"
    assert cfg.diffusion.finetune is False
    assert cfg.diffusion.framework == "chroma"


def test_routing_diffusion_extracts_hotspots():
    # extract_training_config still maps diffusion phrasing when called directly;
    # the router gate (detect_training_intent) requires a train verb.
    cfg = extract_training_config(
        "fine-tune a binder against a target with hotspot residues A30, A33, A34")
    assert cfg.diffusion.hotspot_residues == "A30,A33,A34"


def test_routing_diffusion_user_data_overrides_dataset():
    cfg = extract_training_config("fine-tune a protein diffusion model",
                                  dataset_s3_uri="s3://b/structs/")
    assert cfg.dataset.s3_uri == "s3://b/structs/"


def test_diffusion_not_confused_with_llm():
    # a diffusion request must NOT route to an LLM model_type
    cfg = extract_training_config("fine-tune a protein diffusion model for binders")
    assert cfg.model_type not in ("ludwig_llm", "trl_dpo", "trl_grpo")


def test_route_ml_training_diffusion_ga():
    ga = route_ml_training("fine-tune a protein diffusion model for FcRn binders")
    assert ga is not None
    assert ga["domain"] == "ml_training"
    assert ga["nextflow_path"] == "ml_training/diffusion_train.nf"
    assert "protein_diffusion" in ga["scientific_rationale"]
    assert "diffusion-training" in ga["compute_config"]["container"]


def test_resolve_container_by_nf_path():
    assert "diffusion-training" in resolve_ml_training_container(
        nextflow_path="ml_training/diffusion_train.nf")
    assert "sc-diffusion-training" in resolve_ml_training_container(
        nextflow_path="ml_training/scrna_diffusion_train.nf")
    assert "trl-training" in resolve_ml_training_container(model_type="trl_dpo")
    assert resolve_ml_training_container(model_type="sklearn_tabular").endswith(
        "/biomate/ml-training:latest")


# --- cli ------------------------------------------------------------------
def test_cli_maps_diffusion_args():
    args = _build_parser().parse_args([
        "--dataset", "fixture:structures", "--model-type", "protein_diffusion",
        "--framework", "rfdiffusion", "--hotspot-residues", "A30,A33",
        "--num-designs", "16", "--diffusion-steps", "30", "--from-scratch",
        "--length-min", "40", "--length-max", "80",
    ])
    cfg = build_config_from_args(args)
    assert cfg.model_type == "protein_diffusion"
    assert cfg.task_type == "structure_generation"
    assert cfg.diffusion.framework == "rfdiffusion"
    assert cfg.diffusion.hotspot_residues == "A30,A33"
    assert cfg.diffusion.num_designs == 16
    assert cfg.diffusion.diffusion_steps == 30
    assert cfg.diffusion.finetune is False
    assert (cfg.diffusion.length_min, cfg.diffusion.length_max) == (40, 80)


def test_cli_diffusion_defaults_finetune_true():
    args = _build_parser().parse_args([
        "--dataset", "fixture:structures", "--model-type", "protein_diffusion",
    ])
    cfg = build_config_from_args(args)
    assert cfg.diffusion.finetune is True


# --- executor image selection --------------------------------------------
def test_diffusion_selects_diffusion_image(monkeypatch):
    monkeypatch.delenv("DIFFUSION_TRAINING_IMAGE", raising=False)
    assert "diffusion-training" in _resolve_container(_diff_cfg())
    # other model types must NOT resolve to the diffusion image
    assert "diffusion-training" not in _resolve_container(
        TrainingConfig(name="clf", dataset=DatasetSpec(name="tdc:hERG", target_col="y")))


def test_diffusion_image_env_override(monkeypatch):
    monkeypatch.setenv("DIFFUSION_TRAINING_IMAGE", "myregistry/custom-diff:v1")
    assert _resolve_container(_diff_cfg()) == "myregistry/custom-diff:v1"


def test_execute_request_carries_diffusion_params():
    req = build_execute_request(_diff_cfg(diffusion=DiffusionSpec(
        framework="rfdiffusion", hotspot_residues="A30", num_designs=12,
        contig="10-40")), user_id="u1", s3_dataset_uri="s3://b/structs/")
    params = req["parameters"]
    assert params["model_type"] == "protein_diffusion"
    assert params["framework"] == "rfdiffusion"
    assert params["hotspot_residues"] == "A30"
    assert params["num_designs"] == 12
    assert params["contig"] == "10-40"
    assert params["dataset"] == "s3://b/structs/"
    # all params flat scalars (executor JSON-serializes containers; we avoid them)
    assert all(not isinstance(v, (list, dict)) for v in params.values())
    assert "diffusion-training" in req["compute_config"]["container"]
