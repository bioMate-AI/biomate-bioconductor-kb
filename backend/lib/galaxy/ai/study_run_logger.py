"""
study_run_logger.py
===================
Writes durable per-run JSON log files for every Nextflow workflow execution.

Required by the pilot study plan (docs/pilot_study/20260324_INTERNAL_PILOT_TEST_PLAN.md):
  Location : $BIOMATE_STUDY_LOG_DIR/<session_id>_<workflow>_<timestamp>.json
  Default  : /tmp/biomate-study-logs/
  Format   : JSON (see StudyRunRecord)

Usage (called from nextflow_executor.py after run completes)::

    from galaxy.ai.study_run_logger import StudyRunLogger
    StudyRunLogger.record(run_meta, output_summary)
"""

from __future__ import annotations

import json
import logging
import os
import re
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

log = logging.getLogger(__name__)

# Directory for study run logs. Override with BIOMATE_STUDY_LOG_DIR env var.
_DEFAULT_LOG_DIR = Path(os.environ.get("BIOMATE_STUDY_LOG_DIR", "/tmp/biomate-study-logs"))

# Safeguard against concurrent directory creation
_dir_lock = threading.Lock()


def _ensure_dir(path: Path) -> Path:
    with _dir_lock:
        path.mkdir(parents=True, exist_ok=True)
    return path


def _safe_filename(s: str) -> str:
    """Strip characters unsafe for filenames."""
    return re.sub(r"[^A-Za-z0-9._-]", "_", s)


class StudyRunRecord:
    """
    Canonical schema for one workflow run log entry.

    Fields required by the pilot test plan are marked REQUIRED.
    All other fields are best-effort.
    """

    def __init__(
        self,
        *,
        # — Identity —
        run_id: str,                          # REQUIRED: Nextflow run UUID
        session_id: str,                      # REQUIRED: chat/API session ID (== run_id if not provided)
        invocation_id: str = "",
        user_id: str = "anonymous",
        # — Workflow —
        workflow: str,                        # REQUIRED: short workflow name
        workflow_path: str = "",
        workflow_domain: str = "",
        # — Timing —
        query_submitted_at: Optional[str] = None,   # REQUIRED: ISO8601
        result_delivered_at: Optional[str] = None,  # REQUIRED: ISO8601
        elapsed_seconds: Optional[int] = None,      # REQUIRED
        # — Outcome —
        status: str = "unknown",              # succeeded | failed | unknown
        returncode: Optional[int] = None,
        manual_correction_required: bool = False,
        # — Drug discovery specific (Session 1 / 5 / 6) —
        compound_count: int = 0,
        compounds_passed: int = 0,
        compounds_failed: int = 0,
        compounds_conditional: int = 0,
        top_ranked_compound: str = "",
        terfenadine_rank: Optional[int] = None,
        # — Infrastructure —
        runtime_mode: str = "",               # local | awsbatch
        outdir: str = "",
        log_path: str = "",
        trace_path: str = "",
        # — QC gates —
        qc_gates: Optional[List[Dict[str, Any]]] = None,
        # — Billing —
        estimated_llm_cost_usd: float = 0.0,
        estimated_compute_cost_usd: float = 0.0,
        # — Free-form output summary —
        output_summary: Optional[Dict[str, Any]] = None,
    ):
        self.run_id = run_id
        self.session_id = session_id or run_id
        self.invocation_id = invocation_id
        self.user_id = user_id
        self.workflow = workflow
        self.workflow_path = workflow_path
        self.workflow_domain = workflow_domain
        self.query_submitted_at = query_submitted_at or datetime.now(timezone.utc).isoformat()
        self.result_delivered_at = result_delivered_at
        self.elapsed_seconds = elapsed_seconds
        self.status = status
        self.returncode = returncode
        self.manual_correction_required = manual_correction_required
        self.compound_count = compound_count
        self.compounds_passed = compounds_passed
        self.compounds_failed = compounds_failed
        self.compounds_conditional = compounds_conditional
        self.top_ranked_compound = top_ranked_compound
        self.terfenadine_rank = terfenadine_rank
        self.runtime_mode = runtime_mode
        self.outdir = outdir
        self.log_path = log_path
        self.trace_path = trace_path
        self.qc_gates = qc_gates or []
        self.estimated_llm_cost_usd = estimated_llm_cost_usd
        self.estimated_compute_cost_usd = estimated_compute_cost_usd
        self.output_summary = output_summary or {}

    def to_dict(self) -> Dict[str, Any]:
        return {
            "run_id": self.run_id,
            "session_id": self.session_id,
            "invocation_id": self.invocation_id,
            "user_id": self.user_id,
            "workflow": self.workflow,
            "workflow_path": self.workflow_path,
            "workflow_domain": self.workflow_domain,
            "query_submitted_at": self.query_submitted_at,
            "result_delivered_at": self.result_delivered_at,
            "elapsed_seconds": self.elapsed_seconds,
            "status": self.status,
            "returncode": self.returncode,
            "manual_correction_required": self.manual_correction_required,
            "compound_count": self.compound_count,
            "compounds_passed": self.compounds_passed,
            "compounds_failed": self.compounds_failed,
            "compounds_conditional": self.compounds_conditional,
            "top_ranked_compound": self.top_ranked_compound,
            "terfenadine_rank": self.terfenadine_rank,
            "runtime_mode": self.runtime_mode,
            "outdir": self.outdir,
            "log_path": self.log_path,
            "trace_path": self.trace_path,
            "qc_gates": self.qc_gates,
            "estimated_llm_cost_usd": self.estimated_llm_cost_usd,
            "estimated_compute_cost_usd": self.estimated_compute_cost_usd,
            "output_summary": self.output_summary,
        }


