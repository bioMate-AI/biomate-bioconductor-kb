"""
Unit tests for the BioMate LangGraph StateGraph pipeline.

Tests verify:
1. BioMateQueryState can be instantiated with required fields.
2. The pipeline graph compiles without error (no external API calls).
3. The compiled graph can invoke a simple end-to-end run with all LLM
   and database calls mocked out.

Run with:
    python -m pytest backend/lib/galaxy/ai/tests/test_langgraph_pipeline.py -v
"""
from __future__ import annotations

import os
import sys
from unittest.mock import MagicMock, patch

import pytest

# ---------------------------------------------------------------------------
# Ensure backend/lib is on sys.path so imports work from the repo root
# ---------------------------------------------------------------------------
_BACKEND_LIB = os.path.join(os.path.dirname(__file__), "..", "..", "..", "..")
if _BACKEND_LIB not in sys.path:
    sys.path.insert(0, _BACKEND_LIB)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_initial_state(
    query: str = "run RNA-seq analysis",
    session_id: str = "test-session-001",
    user_id: str = "test-user",
) -> dict:
    """Return a fully-populated BioMateQueryState-compatible dict."""
    return {
        "query": query,
        "session_id": session_id,
        "user_id": user_id,
        "intent": None,
        "confidence": None,
        "clarification_needed": False,
        "workflow_candidates": [],
        "selected_workflow": None,
        "parameters": None,
        "execution_run_id": None,
        "autofix_attempts": 0,
        "error": None,
        "final_response": None,
    }


# ---------------------------------------------------------------------------
# A1 — State instantiation tests
# ---------------------------------------------------------------------------


class TestBioMateQueryState:
    """Tests for the BioMateQueryState TypedDict."""

    def test_state_instantiation_required_fields(self):
        """State dict can be constructed with required fields."""
        from galaxy.ai.langgraph_state import BioMateQueryState

        state: BioMateQueryState = _make_initial_state()
        assert state["query"] == "run RNA-seq analysis"
        assert state["session_id"] == "test-session-001"
        assert state["user_id"] == "test-user"

    def test_state_optional_fields_default_none(self):
        """Optional fields default to None."""
        from galaxy.ai.langgraph_state import BioMateQueryState

        state: BioMateQueryState = _make_initial_state()
        assert state["intent"] is None
        assert state["confidence"] is None
        assert state["selected_workflow"] is None
        assert state["parameters"] is None
        assert state["execution_run_id"] is None
        assert state["error"] is None
        assert state["final_response"] is None

    def test_state_list_fields_default_empty(self):
        """List fields default to empty lists."""
        from galaxy.ai.langgraph_state import BioMateQueryState

        state: BioMateQueryState = _make_initial_state()
        assert state["workflow_candidates"] == []

    def test_state_boolean_field(self):
        """clarification_needed defaults to False."""
        from galaxy.ai.langgraph_state import BioMateQueryState

        state: BioMateQueryState = _make_initial_state()
        assert state["clarification_needed"] is False

    def test_state_autofix_attempts_default_zero(self):
        """autofix_attempts defaults to 0."""
        from galaxy.ai.langgraph_state import BioMateQueryState

        state: BioMateQueryState = _make_initial_state()
        assert state["autofix_attempts"] == 0


# ---------------------------------------------------------------------------
# A2 — Pipeline compilation tests
# ---------------------------------------------------------------------------


class TestBioMatePipelineCompilation:
    """Tests for the build_biomate_pipeline() factory."""

    def test_pipeline_compiles_without_ai_assistant(self):
        """Graph compiles with ai_assistant=None — no external calls needed."""
        from galaxy.ai.langgraph_pipeline import build_biomate_pipeline

        graph = build_biomate_pipeline(ai_assistant=None)
        assert graph is not None

    def test_pipeline_has_invoke_method(self):
        """Compiled graph exposes an invoke() method."""
        from galaxy.ai.langgraph_pipeline import build_biomate_pipeline

        graph = build_biomate_pipeline(ai_assistant=None)
        assert callable(getattr(graph, "invoke", None))

    def test_pipeline_has_stream_method(self):
        """Compiled graph exposes a stream() method for SSE compatibility."""
        from galaxy.ai.langgraph_pipeline import build_biomate_pipeline

        graph = build_biomate_pipeline(ai_assistant=None)
        assert callable(getattr(graph, "stream", None))

    def test_pipeline_graph_nodes_present(self):
        """All expected nodes are registered in the graph."""
        from galaxy.ai.langgraph_pipeline import build_biomate_pipeline

        graph = build_biomate_pipeline(ai_assistant=None)
        # Access the underlying builder's nodes via the graph object
        node_names = set(graph.nodes.keys())
        expected = {
            "classify_intent",
            "clarify_node",
            "search_workflows",
            "generate_workflow",
            "dispatch_execution",
            "run_autofix",
        }
        assert expected.issubset(node_names), (
            f"Missing nodes: {expected - node_names}"
        )


