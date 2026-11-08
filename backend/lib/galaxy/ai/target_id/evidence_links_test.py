"""Every ranked target shows the source behind each channel's score; offline snapshots are used and labelled."""
import json
import os
import tempfile
import unittest

from galaxy.ai.target_id import MockChannel, TargetIDOrchestrator
from galaxy.ai.target_id.channels import LLMReasonedChannel
from galaxy.ai.target_id.client_data import ClientTableChannel
from galaxy.ai.target_id.data_channels import OpenTargetsGeneticsChannel, TableChannel, write_ot_snapshot
from galaxy.ai.target_id.network_channels import StringPpiChannel

EFO = "MONDO_0005105"


def fake_ot(url, payload, **kw):
    return {"data": {"disease": {"name": "melanoma", "associatedTargets": {"count": 3, "rows": [
        {"target": {"id": "ENSG00000157764", "approvedSymbol": "BRAF"}, "score": 0.85},
        {"target": {"id": "ENSG00000147889", "approvedSymbol": "CDKN2A"}, "score": 0.87},
        {"target": {"id": None, "approvedSymbol": "NOID"}, "score": 0.4}]}}}}


class LinkTests(unittest.TestCase):
    def test_open_targets_links_use_the_ensembl_id_and_disease(self):
        r = OpenTargetsGeneticsChannel(http=fake_ot, offline=False).run({"disease_id": EFO})
        self.assertEqual(r.links["BRAF"]["url"], "https://platform.opentargets.org/evidence/ENSG00000157764/%s" % EFO)
        self.assertIn("melanoma", r.links["BRAF"]["label"])
        self.assertTrue(r.links["NOID"]["url"].startswith("https://platform.opentargets.org/search?q=NOID"))
        self.assertEqual(r.provenance["served_from"], "live")

    def test_string_links_are_per_partner(self):
        rows = [{"preferredName_A": "BRAF", "preferredName_B": "MAP2K1", "score": 0.99}]
        r = StringPpiChannel(http=lambda e, p: rows).run({"seed_genes": ["BRAF"]})
        self.assertEqual(r.links["MAP2K1"]["url"], "https://string-db.org/cgi/network?identifiers=MAP2K1&species=9606")

    def test_every_ranked_target_carries_its_sources(self):
        ot = OpenTargetsGeneticsChannel(http=fake_ot, offline=False)
        string = StringPpiChannel(http=lambda e, p: [{"preferredName_A": "BRAF", "preferredName_B": "CDKN2A", "score": 0.9}], include_seed_edges=True)
        llm = LLMReasonedChannel(type("L", (), {"model": "m", "generate": lambda self, p, **k: '{"BRAF": 0.9, "CDKN2A": 0.7}'})())
        client = ClientTableChannel("tumour de", {"BRAF": 0.8}, {"label": "NPC cohort DE", "kind": "differential_expression_up"})
        res = TargetIDOrchestrator([ot, string, llm, client]).identify("melanoma", {"disease_id": EFO}).to_dict()
        top = {t["target"]: t for t in res["targets"]}["BRAF"]
        links = top["evidence_links"]
        self.assertEqual(links["genetics_ot"]["kind"], "public_source")
        self.assertTrue(links["genetics_ot"]["url"].startswith("https://platform.opentargets.org/evidence/ENSG00000157764"))
        self.assertEqual(links["llm_reasoned"], {"kind": "model_judgment", "url": None, "label": "model judgment, no citation"})
        self.assertEqual(links["client_tumour_de"]["kind"], "client_data")
        self.assertIn("NPC cohort DE", links["client_tumour_de"]["label"])
        self.assertEqual(res["ranking"]["seed_source"], "genetics_ot")      # STRING ran on the Open Targets top genes
        self.assertIn("ppi_string", {k for t in res["targets"] for k in t["evidence_links"]})

    def test_table_channel_does_not_leak_the_server_path(self):
        r = TableChannel("/srv/private/dir/depmap.csv", reader=lambda p: [{"target": "A", "score": "1"}]).run({})
        self.assertNotIn("/srv/private", json.dumps(r.provenance))
        self.assertEqual(r.provenance["table"], "depmap.csv")
        bad = TableChannel("/srv/private/dir/missing.csv").run({})
        self.assertNotIn("/srv/private", bad.error)


class SnapshotTests(unittest.TestCase):
    def test_offline_uses_a_labelled_snapshot_and_refuses_when_absent(self):
        with tempfile.TemporaryDirectory() as d:
            path = write_ot_snapshot(EFO, d, http=fake_ot, today="2026-11-01")
            self.assertTrue(os.path.exists(path))
            ch = OpenTargetsGeneticsChannel(offline=True, snapshot_directory=d,
                                            http=lambda *a, **k: (_ for _ in ()).throw(AssertionError("no network when offline")))
            r = ch.run({"disease_id": EFO})
            self.assertTrue(r.ok)
            self.assertEqual(r.provenance["served_from"], "snapshot")
            self.assertEqual(r.provenance["snapshot_date"], "2026-11-01")
            self.assertEqual(r.links["BRAF"]["url"].split("/")[-2], "ENSG00000157764")
            missing = ch.run({"disease_id": "EFO_0000000"})
            self.assertFalse(missing.ok)
            self.assertIn("no snapshot for EFO_0000000", missing.error)
            self.assertIn(EFO, missing.error)                      # lists what IS available

    def test_live_failure_falls_back_to_snapshot_and_says_so(self):
        with tempfile.TemporaryDirectory() as d:
            write_ot_snapshot(EFO, d, http=fake_ot, today="2026-10-01")
            def down(*a, **k):
                raise OSError("network blocked")
            r = OpenTargetsGeneticsChannel(http=down, offline=False, snapshot_directory=d).run({"disease_id": EFO})
            self.assertTrue(r.ok)
            self.assertEqual(r.provenance["served_from"], "snapshot")
            self.assertIn("network blocked", r.provenance["live_error"])

    def test_live_failure_without_snapshot_is_an_explicit_error(self):
        def down(*a, **k):
            raise OSError("network blocked")
        r = OpenTargetsGeneticsChannel(http=down, offline=False).run({"disease_id": EFO})
        self.assertFalse(r.ok)
        self.assertIn("network blocked", r.error)


if __name__ == "__main__":
    unittest.main()
