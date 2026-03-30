"""
AutoFix 3.0 API Endpoints

Exposes the AutoFix 3.0 iterative debugging system as REST endpoints.
Auto-discovered by FastAPI via include_all_package_routers().

Routes:
  POST /api/workflows/{workflow_id}/invocations/{invocation_id}/autofix3/run
  GET  /api/workflows/{workflow_id}/invocations/{invocation_id}/autofix3/sessions
  GET  /api/autofix3/status
"""

import json
import logging
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import HTTPException, Query
from pydantic import BaseModel, Field

from galaxy.webapps.galaxy.api import Router

log = logging.getLogger(__name__)

router = Router(tags=["autofix"])

# ── In-process session registry ──────────────────────────────────────────────
# Maps invocation_id (str) → list of session-record dicts, newest first.
_sessions: Dict[str, List[Dict[str, Any]]] = {}
_sessions_lock = threading.Lock()

_SESSIONS_DISK_DIR = Path("/tmp/biomate_autofix3_sessions")


def _persist_session(invocation_id: str, session: Dict[str, Any]) -> None:
    """Write session record to disk for crash-safe persistence (best-effort)."""
    try:
        _SESSIONS_DISK_DIR.mkdir(parents=True, exist_ok=True)
        store_file = _SESSIONS_DISK_DIR / f"inv_{invocation_id}.json"
        existing: List[Dict] = []
        if store_file.exists():
            with store_file.open() as f:
                existing = json.load(f)
        existing.insert(0, session)
        with store_file.open("w") as f:
            json.dump(existing[:50], f)  # cap at 50 records per invocation
    except Exception as exc:
        log.warning("autofix3: failed to persist session to disk: %s", exc)


def _load_sessions_from_disk(invocation_id: str) -> List[Dict[str, Any]]:
    """Load sessions from disk (called on in-memory cache miss)."""
    try:
        store_file = _SESSIONS_DISK_DIR / f"inv_{invocation_id}.json"
        if store_file.exists():
            with store_file.open() as f:
                return json.load(f)
    except Exception as exc:
        log.warning("autofix3: failed to load sessions from disk: %s", exc)
    return []


# ── Request / Response models ─────────────────────────────────────────────────


class AutoFix3RunRequest(BaseModel):
    auto_apply: bool = False
    max_attempts: int = Field(default=5, ge=1, le=10)
    timeout_seconds: int = Field(default=300, ge=30, le=600)


# ── Helper: resolve workflow directory for a Nextflow run ─────────────────────


def _resolve_workflow_dir(invocation_id: str) -> Optional[Path]:
    """
    Resolve the on-disk workflow directory for a Nextflow run.

    Priority:
    1. In-process _runs registry in nextflow_executor (log_path parent)
    2. Common local work-dir conventions
    """
    try:
        from galaxy.webapps.galaxy.api.nextflow_executor import _runs, _runs_lock
        with _runs_lock:
            run_info = _runs.get(invocation_id)
        if run_info:
            log_path = run_info.get("log_path")
            if log_path:
                return Path(log_path).parent
            work_dir = run_info.get("work_dir")
            if work_dir and not str(work_dir).startswith("s3://"):
                return Path(work_dir).parent
    except Exception as exc:
        log.debug("autofix3: could not look up _runs: %s", exc)

    # Fallback: try common local paths
    for base in [
        Path("/tmp/biomate_nextflow"),
        Path("/home/galaxy/nextflow_runs"),
    ]:
        candidate = base / invocation_id
        if candidate.exists():
            return candidate

    return None


def _read_error_logs(workflow_dir: Path, max_lines: int = 200) -> str:
    """Extract error / failure lines from nextflow.out + workflow-trace.txt."""
    fragments: List[str] = []

    nextflow_out = workflow_dir / "nextflow.out"
    if nextflow_out.exists():
        try:
            lines = nextflow_out.read_text(errors="replace").splitlines()
            fragments.extend(lines[-max_lines:])
        except Exception:
            pass

    trace_file = workflow_dir / "workflow-trace.txt"
    if trace_file.exists():
        try:
            for line in trace_file.read_text(errors="replace").splitlines():
                if "FAILED" in line or "ERROR" in line:
                    fragments.append(line)
        except Exception:
            pass

    return "\n".join(fragments)


