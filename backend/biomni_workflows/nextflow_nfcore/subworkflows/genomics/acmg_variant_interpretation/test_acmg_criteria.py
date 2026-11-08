#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Unit tests for acmg_criteria.py -- deterministic ACMG criteria thresholds.

Run:
    python -m pytest test_acmg_criteria.py           # if pytest available
    python test_acmg_criteria.py                     # plain stdlib runner

Python 3.9-safe; uses unittest so it runs with no third-party deps.
"""
from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import acmg_criteria as ac  # noqa: E402


class TestBA1(unittest.TestCase):
    def test_common_variant_fires(self):
        c = ac.eval_ba1({"gnomad_af": 0.08})
        self.assertTrue(c.applied)
        self.assertEqual(c.direction, "benign")
        self.assertEqual(c.evidence["gnomad_af"], 0.08)

    def test_boundary_exactly_5pct_does_not_fire(self):
        # BA1 is strictly > 0.05
        c = ac.eval_ba1({"gnomad_af": 0.05})
        self.assertFalse(c.applied)

    def test_rare_variant_not_ba1(self):
        c = ac.eval_ba1({"gnomad_af": 0.001})
        self.assertFalse(c.applied)

    def test_missing_af_unknown(self):
        c = ac.eval_ba1({})
        self.assertIsNone(c.applied)

    def test_uses_max_across_populations(self):
        c = ac.eval_ba1({"gnomad_af": 0.001, "gnomad_af_grpmax": 0.07})
        self.assertTrue(c.applied)
        self.assertEqual(c.evidence["source_field"], "gnomad_af_grpmax")


class TestBS1(unittest.TestCase):
    def test_fires_between_default_and_ba1(self):
        c = ac.eval_bs1({"gnomad_af": 0.02})  # >1% and <=5%
        self.assertTrue(c.applied)
        self.assertEqual(c.direction, "benign")

    def test_ba1_supersedes(self):
        c = ac.eval_bs1({"gnomad_af": 0.09})  # >5% -> BA1 territory
        self.assertFalse(c.applied)
        self.assertIn("supersedes", c.rationale)

    def test_below_threshold_not_fired(self):
        c = ac.eval_bs1({"gnomad_af": 0.005})
        self.assertFalse(c.applied)

    def test_custom_max_credible_af(self):
        # With a stricter gene-specific max credible AF of 0.0005, 0.001 fires.
        c = ac.eval_bs1({"gnomad_af": 0.001}, max_credible_af=0.0005)
        self.assertTrue(c.applied)
        self.assertEqual(c.evidence["threshold"], 0.0005)

    def test_missing_af_unknown(self):
        c = ac.eval_bs1({})
        self.assertIsNone(c.applied)


class TestPM2(unittest.TestCase):
    def test_ultrarare_fires(self):
        c = ac.eval_pm2_supporting({"gnomad_af": 0.00001})
        self.assertTrue(c.applied)
        self.assertEqual(c.direction, "pathogenic")
        self.assertEqual(c.strength, "supporting")

    def test_boundary_not_fired(self):
        c = ac.eval_pm2_supporting({"gnomad_af": 0.0001})  # not strictly <
        self.assertFalse(c.applied)

    def test_common_not_fired(self):
        c = ac.eval_pm2_supporting({"gnomad_af": 0.02})
        self.assertFalse(c.applied)

    def test_absent_but_queried_fires(self):
        c = ac.eval_pm2_supporting({"gnomad_queried": True})
        self.assertTrue(c.applied)
        self.assertEqual(c.evidence["gnomad_af"], 0.0)

    def test_absent_not_queried_unknown(self):
        # Absence unconfirmed -> we must NOT claim PM2.
        c = ac.eval_pm2_supporting({})
        self.assertIsNone(c.applied)


class TestPP3BP4(unittest.TestCase):
    def test_revel_pathogenic_pp3(self):
        c = ac.eval_pp3_bp4({"revel": 0.9})
        self.assertEqual(c.code, "PP3")
        self.assertTrue(c.applied)

    def test_revel_benign_bp4(self):
        c = ac.eval_pp3_bp4({"revel": 0.1})
        self.assertEqual(c.code, "BP4")
        self.assertTrue(c.applied)

    def test_revel_intermediate_no_call(self):
        c = ac.eval_pp3_bp4({"revel": 0.5})
        self.assertIsNone(c.applied)

    def test_alphamissense_pathogenic(self):
        c = ac.eval_pp3_bp4({"alphamissense": 0.9})
        self.assertEqual(c.code, "PP3")

    def test_alphamissense_class_string(self):
        c = ac.eval_pp3_bp4({"am_class": "likely_pathogenic"})
        self.assertEqual(c.code, "PP3")

    def test_concordant_predictors_pp3(self):
        c = ac.eval_pp3_bp4({"revel": 0.9, "alphamissense": 0.9, "cadd_phred": 30})
        self.assertEqual(c.code, "PP3")
        self.assertEqual(len(c.evidence["concordant_predictors"]), 3)

    def test_conflicting_predictors_no_call(self):
        # REVEL says pathogenic, AlphaMissense says benign -> conflict -> neither.
        c = ac.eval_pp3_bp4({"revel": 0.9, "alphamissense": 0.1})
        self.assertFalse(c.applied)
        self.assertIn("conflict", c.evidence)

    def test_no_predictors_unknown(self):
        c = ac.eval_pp3_bp4({})
        self.assertIsNone(c.applied)


class TestPVS1(unittest.TestCase):
    def test_lof_in_intolerant_gene_flagged(self):
        c = ac.eval_pvs1_flag({"consequence": "stop_gained", "pli": 0.99})
        self.assertEqual(c.applied, "flag")
        self.assertIn("FLAGGED", c.rationale)

    def test_lof_intolerant_by_loeuf(self):
        c = ac.eval_pvs1_flag({"consequence": "frameshift_variant", "loeuf": 0.2})
        self.assertEqual(c.applied, "flag")

    def test_lof_in_tolerant_gene_not_applied(self):
        c = ac.eval_pvs1_flag({"consequence": "stop_gained", "pli": 0.1})
        self.assertFalse(c.applied)

    def test_lof_no_constraint_unknown(self):
        c = ac.eval_pvs1_flag({"consequence": "splice_donor_variant"})
        self.assertIsNone(c.applied)

    def test_missense_not_lof(self):
        c = ac.eval_pvs1_flag({"consequence": "missense_variant", "pli": 0.99})
        self.assertFalse(c.applied)

    def test_flag_does_not_contribute_points(self):
        # A 'flag' must NOT inflate the provisional tier as if it were applied.
        res = ac.classify({"consequence": "stop_gained", "pli": 0.99,
                           "gnomad_queried": True})
        # PVS1 flagged + PM2 applied (absent, queried). Points from PM2 only (+1).
        self.assertEqual(res["provisional"]["points"], 1)
        self.assertEqual(len(res["flagged_criteria"]), 1)


class TestClassifyIntegration(unittest.TestCase):
    def test_ba1_overrides_to_benign(self):
        res = ac.classify({"gnomad_af": 0.10, "revel": 0.9})
        self.assertIn("Benign", res["provisional"]["tier"])
        # ClinVar not present -> reference is None
        self.assertIsNone(res["clinvar_reference"])

    def test_missing_evidence_defaults_vus(self):
        res = ac.classify({"consequence": "missense_variant"})
        self.assertIn("VUS", res["provisional"]["tier"])
        self.assertTrue(res["provisional"]["default_toward_vus_on_missing_evidence"])

    def test_expert_criteria_always_listed(self):
        res = ac.classify({"gnomad_af": 0.001})
        codes = {c["code"] for c in res["requires_expert_review"]}
        for must in ("PS3", "PP1", "PM3", "PM1", "PS1"):
            self.assertIn(must, codes)

    def test_pathogenic_support_stacks(self):
        # ultra-rare (PM2 +1) + concordant in-silico (PP3 +1) -> still VUS band
        # by points, correctly (only 2 points), NOT auto-pathogenic.
        res = ac.classify({"gnomad_af": 0.00001, "revel": 0.9,
                           "alphamissense": 0.9})
        self.assertEqual(res["provisional"]["points"], 2)
        self.assertIn("VUS", res["provisional"]["tier"])

    def test_clinvar_reference_surfaced_not_used(self):
        res = ac.classify({"gnomad_af": 0.001,
                           "clinvar_sig": "Pathogenic",
                           "clinvar_review": "reviewed_by_expert_panel"})
        cv = res["clinvar_reference"]
        self.assertEqual(cv["clinical_significance"], "Pathogenic")
        self.assertEqual(cv["review_stars"], 3)
        # ClinVar 'Pathogenic' must NOT push the computed tier to pathogenic.
        self.assertNotIn("Pathogenic (computed)", res["provisional"]["tier"])


class TestEvidenceGate(unittest.TestCase):
    def test_empty_evidence_fails_gate(self):
        ok, missing = ac.has_minimum_evidence({})
        self.assertFalse(ok)
        self.assertEqual(len(missing), 3)

    def test_af_only_passes(self):
        ok, _ = ac.has_minimum_evidence({"gnomad_af": 0.01})
        self.assertTrue(ok)

    def test_consequence_only_passes(self):
        ok, _ = ac.has_minimum_evidence({"consequence": "stop_gained"})
        self.assertTrue(ok)

    def test_predictor_only_passes(self):
        ok, _ = ac.has_minimum_evidence({"revel": 0.5})
        self.assertTrue(ok)


class TestDeterminismAndNoRNG(unittest.TestCase):
    def test_identical_input_identical_output(self):
        ev = {"gnomad_af": 0.00001, "revel": 0.9, "consequence": "missense_variant"}
        a = ac.classify(dict(ev))
        b = ac.classify(dict(ev))
        self.assertEqual(a["provisional"], b["provisional"])
        self.assertEqual(a["applied_criteria"], b["applied_criteria"])

    def test_no_random_module_imported(self):
        # Check only executable code lines (strip comments) so that prose in
        # docstrings/comments describing the no-RNG guarantee does not trip it.
        import acmg_criteria as m
        code_lines = []
        for line in open(m.__file__):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            # drop trailing inline comments
            if "#" in line:
                line = line.split("#", 1)[0]
            code_lines.append(line)
        code = "".join(code_lines)
        # remove docstrings crudely: acmg_criteria uses triple-double-quotes
        import re as _re
        code = _re.sub(r'"""(?:.|\n)*?"""', "", code)
        self.assertNotIn("import random", code)
        self.assertNotIn("random(", code)
        self.assertNotIn("np.random", code)
        self.assertNotIn("numpy.random", code)


def _run_stdlib():
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(_run_stdlib())
