"""Offline tests for resource_classification (no galaxy.ai package import — load the module by path)."""
import importlib.util
import os
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "resource_classification_under_test",
    str(Path(__file__).with_name("resource_classification.py")),
)
rc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rc)


class ClassifyTests(unittest.TestCase):
    def test_each_group_has_a_representative(self):
        cases = {
            "FASTQC": "light", "MULTIQC": "light", "SAMTOOLS_SORT": "light", "VOLCANO_PLOT": "light",
            "RENDER_REPORT": "light", "TRIMGALORE": "light",
            "BIOC_DESEQ2": "standard", "EDGER_DE": "standard", "CLUSTERPROFILER_ENRICH": "standard",
            "SEURAT_CLUSTER": "standard", "COMBAT_NORMALIZE": "standard",
            "STAR_ALIGN": "heavy", "BWA_MEM": "heavy", "SPADES_ASSEMBLY": "heavy",
            "GATK_HAPLOTYPECALLER": "heavy", "KRAKEN2": "heavy",
            "DOCKING_AUTODOCK_VINA": "shardable", "ADMET_INFER_SHARD": "shardable", "PHARMACOPHORE_SCREEN": "shardable",
        }
        for name, group in cases.items():
            self.assertEqual(rc.classify_process(name), group, name)

    def test_specific_beats_generic(self):
        # "variant" (heavy) must win over "annot" (standard) for a variant-annotation process.
        self.assertEqual(rc.classify_process("VARIANT_ANNOTATION"), "heavy")
        # an ADMET predictor is shardable, not standard (PREDICT).
        self.assertEqual(rc.classify_process("PREDICT_ADMET_PROPERTIES"), "shardable")
        # clusterprofiler enrichment is standard, not matched as a generic CLUSTER.
        self.assertEqual(rc.classify_process("CLUSTERPROFILER_ENRICH"), "standard")

    def test_unmatched_returns_none(self):
        for name in ("REINVENT4_LEAD_DESIGN", "SOME_CUSTOM_STEP", "", "X"):
            self.assertIsNone(rc.classify_process(name))

    def test_classify_nf_text_only_declared_and_matched(self):
        nf = "process FASTQC {\n}\nprocess STAR_ALIGN{\n}\nprocess MYSTERY_STEP {\n}\n// process COMMENTED_OUT {\n"
        out = rc.classify_nf_text(nf)
        self.assertEqual(out, {"FASTQC": "light", "STAR_ALIGN": "heavy"})


class RenderTests(unittest.TestCase):
    def setUp(self):
        self._env = dict(os.environ)

    def tearDown(self):
        os.environ.clear(); os.environ.update(self._env)

    def test_disabled_by_default_renders_nothing(self):
        os.environ.pop(rc.ENV_FLAG, None)
        self.assertFalse(rc.is_enabled())
        self.assertEqual(rc.render_withname_lines("process FASTQC {\n}\n"), [])

    def test_enabled_emits_withname_only_for_present_matched_processes(self):
        os.environ[rc.ENV_FLAG] = "1"
        lines = rc.render_withname_lines("process FASTQC {\n}\nprocess STAR_ALIGN {\n}\nprocess MYSTERY {\n}\n")
        body = "\n".join(lines)
        self.assertTrue(lines[0] == "process {" and lines[-1] == "}")
        self.assertIn("withName: 'FASTQC' { cpus = 2; memory = '8.GB' }", body)
        self.assertIn("withName: 'STAR_ALIGN' { cpus = 12; memory = '64.GB' }", body)
        self.assertNotIn("MYSTERY", body)              # present but unmatched -> no selector -> keeps its label tier

    def test_enabled_but_no_matches_renders_nothing(self):
        os.environ[rc.ENV_FLAG] = "1"
        self.assertEqual(rc.render_withname_lines("process MYSTERY {\n}\n"), [])

    def test_deployment_tier_override_via_env_json(self):
        os.environ[rc.ENV_FLAG] = "1"
        os.environ[rc.ENV_TIERS] = '{"light": {"cpus": 1, "memory_gb": 4}, "heavy": {"cpus": 32}}'
        t = rc.tiers()
        self.assertEqual(t["light"], {"cpus": 1, "memory_gb": 4})
        self.assertEqual(t["heavy"]["cpus"], 32)
        self.assertEqual(t["heavy"]["memory_gb"], 64)  # untouched key keeps the default
        lines = "\n".join(rc.render_withname_lines("process FASTQC {\n}\n"))
        self.assertIn("cpus = 1; memory = '4.GB'", lines)

    def test_malformed_override_is_ignored(self):
        os.environ[rc.ENV_TIERS] = "{not json"
        self.assertEqual(rc.tiers()["light"], {"cpus": 2, "memory_gb": 8})


if __name__ == "__main__":
    unittest.main()