def _get_first_failed_task(workflow_dir: Path) -> str:
    trace_file = workflow_dir / "workflow-trace.txt"
    if trace_file.exists():
        try:
            for line in trace_file.read_text(errors="replace").splitlines():
                if "FAILED" in line:
                    parts = line.strip().split("\t")
                    if len(parts) > 1:
                        return parts[1]
        except Exception:
            pass
    return "UNKNOWN_TASK"


# ── Main endpoints ────────────────────────────────────────────────────────────


@router.post(
    "/api/workflows/{workflow_id}/invocations/{invocation_id}/autofix3/run",
    summary="Run AutoFix 3.0 iterative debugger for a workflow invocation",
)
async def run_autofix3(
    workflow_id: str,
    invocation_id: str,
    request: AutoFix3RunRequest,
) -> Dict[str, Any]:
    """
    Runs AutoFix 3.0's IterativeDebugger for the given invocation.

    Supported invocation ID formats:
    - Nextflow run ID (e.g. ``nf-abc123``): looks up log paths from the
      in-process run registry and runs IterativeDebugger standalone.
    - Numeric Galaxy invocation ID: delegates to AutoFix3Orchestrator (requires
      Galaxy DB and trans context — only available when called from within the
      Galaxy webapp context with a valid authenticated session).
    """
    session_id = f"{invocation_id}_{int(time.time())}_{uuid.uuid4().hex[:6]}"
    started_at = datetime.now(timezone.utc).isoformat()
    result: Dict[str, Any] = {}
    state = "failed"

    # ── Path A: Nextflow run ID ────────────────────────────────────────────
    try:
        workflow_dir = _resolve_workflow_dir(invocation_id)

        if workflow_dir is not None and workflow_dir.exists():
            log.info(
                "autofix3: Nextflow path for invocation=%s, dir=%s",
                invocation_id,
                workflow_dir,
            )

            error_logs = _read_error_logs(workflow_dir)
            if not error_logs.strip():
                result = {
                    "success": True,
                    "session_id": session_id,
                    "message": "No error logs found — workflow may have succeeded.",
                    "total_attempts": 0,
                    "termination_reason": "no_errors",
                }
                state = "completed"
            else:
                failed_task = _get_first_failed_task(workflow_dir)

                # Build standalone LLM + toolkit (no Galaxy trans required)
                from galaxy.ai.config import AIConfig
                from galaxy.ai.llm_client import LLMClient
                from galaxy.ai.workflow_ops.autofix.toolkit_v2 import EnhancedToolKit
                from galaxy.ai.workflow_ops.autofix.agent import DeepAnalysisAgent
                from galaxy.ai.workflow_ops.autofix.iterative_debugger import IterativeDebugger

                ai_config = AIConfig()
                llm_client = LLMClient(ai_config)

                toolkit = EnhancedToolKit(
                    app_config=ai_config,
                    context={
                        "workflow_id": workflow_id,
                        "invocation_id": invocation_id,
                    },
                    workflow_dir=workflow_dir,
                )

                # Find galaxy_ai_tools.db for parameter recommendations
                db_path: Optional[str] = None
                db_candidates = [
                    Path(__file__).parents[5] / "database" / "galaxy_ai_tools.db",
                    Path("/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"),
                ]
                for db_candidate in db_candidates:
                    if db_candidate.exists():
                        db_path = str(db_candidate)
                        break

                agent = DeepAnalysisAgent(
                    llm_client=llm_client,
                    toolkit=toolkit,
                    max_rounds=5,
                    db_path=db_path,
                )

                debugger = IterativeDebugger(
                    agent=agent,
                    toolkit=toolkit,
                    workflow_dir=workflow_dir,
                    max_attempts=request.max_attempts,
                    timeout_seconds=request.timeout_seconds,
                )

                debug_result = debugger.run_until_fixed(
                    task_name=failed_task,
                    error_logs=error_logs,
                    exit_code=1,
                    context={
                        "workflow_id": workflow_id,
                        "invocation_id": invocation_id,
                    },
                )

                state = "completed" if debug_result.get("success") else "failed"
                result = {
                    **debug_result,
                    "session_id": debug_result.get("session_id", session_id),
                }

        else:
            # ── Path B: No local directory found ─────────────────────────
            # Try AutoFix3Orchestrator (Galaxy DB path) if invocation_id looks numeric.
            if invocation_id.isdigit():
                log.info(
                    "autofix3: Galaxy DB path for invocation_id=%s", invocation_id
                )
                try:
                    # Galaxy trans context is not available in a standalone Router endpoint;
                    # this path only works when the Galaxy WSGI app has injected the request
                    # context.  We import lazily and catch any missing-context errors.
                    from galaxy.ai.workflow_ops.autofix.autofix3_orchestrator import (
                        AutoFix3Orchestrator,
                    )

                    # trans is not available here — callers that need this path should
                    # use the ai_assistant endpoint which has DependsOnTrans.
                    raise HTTPException(
                        status_code=422,
                        detail=(
                            "Galaxy DB orchestrator path requires authenticated trans context. "
                            "Use the /api/invocations/{id}/ai/autofix endpoint instead."
                        ),
                    )
                except HTTPException:
                    raise
                except Exception as exc:
                    log.warning("autofix3: Galaxy path error: %s", exc)
                    result = {
                        "success": False,
                        "session_id": session_id,
                        "error": str(exc),
                        "total_attempts": 0,
                        "termination_reason": "orchestrator_unavailable",
                    }
                    state = "failed"
            else:
                result = {
                    "success": False,
                    "session_id": session_id,
                    "error": (
                        f"Workflow directory not found for invocation '{invocation_id}'. "
                        "The run may have completed and its work directory was cleaned up, "
                        "or it has not started yet."
                    ),
                    "total_attempts": 0,
                    "termination_reason": "workflow_dir_not_found",
                }
                state = "failed"

    except HTTPException:
        raise
    except Exception as exc:
        log.exception(
            "autofix3: unexpected error for invocation=%s", invocation_id
        )
        result = {
            "success": False,
            "session_id": session_id,
            "error": str(exc),
            "total_attempts": 0,
            "termination_reason": "internal_error",
        }
        state = "failed"

    # ── Persist session record ─────────────────────────────────────────────
    session_record: Dict[str, Any] = {
        "session_id": result.get("session_id", session_id),
        "state": state,
        "source": "manual",
        "active": False,
        "total_attempts": result.get("total_attempts", 0),
        "termination_reason": result.get("termination_reason"),
        "message": (
            result.get("error")
            or result.get("message")
            or ("Fix succeeded" if result.get("success") else "Fix failed")
        ),
        "last_action_at": datetime.now(timezone.utc).isoformat(),
        "auto_applied": result.get("auto_applied", False),
        "created_at": started_at,
    }

    with _sessions_lock:
        _sessions.setdefault(invocation_id, []).insert(0, session_record)

    _persist_session(invocation_id, session_record)

    # Return the full debug result merged with session metadata
    return {
        **result,
        "session_id": session_record["session_id"],
        "termination_reason": session_record["termination_reason"],
        "total_attempts": session_record["total_attempts"],
    }


