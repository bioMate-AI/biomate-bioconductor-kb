"""
Phase 3 regression test: extracted modules vs. production monolith.

Verifies that:
  - All expected module files exist in modules/cryosparc/
  - Each module file is valid DSL2 (has 'nextflow.enable.dsl = 2')
  - Each module file defines the expected process(es)
  - The three shared processes (import_movies, patch_motion_correction,
    patch_ctf_estimation) appear in both SPA and helical module files
  - The refactored pipelines/cryosparc_standard_spa/main.nf includes all
    23 modules (no process defined inline)
  - The refactored pipelines/helical_spa_pipeline/main.nf includes the
    3 shared modules instead of redefining them

Does NOT require Nextflow to be installed — pure file/text analysis.
"""

import re
from pathlib import Path

import pytest

PIPELINE_COMPOSITION_DIR = Path(__file__).resolve().parents[1]
MODULES_DIR = PIPELINE_COMPOSITION_DIR / "modules" / "cryosparc"
PIPELINES_DIR = PIPELINE_COMPOSITION_DIR / "pipelines"
WORKFLOWS_BASE = PIPELINE_COMPOSITION_DIR.parent  # biomni_workflows/
PRODUCTION_SPA = (
    WORKFLOWS_BASE
    / "nextflow_nfcore"
    / "subworkflows"
    / "cryo_em"
    / "cryosparc_standard_spa"
    / "main.nf"
)
PRODUCTION_HELICAL = (
    WORKFLOWS_BASE
    / "nextflow_nfcore"
    / "subworkflows"
    / "cryo_em"
    / "helical_spa_pipeline"
    / "main.nf"
)

# All 18 module files expected after Phase 3 extraction
EXPECTED_MODULES = [
    "import_movies.nf",
    "patch_motion_correction.nf",
    "patch_ctf_estimation.nf",
    "micrograph_denoiser.nf",
    "blob_picker.nf",
    "junk_2d_detector.nf",
    "inspect_picks.nf",
    "extract_particles.nf",
    "classify_2d.nf",
    "template_picker.nf",
    "select_2d.nf",
    "ab_initio.nf",
    "homogeneous_refinement.nf",
    "volume_tools.nf",
    "validation_fsc.nf",
    "local_ctf_refinement.nf",
    "non_uniform_refinement.nf",
    "local_resolution.nf",
    "sharpen.nf",
]

# The 23 process names from the SPA monolith
SPA_PROCESSES = [
    "IMPORT_MOVIES",
    "PATCH_MOTION_CORRECTION",
    "PATCH_CTF_ESTIMATION",
    "MICROGRAPH_DENOISER",
    "BLOB_PICKER",
    "JUNK_2D_DETECTOR",
    "INSPECT_PICKS",
    "EXTRACT_PARTICLES_R1",
    "CLASSIFY_2D_R1",
    "SELECT_2D_R1",
    "TEMPLATE_PICKER",
    "INSPECT_PICKS_R2",
    "EXTRACT_PARTICLES_R2",
    "CLASSIFY_2D_R2",
    "SELECT_2D_R2",
    "AB_INITIO",
    "HOMOGENEOUS_REFINEMENT",
    "VOLUME_TOOLS",
    "VALIDATION_FSC",
    "LOCAL_CTF_REFINEMENT",
    "NON_UNIFORM_REFINEMENT",
    "LOCAL_RESOLUTION",
    "SHARPEN",
]

# Processes shared between SPA and helical pipelines
SHARED_PROCESSES = [
    "IMPORT_MOVIES",
    "PATCH_MOTION_CORRECTION",
    "PATCH_CTF_ESTIMATION",
]


def _get_processes_in_file(path: Path) -> list:
    """Return list of process names defined in a .nf file."""
    text = path.read_text()
    return re.findall(r"^process\s+(\w+)\s*\{", text, re.MULTILINE)


# ---------------------------------------------------------------------------
# Module file existence
# ---------------------------------------------------------------------------

class TestModuleFiles:
    @pytest.mark.parametrize("module_file", EXPECTED_MODULES)
    def test_module_file_exists(self, module_file):
        path = MODULES_DIR / module_file
        assert path.exists(), (
            f"Module file not found: {path}\n"
            f"Run Phase 3 extraction to create it."
        )

    @pytest.mark.parametrize("module_file", EXPECTED_MODULES)
    def test_module_file_is_dsl2(self, module_file):
        path = MODULES_DIR / module_file
        if not path.exists():
            pytest.skip(f"{module_file} not yet created")
        text = path.read_text()
        assert "nextflow.enable.dsl = 2" in text, (
            f"{module_file}: must contain 'nextflow.enable.dsl = 2'"
        )

    @pytest.mark.parametrize("module_file", EXPECTED_MODULES)
    def test_module_file_has_process(self, module_file):
        path = MODULES_DIR / module_file
        if not path.exists():
            pytest.skip(f"{module_file} not yet created")
        procs = _get_processes_in_file(path)
        assert procs, f"{module_file}: no 'process NAME {{' found"


# ---------------------------------------------------------------------------
# Process coverage — every SPA process is in a module
# ---------------------------------------------------------------------------

