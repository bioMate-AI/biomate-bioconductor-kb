"""
Phase 1 test: manifest_schema.json is valid JSON Schema and
a hand-crafted example manifest validates against it.
"""

import json
from pathlib import Path

import pytest

try:
    import jsonschema
    HAS_JSONSCHEMA = True
except ImportError:
    HAS_JSONSCHEMA = False

SCHEMA_PATH = Path(__file__).resolve().parents[1] / "manifests" / "manifest_schema.json"

VALID_MANIFEST = {
    "schema_version": "1.0",
    "pipeline_id": "cryosparc_standard_spa",
    "invocation_id": "inv_test_001",
    "completed_at": "2026-03-05T22:00:00Z",
    "outdir": "/results/test_spa/",
    "params": {
        "pixel_size": 1.05,
        "voltage": 300,
        "qc_profile": "cryoem_spa_standard"
    },
    "metrics": {
        "fsc_0143_resolution_angstroms": 3.2,
        "num_particles": 147000,
        "orientation_anisotropy_ratio": 2.1
    },
    "ports": {
        "particles_ctf_refined": "20_local_ctf_refinement/particles_ctf_refined.cs",
        "volume_cs":             "17_homogeneous_refinement/refined_volume.cs",
        "nu_refined_volume":     "21_non_uniform_refinement/nu_refined_volume.cs",
        "sharpened_map":         "23_sharpening/sharpened_map.cs",
        "fsc_report":            "19_validation_fsc/validation_report.json"
    }
}

INVALID_MANIFEST_MISSING_PORTS = {
    "schema_version": "1.0",
    "pipeline_id": "cryosparc_standard_spa",
    "invocation_id": "inv_test_002",
    "completed_at": "2026-03-05T22:00:00Z",
    "outdir": "/results/test/"
    # missing "ports"
}

INVALID_MANIFEST_BAD_VERSION = {
    **VALID_MANIFEST,
    "schema_version": "2.0",  # not "1.0"
}


@pytest.fixture(scope="module")
def schema():
    with open(SCHEMA_PATH) as f:
        return json.load(f)


class TestManifestSchemaFile:
    def test_schema_file_exists(self):
        assert SCHEMA_PATH.exists(), f"manifest_schema.json not found at {SCHEMA_PATH}"

    def test_schema_is_valid_json(self, schema):
        assert isinstance(schema, dict)
        assert "$schema" in schema

    def test_schema_has_required_fields(self, schema):
        required = schema.get("required", [])
        for field in ("schema_version", "pipeline_id", "invocation_id", "completed_at", "outdir", "ports"):
            assert field in required, f"'{field}' should be required in manifest schema"


@pytest.mark.skipif(not HAS_JSONSCHEMA, reason="jsonschema not installed; run: pip install jsonschema")
class TestManifestValidation:
    def test_valid_manifest_passes(self, schema):
        jsonschema.validate(instance=VALID_MANIFEST, schema=schema)

    def test_missing_ports_fails(self, schema):
        with pytest.raises(jsonschema.ValidationError):
            jsonschema.validate(instance=INVALID_MANIFEST_MISSING_PORTS, schema=schema)

    def test_bad_schema_version_fails(self, schema):
        with pytest.raises(jsonschema.ValidationError):
            jsonschema.validate(instance=INVALID_MANIFEST_BAD_VERSION, schema=schema)

    def test_minimal_valid_manifest(self, schema):
        """Ports can have any string keys as long as values are strings."""
        minimal = {
            "schema_version": "1.0",
            "pipeline_id": "particle_subtraction",
            "invocation_id": "inv_min_001",
            "completed_at": "2026-03-05T12:00:00Z",
            "outdir": "/tmp/test/",
            "ports": {
                "subtracted_particles_cs": "particle_subtraction/subtracted_particles.cs"
            }
        }
        jsonschema.validate(instance=minimal, schema=schema)