@router.get(
    "/api/workflows/{workflow_id}/invocations/{invocation_id}/autofix3/sessions",
    summary="List AutoFix 3.0 sessions for a workflow invocation",
)
def list_autofix3_sessions(
    workflow_id: str,
    invocation_id: str,
    limit: int = Query(default=10, ge=1, le=50),
) -> Dict[str, Any]:
    """
    Returns the most recent AutoFix 3.0 sessions for the given invocation,
    newest first.  Falls back to disk if the in-memory cache is empty (e.g.,
    after a Galaxy server restart).
    """
    with _sessions_lock:
        sessions = list(_sessions.get(invocation_id, []))

    if not sessions:
        sessions = _load_sessions_from_disk(invocation_id)

    return {"sessions": sessions[:limit]}


_ANALYSIS_BASE = Path("database/ai_workflow_ops/analysis_results")

_SEVERITY_MAP = {
    "critical": "error",
    "high": "error",
    "medium": "warning",
    "low": "info",
}


@router.get(
    "/api/workflows/{invocation_id}/realtime/status",
    summary="Get AI realtime analysis status for a running workflow",
)
def get_workflow_realtime_status(invocation_id: str) -> Dict[str, Any]:
    """
    Returns AI-detected issues and AutoFix status for a workflow invocation.

    Data is read from ``database/ai_workflow_ops/analysis_results/workflow_{id}/latest.json``
    which is written by ``nextflow_monitor.py`` during execution.  When no analysis
    data exists yet the endpoint returns an empty payload (no error).

    The ``autofix`` object is assembled from in-memory AutoFix 3.0 session records
    for this invocation.
    """
    # ── Read latest.json from nextflow_monitor output ──────────────────────────
    latest_file = _ANALYSIS_BASE / f"workflow_{invocation_id}" / "latest.json"
    raw: Dict[str, Any] = {}
    if latest_file.exists():
        try:
            with latest_file.open() as f:
                raw = json.load(f)
        except Exception as exc:
            log.warning("realtime/status: failed to read %s: %s", latest_file, exc)

    # ── Map stored issues to frontend schema ───────────────────────────────────
    issues: List[Dict[str, Any]] = []
    for stored in raw.get("issues_detected", []):
        sev_raw = stored.get("severity", "medium").lower()
        issues.append({
            "type": stored.get("type", "unknown"),
            "severity": _SEVERITY_MAP.get(sev_raw, sev_raw),
            "message": stored.get("message", ""),
            "suggestion": stored.get("suggestion", ""),
            "auto_fixable": bool(stored.get("auto_fixable", False)),
        })

    # ── Assemble AutoFix summary from in-memory sessions ──────────────────────
    with _sessions_lock:
        inv_sessions = list(_sessions.get(invocation_id, []))
    if not inv_sessions:
        inv_sessions = _load_sessions_from_disk(invocation_id)

    fixes_applied = sum(
        s.get("fixes_applied", 0) for s in inv_sessions
    )
    autofix_active = any(s.get("active") for s in inv_sessions[:1])

    # ── Restart info (last session that has new_invocation_id) ────────────────
    restart_info: Optional[Dict[str, Any]] = None
    for s in inv_sessions:
        nid = s.get("new_invocation_id")
        if nid:
            restart_info = {"new_invocation_id": nid}
            break

    return {
        "workflow_id": invocation_id,
        "timestamp": raw.get("timestamp"),
        "status": raw.get("status"),
        "issues": issues,
        "autofix": {
            "enabled": True,
            "active": autofix_active,
            "fixes_applied": fixes_applied,
            "sessions_count": len(inv_sessions),
        },
        "restart_info": restart_info,
        "has_data": bool(raw),
    }


