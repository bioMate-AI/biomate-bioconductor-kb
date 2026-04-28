"""
Unit tests for _resolve_smart_params() in cryosparc_executor.py.

The executor has heavy deps (cryosparc-tools, etc.) so we cannot import it
directly. Instead we parse the function out with ast and exec() it in a
minimal namespace.
"""

import ast
import math
import os
import logging
import pytest

# ---------------------------------------------------------------------------
# Extract the function without importing the module
# ---------------------------------------------------------------------------

EXECUTOR_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "lib",
    "galaxy",
    "webapps",
    "galaxy",
    "api",
    "cryosparc_executor.py",
)


def _extract_function(filepath: str, funcname: str):
    """Parse *funcname* from *filepath* and return a callable."""
    with open(filepath) as fh:
        src = fh.read()
    tree = ast.parse(src)
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == funcname:
            func_src = ast.get_source_segment(src, node)
            ns: dict = {
                "math": math,
                "os": os,
                "log": logging.getLogger("test"),
                "Dict": dict,
                "Any": object,
                "List": list,
                "__builtins__": __builtins__,
            }
            exec(compile(func_src, filepath, "exec"), ns)  # noqa: S102
            return ns[funcname]
    raise ValueError(f"{funcname} not found in {filepath}")


_resolve_smart_params = _extract_function(
    os.path.abspath(EXECUTOR_PATH), "_resolve_smart_params"
)


# ===========================================================================
# Helpers
# ===========================================================================

def _box(mw_kda: float, pixel_size: float) -> int:
    """Reference box-size formula from the function docstring."""
    diameter_A = 13.3 * (mw_kda ** (1.0 / 3.0))
    raw_box = (diameter_A * 1.5) / pixel_size
    box = int(2 ** math.ceil(math.log2(max(raw_box, 1))))
    return max(64, min(512, box))


# ===========================================================================
# 1. Pixel size defaults
# ===========================================================================

class TestPixelSize:
    def test_membrane_small_gets_0649(self):
        r = _resolve_smart_params({"sample_class": "membrane_small"})
        assert r["pixel_size"] == pytest.approx(0.649)

    def test_large_rna_protein_gets_108(self):
        r = _resolve_smart_params({"sample_class": "large_rna_protein"})
        assert r["pixel_size"] == pytest.approx(1.08)

    def test_symmetric_gets_108(self):
        r = _resolve_smart_params({"sample_class": "symmetric"})
        assert r["pixel_size"] == pytest.approx(1.08)

    def test_soluble_gets_083(self):
        r = _resolve_smart_params({"sample_class": "soluble"})
        assert r["pixel_size"] == pytest.approx(0.83)

    def test_gpcr_g_protein_gets_083(self):
        r = _resolve_smart_params({"sample_class": "gpcr_g_protein"})
        assert r["pixel_size"] == pytest.approx(0.83)

    def test_pore_forming_gets_083(self):
        r = _resolve_smart_params({"sample_class": "pore_forming"})
        assert r["pixel_size"] == pytest.approx(0.83)

    def test_membrane_large_gets_083(self):
        r = _resolve_smart_params({"sample_class": "membrane_large"})
        assert r["pixel_size"] == pytest.approx(0.83)

    def test_default_no_sample_class_gets_083(self):
        r = _resolve_smart_params({})
        assert r["pixel_size"] == pytest.approx(0.83)

    def test_user_supplied_pixel_size_not_overwritten(self):
        """Critical invariant: user value must survive regardless of sample_class."""
        r = _resolve_smart_params({"sample_class": "membrane_small", "pixel_size": 1.5})
        assert r["pixel_size"] == pytest.approx(1.5)

    def test_user_supplied_pixel_size_not_overwritten_large_rna(self):
        r = _resolve_smart_params({"sample_class": "large_rna_protein", "pixel_size": 0.5})
        assert r["pixel_size"] == pytest.approx(0.5)


