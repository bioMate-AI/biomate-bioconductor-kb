"""Offline scientific boundary tests: real orchestrator/ranker, external evidence fixtures."""
import unittest
from pathlib import Path
from . import TargetIDOrchestrator, MockChannel, CallableChannel


class ChatContractTest(unittest.TestCase):
    def test_default_keeps_ot_order_and_serializes_provenance_and_conflicts(self):
        ot = MockChannel("genetics_ot", {"A": .9, "B": .8}, {"source": "OT fixture", "disease_id": "EFO_1"})
        other = MockChannel("llm_reasoned", {"A": 0, "B": 1}, {"source": "LLM fixture"})
        result = TargetIDOrchestrator([ot, other]).identify("q").to_dict()
        self.assertEqual([t["target"] for t in result["targets"]], ["A", "B"])
        self.assertEqual(result["ranking"]["mode"], "primary_channel")
        self.assertEqual(result["ranking"]["primary_channel"], "genetics_ot")
        self.assertEqual(result["channel_provenance"]["genetics_ot"]["disease_id"], "EFO_1")
        self.assertIn("conflict", result["targets"][0])
        self.assertIn("note", result["targets"][0])
        self.assertEqual(result["ranking"]["evidence_value_type"], "normalized_score")

    def test_failed_primary_never_masquerades_as_ot_evidence(self):
        def failed(_context):
            raise RuntimeError("external OT unavailable")
        ot = CallableChannel("genetics_ot", failed)
        other = MockChannel("llm_reasoned", {"B": .8})
        result = TargetIDOrchestrator([ot, other]).identify("q").to_dict()
        self.assertEqual(result["ranking"]["mode"], "weighted_harmonic_sum")
        self.assertIsNone(result["ranking"]["primary_channel"])
        self.assertEqual(result["ranking"]["requested_primary_channel"], "genetics_ot")
        self.assertIn("genetics_ot", result["channel_errors"])
        self.assertNotIn("genetics_ot", result["channel_provenance"])

    def test_all_channels_empty_is_explicit(self):
        result = TargetIDOrchestrator([MockChannel("genetics_ot", {})]).identify("q").to_dict()
        self.assertEqual(result["targets"], [])
        self.assertEqual(result["channels_run"], [])
        self.assertIsNone(result["ranking"]["primary_channel"])

    def test_explicit_candidates_do_not_return_unrelated_top_ot_genes(self):
        ot = MockChannel("genetics_ot", {"OTHER": 1, "BRAF": .9, "TP53": .8})
        result = TargetIDOrchestrator([ot]).identify("q", {"candidate_targets": ["braf", "MISSING"]}).to_dict()
        self.assertEqual([t["target"] for t in result["targets"]], ["BRAF"])
        self.assertEqual(result["targets"][0]["rank"], 1)
        self.assertEqual(result["ranking"]["unscored_candidates"], ["MISSING"])

    def test_http_route_does_not_override_the_audited_default(self):
        source = (Path(__file__).parents[2] / "webapps/galaxy/api/target_id_api.py").read_text()
        self.assertNotIn("arbiter=HarmonicSumArbiter()", source)


if __name__ == "__main__":
    unittest.main()