class StudyRunLogger:
    """
    Static helper that serialises a StudyRunRecord to a dated JSON file.

    Thread-safe: uses a per-file write lock.
    """

    @staticmethod
    def record(run_meta: Dict[str, Any], output_summary: Optional[Dict[str, Any]] = None, log_dir: Optional[Path] = None) -> Optional[Path]:
        """
        Build a StudyRunRecord from the run_meta dict (as stored in _runs[run_id])
        and write it to the study log directory.

        Returns the Path of the written file, or None on failure.
        """
        try:
            run_id = run_meta.get("run_id", "unknown")
            nf_path = run_meta.get("nextflow_path", "") or run_meta.get("entry", "")
            workflow_name = nf_path.rsplit("/", 1)[-1].replace(".nf", "") if nf_path else run_id

            started_at = run_meta.get("started_at")
            completed_at = time.time()
            elapsed = int(completed_at - started_at) if started_at else None

            session_id = run_meta.get("invocation_id") or run_id
            user_id = run_meta.get("user_id", "anonymous")

            # Pull LLM cost accumulated during this session from the cost log.
            llm_cost_usd = 0.0
            try:
                from galaxy.ai import cost_log as _cost_log
                llm_cost_usd = round(
                    sum(
                        r.get("cost_usd", 0.0)
                        for r in _cost_log.query(user_id=user_id)
                        if r.get("session_id") == session_id
                    ),
                    6,
                )
            except Exception:
                pass

            record = StudyRunRecord(
                run_id=run_id,
                session_id=session_id,
                invocation_id=run_meta.get("invocation_id", ""),
                user_id=user_id,
                workflow=workflow_name,
                workflow_path=nf_path,
                workflow_domain=run_meta.get("workflow_domain", ""),
                query_submitted_at=datetime.fromtimestamp(started_at, tz=timezone.utc).isoformat() if started_at else None,
                result_delivered_at=datetime.fromtimestamp(completed_at, tz=timezone.utc).isoformat(),
                elapsed_seconds=elapsed,
                status=run_meta.get("status", "unknown"),
                returncode=run_meta.get("returncode"),
                runtime_mode=run_meta.get("runtime_mode", ""),
                outdir=run_meta.get("outdir", ""),
                log_path=run_meta.get("log_path", ""),
                trace_path=run_meta.get("trace_path", ""),
                estimated_llm_cost_usd=llm_cost_usd,
                output_summary=output_summary or {},
            )

            return StudyRunLogger.write(record, log_dir=log_dir)
        except Exception as exc:
            log.warning("[StudyRunLogger] Failed to build record for run %s: %s", run_meta.get("run_id"), exc)
            return None

    @staticmethod
    def write(record: StudyRunRecord, log_dir: Optional[Path] = None) -> Optional[Path]:
        """Serialise record to JSON file. Returns path on success."""
        try:
            base_dir = log_dir or _DEFAULT_LOG_DIR
            _ensure_dir(base_dir)

            ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            wf_safe = _safe_filename(record.workflow)[:40]
            sid_safe = _safe_filename(record.session_id)[:16]
            filename = f"{sid_safe}_{wf_safe}_{ts}.json"
            path = base_dir / filename

            with open(path, "w", encoding="utf-8") as fh:
                json.dump(record.to_dict(), fh, indent=2, ensure_ascii=False)
                fh.write("\n")

            log.info("[StudyRunLogger] Wrote run log: %s", path)
            return path
        except Exception as exc:
            log.warning("[StudyRunLogger] Failed to write log: %s", exc)
            return None

    @staticmethod
    def list_logs(log_dir: Optional[Path] = None, user_id: Optional[str] = None) -> List[Dict[str, Any]]:
        """Return all run log records, optionally filtered by user_id."""
        base_dir = log_dir or _DEFAULT_LOG_DIR
        records: List[Dict[str, Any]] = []
        if not base_dir.exists():
            return records
        for p in sorted(base_dir.glob("*.json")):
            try:
                d = json.loads(p.read_text(encoding="utf-8"))
                if user_id and d.get("user_id") != user_id:
                    continue
                d["_log_file"] = str(p)
                records.append(d)
            except Exception:
                pass
        return records

    @staticmethod
    def get_log(session_id: str, log_dir: Optional[Path] = None) -> Optional[Dict[str, Any]]:
        """Return the most recent log record for a given session_id."""
        matches = [r for r in StudyRunLogger.list_logs(log_dir) if r.get("session_id") == session_id]
        return matches[-1] if matches else None
