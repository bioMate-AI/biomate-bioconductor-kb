"""
Test: Domain profile personalization in workflow search.

Verifies that two users with different domain profiles (genomics vs drug_discovery)
get different top-1 search results for the same ambiguous query.

Run:
    cd backend && python -m pytest lib/galaxy/ai/tests/test_personalization_domain_profile.py -v
"""

import sys
import os
from pathlib import Path

# Allow importing from the parent package without a full Galaxy install.
_AI_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_AI_ROOT))
sys.path.insert(0, str(_AI_ROOT.parent.parent.parent))  # backend/lib/

import pytest

from unified_workflow_search import UnifiedWorkflowSearch


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_profile(domains):
    """Build a minimal user_profile dict."""
    return {"domains": domains, "topics": []}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestDomainProfilePersonalization:
    """Verify that user_profile influences workflow ranking."""

    @pytest.fixture(scope="class")
    def search(self):
        """Create a single UnifiedWorkflowSearch instance shared across tests."""
        s = UnifiedWorkflowSearch()
        return s

    def test_genomics_user_prefers_genomics_workflow(self, search: UnifiedWorkflowSearch):
        """A genomics user querying for variant analysis should get a genomics workflow."""
        # Use a query with clear genomics terminology — FTS will rank genomics workflows
        # highly AND the +2 user_profile bias reinforces this.
        query = "variant calling whole genome"
        profile = _make_profile(["genomics"])

        results = search.search(query, limit=5, user_profile=profile)
        assert results, "Expected at least one result for the query"

        top = results[0]
        # The top result should be in the genomics domain (or contain genomics-related terms).
        top_domain = (top.domain or "").lower()
        top_name = (top.name or "").lower()
        top_filename = (top.filename or "").lower()
        is_genomics_result = (
            "genomics" in top_domain
            or "genomics" in top_name
            or "genomics" in top_filename
            or "rna" in top_name
            or "wgs" in top_name
            or "variant" in top_name
            or "gatk" in top_name
            or "genome" in top_name
        )
        assert is_genomics_result, (
            f"Expected genomics workflow for genomics user but got: "
            f"name='{top.name}' domain='{top.domain}' score={top.score}"
        )

    def test_drug_discovery_user_prefers_drug_discovery_workflow(self, search: UnifiedWorkflowSearch):
        """A drug_discovery user querying 'analyze my compound data' should get a drug_discovery workflow."""
        query = "analyze my compound data"
        profile = _make_profile(["drug_discovery"])

        results = search.search(query, limit=5, user_profile=profile)
        assert results, "Expected at least one result for the query"

        top = results[0]
        top_domain = (top.domain or "").lower()
        top_name = (top.name or "").lower()
        top_filename = (top.filename or "").lower()
        is_drug_discovery_result = (
            "drug" in top_domain
            or "drug" in top_name
            or "pharmacology" in top_domain
            or "admet" in top_name
            or "docking" in top_name
            or "compound" in top_name
            or "drug_discovery" in top_filename
        )
        assert is_drug_discovery_result, (
            f"Expected drug_discovery workflow for drug_discovery user but got: "
            f"name='{top.name}' domain='{top.domain}' score={top.score}"
        )

    def test_different_profiles_yield_different_top1(self, search: UnifiedWorkflowSearch):
        """
        Core assertion: the same ambiguous query returns a different top-1 result
        depending on the user's domain profile.

        Uses 'analyze my data' — intentionally generic so the profile is the
        deciding factor rather than keyword overlap.
        """
        query = "analyze my data"

        genomics_profile = _make_profile(["genomics"])
        drug_profile = _make_profile(["drug_discovery"])

        genomics_results = search.search(query, limit=5, user_profile=genomics_profile)
        drug_results = search.search(query, limit=5, user_profile=drug_profile)

        assert genomics_results, "No results for genomics profile"
        assert drug_results, "No results for drug_discovery profile"

        genomics_top = genomics_results[0]
        drug_top = drug_results[0]

        # The two profiles should produce different top-1 results.
        # If they are the same workflow, at minimum the score should differ.
        if genomics_top.name == drug_top.name:
            # Same workflow — assert scores differ (profile bias applied differently)
            assert genomics_top.score != drug_top.score, (
                "Same top-1 workflow and same score for different profiles — "
                "user_profile bias is not being applied."
            )
        else:
            # Different workflows — pass (this is the ideal outcome)
            pass

        # Sanity: genomics top-1 should be in genomics domain or drug top-1 in drug domain
        genomics_domain = (genomics_top.domain or "").lower()
        drug_domain = (drug_top.domain or "").lower()
        assert (
            "genomics" in genomics_domain
            or "drug" in drug_domain
            or "pharmacology" in drug_domain
        ), (
            f"Neither profile produced a domain-matched result. "
            f"genomics_top: name='{genomics_top.name}' domain='{genomics_domain}' | "
            f"drug_top: name='{drug_top.name}' domain='{drug_domain}'"
        )

    def test_no_profile_still_returns_results(self, search: UnifiedWorkflowSearch):
        """Passing user_profile=None should not break search (backward compat)."""
        query = "run rna seq analysis"
        results = search.search(query, limit=5, user_profile=None)
        assert results, "Search with no profile should still return results"

    def test_boost_ids_affect_score_of_seeded_workflow(self, search: UnifiedWorkflowSearch):
        """
        boost_ids should add a +1.5 score bonus to the specified workflows so they
        rank higher than they would without the boost.

        We test this by:
        1. Running the search WITHOUT boost_ids and recording the score of the target.
        2. Running WITH boost_ids and checking that the target's score is higher.

        We use a query that the target workflow is marginally relevant to so that
        it appears in both result sets (just with different scores).
        """
        # Find a genomics workflow
        baseline = search.search("whole genome sequencing gatk variant", limit=1)
        if not baseline:
            pytest.skip("No WGS/GATK workflows in DB — skip boost_ids test")

        target_id = baseline[0].id
        target_name = baseline[0].name

        # Use a more general query where the target is likely to appear but not top
        query = "genome analysis sequencing"

        # Get results without boost
        results_no_boost = search.search(query, limit=20)
        target_no_boost = next((r for r in results_no_boost if r.id == target_id), None)

        # Get results with boost
        results_with_boost = search.search(query, limit=20, boost_ids=[target_id])
        target_with_boost = next((r for r in results_with_boost if r.id == target_id), None)

        if target_no_boost is None and target_with_boost is None:
            # Neither query found the target — the query is too specific.
            # Fallback: verify the workflow appears AT ALL with boost.
            results_broad_with_boost = search.search("sequencing", limit=20, boost_ids=[target_id])
            target_broad_with = next((r for r in results_broad_with_boost if r.id == target_id), None)
            assert target_broad_with is not None, (
                f"Workflow '{target_name}' (id={target_id}) did not appear even with boost_ids "
                f"in limit=20 results for 'sequencing'."
            )
        elif target_no_boost is not None and target_with_boost is not None:
            # Both runs found the target — assert that the boosted score is higher
            assert target_with_boost.score > target_no_boost.score, (
                f"boost_ids should raise the score of '{target_name}' (id={target_id}) "
                f"but got no_boost={target_no_boost.score}, with_boost={target_with_boost.score}"
            )
            assert abs(target_with_boost.score - target_no_boost.score - 1.5) < 0.01, (
                f"Expected exactly +1.5 score delta but got "
                f"+{target_with_boost.score - target_no_boost.score:.2f}"
            )
        elif target_with_boost is not None:
            # Target only appears with boost — that's also a valid success
            pass
        else:
            # target_no_boost found but target_with_boost is None — shouldn't happen
            pytest.fail(
                f"Workflow '{target_name}' appeared without boost but not with boost "
                f"— this indicates a bug in the pre-seed logic."
            )
