"""
Standalone Nextflow autofix runner — no Galaxy `trans` context required.

This wraps the "Path A" branch of the /api/autofix3/run HTTP endpoint
(autofix3.py:_resolve_workflow_dir → DeepAnalysisAgent → IterativeDebugger)
into a single callable suitable for invocation from:

  - the LangGraph pipeline's run_autofix node (no trans available there)
  - the existing HTTP endpoint (delegates here to avoid divergence)
  - tests + scripts that need to drive autofix from disk-state only

The Galaxy DB path (Path B) is unchanged and still lives in autofix3.py.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Dict, List, Optional

log = logging.getLogger(__name__)


def resolve_workflow_dir(invocation_id: str) -> Optional[Path]:
    """Resolve the on-disk Nextflow work dir for an invocation id.

    Priority:
      1. In-process `_runs` registry maintained by `nextflow_executor`
      2. Common local work-dir conventions under /tmp/biomate_runs/
    """
    try:
        from galaxy.webapps.galaxy.api.nextflow_executor import _runs, _runs_lock
        with _runs_lock:
            run_info = _runs.get(invocation_id)
        if run_info:
            log_path = run_info.get("log_path")
            if log_path:
                return Path(log_path).parent
    except Exception as exc:
        log.debug("autofix-runner: _runs lookup failed: %s", exc)

    for candidate in (
        Path(f"/tmp/biomate_runs/{invocation_id}"),
        Path(f"/tmp/nextflow_runs/{invocation_id}"),
    ):
        if candidate.exists() and candidate.is_dir():
            return candidate
    return None


def read_error_logs(workflow_dir: Path, max_lines: int = 200) -> str:
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
                if "FAILED" in line or "ERROR" in line.upper():
                    fragments.append(line)
        except Exception:
            pass
    return "\n".join(fragments)


def get_first_failed_task(workflow_dir: Path) -> str:
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


def run_nextflow_autofix(
    invocation_id: str,
    workflow_id: str = "_",
    max_attempts: int = 5,
    timeout_seconds: int = 300,
    db_path: Optional[str] = None,
) -> Dict[str, Any]:
    """Run AutoFix3's IterativeDebugger against a Nextflow run on disk.

    Returns a dict with keys:
      success: bool
      total_attempts: int
      termination_reason: str
      message: str (when nothing to fix)
      session_id: str | None
    """
    workflow_dir = resolve_workflow_dir(invocation_id)
    if workflow_dir is None or not workflow_dir.exists():
        return {
            "success": False,
            "total_attempts": 0,
            "termination_reason": "workflow_dir_not_found",
            "session_id": None,
        }

    error_logs = read_error_logs(workflow_dir)
    if not error_logs.strip():
        return {
            "success": True,
            "total_attempts": 0,
            "termination_reason": "no_errors",
            "message": "No error logs — run may have succeeded.",
            "session_id": None,
        }

    failed_task = get_first_failed_task(workflow_dir)

    try:
        from galaxy.ai.config import AIConfig
        from galaxy.ai.llm_client import LLMClient
        from galaxy.ai.workflow_ops.autofix.toolkit_v2 import EnhancedToolKit
        from galaxy.ai.workflow_ops.autofix.agent import DeepAnalysisAgent
        from galaxy.ai.workflow_ops.autofix.iterative_debugger import IterativeDebugger
    except Exception as exc:
        log.warning("autofix-runner: dependency import failed: %s", exc)
        return {
            "success": False,
            "total_attempts": 0,
            "termination_reason": "import_error",
            "session_id": None,
            "error": str(exc),
        }

    ai_config = AIConfig()
    llm_client = LLMClient(ai_config)
    context = {"workflow_id": workflow_id, "invocation_id": invocation_id}
    toolkit = EnhancedToolKit(app_config=ai_config, context=context, workflow_dir=workflow_dir)

    if db_path is None:
        for cand in (
            Path(__file__).parents[5] / "database" / "galaxy_ai_tools.db",
            Path("/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"),
            Path("/app/database/galaxy_ai_tools.db"),
        ):
            if cand.exists():
                db_path = str(cand)
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
        max_attempts=max_attempts,
        timeout_seconds=timeout_seconds,
    )

    try:
        debug_result = debugger.run_until_fixed(
            task_name=failed_task,
            error_logs=error_logs,
            exit_code=1,
            context=context,
        )
    except Exception as exc:
        log.exception("autofix-runner: debugger crashed for invocation=%s", invocation_id)
        return {
            "success": False,
            "total_attempts": 0,
            "termination_reason": "debugger_crash",
            "session_id": None,
            "error": str(exc),
        }

    return {
        "success": bool(debug_result.get("success")),
        "total_attempts": int(debug_result.get("total_attempts", 0)),
        "termination_reason": debug_result.get("termination_reason", "unknown"),
        "session_id": debug_result.get("session_id"),
        **{k: v for k, v in debug_result.items() if k not in {
            "success", "total_attempts", "termination_reason", "session_id"
        }},
    }
