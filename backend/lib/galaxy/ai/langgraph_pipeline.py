"""
BioMate LangGraph Pipeline

Wraps the existing AI pipeline in a LangGraph StateGraph for observability
and checkpointing.  **No logic changes** — every node delegates directly to
the already-tested components in the ai_assistant / unified_workflow_search
modules.

Graph topology
--------------
    classify_intent
        │
        ▼
    check_clarification ─── clarification_needed=True ──► clarify_node ──► END
        │
        │ clarification_needed=False
        ▼
    search_workflows
        │
        ▼
    generate_workflow
        │
        ▼
    dispatch_execution ─── error AND attempts < 3 ──► run_autofix ──┐
        │                                                             │
        │ (no error OR attempts >= 3)                                 │
        ▼                                                             │
       END ◄────────────────────────────────────────────────────────-┘
            (run_autofix loops back to dispatch_execution)

Usage
-----
    from galaxy.ai.langgraph_pipeline import build_biomate_pipeline

    # ai_assistant is an optional AIAssistant instance for dependency injection.
    graph = build_biomate_pipeline(ai_assistant=None)

    config = {"configurable": {"thread_id": "session-abc"}}
    result = graph.invoke(
        {
            "query": "run RNA-seq analysis",
            "session_id": "session-abc",
            "user_id": "user-1",
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
        },
        config=config,
    )
"""

from __future__ import annotations

import logging
from dataclasses import asdict
from typing import Any, Dict, Optional

from langgraph.checkpoint.memory import MemorySaver
from langgraph.graph import END, StateGraph

from .langgraph_state import BioMateQueryState

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Routing constants
# ---------------------------------------------------------------------------
_ROUTE_CLARIFY = "clarify_node"
_ROUTE_SEARCH = "search_workflows"
_ROUTE_AUTOFIX = "run_autofix"
_ROUTE_END = END


# ---------------------------------------------------------------------------
# Node implementations
# ---------------------------------------------------------------------------


def _make_classify_intent_node(ai_assistant: Optional[Any]):
    """Factory: returns the classify_intent node bound to an AIAssistant."""

    def classify_intent(state: BioMateQueryState) -> Dict[str, Any]:
        """Call the unified intent classifier and update state."""
        query = state["query"]
        log.debug("[classify_intent] query=%r", query)

        if ai_assistant is not None:
            try:
                classification = ai_assistant.classify_intent(query)
                intent = classification.get("intent", "research_question")
                confidence = float(classification.get("confidence", 0.6))
                # If the router explicitly signals that clarification is needed
                # (e.g. ambiguous query flagged by multi-task detection), set
                # the flag.  In the current implementation the intent router
                # does not surface this directly, so we default to False and
                # let downstream logic override when required.
                clarification_needed = bool(
                    classification.get("clarification_needed", False)
                )
            except Exception as exc:
                log.warning("[classify_intent] error: %s", exc)
                intent = "research_question"
                confidence = 0.5
                clarification_needed = False
        else:
            # Fallback when no AIAssistant is injected (e.g. unit tests)
            intent = "research_question"
            confidence = 0.5
            clarification_needed = False

        return {
            "intent": intent,
            "confidence": confidence,
            "clarification_needed": clarification_needed,
        }

    return classify_intent


def _make_clarify_node(ai_assistant: Optional[Any]):
    """Factory: returns the clarify_node that handles ambiguous queries."""

    def clarify_node(state: BioMateQueryState) -> Dict[str, Any]:
        """Surface a clarification request as the final response."""
        log.debug("[clarify_node] query=%r", state["query"])
        response = {
            "type": "clarification_needed",
            "message": (
                "Your request is ambiguous or contains multiple tasks. "
                "Could you please clarify what you would like to analyse?"
            ),
            "query": state["query"],
            "intent": state.get("intent"),
        }
        return {"final_response": response}

    return clarify_node


