"""Offline tests for the bioRxiv/medRxiv federated source (the Europe PMC call is replaced)."""
import unittest
from unittest import mock

from galaxy.ai import federated_query as fq
from galaxy.ai import data_sources as ds

REPLY = {"resultList": {"result": [
    {"id": "PPR1", "doi": "10.1101/2024.08.24.609537", "title": "Switch-like gene expression modulates disease susceptibility",
     "authorString": "A B, C D", "firstPublicationDate": "2024-08-26", "pubYear": "2024",
     "bookOrReportDetails": {"publisher": "bioRxiv"}, "abstractText": "x" * 900},
    {"id": "PPR2", "title": "no doi", "bookOrReportDetails": {"publisher": "medRxiv"}},
    {"id": "PPR3", "doi": "10.1101/2023.01.01.000001", "title": "A medRxiv preprint", "firstPublicationDate": "2023-01-02",
     "bookOrReportDetails": {"publisher": "medRxiv"}},
]}}


class BiorxivTests(unittest.TestCase):
    def test_rows_are_labelled_preprints_and_incomplete_records_dropped(self):
        with mock.patch.object(fq, "_get", return_value=REPLY) as g:
            out = fq._fetch_biorxiv("switch-like genes")
        url = g.call_args[0][0]
        self.assertIn("SRC%3APPR", url); self.assertIn("bioRxiv", url); self.assertIn("medRxiv", url)
        self.assertEqual(out["source"], "biorxiv")
        self.assertEqual([r["doi"] for r in out["results"]], ["10.1101/2024.08.24.609537", "10.1101/2023.01.01.000001"])
        r = out["results"][0]
        self.assertIs(r["peer_reviewed"], False); self.assertEqual(r["evidence_kind"], "preprint_abstract")
        self.assertEqual((r["server"], r["year"], r["url"]), ("bioRxiv", "2024", "https://doi.org/10.1101/2024.08.24.609537"))
        self.assertEqual(len(r["abstract"]), 500)
        self.assertEqual(out["results"][1]["server"], "medRxiv")

    def test_network_failure_gives_empty_results(self):
        with mock.patch.object(fq, "_get", return_value=None):
            self.assertEqual(fq._fetch_biorxiv("x"), {"source": "biorxiv", "results": []})

    def test_registered_in_fetchers_literature_sources_and_registry(self):
        self.assertIn("biorxiv", fq._FETCHERS)
        self.assertIn("biorxiv", fq.ENTITY_SOURCES["literature"])
        src = {s.id: s for s in ds.SOURCES}["biorxiv"]
        self.assertEqual((src.status, src.surfaces), ("live", [ds.SURFACE_FEDERATION]))



class DedicatedSurfaceTests(unittest.TestCase):
    def test_open_targets_and_geo_are_live_through_dedicated_tools_not_the_fan_out(self):
        src = {s.id: s for s in ds.SOURCES}
        for sid in ("opentargets", "geo"):
            self.assertEqual((src[sid].status, src[sid].surfaces), ("live", [ds.SURFACE_DEDICATED]))
            self.assertNotIn(sid, fq._FETCHERS)          # honest: not a federated fetcher
        self.assertIn("NOT implemented", src["geo"].note)  # accession retrieval only, no keyword discovery
        self.assertEqual(ds.summary()["by_surface"][ds.SURFACE_DEDICATED], 2)


if __name__ == "__main__":
    unittest.main()
