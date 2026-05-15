"""
Workflow chat narrator — single source of truth for friendly chat-progress lines.

Maps workflow lifecycle events (state transitions, phase starts/completes, QC
gates, auto-loop remediations, deep-agent rounds) to short user-facing English
sentences AND structured engineer-channel log lines.

Usage:
    from galaxy.ai.workflow_ops.workflow_chat_narrator import emit

    emit("inv-abc-123", "workflow.running")
    emit("inv-abc-123", "workflow.phase_started", {"phase_name": "STAR alignment", "n": 2, "of": 5})
    emit("inv-abc-123", "workflow.failed", {"reason": "exit 127"})

Side effects:
- Calls the SSE inject hook so the frontend's WorkflowSSEManager delivers the
  event to the active chat session under event_type='chat_progress'.
- Emits a structured log line tagged [WORKFLOW] with the same payload so an
  engineer can correlate chat lines with technical events.

This module deliberately has no DB dependencies — the chat session writes
happen entirely on the frontend side via the existing SSE → chat append
pipeline. Backend stays stateless w.r.t. chat history.
"""

from __future__ import annotations

import logging
import time
from typing import Any, Dict, Optional


log = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# Event registry — canonical friendly templates
# ─────────────────────────────────────────────────────────────────────────────
#
# Each entry maps an event kind to a callable that takes the `technical` dict
# and returns the chat-friendly sentence. Using callables instead of f-strings
# lets us handle missing fields gracefully and keep templates testable.
#
# Conventions for friendly text:
#   - 1 sentence, ≤ 80 chars when possible
#   - Plain English. No "[DEEPAGENT][inv=xyz]" prefixes — that's the
#     engineer channel.
#   - Trailing "…" for in-progress, period for finished.

def _phase_started(t: Dict[str, Any]) -> str:
    name = t.get("phase_name") or t.get("name") or "step"
    n = t.get("n")
    of = t.get("of")
    if isinstance(n, int) and isinstance(of, int):
        return f"Step {n}/{of}: {name}…"
    return f"Step {name}…"


def _phase_completed(t: Dict[str, Any]) -> str:
    name = t.get("phase_name") or t.get("name") or "step"
    detail = t.get("detail")
    if detail:
        return f"{name} done — {detail}."
    return f"{name} done."


def _phase_failed(t: Dict[str, Any]) -> str:
    name = t.get("phase_name") or t.get("name") or "Step"
    reason = t.get("reason")
    if reason:
        head = str(reason).split(".")[0].strip()
        return f"{name} failed — {head}."
    return f"{name} failed. Looking into why…"


def _completed_summary(t: Dict[str, Any]) -> str:
    done = t.get("steps_succeeded")
    total = t.get("steps_total")
    if isinstance(done, int) and isinstance(total, int):
        return f"Workflow finished. {done}/{total} steps succeeded."
    return "Workflow finished."


def _qc_warn(t: Dict[str, Any]) -> str:
    metric = t.get("metric") or "metric"
    val = t.get("value")
    th = t.get("threshold")
    if val is not None and th is not None:
        return f"QC flagged {metric} = {val} (threshold {th})."
    return f"QC flagged {metric}."


def _qc_block(t: Dict[str, Any]) -> str:
    metric = t.get("metric")
    if metric:
        return f"QC blocked on {metric} — adjusting parameters."
    return "QC blocked — adjusting parameters."


def _autoloop_started(t: Dict[str, Any]) -> str:
    changes = t.get("changes") or {}
    if isinstance(changes, dict) and changes:
        pairs = ", ".join(f"{k}={v}" for k, v in list(changes.items())[:2])
        return f"Trying again with {pairs}."
    return "Trying again with adjusted parameters."


def _failed_msg(t: Dict[str, Any]) -> str:
    reason = t.get("reason") or t.get("error")
    if reason:
        head = str(reason).split(".")[0].strip()
        return f"Workflow stopped — {head}. Looking into why…"
    return "Workflow stopped. Looking into why…"


