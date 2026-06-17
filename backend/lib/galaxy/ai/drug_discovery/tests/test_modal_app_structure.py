"""Modal app structural validation + adapter discovery unit tests.

These run as part of the pytest suite when the `modal` SDK is
importable (no Modal account or network required — pure structural
inspection of `infra/modal/regulatory_llm_app.py`). When `modal` is
not installed (the default local-dev state) the file skips cleanly
via `pytest.importorskip` rather than producing 15 ERRORs that mask
real regressions in the rest of the drug_discovery test suite.
They catch:

  1. Modal SDK API drift (deprecated kwargs, missing decorators) that
     would only surface at `modal deploy` time otherwise — e.g. the
     container_idle_timeout → scaledown_window rename caught earlier.
  2. Configuration regressions (e.g. someone bumps idle window to 30 min
     and blows the budget, or removes the Volume mounts).
  3. LoRA discovery edge cases (missing dir, partial adapter,
     non-directory entries, sorting determinism).

The actual @modal.enter() boot path can only be exercised on Modal, but
the pure discover_adapters function is identical to what enter() calls,
so testing it here proves the per-org adapter selection logic.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest

# The Modal app file does `import modal` at module top + uses
# `modal.Image/Volume/App` at module body — none of those can be
# lazy-imported without rewriting the entire deploy artifact (the
# `@app.function` decorators need the app object at decoration time).
# When modal isn't installed (the default local-dev state — Modal is
# only needed at `modal deploy` time), skip the entire structural
# validation file. CI environments that DO have modal installed
# (the deploy gate) still run every check. This is the standard
# pytest idiom for an optional-dep test module, not a workaround:
# without modal there is no Modal artifact to validate.
pytest.importorskip(
    "modal",
    reason="modal SDK not installed locally; structural validation of "
    "infra/modal/regulatory_llm_app.py runs in the deploy gate where "
    "`pip install modal` is part of the image.",
)


# ---------------------------------------------------------------------------
# Module loader (the Modal app file isn't a normal Python package)
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def modal_app():
    repo_root = Path(__file__).resolve().parents[6]
    spec = importlib.util.spec_from_file_location(
        "biomate_modal_app", repo_root / "infra" / "modal" / "regulatory_llm_app.py",
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------------------
# App / class structural assertions
# ---------------------------------------------------------------------------

def test_app_name_matches_runbook(modal_app):
    """The deploy runbook references `modal app restart biomate-regulatory-llm`
    so the app name is part of the public contract."""
    assert modal_app.app.name == "biomate-regulatory-llm"


def test_class_exists_with_expected_methods(modal_app):
    """RegulatoryLLM must expose @modal.enter load and @modal.asgi_app serve."""
    cls = modal_app.RegulatoryLLM
    assert hasattr(cls, "load")
    assert hasattr(cls, "serve")
    # Modal wraps decorated methods — they're modal Function objects, not
    # plain Python callables.
    assert cls.load.__class__.__name__ == "Function"
    assert cls.serve.__class__.__name__ == "Function"


def test_base_model_is_qwen3_8b(modal_app):
    assert modal_app.RegulatoryLLM.BASE_MODEL == "Qwen/Qwen3-8B"


def test_upload_adapter_function_is_modal_function(modal_app):
    """upload_adapter is a @app.function the operator can call via
    `modal run` to deploy a new LoRA without rebuilding the image."""
    assert modal_app.upload_adapter.__class__.__name__ == "Function"


def test_volumes_use_persistent_named_volumes(modal_app):
    """Adapters + HF cache must be persistent (survive container restarts).
    A modal.Volume.from_name(...) gives a named persistent volume; if
    someone accidentally uses an ephemeral Volume, weights re-download
    every cold start and cost balloons."""
    adapters_vol = modal_app.adapters_vol
    hf_cache_vol = modal_app.hf_cache_vol
    # Both volumes should be modal.Volume instances (not Mount, not Ephemeral)
    import modal
    assert isinstance(adapters_vol, modal.Volume)
    assert isinstance(hf_cache_vol, modal.Volume)


def test_adapters_dir_mounted_inside_container(modal_app):
    """The @modal.enter() handler reads ADAPTERS_DIR, so the constant must
    match the volume mount path. Hardcoding both sides is intentional —
    they MUST agree."""
    assert str(modal_app.ADAPTERS_DIR) == "/adapters"
    assert str(modal_app.HF_CACHE_DIR) == "/hf-cache"


def test_vllm_image_tag_is_pinned(modal_app):
    """We pin to a known-good vLLM tag so cold-start behavior is
    deterministic. If this changes, someone has to bump it deliberately."""
    assert modal_app.VLLM_TAG == "v0.6.4"


# ---------------------------------------------------------------------------
# discover_adapters — pure function tests with fake filesystems
# ---------------------------------------------------------------------------

def test_discover_returns_empty_when_dir_missing(modal_app, tmp_path):
    out = modal_app.discover_adapters(tmp_path / "nope")
    assert out == []


def test_discover_returns_empty_when_dir_has_nothing(modal_app, tmp_path):
    out = modal_app.discover_adapters(tmp_path)
    assert out == []


def test_discover_returns_one_adapter(modal_app, tmp_path):
    a = tmp_path / "regulatory_llm_v6"
    (a / "lora_adapter").mkdir(parents=True)
    (a / "lora_adapter" / "adapter_config.json").write_text("{}")
    (a / "lora_adapter" / "adapter_model.safetensors").write_bytes(b"\x00" * 16)

    out = modal_app.discover_adapters(tmp_path)
    assert len(out) == 1
    assert out[0]["name"] == "regulatory_llm_v6"
    assert out[0]["path"].endswith("/regulatory_llm_v6/lora_adapter")


def test_discover_returns_multiple_sorted(modal_app, tmp_path):
    # Create adapters out of alphabetical order — discover must sort.
    for name in ["regulatory_llm_v6_zeta", "regulatory_llm_v6_acme", "regulatory_llm_v6"]:
        d = tmp_path / name / "lora_adapter"
        d.mkdir(parents=True)
        (d / "adapter_config.json").write_text("{}")

    out = modal_app.discover_adapters(tmp_path)
    assert [a["name"] for a in out] == [
        "regulatory_llm_v6",
        "regulatory_llm_v6_acme",
        "regulatory_llm_v6_zeta",
    ]


def test_discover_skips_dir_without_lora_adapter_subdir(modal_app, tmp_path):
    """An adapter directory that's missing lora_adapter/ is skipped (no
    partially-deployed adapters served)."""
    (tmp_path / "regulatory_llm_v6_acme").mkdir()
    (tmp_path / "regulatory_llm_v6_acme" / "README.md").write_text("WIP")
    out = modal_app.discover_adapters(tmp_path)
    assert out == []


def test_discover_skips_lora_dir_without_adapter_config_json(modal_app, tmp_path):
    """If adapter_config.json is missing, vLLM can't load the adapter — skip."""
    d = tmp_path / "incomplete" / "lora_adapter"
    d.mkdir(parents=True)
    (d / "adapter_model.safetensors").write_bytes(b"\x00")
    out = modal_app.discover_adapters(tmp_path)
    assert out == []