# ===========================================================================
# 2. Box size — formula: 2^ceil(log2((diameter_A * 1.5) / pixel_size))
#    capped [64, 512]; diameter_A = 13.3 * MW^(1/3)
# ===========================================================================

class TestBoxSize:
    def test_mfsd2b_21kda_0649px_gives_128(self):
        """MFSD2B: 21 kDa, membrane_small → pixel_size=0.649 → box=128."""
        r = _resolve_smart_params({
            "sample_class": "membrane_small",
            "molecular_weight_kda": 21,
        })
        assert r["box_size_pix"] == 128, (
            f"Expected 128 for MFSD2B, got {r['box_size_pix']}; "
            f"reference formula gives {_box(21, 0.649)}"
        )

    def test_cav12_400kda_083px_gives_256(self):
        """CaV1.2: 400 kDa, membrane_large → pixel_size=0.83 → box=256."""
        r = _resolve_smart_params({
            "sample_class": "membrane_large",
            "molecular_weight_kda": 400,
        })
        assert r["box_size_pix"] == 256, (
            f"Expected 256 for CaV1.2, got {r['box_size_pix']}; "
            f"reference formula gives {_box(400, 0.83)}"
        )

    def test_spliceosome_2500kda_108px_gives_256(self):
        """Spliceosome: 2500 kDa, large_rna_protein → pixel_size=1.08 → box=256."""
        r = _resolve_smart_params({
            "sample_class": "large_rna_protein",
            "molecular_weight_kda": 2500,
        })
        assert r["box_size_pix"] == 256, (
            f"Expected 256 for spliceosome, got {r['box_size_pix']}; "
            f"reference formula gives {_box(2500, 1.08)}"
        )

    def test_box_size_minimum_clamped_to_64(self):
        """Tiny particle + large pixel → raw box < 64 → clamp to 64."""
        # 1 kDa, pixel=5 Å → raw_box = (13.3*1^(1/3)*1.5)/5 ≈ 4 → clamp 64
        r = _resolve_smart_params({
            "molecular_weight_kda": 1,
            "pixel_size": 5.0,
        })
        assert r["box_size_pix"] == 64

    def test_box_size_maximum_clamped_to_512(self):
        """Huge particle + tiny pixel → clamp to 512."""
        r = _resolve_smart_params({
            "molecular_weight_kda": 100_000,
            "pixel_size": 0.1,
        })
        assert r["box_size_pix"] == 512

    def test_user_supplied_box_size_not_overwritten(self):
        r = _resolve_smart_params({
            "sample_class": "soluble",
            "molecular_weight_kda": 200,
            "box_size_pix": 384,
        })
        assert r["box_size_pix"] == 384

    def test_box_size_power_of_two(self):
        """Box size must always be a power of two."""
        for mw in [50, 150, 500, 1000, 5000]:
            r = _resolve_smart_params({"molecular_weight_kda": mw})
            bs = r["box_size_pix"]
            assert (bs & (bs - 1)) == 0, f"box_size_pix={bs} is not a power of two (MW={mw})"

    def test_box_size_uses_resolved_pixel_size(self):
        """Box size should use the resolved pixel_size (after default applied)."""
        # membrane_small → pixel_size=0.649
        r = _resolve_smart_params({
            "sample_class": "membrane_small",
            "molecular_weight_kda": 21,
        })
        expected = _box(21, 0.649)
        assert r["box_size_pix"] == expected

    def test_box_size_uses_user_pixel_size_when_supplied(self):
        """If user supplies pixel_size, box formula must use that value."""
        r = _resolve_smart_params({
            "sample_class": "membrane_small",
            "molecular_weight_kda": 21,
            "pixel_size": 1.0,
        })
        expected = _box(21, 1.0)
        assert r["box_size_pix"] == expected


# ===========================================================================
# 3. Resolution → particle count
# ===========================================================================