def _cancelled_msg(t: Dict[str, Any]) -> str:
    reason = t.get("reason")
    if reason:
        return f"Workflow cancelled — {reason}."
    return "Workflow cancelled by you."


def _paused_msg(t: Dict[str, Any]) -> str:
    return "Workflow paused. Tap Resume when you're ready to continue."


def _auto_proceeded_msg(t: Dict[str, Any]) -> str:
    decision = t.get("decision") or "continued"
    return f"No response — {decision} automatically."


# kind → (callable or static string)
_TEMPLATES: Dict[str, Any] = {
    "workflow.submitted": "Got it — starting your workflow now.",
    "workflow.uploading_inputs": "Uploading inputs to S3…",
    "workflow.queued": "Your workflow is in the AWS Batch queue.",
    "workflow.running": "Workflow is running.",
    "workflow.phase_started": _phase_started,
    "workflow.phase_completed": _phase_completed,
    "workflow.phase_failed": _phase_failed,
    "workflow.qc_gate_warning": _qc_warn,
    "workflow.qc_gate_blocked": _qc_block,
    "workflow.autoloop_started": _autoloop_started,
    "workflow.completed": _completed_summary,
    "workflow.failed": _failed_msg,
    # User-control events
    "workflow.cancelled": _cancelled_msg,
    "workflow.paused": _paused_msg,
    "workflow.resumed": "Resuming your workflow.",
    # Auto-proceeded after user didn't react in time
    "workflow.auto_proceeded": _auto_proceeded_msg,
    # deepagent.* events are emitted by DeepAnalysisAgent via its own
    # progress_callback; they flow through emit() too for consistency.
    "deepagent.start": "Looking into why your workflow failed…",
    "deepagent.investigating": lambda t: t.get("friendly_message") or "Investigating…",
    "deepagent.tool_call": lambda t: t.get("friendly_message") or "Checking something in the workflow files…",
    "deepagent.suggestion": lambda t: t.get("friendly_message") or "Got a suggestion — see the workflow panel.",
}


def render_friendly(kind: str, technical: Optional[Dict[str, Any]] = None) -> str:
    """Return the chat-friendly sentence for an event kind. Never raises."""
    technical = technical or {}
    tmpl = _TEMPLATES.get(kind)
    if tmpl is None:
        # Unknown kind — render something safe; logs will tell the engineer.
        return f"Workflow update: {kind}."
    if callable(tmpl):
        try:
            return tmpl(technical)
        except Exception as exc:
            log.debug("workflow_chat_narrator: template %r failed: %s", kind, exc)
            return f"Workflow update: {kind}."
    return tmpl


def emit(
    invocation_id: str,
    kind: str,
    technical: Optional[Dict[str, Any]] = None,
    *,
    sse_callback: Optional[Any] = None,
) -> Dict[str, Any]:
    """
    Emit a workflow progress event.

    - Renders the friendly chat line for `kind`.
    - Logs a structured [WORKFLOW] line with the technical payload.
    - If `sse_callback` is provided, calls it with ('chat_progress', payload)
      so the frontend WorkflowSSEManager delivers the event. Optional so
      tests can introspect the payload without wiring SSE.

    Returns the payload dict (useful for tests).
    """
    technical = technical or {}
    friendly = render_friendly(kind, technical)
    payload = {
        "kind": kind,
        "invocation_id": invocation_id,
        "friendly_message": friendly,
        "ts": time.time(),
        "technical": technical,
    }

    # Engineer channel: structured log line
    log.info("[WORKFLOW][inv=%s][%s] %s | technical=%s", invocation_id, kind, friendly, technical)

    # User channel: SSE inject (when caller provides it)
    if sse_callback is not None:
        try:
            sse_callback("chat_progress", payload)
        except Exception as exc:
            log.debug("workflow_chat_narrator: sse_callback raised for %s: %s", kind, exc)

    return payload