@router.get(
    "/api/workflows/{invocation_id}/error-summary",
    summary="Parse Nextflow failure logs into a structured error summary via LLM",
)
def get_workflow_error_summary(invocation_id: str) -> Dict[str, Any]:
    """
    Reads the last 200 lines of the Nextflow log for a failed run and asks a
    fast LLM (claude-haiku) to return a structured JSON summary with fields:
      error_type, failed_step, human_summary, root_cause, suggested_fix, can_resume.

    Falls back to a minimal unknown-error payload when logs are unavailable or
    the LLM call fails, so the UI always gets a well-formed response.
    """
    _FALLBACK = {
        "error_type": "unknown",
        "failed_step": None,
        "human_summary": "Workflow failed — check logs for details.",
        "root_cause": None,
        "suggested_fix": None,
        "can_resume": False,
    }

    # ── 1. Resolve working directory ──────────────────────────────────────────
    workflow_dir = _resolve_workflow_dir(invocation_id)
    if workflow_dir is None or not workflow_dir.exists():
        log.debug("error-summary: no workflow_dir found for invocation=%s", invocation_id)
        return _FALLBACK

    # ── 2. Read last 200 lines from nextflow.out / nextflow.err / .nextflow.log ─
    log_text = ""
    for candidate in [
        workflow_dir / "nextflow.out",
        workflow_dir / "nextflow.err",
        workflow_dir / ".nextflow.log",
    ]:
        try:
            if candidate.exists():
                lines = candidate.read_text(errors="replace").splitlines()
                if lines:
                    log_text = "\n".join(lines[-200:])
                    break
        except FileNotFoundError:
            continue
        except Exception as exc:
            log.debug("error-summary: could not read %s: %s", candidate, exc)

    if not log_text.strip():
        log.debug("error-summary: no log content for invocation=%s", invocation_id)
        return _FALLBACK

    # ── 3. Call LLM to parse the error ────────────────────────────────────────
    prompt = (
        "You are a bioinformatics workflow debugging assistant.\n"
        "Analyze the following Nextflow workflow log snippet and return ONLY a JSON object "
        "(no markdown, no explanation) with exactly these fields:\n"
        "  error_type: short category string (e.g. 'missing_file', 'permission_denied', 'oom', 'tool_not_found', 'unknown')\n"
        "  failed_step: name of the Nextflow process/step that failed, or null\n"
        "  human_summary: 1-2 sentence plain-English description of what went wrong\n"
        "  root_cause: brief technical explanation of the root cause, or null\n"
        "  suggested_fix: concrete actionable suggestion for the user, or null\n"
        "  can_resume: true if Nextflow -resume would likely succeed after the fix, false otherwise\n\n"
        f"Log:\n{log_text}"
    )

    try:
        from galaxy.ai.config import AIConfig
        from galaxy.ai.llm_client import LLMClient

        ai_config = AIConfig()
        llm_client = LLMClient(ai_config)

        raw_response = llm_client.complete(
            prompt=prompt,
            provider="anthropic",
            model="claude-haiku-20240307",
            max_tokens=512,
            temperature=0.0,
        )

        # Extract first JSON object from the response (handles stray text)
        import re as _re
        json_match = _re.search(r"\{[\s\S]*\}", raw_response or "")
        if not json_match:
            log.debug("error-summary: LLM returned no JSON for invocation=%s", invocation_id)
            return _FALLBACK

        parsed = json.loads(json_match.group())

        # Ensure required keys are present and types are safe
        result: Dict[str, Any] = {
            "error_type": str(parsed.get("error_type") or "unknown"),
            "failed_step": parsed.get("failed_step") or None,
            "human_summary": str(parsed.get("human_summary") or _FALLBACK["human_summary"]),
            "root_cause": parsed.get("root_cause") or None,
            "suggested_fix": parsed.get("suggested_fix") or None,
            "can_resume": bool(parsed.get("can_resume", False)),
        }
        return result

    except Exception as exc:
        log.warning("error-summary: LLM call failed for invocation=%s: %s", invocation_id, exc)
        return _FALLBACK


@router.get(
    "/api/autofix3/status",
    summary="Get AutoFix 3.0 system status and availability",
)
def get_autofix3_status() -> Dict[str, Any]:
    """
    Returns the current availability of AutoFix 3.0 components and the count
    of active / tracked sessions.
    """
    components: Dict[str, bool] = {}

    for name, mod_path in [
        ("IterativeDebugger", "galaxy.ai.workflow_ops.autofix.iterative_debugger"),
        ("DeepAnalysisAgent", "galaxy.ai.workflow_ops.autofix.agent"),
        ("EnhancedToolKit", "galaxy.ai.workflow_ops.autofix.toolkit_v2"),
        ("LLMClient", "galaxy.ai.llm_client"),
    ]:
        try:
            __import__(mod_path)
            components[name] = True
        except ImportError:
            components[name] = False

    all_available = all(components.values())

    with _sessions_lock:
        active_count = sum(
            1
            for sessions in _sessions.values()
            for s in sessions[:1]
            if s.get("active")
        )
        total_invocations = len(_sessions)

    return {
        "status": "operational" if all_available else "degraded",
        "autofix3_available": all_available,
        "components": components,
        "active_sessions": active_count,
        "total_invocations_tracked": total_invocations,
    }