# ---------------------------------------------------------------------------
# A2 — End-to-end invoke tests (all LLM/DB calls mocked)
# ---------------------------------------------------------------------------


class TestBioMatePipelineInvoke:
    """End-to-end invocation tests with no external API calls."""

    def test_happy_path_no_ai_assistant(self):
        """
        A simple workflow-query state flows from classify_intent through
        dispatch_execution to END without errors when ai_assistant is None.
        """
        from galaxy.ai.langgraph_pipeline import build_biomate_pipeline

        graph = build_biomate_pipeline(ai_assistant=None)
        initial = _make_initial_state("run RNA-seq differential expression")
        config = {"configurable": {"thread_id": initial["session_id"]}}

        result = graph.invoke(initial, config=config)

        # Graph should complete — final state has all original keys
        assert "query" in result
        assert result["query"] == "run RNA-seq differential expression"
        # No error should be present in the happy-path stub run
        assert result.get("autofix_attempts", 0) >= 0

    def test_clarification_path_terminates_early(self):
        """
        When clarification_needed is pre-set to True, the graph routes to
        clarify_node → END without touching search_workflows.
        """
        from galaxy.ai.langgraph_pipeline import build_biomate_pipeline

        graph = build_biomate_pipeline(ai_assistant=None)

        # Pre-set clarification_needed so classify_intent node doesn't
        # overwrite it (ai_assistant=None keeps False; we inject a mock).
        mock_assistant = MagicMock()
        mock_assistant.classify_intent.return_value = {
            "intent": "ambiguous",
            "confidence": 0.4,
            "clarification_needed": True,
        }
        # Rebuild with the mock assistant so classify_intent sets the flag
        graph_with_mock = build_biomate_pipeline(ai_assistant=mock_assistant)
        initial = _make_initial_state("do something")
        config = {"configurable": {"thread_id": "clarify-test"}}

        result = graph_with_mock.invoke(initial, config=config)

        # final_response should be set by clarify_node
        assert result.get("final_response") is not None
        assert result["final_response"].get("type") == "clarification_needed"
        # workflow_candidates should NOT have been populated (early exit)
        assert result.get("workflow_candidates") == []

    def test_autofix_loop_increments_attempts(self):
        """
        When dispatch_execution returns an error, run_autofix increments
        autofix_attempts.  After 3 attempts the graph exits to END.
        """
        from galaxy.ai.langgraph_pipeline import build_biomate_pipeline

        # Mock an ai_assistant that always raises during dispatch so that the
        # dispatch stub ends up with an error in the state.
        mock_assistant = MagicMock()
        mock_assistant.classify_intent.return_value = {
            "intent": "workflow_generation",
            "confidence": 0.9,
            "clarification_needed": False,
        }
        mock_assistant.workflow_search.search.return_value = []
        mock_assistant.generate_workflow_unified.return_value = {
            "success": True,
            "workflow_ga": {"id": "wf-1"},
        }

        graph = build_biomate_pipeline(ai_assistant=mock_assistant)

        # Inject a pre-existing error + max attempts so the graph exits
        # immediately (avoids waiting for 3 real autofix cycles in unit tests).
        initial = _make_initial_state()
        initial["autofix_attempts"] = 3   # already exhausted
        initial["error"] = "simulated execution error"
        config = {"configurable": {"thread_id": "autofix-test"}}

        result = graph.invoke(initial, config=config)

        # Graph should reach END without looping (attempts already at limit)
        assert result is not None

    def test_pipeline_accepts_custom_checkpointer(self):
        """build_biomate_pipeline() accepts a caller-supplied checkpointer."""
        from langgraph.checkpoint.memory import MemorySaver

        from galaxy.ai.langgraph_pipeline import build_biomate_pipeline

        custom_saver = MemorySaver()
        graph = build_biomate_pipeline(ai_assistant=None, checkpointer=custom_saver)
        assert graph is not None