def _make_search_workflows_node(ai_assistant: Optional[Any]):
    """Factory: returns the search_workflows node."""

    def search_workflows(state: BioMateQueryState) -> Dict[str, Any]:
        """Call UnifiedWorkflowSearch.search() and populate workflow_candidates."""
        query = state["query"]
        log.debug("[search_workflows] query=%r", query)

        candidates: list = []
        if ai_assistant is not None:
            try:
                workflow_search = ai_assistant.workflow_search
                matches = workflow_search.search(query, limit=5)
                candidates = [asdict(m) for m in matches]
            except Exception as exc:
                log.warning("[search_workflows] search error: %s", exc)

        return {"workflow_candidates": candidates}

    return search_workflows


def _make_generate_workflow_node(ai_assistant: Optional[Any]):
    """Factory: returns the generate_workflow node."""

    def generate_workflow(state: BioMateQueryState) -> Dict[str, Any]:
        """Call generate_workflow_unified() and store the result in state."""
        query = state["query"]
        log.debug("[generate_workflow] query=%r", query)

        if ai_assistant is not None:
            try:
                result = ai_assistant.generate_workflow_unified(query)
                return {
                    "selected_workflow": result.get("workflow_ga"),
                    "parameters": result.get("parameters"),
                    "final_response": result,
                }
            except Exception as exc:
                log.warning("[generate_workflow] error: %s", exc)
                return {
                    "error": str(exc),
                    "selected_workflow": None,
                    "parameters": None,
                }

        # No ai_assistant — pass through for testing
        return {
            "selected_workflow": None,
            "parameters": None,
        }

    return generate_workflow


def _make_dispatch_execution_node(ai_assistant: Optional[Any]):
    """Factory: returns the dispatch_execution node."""

    def dispatch_execution(state: BioMateQueryState) -> Dict[str, Any]:
        """Dispatch the selected workflow for execution."""
        log.debug(
            "[dispatch_execution] workflow=%r", state.get("selected_workflow")
        )

        # In the current architecture, execution is triggered via the Galaxy
        # Nextflow/Galaxy executor APIs.  The node sets execution_run_id when
        # successful or populates error when it fails.  Actual wiring to the
        # executor happens in a future workstream; here we emit a structured
        # placeholder so the graph compiles and runs end-to-end.
        if ai_assistant is not None and state.get("selected_workflow"):
            try:
                # Real execution dispatch will be inserted here (Workstream B).
                # For now, record that a run was initiated.
                import uuid
                run_id = str(uuid.uuid4())
                log.info("[dispatch_execution] run_id=%s (stub)", run_id)
                return {
                    "execution_run_id": run_id,
                    "error": None,
                }
            except Exception as exc:
                log.warning("[dispatch_execution] error: %s", exc)
                return {"error": str(exc)}

        return {"execution_run_id": None}

    return dispatch_execution


def _make_run_autofix_node(ai_assistant: Optional[Any]):
    """Factory: returns the run_autofix node that calls AutoFix3."""

    def run_autofix(state: BioMateQueryState) -> Dict[str, Any]:
        """Attempt to fix execution errors using AutoFix3's IterativeDebugger.

        Uses the standalone Nextflow path (no Galaxy trans context needed).
        On success: clears error so dispatch_execution retries with the fix.
        On failure: still clears error + bumps counter so the retry/cap loop
        in _route_after_dispatch terminates after `autofix_attempts >= 3`.
        """
        attempts = state.get("autofix_attempts", 0) + 1
        run_id = state.get("execution_run_id")
        log.info(
            "[run_autofix] attempt %d for run_id=%s error=%r",
            attempts,
            run_id,
            state.get("error"),
        )

        next_state: Dict[str, Any] = {
            "autofix_attempts": attempts,
            "error": None,  # clear; dispatch_execution will re-set if retry fails
        }

        if not run_id:
            log.info("[run_autofix] no run_id — skipping autofix invocation")
            return next_state

        try:
            from galaxy.ai.workflow_ops.autofix.nextflow_runner import (
                run_nextflow_autofix,
            )
            result = run_nextflow_autofix(
                invocation_id=str(run_id),
                max_attempts=3,
                timeout_seconds=180,
            )
            log.info(
                "[run_autofix] result: success=%s reason=%s attempts=%s session=%s",
                result.get("success"),
                result.get("termination_reason"),
                result.get("total_attempts"),
                result.get("session_id"),
            )
            next_state["autofix_result"] = result
        except Exception as exc:
            # The pipeline must keep moving even if autofix crashes; record
            # the failure but don't propagate.
            log.exception("[run_autofix] crashed: %s", exc)
            next_state["autofix_result"] = {
                "success": False,
                "termination_reason": "node_exception",
                "error": str(exc),
            }

        return next_state

    return run_autofix


