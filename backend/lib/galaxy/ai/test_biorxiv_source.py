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



class ClinicalTrialsTests(unittest.TestCase):
    REPLY = {"studies": [
        {"protocolSection": {"identificationModule": {"nctId": "NCT00000001", "briefTitle": "Drug X in lupus"},
                             "statusModule": {"overallStatus": "TERMINATED", "whyStopped": "Lack of efficacy", "startDateStruct": {"date": "2018-03"}},
                             "sponsorCollaboratorsModule": {"leadSponsor": {"name": "Acme"}}, "conditionsModule": {"conditions": ["Lupus"]},
                             "designModule": {"phases": ["PHASE2"]}, "armsInterventionsModule": {"interventions": [{"name": "Drug X"}]}},
         "hasResults": True},
        {"protocolSection": {"identificationModule": {}}},
    ]}

    def test_rows_carry_registry_fields_and_skip_records_without_an_id(self):
        with mock.patch.object(fq, "_get", return_value=self.REPLY) as g:
            out = fq._fetch_clinicaltrials("lupus Drug X")
        self.assertIn("clinicaltrials.gov/api/v2/studies", g.call_args[0][0])
        self.assertEqual(len(out["results"]), 1)
        r = out["results"][0]
        self.assertEqual((r["nct_id"], r["status"], r["why_stopped"], r["phases"], r["has_results"]),
                         ("NCT00000001", "TERMINATED", "Lack of efficacy", ["PHASE2"], True))
        self.assertEqual(r["url"], "https://clinicaltrials.gov/study/NCT00000001")
        self.assertEqual(r["evidence_kind"], "registry_record")

    def test_failure_gives_empty_and_registration(self):
        with mock.patch.object(fq, "_get", return_value=None):
            self.assertEqual(fq._fetch_clinicaltrials("x"), {"source": "clinicaltrials", "results": []})
        self.assertIn("clinicaltrials", fq._FETCHERS)
        self.assertIn("clinicaltrials", fq.ENTITY_SOURCES["disease"])
        src = {x.id: x for x in ds.SOURCES}["clinicaltrials"]
        self.assertEqual((src.status, src.category), ("live", "clinical"))



class FailureVisibilityTests(unittest.TestCase):
    """A swallowed HTTP failure must surface as an error, never as "ok, 0 results"."""

    def _http_error(self, code):
        import urllib.error
        return urllib.error.HTTPError("https://api.semanticscholar.org/x", code, "Too Many Requests", {}, None)

    def test_rate_limited_source_is_reported_as_an_error_with_the_status_code(self):
        with mock.patch.object(fq.urllib.request, "urlopen", side_effect=self._http_error(429)):
            res = fq._run_fetcher(fq._fetch_semantic_scholar, "kras")
        self.assertEqual(res["status"], "error")
        self.assertIn("HTTP 429", res["error"]); self.assertIn("semanticscholar", res["error"])
        self.assertEqual(res["results"], [])

    def test_failure_with_some_results_is_kept_as_a_warning_not_an_error(self):
        def fetcher(q):
            fq._note_failure("https://x.org/a", self._http_error(500))
            return {"source": "x", "results": [{"title": "t"}]}
        res = fq._run_fetcher(fetcher, "q")
        self.assertNotIn("error", res); self.assertIn("HTTP 500 from x.org", res["warnings"][0])

    def test_error_state_does_not_leak_between_fetchers_on_one_thread(self):
        fq._note_failure("https://x.org/a", self._http_error(503))
        res = fq._run_fetcher(lambda q: {"source": "ok", "results": []}, "q")
        self.assertNotIn("error", res)

    def test_fan_out_lists_the_failed_source_and_skips_the_cache(self):
        boom = lambda q: (fq._note_failure("https://api.semanticscholar.org/x", self._http_error(429)) or {"source": "semantic_scholar", "results": []})
        fine = lambda q: {"source": "pubmed", "results": [{"title": "paper", "pmid": "1"}]}
        stored = []
        with mock.patch.dict(fq._FETCHERS, {"semantic_scholar": boom, "pubmed": fine}), \
             mock.patch.object(fq, "_cache_get", return_value=None), mock.patch.object(fq, "_cache_set", side_effect=lambda *a: stored.append(a)):
            out = fq.federated_query("kras g12c", entity_type="literature", sources=["semantic_scholar", "pubmed"])
        self.assertEqual(out["sources_failed"], ["semantic_scholar"]); self.assertEqual(out["sources_succeeded"], ["pubmed"])
        self.assertIn("HTTP 429", out["results"]["semantic_scholar"]["error"])
        self.assertEqual(stored, [])

    def test_semantic_scholar_sends_the_api_key_only_when_configured(self):
        with mock.patch.object(fq, "_get", return_value={"data": []}) as g, mock.patch.dict(fq.os.environ, {"SEMANTIC_SCHOLAR_API_KEY": "k123"}):
            fq._fetch_semantic_scholar("x")
        self.assertEqual(g.call_args.kwargs.get("headers"), {"x-api-key": "k123"})
        with mock.patch.object(fq, "_get", return_value={"data": []}) as g, mock.patch.dict(fq.os.environ, {"SEMANTIC_SCHOLAR_API_KEY": ""}):
            fq._fetch_semantic_scholar("x")
        self.assertIsNone(g.call_args.kwargs.get("headers"))


if __name__ == "__main__":
    unittest.main()
