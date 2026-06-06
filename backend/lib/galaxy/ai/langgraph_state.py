"""
BioMate LangGraph State Definition

Defines the shared state TypedDict that flows through the BioMate
LangGraph StateGraph pipeline.  Every field is written by at most one
node so that state updates are deterministic.
"""

from typing import TypedDict, Optional, List


class BioMateQueryState(TypedDict):
    """Shared state propagated across all nodes of the BioMate pipeline."""

    # ── Input ──────────────────────────────────────────────────────────────
    query: str
    session_id: str
    user_id: str

    # ── Intent classification (classify_intent node) ───────────────────────
    intent: Optional[str]           # from UnifiedIntentRouter / classify_intent
    confidence: Optional[float]
    clarification_needed: bool

    # ── Workflow search (search_workflows node) ────────────────────────────
    workflow_candidates: List[dict]  # raw WorkflowMatch objects serialised to dict

    # ── Workflow selection / generation (generate_workflow node) ───────────
    selected_workflow: Optional[dict]
    parameters: Optional[dict]

    # ── Execution (dispatch_execution node) ───────────────────────────────
    execution_run_id: Optional[str]

    # ── AutoFix loop (run_autofix node) ───────────────────────────────────
    autofix_attempts: int
    autofix_result: Optional[dict]  # populated by run_autofix; nullable
    error: Optional[str]

    # ── Final output (any terminal node) ──────────────────────────────────
    final_response: Optional[dict]