class TestResolutionToParticleCount:
    def test_no_target_resolution_no_particle_count(self):
        """If target_resolution_A not supplied, target_particle_count must not appear."""
        r = _resolve_smart_params({"sample_class": "soluble"})
        assert "target_particle_count" not in r

    def test_2_2A_gives_1M(self):
        r = _resolve_smart_params({"target_resolution_A": 2.2})
        assert r["target_particle_count"] == 1_000_000

    def test_2_5A_boundary_gives_400K(self):
        """2.5 is NOT < 2.5 so should hit 400K bracket."""
        r = _resolve_smart_params({"target_resolution_A": 2.5})
        assert r["target_particle_count"] == 400_000

    def test_2_8A_gives_400K(self):
        r = _resolve_smart_params({"target_resolution_A": 2.8})
        assert r["target_particle_count"] == 400_000

    def test_3_0A_boundary_gives_100K(self):
        """3.0 is NOT < 3.0 so hits 100K bracket."""
        r = _resolve_smart_params({"target_resolution_A": 3.0})
        assert r["target_particle_count"] == 100_000

    def test_3_2A_gives_100K(self):
        r = _resolve_smart_params({"target_resolution_A": 3.2})
        assert r["target_particle_count"] == 100_000

    def test_4_0A_gives_30K(self):
        r = _resolve_smart_params({"target_resolution_A": 4.0})
        assert r["target_particle_count"] == 30_000

    def test_4_5A_boundary_gives_5K(self):
        """4.5 is NOT < 4.5 so hits 5K bracket."""
        r = _resolve_smart_params({"target_resolution_A": 4.5})
        assert r["target_particle_count"] == 5_000

    def test_6_0A_gives_5K(self):
        r = _resolve_smart_params({"target_resolution_A": 6.0})
        assert r["target_particle_count"] == 5_000

    def test_user_supplied_particle_count_not_overwritten(self):
        r = _resolve_smart_params({
            "target_resolution_A": 2.2,
            "target_particle_count": 500_000,
        })
        assert r["target_particle_count"] == 500_000


# ===========================================================================
# 4. Heterogeneity depth → classification strategy
# ===========================================================================

class TestHeterogeneityDepth:
    def test_low_gives_3_classes_no_3dva_no_multibody(self):
        r = _resolve_smart_params({"heterogeneity": "low"})
        assert r["num_3d_classes"] == 3
        assert r["use_3dva"] is False
        assert r["use_multibody"] is False

    def test_default_heterogeneity_is_low(self):
        """Omitting heterogeneity → treat as low."""
        r = _resolve_smart_params({})
        assert r["num_3d_classes"] == 3

    def test_medium_gives_6_classes_3dva_no_multibody(self):
        r = _resolve_smart_params({"heterogeneity": "medium"})
        assert r["num_3d_classes"] == 6
        assert r["use_3dva"] is True
        assert r["use_multibody"] is False

    def test_high_gives_8_classes_3dva_multibody_4bodies(self):
        r = _resolve_smart_params({"heterogeneity": "high"})
        assert r["num_3d_classes"] == 8
        assert r["use_3dva"] is True
        assert r["use_multibody"] is True
        assert r["num_multibody_bodies"] == 4

    def test_user_supplied_num_3d_classes_not_overwritten(self):
        r = _resolve_smart_params({
            "heterogeneity": "high",
            "num_3d_classes": 12,
        })
        assert r["num_3d_classes"] == 12

    def test_high_heterogeneity_uses_setdefault_for_3dva(self):
        """User-supplied use_3dva=False should survive even for high heterogeneity."""
        r = _resolve_smart_params({
            "heterogeneity": "high",
            "use_3dva": False,
        })
        assert r["use_3dva"] is False

    def test_high_heterogeneity_uses_setdefault_for_bodies(self):
        r = _resolve_smart_params({
            "heterogeneity": "high",
            "num_multibody_bodies": 6,
        })
        assert r["num_multibody_bodies"] == 6


# ===========================================================================
# 5. CTF refinement level
# ===========================================================================

