"""Offline tests for ingest_ctgov and llm_map (fake LLM; real SQLite FTS5 index in a temp dir)."""
import json
import os
import tempfile
import unittest

from galaxy.ai.corpus_fs.index import Fts5CorpusIndex
from galaxy.ai.corpus_fs.ingest_ctgov import ctgov_to_record
from galaxy.ai.corpus_fs import llm_map as lm

STUDY = {
    "protocolSection": {
        "identificationModule": {"nctId": "NCT00000001", "briefTitle": "Drug X in lupus", "officialTitle": "A Phase 2 trial of Drug X"},
        "statusModule": {"overallStatus": "TERMINATED", "whyStopped": "Lack of efficacy at interim analysis",
                         "startDateStruct": {"date": "2018-03"}},
        "descriptionModule": {"briefSummary": "Drug X was tested against placebo in adults with lupus nephritis."},
        "conditionsModule": {"conditions": ["Lupus Nephritis"]},
        "designModule": {"studyType": "INTERVENTIONAL", "phases": ["PHASE2"], "enrollmentInfo": {"count": 120}},
        "armsInterventionsModule": {"interventions": [{"type": "DRUG", "name": "Drug X", "otherNames": ["DX-1"]}]},
        "outcomesModule": {"primaryOutcomes": [{"measure": "Complete renal response", "timeFrame": "52 weeks"}]},
        "eligibilityModule": {"eligibilityCriteria": "Adults aged 18 to 65 with biopsy-proven lupus nephritis."},
    },
    "hasResults": False,
}


class FakeLLM:
    def __init__(self, replies):
        self.replies, self.calls = list(replies), []

    def generate(self, prompt, **kw):
        self.calls.append(prompt)
        return self.replies.pop(0)


def make_index(tmp):
    idx = Fts5CorpusIndex(os.path.join(tmp, "c.db"))
    idx.ingest([ctgov_to_record(STUDY), ctgov_to_record({**STUDY, "protocolSection": {**STUDY["protocolSection"],
                "identificationModule": {"nctId": "NCT00000002", "briefTitle": "Other"}}})])
    return idx


class IngestTests(unittest.TestCase):
    def test_record_shape_and_grounded_sections(self):
        r = ctgov_to_record(STUDY)
        self.assertEqual((r["doc_id"], r["year"], r["source"]), ("NCT00000001", 2018, "ClinicalTrials.gov"))
        secs = {b["section"]: b["text"] for b in r["blocks"]}
        self.assertIn("Why stopped: Lack of efficacy at interim analysis", secs["Status"])
        self.assertIn("also known as DX-1", secs["Interventions"])
        self.assertIn("Phase: PHASE2", secs["Design"])
        self.assertNotIn("Results", secs)

    def test_bad_input_returns_none(self):
        self.assertIsNone(ctgov_to_record({}))
        self.assertIsNone(ctgov_to_record({"protocolSection": {"identificationModule": {"nctId": "NCT1"}}}))

    def test_index_round_trip(self):
        with tempfile.TemporaryDirectory() as t:
            idx = make_index(t)
            self.assertIn("/papers/NCT00000001/sections/Status.lines", idx.ls("NCT00000001"))
            hits = idx.grep("efficacy")
            self.assertEqual(hits[0]["doc_id"], "NCT00000001")


