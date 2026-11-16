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
import re
import time
import uuid
from typing import Any, Dict, Optional

# A bare process exit code ("exit 1", "exit 127", "rc=1", "127") is meaningless to
# a user — it belongs in the engineer log, not the friendly line.
_BARE_EXIT_RE = re.compile(
    r"^(exit(\s?code)?|return\s?code|returncode|rc|status|code|signal)?\s*[:=]?\s*-?\d+$",
    re.IGNORECASE,
)


def _clean_reason(reason: Any) -> Optional[str]:
    if not reason:
        return None
    head = str(reason).split(".")[0].strip()
    if not head or _BARE_EXIT_RE.match(head):
        return None
    return head


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
    reason = _clean_reason(t.get("reason"))
    if reason:
        return f"{name} failed — {reason}."
    return f"{name} failed."


def _completed_summary(t: Dict[str, Any]) -> str:
    done = t.get("steps_succeeded")
    total = t.get("steps_total")
    if isinstance(done, int) and isinstance(total, int):
        return f"Workflow finished. {done}/{total} steps succeeded."
    return "Workflow finished."


_METRIC_LABELS: Dict[str, str] = {
    "dili_risk":       "DILI risk",
    "herg_ic50_uM":    "hERG IC50",
    "herg":            "hERG",
    "ames_mutagenicity": "Ames mutagenicity",
    "caco2_logpapp":   "Caco-2 permeability",
    "bbb_penetration": "BBB penetration",
    "ppb":             "plasma protein binding",
    "oral_bioavailability": "oral bioavailability",
    "cyp2d6_inhibitor": "CYP2D6 inhibition",
    "cyp3a4_substrate": "CYP3A4 substrate",
    "clintox":         "clinical toxicity",
}


def _humanize_metric(metric: str) -> str:
    return _METRIC_LABELS.get(metric, metric.replace("_", " "))


def _qc_warn(t: Dict[str, Any]) -> str:
    metric = _humanize_metric(t.get("metric") or "metric")
    val = t.get("value")
    th = t.get("threshold")
    if val is not None and th is not None:
        return f"QC flagged {metric} = {val} (threshold {th})."
    return f"QC flagged {metric}."


def _qc_block(t: Dict[str, Any]) -> str:
    raw = t.get("metric")
    if raw:
        return f"QC blocked on {_humanize_metric(raw)} — adjusting parameters."
    return "QC blocked — adjusting parameters."


def _autoloop_started(t: Dict[str, Any]) -> str:
    changes = t.get("changes") or {}
    if isinstance(changes, dict) and changes:
        pairs = ", ".join(f"{k}={v}" for k, v in list(changes.items())[:2])
        return f"Trying again with {pairs}."
    return "Trying again with adjusted parameters."


def _failed_msg(t: Dict[str, Any]) -> str:
    # Not necessarily terminal — an attempt failure triggers auto-fix (deepagent).
    # Neutral wording so an auto-recovered (COMPLETED) run doesn't read "stopped";
    # the run status badge carries the terminal truth.
    reason = _clean_reason(t.get("reason") or t.get("error"))
    if reason:
        return f"Workflow hit an error — {reason}."
    return "Workflow hit an error."


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
    # Generic info line: renders the caller-supplied message verbatim.
    "workflow.info": lambda t: t.get("message") or "Workflow update.",
    # Auto-proceeded after user didn't react in time
    "workflow.auto_proceeded": _auto_proceeded_msg,
    # deepagent.* events are emitted by DeepAnalysisAgent via its own
    # progress_callback; they flow through emit() too for consistency.
    "deepagent.start": "Auto-diagnosing and fixing the error…",
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
    event_id: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Emit a workflow progress event.

    - Renders the friendly chat line for `kind`.
    - Assigns a durable event identity; a replay may pass the original event_id.
    - Logs a structured [WORKFLOW] line with the technical payload.
    - If `sse_callback` is provided, calls it with ('chat_progress', payload)
      so the frontend WorkflowSSEManager delivers the event. Optional so
      tests can introspect the payload without wiring SSE.

    Returns the payload dict (useful for tests).
    """
    technical = technical or {}
    friendly = render_friendly(kind, technical)
    payload = {
        "event_id": event_id or str(uuid.uuid4()),
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