class TestCtfRefineLevel:
    def test_2_2A_gives_full(self):
        r = _resolve_smart_params({"target_resolution_A": 2.2})
        assert r["ctf_refine_level"] == "full"

    def test_boundary_2_5_not_less_than_2_5_gives_standard(self):
        """2.5 is NOT < 2.5 → standard."""
        r = _resolve_smart_params({"target_resolution_A": 2.5})
        assert r["ctf_refine_level"] == "standard"

    def test_3_0A_gives_standard(self):
        r = _resolve_smart_params({"target_resolution_A": 3.0})
        assert r["ctf_refine_level"] == "standard"

    def test_boundary_3_5_not_less_than_3_5_gives_minimal(self):
        """3.5 is NOT < 3.5 → minimal."""
        r = _resolve_smart_params({"target_resolution_A": 3.5})
        assert r["ctf_refine_level"] == "minimal"

    def test_5_0A_gives_minimal(self):
        r = _resolve_smart_params({"target_resolution_A": 5.0})
        assert r["ctf_refine_level"] == "minimal"

    def test_default_no_resolution_gives_minimal(self):
        """Default target_resolution_A=3.5 → minimal."""
        r = _resolve_smart_params({})
        assert r["ctf_refine_level"] == "minimal"

    def test_user_supplied_ctf_refine_level_not_overwritten(self):
        r = _resolve_smart_params({
            "target_resolution_A": 2.2,
            "ctf_refine_level": "minimal",
        })
        assert r["ctf_refine_level"] == "minimal"


# ===========================================================================
# 6. Picker strategy
# ===========================================================================

class TestPickerStrategy:
    def test_membrane_small_gets_blob_template_topaz(self):
        r = _resolve_smart_params({"sample_class": "membrane_small"})
        assert r["picker_strategy"] == "blob+template+topaz"

    def test_soluble_small_mw_gets_blob_template_topaz(self):
        """Soluble with MW < 80 kDa → three-picker strategy."""
        r = _resolve_smart_params({
            "sample_class": "soluble",
            "molecular_weight_kda": 50,
        })
        assert r["picker_strategy"] == "blob+template+topaz"

    def test_pore_forming_gets_topaz_trained(self):
        r = _resolve_smart_params({"sample_class": "pore_forming"})
        assert r["picker_strategy"] == "topaz_trained"

    def test_large_rna_protein_gets_blob_template(self):
        r = _resolve_smart_params({"sample_class": "large_rna_protein"})
        assert r["picker_strategy"] == "blob+template"

    def test_symmetric_gets_blob_template(self):
        r = _resolve_smart_params({"sample_class": "symmetric"})
        assert r["picker_strategy"] == "blob+template"

    def test_membrane_large_gets_blob_template(self):
        r = _resolve_smart_params({"sample_class": "membrane_large"})
        assert r["picker_strategy"] == "blob+template"

    def test_soluble_large_mw_gets_blob_template(self):
        r = _resolve_smart_params({
            "sample_class": "soluble",
            "molecular_weight_kda": 200,
        })
        assert r["picker_strategy"] == "blob+template"

    def test_user_supplied_picker_strategy_not_overwritten(self):
        """Critical: user value survives regardless of sample_class."""
        r = _resolve_smart_params({
            "sample_class": "pore_forming",
            "picker_strategy": "blob",
        })
        assert r["picker_strategy"] == "blob"

    def test_membrane_small_user_override_survives(self):
        r = _resolve_smart_params({
            "sample_class": "membrane_small",
            "picker_strategy": "topaz_trained",
        })
        assert r["picker_strategy"] == "topaz_trained"


# ===========================================================================
# 7. QC profile
# ===========================================================================

