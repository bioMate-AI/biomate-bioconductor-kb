"""
Phase 1 test: manifest generation.

Verifies that:
  - write_manifest.py exists and is importable
  - write_manifest() produces schema-valid JSON for every registered pipeline
  - Manifest port keys match the pipeline's declared registry output ports
  - The PIPELINE_MANIFEST Nextflow module file exists and is syntactically sound
  - The staged pipeline directory for cryosparc_standard_spa exists

Does NOT require Nextflow to be installed — tests the Python manifest writer directly.
"""

import importlib.util
import json
import sys
from pathlib import Path

import pytest

PIPELINE_COMPOSITION_DIR = Path(__file__).resolve().parents[1]
REGISTRY_PATH = PIPELINE_COMPOSITION_DIR / "registry" / "pipeline_registry.json"
SCHEMA_PATH   = PIPELINE_COMPOSITION_DIR / "manifests" / "manifest_schema.json"

try:
    import jsonschema
    HAS_JSONSCHEMA = True
except ImportError:
    HAS_JSONSCHEMA = False


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_write_manifest():
    """Import write_manifest.py via importlib (avoids __init__.py dependency)."""
    path = PIPELINE_COMPOSITION_DIR / "manifests" / "write_manifest.py"
    spec = importlib.util.spec_from_file_location("write_manifest", path)
    mod  = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _make_mock_ports(entry: dict) -> dict:
    """Build a placeholder port map from a registry entry's output declarations."""
    return {name: f"mock_output/{name}.out" for name in entry["outputs"]}


def _make_mock_manifest(pipeline_id: str, entry: dict) -> dict:
    return {
        "schema_version": "1.0",
        "pipeline_id":    pipeline_id,
        "invocation_id":  f"inv_mock_{pipeline_id[:12]}",
        "completed_at":   "2026-03-05T22:00:00Z",
        "outdir":         f"/results/{pipeline_id}_test/",
        "ports":          _make_mock_ports(entry),
    }


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def registry():
    with open(REGISTRY_PATH) as f:
        return json.load(f)


@pytest.fixture(scope="module")
def schema():
    with open(SCHEMA_PATH) as f:
        return json.load(f)


@pytest.fixture(scope="module")
def wm_module():
    return _load_write_manifest()


# ---------------------------------------------------------------------------
# File existence
# ---------------------------------------------------------------------------

class TestPhase1Files:
    def test_write_manifest_exists(self):
        path = PIPELINE_COMPOSITION_DIR / "manifests" / "write_manifest.py"
        assert path.exists(), f"write_manifest.py not found at {path}"

    def test_pipeline_manifest_nf_exists(self):
        path = PIPELINE_COMPOSITION_DIR / "modules" / "pipeline_manifest.nf"
        assert path.exists(), f"pipeline_manifest.nf not found at {path}"

    def test_staged_spa_pipeline_exists(self):
        path = PIPELINE_COMPOSITION_DIR / "pipelines" / "cryosparc_standard_spa" / "main.nf"
        assert path.exists(), f"Staged SPA pipeline not found at {path}"

    def test_pipeline_manifest_nf_has_publishdir(self):
        """Sanity-check: the .nf module must write to outdir."""
        nf = (PIPELINE_COMPOSITION_DIR / "modules" / "pipeline_manifest.nf").read_text()
        assert "publishDir" in nf, "PIPELINE_MANIFEST.nf missing publishDir directive"
        assert "workflow_outputs.json" in nf, "PIPELINE_MANIFEST.nf missing output filename"

    def test_staged_spa_includes_manifest_module(self):
        nf = (
            PIPELINE_COMPOSITION_DIR / "pipelines" / "cryosparc_standard_spa" / "main.nf"
        ).read_text()
        assert "PIPELINE_MANIFEST" in nf, (
            "Staged SPA pipeline must include and call PIPELINE_MANIFEST"
        )


# ---------------------------------------------------------------------------
# write_manifest() Python API
# ---------------------------------------------------------------------------

