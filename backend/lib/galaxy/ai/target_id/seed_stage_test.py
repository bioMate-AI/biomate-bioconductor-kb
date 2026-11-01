"""Network channels receive the primary channel's top genes as seeds (two-stage run) and fail soft without them."""
import unittest

from galaxy.ai.target_id import MockChannel, TargetIDOrchestrator
from galaxy.ai.target_id.channels import Channel
from galaxy.ai.target_id.network_channels import StringPpiChannel
from galaxy.ai.target_id.types import ChannelResult


class Recorder(Channel):
    needs_seeds = True
    name = "recorder"

    def __init__(self):
        self.contexts = []

    def run(self, context):
        self.contexts.append(dict(context))
        return ChannelResult(channel=self.name, scores={"TP53": 0.5}, provenance={"source": "rec"})


class SeedStageTests(unittest.TestCase):
    def test_string_gets_the_top_primary_genes_as_seeds(self):
        seen = {}
        def http(endpoint, params):
            seen["ids"] = params["identifiers"]
            return [{"preferredName_A": "TP53", "preferredName_B": "MDM2", "score": 0.95}]
        ot = MockChannel("genetics_ot", {"TP53": 0.9, "BRAF": 0.8, "X": 0.1, "Y": 0.05})
        res = TargetIDOrchestrator([ot, StringPpiChannel(http=http)], seed_top_n=2).identify("q").to_dict()
        self.assertEqual(seen["ids"], "TP53\rBRAF")
        self.assertEqual((res["ranking"]["seed_source"], res["ranking"]["n_seed_genes"]), ("genetics_ot", 2))
        self.assertIn("ppi_string", res["channels_run"])
        self.assertEqual(res["ranking"]["mode"], "primary_channel")            # STRING only corroborates; ranking is still Open Targets
        self.assertNotIn("MDM2", [t["target"] for t in res["targets"]])        # expansion genes do not dilute the ranking

    def test_seed_to_seed_edges_give_the_top_genes_their_own_network_corroboration(self):
        rows = [{"preferredName_A": "TP53", "preferredName_B": "BRAF", "score": 0.8},
                {"preferredName_A": "BRAF", "preferredName_B": "TP53", "score": 0.7},
                {"preferredName_A": "BRAF", "preferredName_B": "BRAF", "score": 1.0}]       # self edge must never count
        ot = MockChannel("genetics_ot", {"TP53": 0.9, "BRAF": 0.8})
        plain = StringPpiChannel(http=lambda e, p: rows).run({"seed_genes": ["TP53", "BRAF"]})
        self.assertFalse(plain.ok)                                   # expansion mode: seeds are not candidates
        seeded = StringPpiChannel(http=lambda e, p: rows, include_seed_edges=True).run({"seed_genes": ["TP53", "BRAF"]})
        self.assertEqual(seeded.scores, {"BRAF": 0.8, "TP53": 0.7})
        self.assertTrue(seeded.provenance["seed_to_seed_edges"])
        res = TargetIDOrchestrator([ot, StringPpiChannel(http=lambda e, p: rows, include_seed_edges=True)]).identify("q").to_dict()
        self.assertEqual({t["target"]: "ppi_string" in t["fired_channels"] for t in res["targets"]}, {"TP53": True, "BRAF": True})

    def test_explicit_seed_genes_are_respected(self):
        rec = Recorder()
        res = TargetIDOrchestrator([MockChannel("genetics_ot", {"A": 1.0}), rec]).identify("q", {"seed_genes": ["Z1", "Z2"]}).to_dict()
        self.assertEqual(rec.contexts[0]["seed_genes"], ["Z1", "Z2"])
        self.assertEqual(res["ranking"]["seed_source"], "request")

    def test_seeded_channels_run_after_the_first_stage_never_before(self):
        rec = Recorder()
        TargetIDOrchestrator([rec, MockChannel("genetics_ot", {"A": 1.0})]).identify("q")
        self.assertEqual(rec.contexts[0]["seed_genes"], ["A"])                # channel order does not matter

    def test_without_seeds_the_network_channel_fails_soft_and_visibly(self):
        def down(*a, **k):
            raise RuntimeError("OT down")
        from galaxy.ai.target_id import CallableChannel
        res = TargetIDOrchestrator([CallableChannel("genetics_ot", down), StringPpiChannel(http=lambda e, p: [])]).identify("q").to_dict()
        self.assertIn("seed_genes", res["channel_errors"]["ppi_string"])
        self.assertEqual(res["ranking"]["n_seed_genes"], 0)


if __name__ == "__main__":
    unittest.main()