class TestQcProfile:
    def test_membrane_small_gets_membrane_profile(self):
        r = _resolve_smart_params({"sample_class": "membrane_small"})
        assert r["qc_profile"] == "cryoem_spa_membrane"

    def test_membrane_large_gets_membrane_profile(self):
        r = _resolve_smart_params({"sample_class": "membrane_large"})
        assert r["qc_profile"] == "cryoem_spa_membrane"

    def test_gpcr_g_protein_gets_membrane_profile(self):
        r = _resolve_smart_params({"sample_class": "gpcr_g_protein"})
        assert r["qc_profile"] == "cryoem_spa_membrane"

    def test_pore_forming_gets_membrane_profile(self):
        r = _resolve_smart_params({"sample_class": "pore_forming"})
        assert r["qc_profile"] == "cryoem_spa_membrane"

    def test_soluble_gets_purified_profile(self):
        r = _resolve_smart_params({"sample_class": "soluble"})
        assert r["qc_profile"] == "cryoem_spa_purified"

    def test_large_rna_protein_gets_purified_profile(self):
        r = _resolve_smart_params({"sample_class": "large_rna_protein"})
        assert r["qc_profile"] == "cryoem_spa_purified"

    def test_symmetric_gets_purified_profile(self):
        r = _resolve_smart_params({"sample_class": "symmetric"})
        assert r["qc_profile"] == "cryoem_spa_purified"

    def test_user_supplied_qc_profile_not_overwritten(self):
        r = _resolve_smart_params({
            "sample_class": "soluble",
            "qc_profile": "custom_profile",
        })
        assert r["qc_profile"] == "custom_profile"


# ===========================================================================
# 8. Symmetry discipline
# ===========================================================================

class TestSymmetryDiscipline:
    def test_symmetric_class_sets_refine_symmetry_and_abinitio_c1(self):
        """For symmetric sample_class without a user-set 'symmetry', the function
        should set refine_symmetry from expected_symmetry and abinitio_symmetry=C1."""
        r = _resolve_smart_params({
            "sample_class": "symmetric",
            "expected_symmetry": "D4",
        })
        assert r.get("refine_symmetry") == "D4"
        assert r.get("abinitio_symmetry") == "C1"

    def test_symmetric_class_defaults_refine_symmetry_to_c1(self):
        """If expected_symmetry not provided, refine_symmetry defaults to C1."""
        r = _resolve_smart_params({"sample_class": "symmetric"})
        assert r.get("refine_symmetry") == "C1"
        assert r.get("abinitio_symmetry") == "C1"

    def test_user_supplied_symmetry_sets_refine_symmetry(self):
        """User-supplied symmetry param → refine_symmetry (setdefault), abinitio=C1."""
        r = _resolve_smart_params({
            "sample_class": "soluble",
            "symmetry": "C3",
        })
        assert r.get("refine_symmetry") == "C3"
        assert r.get("abinitio_symmetry") == "C1"

    def test_user_supplied_refine_symmetry_not_overwritten(self):
        """If user already set refine_symmetry, setdefault should not touch it."""
        r = _resolve_smart_params({
            "sample_class": "soluble",
            "symmetry": "C3",
            "refine_symmetry": "C6",
        })
        assert r["refine_symmetry"] == "C6"

    def test_non_symmetric_class_no_auto_symmetry(self):
        """Non-symmetric classes should not inject refine_symmetry."""
        r = _resolve_smart_params({"sample_class": "soluble"})
        assert "refine_symmetry" not in r
        assert "abinitio_symmetry" not in r

    def test_symmetric_class_symmetry_gate_fires_once(self):
        """The function has TWO symmetry blocks; when sample_class=symmetric and
        no 'symmetry' key, first block sets symmetry=expected_symmetry,
        second block (elif 'symmetry' in p) should NOT fire again."""
        r = _resolve_smart_params({
            "sample_class": "symmetric",
            "expected_symmetry": "O",
        })
        # refine_symmetry should be 'O', not overridden
        assert r.get("refine_symmetry") == "O"


# ===========================================================================
# 9. User-supplied values are NEVER overwritten — critical invariant
# ===========================================================================