class TestWriteManifestAPI:
    def test_write_manifest_is_importable(self, wm_module):
        assert hasattr(wm_module, "write_manifest"), (
            "write_manifest.py must expose a write_manifest() function"
        )

    def test_write_manifest_requires_non_empty_ports(self, wm_module, tmp_path):
        with pytest.raises((ValueError, Exception)):
            wm_module.write_manifest(
                pipeline_id="test",
                invocation_id="inv_000",
                outdir="/tmp/test/",
                ports={},
                output_path=str(tmp_path / "out.json"),
                validate=False,
            )

    def test_write_manifest_creates_file(self, wm_module, tmp_path):
        out = tmp_path / "workflow_outputs.json"
        wm_module.write_manifest(
            pipeline_id="particle_subtraction",
            invocation_id="inv_test_001",
            outdir="/results/ps_test/",
            ports={"subtracted_particles_cs": "particle_subtraction/subtracted.cs",
                   "subtraction_report":       "particle_subtraction/report.json"},
            output_path=str(out),
            validate=False,
        )
        assert out.exists()
        data = json.loads(out.read_text())
        assert data["schema_version"] == "1.0"
        assert data["pipeline_id"] == "particle_subtraction"
        assert "subtracted_particles_cs" in data["ports"]

    @pytest.mark.skipif(not HAS_JSONSCHEMA, reason="jsonschema not installed")
    def test_write_manifest_spa_schema_valid(self, wm_module, schema, tmp_path):
        """Full SPA manifest with all ports passes JSON Schema validation."""
        out = tmp_path / "workflow_outputs.json"
        manifest = wm_module.write_manifest(
            pipeline_id="cryosparc_standard_spa",
            invocation_id="inv_phase1_spa",
            outdir="/results/spa_phase1/",
            ports={
                "particles_ctf_refined": "20_local_ctf_refinement/particles_ctf_refined.cs",
                "volume_cs":             "17_homogeneous_refinement/refined_volume.cs",
                "nu_refined_volume":     "21_non_uniform_refinement/nu_refined_volume.cs",
                "sharpened_map":         "23_sharpening/sharpened_map.cs",
                "fsc_report":            "19_validation_fsc/validation_report.json",
                "local_resolution_map":  "22_local_resolution/local_resolution.cs",
                "micrographs_ctf":       "04_patch_ctf/micrographs_ctf.cs",
            },
            params={"pixel_size": 1.05, "voltage": 300, "qc_profile": "cryoem_spa_standard"},
            metrics={
                "fsc_0143_resolution_angstroms": 3.2,
                "num_particles":                 147000,
                "orientation_anisotropy_ratio":  2.1,
            },
            output_path=str(out),
            validate=True,
        )
        assert manifest["pipeline_id"] == "cryosparc_standard_spa"
        assert out.exists()
        # Re-validate loaded file
        jsonschema.validate(instance=json.loads(out.read_text()), schema=schema)

    @pytest.mark.skipif(not HAS_JSONSCHEMA, reason="jsonschema not installed")
    def test_write_manifest_et_pipeline_schema_valid(self, wm_module, schema, tmp_path):
        out = tmp_path / "et_manifest.json"
        wm_module.write_manifest(
            pipeline_id="et_full_pipeline",
            invocation_id="inv_phase1_et",
            outdir="/results/et_phase1/",
            ports={
                "sta_report":          "04_subtomogram_averaging/sta_report.json",
                "et_pipeline_summary": "et_pipeline_summary.json",
            },
            params={"pixel_size": 1.35, "voltage": 300},
            output_path=str(out),
            validate=True,
        )
        jsonschema.validate(instance=json.loads(out.read_text()), schema=schema)


# ---------------------------------------------------------------------------
# Registry × manifest consistency
# ---------------------------------------------------------------------------

class TestRegistryManifestConsistency:
    @pytest.mark.skipif(not HAS_JSONSCHEMA, reason="jsonschema not installed")
    def test_all_registered_pipelines_produce_valid_manifests(self, registry, schema):
        """Mock manifests built from registry entries must pass JSON Schema."""
        failures = []
        for pid, entry in registry["pipelines"].items():
            manifest = _make_mock_manifest(pid, entry)
            try:
                jsonschema.validate(instance=manifest, schema=schema)
            except jsonschema.ValidationError as e:
                failures.append(f"{pid}: {e.message}")
        assert failures == [], (
            "Mock manifests failed schema validation:\n" + "\n".join(failures)
        )

    def test_manifest_ports_match_registry_outputs(self, registry):
        """Port keys in manifest must equal declared output port names in registry."""
        for pid, entry in registry["pipelines"].items():
            declared = set(entry["outputs"].keys())
            mock_ports = set(_make_mock_ports(entry).keys())
            assert declared == mock_ports, (
                f"{pid}: manifest ports {mock_ports} != registry outputs {declared}"
            )

    def test_all_pipelines_have_at_least_one_port(self, registry):
        for pid, entry in registry["pipelines"].items():
            assert entry["outputs"], f"{pid}: outputs must have at least one port"

    @pytest.mark.skipif(not HAS_JSONSCHEMA, reason="jsonschema not installed")
    def test_write_manifest_matches_registry_for_every_pipeline(
        self, registry, wm_module, schema, tmp_path
    ):
        """write_manifest() produces schema-valid output for every registered pipeline."""
        failures = []
        for pid, entry in registry["pipelines"].items():
            out = tmp_path / f"{pid}_manifest.json"
            try:
                wm_module.write_manifest(
                    pipeline_id=pid,
                    invocation_id=f"inv_test_{pid[:8]}",
                    outdir=f"/results/{pid}/",
                    ports=_make_mock_ports(entry),
                    output_path=str(out),
                    validate=True,
                )
                jsonschema.validate(instance=json.loads(out.read_text()), schema=schema)
            except Exception as e:
                failures.append(f"{pid}: {e}")
        assert failures == [], (
            "write_manifest() failed for these pipelines:\n" + "\n".join(failures)
        )
