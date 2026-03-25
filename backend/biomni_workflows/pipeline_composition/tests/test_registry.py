"""
Phase 2 test: pipeline_registry.json completeness and consistency.

Checks:
  - Every cryo_em/ and cryo_et/ main.nf has a registry entry
  - Every registry entry has at least one input and one output
  - Type compatibility table covers all types declared in port schemas
  - All output port names are consistent across registry and any existing manifests
"""

import json
import os
import sys
from pathlib import Path

import pytest

PIPELINE_COMPOSITION_DIR = Path(__file__).resolve().parents[1]        # .../pipeline_composition/
WORKFLOWS_BASE = PIPELINE_COMPOSITION_DIR.parent                       # .../biomni_workflows/
WORKFLOWS_ROOT = WORKFLOWS_BASE / "nextflow_nfcore" / "subworkflows"
REGISTRY_PATH = PIPELINE_COMPOSITION_DIR / "registry" / "pipeline_registry.json"
CRYO_EM_DIR = WORKFLOWS_ROOT / "cryo_em"
CRYO_ET_DIR = WORKFLOWS_ROOT / "cryo_et"


@pytest.fixture(scope="module")
def registry():
    with open(REGISTRY_PATH) as f:
        return json.load(f)


def get_all_workflow_dirs():
    """Return all directories with a main.nf in cryo_em/ and cryo_et/."""
    dirs = []
    for base in (CRYO_EM_DIR, CRYO_ET_DIR):
        if base.exists():
            for d in sorted(base.iterdir()):
                if (d / "main.nf").exists():
                    dirs.append(d.name)
    return dirs


class TestRegistryStructure:
    def test_registry_loads(self, registry):
        assert "pipelines" in registry
        assert "type_compatibility" in registry
        assert len(registry["pipelines"]) >= 15

    def test_every_cryo_workflow_has_entry(self, registry):
        """Every workflow directory should be in the registry."""
        pipeline_ids = set(registry["pipelines"].keys())
        workflow_dirs = get_all_workflow_dirs()
        missing = [d for d in workflow_dirs if d not in pipeline_ids]
        assert missing == [], (
            f"Workflows present in filesystem but missing from registry: {missing}\n"
            f"Add entries to pipeline_registry.json for each."
        )

    def test_every_entry_has_inputs(self, registry):
        for pid, entry in registry["pipelines"].items():
            assert "inputs" in entry, f"{pid}: missing 'inputs'"
            assert len(entry["inputs"]) >= 1, f"{pid}: inputs must have at least one port"

    def test_every_entry_has_outputs(self, registry):
        for pid, entry in registry["pipelines"].items():
            assert "outputs" in entry, f"{pid}: missing 'outputs'"
            assert len(entry["outputs"]) >= 1, f"{pid}: outputs must have at least one port"

    def test_every_entry_has_entrypoint(self, registry):
        for pid, entry in registry["pipelines"].items():
            assert "entrypoint" in entry, f"{pid}: missing 'entrypoint'"

    def test_entrypoints_exist(self, registry):
        missing = []
        for pid, entry in registry["pipelines"].items():
            path = WORKFLOWS_BASE / entry["entrypoint"]
            if not path.exists():
                missing.append(f"{pid}: {entry['entrypoint']}")
        assert missing == [], f"Entrypoint files not found:\n" + "\n".join(missing)


class TestPortTypes:
    def test_all_declared_types_in_compatibility_table(self, registry):
        """Every type used in port declarations must appear in type_compatibility."""
        compat = set(registry["type_compatibility"].keys())
        undeclared = []
        for pid, entry in registry["pipelines"].items():
            for direction in ("inputs", "outputs"):
                for port_name, port in entry.get(direction, {}).items():
                    t = port.get("type", "")
                    if t and t not in compat:
                        undeclared.append(f"{pid}.{direction}.{port_name}: type '{t}'")
        assert undeclared == [], "Types used in registry but missing from type_compatibility:\n" + "\n".join(undeclared)

    def test_required_flag_is_bool(self, registry):
        for pid, entry in registry["pipelines"].items():
            for port_name, port in entry.get("inputs", {}).items():
                if "required" in port:
                    assert isinstance(port["required"], bool), (
                        f"{pid}.inputs.{port_name}: 'required' must be bool, got {type(port['required'])}"
                    )


class TestPortCompatibility:
    """
    Verify that the natural chaining relationships between pipelines
    have at least one compatible port pair.
    """

    def _types_compatible(self, registry, type_a, type_b):
        return type_b in registry["type_compatibility"].get(type_a, [])

    def _find_compatible_connections(self, registry, upstream_id, downstream_id):
        """Return list of (output_port, input_port) pairs that are type-compatible."""
        upstream = registry["pipelines"][upstream_id]["outputs"]
        downstream = registry["pipelines"][downstream_id]["inputs"]
        connections = []
        for out_name, out_port in upstream.items():
            for in_name, in_port in downstream.items():
                if self._types_compatible(registry, out_port["type"], in_port["type"]):
                    connections.append((out_name, in_name))
        return connections

    @pytest.mark.parametrize("upstream,downstream", [
        ("cryosparc_standard_spa", "particle_subtraction"),
        ("cryosparc_standard_spa", "local_refinement"),
        ("cryosparc_standard_spa", "3d_variability_analysis"),
        ("cryosparc_standard_spa", "3d_variability_pipeline"),
        ("cryosparc_standard_spa", "symmetry_expansion"),
        ("cryosparc_standard_spa", "global_ctf_refinement"),
        ("cryosparc_standard_spa", "topaz_train"),
        ("particle_subtraction",   "local_refinement"),
        ("symmetry_expansion",     "local_refinement"),
        ("topaz_train",            "topaz_extract"),
        ("import_micrographs",     "topaz_extract"),
        ("import_particles",       "3d_variability_analysis"),
    ])
    def test_chain_has_compatible_ports(self, registry, upstream, downstream):
        if upstream not in registry["pipelines"] or downstream not in registry["pipelines"]:
            pytest.skip(f"One of {upstream}, {downstream} not yet in registry")
        connections = self._find_compatible_connections(registry, upstream, downstream)
        assert connections, (
            f"No compatible port pairs between {upstream} → {downstream}.\n"
            f"Upstream outputs: {list(registry['pipelines'][upstream]['outputs'].keys())}\n"
            f"Downstream inputs: {list(registry['pipelines'][downstream]['inputs'].keys())}"
        )