class TestUserValuesNeverOverwritten:
    """The function docstring guarantees: user-supplied values are NEVER overwritten."""

    def test_pixel_size_not_overwritten(self):
        r = _resolve_smart_params({"sample_class": "membrane_small", "pixel_size": 1.5})
        assert r["pixel_size"] == 1.5

    def test_box_size_not_overwritten(self):
        r = _resolve_smart_params({"sample_class": "soluble", "box_size_pix": 400})
        assert r["box_size_pix"] == 400

    def test_particle_count_not_overwritten(self):
        r = _resolve_smart_params({
            "target_resolution_A": 2.2,
            "target_particle_count": 250_000,
        })
        assert r["target_particle_count"] == 250_000

    def test_3d_classes_not_overwritten(self):
        r = _resolve_smart_params({"heterogeneity": "high", "num_3d_classes": 5})
        assert r["num_3d_classes"] == 5

    def test_ctf_refine_level_not_overwritten(self):
        r = _resolve_smart_params({"target_resolution_A": 2.2, "ctf_refine_level": "minimal"})
        assert r["ctf_refine_level"] == "minimal"

    def test_picker_strategy_not_overwritten(self):
        r = _resolve_smart_params({"sample_class": "pore_forming", "picker_strategy": "blob"})
        assert r["picker_strategy"] == "blob"

    def test_qc_profile_not_overwritten(self):
        r = _resolve_smart_params({"sample_class": "pore_forming", "qc_profile": "my_profile"})
        assert r["qc_profile"] == "my_profile"

    def test_total_dose_not_overwritten(self):
        r = _resolve_smart_params({"sample_class": "symmetric", "total_dose": 60})
        assert r["total_dose"] == 60

    def test_dose_weighting_not_overwritten(self):
        """User setting use_dose_weighting=False with a dose_per_frame must survive."""
        r = _resolve_smart_params({
            "dose_per_frame": 1.5,
            "use_dose_weighting": False,
        })
        assert r["use_dose_weighting"] is False

    def test_particle_diameter_not_overwritten(self):
        r = _resolve_smart_params({"particle_diameter": 999})
        assert r["particle_diameter"] == 999

    def test_num_2d_classes_not_overwritten(self):
        r = _resolve_smart_params({"sample_class": "large_rna_protein", "num_2d_classes": 200})
        assert r["num_2d_classes"] == 200

    def test_input_dict_not_mutated(self):
        """Original input dict must be unchanged after the call."""
        original = {"sample_class": "soluble"}
        original_copy = dict(original)
        _resolve_smart_params(original)
        assert original == original_copy


# ===========================================================================
# 10. Total dose
# ===========================================================================

class TestTotalDose:
    def test_pore_forming_gives_45(self):
        r = _resolve_smart_params({"sample_class": "pore_forming"})
        assert r["total_dose"] == 45

    def test_large_rna_protein_gives_45(self):
        r = _resolve_smart_params({"sample_class": "large_rna_protein"})
        assert r["total_dose"] == 45

    def test_symmetric_gives_55(self):
        r = _resolve_smart_params({"sample_class": "symmetric"})
        assert r["total_dose"] == 55

    def test_soluble_gives_50(self):
        r = _resolve_smart_params({"sample_class": "soluble"})
        assert r["total_dose"] == 50

    def test_membrane_small_gives_50(self):
        r = _resolve_smart_params({"sample_class": "membrane_small"})
        assert r["total_dose"] == 50

    def test_membrane_large_gives_50(self):
        r = _resolve_smart_params({"sample_class": "membrane_large"})
        assert r["total_dose"] == 50

    def test_gpcr_g_protein_gives_50(self):
        r = _resolve_smart_params({"sample_class": "gpcr_g_protein"})
        assert r["total_dose"] == 50

    def test_default_no_sample_class_gives_50(self):
        r = _resolve_smart_params({})
        assert r["total_dose"] == 50

    def test_user_supplied_total_dose_not_overwritten(self):
        r = _resolve_smart_params({"sample_class": "symmetric", "total_dose": 60})
        assert r["total_dose"] == 60


# ===========================================================================
# 11. Dose weighting
# ===========================================================================