# ---------------------------------------------------------------------------
# Conditional routing functions
# ---------------------------------------------------------------------------


def _route_after_clarification_check(state: BioMateQueryState) -> str:
    """Route based on whether clarification is needed."""
    if state.get("clarification_needed"):
        return _ROUTE_CLARIFY
    return _ROUTE_SEARCH


def _route_after_dispatch(state: BioMateQueryState) -> str:
    """Route to autofix or END after execution dispatch."""
    has_error = bool(state.get("error"))
    under_limit = state.get("autofix_attempts", 0) < 3
    if has_error and under_limit:
        return _ROUTE_AUTOFIX
    return _ROUTE_END


# ---------------------------------------------------------------------------
# Public factory
# ---------------------------------------------------------------------------


def build_biomate_pipeline(
    ai_assistant: Optional[Any] = None,
    checkpointer: Optional[Any] = None,
) -> Any:
    """
    Build and compile the BioMate LangGraph StateGraph.

    Parameters
    ----------
    ai_assistant:
        An optional ``AIAssistant`` instance.  When provided, nodes will call
        real business logic.  When ``None`` (e.g. unit tests), nodes are
        no-ops that exercise only graph structure.
    checkpointer:
        Optional LangGraph checkpointer.  Defaults to an in-process
        ``MemorySaver`` keyed by the ``session_id`` (passed as
        ``configurable["thread_id"]`` in the invoke config).

    Returns
    -------
    CompiledGraph
        A compiled LangGraph ``StateGraph`` ready to ``.invoke()`` or
        ``.stream()``.
    """
    if checkpointer is None:
        checkpointer = MemorySaver()

    builder = StateGraph(BioMateQueryState)

    # ── Register nodes ──────────────────────────────────────────────────────
    builder.add_node("classify_intent", _make_classify_intent_node(ai_assistant))
    builder.add_node("clarify_node", _make_clarify_node(ai_assistant))
    builder.add_node("search_workflows", _make_search_workflows_node(ai_assistant))
    builder.add_node("generate_workflow", _make_generate_workflow_node(ai_assistant))
    builder.add_node("dispatch_execution", _make_dispatch_execution_node(ai_assistant))
    builder.add_node("run_autofix", _make_run_autofix_node(ai_assistant))

    # ── Entry point ─────────────────────────────────────────────────────────
    builder.set_entry_point("classify_intent")

    # ── Edges ───────────────────────────────────────────────────────────────
    # classify_intent → check_clarification (implemented as conditional from classify_intent)
    builder.add_conditional_edges(
        "classify_intent",
        _route_after_clarification_check,
        {
            _ROUTE_CLARIFY: "clarify_node",
            _ROUTE_SEARCH: "search_workflows",
        },
    )

    # clarify_node → END  (clarification terminates the pipeline)
    builder.add_edge("clarify_node", END)

    # search_workflows → generate_workflow → dispatch_execution
    builder.add_edge("search_workflows", "generate_workflow")
    builder.add_edge("generate_workflow", "dispatch_execution")

    # dispatch_execution → (error & attempts < 3 → run_autofix | else → END)
    builder.add_conditional_edges(
        "dispatch_execution",
        _route_after_dispatch,
        {
            _ROUTE_AUTOFIX: "run_autofix",
            _ROUTE_END: END,
        },
    )

    # run_autofix loops back to dispatch_execution
    builder.add_edge("run_autofix", "dispatch_execution")

    # ── Compile ─────────────────────────────────────────────────────────────
    compiled = builder.compile(checkpointer=checkpointer)
    log.info("BioMate LangGraph pipeline compiled successfully")
    return compiled