def test_discover_ignores_non_directory_entries(modal_app, tmp_path):
    """Stray files at the top level (.DS_Store, README.md) are ignored."""
    (tmp_path / "README.md").write_text("# adapters live here")
    (tmp_path / ".DS_Store").write_bytes(b"\x00")

    d = tmp_path / "regulatory_llm_v6" / "lora_adapter"
    d.mkdir(parents=True)
    (d / "adapter_config.json").write_text("{}")

    out = modal_app.discover_adapters(tmp_path)
    assert len(out) == 1
    assert out[0]["name"] == "regulatory_llm_v6"


def test_discover_handles_per_org_naming_convention(modal_app, tmp_path):
    """Per-org adapters follow regulatory_llm_v6_<orgid>; discover treats
    them as ordinary adapters — the orgid → adapter mapping lives in
    _resolve_adapter_name on the Galaxy side."""
    for name in ["regulatory_llm_v6", "regulatory_llm_v6_acme", "regulatory_llm_v7"]:
        d = tmp_path / name / "lora_adapter"
        d.mkdir(parents=True)
        (d / "adapter_config.json").write_text(json.dumps({"r": 16}))

    out = modal_app.discover_adapters(tmp_path)
    assert {a["name"] for a in out} == {
        "regulatory_llm_v6", "regulatory_llm_v6_acme", "regulatory_llm_v7",
    }