class TestDoseWeighting:
    def test_dose_per_frame_positive_enables_weighting(self):
        r = _resolve_smart_params({"dose_per_frame": 1.5})
        assert r["use_dose_weighting"] is True

    def test_dose_per_frame_zero_disables_weighting(self):
        r = _resolve_smart_params({"dose_per_frame": 0})
        assert r["use_dose_weighting"] is False

    def test_dose_per_frame_missing_disables_weighting(self):
        r = _resolve_smart_params({})
        assert r["use_dose_weighting"] is False

    def test_dose_per_frame_negative_disables_weighting(self):
        """Negative dose is nonsensical; should not enable weighting."""
        r = _resolve_smart_params({"dose_per_frame": -1.0})
        assert r["use_dose_weighting"] is False

    def test_user_dose_weighting_false_survives_with_positive_dose(self):
        r = _resolve_smart_params({
            "dose_per_frame": 2.0,
            "use_dose_weighting": False,
        })
        assert r["use_dose_weighting"] is False

    def test_user_dose_weighting_true_survives_without_dose(self):
        r = _resolve_smart_params({"use_dose_weighting": True})
        assert r["use_dose_weighting"] is True


# ===========================================================================
# 12. Ancillary parameters (defocus, num_2d_classes, ab initio, particle diam)
# ===========================================================================

class TestAncillaryParams:
    # Defocus
    def test_large_rna_protein_defocus_range(self):
        r = _resolve_smart_params({"sample_class": "large_rna_protein"})
        assert r["defocus_min"] == pytest.approx(1.0)
        assert r["defocus_max"] == pytest.approx(3.0)

    def test_gpcr_g_protein_defocus_range(self):
        r = _resolve_smart_params({"sample_class": "gpcr_g_protein"})
        assert r["defocus_min"] == pytest.approx(0.8)
        assert r["defocus_max"] == pytest.approx(2.0)

    def test_default_defocus_range(self):
        r = _resolve_smart_params({})
        assert r["defocus_min"] == pytest.approx(0.8)
        assert r["defocus_max"] == pytest.approx(2.0)

    # num_2d_classes
    def test_large_rna_protein_100_2d_classes(self):
        r = _resolve_smart_params({"sample_class": "large_rna_protein"})
        assert r["num_2d_classes"] == 100

    def test_symmetric_100_2d_classes(self):
        r = _resolve_smart_params({"sample_class": "symmetric"})
        assert r["num_2d_classes"] == 100

    def test_pore_forming_100_2d_classes(self):
        r = _resolve_smart_params({"sample_class": "pore_forming"})
        assert r["num_2d_classes"] == 100

    def test_soluble_50_2d_classes(self):
        r = _resolve_smart_params({"sample_class": "soluble"})
        assert r["num_2d_classes"] == 50

    # num_ab_initio_classes
    def test_large_rna_protein_6_ab_initio_classes(self):
        r = _resolve_smart_params({"sample_class": "large_rna_protein"})
        assert r["num_ab_initio_classes"] == 6

    def test_symmetric_1_ab_initio_class(self):
        r = _resolve_smart_params({"sample_class": "symmetric"})
        assert r["num_ab_initio_classes"] == 1

    def test_soluble_3_ab_initio_classes(self):
        r = _resolve_smart_params({"sample_class": "soluble"})
        assert r["num_ab_initio_classes"] == 3

    # particle diameter formula
    def test_particle_diameter_formula_200kda(self):
        r = _resolve_smart_params({"molecular_weight_kda": 200})
        expected = round(13.3 * (200 ** (1.0 / 3.0)))
        assert r["particle_diameter"] == expected

    def test_particle_diameter_formula_21kda(self):
        r = _resolve_smart_params({"molecular_weight_kda": 21})
        expected = round(13.3 * (21 ** (1.0 / 3.0)))
        assert r["particle_diameter"] == expected


# ===========================================================================
# 13. Integration / combined scenario tests
# ===========================================================================

