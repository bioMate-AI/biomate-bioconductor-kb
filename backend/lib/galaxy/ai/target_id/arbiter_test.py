"""The fusion engine is GENERAL: fuse_channels ranks arbitrary entities from
arbitrary named channels, with no target-ID assumptions. These tests exercise
that generality directly (the engine was previously only reached via target-ID)."""
import unittest

from galaxy.ai.target_id.arbiter import fuse_channels
from galaxy.ai.target_id.types import TargetScore, TargetEvidence


class FuseChannelsGeneralTest(unittest.TestCase):
    def _channels(self):
        # Arbitrary entities (documents), not genes/targets. "doc1" is strong in two
        # independent channels; "doc2" strong in one; the rest are background.
        bg = {f"doc{i}": 1.0 for i in range(3, 10)}
        return [
            ("relevance", dict({"doc1": 9.0, "doc2": 1.0}, **bg)),
            ("recency",   dict({"doc1": 9.0, "doc2": 1.0}, **bg)),
            ("citations", dict({"doc2": 9.0, "doc1": 1.0}, **bg)),
        ]

    def test_fuses_arbitrary_entities(self):
        out = fuse_channels(self._channels(), method="evidence_gate")
        self.assertTrue(out)
        # generic entity names preserved (not coerced to target semantics)
        self.assertTrue(all(isinstance(r["entity"], str) and r["entity"].startswith("doc") for r in out))
        # each row has the full structure
        for r in out:
            self.assertEqual(sorted(r), ["entity", "fired_channels", "n_fired", "per_channel_z", "rank", "score", "tier"])
        # the entity strong in two channels ranks first
        self.assertEqual(out[0]["entity"], "doc1")
        self.assertEqual(out[0]["rank"], 1)
        self.assertGreaterEqual(out[0]["n_fired"], 2)   # corroborated across channels

    def test_harmonic_sum_method_with_generic_weights(self):
        out = fuse_channels(self._channels(), method="harmonic_sum",
                            weights={"relevance": 1.0, "recency": 1.0, "citations": 0.5})
        self.assertTrue(out)
        self.assertEqual(out[0]["entity"], "doc1")      # two full-weight channels win

    def test_accepts_channelresult_and_dict_and_tuple_inputs(self):
        from galaxy.ai.target_id.types import ChannelResult
        mixed = [
            ChannelResult(channel="a", scores={"x": 5.0, "y": 0.0, "z": 0.0}),
            {"channel": "b", "scores": {"x": 5.0, "y": 0.0, "z": 0.0}},
            ("c", {"y": 5.0, "x": 0.0, "z": 0.0}),
        ]
        out = fuse_channels(mixed)
        self.assertEqual(out[0]["entity"], "x")
        self.assertEqual({r["entity"] for r in out}, {"x", "y", "z"})

    def test_top_k_limit(self):
        out = fuse_channels(self._channels(), top_k=3)
        self.assertEqual(len(out), 3)

    def test_entity_alias_on_target_score(self):
        ev = TargetEvidence(target="EGFR")
        s = TargetScore(target="EGFR", score=0.9, tier="corroborated", rank=1, evidence=ev)
        self.assertEqual(s.entity, "EGFR")   # generic alias == target


if __name__ == "__main__":
    unittest.main()
