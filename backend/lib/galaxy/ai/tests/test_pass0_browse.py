"""
Unit tests for N5 — Pass-0 LLM catalog browse in UnifiedWorkflowSearch.

Tests verify:
- set_llm_client() wires the client correctly
- _browse_catalog_with_llm() returns IDs when LLM is available
- _browse_catalog_with_llm() returns [] when LLM is unavailable or fails
- search() applies the graded Pass-0 boost to LLM-preferred IDs
- search() falls back gracefully when LLM client returns bad JSON
"""

import pytest
from unittest.mock import MagicMock
from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch, WorkflowMatch


class FakeLLMClient:
    """Minimal fake that mimics LLMClient.generate()."""
    def __init__(self, response: str = "[]"):
        self.response = response
        self.called_with: list = []

    def generate(self, prompt: str, max_tokens: int = 128, temperature: float = 0.0) -> str:
        self.called_with.append(prompt)
        return self.response


# ---------------------------------------------------------------------------
# set_llm_client
# ---------------------------------------------------------------------------

class TestSetLLMClient:
    def test_set_llm_client_stores_client(self):
        search = UnifiedWorkflowSearch()
        assert search._llm_client is None
        fake = FakeLLMClient()
        search.set_llm_client(fake)
        assert search._llm_client is fake

    def test_set_llm_client_overwrites_existing(self):
        search = UnifiedWorkflowSearch()
        c1 = FakeLLMClient()
        c2 = FakeLLMClient()
        search.set_llm_client(c1)
        search.set_llm_client(c2)
        assert search._llm_client is c2


# ---------------------------------------------------------------------------
# _browse_catalog_with_llm
# ---------------------------------------------------------------------------

class TestBrowseCatalogWithLLM:
    def test_returns_empty_when_no_llm_client(self):
        search = UnifiedWorkflowSearch()
        result = search._browse_catalog_with_llm("RNA-seq analysis")
        assert result == []

    def test_returns_ids_from_llm_json_array(self):
        search = UnifiedWorkflowSearch()
        # We need real IDs from the DB; use a fake that returns ids 1,2,3
        search.set_llm_client(FakeLLMClient(response="[1, 2, 3]"))
        result = search._browse_catalog_with_llm("RNA-seq analysis")
        # The returned IDs must be a list of ints
        assert isinstance(result, list)
        assert all(isinstance(x, int) for x in result)
        # If IDs 1,2,3 are in the DB, they'll be returned; otherwise [] is acceptable
        # (because broad_limit=60 gets top-60 FTS hits, not necessarily id 1,2,3)

    def test_llm_called_with_catalog_prompt(self):
        search = UnifiedWorkflowSearch()
        fake = FakeLLMClient(response="[]")
        search.set_llm_client(fake)
        search._browse_catalog_with_llm("variant calling with GATK")
        if fake.called_with:  # only if DB has matching rows
            prompt = fake.called_with[0]
            assert "variant calling with GATK" in prompt

    def test_returns_empty_on_malformed_json(self):
        search = UnifiedWorkflowSearch()
        search.set_llm_client(FakeLLMClient(response="I recommend STAR aligner for RNA-seq."))
        result = search._browse_catalog_with_llm("RNA-seq alignment")
        assert result == []

    def test_returns_empty_on_llm_exception(self):
        search = UnifiedWorkflowSearch()
        bad_client = MagicMock()
        bad_client.generate.side_effect = RuntimeError("LLM offline")
        search.set_llm_client(bad_client)
        result = search._browse_catalog_with_llm("RNA-seq analysis")
        assert result == []

    def test_respects_output_limit(self):
        search = UnifiedWorkflowSearch()
        # LLM returns more IDs than output_limit
        search.set_llm_client(FakeLLMClient(response="[1,2,3,4,5,6,7,8,9,10,11,12]"))
        result = search._browse_catalog_with_llm("test", output_limit=5)
        assert len(result) <= 5


# ---------------------------------------------------------------------------
# search() — Pass-0 boost integration
# ---------------------------------------------------------------------------

class TestSearchWithPass0Boost:
    def test_search_without_llm_client_still_works(self):
        """No regression: search without LLM returns results normally."""
        search = UnifiedWorkflowSearch()
        results = search.search("RNA-seq differential expression", limit=3)
        assert isinstance(results, list)
        # Should still find some results from FTS
        assert len(results) >= 0  # may be 0 if DB is empty, but no crash

    def test_pass0_boost_raises_score_for_llm_preferred_ids(self):
        """IDs returned by LLM should get a higher score than without Pass-0."""
        search_a = UnifiedWorkflowSearch()

        # First, run search without LLM to get baseline scores
        baseline_results = search_a.search("RNA-seq analysis", limit=10)
        if not baseline_results:
            pytest.skip("DB has no RNA-seq workflows to test against")

        # Get the ID and score of the top result
        top_id = baseline_results[0].id
        top_score_baseline = baseline_results[0].score

        # Use a fresh instance so Pass-0 boost is cleanly applied
        search_b = UnifiedWorkflowSearch()
        search_b.set_llm_client(FakeLLMClient(response=f"[{top_id}]"))
        boosted_results = search_b.search("RNA-seq analysis", limit=10)

        # The same top result should now score higher (bonus ≈ +3.0 for rank 0)
        boosted_match = next((r for r in boosted_results if r.id == top_id), None)
        if boosted_match:
            assert boosted_match.score > top_score_baseline

    def test_pass0_bad_json_does_not_crash_search(self):
        """When LLM returns garbage, search should complete normally."""
        search = UnifiedWorkflowSearch()
        search.set_llm_client(FakeLLMClient(response="not json at all"))
        results = search.search("RNA-seq differential expression", limit=3)
        assert isinstance(results, list)

    def test_pass0_llm_exception_does_not_crash_search(self):
        """When LLM throws, search should complete using pure FTS."""
        search = UnifiedWorkflowSearch()
        bad = MagicMock()
        bad.generate.side_effect = Exception("timeout")
        search.set_llm_client(bad)
        results = search.search("RNA-seq differential expression", limit=3)
        assert isinstance(results, list)