class TestIntegrationScenarios:
    def test_mfsd2b_full_scenario(self):
        """MFSD2B: 21 kDa membrane protein, no user overrides."""
        r = _resolve_smart_params({
            "sample_class": "membrane_small",
            "molecular_weight_kda": 21,
        })
        assert r["pixel_size"] == pytest.approx(0.649)
        assert r["box_size_pix"] == 128
        assert r["qc_profile"] == "cryoem_spa_membrane"
        assert r["picker_strategy"] == "blob+template+topaz"
        assert r["total_dose"] == 50

    def test_cav12_full_scenario(self):
        """CaV1.2: 400 kDa membrane_large, no user overrides."""
        r = _resolve_smart_params({
            "sample_class": "membrane_large",
            "molecular_weight_kda": 400,
        })
        assert r["pixel_size"] == pytest.approx(0.83)
        assert r["box_size_pix"] == 256
        assert r["qc_profile"] == "cryoem_spa_membrane"
        assert r["picker_strategy"] == "blob+template"
        assert r["total_dose"] == 50

    def test_spliceosome_full_scenario(self):
        """Spliceosome: 2500 kDa large_rna_protein, no user overrides."""
        r = _resolve_smart_params({
            "sample_class": "large_rna_protein",
            "molecular_weight_kda": 2500,
        })
        assert r["pixel_size"] == pytest.approx(1.08)
        assert r["box_size_pix"] == 256
        assert r["qc_profile"] == "cryoem_spa_purified"
        assert r["picker_strategy"] == "blob+template"
        assert r["total_dose"] == 45
        assert r["num_ab_initio_classes"] == 6

    def test_bax_pore_scenario(self):
        """BAX pore-forming protein scenario."""
        r = _resolve_smart_params({
            "sample_class": "pore_forming",
            "molecular_weight_kda": 120,
            "target_resolution_A": 3.5,
        })
        assert r["picker_strategy"] == "topaz_trained"
        assert r["qc_profile"] == "cryoem_spa_membrane"
        assert r["total_dose"] == 45
        assert r["ctf_refine_level"] == "minimal"

    def test_symmetric_virus_scenario(self):
        """Symmetric virus capsid with known symmetry."""
        r = _resolve_smart_params({
            "sample_class": "symmetric",
            "molecular_weight_kda": 5000,
            "expected_symmetry": "I",
        })
        assert r["pixel_size"] == pytest.approx(1.08)
        assert r["total_dose"] == 55
        assert r["num_ab_initio_classes"] == 1
        assert r.get("refine_symmetry") == "I"
        assert r.get("abinitio_symmetry") == "C1"

    def test_high_res_soluble_with_dose(self):
        """High-resolution soluble target with dose per frame."""
        r = _resolve_smart_params({
            "sample_class": "soluble",
            "molecular_weight_kda": 150,
            "target_resolution_A": 2.2,
            "heterogeneity": "medium",
            "dose_per_frame": 1.2,
        })
        assert r["pixel_size"] == pytest.approx(0.83)
        assert r["target_particle_count"] == 1_000_000
        assert r["ctf_refine_level"] == "full"
        assert r["num_3d_classes"] == 6
        assert r["use_3dva"] is True
        assert r["use_multibody"] is False
        assert r["use_dose_weighting"] is True

    def test_all_user_overrides_survive(self):
        """Every overridable field simultaneously supplied — none should be touched."""
        inp = {
            "sample_class": "membrane_small",
            "pixel_size": 1.5,
            "box_size_pix": 384,
            "picker_strategy": "blob",
            "qc_profile": "custom",
            "total_dose": 60,
            "target_resolution_A": 2.2,
            "target_particle_count": 999,
            "heterogeneity": "high",
            "num_3d_classes": 10,
            "ctf_refine_level": "minimal",
            "use_dose_weighting": False,
            "particle_diameter": 500,
            "num_2d_classes": 75,
            "num_ab_initio_classes": 9,
        }
        r = _resolve_smart_params(inp)
        for key, expected in inp.items():
            assert r[key] == expected, f"Key {key!r} was overwritten: got {r[key]!r}"