class LlmMapTests(unittest.TestCase):
    Q = "Why was the trial stopped?"

    def run_one(self, replies, **kw):
        with tempfile.TemporaryDirectory() as t:
            idx = make_index(t)
            llm = FakeLLM(replies)
            return lm.llm_corpus_map(idx, self.Q, ["NCT00000001"], llm, **kw), llm

    def test_verified_answer_is_kept(self):
        reply = json.dumps({"answerable": True, "answer": "Lack of efficacy",
                            "evidence": [{"section": "Status", "quote": "Why stopped:  lack of EFFICACY at interim analysis"}], "confidence": 0.9})
        out, llm = self.run_one([reply, '{"verdict": "accept", "reason": "ok"}'])
        r = out["results"][0]
        self.assertEqual((r["status"], r["answer"]), ("answered", "Lack of efficacy"))
        self.assertEqual(out["reduced"]["by_status"], {"answered": 1})
        self.assertEqual(len(llm.calls), 2)

    def test_quote_not_in_document_makes_the_answer_unsupported(self):
        reply = json.dumps({"answerable": True, "answer": "Safety signal",
                            "evidence": [{"section": "Status", "quote": "stopped because of a hepatic safety signal"}]})
        out, _ = self.run_one([reply], with_reviewer=False)
        r = out["results"][0]
        self.assertEqual(r["status"], "unsupported")
        self.assertIsNone(r["answer"]); self.assertEqual(r["claimed_answer"], "Safety signal")
        self.assertEqual(r["rejected_evidence"][0]["reason"], "quote_not_in_section")
        self.assertEqual(out["reduced"]["answers"], [])

    def test_quote_cited_to_the_wrong_section_is_rejected(self):
        reply = json.dumps({"answerable": True, "answer": "x",
                            "evidence": [{"section": "Summary", "quote": "Lack of efficacy at interim analysis"}]})
        out, _ = self.run_one([reply], with_reviewer=False)
        self.assertEqual(out["results"][0]["status"], "unsupported")

    def test_short_or_malformed_evidence_is_rejected(self):
        reply = json.dumps({"answerable": True, "answer": "x", "evidence": [{"section": "Status", "quote": "Why"}, "junk", {"quote": "q"}]})
        out, _ = self.run_one([reply], with_reviewer=False)
        r = out["results"][0]
        self.assertEqual((r["status"], len(r["rejected_evidence"])), ("unsupported", 3))

    def test_reviewer_reject_overrides_a_verified_answer(self):
        reply = json.dumps({"answerable": True, "answer": "Efficacy",
                            "evidence": [{"section": "Status", "quote": "Lack of efficacy at interim analysis"}]})
        out, _ = self.run_one([reply, '{"verdict": "reject", "reason": "does not state a cause"}'])
        r = out["results"][0]
        self.assertEqual((r["status"], r["answer"]), ("rejected_by_reviewer", None))

    def test_not_answerable_and_unparseable(self):
        out, _ = self.run_one(['{"answerable": false, "answer": "", "evidence": []}'], with_reviewer=False)
        self.assertEqual(out["results"][0]["status"], "not_answerable")
        out, _ = self.run_one(["I cannot answer in JSON"], with_reviewer=False)
        self.assertEqual(out["results"][0]["status"], "unparseable")

    def test_one_failing_document_does_not_stop_the_others(self):
        with tempfile.TemporaryDirectory() as t:
            idx = make_index(t)
            ok = json.dumps({"answerable": False, "answer": "", "evidence": []})

            class Flaky(FakeLLM):
                def generate(self, prompt, **kw):
                    if "NCT00000001" in prompt:
                        raise RuntimeError("llm down")
                    return ok
            out = lm.llm_corpus_map(idx, self.Q, ["NCT00000001", "NCT00000002"], Flaky([]), with_reviewer=False)
        self.assertEqual(len(out["errors"]), 1)
        self.assertEqual([r["doc_id"] for r in out["results"] if r], ["NCT00000002"])
        self.assertEqual(out["reduced"]["n_docs"], 1)

    def test_synthesis_removes_ids_that_are_not_inputs(self):
        reduced = {"answers": [{"doc_id": "NCT00000001", "answer": "Efficacy", "evidence": [{"quote": "Lack of efficacy at interim analysis"}]}]}
        llm = FakeLLM(["Trials stopped for efficacy [NCT00000001] and also NCT99999999 PMID 12345678."])
        out = lm.synthesize(self.Q, reduced, llm)
        self.assertEqual(out["unknown_ids_removed"], ["NCT99999999", "PMID 12345678"])
        self.assertNotIn("NCT99999999", out["text"]); self.assertIn("NCT00000001", out["text"])
        self.assertEqual(lm.synthesize(self.Q, {"answers": []}, FakeLLM([]))["unknown_ids_removed"], [])

    def test_extract_json_handles_prose_and_nested_braces(self):
        self.assertEqual(lm.extract_json('text {"a": {"b": 1}} more'), {"a": {"b": 1}})
        self.assertIsNone(lm.extract_json("no json")); self.assertIsNone(lm.extract_json(None))


if __name__ == "__main__":
    unittest.main()