class TestProcessCoverage:
    def _all_processes_in_modules(self) -> set:
        """Return all process names found across all module files."""
        processes = set()
        for nf in MODULES_DIR.glob("*.nf"):
            processes.update(_get_processes_in_file(nf))
        return processes

    def test_all_spa_processes_in_modules(self):
        """Every process from the SPA monolith must exist in a module file."""
        found = self._all_processes_in_modules()
        missing = [p for p in SPA_PROCESSES if p not in found]
        assert missing == [], (
            f"Processes from SPA monolith not yet extracted to modules:\n"
            + "\n".join(f"  - {p}" for p in missing)
        )

    def test_no_extra_processes(self):
        """Module files should only define the 23 SPA processes (+ PIPELINE_MANIFEST)."""
        found = self._all_processes_in_modules()
        expected = set(SPA_PROCESSES)
        extra = found - expected
        assert extra == set(), (
            f"Unexpected processes found in module files: {extra}"
        )

    def test_shared_processes_in_module_files(self):
        """IMPORT_MOVIES, PATCH_MOTION_CORRECTION, PATCH_CTF_ESTIMATION must each
        live in their own dedicated module file (shared with helical pipeline)."""
        shared_map = {
            "IMPORT_MOVIES":           "import_movies.nf",
            "PATCH_MOTION_CORRECTION": "patch_motion_correction.nf",
            "PATCH_CTF_ESTIMATION":    "patch_ctf_estimation.nf",
        }
        for process_name, expected_file in shared_map.items():
            path = MODULES_DIR / expected_file
            if not path.exists():
                pytest.skip(f"{expected_file} not yet created")
            procs = _get_processes_in_file(path)
            assert process_name in procs, (
                f"{process_name} should be defined in {expected_file}, not elsewhere"
            )
            # Must be in ONLY that file (not duplicated across modules)
            other_files_with_proc = [
                nf.name for nf in MODULES_DIR.glob("*.nf")
                if nf.name != expected_file
                and process_name in _get_processes_in_file(nf)
            ]
            assert other_files_with_proc == [], (
                f"{process_name} defined in multiple module files: "
                f"{expected_file} and {other_files_with_proc}"
            )


# ---------------------------------------------------------------------------
# Production monolith analysis
# ---------------------------------------------------------------------------

class TestProductionMonolith:
    def test_production_spa_exists(self):
        assert PRODUCTION_SPA.exists(), f"Production SPA not found at {PRODUCTION_SPA}"

    def test_production_spa_has_all_23_processes(self):
        if not PRODUCTION_SPA.exists():
            pytest.skip("Production SPA not found")
        procs = _get_processes_in_file(PRODUCTION_SPA)
        missing = [p for p in SPA_PROCESSES if p not in procs]
        assert missing == [], (
            f"Production SPA missing processes: {missing}\n"
            f"(These should exist in the production monolith)"
        )

    def test_production_helical_redefines_shared_processes(self):
        """Confirm that helical_spa_pipeline currently duplicates the 3 shared processes.
        This is the duplication Phase 3 eliminates."""
        if not PRODUCTION_HELICAL.exists():
            pytest.skip("Production helical pipeline not found")
        helical_procs = set(_get_processes_in_file(PRODUCTION_HELICAL))
        shared_in_helical = [p for p in SHARED_PROCESSES if p in helical_procs]
        assert shared_in_helical, (
            "Expected helical pipeline to redefine some shared processes "
            "(IMPORT_MOVIES, PATCH_MOTION_CORRECTION, PATCH_CTF_ESTIMATION). "
            "If helical pipeline already uses include, this test can be removed."
        )


# ---------------------------------------------------------------------------
# Refactored pipeline structure
# ---------------------------------------------------------------------------

class TestRefactoredPipelines:
    def test_staged_spa_exists(self):
        path = PIPELINES_DIR / "cryosparc_standard_spa" / "main.nf"
        assert path.exists(), f"Staged SPA pipeline not found at {path}"

    def test_staged_spa_uses_include_not_inline_processes(self):
        """Phase 3 refactored SPA must use include statements, not inline processes."""
        path = PIPELINES_DIR / "cryosparc_standard_spa" / "main.nf"
        if not path.exists():
            pytest.skip("Staged SPA not found")
        text = path.read_text()
        inline_procs = _get_processes_in_file(path)
        assert inline_procs == [], (
            f"Staged SPA still defines processes inline: {inline_procs}\n"
            f"Phase 3 requires all processes to be in modules/ and included."
        )
        assert "include {" in text or "include{" in text, (
            "Staged SPA has no include statements — it should include from modules/"
        )

    def test_staged_spa_includes_pipeline_manifest(self):
        path = PIPELINES_DIR / "cryosparc_standard_spa" / "main.nf"
        if not path.exists():
            pytest.skip("Staged SPA not found")
        text = path.read_text()
        assert "PIPELINE_MANIFEST" in text, (
            "Staged SPA must call PIPELINE_MANIFEST at the end"
        )

    def test_staged_helical_exists(self):
        path = PIPELINES_DIR / "helical_spa_pipeline" / "main.nf"
        if not path.exists():
            pytest.skip("Staged helical pipeline not yet created (Phase 3)")

    def test_staged_helical_includes_shared_modules(self):
        """The helical pipeline should include the shared SPA modules."""
        path = PIPELINES_DIR / "helical_spa_pipeline" / "main.nf"
        if not path.exists():
            pytest.skip("Staged helical pipeline not yet created (Phase 3)")
        text = path.read_text()
        for module_file in ["import_movies.nf", "patch_motion_correction.nf",
                            "patch_ctf_estimation.nf"]:
            assert module_file in text, (
                f"Staged helical pipeline should include {module_file} "
                f"instead of redefining the shared process"
            )
