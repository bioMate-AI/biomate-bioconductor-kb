"""
Nextflow Executor API

Provides POST /api/nextflow/execute — launches a Nextflow workflow
as a background subprocess and returns tracking IDs.

Does NOT require Galaxy workflow/invocation infrastructure.
"""
# CRITICAL: keep this first import. PEP 604 union syntax (`list | str | None`)
# below requires it on Python 3.9. Without it Galaxy gunicorn workers crash at
# boot with TypeError, sending the API into a perpetual restart loop (Gap 0).
# Auto-sync has stripped this line 4+ times — do not remove.
from __future__ import annotations

import logging
import os
import re
import subprocess
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional, Union, Tuple

from fastapi import HTTPException, Request, Response
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from galaxy.managers.context import ProvidesUserContext
from galaxy.webapps.galaxy.api import (
    DependsOnTrans,
    Router,
)

log = logging.getLogger(__name__)

# Load .env from the backend root so NEXTFLOW_USE_AWS, AWS_S3_BUCKET, etc.
# are available even when gunicorn is started without explicit env exports.
try:
    _backend_root = Path(__file__).resolve().parents[5]
    _dotenv_path = _backend_root / ".env"
    if _dotenv_path.exists():
        from dotenv import load_dotenv
        load_dotenv(_dotenv_path, override=True)   # override=True: .env changes take effect on SIGHUP reload
        log.info(f"[Nextflow] Loaded environment from {_dotenv_path}")
except Exception as _e:
    log.warning(f"[Nextflow] Could not load .env: {_e}")

router = Router(tags=["nextflow"])

# In-process registry: run_id → {status, process, outdir, ...}
_runs: Dict[str, Dict[str, Any]] = {}
_runs_lock = threading.Lock()

# Concurrency throttle for Nextflow head-process launches.
# Each NF head JVM is ~500MB–1GB resident. Without a cap, parallel-fired
# workflow submissions OOM-kill the Galaxy container (observed 2026-06-07
# host impairment at 17:25, Galaxy crash again 2026-06-08 ~19:00 — both
# from ~20 concurrent NF heads on an 8GB dev box). Production hosts may
# tolerate more; tune via BIOMATE_NF_MAX_CONCURRENT.
#
# Default 10 = headroom for Galaxy gunicorn + Celery + Postgres on 8GB dev,
# given the 512MB head heap cap also added in this commit. With -Xmx512m each
# NF head holds ~700MB resident; 10 heads × 0.7 GB = 7 GB worst-case. Safe
# upper bound for 16GB hosts is ~20 with the same per-head budget.
_nf_max_concurrent = int(os.environ.get("BIOMATE_NF_MAX_CONCURRENT", "10"))
_nf_launch_semaphore = threading.BoundedSemaphore(_nf_max_concurrent)


def _narrate_chat(invocation_id: str, kind: str, technical: Optional[Dict[str, Any]] = None) -> None:
    """
    Emit a workflow-progress chat line to the frontend's SSE inject endpoint.

    Delegates friendly-text generation to workflow_chat_narrator (the single
    source of truth for chat-progress copy). Safe to call from any thread —
    network failures and missing FRONTEND_URL are swallowed.
    """
    try:
        from galaxy.ai.workflow_ops.workflow_chat_narrator import emit as _narrator_emit
    except Exception:
        return

    import os as _os
    import json as _json
    import urllib.request as _urllib

    frontend_url = _os.environ.get("FRONTEND_URL", "http://localhost:5000")
    inject_url = f"{frontend_url}/internal/sse-inject"

    def _post_sse(event_type: str, data: Dict[str, Any]) -> None:
        try:
            req = _urllib.Request(
                inject_url,
                data=_json.dumps({
                    "invocation_id": invocation_id,
                    "event_type": event_type,
                    "data": data,
                }).encode("utf-8"),
                headers={"Content-Type": "application/json"},
            )
            with _urllib.urlopen(req, timeout=5):
                pass
        except Exception as exc:
            log.debug("[narrate_chat] SSE inject failed for %s: %s", event_type, exc)

    # narrator.emit() handles friendly-text rendering + engineer-channel logging
    # AND fires the SSE callback we provide.
    _narrator_emit(invocation_id, kind, technical, sse_callback=_post_sse)


def _aws_cli_bin() -> str:
    """Canonical path to the aws CLI binary inside the Galaxy container.

    Galaxy's Dockerfile installs aws CLI v2 to /opt/aws-cli/bin/aws (the
    same path used by Nextflow's aws.batch.cliPath, intentionally — see
    docs/nextPhase/20260410_AWS_BATCH_CLIPATH_COMPLETE_FIX.md). Use the
    absolute path so the call works even on stale-image dev containers
    that have /opt/aws-cli installed but no `aws` on PATH. Fall back to
    PATH lookup ('aws') so the function still works in environments
    that install via apt or pip into /usr/local/bin.
    """
    return "/opt/aws-cli/bin/aws" if os.path.exists("/opt/aws-cli/bin/aws") else "aws"


def _sanitize_subprocess_env(base: Optional[Dict[str, str]] = None) -> Dict[str, str]:
    """Drop exported bash completion functions (BASH_FUNC_*) that break Batch/Nextflow shells,
    and assert the Nextflow framework pin is present.

    Returns an env dict with NXF_VER already populated. Subprocess launchers
    must use this rather than building env from os.environ directly, or the
    pin will silently drift (see docs/20260601_NEXTFLOW_VERSION_DRIFT.md).

    History: this pin has been stripped by parallel-session syncs 4+ times.
    The previous "fix it at the launch site" approach kept getting reverted
    because the launch-site line is easy for a sweep to mistake as
    redundant. Living here, every launcher already calls this function for
    BASH_FUNC sanitization — the pin rides along and is harder to strip
    without breaking that path.
    """
    raw = dict(base if base is not None else os.environ)
    clean = {k: v for k, v in raw.items() if not k.startswith("BASH_FUNC")}
    # Defence-in-depth: ensure the Nextflow framework version pin is set in
    # every subprocess env. Without this, the Nextflow launcher script
    # downloads whatever framework jar is current on JFrog at first invocation
    # (drifted from 25.10.5 to 26.04.2 between 2026-05-25 and 2026-06-01).
    # Hard pin — always force the value, don't honour "user-supplied" overrides.
    # We've had this stripped 5+ times by parallel-session sweeps; each time
    # the launcher silently downloads NF 26.04.2 (the LATEST), which makes
    # AWS CRT the default S3 client and crashes the JVM at FileTransfer/
    # PublishDir. There is no legitimate reason for a different value in
    # this codebase right now.
    desired_nxf_ver = "25.10.5"
    if clean.get("NXF_VER") != desired_nxf_ver:
        prior = clean.get("NXF_VER", "<unset>")
        clean["NXF_VER"] = desired_nxf_ver
        if prior != "<unset>":
            log.warning(
                f"[Nextflow] NXF_VER was {prior!r} in subprocess env — overriding to "
                f"{desired_nxf_ver}. The hard pin exists because NF 26.04 makes AWS "
                f"CRT the default S3 client and crashes the JVM in this glibc/JDK combo."
            )
    # NXF_OFFLINE=true is in the Galaxy container ENV (set by Dockerfile to
    # protect against auto-fetching a NEW Nextflow version). The container
    # process inherits it. But Nextflow plugins (nf-amazon@3.4.4 in particular)
    # are NOT pre-cached — they download on first use. With NXF_OFFLINE=true
    # the launcher refuses to fetch nf-amazon and fails with:
    #   "Plugin with id nf-amazon not found in any repository"
    # So we explicitly UNSET NXF_OFFLINE for the subprocess env. The per-run
    # NXF_HOME is a fresh dir each time, so the plugin fetch happens once per
    # run. Cost: ~10s extra at workflow start. Eliminating that requires
    # pre-baking nf-amazon into the image, which is a separate rebuild.
    # We keep NXF_VER as the load-bearing pin (NF 26.04 = doom, NF 25.10.5 =
    # safe), and disable NXF_OFFLINE here so plugins can still resolve.
    clean.pop("NXF_OFFLINE", None)
    return clean


# QC handler registry: invocation_id → NextflowQCGateHandler
# Populated by _start_qc_monitor so the export endpoint can retrieve live state.
_qc_handlers: Dict[str, Any] = {}
_qc_handlers_lock = threading.Lock()

# ---------------------------------------------------------------------------
# Public database accession detection
# ---------------------------------------------------------------------------
# Covers all major life-science databases so accession strings are never treated
# as local file paths.  Each entry maps a human-readable type label to a compiled
# regex (anchored) and a handler type used to choose the download strategy.
#
# handler types:
#   "sequencing"   → nf-core/fetchngs pre-step (produces samplesheet.csv)
#   "structure"    → RCSB / EMDB HTTP download  (produces .cif / .map.gz)
#   "protein_seq"  → UniProt / NCBI protein API  (produces .fasta)
#   "proteomics"   → PRIDE FTP or aspera         (produces raw MS files)
#   "chemical"     → ChEMBL / PubChem API        (produces .sdf / .json)
#   "genomic_ref"  → Ensembl REST / NCBI API     (produces .fasta / .vcf)
#   "annotation"   → no file download; informational only (rs IDs, ClinVar)
# ---------------------------------------------------------------------------

_ACCESSION_REGISTRY: list[dict] = [
    # ── Sequencing / raw reads ────────────────────────────────────────────
    {
        "label": "SRA run",
        "handler": "sequencing",
        "re": re.compile(r'^[SED]RR\d{6,9}$', re.IGNORECASE),
        "example": "SRR628582",
    },
    {
        "label": "ENA / SRA project",
        "handler": "sequencing",
        "re": re.compile(r'^[ES]RP\d{6,9}$', re.IGNORECASE),
        "example": "SRP123456",
    },
    {
        "label": "BioProject",
        "handler": "sequencing",
        "re": re.compile(r'^PRJ[NE][A-Z]\d{4,9}$', re.IGNORECASE),
        "example": "PRJNA12345",
    },
    {
        "label": "GEO series",
        "handler": "sequencing",
        "re": re.compile(r'^GSE\d{4,9}$', re.IGNORECASE),
        "example": "GSE12345",
    },
    {
        "label": "GEO sample",
        "handler": "sequencing",
        "re": re.compile(r'^GSM\d{5,9}$', re.IGNORECASE),
        "example": "GSM123456",
    },
    {
        "label": "ArrayExpress / BioStudies",
        "handler": "sequencing",
        "re": re.compile(r'^E-[A-Z]{4}-\d{4,9}$', re.IGNORECASE),
        "example": "E-MTAB-1234",
    },
    # ── Macromolecular structure ──────────────────────────────────────────
    {
        "label": "PDB entry",
        "handler": "structure",
        # PDB IDs: digit + 3 alphanumeric chars, at least one must be a letter
        # (pure-numeric 4-char strings like "1000" are not valid PDB IDs)
        "re": re.compile(r'^[0-9](?=[A-Z0-9]{0,2}[A-Z])[A-Z0-9]{3}$', re.IGNORECASE),
        "example": "4ZQK",
    },
    {
        "label": "EMDB entry",
        "handler": "structure",
        "re": re.compile(r'^EMD-\d{4,6}$', re.IGNORECASE),
        "example": "EMD-1234",
    },
    # ── Protein / gene sequences ─────────────────────────────────────────
    {
        "label": "UniProt accession",
        "handler": "protein_seq",
        # UniProtKB: [OPQ][0-9][A-Z0-9]{3}[0-9] or [A-NR-Z][0-9][A-Z][A-Z0-9]{2}[0-9]
        "re": re.compile(
            r'^[OPQ][0-9][A-Z0-9]{3}[0-9]$|^[A-NR-Z][0-9]([A-Z][A-Z0-9]{2}[0-9]){1,2}$',
            re.IGNORECASE,
        ),
        "example": "P12345",
    },
    {
        "label": "NCBI RefSeq protein",
        "handler": "protein_seq",
        "re": re.compile(r'^[NXW]P_\d{6,9}(\.\d+)?$', re.IGNORECASE),
        "example": "NP_012345.1",
    },
    {
        "label": "NCBI RefSeq nucleotide",
        "handler": "genomic_ref",
        "re": re.compile(r'^[NXW][CGMRTZ]_\d{6,9}(\.\d+)?$', re.IGNORECASE),
        "example": "NC_000001.11",
    },
    {
        "label": "Ensembl gene",
        "handler": "genomic_ref",
        "re": re.compile(r'^ENSG\d{11}(\.\d+)?$', re.IGNORECASE),
        "example": "ENSG00000141510",
    },
    {
        "label": "Ensembl transcript",
        "handler": "genomic_ref",
        "re": re.compile(r'^ENST\d{11}(\.\d+)?$', re.IGNORECASE),
        "example": "ENST00000269305",
    },
    {
        "label": "Ensembl protein",
        "handler": "protein_seq",
        "re": re.compile(r'^ENSP\d{11}(\.\d+)?$', re.IGNORECASE),
        "example": "ENSP00000269305",
    },
    # ── Proteomics / mass spectrometry ───────────────────────────────────
    {
        "label": "PRIDE dataset",
        "handler": "proteomics",
        "re": re.compile(r'^PXD\d{6,9}$', re.IGNORECASE),
        "example": "PXD001234",
    },
    {
        "label": "MassIVE dataset",
        "handler": "proteomics",
        "re": re.compile(r'^MSV\d{9}$', re.IGNORECASE),
        "example": "MSV000079033",
    },
    # ── Chemical / small molecules ───────────────────────────────────────
    {
        "label": "ChEMBL compound",
        "handler": "chemical",
        "re": re.compile(r'^CHEMBL\d{1,9}$', re.IGNORECASE),
        "example": "CHEMBL25",
    },
    {
        "label": "PubChem CID",
        "handler": "chemical",
        "re": re.compile(r'^CID\d{1,9}$', re.IGNORECASE),
        "example": "CID2244",
    },
    # ── Variant / clinical annotation (no download, flag only) ───────────
    {
        "label": "dbSNP variant",
        "handler": "annotation",
        "re": re.compile(r'^rs\d{6,12}$', re.IGNORECASE),
        "example": "rs1234567",
    },
    {
        "label": "ClinVar variant",
        "handler": "annotation",
        "re": re.compile(r'^[RV]CV\d{9}$', re.IGNORECASE),
        "example": "VCV000012345",
    },
]


_ANSI_ESCAPE_RE = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')

# Nextflow startup noise patterns — lines matching any of these are dropped
# from log_tail to keep execution logs focused on actual process output.
_NF_NOISE_RE = re.compile(
    r'(?:'
    r'N\s+E\s+X\s+T\s+F\s+L\s+O\s+W'          # ASCII banner "N E X T F L O W"
    r'|Nextflow\s+\d+\.\d+\.\d+\s+is available'  # version-update notice
    r'|Please consider updating'                  # update recommendation
    r'|Downloading nextflow dependencies'          # initial dep download
    r'|nf-core/tools version'                     # nf-core tooling header
    r')',
    re.IGNORECASE,
)

def _strip_ansi(text: str) -> str:
    """Remove ANSI escape sequences (colors, cursor movement) from terminal output."""
    return _ANSI_ESCAPE_RE.sub('', text)


def _clean_log_line(line: str) -> str:
    """Strip ANSI codes and return the cleaned line, or empty string if it is noise."""
    cleaned = _strip_ansi(line).rstrip()
    if _NF_NOISE_RE.search(cleaned):
        return ''
    return cleaned


_NF_LOG_FAILURE_MARKERS = (
    "Workflow execution failed",
    "Pipeline failed",
    "ERROR ~ ",
    "WorkflowScriptErrorException",
    "ProcessFailedException",
    "Session aborted",
    "netmhcpan_path not specified",
    "netmhciipan_path not specified",
)

_NF_LOG_EXCEPTION_RE = re.compile(
    # DO NOT REVERT: WARN is intentionally excluded. Nextflow emits many
    # benign WARNs (e.g. "no process matching config selector: CRYODRGN_TRAIN"
    # for absent optional processes, "Unrecognized config option
    # 'process.environment.BIOMATE_USER_ID'"). Matching WARN here marks every
    # tier 0 run as failed even when Phase A is healthily submitting to Batch.
    # See docs/20260603_TIER0_COMPREHENSIVE_E2E_AND_DISPATCH_BUG.md.
    r'(?:'
    r'Caused by:\s*\w'
    r'|(?:^|\s)ERROR\s+(?:nextflow|groovy|org\.codehaus\.groovy)'
    r'|nextflow\.exception\.\w+'
    r'|org\.codehaus\.groovy'
    r'|groovy\.lang\.\w+Exception'
    r'|Stack trace:'
    r'|\tat groovy\.'
    r'|\tat org\.codehaus\.groovy'
    r'|\tat java\.'
    r'|Script compilation error'
    r'|MissingPropertyException'
    r'|MissingMethodException'
    r')',
    re.IGNORECASE | re.MULTILINE,
)

_S3_OUTPUT_REQUIRED_DOMAINS = frozenset({
    "drug_discovery", "pharmacology", "epitope_prediction",
    "immunoinformatics", "docking",
})

_QUICK_FAIL_ZERO_STEPS_THRESHOLD_S = 120

_NF_LOG_WORKFLOW_STATS_RE = re.compile(
    r"WorkflowStats\[succeededCount=(\d+);\s*failedCount=(\d+)",
)


def _parse_workflow_stats_from_log(
    log_full_text: str = "",
    log_tail: Optional[Union[list, str]] = None,
) -> Optional[Tuple[int, int]]:
    """Return (succeeded_count, failed_count) from the last WorkflowStats line in logs."""
    text_parts: list[str] = []
    if log_full_text:
        text_parts.append(log_full_text)
    if log_tail:
        if isinstance(log_tail, list):
            text_parts.append("\n".join(str(line) for line in log_tail))
        else:
            text_parts.append(str(log_tail))
    combined = "\n".join(text_parts)
    matches = list(_NF_LOG_WORKFLOW_STATS_RE.finditer(combined))
    if not matches:
        return None
    m = matches[-1]
    return int(m.group(1)), int(m.group(2))


def _log_indicates_nextflow_failure(
    log_full_text: str = "",
    log_tail: Optional[Union[list, str]] = None,
) -> bool:
    """True when log content suggests failure despite a clean Nextflow exit code."""
    text_parts: list[str] = []
    if log_full_text:
        text_parts.append(log_full_text)
    if log_tail:
        if isinstance(log_tail, list):
            text_parts.append("\n".join(str(line) for line in log_tail))
        else:
            text_parts.append(str(log_tail))
    combined = "\n".join(text_parts)
    if not combined.strip():
        return False
    for marker in _NF_LOG_FAILURE_MARKERS:
        if marker in combined:
            return True
    return bool(_NF_LOG_EXCEPTION_RE.search(combined))


def _workflow_requires_s3_outputs(workflow_domain: str, nextflow_path: str = "") -> bool:
    domain = (workflow_domain or "").lower()
    if domain in _S3_OUTPUT_REQUIRED_DOMAINS:
        return True
    path_low = (nextflow_path or "").lower()
    return any(token in path_low for token in (
        "epitope", "netmhc", "docking", "admet", "pharmacology", "drug_discovery",
    ))


def _read_run_timing_json(run_id: str) -> Dict[str, Any]:
    """Load persisted timing.json for a run (cross-worker terminal state)."""
    timing_path = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs")) / run_id / "timing.json"
    if not timing_path.is_file():
        return {}
    try:
        import json as _json

        return _json.loads(timing_path.read_text())
    except Exception:
        return {}


def _read_run_nextflow_log_text(log_dir: Path) -> tuple[str, list[str]]:
    """Merge launcher and work-dir Nextflow logs (AWS Batch runs often only complete in work/.nextflow.log).

    The returned log_tail is the last 20 non-noise lines, BUT we also prefer
    any ERROR / WARN / Caused by / Exception / FATAL lines from the broader
    log when present. On an early script-parse failure the last 20 lines are
    DEBUG startup; the actual stack trace lives a few hundred lines earlier,
    is in the log file, and is what an operator needs to see. Pulling those
    into log_tail surfaces the real cause to the run-status API.
    """
    parts: list[str] = []
    for rel in (Path("nextflow.log"), Path("work") / ".nextflow.log"):
        path = log_dir / rel
        if not path.is_file():
            continue
        try:
            parts.append(path.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            continue
    combined = "\n".join(parts)
    cleaned_lines = [c for l in combined.splitlines() if (c := _clean_log_line(l))]
    # Window of last 80 cleaned lines for the tail itself.
    tail_window = cleaned_lines[-80:][-20:]
    # Surface the most recent error context anywhere in the log so operators
    # don't have to ssh in just to read the .nextflow.log.
    err_markers = (
        "ERROR",
        "WARN",
        " FATAL",
        "Caused by:",
        "Exception:",
        "at nextflow.",
        "Pipeline failed",
        "Workflow execution failed",
        "Cannot find",
        "Missing",
        "Unable to ",
        "Unexpected token",
        "syntax error",
    )
    err_lines = [l for l in cleaned_lines if any(m in l for m in err_markers)][-15:]
    if err_lines:
        # Put the error excerpt at the END of log_tail so JSON consumers that
        # render the tail get the error block visible without scrolling.
        marker = "--- error context ---"
        if marker not in tail_window:
            log_tail = tail_window + [marker] + err_lines
        else:
            log_tail = tail_window
    else:
        log_tail = tail_window
    return combined, log_tail


def _evaluate_workflow_trace_terminal(
    log_dir: Path,
    log_full_text: str,
    log_tail: Optional[List[str]] = None,
) -> tuple[bool, bool, int, int, int]:
    """Return (trace_done, trace_failed, completed_count, failed_count, total_count)."""
    trace_path = log_dir / "workflow-trace.txt"
    if not trace_path.is_file():
        return False, False, 0, 0, 0
    try:
        trace_lines = [
            l for l in trace_path.read_text().splitlines()
            if l.strip() and not l.startswith("task_id")
        ]
    except Exception:
        return False, False, 0, 0, 0
    total = len(trace_lines)
    completed = sum(1 for l in trace_lines if "\tCOMPLETED\t" in l)
    failed = sum(1 for l in trace_lines if "\tFAILED\t" in l)
    nf_log_done = "Execution complete" in log_full_text
    nf_log_failed = _log_indicates_nextflow_failure(log_full_text, log_tail)
    if total > 0 and (completed + failed) >= total and (nf_log_done or nf_log_failed):
        return True, failed > 0 or nf_log_failed, completed, failed, total
    if (nf_log_done or nf_log_failed) and total == 0:
        return True, nf_log_failed, 0, 0, 0
    return False, False, completed, failed, total


def _looks_like_log_stream_orphan_failure(disk: dict) -> bool:
    """timing.json marked failed within ~30s with rc in (-1, 1) from a lost log-stream thread.

    The classic case: gunicorn was HUP'd (e.g. by sync_to_dev.sh's restart_galaxy)
    mid-run. The Python _stream_logs thread loses its stdout pipe, process.wait()
    returns prematurely (often with rc=1 or rc=-1), and the worker writes a
    bogus terminal state to timing.json — even though the actual Nextflow JVM
    survived via start_new_session=True and is still driving AWS Batch tasks.
    Recover by polling: if elapsed is short and trace shows submitted-but-not-
    terminal tasks, the run is alive.
    """
    rc = disk.get("returncode")
    if rc not in (-1, 1):
        return False
    if disk.get("status") not in ("failed", "interrupted", None):
        return False
    started = disk.get("started_at")
    completed = disk.get("completed_at")
    if started is None or completed is None:
        return False
    try:
        elapsed = float(completed) - float(started)
    except (TypeError, ValueError):
        return False
    return elapsed < 30.0


def _revive_orphan_nextflow_run(run_id: str) -> bool:
    """If the Nextflow JVM is still running, clear bogus terminal timing.json."""
    if not _find_nextflow_pids_for_run(run_id):
        return False
    _write_timing(run_id, {"completed_at": None, "status": "running", "returncode": None})
    log.warning(
        "[Nextflow run %s] revived orphan run — Nextflow JVM alive after log-stream loss",
        run_id,
    )
    return True


def _apply_disk_timing_terminal_state(info: Dict[str, Any], run_id: str) -> Dict[str, Any]:
    """Prefer timing.json terminal status/returncode over stale in-memory _runs entries."""
    disk = _read_run_timing_json(run_id)
    if not disk.get("completed_at"):
        return info
    if _looks_like_log_stream_orphan_failure(disk) and _revive_orphan_nextflow_run(run_id):
        merged = dict(info)
        merged["status"] = "running"
        merged["returncode"] = None
        merged.pop("completed_at", None)
        return merged
    merged = dict(info)
    disk_status = disk.get("status")
    disk_rc = disk.get("returncode")
    if disk_status in ("failed", "interrupted"):
        merged["status"] = disk_status
        if disk_rc is not None:
            merged["returncode"] = disk_rc
    elif disk_rc not in (0, None):
        merged["status"] = "failed"
        merged["returncode"] = disk_rc
    return merged


def _non_pipeline_info_s3_outputs(s3_output_files: Optional[list]) -> list:
    """Drop nf-core pipeline_info/ artifacts — they are written even when no tasks run."""
    kept: list = []
    for f in s3_output_files or []:
        uri = str(f.get("s3_uri", ""))
        name = str(f.get("filename", ""))
        if "/pipeline_info/" in uri or name.startswith("pipeline_info/"):
            continue
        kept.append(f)
    return kept


def _looks_like_false_success(
    *,
    log_full_text: str = "",
    log_tail: Optional[Union[list, str]] = None,
    total_steps: int = 0,
    duration_s: Optional[int] = None,
    s3_output_files: Optional[list] = None,
    workflow_domain: str = "",
    nextflow_path: str = "",
) -> bool:
    """Detect polling heuristics that would mark a quick/no-output failure as succeeded."""
    if _log_indicates_nextflow_failure(log_full_text, log_tail):
        return True
    has_outputs = bool(_non_pipeline_info_s3_outputs(s3_output_files))
    if (
        total_steps == 0
        and duration_s is not None
        and duration_s < _QUICK_FAIL_ZERO_STEPS_THRESHOLD_S
        and not has_outputs
    ):
        return True
    if _workflow_requires_s3_outputs(workflow_domain, nextflow_path) and not has_outputs:
        return True
    return False


def _looks_like_false_failure(
    *,
    log_full_text: str = "",
    log_tail: Optional[Union[list, str]] = None,
    returncode: Optional[int] = None,
    s3_output_files: Optional[list] = None,
    processes: Optional[list] = None,
) -> bool:
    """Nextflow exited non-zero but Batch tasks succeeded and real outputs were published."""
    if returncode == 0:
        return False
    has_outputs = bool(_non_pipeline_info_s3_outputs(s3_output_files))
    if not has_outputs:
        return False

    text_parts: list[str] = []
    if log_full_text:
        text_parts.append(log_full_text)
    if log_tail:
        if isinstance(log_tail, list):
            text_parts.append("\n".join(str(line) for line in log_tail))
        else:
            text_parts.append(str(log_tail))
    combined = "\n".join(text_parts)
    for marker in _NF_LOG_FAILURE_MARKERS:
        if marker in combined:
            return False
    if "No such property: meta for class" in combined:
        return False

    stats = _parse_workflow_stats_from_log(log_full_text, log_tail)
    if stats:
        succeeded, failed = stats
        if succeeded >= 1 and failed == 0:
            return True

    proc_list = processes or []
    if proc_list and all((p.get("status") or "").lower() == "completed" for p in proc_list):
        return True

    return False


def _classify_accession(value: str) -> Optional[Dict[str, str]]:
    """
    Return accession metadata if *value* is a recognised public-database accession,
    or None if it looks like a normal path/parameter value.

    Returns: {"label": str, "handler": str, "accession": str} or None.
    """
    if not isinstance(value, str):
        return None
    v = value.strip()
    if not v or len(v) < 4 or len(v) > 30:
        return None
    # Reject strings that look like file paths or URLs
    if v.startswith("/") or v.startswith("s3://") or v.startswith("http") or "." in v.split("/")[-1].split("_")[0]:
        return None
    for entry in _ACCESSION_REGISTRY:
        if entry["re"].match(v):
            return {"label": entry["label"], "handler": entry["handler"], "accession": v.upper()}
    return None


def _is_public_accession(value: str) -> bool:
    """Convenience wrapper: True if the value is a recognised public-database accession."""
    return _classify_accession(value) is not None


# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------

def _default_nf_profile() -> str:
    """Return the deployment-level Nextflow profile from env.

    Precedence:
    1. BIOMATE_NF_PROFILE env var (explicit override)
    2. 'aws' when NEXTFLOW_USE_AWS=true (all production workflows use AWS Batch)
    3. 'docker' (local development fallback)
    """
    if os.environ.get("BIOMATE_NF_PROFILE"):
        return os.environ["BIOMATE_NF_PROFILE"]
    if os.environ.get("NEXTFLOW_USE_AWS", "false").lower() in ("true", "1", "yes"):
        return "aws"
    return "docker"


class NextflowExecuteRequest(BaseModel):
    nextflow_path: str
    parameters: Optional[Dict[str, Any]] = None
    profile: Optional[str] = None  # None → resolved at execution time from BIOMATE_NF_PROFILE
    entry: Optional[str] = None
    history_id: Optional[str] = None
    compute_config: Optional[Dict[str, Any]] = None
    qc_overrides: Optional[Dict[str, Any]] = None
    qc_profile: Optional[str] = None
    workflow_domain: Optional[str] = None
    user_id: Optional[str] = None  # billing: propagated to Batch job env vars
    is_pilot: Optional[bool] = None  # pilot study: bypass billing; tag in KPI logs
    resume_from_run_id: Optional[str] = None  # if set, passes -resume -w <prev_work_dir>
    credentials: Optional[Dict[str, Any]] = None  # {tool_id: {username, token} | {license_key}}


class NextflowStatusRequest(BaseModel):
    run_id: str


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get_nextflow_bin() -> str:
    nf = os.environ.get("NEXTFLOW_BIN", "nextflow")
    # Verify it's actually on PATH
    import shutil
    resolved = shutil.which(nf)
    if resolved:
        return resolved
    raise RuntimeError(
        f"Nextflow binary '{nf}' not found on PATH. "
        "Install with: curl -s https://get.nextflow.io | bash"
    )


def _candidate_bases() -> list[Path]:
    """
    Build ordered search roots for resolving logical Nextflow paths.

    We intentionally keep DB paths relative (portable across sites) and resolve
    them here against deployment-specific roots.
    """
    roots: list[Path] = []

    env_roots = os.environ.get("NEXTFLOW_SEARCH_ROOTS", "")
    if env_roots:
        for part in env_roots.split(":"):
            part = part.strip()
            if part:
                roots.append(Path(part))

    # Common in-repo defaults (relative to this file's location).
    this_file = Path(__file__).resolve()
    backend_root = this_file.parents[5]
    roots.extend([
        backend_root,  # allows resolving paths already rooted at backend/
        backend_root / "biomni_workflows" / "nextflow_nfcore",
        backend_root / "biomni_workflows" / "nextflow_nfcore" / "subworkflows",
        backend_root / "biomni_workflows" / "nextflow_nfcore" / "workflows",
        backend_root / "nf-core-workflows",
        backend_root / "nf-core-workflows" / "modules" / "biomate-ai-tools",
        backend_root / "nf-core-modules",
        backend_root / "nf-core-modules" / "subworkflows" / "nf-core",
    ])

    # Preserve order and uniqueness.
    seen: set[str] = set()
    unique_roots: list[Path] = []
    for root in roots:
        key = str(root)
        if key not in seen:
            seen.add(key)
            unique_roots.append(root)
    return unique_roots


def _resolve_nextflow_path(raw_path: str) -> Path:
    """
    Resolve DB/logical nextflow path to an executable local .nf script.

    Supported inputs:
    - absolute path to script
    - relative path to script
    - logical IDs like:
      - nfcore/<pipeline>/main.nf
      - nfcore/subworkflows/<name>
      - biomni_nf/<domain>/<name>.nf
    """
    provided = Path(raw_path)
    if provided.is_absolute() and provided.exists():
        return provided
    if provided.exists():
        return provided.resolve()

    # Normalize logical aliases used in indexed DB rows.
    logical_candidates: list[Path] = [Path(raw_path)]

    if raw_path.startswith("nfcore/subworkflows/"):
        name = raw_path.split("nfcore/subworkflows/", 1)[1].strip("/")
        logical_candidates.extend([
            Path("subworkflows") / name / "main.nf",
            Path(name) / "main.nf",
        ])
    elif raw_path.startswith("nfcore/"):
        rest = raw_path.split("nfcore/", 1)[1].strip("/")
        logical_candidates.extend([
            Path(rest),
            Path(rest) / "main.nf",
        ])
    elif raw_path.startswith("biomni_nf/"):
        rest = raw_path.split("biomni_nf/", 1)[1].strip("/")
        logical_candidates.extend([
            Path("subworkflows") / rest,
            Path("subworkflows") / rest / "main.nf",
        ])
    elif raw_path.startswith("nextflow_nfcore/"):
        # AI sometimes returns paths prefixed with nextflow_nfcore/ — strip it and
        # search both with and without an intermediate subworkflows/ component.
        rest = raw_path.split("nextflow_nfcore/", 1)[1].strip("/")
        logical_candidates.extend([
            Path(rest),
            Path(rest) / "main.nf",
            Path("subworkflows") / rest,
            Path("subworkflows") / rest / "main.nf",
        ])

    # If DB stored path without extension, try main.nf / .nf variants.
    expanded_candidates: list[Path] = []
    for candidate in logical_candidates:
        expanded_candidates.append(candidate)
        if candidate.suffix != ".nf":
            expanded_candidates.append(candidate.with_suffix(".nf"))
            expanded_candidates.append(candidate / "main.nf")

    # Search all candidates under configured roots.
    for root in _candidate_bases():
        for candidate in expanded_candidates:
            test_path = (root / candidate).resolve()
            if test_path.exists() and test_path.is_file() and test_path.suffix == ".nf":
                return test_path

    # Domain alias fallback: drug_discovery ↔ pharmacology subworkflows are
    # often identical. If the primary search failed, retry with the sibling domain.
    _DOMAIN_ALIASES: dict[str, str] = {
        "drug_discovery": "pharmacology",
        "pharmacology": "drug_discovery",
    }
    alias_candidates: list[Path] = []
    for candidate in expanded_candidates:
        parts = candidate.parts
        for i, part in enumerate(parts):
            if part in _DOMAIN_ALIASES:
                aliased = Path(*parts[:i]) / _DOMAIN_ALIASES[part] / Path(*parts[i + 1:])
                alias_candidates.append(aliased)
                break

    for root in _candidate_bases():
        for candidate in alias_candidates:
            test_path = (root / candidate).resolve()
            if test_path.exists() and test_path.is_file() and test_path.suffix == ".nf":
                return test_path

    raise FileNotFoundError(
        f"Could not resolve Nextflow script '{raw_path}'. "
        f"Set NEXTFLOW_SEARCH_ROOTS to include your workflow roots."
    )


def _detect_nextflow_entry(nf_path: Path) -> Optional[str]:
    """
    Detect entry workflow name for scripts that define only named workflows.

    If an anonymous `workflow { ... }` exists, Nextflow can use default entry and
    no explicit `-entry` is needed.
    """
    try:
        text = nf_path.read_text(errors="replace")
    except OSError:
        return None

    # Anonymous workflow block exists; default entry is available.
    if re.search(r"(?m)^\s*workflow\s*\{", text):
        return None

    named_entries = re.findall(r"(?m)^\s*workflow\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{", text)
    if not named_entries:
        return None

    preferred = [name for name in named_entries if name.lower() in ("main", "run", "workflow")]
    return preferred[0] if preferred else named_entries[0]


def _extract_documented_images() -> list[str]:
    """
    Extract workflow container images from local BioMate docs.
    This keeps runtime image selection aligned with documented, previously built images.
    """
    docs = [
        Path(__file__).resolve().parents[5] / "20260119_1538_DOCKER_CONTAINER_ROUTING_APPROACH.md",
        Path(__file__).resolve().parents[5] / "20260116_BIOMNI_DOCKER_TEST_RESULTS.md",
        Path(__file__).resolve().parents[5] / "biomni_workflows" / "galaxy" / "docker" / "20251203_DOCKER_TOOL_EXECUTION_GUIDE.md",
        Path(__file__).resolve().parents[5] / "biomni_workflows" / "20251204_NEXTFLOW_DOCKER_CONFIGURATION.md",
    ]
    image_pattern = re.compile(r"(biomate/[a-zA-Z0-9._-]+(?::[a-zA-Z0-9._-]+)?)")
    images: list[str] = []
    for doc in docs:
        if not doc.exists():
            continue
        try:
            text = doc.read_text(errors="replace")
        except OSError:
            continue
        for match in image_pattern.findall(text):
            if match not in images:
                images.append(match)
    return images


def _is_local_docker_image(image: str) -> bool:
    """Return True if Docker image exists locally."""
    try:
        result = subprocess.run(
            ["docker", "image", "inspect", image],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=10,
        )
        return result.returncode == 0
    except Exception:
        return False


def _host_arch() -> str:
    """Return normalized host architecture: arm64 | amd64 | unknown."""
    machine = os.uname().machine.lower()
    if machine in ("aarch64", "arm64"):
        return "arm64"
    if machine in ("x86_64", "amd64"):
        return "amd64"
    return "unknown"


def _image_declared_arch(image: str) -> str:
    """
    Best-effort arch hint from image tag naming convention.
    Returns: arm64 | amd64 | unknown
    """
    image_l = image.lower()
    if ":arm64" in image_l or "-arm64" in image_l:
        return "arm64"
    if ":x86" in image_l or ":amd64" in image_l or "-x86" in image_l or "-amd64" in image_l:
        return "amd64"
    return "unknown"


def _image_runtime_arch(image: str) -> str:
    """Inspect local image architecture via Docker metadata."""
    try:
        result = subprocess.run(
            ["docker", "image", "inspect", "--format", "{{.Architecture}}", image],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return "unknown"
        arch = result.stdout.strip().lower()
        if arch in ("arm64", "aarch64"):
            return "arm64"
        if arch in ("amd64", "x86_64"):
            return "amd64"
        return "unknown"
    except Exception:
        return "unknown"


def _is_image_arch_compatible(image: str) -> tuple[bool, str, str]:
    """
    Returns (compatible, host_arch, image_arch).
    By default cross-arch is disabled; enable with NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER=true.
    """
    host_arch = _host_arch()
    image_arch = _image_runtime_arch(image)
    if image_arch == "unknown":
        image_arch = _image_declared_arch(image)

    allow_cross = os.environ.get("NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER", "false").lower() in ("1", "true", "yes")
    if allow_cross:
        return True, host_arch, image_arch
    if host_arch == "unknown" or image_arch == "unknown":
        return True, host_arch, image_arch
    return host_arch == image_arch, host_arch, image_arch


def _extract_python_imports(nf_path: Path) -> list[str]:
    """
    Best-effort extraction of Python imports embedded in Nextflow scripts.
    """
    try:
        text = nf_path.read_text(errors="replace")
    except OSError:
        return []

    imports: set[str] = set()
    # Only extract TOP-LEVEL (zero-indent) imports — these are always required.
    # Indented imports (inside try/except, if blocks, functions) are conditional/optional
    # and must NOT be treated as hard requirements (e.g. DeepPurpose inside a try block).
    for mod in re.findall(r"^import\s+([a-zA-Z_][a-zA-Z0-9_\.]*)", text, flags=re.MULTILINE):
        imports.add(mod.split(".")[0])
    for mod in re.findall(r"^from\s+([a-zA-Z_][a-zA-Z0-9_\.]*)\s+import", text, flags=re.MULTILINE):
        imports.add(mod.split(".")[0])

    stdlib = {
        "os", "sys", "re", "json", "math", "time", "datetime", "pathlib", "typing",
        "collections", "itertools", "functools", "subprocess", "logging", "argparse",
        "csv", "gzip", "shutil", "glob",
    }
    return sorted([m for m in imports if m not in stdlib])


def _docker_has_python_modules(image: str, modules: list[str]) -> bool:
    """Check whether image has all required Python modules."""
    if not modules:
        return True
    script = "; ".join([f"import {m}" for m in modules])
    cmd = ["docker", "run", "--rm", "--entrypoint", "python", image, "-c", script]
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=30,
        )
        return result.returncode == 0
    except Exception:
        return False


def _host_has_python_modules(modules: list[str]) -> tuple[bool, list[str]]:
    """Return (all_present, missing_modules) for host Python runtime."""
    missing: list[str] = []
    for mod in modules:
        try:
            __import__(mod)
        except Exception:
            missing.append(mod)
    return len(missing) == 0, missing


def _auto_install_host_modules(modules: list[str]) -> list[str]:
    """Attempt pip install for missing modules. Returns modules still missing."""
    if not modules:
        return []
    still_missing: list[str] = []
    for mod in modules:
        pkg = mod
        try:
            result = subprocess.run(
                ["python", "-m", "pip", "install", pkg],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=120,
            )
            if result.returncode != 0:
                still_missing.append(mod)
                continue
            try:
                __import__(mod)
            except Exception:
                still_missing.append(mod)
        except Exception:
            still_missing.append(mod)
    return still_missing


def _check_pipeline_constraints(
    nf_path: Path, params: dict, compute: dict
) -> Optional[Dict[str, Any]]:
    """
    Pre-flight check: detect pipelines that cannot run on this host and explain why.
    Returns None if OK to proceed, or a dict with blocking details.

    Currently detects:
      - CryoSPARC pipelines running with mock_mode=false on ARM64 without AWS Batch
    """
    executor = compute.get("executor", "local")
    if executor == "awsbatch":
        # Mock mode is never permitted on real cloud hardware — simulations waste
        # EC2 compute time and billing without producing real scientific data.
        if params.get("mock_mode", False):
            log.warning(
                "[Nextflow] mock_mode=true override: forcing mock_mode=false for "
                "awsbatch executor — real container images will run on Batch."
            )
            params["mock_mode"] = False
        return None  # skip local constraint checks for cloud executor

    if executor != "local":
        # Other non-local executors (slurm, etc.); skip local constraint checks.
        return None

    host_arch = _host_arch()
    if host_arch == "amd64":
        return None  # x86_64 host can run anything

    try:
        text = nf_path.read_text(errors="replace")
    except OSError:
        return None

    # Detect CryoSPARC pipelines
    is_cryosparc = (
        "use_cryosparc" in text
        or "cryosparc" in nf_path.as_posix().lower()
    )
    if not is_cryosparc:
        return None

    # Determine effective mock_mode
    # Priority: explicit param > pipeline default
    mock_from_params = params.get("mock_mode", None)
    if mock_from_params is not None:
        will_mock = bool(mock_from_params)
    else:
        # Check pipeline default: `params.mock_mode = true|false`
        m = re.search(r"params\.mock_mode\s*=\s*(true|false)", text, re.IGNORECASE)
        will_mock = (m is None) or (m.group(1).lower() == "true")

    if will_mock:
        return None  # mock_mode=true runs pure Python; ARM is fine

    return {
        "blocked": True,
        "reason": (
            f"CryoSPARC requires x86_64 hardware (this host is {host_arch}). "
            "CryoSPARC binaries and Docker images are not available for ARM."
        ),
        "suggestion": (
            "Option A: pass mock_mode=true to run the full pipeline with synthetic data.\n"
            "Option B: configure AWS Batch in Settings → Compute to run on x86_64 cloud."
        ),
        "mock_mode_available": True,
    }


_INPUT_SIZE_LIMIT_BYTES = 10 * 1024 ** 3  # 10 GB


def _is_path_param(key: str, value: Any) -> bool:
    """Heuristic: is this param likely a local file or directory path?"""
    if not isinstance(value, str):
        return False
    path_keywords = (
        "path", "input", "reads", "file", "dir", "movies", "sample",
        "samplesheet", "fasta", "fastq", "bam", "csv", "tsv", "mrc",
        "tif", "tiff", "mdoc", "ref", "genome",
    )
    # Known non-path params that happen to contain path-like substrings
    _NON_PATH_KEYS = frozenset({
        "publish_dir_mode", "save_merged_fastq", "publish_dir",
        "outdir_mode", "output_mode", "copy_mode", "dir_mode",
        "output_dir",  # Nextflow task-relative scratch dir; not validated on API server disk
        "sample_id", "sample_name", "genome_build", "genome_name",
        # CryoSPARC remote paths — exist on EC2 instance, not local disk
        "cryosparc_project_dir", "cryosparc_host", "cryosparc_email",
        "cryosparc_password", "cryosparc_license", "cryosparc_lane",
        "movies_path",          # staged to remote CryoSPARC EC2 instance; not on head node
        "particle_star_file",   # lives on CryoSPARC EC2 instance
        "particle_blob_path",   # lives on CryoSPARC EC2 instance
        "movie_batch_dirs",     # JSON string of per-batch dir info (not a local path)
    })
    key_l = key.lower()
    if key_l in _NON_PATH_KEYS:
        return False
    val = value.strip()
    # Skip empty strings, booleans, numbers, mode strings, URLs already handled separately
    if not val or val.lower() in ("true", "false", "null", "none", "copy", "symlink", "move", "link"):
        return False
    if val.startswith("s3://") or val.startswith("http"):
        return False
    # Inline data (CSV, TSV, multi-line text) always contains newlines — never a path.
    if "\n" in val or "\r" in val:
        return False
    # Exclude chemistry/biology data strings that can't be filesystem paths.
    # SMILES, InChI, FASTA sequences, and compound IDs contain characters
    # that are illegal or highly unusual in file/directory names.
    _NON_PATH_CHARS = frozenset("()=#+@[]\\|~`'\"")
    if any(c in val for c in _NON_PATH_CHARS):
        return False
    # Long strings that don't look like paths (no slashes, no extension) are data.
    if len(val) > 100 and "/" not in val and "." not in val:
        return False
    # Short genome/reference identifiers (e.g. hg38, GRCh38, mm10, hg19) are NOT file paths.
    # They map to iGenomes S3 references; real paths would contain '/' or a file extension.
    _GENOME_ID_KEYS = frozenset({"genome", "reference_genome", "ref_genome", "genome_id", "assembly"})
    if key_l in _GENOME_ID_KEYS and "/" not in val and "." not in val:
        return False
    # Value must either start with '/' (absolute path) or contain a '/' (relative path),
    # OR have a recognized file extension — otherwise it's likely an identifier, not a path.
    _PATH_EXTENSIONS = frozenset({
        ".fasta", ".fa", ".fastq", ".fq", ".bam", ".sam", ".cram",
        ".vcf", ".bcf", ".bed", ".gtf", ".gff", ".gff3", ".csv",
        ".tsv", ".txt", ".mrc", ".tif", ".tiff", ".mdoc", ".json",
        ".gz", ".tar", ".zip",
    })
    looks_like_path = val.startswith("/") or "/" in val or any(val.lower().endswith(ext) for ext in _PATH_EXTENSIONS)
    # Key name must suggest a path AND value must look like a path
    return (any(kw in key_l for kw in path_keywords) and looks_like_path) or val.startswith("/")


def _local_path_size(p: Path) -> int:
    """Return total size in bytes of a file or directory tree."""
    if p.is_file():
        return p.stat().st_size
    total = 0
    for child in p.rglob("*"):
        if child.is_file():
            try:
                total += child.stat().st_size
            except OSError:
                pass
    return total


def _validate_input_paths(params: dict) -> None:
    """
    Validate all input path parameters before launching Nextflow.

    Checks:
    1. Every local path param exists (file or directory).
    2. Total local input size does not exceed 10 GB.
    3. Every S3 input path is accessible (bucket reachable + object exists).

    Raises HTTPException(422) on any violation.
    """
    missing: list[str] = []
    total_bytes = 0
    large_items: list[str] = []

    for key, value in params.items():
        if key == "outdir":
            continue  # output, not input — validated elsewhere
        if isinstance(value, str) and value.startswith("s3://"):
            # Pre-flight: validate S3 input is accessible before job starts.
            _validate_s3_url(value, check_object=True)
            continue
        # Skip public-database accessions — they will be resolved by a pre-step
        # download handler (_accession_chain_thread) before the main workflow runs.
        if _is_public_accession(str(value)):
            continue
        if not _is_path_param(key, value):
            continue

        p = Path(value)
        if not p.exists():
            missing.append(f"--{key} '{value}': path does not exist")
            continue

        size = _local_path_size(p)
        total_bytes += size
        if size > _INPUT_SIZE_LIMIT_BYTES:
            gb = size / 1024 ** 3
            large_items.append(f"--{key} '{value}' ({gb:.1f} GB)")

    if missing:
        raise HTTPException(
            status_code=422,
            detail={
                "error": "Input path(s) not found",
                "missing": missing,
                "suggestion": "Check that all --input / --reads / --movies_path values exist on disk.",
            },
        )

    if total_bytes > _INPUT_SIZE_LIMIT_BYTES:
        total_gb = total_bytes / 1024 ** 3
        raise HTTPException(
            status_code=422,
            detail={
                "error": "Input data exceeds the 10 GB per-run limit",
                "total_gb": round(total_gb, 2),
                "limit_gb": 10,
                "large_inputs": large_items or ["(combined total)"],
                "suggestion": (
                    "Split your data into batches of ≤ 10 GB, or stage large inputs "
                    "directly to S3 and pass an s3:// path instead."
                ),
            },
        )


def _validate_epitope_netmhc_params(nf_path: Path, params: dict) -> None:
    """Reject epitopeprediction runs that enable NetMHC tools without licensed tarballs."""
    path_low = str(nf_path).lower()
    if "epitopeprediction" not in path_low and "epitope_prediction" not in path_low:
        return
    tools_raw = str(params.get("tools") or "")
    tool_list = [t.strip().lower() for t in tools_raw.replace(" ", "").split(",") if t.strip()]
    missing: list[str] = []
    if "netmhcpan" in tool_list and not params.get("netmhcpan_path"):
        missing.append("netmhcpan_path")
    if "netmhciipan" in tool_list and not params.get("netmhciipan_path"):
        missing.append("netmhciipan_path")
    if not missing:
        return
    raise HTTPException(
        status_code=422,
        detail={
            "error": "NetMHC software path required",
            "missing": missing,
            "suggestion": (
                "Pass --netmhcpan_path (and/or --netmhciipan_path) as an s3:// URI to the "
                "DTU-licensed tarball. For Plan A science sprint: "
                "python3 research/anti-virus/science_sprint/track_plan_a_multitool.py "
                "--netmhcpan-path s3://biomate-nextflow-work/inputs/andv_campaign/netmhcpan/netMHCpan-4.1b.Linux.tar.gz"
            ),
        },
    )


def _validate_s3_url(s3_url: str, check_object: bool = False) -> None:
    """
    Validate an s3:// URL is accessible before launching Nextflow.

    Args:
        s3_url:       Must start with 's3://'.
        check_object: If True and the URL has a key component, verify the
                      object exists with head_object (used for input files).
                      Skipped for bucket-only or directory-prefix URLs.

    Raises HTTPException(422) with a human-readable reason if not.
    """
    try:
        import boto3
        from botocore.exceptions import ClientError, NoCredentialsError
    except ImportError:
        log.warning("[Nextflow] boto3 not installed — skipping S3 validation")
        return

    parts = s3_url[len("s3://"):].split("/", 1)
    bucket = parts[0]
    key = parts[1] if len(parts) > 1 else ""
    if not bucket:
        raise HTTPException(
            status_code=422,
            detail={"error": f"Invalid S3 URL '{s3_url}': no bucket name"},
        )

    # Well-known public reference buckets — always accessible, skip pre-flight check
    # to avoid cross-region head_bucket 400 errors.
    _PUBLIC_REF_BUCKETS = frozenset({
        "ngi-igenomes",       # nf-core iGenomes (eu-west-1, requester-pays)
        "broad-references",   # Broad GATK bundle
        "gatk-sv-resources-public",
        "aws-genomics-datasets",
    })
    if bucket in _PUBLIC_REF_BUCKETS:
        # Trust known-good public buckets; validate object existence below if needed.
        pass
    else:
        s3 = boto3.client("s3", region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
        try:
            s3.head_bucket(Bucket=bucket)
        except NoCredentialsError:
            raise HTTPException(
                status_code=422,
                detail={
                    "error": "AWS credentials not configured",
                    "bucket": bucket,
                    "suggestion": (
                        "Run 'aws configure' or set the AWS_ACCESS_KEY_ID / "
                        "AWS_SECRET_ACCESS_KEY environment variables."
                    ),
                },
            )
        except ClientError as exc:
            code = exc.response.get("Error", {}).get("Code", "")
            if code in ("403", "AccessDenied"):
                raise HTTPException(
                    status_code=422,
                    detail={
                        "error": f"Access denied to S3 bucket '{bucket}'",
                        "bucket": bucket,
                        "suggestion": (
                            "Ensure the IAM role/user has s3:GetObject, "
                            "s3:PutObject, and s3:ListBucket on this bucket."
                        ),
                    },
                )
            if code in ("404", "NoSuchBucket"):
                raise HTTPException(
                    status_code=422,
                    detail={
                        "error": f"S3 bucket '{bucket}' does not exist",
                        "bucket": bucket,
                        "suggestion": f"Create it with: aws s3 mb s3://{bucket} --region <region>",
                    },
                )
            # 301/400 = cross-region redirect — bucket exists in another region, treat as OK.
            http_status = exc.response.get("ResponseMetadata", {}).get("HTTPStatusCode", 0)
            if http_status in (301, 400):
                log.info("[S3Validate] Bucket '%s' in different region (HTTP %s) — skipping validation", bucket, http_status)
            else:
                raise HTTPException(
                    status_code=422,
                    detail={
                        "error": f"Cannot access S3 bucket '{bucket}': {exc}",
                        "bucket": bucket,
                    },
                )

    # Optional: verify the specific object exists (for input file paths).
    # Skip for directory-style prefixes (key ends with '/') or bucket-only URLs.
    # Also skip head_object for glob patterns — use list_objects_v2 instead.
    _is_glob_key = any(c in key for c in ("*", "?", "[", "]"))
    if check_object and key and not key.endswith("/") and not _is_glob_key:
        try:
            s3.head_object(Bucket=bucket, Key=key)
        except ClientError as exc:
            code = exc.response.get("Error", {}).get("Code", "")
            if code in ("404", "NoSuchKey"):
                raise HTTPException(
                    status_code=422,
                    detail={
                        "error": f"S3 input object not found: s3://{bucket}/{key}",
                        "bucket": bucket,
                        "key": key,
                        "suggestion": (
                            "Upload your input file first, or check the S3 path for typos. "
                            f"List available files with: aws s3 ls s3://{bucket}/{'/'.join(key.split('/')[:-1])}/"
                        ),
                    },
                )
            # Access denied on object but bucket was reachable — different IAM policy.
            if code in ("403", "AccessDenied"):
                raise HTTPException(
                    status_code=422,
                    detail={
                        "error": f"Access denied to S3 object s3://{bucket}/{key}",
                        "suggestion": "Ensure the IAM role has s3:GetObject on this key.",
                    },
                )


def _generate_executor_config(
    compute: dict, config_dir: Path, *, user_id: str = "unknown", run_id: str = "unknown",
    credentials: Optional[Dict[str, Any]] = None, nf_path: str = "",
) -> Optional[Path]:
    """
    Generate a temporary nextflow.config for non-local executors.

    Nextflow reads executor from nextflow.config, NOT from environment variables.
    NXF_EXECUTOR is not a real Nextflow env var — this function replaces the
    previous (broken) NXF_EXECUTOR approach.

    Returns path to generated config file, or None for local execution.
    """
    executor = compute.get("executor", "local")
    if executor not in ("awsbatch", "slurm"):
        return None

    config_path = config_dir / "biomate_executor_override.config"

    if executor == "awsbatch":
        queue = (
            compute.get("aws_batch_queue")
            or os.environ.get("AWS_BATCH_QUEUE", "biomate-nextflow-queue")
        )
        region = (
            compute.get("aws_region")
            or os.environ.get("AWS_DEFAULT_REGION", "us-west-2")
        )
        s3_bucket = (
            compute.get("s3_bucket")
            or os.environ.get("NEXTFLOW_S3_BUCKET", "biomate-nextflow-work")
        )
        # Container for tasks. MUST have both Python 3 and the AWS CLI.
        # Nextflow injects an nxf_s3_upload() shell function into every task's
        # .command.run that calls `aws s3 cp` — if the container lacks the aws
        # binary, the task exits with code 127 immediately.
        # civitaspo/python-awscli:latest = Python 3 + AWS CLI v2 (verified working).
        container = compute.get("container") or os.environ.get(
            "NEXTFLOW_BATCH_CONTAINER", "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest"
        )

        # Plugin pin per workload:
        #   - BioMate workflows: nf-amazon@3.3.0 (last pre-CRT, prevents the
        #     JVM SIGSEGV from publishDir-triggered S3TransferManager init).
        #   - nf-core: nf-amazon@3.4.4 — 3.3.0 has an unfixed multipart bug
        #     ("list of parts was not in ascending order") that fires on every
        #     staging upload. 3.4.4+ has it fixed. We don't inject
        #     publishDir=null for nf-core, so the CRT crash path stays cold.
        nfamazon_version = "3.4.4" if "/nf-core-workflows/" in nf_path else "3.3.0"
        lines = [
            "plugins {",
            f"    id 'nf-amazon@{nfamazon_version}'",
            "}",
            # Override params.container so workflow configs that do
            # `process { container = params.container }` use the ECR image.
            # Override params.outdir so publishDir uses S3 — without this,
            # workflows default to ./results (container-local disk) and
            # s3_output_files stays empty after the run.
            #
            # Skip params.container for nf-core: their utils_nfschema_plugin
            # validates params types against nextflow_schema.json, where
            # `container` is typed as a Map [name:..., engine:...] in newer
            # pipelines. Injecting a String raises:
            #   Cannot cast object '...' with class String to class Map
            # Reproduced 2026-06-07 on nfcore/abotyper, nfcore/createtaxdb.
            "params {",
            *( [f"    container = '{container}'"] if "/nf-core-workflows/" not in nf_path else [] ),
            f"    outdir = 's3://{s3_bucket}/nextflow/outputs/{user_id}/{run_id}'",
            "}",
            # DISABLE publishDir entirely on the head JVM. publishDir is what
            # spawns S3 TransferManager which constructs S3CrtAsyncClient
            # which loads the AWS CRT native lib. That lib's dlopen randomly
            # SIGSEGVs the JVM via:
            #   software.amazon.awssdk.crt.CRT.extractAndLoadLibrary
            #   → System.load → ld-linux dlopen → SIGSEGV
            # Empirically reproduced on:
            #   - JDK 21 + Debian trixie (glibc 2.41) — +0x2475a
            #   - JDK 17 + Debian bookworm (glibc 2.36) — +0x224ba
            #   - nf-amazon 3.3.0 AND 3.4.4 — both load CRT
            # The bug is in AWS CRT native lib, not OS/JDK.
            # All output files stay in work/<task-hash>/ on S3 (placed there
            # by Batch task's own `aws s3 cp` — no CRT). Galaxy already reads
            # work/ via the `run:<runId>:datasets` URI handler in
            # routes.ts:2898 — no CRT path on Galaxy side either.
            # Tradeoff: outputs/ S3 dir won't be populated, but the
            # `nextflowOutputDir` field in run state still points at it for
            # future fix that does a Galaxy-side post-task `aws s3 sync`.
            # When that lands, the head JVM continues to never touch S3 for
            # bulk transfer.
            # `process { publishDir = null }` was belt-and-suspenders against the
            # CRT crash; nf-amazon@3.3.0 pin above already prevents CRT load.
            # For nf-core 25+ pipelines this directive breaks: newer nf-core
            # uses `workflow.output.mode = params.publish_dir_mode` syntax
            # which compares ConfigObject `[:]` against publishDir's effective
            # value and crashes with:
            #   Cannot compare groovy.util.ConfigObject [:] with Integer 0
            # Reproduced 2026-06-07 on nfcore/airrflow 5.1.0.
            *(
                ["process {", "    publishDir = null", "}"]
                if "/nf-core-workflows/" not in nf_path
                else []
            ),
            "process {",
            "    executor = 'awsbatch'",
        ]
        if queue:
            lines.append(f"    queue = '{queue}'")
        # Build environment block — billing context + optional credentials
        creds = credentials or {}
        env_lines = [
            f"        BIOMATE_USER_ID: '{user_id}',",
            f"        BIOMATE_RUN_ID: '{run_id}',",
        ]
        # beforeScript parts — credential injection only.
        before_script_parts: list[str] = []

        # Docker Hub auth (AlphaFold3 or any docker_auth tool)
        af3_cred = creds.get("alphafold3") or {}
        if af3_cred.get("username") and af3_cred.get("token"):
            import base64 as _b64
            auth_b64 = _b64.b64encode(
                f"{af3_cred['username']}:{af3_cred['token']}".encode()
            ).decode()
            env_lines.append(f"        DOCKER_HUB_AUTH_B64: '{auth_b64}',")
            before_script_parts.append(
                r"mkdir -p $HOME/.docker && "
                r'printf \'{"auths":{"https://index.docker.io/v1/":{"auth":"%s"}}}\' '
                r'"$DOCKER_HUB_AUTH_B64" > $HOME/.docker/config.json'
            )
            log.info("[Nextflow] AlphaFold3 Docker auth will be injected into Batch tasks")

        # CryoSPARC license key
        cs_cred = creds.get("cryosparc") or {}
        if cs_cred.get("license_key"):
            env_lines.append(f"        CRYOSPARC_LICENSE_ID: '{cs_cred['license_key']}',")
            log.info("[Nextflow] CryoSPARC license key will be injected into Batch tasks")

        before_script_str = " && ".join(before_script_parts) if before_script_parts else ""

        # Only force our default container for BioMate's custom workflows.
        # nf-core pipelines declare container per-process (often as a Map under
        # newer schemas like `container = [name:..., engine:...]`), and injecting
        # a String here clashes with their Map-typed config:
        #   "Cannot cast object 'ECR_URI' with class 'String' to class 'Map'"
        # Symptom hit by nfcore/abotyper, nfcore/createtaxdb on NF 25.10
        # post-pull (2026-06-07). Skip the directive for nfcore + bioconductor.
        is_nfcore_or_bioc = "/nf-core-workflows/" in nf_path or "/bioconductor/" in nf_path
        lines += [
            *( [f"    container = '{container}'"] if not is_nfcore_or_bioc else [] ),
            # Inject billing context + credentials into every Batch task container.
            "    environment = [",
        ] + env_lines + [
            "    ]",
        ]
        if before_script_str:
            lines.append(f"    beforeScript = '{before_script_str}'")
        # Host-mounted AWS CLI (aws.batch.cliPath) must resolve zlib before Nextflow's
        # S3 staging runs. process.environment and beforeScript are applied too late;
        # ECS `docker run -e` via containerOptions is not.
        _ld_aws_host = (
            "/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:"
            "/lib/aarch64-linux-gnu:/usr/lib/aarch64-linux-gnu:"
            "/lib64:/usr/lib64:/usr/lib:/lib:"
            "/opt/conda/lib:/opt/conda/x86_64-conda-linux-gnu/lib:"
            "/usr/local/lib"
        )
        # For nf-core paths: nf-core uses minimal biocontainers without libz,
        # and the host-mounted /opt/aws-cli/bin/aws is dynamically linked
        # against libz on the AMI side. Single-file mount of libz into the
        # container side-steps the bigger glibc-symbol-mismatch risk of
        # mounting all of /usr/lib. Pairs with the Batch AMI fix in
        # docs/20260607_BATCH_AMI_AWSCLI_NOT_SELF_CONTAINED.md (the true
        # fix is rebuilding the AMI with a self-contained aws-cli; this
        # is the temporary workaround so nf-core test runs work today).
        if "/nf-core-workflows/" in nf_path:
            # AL2023 Batch host is RHEL-family: libs live in /usr/lib64.
            # Mount into BOTH /lib/x86_64-linux-gnu/ AND /usr/lib64/ inside
            # the container so glibc-style and RHEL-style search paths both
            # resolve libz.so.1.
            _container_opts = (
                "-v /usr/lib64/libz.so.1:/usr/lib/x86_64-linux-gnu/libz.so.1:ro "
                "-v /usr/lib64/libz.so.1:/usr/lib64/libz.so.1:ro "
                f"-e LD_LIBRARY_PATH={_ld_aws_host}"
            )
        else:
            _container_opts = f"-e LD_LIBRARY_PATH={_ld_aws_host}"
        lines.append(f"    containerOptions = '{_container_opts}'")
        lines.append("}")
        # Per-label GPU queue routing: processes labeled 'process_gpu' go to the GPU queue.
        # Avoids a single monolithic queue for all workflows.
        # IMPORTANT — a sensible default is required. Without it, every GPU-labelled
        # process (cpa_synergy_gpu, gears_perturbation_gpu, transcriptformer_gpu, etc.)
        # inherits the CPU queue 'biomate-nextflow-queue', sits in RUNNABLE forever
        # because the CPU CE has no GPU instance types, and (per AWS Batch FIFO) blocks
        # CPU jobs queued behind it from getting scheduled. Observed 2026-06-04 with
        # 12 stuck jobs (10 GPU, 2 CPU) backing up the queue for hours.
        gpu_queue = (
            compute.get("gpu_batch_queue")
            or os.environ.get("GPU_BATCH_QUEUE", "")
            or "biomate-gpu-spot-queue"
        )
        if gpu_queue:
            lines += [
                "process {",
                "    withLabel: 'process_gpu' {",
                f"        queue = '{gpu_queue}'",
                "        accelerator = 1",
                # Ensure GPU processes get adequate resources — 8 vCPU / 32 GB is the
                # standard GPU node allocation. These override any global defaults that
                # might otherwise default to 1 vCPU / 1 GB on EC2 Batch environments.
                "        cpus = 8",
                "        memory = '32.GB'",
                "    }",
                "    withName: 'PRODUCTION_MD' {",
                f"        queue = '{gpu_queue}'",
                "        accelerator = 1",
                "        cpus = 8",
                "        memory = '32.GB'",
                "    }",
                "}",
            ]
            log.info(f"[Nextflow] GPU queue routing: process_gpu → {gpu_queue}")
        # For nf-core pipelines: emit a slimmer aws.client block.
        # Their own nextflow.config often sets `aws.client.anonymous = true`
        # globally (so iGenomes public-bucket reads work). That makes ALL
        # S3 ops anonymous, including PUTs to our private workDir → 403.
        # We force `anonymous = false` to win over theirs (NF applies our
        # -c override after their nextflow.config). Their pipeline-specific
        # tuning (maxConnections etc.) is left alone for nfcore.
        # Reproduced 2026-06-07 on bamtofastq 2.2.1 with igenomes_ignore=true.
        is_nfcore = "/nf-core-workflows/" in nf_path
        lines += [
            f"aws {{",
            f"    region = '{region}'",
            "    client {",
            "        maxConnections = 20",
            # nf-amazon@3.3.0 has a bug where multipart upload parts can be
            # submitted out of order → CompleteMultipartUpload fails with
            # "list of parts was not in ascending order". Newer versions
            # fix it but pull in CRT (which crashes our JDK). Workaround:
            # tune chunk size per workload to favour single-part uploads:
            #   - BioMate workflows: 100 MB (production outputs are GB-scale,
            #     so multipart is mandatory anyway and the bug is rare).
            #   - nf-core: 50 MB (test fixtures are typically a few MB → fit
            #     in single-part; full runs use multipart but still ordered
            #     since fewer parts).
            *(
                ["        uploadChunkSize = 52428800"]  # 50 MB
                if is_nfcore
                else ["        uploadChunkSize = 104857600"]  # 100 MB
            ),
            # For nf-core: force anonymous=false so it wins over their
            # iGenomes-anonymous setting (pipelines like bamtofastq set it
            # globally, breaking workDir PUTs).
            *(["        anonymous = false"] if is_nfcore else []),
            "    }",
            "    batch {",
            # AMI ami-08fe495be97a3dbf4 (biomate-nextflow-al2023-awscli-20260409):
            #   Base: ami-0b495ea217b3a1543 (ECS-optimized AL2023, kernel 6.1, 2026-04-03)
            #   Baked in: AWS CLI v2 at /usr/local/bin/aws + symlink /opt/aws-cli/bin/aws
            # cliPath = /opt/aws-cli/bin/aws:
            #   Nextflow mounts grandparent /opt/aws-cli (host→container) — safe, does NOT
            #   shadow /usr/local or /usr/bin. Works for BOTH ECR (BioMate) containers AND
            #   public third-party containers (gromacs, rocker, etc.) without aws of their own.
            # DO NOT change to /usr/local/bin/aws — that shadows /usr/local/lib/python3
            #   site-packages inside containers, causing exit 127 on all python tasks.
            # cliPath auto-mounts /opt/aws-cli (grandparent) host→container; no explicit
            # volumes needed — adding volumes=['/opt/aws-cli'] would duplicate the mount
            # and cause "containerPath values aren't unique across mountPoints" on AWS Batch.
            "        cliPath = '/opt/aws-cli/bin/aws'",
            # For nf-core: their task containers are minimal biocontainers
            # (perl, gtf2bed, etc.) lacking libz/libcrypto/libssl. The Batch
            # AMI's /opt/aws-cli/bin/aws is dynamically linked against
            # system libs at /usr/lib64. Mount /usr/lib64 read-only into the
            # container so the dynamic loader finds them via the existing
            # LD_LIBRARY_PATH (/lib64:/usr/lib64).
            # NB: Batch ignores `-v` flags in containerOptions; only the
            # `volumes` directive (which translates to Batch mountPoints)
            # has effect. See AWS Batch ContainerProperties docs.
            #
            # Mount ONLY the specific libz file — mounting all of /usr/lib64
            # caused glibc symbol mismatches (host libtinfo built against
            # GLIBC_2.33+ overrode container's older libc). Verified 2026-06-08
            # on nfcore/chipseq: with libz-only mount, GTF2BED passes (libz
            # error gone) and the run moves to next process. With full
            # /usr/lib64 mount, /bin/sh itself fails on tinfo glibc.
            *(
                ["        volumes = ['/usr/lib64/libz.so.1:/usr/lib64/libz.so.1:ro']"]
                if is_nfcore
                else []
            ),
            "    }",
            "}",
            "docker.enabled = true",
            f"workDir = 's3://{s3_bucket}/nextflow/work/{user_id}/{run_id}'",
            # Empty profiles.aws so -profile aws validates for workflows without their own
            # nextflow.config (real Batch settings are top-level above).
            "profiles {",
            "    aws {",
            "        // intentionally empty — real settings are top-level",
            "    }",
            "}",
        ]

        if not queue:
            log.warning(
                "[Nextflow] AWS Batch executor: no queue name. "
                "Set AWS_BATCH_QUEUE env var or compute_config.aws_batch_queue."
            )

    elif executor == "slurm":
        partition = compute.get("slurm_partition") or "compute"
        qos = compute.get("slurm_qos") or ""
        cluster_opts = f"--partition={partition}"
        if qos:
            cluster_opts += f" --qos={qos}"

        lines = [
            "process {",
            "    executor = 'slurm'",
            f"    clusterOptions = '{cluster_opts}'",
            "}",
        ]

    config_path.write_text("\n".join(lines) + "\n")
    log.info(f"[Nextflow] Generated executor config: {config_path}")
    return config_path


def _choose_container_strategy(nf_path: Path, raw_nextflow_path: str) -> Dict[str, Any]:
    """
    Choose execution strategy:
      1) Prefer documented local Docker images that satisfy module requirements.
      2) Fallback to host mode with automatic module installation.
    """
    required_modules = _extract_python_imports(nf_path)
    documented_images = _extract_documented_images()

    # Domain-aware preference order
    image_preferences: list[str] = []
    if raw_nextflow_path.startswith("biomni_nf/"):
        image_preferences.extend(["biomate/biomni-tools:latest", "biomate/biotools:arm64"])
    elif raw_nextflow_path.startswith("nfcore/"):
        image_preferences.extend(["biomate/rnaseq:x86", "biomate/biotools:arm64"])

    # Optional explicit priority list (comma-separated image refs).
    custom_priority = os.environ.get("NEXTFLOW_RUNTIME_IMAGE_PRIORITY", "").strip()
    if custom_priority:
        for image in [p.strip() for p in custom_priority.split(",") if p.strip()]:
            if image not in image_preferences:
                image_preferences.append(image)

    for image in documented_images:
        if image not in image_preferences:
            image_preferences.append(image)

    local_candidates: list[str] = []
    host_arch = _host_arch()
    for img in image_preferences:
        if not _is_local_docker_image(img):
            continue
        compatible, _, image_arch = _is_image_arch_compatible(img)
        if not compatible:
            log.info(
                f"[Nextflow runtime] Skipping cross-arch image {img} "
                f"(host={host_arch}, image={image_arch}). "
                "Set NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER=true to allow emulation."
            )
            continue
        local_candidates.append(img)

    for image in local_candidates:
        if _docker_has_python_modules(image, required_modules):
            docker_opts: list[str] = ['-u $(id -u):$(id -g)', '--entrypoint ""']
            biomni_mount = Path(__file__).resolve().parents[6] / "Biomni"
            if biomni_mount.exists():
                docker_opts.append(f"-v {biomni_mount}:/app/Biomni:ro")
            return {
                "mode": "docker",
                "image": image,
                "docker_opts": " ".join(docker_opts),
                "required_modules": required_modules,
                "missing_modules": [],
                "host_arch": host_arch,
                "image_arch": _image_runtime_arch(image),
                "cross_arch_allowed": os.environ.get("NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER", "false"),
            }

    # Fallback: host mode with auto install
    _, missing = _host_has_python_modules(required_modules)
    remaining = _auto_install_host_modules(missing)
    return {
        "mode": "host",
        "image": None,
        "docker_opts": "",
        "required_modules": required_modules,
        "missing_modules": remaining,
        "host_arch": host_arch,
        "image_arch": None,
        "cross_arch_allowed": os.environ.get("NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER", "false"),
    }


_TRACE_SKIP_FILES = frozenset({
    ".command.sh", ".command.run", ".command.log", ".command.out",
    ".command.err", ".command.env", ".command.trace", ".exitcode",
    ".started", ".nf-params.json",
})


def _scan_task_work_dir(work_dir: str) -> List[str]:
    """List output files in a Nextflow task work directory, skipping internal files."""
    p = Path(work_dir)
    if not p.is_dir():
        return []
    files: List[str] = []
    try:
        for entry in p.iterdir():
            if not entry.is_file():
                continue
            if entry.name in _TRACE_SKIP_FILES:
                continue
            files.append(entry.name)
    except PermissionError:
        pass
    return sorted(files)


def _parse_trace_progress(trace_path: Path) -> dict:
    """Parse Nextflow trace file and return task-level progress counts.

    Also reads the optional ``workdir`` column (column 14) to surface per-task
    output files — enabling the UI to show intermediate results per step.
    """
    if not trace_path.exists():
        return {}
    try:
        lines = trace_path.read_text(errors="replace").splitlines()
    except OSError:
        return {}

    if not lines:
        return {}

    # Parse header to locate columns by name (trace format can vary)
    header = [h.strip() for h in lines[0].split("\t")]
    col_idx = {name: i for i, name in enumerate(header)}
    idx_task_id  = col_idx.get("task_id",  0)
    idx_name     = col_idx.get("name",     3)
    idx_status   = col_idx.get("status",   4)
    idx_workdir  = col_idx.get("workdir",  -1)  # not present in all Nextflow versions

    completed = failed = running = 0
    processes = []
    seen_tasks: Dict[str, str] = {}  # task_id → latest status

    for line in lines[1:]:  # skip header row
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 5:
            continue
        task_id      = parts[idx_task_id].strip() if idx_task_id < len(parts) else ""
        process_name = parts[idx_name].strip()    if idx_name    < len(parts) else ""
        status       = parts[idx_status].strip()  if idx_status  < len(parts) else ""
        work_dir     = (
            parts[idx_workdir].strip()
            if idx_workdir >= 0 and idx_workdir < len(parts)
            else ""
        )

        seen_tasks[task_id] = status

        # Collect files produced by this task (only for completed local tasks)
        task_files: List[str] = []
        if work_dir and status == "COMPLETED":
            task_files = _scan_task_work_dir(work_dir)

        processes.append({
            "id": task_id,
            "name": process_name,
            "status": status,
            "work_dir": work_dir,
            "task_files": task_files,
        })

    for s in seen_tasks.values():
        if s == "COMPLETED":
            completed += 1
        elif s == "FAILED":
            failed += 1
        elif s in ("RUNNING", "SUBMITTED"):
            running += 1

    total = len(seen_tasks)
    return {
        "completedTasks": completed,
        "failedTasks": failed,
        "runningTasks": running,
        "totalTasks": total,
        "progressPercent": int(completed * 100 / max(total, 1)) if total > 0 else 0,
        "processes": processes,
    }


def _evaluate_qc_from_s3(
    run_id: str,
    s3_output_files: list,
    workflow_domain: str,
    qc_overrides: dict,
) -> list:
    """
    Evaluate QC gates for completed AWS Batch runs by reading output files from S3.
    Returns a list of gate failure dicts (empty = all clear).
    Called once at run completion when local work dirs don't have output files.
    """
    try:
        import json as _json, io as _io, subprocess as _sub
        from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler, QC_RED_LINES

        domain_upper = workflow_domain.upper()
        is_admet = any(k in domain_upper for k in ("ADMET", "PHARMACOL", "DRUG_DISC", "TOXICITY"))
        is_admet_files = any(
            f.get("filename", "").endswith("toxicity_report.json") or
            "predict_admet_properties" in f.get("filename", "")
            for f in s3_output_files
        )
        is_cryo = any(k in domain_upper for k in ("CRYO", "CRYOSPARC", "CRYOEM", "CRYO_EM"))
        if not (is_admet or is_admet_files) and not is_cryo:
            return []  # S3 QC supported for ADMET and CryoEM domains

        # ── CryoEM path ────────────────────────────────────────────────────
        if is_cryo and not (is_admet or is_admet_files):
            # Build outdir from one of the s3_uris
            outdir = ""
            for _f in s3_output_files:
                _uri = _f.get("s3_uri", "")
                if _uri.startswith("s3://"):
                    # Use bucket + first two path components as outdir prefix
                    _parts = _uri[5:].split("/")
                    outdir = "s3://" + "/".join(_parts[:3]) if len(_parts) >= 3 else _uri
                    break
            qc_data = _build_qc_report_from_s3_files(s3_output_files, outdir)
            if not qc_data:
                return []
            gate_failures: List[Dict] = []
            # Operator and key mapping for each named metric
            _metric_map = {
                "Avg motion drift (Å)":         ("total_drift_angstrom",      ">"),
                "CTF fit resolution (Å)":        ("ctf_fit_to_A",              ">"),
                "Particle picking yield (/mic)": ("particles_per_micrograph",  "<"),
                "FSC 0.143 resolution (Å)":      ("fsc_resolution_angstrom",   ">"),
                "Junk class fraction":           ("junk_class_fraction",       ">"),
                "CTF fit quality":               ("ctf_fit_quality",           "<"),
            }
            for m in qc_data.get("_all_metrics", []):
                if m.get("pass", True):
                    continue  # Gate passed — nothing to report
                name = m.get("name", "")
                metric_key, operator = _metric_map.get(name, (
                    name.lower().replace(" ", "_").replace("(", "").replace(")", "").replace("/", "_per_"),
                    ">"
                ))
                gate_failures.append({
                    "metric": metric_key,
                    "value": m["measured"],
                    "threshold": m["threshold"],
                    "operator": operator,
                    "message": f"{name}: {m['measured']} {m.get('unit', '')} (threshold: {m['threshold']})",
                })
            return gate_failures

        # ── ADMET path ─────────────────────────────────────────────────────
        # Build a dummy handler just to reuse _check_qc_thresholds
        handler = NextflowQCGateHandler(
            invocation_id=run_id,
            work_dir=Path("/tmp"),
            sse_callback=lambda *a: None,
            app=None,
            workflow_domain=workflow_domain,
            qc_overrides=qc_overrides,
        )

        # Read toxicity_report.json from S3
        metrics: Dict[str, Any] = {}
        for f in s3_output_files:
            s3_uri = f.get("s3_uri", "")
            filename = f.get("filename", "")
            if not (filename == "toxicity_report.json" or s3_uri.endswith("/toxicity_report.json")):
                continue
            try:
                result = _sub.run(
                    [_aws_cli_bin(), "s3", "cp", s3_uri, "-"],
                    capture_output=True, timeout=15
                )
                if result.returncode == 0:
                    data = _json.loads(result.stdout)
                    tox = data.get("toxicity", data)
                    for key in ("herg_ic50_uM", "dili_risk", "dili_probability",
                                "ames_positive", "ames_probability", "clintox_probability"):
                        if key in tox:
                            metrics[key] = tox[key]
                    break
            except Exception as _e:
                log.warning("[QC S3] Failed to read %s: %s", s3_uri, _e)

        if not metrics:
            return []

        _, all_failures = handler._check_qc_thresholds(
            "PREDICT_ADMET_PROPERTIES", metrics
        )
        return all_failures

    except Exception as _exc:
        log.warning("[QC S3] Gate evaluation failed for %s: %s", run_id, _exc)
        return []


def _start_qc_monitor(
    invocation_id: str,
    work_dir: Path,
    qc_overrides: Dict[str, Any],
    workflow_domain: str,
    qc_profile: Optional[str] = None,
    trace_path: Optional[Path] = None,
    is_batch: bool = False,
    s3_outdir: Optional[str] = None,
) -> None:
    """
    Spawn a background thread that polls the Nextflow trace file and fires
    QC gate / warning events via SSE inject for the direct-executor path.

    The thread exits gracefully once the process finishes (no more trace updates
    for 120 s local / 1800 s Batch with a COMPLETED/FAILED final status)
    or after a 12-hour hard cap.
    """
    try:
        from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler
    except ImportError:
        log.warning("[QC Monitor] QC gate handler not available — skipping QC monitoring")
        return

    import os as _os
    import json as _json
    import urllib.request as _urllib

    # FRONTEND_URL when set is authoritative. Otherwise try the dev/prod
    # docker-compose service names on their actual listen ports (Node app
    # binds 3000, not 5000), then localhost as last resort. Probing order
    # matters: the first reachable URL is cached for the lifetime of this
    # callback closure.
    _explicit = _os.environ.get("FRONTEND_URL")
    _candidates = ([_explicit] if _explicit else [
        "http://biomate-dev-frontend:3000",
        "http://biomate-frontend:3000",
        "http://localhost:3000",
        "http://localhost:5000",
    ])
    inject_url_cache: dict = {"url": None}

    def _resolve_inject_url() -> str:
        if inject_url_cache["url"]:
            return inject_url_cache["url"]
        import socket as _socket
        for base in _candidates:
            url = f"{base}/internal/sse-inject"
            # Reachability check is a raw TCP connect to host:port, NOT an
            # HTTP probe. HTTP probes with an empty body return 4xx which
            # an HTTPError except would falsely treat as "unreachable", and
            # any real body would mutate state. TCP connect succeeds iff
            # the listener is alive.
            try:
                from urllib.parse import urlparse as _urlparse
                u = _urlparse(base)
                with _socket.create_connection((u.hostname, u.port or 80), timeout=2):
                    inject_url_cache["url"] = url
                    log.info("[QC Monitor] SSE inject endpoint: %s", url)
                    return url
            except Exception:
                continue
        inject_url_cache["url"] = f"{_candidates[0]}/internal/sse-inject"
        log.warning("[QC Monitor] No SSE inject endpoint reachable; falling back to %s", inject_url_cache["url"])
        return inject_url_cache["url"]

    def _sse_callback(event_type: str, data: dict) -> None:
        payload = _json.dumps({
            "invocation_id": invocation_id,
            "event_type": event_type,
            "data": data,
        }).encode("utf-8")
        try:
            req = _urllib.Request(
                _resolve_inject_url(),
                data=payload,
                headers={"Content-Type": "application/json"},
            )
            with _urllib.urlopen(req, timeout=5):
                pass
        except Exception as exc:
            log.warning("[QC Monitor] SSE inject failed for %s: %s", event_type, exc)

    handler = NextflowQCGateHandler(
        invocation_id=invocation_id,
        work_dir=work_dir,
        sse_callback=_sse_callback,
        app=None,
        workflow_domain=workflow_domain,
        qc_overrides=qc_overrides,
        qc_profile=qc_profile,
        s3_outdir=s3_outdir,
    )

    # Register handler so export endpoint can access live QC state.
    with _qc_handlers_lock:
        _qc_handlers[invocation_id] = handler

    def _poll() -> None:
        import time as _time
        trace_file = trace_path if trace_path is not None else (work_dir / "workflow-trace.txt")
        seen_tasks: set = set()
        # Phase-progress tracking (separate from QC's task tracking):
        #   seen_phase_started   — process_names that already fired workflow.phase_started
        #   seen_phase_terminal  — process_names that already fired workflow.phase_completed/failed
        # Aggregating by process_name avoids spamming chat when one process spawns N parallel tasks.
        seen_phase_started: set = set()
        seen_phase_terminal: set = set()
        idle_seconds = 0
        max_idle = 1800 if is_batch else 120  # 30 min for Batch cold-start; 2 min local
        hard_cap = 12 * 3600  # 12-hour hard stop

        def _short_phase_name(full: str) -> str:
            # "NFCORE_RNASEQ:RNASEQ:FASTQ_QC_TRIM_FILTER:STAR_ALIGN" → "STAR_ALIGN"
            return full.rsplit(":", 1)[-1] if ":" in full else full

        deadline = _time.monotonic() + hard_cap

        while _time.monotonic() < deadline:
            _time.sleep(5)
            if not trace_file.exists():
                idle_seconds += 5
                if idle_seconds >= max_idle:
                    break
                continue

            try:
                lines = trace_file.read_text(errors="replace").splitlines()
            except OSError:
                continue

            new_task_found = False
            # Per-iteration aggregation: process_name → list of task statuses.
            # Used after the per-task loop to decide phase_completed/failed.
            process_status_map: Dict[str, List[str]] = {}

            for line in lines[1:]:  # skip header
                if not line.strip():
                    continue
                parts = line.split("\t")
                if len(parts) < 5:
                    continue
                task_id = parts[0].strip()
                process_hash = parts[1].strip()
                process_name = parts[3].strip()
                task_status = parts[4].strip()

                # Aggregate for phase-completion decision below.
                process_status_map.setdefault(process_name, []).append(task_status)

                # Fire workflow.phase_started exactly once per process_name on its
                # first appearance in the trace, regardless of task_status.
                if process_name and process_name not in seen_phase_started:
                    seen_phase_started.add(process_name)
                    try:
                        _narrate_chat(
                            invocation_id,
                            "workflow.phase_started",
                            {"phase_name": _short_phase_name(process_name)},
                        )
                    except Exception as exc:
                        log.debug("[QC Monitor] phase_started emit failed for %s: %s", process_name, exc)

                task_key = f"{task_id}:{task_status}"
                if task_key not in seen_tasks and task_status in ("COMPLETED", "FAILED"):
                    seen_tasks.add(task_key)
                    new_task_found = True
                    try:
                        handler.handle_process_completion(
                            task_id=task_id,
                            process_name=process_name,
                            process_hash=process_hash,
                            status=task_status,
                        )
                    except Exception as exc:
                        log.warning(f"[QC Monitor] Error handling {process_name}: {exc}")

            # Fire workflow.phase_completed or phase_failed for each process_name
            # whose ALL observed tasks are now in a terminal state, and which has
            # not already had a terminal phase event emitted.
            _TERMINAL = ("COMPLETED", "FAILED", "ABORTED")
            for pname, statuses in process_status_map.items():
                if pname in seen_phase_terminal:
                    continue
                if not statuses or any(s not in _TERMINAL for s in statuses):
                    continue
                seen_phase_terminal.add(pname)
                short_name = _short_phase_name(pname)
                try:
                    if any(s == "FAILED" for s in statuses):
                        _narrate_chat(
                            invocation_id,
                            "workflow.phase_failed",
                            {"phase_name": short_name, "reason": f"{statuses.count('FAILED')} task(s) failed"},
                        )
                    else:
                        n_ok = statuses.count("COMPLETED")
                        detail = f"{n_ok} task(s)" if len(statuses) > 1 else None
                        _narrate_chat(
                            invocation_id,
                            "workflow.phase_completed",
                            {"phase_name": short_name, "detail": detail} if detail else {"phase_name": short_name},
                        )
                except Exception as exc:
                    log.debug("[QC Monitor] phase_terminal emit failed for %s: %s", pname, exc)

            if new_task_found:
                idle_seconds = 0
            else:
                idle_seconds += 5
                if idle_seconds >= max_idle:
                    break

        log.debug(f"[QC Monitor] Monitoring thread for {invocation_id} exiting")
        # Keep handler in registry even after thread exits — it holds the
        # complete in-memory event log that the export endpoint reads.

    t = threading.Thread(target=_poll, daemon=True, name=f"qc-monitor-{invocation_id[:8]}")
    t.start()
    log.info(
        f"[QC Monitor] Started QC monitoring for {invocation_id} "
        f"(domain={workflow_domain}, profile={qc_profile!r}, overrides={list(qc_overrides.keys())})"
    )


def _list_s3_output_files(s3_uri: str) -> list:
    """
    List output files in an S3 prefix after a workflow completes.
    Returns list of dicts: {key, name, size, extension}.
    Skips Nextflow internal files (work/, .nextflow/, trace).
    """
    try:
        import boto3
    except ImportError:
        return []
    try:
        parts = s3_uri[len("s3://"):].split("/", 1)
        bucket = parts[0]
        prefix = (parts[1] if len(parts) > 1 else "").rstrip("/") + "/"
        s3 = boto3.client("s3", region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
        paginator = s3.get_paginator("list_objects_v2")
        skip_prefixes = ("/work/", "/.nextflow/", "/trace.", "/timeline.", "/dag.", "/report.")
        results = []
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                # Skip Nextflow internals
                if any(p in key for p in skip_prefixes):
                    continue
                name = key.split("/")[-1]
                if not name:
                    continue
                ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
                results.append({
                    "s3_uri": f"s3://{bucket}/{key}",
                    "name": name,
                    "size": obj["Size"],
                    "extension": ext,
                })
        log.info(f"[Nextflow] Listed {len(results)} S3 output files from {s3_uri}")
        return results
    except Exception as exc:
        log.warning(f"[Nextflow] S3 output listing failed for {s3_uri}: {exc}")
        return []


# CryoSPARC-specific: map S3 output directory names → 0-indexed step IDs
# (matching _CRYOSPARC_STEP_PHASES in ai_assistant.py)
_CRYOSPARC_S3_DIR_TO_STEP: Dict[str, int] = {
    # Phase A — Motion Correction & CTF (step IDs from workflow definition)
    "00_cs_init": 0,                       # INIT_CRYOSPARC_PROJECT
    "00_batch_split": 1,                   # SPLIT_INTO_BATCHES
    "02_motion_correction": 2,             # PATCH_MOTION_CORRECTION_BATCH
    "03_ctf_estimation": 3,               # PATCH_CTF_ESTIMATION_BATCH
    "05_blob_picker": 4,                   # BLOB_PICKER_BATCH
    "08_extract_round1": 5,               # EXTRACT_PARTICLES_R1_BATCH
    # Phase B — 2D Classification
    "09_particle_batch_split": 6,          # SPLIT_PARTICLE_BATCHES
    "09_particle_batch_split_r2": 7,       # SPLIT_PARTICLE_BATCHES_R2
    "09_classify_2d_round1": 8,           # CLASSIFY_2D_R1_BATCH
    "14_classify_2d_round2": 9,           # CLASSIFY_2D_R2_BATCH
    # Phase C — 3D Reconstruction
    "16_ab_initio": 10,                    # AB_INITIO_BATCH
    "17_homo_refinement": 11, "17_homogeneous_refinement": 11,  # HOMO_REFINEMENT_BATCH
    "03b_merge_micrographs": 12,           # MERGE_MICROGRAPHS
    "merge_particles": 13,                 # MERGE_PARTICLES
    # Phase D — Post-processing
    "merge_classes": 14,                   # MERGE_CLASSES
    "merge_particles_r1": 16,             # MERGE_PARTICLES_R1
    "merge_classes_r2": 17,               # MERGE_CLASSES_R2
    "16b_merge_volumes": 18,              # MERGE_VOLUMES
    # Phase E — QC & Analysis
    "04_denoiser": 19,                    # MICROGRAPH_DENOISER
    "06_junk_detector": 20,               # JUNK_2D_DETECTOR
    "07_inspect_picks_round1": 21,        # INSPECT_PICKS
    "10_select_2d_round1": 22,            # SELECT_2D_R1
    "11_template_picker": 23,             # TEMPLATE_PICKER
    "12_inspect_picks_round2": 24,        # INSPECT_PICKS_R2
    "13_extract_round2": 25,              # EXTRACT_PARTICLES_R2
    "15_select_2d_round2": 26,            # SELECT_2D_R2
    "18_volume_tools": 27,               # VOLUME_TOOLS
    "19_validation_fsc": 28, "22_fsc_validation": 28,  # VALIDATION_FSC
    "20_local_ctf_refinement": 29, "19_local_ctf": 29,  # LOCAL_CTF_REFINEMENT
    "21_non_uniform_refinement": 30, "18_nu_refinement": 30,  # NON_UNIFORM_REFINEMENT
    "20_local_resolution": 31,            # LOCAL_RESOLUTION
    "23_sharpening": 32, "21_sharpen": 32,  # SHARPEN
}

# File extensions to exclude from step output surfacing (empty directory markers etc.)
_CRYOSPARC_SKIP_EXT = {""}


def _build_processes_from_s3_files(s3_files: List[Dict], outdir: str,
                                    workflow_domain: str = "") -> List[Dict]:
    """
    Group S3 output files by step directory and return a `processes` array
    compatible with the viewer's nfProcessByName lookup.

    For cryo_em domain: uses _CRYOSPARC_S3_DIR_TO_STEP to map directory names to
    step IDs (string integers) that match the workflow definition's step indices.
    For other domains: uses the numeric prefix of the directory name as the step ID.

    The viewer looks up processes via proc.id / proc.name and reads proc.task_files
    (array of string paths) to populate step output chips.
    """
    from collections import defaultdict
    step_files: Dict[str, List[str]] = defaultdict(list)

    prefix = outdir.rstrip("/") + "/"
    for f in s3_files:
        uri = f.get("s3_uri", "")
        if not uri or uri.endswith("/"):   # skip directory markers
            continue
        # Get path relative to outdir
        if uri.startswith(prefix):
            rel = uri[len(prefix):]
        else:
            parts = uri.split("/")
            # Reconstruct relative from last 3 segments (step_dir/subdir/file)
            rel = "/".join(parts[-3:]) if len(parts) >= 3 else parts[-1]
        step_dir = rel.split("/")[0]
        filename = rel.split("/")[-1]
        if not filename:   # another guard against directory URIs
            continue
        ext = "." + filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
        if ext in _CRYOSPARC_SKIP_EXT:
            continue
        step_files[step_dir].append(uri)

    processes = []
    for step_dir, uris in step_files.items():
        if workflow_domain == "cryo_em":
            step_id = str(_CRYOSPARC_S3_DIR_TO_STEP.get(step_dir, -1))
        else:
            # Generic: parse numeric prefix (e.g. "02_motion" → "1" (0-indexed))
            try:
                step_id = str(int(step_dir.split("_")[0]) - 1)
            except (ValueError, IndexError):
                step_id = step_dir
        # Index by multiple keys so viewer's nfProcessByName lookup hits regardless
        # of whether phase.id is the numeric index ("2"), the raw dir ("02_motion_correction"),
        # or the unprefixed snake_case ("motion_correction").
        unprefixed = step_dir.split("_", 1)[1] if "_" in step_dir and step_dir.split("_", 1)[0].isdigit() else step_dir
        processes.append({
            "id": step_id,
            "name": step_dir,
            "process": unprefixed,
            "step_dir": step_dir,
            "status": "completed",
            "task_files": uris,
        })

    return processes


def _build_qc_report_from_s3_files(s3_files: List[Dict], outdir: str) -> Optional[Dict]:
    """
    Download JSON report files from S3 and aggregate QC metrics into a structured
    report dict. Works for any workflow — reads all *_report*.json files.

    Returns None if no metrics could be extracted, or:
    {
      "motion": {"avg_total_motion_A": 18.3, "max_total_motion_A": 41.2},
      "ctf":    {"avg_fit_quality": 0.72, "avg_defocus_A": 18500, "avg_astigmatism_A": 420},
      "picking": {"num_particles": 24879},
      "classification": {"num_good_classes": 32, "num_classes": 50, "junk_class_fraction": 0.36},
      "_all_metrics": [{"name": "...", "measured": ..., "unit": "...", "step": "..."}]
    }
    """
    try:
        import boto3 as _boto3
        import json as _json
        s3_client = _boto3.client("s3", region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
    except ImportError:
        return None

    report_files = [f for f in s3_files
                    if "report" in f.get("name", "").lower() and f.get("extension") == "json"]
    if not report_files:
        return None

    metrics: Dict[str, Any] = {}
    all_metrics: List[Dict] = []
    # Track motion micrograph count so picking can compute particles/mic
    _motion_num_mics: Optional[int] = None

    for rf in report_files:
        uri = rf.get("s3_uri", "")
        if not uri.startswith("s3://"):
            continue
        try:
            parts = uri[5:].split("/", 1)
            obj = s3_client.get_object(Bucket=parts[0], Key=parts[1])
            data: Dict = _json.loads(obj["Body"].read().decode("utf-8"))
        except Exception as _e:
            log.warning("[QC] S3 read failed for %s: %s", rf.get("name"), _e)
            continue

        step = data.get("step", rf.get("name", ""))

        if "02_patch_motion" in step or "02_motion" in step:
            num_mics = data.get("num_micrographs")
            motion_entry: Dict[str, Any] = {}
            if num_mics is not None:
                motion_entry["num_micrographs"] = num_mics
                _motion_num_mics = int(num_mics)
            if "avg_total_motion_A" in data:
                motion_entry.update({
                    "avg_total_motion_A": data["avg_total_motion_A"],
                    "max_total_motion_A": data.get("max_total_motion_A"),
                    "num_accepted": data.get("num_accepted"),
                })
                all_metrics.append({"name": "Avg motion drift (Å)", "step": step,
                                     "measured": data["avg_total_motion_A"], "unit": "Å",
                                     "threshold": 50.0,
                                     "pass": data["avg_total_motion_A"] < 50.0})
            if motion_entry:
                metrics.setdefault("motion", {}).update(motion_entry)

        elif "03_patch_ctf" in step or "03_ctf" in step:
            num_mics = data.get("num_micrographs")
            ctf_entry: Dict[str, Any] = {}
            if num_mics is not None:
                ctf_entry["num_micrographs"] = num_mics
            # Use avg_ctf_fit_to_A (actual field written by pipeline) NOT avg_fit_quality
            if "avg_ctf_fit_to_A" in data:
                fit_val = float(data["avg_ctf_fit_to_A"])
                ctf_entry.update({
                    "avg_ctf_fit_to_A": fit_val,
                    "avg_defocus_A": data.get("avg_defocus_A"),
                    "avg_astigmatism_A": data.get("avg_astigmatism_A"),
                    # Derived quality score: 0..1, higher is better (1.0 = 0Å fit, 0.0 = 10Å)
                    "avg_fit_quality": round(max(0.0, 1.0 - fit_val / 10.0), 3),
                })
                # Gate: CTF fit resolution ≤ 8Å is acceptable; higher = worse
                all_metrics.append({"name": "CTF fit resolution (Å)", "step": step,
                                     "measured": fit_val, "unit": "Å",
                                     "threshold": 8.0,
                                     "pass": fit_val <= 8.0})
            elif "avg_fit_quality" in data:
                # Legacy field — keep backward compat
                ctf_entry["avg_fit_quality"] = data["avg_fit_quality"]
                all_metrics.append({"name": "CTF fit quality", "step": step,
                                     "measured": data["avg_fit_quality"], "unit": "",
                                     "threshold": 0.7,
                                     "pass": data["avg_fit_quality"] >= 0.7})
            if ctf_entry:
                metrics.setdefault("ctf", {}).update(ctf_entry)

        elif "05_blob_picker" in step or "blob_picker" in step:
            num_particles = data.get("num_particles")
            picking_entry: Dict[str, Any] = {}
            if num_particles is not None:
                picking_entry["num_particles"] = int(num_particles)
            if "particle_diameter_angstroms" in data:
                picking_entry["particle_diameter_angstroms"] = data["particle_diameter_angstroms"]
            # Compute particles/micrograph yield if we have micrograph count
            if num_particles is not None and _motion_num_mics and _motion_num_mics > 0:
                yield_per_mic = round(float(num_particles) / float(_motion_num_mics), 1)
                picking_entry["particles_per_micrograph"] = yield_per_mic
                all_metrics.append({"name": "Particle picking yield (/mic)", "step": step,
                                     "measured": yield_per_mic, "unit": "/mic",
                                     "threshold": 50.0,
                                     "pass": yield_per_mic >= 50.0})
            elif num_particles is not None and num_particles > 0:
                # Can't compute yield without mic count; record raw count only
                picking_entry.setdefault("note", "num_micrographs unavailable for yield calc")
            if picking_entry:
                metrics.setdefault("picking", {}).update(picking_entry)

        elif "09_classify" in step or "14_classify" in step:
            # Skip selection_report — num_selected_particles=0 is a known cs_mode bug
            if "num_selected_particles" in data and data.get("num_particles", -1) == 0:
                continue
            nm = data.get("num_particles") or data.get("num_items", 0)
            nc = data.get("num_classes", 0)
            if nm:
                # Keep the higher count across rounds
                prev_nm = metrics.get("classification", {}).get("num_particles", 0)
                if nm > prev_nm:
                    metrics.setdefault("classification", {}).update({
                        "num_particles": nm,
                        "num_classes": nc,
                        "step": step,
                    })
                    # Update picking num_particles too (post-2D selection)
                    metrics.setdefault("picking", {})["num_particles_2d"] = nm
            if "junk_class_fraction" in data:
                metrics.setdefault("classification", {}).update({
                    "junk_class_fraction": data["junk_class_fraction"],
                    "num_good_classes": data.get("num_good_classes"),
                })
                all_metrics.append({"name": "Junk class fraction", "step": step,
                                     "measured": data["junk_class_fraction"], "unit": "",
                                     "threshold": 0.5,
                                     "pass": data["junk_class_fraction"] <= 0.5})

        elif "21_non_uniform_refinement" in step or "non_uniform_refinement" in step:
            # Record job UID as proof of refinement reaching this step
            if data.get("cs_job_uid"):
                metrics.setdefault("refinement", {})["cs_job_uid"] = data["cs_job_uid"]
            # DON'T add num_particles if 0 — cs_mode bug causes false zeros
            np_val = data.get("num_particles", 0)
            if np_val and np_val > 0:
                metrics.setdefault("refinement", {})["num_particles"] = np_val

        elif "fsc" in step.lower() or "19_validation" in step:
            if "fsc_resolution_angstrom" in data:
                res = float(data["fsc_resolution_angstrom"])
                metrics.setdefault("fsc", {})["resolution_A"] = res
                all_metrics.append({"name": "FSC 0.143 resolution (Å)", "step": step,
                                     "measured": res, "unit": "Å",
                                     "threshold": 10.0,
                                     "pass": res <= 10.0})
            elif "estimated_resolution_A" in data:
                res = float(data["estimated_resolution_A"])
                metrics.setdefault("fsc", {})["resolution_A"] = res
                all_metrics.append({"name": "FSC 0.143 resolution (Å)", "step": step,
                                     "measured": res, "unit": "Å",
                                     "threshold": 10.0,
                                     "pass": res <= 10.0})
            elif "fsc_curve" in data:
                curve = data["fsc_curve"]
                if isinstance(curve, list) and len(curve) > 0:
                    # Find resolution where FSC crosses 0.143 (gold-standard criterion)
                    res_at_143 = None
                    for i in range(len(curve) - 1):
                        pt = curve[i]
                        pt_next = curve[i + 1]
                        fsc_val = pt.get("fsc", pt.get("y", None))
                        fsc_next = pt_next.get("fsc", pt_next.get("y", None))
                        if fsc_val is not None and fsc_next is not None:
                            if fsc_val >= 0.143 and fsc_next < 0.143:
                                # Linearly interpolate resolution at 0.143
                                res_val = pt.get("resolution_A", pt.get("x", 0))
                                res_next = pt_next.get("resolution_A", pt_next.get("x", 0))
                                frac = (0.143 - fsc_val) / (fsc_next - fsc_val)
                                res_at_143 = round(res_val + frac * (res_next - res_val), 2)
                                break
                    if res_at_143 is not None:
                        metrics.setdefault("fsc", {})["resolution_A"] = res_at_143
                        all_metrics.append({"name": "FSC 0.143 resolution (Å)", "step": step,
                                             "measured": res_at_143, "unit": "Å",
                                             "threshold": 10.0,
                                             "pass": res_at_143 <= 10.0})

    # Only return a result if there's at least one actionable metric beyond micrograph count
    has_real_metrics = bool(all_metrics) or bool(
        metrics.get("picking") or metrics.get("classification") or
        metrics.get("refinement") or metrics.get("fsc")
    )
    if not has_real_metrics:
        return None
    metrics["_all_metrics"] = all_metrics
    return metrics


def _tag_s3_outputs(run_meta: Dict[str, Any]) -> None:
    """
    Tag all S3 output objects for a completed run with user_id and run_id.

    This allows the biomate-s3-billing Lambda to attribute storage costs to the
    correct user even when Nextflow writes files without object tags. Called
    once after the run finishes — best-effort, never blocks the run itself.
    """
    user_id = run_meta.get("user_id") or ""
    run_id = run_meta.get("run_id") or ""
    outdir = run_meta.get("outdir") or ""

    if not (user_id and run_id and str(outdir).startswith("s3://")):
        return

    try:
        import boto3
        parts = outdir.replace("s3://", "").split("/", 1)
        bucket = parts[0]
        prefix = parts[1] if len(parts) > 1 else ""

        s3 = boto3.client("s3")
        paginator = s3.get_paginator("list_objects_v2")
        tag_set = [
            {"Key": "user_id", "Value": user_id},
            {"Key": "workflow_id", "Value": run_id},
            {"Key": "tagged_by", "Value": "biomate-postrun"},
        ]

        count = 0
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                try:
                    s3.put_object_tagging(
                        Bucket=bucket,
                        Key=key,
                        Tagging={"TagSet": tag_set},
                    )
                    count += 1
                except Exception as tag_err:
                    log.warning("[S3 tag] Failed to tag s3://%s/%s: %s", bucket, key, tag_err)

        log.info("[S3 tag] Tagged %d output objects for run=%s user=%s", count, run_id, user_id)
    except Exception as exc:
        log.warning("[S3 tag] Post-run tagging failed for run=%s: %s", run_id, exc)


def _write_timing(run_id: str, updates: dict) -> None:
    """Atomically merge *updates* into timing.json for *run_id*."""
    import json as _json
    _timing_path = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs")) / run_id / "timing.json"
    try:
        _existing: dict = {}
        if _timing_path.exists():
            _existing = _json.loads(_timing_path.read_text())
        _existing.update(updates)
        _timing_path.write_text(_json.dumps(_existing))
    except Exception as _te:
        log.debug("[timing] Could not update timing.json for %s: %s", run_id, _te)


def _stream_logs(process: subprocess.Popen, run_id: str, log_path: Path):
    """Wait for the Nextflow subprocess and post-process its on-disk log.

    DO NOT REVERT to `for line in process.stdout` — that pattern requires
    `stdout=subprocess.PIPE` on the Popen, which causes the Nextflow JVM to
    block on a full pipe buffer when the gunicorn worker recycles, killing
    the run ~60s after Phase A submit. The subprocess now writes directly to
    `log_path` via an inherited fd (see Popen sites at ~3125 and ~3659).
    See docs/20260603_TIER0_COMPREHENSIVE_E2E_AND_DISPATCH_BUG.md.
    """
    _completed_at_now: float = 0.0
    final_status: str = "interrupted"
    returncode: int = -1
    run_meta: Dict[str, Any] = {}
    try:
        process.wait()
        returncode = process.returncode
        _completed_at_now = time.time()

        # nf-core epitopeprediction calls Nextflow.error() for missing NetMHC paths but
        # may still exit 0 — scan the log before marking success.
        _log_text = ""
        try:
            if log_path.is_file():
                _log_text = log_path.read_text(encoding="utf-8", errors="replace")
        except Exception:
            pass
        with _runs_lock:
            _run_snap = dict(_runs.get(run_id) or {})
        _duration_s: Optional[int] = None
        _started = _run_snap.get("started_at")
        if _started:
            _duration_s = int(_completed_at_now - _started)
        _total_steps = 0
        _trace_path = Path(_run_snap.get("trace_path", ""))
        if _trace_path.is_file():
            try:
                _trace_lines = [
                    l for l in _trace_path.read_text().splitlines()
                    if l.strip() and not l.startswith("task_id")
                ]
                _total_steps = len(_trace_lines)
            except Exception:
                pass
        if returncode == 0 and _looks_like_false_success(
            log_full_text=_log_text,
            total_steps=_total_steps,
            duration_s=_duration_s,
            s3_output_files=[],
            workflow_domain=_run_snap.get("workflow_domain", ""),
            nextflow_path=_run_snap.get("nextflow_path", ""),
        ):
            log.warning(
                "[Nextflow run %s] exit 0 but looks like false success — marking failed",
                run_id,
            )
            returncode = 1

        _s3_files_for_salvage: list = []
        _outdir_chk = _run_snap.get("outdir", "")
        if returncode != 0 and str(_outdir_chk).startswith("s3://"):
            _s3_files_for_salvage = _list_s3_output_files(_outdir_chk)
        if returncode != 0 and _looks_like_false_failure(
            log_full_text=_log_text,
            returncode=returncode,
            s3_output_files=_s3_files_for_salvage,
        ):
            log.warning(
                "[Nextflow run %s] exit %d but Batch succeeded with published outputs — marking succeeded",
                run_id,
                returncode,
            )
            returncode = 0

        if returncode == 0:
            final_status = "succeeded"
        elif returncode < 0:
            # Negative return code means killed by signal (e.g. SIGTERM = -15)
            import signal as _signal
            try:
                sig_name = _signal.Signals(-returncode).name
            except ValueError:
                sig_name = str(-returncode)
            final_status = "interrupted"
            log.warning(
                "[Nextflow run %s] process killed by signal %s (%s) — "
                "gunicorn restart or container stop; resume required",
                run_id, sig_name, returncode,
            )
        else:
            final_status = "failed"

        with _runs_lock:
            if run_id in _runs:
                _runs[run_id]["status"] = final_status
                _runs[run_id]["returncode"] = returncode
                _runs[run_id]["completed_at"] = _completed_at_now
            _inv_id = _runs.get(run_id, {}).get("invocation_id")

        # Friendly chat-progress: emit the right line for the terminal state.
        if _inv_id:
            if final_status == "completed" or returncode == 0:
                _narrate_chat(_inv_id, "workflow.completed", {"run_id": run_id, "returncode": returncode})
            elif final_status == "failed":
                _narrate_chat(_inv_id, "workflow.failed", {"run_id": run_id, "returncode": returncode, "reason": f"exit {returncode}"})
            elif final_status == "interrupted":
                _narrate_chat(_inv_id, "workflow.failed", {"run_id": run_id, "reason": "workflow was interrupted"})

        # Write timing.json immediately — before any follow-on work that could fail.
        _write_timing(run_id, {
            "completed_at": _completed_at_now,
            "status": final_status,
            "returncode": returncode,
        })

        with _runs_lock:
            if run_id in _runs:
                # Enumerate S3 output files on success (including salvaged false failures).
                if returncode == 0:
                    outdir = _runs[run_id].get("outdir", "")
                    if str(outdir).startswith("s3://"):
                        _runs[run_id]["s3_output_files"] = (
                            _s3_files_for_salvage or _list_s3_output_files(outdir)
                        )
                        # Evaluate QC gates from S3 output files (Batch runs have no local work dir)
                        _qc_gates_s3 = _evaluate_qc_from_s3(
                            run_id=run_id,
                            s3_output_files=_runs[run_id]["s3_output_files"],
                            workflow_domain=_runs[run_id].get("workflow_domain", ""),
                            qc_overrides=_runs[run_id].get("qc_overrides", {}),
                        )
                        if _qc_gates_s3:
                            _runs[run_id]["qc_gates"] = _qc_gates_s3
                            log.info("[QC Gate] S3 evaluation for %s: %d gate(s)", run_id, len(_qc_gates_s3))
                run_meta = dict(_runs[run_id])
        log.info("[Nextflow run %s] finished — status=%s returncode=%d", run_id, final_status, returncode)

        # Emit structured log lines for every Batch job ID found in .nextflow.log
        _scrape_batch_job_ids(run_id)

        # Tag all S3 output objects with user_id so the billing Lambda can attribute them.
        # This is done as a best-effort background step after run completion.
        _tag_s3_outputs(run_meta)

        # C2a — Write durable per-run JSON study log (required by pilot study plan)
        try:
            from galaxy.ai.study_run_logger import StudyRunLogger
            StudyRunLogger.record(run_meta)
        except Exception as _log_err:
            log.warning("[StudyRunLogger] log write failed for run %s: %s", run_id, _log_err)

        # C2b — Record workflow outcome in LTM (fire-and-forget; never blocks main flow)
        try:
            from galaxy.ai.memory.agentic_memory import get_memory_service
            duration_s = None
            started_at = run_meta.get("started_at")
            if started_at:
                duration_s = int(time.time() - started_at)
            nf_path = run_meta.get("nextflow_path", "")
            workflow_name = nf_path.rsplit("/", 1)[-1] if nf_path else run_id
            memory_svc = get_memory_service()
            memory_svc.record_workflow_outcome(
                user_id=run_meta.get("user_id") or "anonymous",
                session_id=run_id,
                query=workflow_name,
                workflow_id=nf_path or run_id,
                outcome=final_status,
                run_duration_s=duration_s,
                autofix_count=0,
                error_type=None if returncode == 0 else f"exit_code_{returncode}",
            )
            log.info("[ltm] Recorded workflow outcome: run=%s status=%s", run_id, final_status)
        except Exception as _ltm_err:
            log.warning("[ltm] record_outcome failed for run %s: %s", run_id, _ltm_err)

        # C2c — Direct compute billing record (bypasses Lambda/EventBridge).
        # Calls POST /internal/billing/job_completed on the local Galaxy billing API.
        # Only emits for real AWS Batch runs; skips pilot/anonymous users.
        try:
            if (run_meta.get("is_batch")
                    and not run_meta.get("is_pilot")
                    and run_meta.get("user_id") not in (None, "", "anonymous")):
                import urllib.request as _urllib_req
                import json as _billing_json
                _billing_key = (
                    os.environ.get("BILLING_INTERNAL_KEY")
                    or os.environ.get("BILLING_API_KEY")
                    or "dev-insecure-key"
                )
                _galaxy_base = (
                    os.environ.get("GALAXY_URL", "").rstrip("/")
                    or "http://localhost:8081"
                )
                _billing_url = f"{_galaxy_base}/internal/billing/job_completed"
                _started = run_meta.get("started_at") or _completed_at_now
                _duration = max(_completed_at_now - _started, 1.0)
                _bill_payload = _billing_json.dumps({
                    "user_id": run_meta["user_id"],
                    "job_id": run_id,
                    "workflow_id": run_meta.get("nextflow_path", run_id),
                    "status": "SUCCEEDED" if returncode == 0 else "FAILED",
                    "instance_type": "optimal",
                    "vcpus": 4.0,
                    "memory_mb": 8192,
                    "gpu_count": 0,
                    "duration_seconds": _duration,
                }).encode()
                _bill_req = _urllib_req.Request(
                    _billing_url,
                    data=_bill_payload,
                    headers={"Content-Type": "application/json", "X-Internal-Key": _billing_key},
                    method="POST",
                )
                with _urllib_req.urlopen(_bill_req, timeout=5) as _bill_resp:
                    _bill_resp.read()
                log.info("[billing] job_completed emitted for run %s (%.1fs)", run_id, _duration)
        except Exception as _bill_err:
            log.warning("[billing] job_completed emit failed for run %s: %s", run_id, _bill_err)

    except Exception as exc:
        log.error("[Nextflow run %s] log streaming error: %s", run_id, exc)
        if _find_nextflow_pids_for_run(run_id):
            log.warning(
                "[Nextflow run %s] log streaming lost but Nextflow JVM still running — keeping status=running",
                run_id,
            )
            with _runs_lock:
                if run_id in _runs:
                    _runs[run_id]["status"] = "running"
            return
        final_status = "failed"
        _completed_at_now = time.time()
        with _runs_lock:
            if run_id in _runs:
                _runs[run_id]["status"] = "failed"
    finally:
        # Best-effort: always write completed_at to disk so status endpoint
        # can report a terminal state even after gunicorn worker is recycled.
        if _completed_at_now:
            _write_timing(run_id, {
                "completed_at": _completed_at_now,
                "status": final_status,
                "returncode": returncode,
            })


# ---------------------------------------------------------------------------
# Public-database accession download handlers
# ---------------------------------------------------------------------------

def _run_fetchngs_prefetch(
    accessions: list[str],
    work_base: Path,
    run_id: str,
    nf_bin: str,
    profile: str,
    env: dict,
    executor_config_path: Optional[Path],
) -> Optional[str]:
    """
    Run nf-core/fetchngs synchronously to download sequencing data for *accessions*.

    Returns the path to the generated samplesheet.csv, or None on failure.
    The samplesheet can be passed as --input to the main workflow.
    """
    try:
        fetchngs_path = _resolve_nextflow_path("nfcore/fetchngs/main.nf")
    except FileNotFoundError:
        log.warning("[fetchngs] nf-core/fetchngs not found in workflow search roots — skipping prefetch")
        return None

    fetch_run_dir = work_base / f"{run_id}_fetchngs"
    fetch_run_dir.mkdir(parents=True, exist_ok=True)

    # Write accession list file
    ids_file = fetch_run_dir / "ids.csv"
    ids_file.write_text("\n".join(accessions) + "\n")

    fetch_outdir = fetch_run_dir / "output"
    fetch_outdir.mkdir(exist_ok=True)
    fetch_work = fetch_run_dir / "work"
    fetch_work.mkdir(exist_ok=True)

    cmd = [
        nf_bin, "run", str(fetchngs_path),
        "-profile", profile,
        "-w", str(fetch_work),
        "--input", str(ids_file),
        "--outdir", str(fetch_outdir),
        "--nf_core_pipeline", "rnaseq",  # generates samplesheet compatible with nf-core pipelines
    ]
    if executor_config_path:
        cmd += ["-c", str(executor_config_path)]

    log_path = fetch_run_dir / "fetchngs.log"
    log.info(f"[fetchngs run_id={run_id}] Starting prefetch: {' '.join(accessions)}")
    log.info(f"[fetchngs run_id={run_id}] cmd: {' '.join(cmd)}")

    try:
        with open(log_path, "w") as lf:
            proc = subprocess.Popen(
                cmd,
                stdout=lf,
                stderr=subprocess.STDOUT,
                text=True,
                cwd=str(fetchngs_path.parent),
                env=env,
            )
            proc.wait(timeout=3600)  # 1 hour max for prefetch

        if proc.returncode != 0:
            log.error(f"[fetchngs run_id={run_id}] Failed (rc={proc.returncode}) — check {log_path}")
            return None

        # nf-core/fetchngs writes samplesheet to outdir/samplesheet/samplesheet.csv
        for candidate in [
            fetch_outdir / "samplesheet" / "samplesheet.csv",
            fetch_outdir / "fastq" / "samplesheet.csv",
            fetch_outdir / "samplesheet.csv",
        ]:
            if candidate.exists():
                log.info(f"[fetchngs run_id={run_id}] Samplesheet ready: {candidate}")
                return str(candidate)

        log.warning(f"[fetchngs run_id={run_id}] No samplesheet found in {fetch_outdir}")
        return None

    except subprocess.TimeoutExpired:
        proc.kill()
        log.error(f"[fetchngs run_id={run_id}] Prefetch timed out after 1 hour")
        return None
    except Exception as exc:
        log.error(f"[fetchngs run_id={run_id}] Prefetch error: {exc}")
        return None


def _download_pdb_structure(accession: str, out_dir: Path) -> Optional[str]:
    """
    Download a PDB/EMDB structure file via the RCSB / EMDB HTTP API.
    Returns local file path or None on failure.
    """
    import urllib.request
    import urllib.error

    out_dir.mkdir(parents=True, exist_ok=True)
    acc_upper = accession.upper()

    if acc_upper.startswith("EMD-"):
        emdb_id = acc_upper[4:]  # strip "EMD-"
        url = f"https://ftp.ebi.ac.uk/pub/databases/emdb/structures/EMD-{emdb_id}/map/emd_{emdb_id}.map.gz"
        dest = out_dir / f"emd_{emdb_id}.map.gz"
    else:
        # Use legacy PDB format (.pdb) for compatibility with Bio.PDB.PDBParser.
        # mmCIF format causes ValueError in PDBParser ("invalid literal for int").
        url = f"https://files.rcsb.org/download/{acc_upper}.pdb"
        dest = out_dir / f"{acc_upper}.pdb"

    if dest.exists():
        log.info(f"[accession] {acc_upper}: already downloaded at {dest}")
        return str(dest)

    try:
        log.info(f"[accession] Downloading {acc_upper} from {url}")
        urllib.request.urlretrieve(url, dest)
        log.info(f"[accession] {acc_upper}: saved to {dest} ({dest.stat().st_size // 1024} KB)")
        return str(dest)
    except urllib.error.HTTPError as exc:
        log.error(f"[accession] {acc_upper}: HTTP {exc.code} from {url}")
        return None
    except Exception as exc:
        log.error(f"[accession] {acc_upper}: download failed: {exc}")
        return None


def _download_uniprot_fasta(accession: str, out_dir: Path) -> Optional[str]:
    """
    Download a protein sequence (UniProt / Ensembl protein / NCBI RefSeq) as FASTA.
    Returns local file path or None on failure.
    """
    import urllib.request
    import urllib.error

    out_dir.mkdir(parents=True, exist_ok=True)
    acc_upper = accession.upper()
    dest = out_dir / f"{acc_upper}.fasta"

    if dest.exists():
        log.info(f"[accession] {acc_upper}: already downloaded at {dest}")
        return str(dest)

    # Choose URL based on accession prefix
    if acc_upper.startswith("ENSP"):
        url = f"https://rest.ensembl.org/sequence/id/{acc_upper}?content-type=text/x-fasta;type=protein"
    elif acc_upper.startswith(("NP_", "XP_", "WP_")):
        # NCBI efetch
        url = (
            f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
            f"?db=protein&id={acc_upper}&rettype=fasta&retmode=text"
        )
    else:
        # UniProtKB
        url = f"https://rest.uniprot.org/uniprotkb/{acc_upper}.fasta"

    try:
        log.info(f"[accession] Downloading protein FASTA for {acc_upper} from {url}")
        urllib.request.urlretrieve(url, dest)
        log.info(f"[accession] {acc_upper}: saved to {dest} ({dest.stat().st_size} bytes)")
        return str(dest)
    except urllib.error.HTTPError as exc:
        log.error(f"[accession] {acc_upper}: HTTP {exc.code} from {url}")
        return None
    except Exception as exc:
        log.error(f"[accession] {acc_upper}: download failed: {exc}")
        return None


def _download_genomic_ref(accession: str, out_dir: Path) -> Optional[str]:
    """
    Download a genomic reference sequence (Ensembl gene/transcript or NCBI RefSeq nucleotide).
    Returns local FASTA path or None on failure.
    """
    import urllib.request
    import urllib.error

    out_dir.mkdir(parents=True, exist_ok=True)
    acc_upper = accession.upper()
    dest = out_dir / f"{acc_upper}.fasta"

    if dest.exists():
        return str(dest)

    if acc_upper.startswith("ENSG") or acc_upper.startswith("ENST"):
        endpoint = "sequence/id"
        type_param = "genomic" if acc_upper.startswith("ENSG") else "cdna"
        url = f"https://rest.ensembl.org/{endpoint}/{acc_upper}?content-type=text/x-fasta;type={type_param}"
    else:
        # NCBI RefSeq nucleotide
        url = (
            f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
            f"?db=nuccore&id={acc_upper}&rettype=fasta&retmode=text"
        )

    try:
        log.info(f"[accession] Downloading genomic FASTA for {acc_upper}")
        urllib.request.urlretrieve(url, dest)
        return str(dest)
    except Exception as exc:
        log.error(f"[accession] {acc_upper}: download failed: {exc}")
        return None


def _download_chemical_structure(accession: str, out_dir: Path) -> Optional[str]:
    """
    Download a small-molecule structure (ChEMBL or PubChem) as SDF.
    Returns local file path or None on failure.
    """
    import urllib.request
    import urllib.error

    out_dir.mkdir(parents=True, exist_ok=True)
    acc_upper = accession.upper()
    dest = out_dir / f"{acc_upper}.sdf"

    if dest.exists():
        return str(dest)

    if acc_upper.startswith("CHEMBL"):
        url = f"https://www.ebi.ac.uk/chembl/api/data/molecule/{acc_upper}.sdf"
    elif acc_upper.startswith("CID"):
        cid_num = acc_upper[3:]  # strip "CID"
        url = f"https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/{cid_num}/SDF"
    else:
        return None

    try:
        log.info(f"[accession] Downloading chemical structure for {acc_upper}")
        urllib.request.urlretrieve(url, dest)
        return str(dest)
    except Exception as exc:
        log.error(f"[accession] {acc_upper}: download failed: {exc}")
        return None


def _resolve_accession_file(
    accession_info: Dict[str, str],
    work_base: Path,
    run_id: str,
    nf_bin: str,
    profile: str,
    env: dict,
    executor_config_path: Optional[Path],
) -> Optional[str]:
    """
    Dispatch to the appropriate download handler for a single accession.
    Returns the local file path (or samplesheet path for sequencing data), or None.
    """
    handler = accession_info["handler"]
    accession = accession_info["accession"]
    dl_dir = work_base / f"{run_id}_accession_downloads"

    if handler == "sequencing":
        return _run_fetchngs_prefetch(
            [accession], work_base, run_id, nf_bin, profile, env, executor_config_path
        )
    elif handler == "structure":
        return _download_pdb_structure(accession, dl_dir)
    elif handler == "protein_seq":
        return _download_uniprot_fasta(accession, dl_dir)
    elif handler == "genomic_ref":
        return _download_genomic_ref(accession, dl_dir)
    elif handler == "chemical":
        return _download_chemical_structure(accession, dl_dir)
    elif handler == "proteomics":
        # PRIDE datasets are large; provide the FTP URL as metadata instead of downloading
        log.info(
            f"[accession] {accession}: PRIDE download not automated. "
            f"Retrieve from https://www.ebi.ac.uk/pride/archive/projects/{accession}"
        )
        return None
    elif handler == "annotation":
        # Variant / clinical IDs are looked up online; no file to download
        log.info(f"[accession] {accession}: annotation-only ID ({accession_info['label']}) — no file to download")
        return None
    else:
        log.warning(f"[accession] Unknown handler '{handler}' for {accession}")
        return None


def _accession_chain_thread(
    *,
    run_id: str,
    accession_params: Dict[str, Dict[str, str]],  # param_key → accession_info
    remaining_params: Dict[str, Any],
    main_cmd: list[str],
    nf_bin: str,
    nf_path: Path,
    profile: str,
    work_base: Path,
    log_path: Path,
    trace_path: Path,
    env: dict,
    executor_config_path: Optional[Path],
) -> None:
    """
    Background thread: resolve all public-database accessions, substitute resolved
    file paths into the main Nextflow command, then launch and stream the main workflow.

    Status transitions: fetching_accessions → running (or failed).
    """
    def _set_status(status: str, **extra: Any) -> None:
        with _runs_lock:
            if run_id in _runs:
                _runs[run_id]["status"] = status
                _runs[run_id].update(extra)

    log.info(f"[accession chain run_id={run_id}] Starting accession resolution for params: {list(accession_params)}")

    # Resolve each accession-valued parameter to a local file path
    resolved: Dict[str, str] = {}
    any_sequencing = any(v["handler"] == "sequencing" for v in accession_params.values())

    if any_sequencing:
        # Batch all sequencing accessions into a single fetchngs run
        sequencing_keys = [k for k, v in accession_params.items() if v["handler"] == "sequencing"]
        seq_accessions = [accession_params[k]["accession"] for k in sequencing_keys]
        _set_status("fetching_accessions", accession_status="running fetchngs")

        samplesheet = _run_fetchngs_prefetch(
            seq_accessions, work_base, run_id, nf_bin, profile, env, executor_config_path
        )
        if samplesheet:
            # Map the first sequencing param → samplesheet; others get the same path
            for k in sequencing_keys:
                resolved[k] = samplesheet
            log.info(f"[accession chain run_id={run_id}] fetchngs done → {samplesheet}")
        else:
            _set_status("failed", error="fetchngs prefetch failed — check fetchngs logs")
            return

    # Resolve non-sequencing accessions individually
    for key, info in accession_params.items():
        if info["handler"] == "sequencing":
            continue  # already resolved above
        local_file = _resolve_accession_file(
            info, work_base, run_id, nf_bin, profile, env, executor_config_path
        )
        if local_file:
            resolved[key] = local_file
        else:
            # Non-sequencing download failures are warnings, not fatal — the main
            # workflow may have its own retrieval logic (e.g. alphafold with PDB id)
            log.warning(f"[accession chain run_id={run_id}] Could not resolve {info['accession']} for --{key}; passing original accession string")
            resolved[key] = info["accession"]

    # Substitute resolved paths into the main command
    # Replace "--<key> <original_accession>" with "--<key> <resolved_path>"
    substituted_cmd = []
    original_accession_values = {k: v["accession"] for k, v in accession_params.items()}
    i = 0
    while i < len(main_cmd):
        token = main_cmd[i]
        # Check if this is a --param flag whose value should be substituted
        if token.startswith("--") and i + 1 < len(main_cmd):
            param_name = token[2:]
            next_val = main_cmd[i + 1]
            if param_name in resolved and next_val.upper() == original_accession_values.get(param_name, "").upper():
                substituted_cmd.append(token)
                substituted_cmd.append(resolved[param_name])
                log.info(f"[accession chain run_id={run_id}] Substituted --{param_name}: {next_val!r} → {resolved[param_name]!r}")
                i += 2  # advance past both "--key" and old accession value
                continue
        substituted_cmd.append(token)
        i += 1

    _set_status("running", accession_status="launching main workflow")
    log.info(f"[accession chain run_id={run_id}] Launching main workflow: {' '.join(substituted_cmd)}")

    # Use the writable work_dir as cwd so Nextflow can write temp files and
    # bootstrap its .nextflow directory.  nf_path.parent is often read-only
    # inside the Galaxy container.
    chain_work_dir = work_base / run_id / "work"
    chain_work_dir.mkdir(parents=True, exist_ok=True)
    try:
        # FD-decouple: child writes stdout/stderr directly to log_path. DO NOT
        # REVERT to stdout=subprocess.PIPE — see _stream_logs for rationale and
        # docs/20260603_TIER0_COMPREHENSIVE_E2E_AND_DISPATCH_BUG.md.
        log_path.parent.mkdir(parents=True, exist_ok=True)
        _log_fh = open(log_path, "wb", buffering=0)
        process = subprocess.Popen(
            substituted_cmd,
            stdout=_log_fh,
            stderr=subprocess.STDOUT,
            cwd=str(chain_work_dir),
            env=env,
            start_new_session=True,
            close_fds=True,
        )
        _log_fh.close()  # child holds its own fd; parent doesn't need it
        with _runs_lock:
            if run_id in _runs:
                _runs[run_id]["process"] = process
    except Exception as exc:
        _set_status("failed", error=f"Failed to launch main workflow: {exc}")
        log.error(f"[accession chain run_id={run_id}] Launch error: {exc}")
        return

    _stream_logs(process, run_id, log_path)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post("/api/nextflow/execute", summary="Launch a Nextflow workflow")
def execute_nextflow(
    request: NextflowExecuteRequest,
) -> Dict[str, Any]:
    """
    Launch a Nextflow workflow by path.  Returns immediately with a run_id.
    The workflow runs as a background subprocess.
    """
    try:
        nf_path = _resolve_nextflow_path(request.nextflow_path)
    except FileNotFoundError as exc:
        raise HTTPException(
            status_code=404,
            detail=str(exc)
        )

    # Pre-flight: check if this pipeline can run on this host with these settings.
    params = dict(request.parameters or {})
    # `profile` and `executor` are Nextflow CLI / compute options — not pipeline params.
    # Passing them as --profile in the param loop breaks nf-core (duplicate -profile vs --profile).
    _param_profile = params.pop("profile", None)
    _param_executor = params.pop("executor", None)
    compute = dict(request.compute_config or {})
    if _param_executor and not compute.get("executor"):
        compute["executor"] = str(_param_executor)

    # Default to AWS Batch when NEXTFLOW_USE_AWS=true and no explicit executor is set.
    # This is the platform default: all workflows run on Batch unless explicitly overridden.
    _use_aws_env = os.environ.get("NEXTFLOW_USE_AWS", "false").lower() in ("true", "1", "yes")
    # Normalise user_id early for path construction (before run_id is generated)
    _uid_for_path = (request.user_id or "unknown").replace("/", "_").replace("..", "_")
    # Route to AWS Batch when NEXTFLOW_USE_AWS=true OR when executor is already "awsbatch"
    # (the frontend sends executor="awsbatch" by default as the platform standard).
    _executor_requested = compute.get("executor", "")
    if _use_aws_env or _executor_requested == "awsbatch":
        s3_bucket_default = os.environ.get("AWS_S3_BUCKET", "biomate-nextflow-work")
        run_uuid_short = str(uuid.uuid4())[:8]
        _auto_outdir = f"s3://{s3_bucket_default}/nextflow/outputs/{_uid_for_path}/{run_uuid_short}"
        if not params.get("outdir"):
            params["outdir"] = _auto_outdir
            log.info(
                f"[Nextflow] AWS Batch executor — auto-setting "
                f"outdir={_auto_outdir}"
            )
        compute["executor"] = "awsbatch"
        if not compute.get("s3_bucket"):
            compute["s3_bucket"] = s3_bucket_default

    # Auto-detect S3 outdir → route to AWS Batch automatically.
    # If the caller passes outdir=s3://..., we treat that as an implicit request
    # for cloud execution — no separate compute_config.executor needed.
    effective_outdir = params.get("outdir", "")
    is_s3 = str(effective_outdir).startswith("s3://")

    if is_s3:
        # Validate the bucket is reachable before launching anything.
        _validate_s3_url(effective_outdir)

        # Auto-upgrade to AWS Batch unless an explicit executor was already given.
        if not compute.get("executor"):
            compute["executor"] = "awsbatch"
            log.info(
                f"[Nextflow] S3 outdir '{effective_outdir}' detected — "
                "auto-selecting AWS Batch executor"
            )

        # Propagate bucket name so _generate_executor_config can set workDir.
        if not compute.get("s3_bucket"):
            compute["s3_bucket"] = effective_outdir.split("/")[2]  # s3://BUCKET/...

    # Auto-detect S3 inputs → also route to AWS Batch.
    # Nextflow stages S3 inputs natively on awsbatch; local executor cannot
    # reliably access S3 paths without the nf-amazon plugin + S3 workDir.
    s3_inputs = [
        v for k, v in params.items()
        if k != "outdir" and isinstance(v, str) and v.startswith("s3://")
    ]
    if s3_inputs:
        if not compute.get("executor"):
            compute["executor"] = "awsbatch"
            log.info(
                f"[Nextflow] S3 input(s) detected ({len(s3_inputs)}) — "
                "auto-selecting AWS Batch executor"
            )
        # Ensure outdir is also S3 when inputs are S3: Batch containers cannot
        # write publishDir to a local path on the head node.
        if not is_s3:
            s3_bucket_from_input = s3_inputs[0].split("/")[2]
            effective_outdir = (
                f"s3://{s3_bucket_from_input}/nextflow/outputs/{_uid_for_path}/"
                + str(uuid.uuid4())[:8]
            )
            is_s3 = True
            params["outdir"] = effective_outdir
            if not compute.get("s3_bucket"):
                compute["s3_bucket"] = s3_bucket_from_input
            log.info(
                f"[Nextflow] Auto-setting S3 outdir for S3 inputs: {effective_outdir}"
            )

    # Validate all input paths exist and total size ≤ 10 GB.
    _validate_input_paths(params)
    _validate_epitope_netmhc_params(nf_path, params)

    constraint = _check_pipeline_constraints(nf_path, params, compute)
    if constraint and constraint.get("blocked"):
        raise HTTPException(
            status_code=422,
            detail={
                "error": "Pipeline cannot run locally on this host",
                "reason": constraint["reason"],
                "suggestion": constraint["suggestion"],
                "mock_mode_available": constraint.get("mock_mode_available", False),
            },
        )

    # Generate unique IDs
    run_id = str(uuid.uuid4())
    invocation_id = str(uuid.uuid4())

    # Work / output directory (local staging area for logs and config files).
    work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
    log_dir = work_base / run_id
    log_dir.mkdir(parents=True, exist_ok=True)

    # If resuming, copy .nextflow/ cache from the previous run's work dir so
    # Nextflow recognises the project history and honours -resume.
    # Nextflow's CWD is work_dir (work/ subdir), so .nextflow/ lives inside work/.
    # Without this copy, Nextflow prints "never run this project before" and ignores -resume.
    _resume_nf_cache_src: Optional[Path] = None  # resolved after work_dir is created
    if request.resume_from_run_id:
        _prev_nf_cache = work_base / request.resume_from_run_id / "work" / ".nextflow"
        _resume_nf_cache_src = _prev_nf_cache if _prev_nf_cache.exists() else None
        if _resume_nf_cache_src is None:
            log.warning(
                "[Nextflow run %s] No .nextflow cache found at %s — "
                "-resume will be ignored by Nextflow; all tasks will re-run",
                run_id, _prev_nf_cache,
            )

    if is_s3:
        # S3 mode: outputs go to S3; local work_dir only used by Nextflow head process.
        outdir = effective_outdir   # pass through as-is
        work_dir = log_dir / "work"
        work_dir.mkdir(parents=True, exist_ok=True)
    else:
        outdir_path = work_base / run_id / "output"
        work_dir = work_base / run_id / "work"
        outdir_path.mkdir(parents=True, exist_ok=True)
        work_dir.mkdir(parents=True, exist_ok=True)
        outdir = str(outdir_path)

    # Detect whether any param contains multi-line content (inline CSV/SMILES/FASTA).
    # If so, write ALL params to a JSON file and use --params-file instead of individual
    # --key value flags. This avoids shell/Nextflow arg-parsing issues with newlines
    # embedded in command-line arguments.
    _has_multiline = any(
        isinstance(v, str) and "\n" in v for v in params.values()
    )

    # Build nextflow command
    try:
        nf_bin = _get_nextflow_bin()
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))

    cmd = [nf_bin, "run", str(nf_path)]

    # Entry selection: honor explicit request first; otherwise auto-detect for
    # scripts with named-only workflows (e.g. runnable subworkflows).
    selected_entry = (request.entry or "").strip() or _detect_nextflow_entry(nf_path)
    if selected_entry:
        cmd += ["-entry", selected_entry]

    # Resolve runtime environment using documented local Docker images first.
    # For awsbatch, skip -with-docker — the ECR container is set in the executor config;
    # passing -with-docker here would override the per-process ECR container directives.
    _executor_for_container = (compute or {}).get("executor", "")
    strategy = _choose_container_strategy(nf_path, request.nextflow_path)
    if _executor_for_container != "awsbatch" and strategy["mode"] == "docker" and strategy["image"]:
        cmd += ["-with-docker", strategy["image"]]
    elif _executor_for_container != "awsbatch" and strategy["missing_modules"]:
        raise HTTPException(
            status_code=503,
            detail=(
                "Missing required runtime modules and auto-install failed: "
                + ", ".join(strategy["missing_modules"])
            ),
        )

    # Profile — explicit request value wins; fall back to param then BIOMATE_NF_PROFILE env var.
    profile = request.profile or _param_profile or _default_nf_profile()
    cmd += ["-profile", profile]

    # Real-mode guard: for any non-mock profile, ensure mock_mode is off.
    # Workflows default params.mock_mode = true; command-line params override defaults.
    # This keeps the logic centralised here rather than scattered across workflow configs.
    _mock_profiles = {"standard", "test", "test_full", "test_cache"}
    if not any(p.strip() in _mock_profiles for p in profile.split(",")) and "mock_mode" not in params:
        params["mock_mode"] = False
        log.info(f"[Nextflow run {run_id}] profile={profile!r} → injecting --mock_mode false")

    # CryoSPARC connection params — inject from environment when running a CryoSPARC workflow.
    # The standard AI assistant chat path never calls /api/cryosparc/execute, so host/password
    # must be filled from env vars here; otherwise the Nextflow task defaults to localhost:30000
    # which is unreachable inside AWS Batch containers.
    if "cryosparc" in str(nf_path).lower():
        _cs_host = os.environ.get("CRYOSPARC_HOST", "")
        _cs_port = int(os.environ.get("CRYOSPARC_DIRECT_PORT", "30000"))
        _cs_email = os.environ.get("CRYOSPARC_EMAIL", "admin@biomate.ai")
        _cs_password = os.environ.get("CRYOSPARC_PASSWORD", "")
        _cs_license = os.environ.get("CRYOSPARC_LICENSE_ID", "")
        for _k, _v in [
            ("cryosparc_host", _cs_host),
            ("cryosparc_port", _cs_port),
            ("cryosparc_email", _cs_email),
            ("cryosparc_password", _cs_password),
            ("cryosparc_license", _cs_license),
        ]:
            if _v and _k not in params:
                params[_k] = _v
        log.info(f"[Nextflow run {run_id}] CryoSPARC params injected: host={_cs_host!r} port={_cs_port} email={_cs_email!r}")

    # Work directory — for awsbatch, the work dir must be S3 (set in executor config);
    # passing a local path via -w would override that and cause "S3 bucket required" errors.
    _executor = (compute or {}).get("executor", "")
    _s3_work_dir: str = ""  # set below for awsbatch; used in _runs registration
    if _executor == "awsbatch":
        s3_bucket_for_work = (
            (compute or {}).get("s3_bucket")
            or os.environ.get("NEXTFLOW_S3_BUCKET", "biomate-nextflow-work")
        )
        _s3_work_dir = f"s3://{s3_bucket_for_work}/nextflow/work/{_uid_for_path}/{run_id}"
        cmd += ["-w", _s3_work_dir]
    else:
        cmd += ["-w", str(work_dir)]

    # Nextflow -resume: reuse cached work from a prior run if requested.
    if request.resume_from_run_id:
        with _runs_lock:
            prev = _runs.get(request.resume_from_run_id, {})
        prev_work = prev.get("work_dir")
        # Fallback: reconstruct S3 work dir from the known naming pattern.
        # This works even after gunicorn restarts when _runs is empty.
        if not prev_work and is_s3:
            s3_bucket_resume = compute.get("s3_bucket", os.environ.get("AWS_S3_BUCKET", "biomate-nextflow-work"))
            prev_uid = (_uid_for_path)  # same user
            prev_work = f"s3://{s3_bucket_resume}/nextflow/work/{prev_uid}/{request.resume_from_run_id}"
            log.info(f"[Nextflow run {run_id}] Reconstructed prev work_dir={prev_work}")
        if prev_work:
            # Replace the already-added -w with the previous run's work dir so
            # Nextflow can find cached task results.  Do NOT append a second -w.
            try:
                w_idx = cmd.index("-w")
                cmd[w_idx + 1] = str(prev_work)
            except ValueError:
                cmd += ["-w", str(prev_work)]
            cmd.append("-resume")
            log.info(f"[Nextflow run {run_id}] Resuming from {request.resume_from_run_id}, work_dir={prev_work}")

    if _has_multiline:
        # One or more params contain embedded newlines (inline CSV/SMILES/FASTA).
        # Nextflow 25.x --params-file silently drops multi-line string values
        # (they arrive as null in params). Workaround: write multi-line values
        # into a Nextflow config file using triple-quoted Groovy strings, which
        # Nextflow reads correctly. Single-line params are passed as normal flags.
        _inline_cfg_lines = ["params {"]
        _scalar_params: dict = {}
        for key, value in params.items():
            if isinstance(value, str) and "\n" in value:
                # Escape any triple-quote sequences inside the content
                _safe_val = value.replace('"""', '\\"\\"\\"')
                _inline_cfg_lines.append(f'    {key} = """{_safe_val}"""')
                log.info(f"[Nextflow run {run_id}] inline multi-line param '{key}' → config block ({len(value)} chars)")
            else:
                _scalar_params[key] = value
        _inline_cfg_lines.append("}")
        _inline_cfg_path = log_dir / "biomate_inline_params.config"
        _inline_cfg_path.write_text("\n".join(_inline_cfg_lines) + "\n")
        cmd += ["-c", str(_inline_cfg_path)]
        log.info(f"[Nextflow run {run_id}] inline params config: {_inline_cfg_path}")
        # Also emit a params-file for audit purposes (scalar params only)
        import json as _ml_json
        _params_for_json = {}
        for key, value in _scalar_params.items():
            if isinstance(value, bool):
                _params_for_json[key] = value
            elif isinstance(value, (int, float)):
                _params_for_json[key] = value
            else:
                _params_for_json[key] = str(value)
        if "outdir" not in _params_for_json:
            _params_for_json["outdir"] = str(outdir)
        _params_json_path = log_dir / "nf-params.json"
        _params_json_path.write_text(_ml_json.dumps(_params_for_json, indent=2))
        cmd += ["--params-file", str(_params_json_path)]
        log.info(f"[Nextflow run {run_id}] --params-file (scalar only): {list(_params_for_json.keys())}")
    else:
        # Standard path: pass params as individual --key value flags.
        if "outdir" not in params:
            cmd += ["--outdir", str(outdir)]
        for key, value in params.items():
            if key == "outdir":
                cmd += ["--outdir", str(value)]
            elif isinstance(value, bool):
                cmd += [f"--{key}", "true" if value else "false"]
            else:
                cmd += [f"--{key}", str(value)]

    log.info(f"[Nextflow run {run_id}] cmd: {' '.join(cmd)}")
    log.info(f"[Nextflow run {run_id}] outdir: {outdir}")
    if selected_entry:
        log.info(f"[Nextflow run {run_id}] entry: {selected_entry}")

    log_path = log_dir / "nextflow.log"
    trace_path = log_dir / "workflow-trace.txt"
    cmd += ["-with-trace", str(trace_path)]

    # Environment — strip BASH_FUNC_* (bash completion exports break AWS Batch .command.sh)
    env = _sanitize_subprocess_env()
    # SHARED NXF_HOME — was per-run, causing 16 concurrent NF heads to all
    # download the same nf-amazon plugin to their own private dirs and race
    # on plugin-jar extraction (similar mechanism to the AWS CRT race below).
    # /opt/nextflow is created by the Dockerfile, contains the pre-fetched
    # framework jar at /opt/nextflow/framework/25.10.5/. Plugins land in
    # /opt/nextflow/plugins/ — read-only after first download. NF's plugin
    # loader is safe for many concurrent readers, races only on first write.
    # Subsequent runs find the cache warm and skip download entirely.
    env["NXF_HOME"] = "/opt/nextflow"

    # Plugin pre-warm. DO NOT REVERT — without this, each run starts with an
    # empty {NXF_HOME}/plugins dir and Nextflow attempts to download nf-amazon
    # at startup. The download fails on the dev EC2 (FileMutex lock contention
    # + intermittent registry timeouts), Nextflow exits returncode=1 before
    # submitting Phase A. Pre-seed from the image-baked shared cache.
    # See docs/20260603_TIER0_COMPREHENSIVE_E2E_AND_DISPATCH_BUG.md.
    _nxf_shared = Path("/app/.nextflow-shared")
    if _nxf_shared.is_dir():
        import shutil as _shutil
        _run_nf_home = log_dir / ".nextflow"
        for _src_name in ("plugins", "framework"):
            _src = _nxf_shared / _src_name
            _dst = _run_nf_home / _src_name
            if not _src.is_dir():
                continue
            # Bug fix (2026-06-05): the previous guard was `not _dst.exists()`,
            # but in practice the empty `.nextflow/plugins/` dir already exists
            # by the time we get here (created by earlier work_dir setup or a
            # prior failed attempt at this run_id). copytree was being skipped,
            # plugins ended up empty, Nextflow then tried to download
            # nf-amazon@3.4.4 from the public registry — which 404s because
            # 3.4.4 is no longer published (latest: 3.1.0) — and crashed at
            # CmdRun before submitting Phase A. Observed live on dev runs
            # 15632954, d568eb1e, etc. Now: treat empty dst as "not warmed"
            # and force the copy.
            try:
                if _dst.exists() and any(_dst.iterdir()):
                    # Real prior content — assume valid, leave alone.
                    continue
                if _dst.exists():
                    # Empty stub — remove so copytree can recreate.
                    _shutil.rmtree(str(_dst))
                _dst.parent.mkdir(parents=True, exist_ok=True)
                _shutil.copytree(str(_src), str(_dst))
                log.info("[Nextflow run %s] pre-warmed %s from /app/.nextflow-shared", run_id, _src_name)
            except Exception as _e:
                log.warning("[Nextflow run %s] plugin pre-warm copy failed for %s: %s", run_id, _src_name, _e)


    if strategy["mode"] == "docker" and strategy["docker_opts"]:
        env["NXF_DOCKER_OPTS"] = strategy["docker_opts"]
    # All workflows use System.getenv('NEXTFLOW_USE_AWS') to select ECR vs local containers.
    # Set it whenever we're running on AWS Batch so every .nf file picks the correct ECR image.
    if compute.get("executor") == "awsbatch":
        env["NEXTFLOW_USE_AWS"] = "true"

    # AWS CRT SIGSEGV mitigation. Use a SHARED CRT cache dir, NOT per-run.
    # Per-run was the old mitigation (each NF head extracts its own .so).
    # That works for sequential fires (one extraction at a time) but with
    # 16 concurrent NF heads, all 16 race-extract the same .so file from
    # the shaded jar to their own per-run dirs, and the kernel-level file-
    # extraction race triggers the dlopen SIGSEGV on at least 15/16 of them
    # (empirical 2026-06-06 sweep: 15/16 SIGABRT at parallel fire).
    # Shared cache: first NF head on a freshly-booted Galaxy extracts once
    # to /opt/nextflow/.aws-crt-cache; all subsequent heads find the .so
    # already there and skip extraction (NF's CRT loader checks for an
    # existing file before re-extracting). No race after the first run.
    # Pre-warm at Galaxy boot would eliminate even the first-run risk; for
    # now the empirical "first run after boot is single-fire" pattern is
    # enough to keep the cache warm for the rest of the day.
    # The cache is read-only after extraction → safe for many concurrent
    # readers. Same .so is what every NF run loads regardless.
    _shared_crt_cache = Path("/opt/nextflow/.aws-crt-cache")
    _shared_crt_cache.mkdir(parents=True, exist_ok=True)
    _existing_nxf_opts = env.get("NXF_OPTS", "")
    # Cap head JVM heap at 512 MB. The head process only parses the workflow,
    # submits Batch jobs, then polls task state + streams logs — most memory
    # is wasted on JVM defaults (NF defaults to -Xmx5g). 512 MB is comfortable
    # for pipelines with up to ~200 concurrent tasks; raise via BIOMATE_NF_HEAP
    # if a specific pipeline ever needs more. Halving per-head footprint lets
    # us run 2x more concurrent workflows on the same host.
    _heap = os.environ.get("BIOMATE_NF_HEAP", "512m")
    _crt_opts = (
        f"-Xms128m -Xmx{_heap} "
        f"-Daws.crt.lib.dir={_shared_crt_cache} "
        f"-Daws.crt.disable.crt.in.client=true -Xss2m"
    )
    env["NXF_OPTS"] = f"{_existing_nxf_opts} {_crt_opts}".strip()

    # Additional glibc-side mitigation. The CRT crash on Debian trixie's
    # glibc 2.41 + OpenJDK 21.0.11 is in ld-linux's lazy symbol-resolution
    # path (`ld-linux-x86-64.so.2+0x2475a`). Forcing eager binding at dlopen
    # time (LD_BIND_NOW=1) skips the lazy resolution that triggers the
    # SIGSEGV. Adds tiny startup latency, no behavioural change for the
    # rest of the run. Independent of NXF_OPTS — applies to ANY dlopen
    # the Nextflow head does, including the CRT native lib extraction.
    # Pair with the existing NXF_OPTS CRT cache + Xss2m mitigations.
    env["LD_BIND_NOW"] = "1"

    # Compute config overrides: generate a real nextflow.config for non-local executors.
    # NXF_EXECUTOR is not a valid Nextflow env var — executor must be set in a config file.
    billing_user_id = _uid_for_path  # same sanitised value used in S3 path construction
    executor_config_path = _generate_executor_config(
        compute, log_dir, user_id=billing_user_id, run_id=run_id,
        credentials=dict(request.credentials or {}),
        nf_path=str(nf_path),
    )
    if executor_config_path:
        cmd += ["-c", str(executor_config_path)]

    # Validate qc_overrides and qc_profile if provided
    qc_overrides = request.qc_overrides or {}
    qc_profile = request.qc_profile or None
    workflow_domain = request.workflow_domain or "unknown"
    try:
        from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler
        # Auto-infer qc_profile from workflow path when not explicitly provided
        if not qc_profile:
            qc_profile = NextflowQCGateHandler.infer_qc_profile(str(nf_path))
            if qc_profile:
                log.info(f"[QC] Auto-selected profile '{qc_profile}' for {nf_path}")
        if qc_overrides:
            valid, errors = NextflowQCGateHandler.validate_qc_overrides(qc_overrides)
            if not valid:
                raise HTTPException(
                    status_code=422,
                    detail={"error": "Invalid qc_overrides", "errors": errors}
                )
        if qc_profile:
            valid, errors = NextflowQCGateHandler.validate_qc_profile(qc_profile)
            if not valid:
                raise HTTPException(
                    status_code=422,
                    detail={"error": "Unknown qc_profile", "errors": errors}
                )
    except ImportError:
        log.warning("[QC] QC gate handler not available — skipping override/profile validation")

    _is_batch = compute.get("executor") == "awsbatch"

    # ── Detect public-database accessions in parameters ───────────────────────
    # If any parameter value is a recognised accession (SRA, PDB, UniProt, etc.)
    # we launch an accession-chain thread that first downloads / resolves the data,
    # then substitutes the local path into the Nextflow command and runs the workflow.
    # This avoids the 422 "path does not exist" error for accession-valued params.
    accession_params: Dict[str, Dict[str, str]] = {}
    for key, value in params.items():
        if key == "outdir":
            continue
        info = _classify_accession(str(value))
        if info:
            accession_params[key] = info
            log.info(
                f"[Nextflow run {run_id}] Detected {info['label']} accession in "
                f"--{key}: {info['accession']} (handler={info['handler']})"
            )

    initial_status = "fetching_accessions" if accession_params else "running"

    # Friendly chat-progress: tell the user we got their workflow.
    # Skip if no invocation_id (some legacy paths don't have one) — narrator
    # needs an inv ID to route the SSE event to the right chat session.
    if invocation_id:
        _narrate_chat(invocation_id, "workflow.submitted", {"run_id": run_id, "workflow": str(nf_path)})

    # Register run before starting any thread so status endpoint returns immediately.
    # Capture started_at once so _runs and timing.json use the identical timestamp.
    _started_at_now = time.time()
    with _runs_lock:
        _runs[run_id] = {
            "run_id": run_id,
            "invocation_id": invocation_id,
            "status": initial_status,
            "returncode": None,
            "outdir": str(outdir),
            "log_path": str(log_path),
            "trace_path": str(trace_path),
            "nextflow_path": str(nf_path),
            "profile": profile,
            "qc_overrides": qc_overrides,
            "qc_profile": qc_profile,
            "workflow_domain": workflow_domain,
            "work_dir": _s3_work_dir if _s3_work_dir else str(work_dir),
            "runtime_mode": strategy["mode"],
            "runtime_image": strategy["image"],
            "entry": selected_entry,
            "required_modules": strategy["required_modules"],
            "missing_modules": strategy["missing_modules"],
            "host_arch": strategy.get("host_arch"),
            "image_arch": strategy.get("image_arch"),
            "is_batch": _is_batch,
            "user_id": request.user_id or "anonymous",
            "is_pilot": bool(request.is_pilot),
            "started_at": _started_at_now,
            # Accession metadata (empty dict when not applicable)
            "accession_params": {k: v["label"] for k, v in accession_params.items()},
        }

    # Persist timing to disk so other gunicorn workers can read it via the disk fallback.
    try:
        import json as _json
        _timing_path = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs")) / run_id / "timing.json"
        _timing_path.parent.mkdir(parents=True, exist_ok=True)
        _timing_path.write_text(_json.dumps({
            "started_at": _started_at_now,
            "outdir": str(outdir),
            "workflow_domain": workflow_domain or "",
            "nextflow_path": request.nextflow_path or str(nf_path),
        }))
    except Exception as _te:
        log.debug("[timing] Could not write timing.json for %s: %s", run_id, _te)

    if accession_params:
        # Accession path: run download pre-step then main workflow in one thread
        t = threading.Thread(
            target=_accession_chain_thread,
            kwargs={
                "run_id": run_id,
                "accession_params": accession_params,
                "remaining_params": {k: v for k, v in params.items() if k not in accession_params},
                "main_cmd": cmd,
                "nf_bin": nf_bin,
                "nf_path": nf_path,
                "profile": profile,
                "work_base": work_base,
                "log_path": log_path,
                "trace_path": trace_path,
                "env": env,
                "executor_config_path": executor_config_path,
            },
            daemon=True,
            name=f"nf-acc-{run_id[:8]}",
        )
        t.start()
        # QC monitor is started here; the chain thread will launch the Nextflow
        # process internally, but the monitor waits for the trace file to appear.
        _start_qc_monitor(
            invocation_id=invocation_id,
            work_dir=work_dir,
            qc_overrides=qc_overrides,
            workflow_domain=workflow_domain,
            qc_profile=qc_profile,
            trace_path=trace_path,
            is_batch=_is_batch,
            s3_outdir=str(outdir) if _is_batch and str(outdir).startswith("s3://") else None,
        )
        return {
            "success": True,
            "run_id": run_id,
            "invocation_id": invocation_id,
            "status": "fetching_accessions",
            "accessions": {k: v["label"] for k, v in accession_params.items()},
            "outputs": {"outdir": str(outdir)},
            "runtime": {
                "mode": strategy["mode"],
                "image": strategy["image"],
                "entry": selected_entry,
            },
            "message": (
                f"Downloading {len(accession_params)} accession(s) before launching workflow "
                f"(run_id: {run_id})"
            ),
        }

    # ── Normal path: no accessions — launch Nextflow directly ────────────────
    # Copy .nextflow/ cache into the CWD (work_dir) so -resume finds history.
    if request.resume_from_run_id and _resume_nf_cache_src is not None:
        import shutil as _shutil
        _dest_nf = work_dir / ".nextflow"
        if not _dest_nf.exists():
            try:
                _shutil.copytree(str(_resume_nf_cache_src), str(_dest_nf))
                log.info(
                    "[Nextflow run %s] Copied .nextflow cache from %s/work/.nextflow → work/.nextflow",
                    run_id, request.resume_from_run_id,
                )
            except Exception as _e:
                log.warning("[Nextflow run %s] Could not copy .nextflow cache: %s", run_id, _e)

    # Use the writable work_dir as cwd — nf_path.parent is read-only in container.
    try:
        # FD-decouple: child writes stdout/stderr directly to log_path. DO NOT
        # REVERT to stdout=subprocess.PIPE — that pattern blocks the Nextflow
        # JVM on a full pipe buffer when the gunicorn worker recycles, killing
        # the run ~60s after Phase A submits. See _stream_logs and
        # docs/20260603_TIER0_COMPREHENSIVE_E2E_AND_DISPATCH_BUG.md.
        log_path.parent.mkdir(parents=True, exist_ok=True)
        # Bounded concurrency: block here until a slot frees up. Prevents
        # OOM-kill of the Galaxy container when many submissions arrive at once.
        # Slot is released by a background reaper when the NF head process exits
        # (see thread spawned below).
        _slot_acquired = _nf_launch_semaphore.acquire(timeout=300)
        if not _slot_acquired:
            log.error(
                f"[Nextflow run {run_id}] timed out waiting for launch slot "
                f"(>{_nf_max_concurrent} concurrent runs in flight for >5min)"
            )
            raise HTTPException(
                status_code=503,
                detail=(
                    "Too many concurrent Nextflow runs in flight. "
                    "Wait for some to complete and retry."
                ),
            )
        _log_fh = open(log_path, "wb", buffering=0)
        process = subprocess.Popen(
            cmd,
            stdout=_log_fh,
            stderr=subprocess.STDOUT,
            cwd=str(work_dir),
            env=env,
            start_new_session=True,
            close_fds=True,
        )
        _log_fh.close()  # child holds its own fd; parent doesn't need it
        # Release the semaphore slot when the head process exits.
        def _release_slot(p: subprocess.Popen, rid: str) -> None:
            try:
                p.wait()
            finally:
                try:
                    _nf_launch_semaphore.release()
                    log.info(f"[Nextflow run {rid}] launch slot released")
                except ValueError:
                    pass  # already released
        threading.Thread(
            target=_release_slot, args=(process, run_id),
            daemon=True, name=f"nf-slot-{run_id[:8]}",
        ).start()
    except HTTPException:
        raise
    except Exception as exc:
        # Release the slot we may have acquired before the failure.
        if _slot_acquired:
            try: _nf_launch_semaphore.release()
            except ValueError: pass
        log.error(f"[Nextflow run {run_id}] failed to launch: {exc}")
        raise HTTPException(status_code=500, detail=f"Failed to launch Nextflow: {exc}")

    # Stream logs in background
    t = threading.Thread(
        target=_stream_logs,
        args=(process, run_id, log_path),
        daemon=True,
        name=f"nf-log-{run_id[:8]}",
    )
    t.start()

    # QC monitoring thread — reads trace file and fires QC gate events
    _start_qc_monitor(
        invocation_id=invocation_id,
        work_dir=work_dir,
        qc_overrides=qc_overrides,
        workflow_domain=workflow_domain,
        qc_profile=qc_profile,
        trace_path=trace_path,
        is_batch=_is_batch,
        s3_outdir=str(outdir) if _is_batch and str(outdir).startswith("s3://") else None,
    )

    return {
        "success": True,
        "run_id": run_id,
        "invocation_id": invocation_id,
        "status": "running",
        "outputs": {
            "outdir": str(outdir),
        },
        "runtime": {
            "mode": strategy["mode"],
            "image": strategy["image"],
            "entry": selected_entry,
            "required_modules": strategy["required_modules"],
            "missing_modules": strategy["missing_modules"],
            "host_arch": strategy.get("host_arch"),
            "image_arch": strategy.get("image_arch"),
            "cross_arch_allowed": strategy.get("cross_arch_allowed"),
        },
        "message": f"Nextflow workflow started (run_id: {run_id})",
    }


class ResumeRunRequest(BaseModel):
    # Optional nextflow_path sent by routes.ts when _runs may be empty
    # (multi-worker: the original run was registered in a different gunicorn worker)
    nextflow_path: Optional[str] = None
    is_batch: Optional[bool] = None       # True → awsbatch/S3 resume; None → auto-detect
    user_id: Optional[str] = None         # needed to reconstruct S3 work dir after restart
    parameters: Optional[Dict[str, Any]] = None  # forwarded to execute_nextflow


def _steps_from_db_metadata(nextflow_path: str) -> Dict[str, Any]:
    """Build viewer steps from the collected DB step_metadata (per-step phase /
    visualizations / QC / outputs). Robust for non-main Bioconductor workflows whose
    .nf parse comes up short or whose file isn't on this host."""
    import sqlite3, json as _json, re as _re
    from pathlib import Path as _Path
    out: Dict[str, Any] = {}
    try:
        m = _re.search(r"/bioconductor/([^/]+)/([^/]+)\.nf$", nextflow_path)
        if not m:
            return out
        db = _Path(__file__).resolve().parents[5] / "database" / "galaxy_ai_tools.db"
        if not db.exists():
            return out
        conn = sqlite3.connect(str(db))
        row = conn.execute(
            "SELECT step_metadata FROM workflows WHERE source='bioconductor' "
            "AND filename LIKE ? LIMIT 1", (f"%/{m.group(1)}/{m.group(2)}.nf",)).fetchone()
        conn.close()
        meta = _json.loads(row[0]) if row and row[0] else None
        if not isinstance(meta, list):
            return out
        for i, s in enumerate(meta):
            nm = (s.get("step") or f"Step {i + 1}").strip()
            out[str(i)] = {
                "id": str(i), "name": nm, "annotation": nm, "description": nm,
                "tool_id": _re.sub(r"[^A-Za-z0-9]+", "_", nm).upper()[:48],
                "type": "tool", "parameters": {}, "inputs": {},
                "phase_group": s.get("phase", "") or "", "phase_label": s.get("phase", "") or "",
                "visualizations": s.get("visualizations", []) or [],
                "qc": s.get("qc", []) or [], "outputs": s.get("outputs", []) or [],
            }
    except Exception:
        return {}
    return out


@router.get("/api/nextflow/steps", summary="Parse workflow phase steps from a .nf file")
def get_nextflow_steps(nextflow_path: str = "") -> Dict[str, Any]:
    """
    Return the phase steps for a Nextflow workflow file.
    Used by the viewer to lazy-load steps when the stored workflowDefinition
    was created before steps were available (e.g. older sessions).
    """
    from galaxy.webapps.galaxy.api.ai_assistant import _parse_nextflow_steps
    if not nextflow_path:
        raise HTTPException(status_code=400, detail="nextflow_path is required")
    steps = _parse_nextflow_steps(nextflow_path)
    # Prefer the COLLECTED DB step_metadata for Bioconductor workflows: it is the curated,
    # enriched source carrying per-step visualizations + QC (which the .nf parser does not
    # emit), and it also covers non-main workflows whose .nf isn't on this host. Whenever the
    # DB has step_metadata for this path it wins; the parser stays the fallback for everything
    # else (nf-core / drug_discovery / non-indexed paths -> _steps_from_db_metadata returns {}).
    db_steps = _steps_from_db_metadata(nextflow_path)
    if db_steps:
        steps = db_steps
    return {"steps": steps, "count": len(steps)}


@router.post("/api/nextflow/resume/{run_id}", summary="Resume a Nextflow run with -resume")
def resume_nextflow_run(run_id: str, body: ResumeRunRequest = ResumeRunRequest()) -> Dict[str, Any]:
    """
    Re-launch a previous Nextflow run with ``-resume``, reusing its work
    directory so all already-cached tasks are skipped.  Returns a new run_id.

    Multi-worker safe: if the run is not in this worker's _runs dict (it was
    registered in a different gunicorn worker), falls back to reconstructing
    the work directory from disk at NEXTFLOW_WORK_DIR/<run_id>/work.

    Called by the frontend "Run Step" / "Rerun Step" button in the per-step
    execution panel of nextflow-workflow-viewer.tsx.
    """
    with _runs_lock:
        prev = dict(_runs.get(run_id, {}))

    if not prev:
        nextflow_path = body.nextflow_path
        if not nextflow_path:
            raise HTTPException(
                status_code=404,
                detail=(
                    f"Run {run_id!r} not found in this worker's run registry. "
                    "Provide nextflow_path in the request body to resume."
                ),
            )
        # Determine if this was a Batch (S3) run.
        # body.is_batch=True forces Batch mode; None → auto-detect via env var default.
        _force_batch = body.is_batch
        if _force_batch is None:
            _nf_profile = os.environ.get("BIOMATE_NF_PROFILE", "")
            _force_batch = "batch" in _nf_profile or "awsbatch" in _nf_profile
        if not _force_batch:
            # Local fallback: check disk
            work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
            candidate_work_dir = work_base / run_id / "work"
            if not candidate_work_dir.exists():
                # No disk dir and not forced batch — still try batch if NEXTFLOW_S3_BUCKET set
                _force_batch = bool(os.environ.get("NEXTFLOW_S3_BUCKET") or os.environ.get("AWS_S3_BUCKET"))
        prev = {
            "nextflow_path": nextflow_path,
            "work_dir": None,  # execute_nextflow will reconstruct S3 path via resume_from_run_id
            "is_batch": _force_batch,
            "profile": None,
            "entry": None,
            "workflow_domain": None,
            "user_id": body.user_id,
        }
        log.info(
            f"[resume/{run_id}] _runs miss — reconstructed: nextflow_path={nextflow_path} is_batch={_force_batch} user_id={body.user_id!r}"
        )

    resume_request = NextflowExecuteRequest(
        nextflow_path=prev["nextflow_path"],
        profile=prev.get("profile"),
        entry=prev.get("entry"),
        workflow_domain=prev.get("workflow_domain"),
        user_id=prev.get("user_id") or body.user_id,
        parameters=body.parameters or None,
        resume_from_run_id=run_id,
        compute_config=(
            {"executor": "awsbatch"} if prev.get("is_batch") else None
        ),
    )

    # Friendly chat-progress: a -resume with new params is the auto-loop /
    # manual retry kicking in. Emit on the ORIGINAL invocation_id so the line
    # lands in the same chat session that originated the run.
    _prev_inv = prev.get("invocation_id")
    if _prev_inv and body.parameters:
        _changes = {k: v for k, v in (body.parameters or {}).items() if not str(k).startswith("__")}
        _narrate_chat(_prev_inv, "workflow.autoloop_started", {"changes": _changes, "resumed_from": run_id})

    return execute_nextflow(resume_request)


def _find_nextflow_pids_for_run(run_id: str) -> List[int]:
    """Find Nextflow java PIDs that have this run_id in their command line.
    Survives the multi-worker gunicorn case where the subprocess is owned by
    a different worker than the one handling the cancel/pause request."""
    import shutil, subprocess as _subprocess
    pgrep = shutil.which("pgrep")
    if not pgrep:
        return []
    try:
        out = _subprocess.run([pgrep, "-f", run_id], capture_output=True, text=True, timeout=5)
        pids = [int(p) for p in out.stdout.split() if p.strip().isdigit()]
        nf_pids: List[int] = []
        import re as _re
        # Tight match: only Java processes running a `nextflow*.jar` AND
        # carrying the run_id in their command line. Filters out incidental
        # processes that happen to mention "nextflow" or the run_id in env.
        nf_jar_re = _re.compile(r"nextflow[\-\w\.]*\.jar")
        for pid in pids:
            try:
                with open(f"/proc/{pid}/cmdline", "rb") as fh:
                    cmdline = fh.read().decode("utf-8", errors="replace")
                # Replace NULs from /proc/.../cmdline for regex matching.
                cmdline_str = cmdline.replace("\x00", " ")
                if nf_jar_re.search(cmdline_str) and run_id in cmdline_str:
                    nf_pids.append(pid)
            except OSError:
                continue
        return nf_pids
    except Exception as exc:
        log.debug("pgrep lookup for run_id=%s failed: %s", run_id, exc)
        return []


def _terminate_run_process(run_id: str, soft: bool = False) -> Dict[str, Any]:
    """
    Actually terminate the local Nextflow subprocess for a run_id.

    soft=False → cancel: SIGTERM, then SIGKILL after 5s; mark status=cancelled.
    soft=True  → pause:  same termination, but mark status=paused so a later
                          /api/nextflow/resume can pick up where -resume
                          left off (Nextflow's task cache survives).

    Multi-worker safe: if the run's process handle is not in this worker's
    _runs dict, falls back to a system-level pgrep of the run_id in the Java
    process command line, then os.kill.
    """
    invocation_id: Optional[str] = None
    proc: Optional[subprocess.Popen] = None
    info: Optional[Dict[str, Any]] = None

    with _runs_lock:
        info = _runs.get(run_id)
        if info:
            invocation_id = info.get("invocation_id")
            proc = info.get("process")

    pids_terminated: List[int] = []
    note: str

    if proc is not None:
        rc = proc.poll()
        if rc is not None:
            return {"run_id": run_id, "ok": True, "status": info.get("status") if info else None, "note": "already-exited"}
        try:
            proc.terminate()
            try:
                proc.wait(timeout=5.0)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2.0)
            pids_terminated.append(proc.pid)
            note = "by-handle"
        except Exception as exc:
            log.warning("[Nextflow run %s] proc.terminate failed: %s", run_id, exc)
            note = "handle-error"
    else:
        # Multi-worker fallback: find the Nextflow Java PID by run_id match.
        import os as _os
        import signal as _signal
        pids = _find_nextflow_pids_for_run(run_id)
        for pid in pids:
            try:
                _os.kill(pid, _signal.SIGTERM)
                pids_terminated.append(pid)
            except OSError as exc:
                log.debug("SIGTERM to pid=%s failed: %s", pid, exc)
        if pids_terminated:
            time.sleep(5.0)
            for pid in list(pids_terminated):
                try:
                    _os.kill(pid, 0)
                    _os.kill(pid, _signal.SIGKILL)
                except OSError:
                    pass
            note = "by-pgrep"
        else:
            note = "no-process-found"

    with _runs_lock:
        if run_id in _runs:
            _runs[run_id]["status"] = "paused" if soft else "cancelled"
            _runs[run_id]["completed_at"] = time.time()

    if invocation_id:
        _narrate_chat(
            invocation_id,
            "workflow.paused" if soft else "workflow.cancelled",
            {"reason": "by user", "terminated_pids": pids_terminated},
        )

    return {
        "run_id": run_id, "ok": True,
        "status": "paused" if soft else "cancelled",
        "terminated_pids": pids_terminated,
        "note": note,
    }


@router.post("/api/nextflow/cancel/{run_id}", summary="Cancel a running Nextflow run (terminates local subprocess)")
def cancel_nextflow_run(run_id: str) -> Dict[str, Any]:
    """Terminate the Nextflow subprocess for a run_id and mark status=cancelled.

    Multi-worker note: if the run was registered in a different gunicorn worker
    this worker's _runs dict won't have the process handle. We mark status
    anyway so the frontend gets a terminal signal, and the workflow naturally
    completes (Nextflow can't be told to stop from outside its own process).
    """
    return _terminate_run_process(run_id, soft=False)


@router.post("/api/nextflow/pause/{run_id}", summary="Pause a running Nextflow run (terminates with -resume cache intact)")
def pause_nextflow_run(run_id: str) -> Dict[str, Any]:
    """Soft-cancel a Nextflow run, keeping the work-dir intact so the user
    can later POST /api/nextflow/resume/{run_id} to pick up via -resume.

    Nextflow has no native pause-mid-run. This is the honest semantic: we kill
    the local Nextflow process so it stops submitting new tasks; already-running
    tasks (e.g. AWS Batch jobs in-flight) will complete on their own and cache
    in the work dir. A subsequent resume reuses the cache and re-launches only
    what's missing.
    """
    return _terminate_run_process(run_id, soft=True)


@router.get("/api/nextflow/status/{run_id}", summary="Get Nextflow run status")
def get_nextflow_status(
    run_id: str,
) -> Dict[str, Any]:
    """Return current status of a Nextflow run."""
    with _runs_lock:
        info = _runs.get(run_id)

    if info is not None:
        info = _apply_disk_timing_terminal_state(info, run_id)

    if info is None:
        # Fallback: run may have been started in a different gunicorn worker.
        # gunicorn --workers 4 creates 4 separate Python processes each with their own
        # _runs dict. If the execute request hit Worker A and this status request hits
        # Worker B, _runs.get(run_id) returns None. Reconstruct status from disk.
        work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
        log_dir = work_base / run_id
        output_dir = log_dir / "output"
        log_path_fallback = log_dir / "nextflow.log"
        # Read persisted timing (written by execute_nextflow on start/end).
        _disk_timing: Dict[str, Any] = {}
        _timing_path_fb = log_dir / "timing.json"
        if _timing_path_fb.exists():
            try:
                import json as _json
                _disk_timing = _json.loads(_timing_path_fb.read_text())
            except Exception:
                pass
        _fb_started_at: Optional[float] = _disk_timing.get("started_at")
        _fb_completed_at: Optional[float] = _disk_timing.get("completed_at")
        _fb_duration_s: Optional[int] = None
        if _fb_started_at:
            _end = _fb_completed_at if _fb_completed_at else time.time()
            _fb_duration_s = int(_end - _fb_started_at)
        log_tail_fallback: list = []
        log_full_text = ""
        if log_dir.exists():
            try:
                log_full_text, log_tail_fallback = _read_run_nextflow_log_text(log_dir)
            except Exception:
                pass
        if output_dir.exists():
            # Use the Nextflow log as the primary completion signal.
            # Nextflow writes pipeline_info/ as soon as execution starts, so we cannot
            # rely on directory presence alone — the run may still be in progress.
            nf_done = "Execution complete" in log_full_text
            nf_failed_log = _log_indicates_nextflow_failure(
                log_full_text, log_tail_fallback,
            )
            if not nf_done and not nf_failed_log:
                # Log doesn't yet show completion → run is still in progress.
                return {
                    "run_id": run_id,
                    "invocation_id": run_id,
                    "status": "running",
                    "returncode": None,
                    "outdir": str(output_dir),
                    "work_dir": str(log_dir / "work"),
                    "log_tail": log_tail_fallback,
                    "is_batch": False,
                    "s3_output_files": [],
                    "completedSteps": 0,
                    "totalSteps": 0,
                    "progressPercent": 50,
                    "processes": [],
                    "started_at": _fb_started_at,
                    "completed_at": None,
                    "duration_s": _fb_duration_s,
                }

            # Nextflow finished. Check whether result directories were produced.
            nf_internal = {"pipeline_info"}
            real_subdirs = [
                d for d in output_dir.iterdir()
                if d.is_dir() and d.name not in nf_internal
            ] if output_dir.is_dir() else []
            has_results = len(real_subdirs) > 0

            fallback_status = "succeeded" if has_results else "failed"
            if fallback_status == "succeeded" and _looks_like_false_success(
                log_full_text=log_full_text,
                log_tail=log_tail_fallback,
                total_steps=0,
                duration_s=_fb_duration_s,
                s3_output_files=[],
                workflow_domain=_disk_timing.get("workflow_domain", ""),
                nextflow_path=_disk_timing.get("nextflow_path", ""),
            ):
                fallback_status = "failed"
            return {
                "run_id": run_id,
                "invocation_id": run_id,
                "status": fallback_status,
                "returncode": 0 if fallback_status == "succeeded" else 1,
                "outdir": str(output_dir),
                "work_dir": str(log_dir / "work"),
                "log_tail": log_tail_fallback,
                "is_batch": False,
                "s3_output_files": [],
                "completedSteps": 0,
                "totalSteps": 0,
                "progressPercent": 100,
                "processes": [],
                "started_at": _fb_started_at,
                "completed_at": _fb_completed_at,
                "duration_s": _fb_duration_s,
            }
        elif log_dir.exists():
            # Log dir exists but no local output dir.
            # For AWS Batch runs, outdir is S3 — check workflow-trace.txt + timing.json
            # to determine if the Nextflow process actually finished.
            trace_done, trace_failed, completed_steps_fb, _failed_fb, total_steps_fb = (
                _evaluate_workflow_trace_terminal(log_dir, log_full_text, log_tail_fallback)
            )

            # Also treat timing.json with completed_at as a done signal
            if (
                not trace_done
                and _fb_completed_at
                and _looks_like_log_stream_orphan_failure(_disk_timing)
                and _revive_orphan_nextflow_run(run_id)
            ):
                _fb_completed_at = None
            if not trace_done and _fb_completed_at:
                trace_done = True
                trace_failed = (
                    _disk_timing.get("status") in ("failed", "interrupted")
                    or (_disk_timing.get("returncode") not in (0, None))
                    or _log_indicates_nextflow_failure(log_full_text, log_tail_fallback)
                )

            # Read S3 outdir from timing.json (written at run start with the actual S3 path).
            # Fallback: scan config file (legacy runs that predate timing.json outdir field).
            _s3_outdir: Optional[str] = _disk_timing.get("outdir") or None
            if _s3_outdir and not _s3_outdir.startswith("s3://"):
                _s3_outdir = None   # local path — not useful here
            if not _s3_outdir:
                _config_path = log_dir / "biomate_executor_override.config"
                if _config_path.exists():
                    try:
                        _cfg = _config_path.read_text()
                        import re as _re
                        m = _re.search(r"outdir\s*=\s*['\"]?(s3://[^\s'\"]+)", _cfg)
                        if m:
                            _s3_outdir = m.group(1)
                    except Exception:
                        pass

            if trace_done:
                # List S3 output files for completed AWS Batch runs
                _s3_files_fb: list = []
                if _s3_outdir:
                    try:
                        import subprocess as _sp
                        _ls = _sp.run(
                            [_aws_cli_bin(), "s3", "ls", _s3_outdir + "/", "--recursive"],
                            capture_output=True, text=True, timeout=10,
                        )
                        for _line in _ls.stdout.splitlines():
                            parts = _line.split()
                            if len(parts) >= 4:
                                _key = parts[3]
                                _s3_files_fb.append({
                                    "s3_uri": f"s3://{_s3_outdir.split('s3://')[1].split('/')[0]}/{_key}",
                                    "filename": _key.split("/")[-1],
                                    "size": int(parts[2]) if parts[2].isdigit() else 0,
                                })
                    except Exception:
                        pass
                if not trace_failed and _looks_like_false_success(
                    log_full_text=log_full_text,
                    log_tail=log_tail_fallback,
                    total_steps=total_steps_fb,
                    duration_s=_fb_duration_s,
                    s3_output_files=_s3_files_fb,
                    workflow_domain=_disk_timing.get("workflow_domain", ""),
                    nextflow_path=_disk_timing.get("nextflow_path", ""),
                ):
                    trace_failed = True
                _fb_processes = _build_processes_from_s3_files(
                    _s3_files_fb, _s3_outdir or "", _disk_timing.get("workflow_domain", "")
                ) if _s3_files_fb and _s3_outdir else []
                if trace_failed and _looks_like_false_failure(
                    log_full_text=log_full_text,
                    log_tail=log_tail_fallback,
                    returncode=1,
                    s3_output_files=_s3_files_fb,
                    processes=_fb_processes,
                ):
                    trace_failed = False
                _fb_final_status = "failed" if trace_failed else "succeeded"
                return {
                    "run_id": run_id,
                    "invocation_id": run_id,
                    "status": _fb_final_status,
                    "returncode": 1 if trace_failed else 0,
                    "outdir": _s3_outdir or str(output_dir),
                    "work_dir": str(log_dir / "work"),
                    "log_tail": log_tail_fallback,
                    "is_batch": bool(_s3_outdir),
                    "s3_output_files": _s3_files_fb,
                    "completedSteps": completed_steps_fb,
                    "totalSteps": total_steps_fb,
                    "progressPercent": 100,
                    "processes": _fb_processes,
                    "started_at": _fb_started_at,
                    "completed_at": _fb_completed_at or time.time(),
                    "duration_s": _fb_duration_s,
                }

            # S3 completion heuristic: if ≥3 output files exist and the run has been going
            # for >5 min without a Nextflow "Execution complete" log, treat as completed.
            # This handles the race where Nextflow exits cleanly but its log line is read
            # before the final write, leaving the executor stuck in "running" indefinitely.
            if _s3_outdir and _fb_started_at:
                import subprocess as _sp_h
                # Defensive: if the aws CLI isn't installed in the Galaxy
                # container (stale image without the Dockerfile's
                # /opt/aws-cli install step), don't 500 the entire status
                # endpoint — every poll would crash with
                # FileNotFoundError: [Errno 2] No such file or directory:
                # 'aws'. Prefer the self-contained absolute path Galaxy's
                # Dockerfile installs to (/opt/aws-cli/bin/aws), then PATH
                # lookup, then bail gracefully.
                _h_files = []
                try:
                    _h_ls = _sp_h.run(
                        [_aws_cli_bin(), "s3", "ls", _s3_outdir + "/", "--recursive"],
                        capture_output=True, text=True, timeout=10,
                    )
                except FileNotFoundError:
                    log.warning(
                        "[Nextflow] aws CLI not available for S3 completion heuristic "
                        "(neither /opt/aws-cli/bin/aws nor PATH lookup found). "
                        "Status endpoint will continue without S3-based terminal detection."
                    )
                    _h_ls = None
                except Exception as _h_ls_err:
                    log.warning("[Nextflow] aws s3 ls failed for heuristic: %s", _h_ls_err)
                    _h_ls = None
                for _hl in (_h_ls.stdout.splitlines() if _h_ls else []):
                    _hp = _hl.split()
                    if len(_hp) >= 4:
                        _hf = _hp[3].split("/")[-1]
                        _he = _hf.rsplit(".", 1)[-1].lower() if "." in _hf else ""
                        if _he in {"json", "csv", "html", "png", "pdf"}:
                            _h_files.append({"s3_uri": f"s3://{_s3_outdir.split('s3://')[1].split('/')[0]}/{_hp[3]}", "filename": _hf, "size": int(_hp[2]) if _hp[2].isdigit() else 0})
                _h_elapsed = time.time() - _fb_started_at
                if len(_h_files) >= 3 and _h_elapsed > 300:
                    if _looks_like_false_success(
                        log_full_text=log_full_text,
                        log_tail=log_tail_fallback,
                        total_steps=0,
                        duration_s=int(_h_elapsed),
                        s3_output_files=_h_files,
                        workflow_domain=_disk_timing.get("workflow_domain", ""),
                        nextflow_path=_disk_timing.get("nextflow_path", ""),
                    ):
                        log.warning(
                            "[Nextflow] S3 completion heuristic suppressed for %s (false success)",
                            run_id,
                        )
                    else:
                        log.info("[Nextflow] S3 completion heuristic: %d files, %.0fs elapsed — marking completed", len(_h_files), _h_elapsed)
                        _fb_procs_h = _build_processes_from_s3_files(_h_files, _s3_outdir, "")
                        return {
                            "run_id": run_id, "invocation_id": run_id,
                            "status": "completed", "returncode": 0,
                            "outdir": _s3_outdir, "work_dir": str(log_dir / "work"),
                            "log_tail": log_tail_fallback, "is_batch": True,
                            "s3_output_files": _h_files, "completedSteps": len(_h_files),
                            "totalSteps": len(_h_files), "progressPercent": 100,
                            "processes": _fb_procs_h, "started_at": _fb_started_at,
                            "completed_at": time.time(), "duration_s": int(_h_elapsed),
                        }

            # Still running — list intermediate S3 outputs so the UI can show them
            _running_s3_files: list = []
            if _s3_outdir:
                try:
                    import subprocess as _sp
                    _ls_run = _sp.run(
                        [_aws_cli_bin(), "s3", "ls", _s3_outdir + "/", "--recursive"],
                        capture_output=True, text=True, timeout=10,
                    )
                    for _line in _ls_run.stdout.splitlines():
                        _parts = _line.split()
                        if len(_parts) >= 4:
                            _key = _parts[3]
                            _fname = _key.split("/")[-1]
                            _ext = _fname.rsplit(".", 1)[-1].lower() if "." in _fname else ""
                            # Only surface user-facing output files, skip empty/internal
                            if _ext and _ext not in {"txt", "html", "dot", "yml", "run", "sh", "log", "err", "out", "env", "trace"}:
                                _running_s3_files.append({
                                    "s3_uri": f"s3://{_s3_outdir.split('s3://')[1].split('/')[0]}/{_key}",
                                    "filename": _fname,
                                    "size": int(_parts[2]) if _parts[2].isdigit() else 0,
                                })
                except Exception:
                    pass
            _running_processes = _build_processes_from_s3_files(
                _running_s3_files, _s3_outdir or "", _disk_timing.get("workflow_domain", "")
            ) if _running_s3_files and _s3_outdir else []
            return {
                "run_id": run_id,
                "invocation_id": run_id,
                "status": "running",
                "returncode": None,
                "outdir": _s3_outdir or str(output_dir),
                "work_dir": str(log_dir / "work"),
                "log_tail": log_tail_fallback,
                "is_batch": bool(_s3_outdir),
                "s3_output_files": _running_s3_files,
                "completedSteps": completed_steps_fb,
                "totalSteps": total_steps_fb,
                "progressPercent": 50 if total_steps_fb == 0 else int(100 * completed_steps_fb / total_steps_fb),
                "processes": _running_processes,
                "started_at": _fb_started_at,
                "completed_at": None,
                "duration_s": _fb_duration_s,
            }
        raise HTTPException(status_code=404, detail=f"Run not found: {run_id}")

    # Read last few lines of log for progress info
    log_tail: list = []
    log_path = Path(info.get("log_path", ""))
    log_full_text = ""
    log_dir = log_path.parent if log_path else Path("")
    if log_dir.is_dir():
        try:
            log_full_text, log_tail = _read_run_nextflow_log_text(log_dir)
        except Exception:
            pass
    elif log_path.exists():
        try:
            with open(log_path) as fh:
                lines = fh.readlines()
            log_full_text = "".join(lines)
            log_tail = [c for l in lines[-40:] if (c := _clean_log_line(l))][-20:]
        except Exception:
            pass

    # Stale in-memory "running" after Nextflow exited on another worker or log landed in work/.nextflow.log
    if info.get("status") == "running" and log_dir.is_dir():
        trace_done, trace_failed, _, _, _ = _evaluate_workflow_trace_terminal(
            log_dir, log_full_text, log_tail,
        )
        if trace_done and trace_failed:
            info = dict(info)
            info["status"] = "failed"
            info["returncode"] = 1
            info["completed_at"] = info.get("completed_at") or time.time()

    # Parse trace file for task-level progress
    trace_path = Path(info.get("trace_path", ""))
    progress = _parse_trace_progress(trace_path)

    s3_files = info.get("s3_output_files", [])
    outdir = info.get("outdir", "")
    workflow_domain = info.get("workflow_domain", "")

    _info_status_early = info.get("status", "running")
    if (
        not s3_files
        and str(outdir).startswith("s3://")
        and _info_status_early in ("failed", "succeeded", "completed", "running")
    ):
        try:
            s3_files = _list_s3_output_files(outdir)
        except Exception:
            pass

    # Build step-level processes from S3 output files.
    # If the trace produced real process entries, annotate them with matching S3 files.
    # If the trace is empty/sparse (e.g. CryoSPARC-via-Nextflow where Batch jobs exit
    # after submitting CryoSPARC jobs), build entirely from S3 directory structure.
    trace_processes = progress.get("processes", [])
    # For cryo_em: trace process names (e.g. PATCH_MOTION_CORRECTION_BATCH) don't
    # match output directory names (e.g. 02_motion_correction). The S3-dir builder
    # uses _CRYOSPARC_S3_DIR_TO_STEP for correct mapping, so prefer it when files exist.
    if workflow_domain == "cryo_em" and s3_files and outdir:
        processes = _build_processes_from_s3_files(s3_files, outdir, workflow_domain)
    elif trace_processes:
        for proc in trace_processes:
            proc_name = proc["name"].split(":")[-1]
            matched_files = [
                f for f in s3_files
                if f"/{proc_name}/" in f.get("s3_uri", "") or
                   f"/{proc_name.lower()}/" in f.get("s3_uri", "")
            ]
            proc["outputs"] = matched_files
            # Viewer's nfProcessByName lookup reads `task_files` (array of s3 URIs)
            # and indexes by lowercase name/process/id — emit the short snake_cased
            # form so phase.id like "import_movies" matches.
            proc["task_files"] = [m.get("s3_uri", "") for m in matched_files if m.get("s3_uri")]
            short = proc_name.lower()
            proc["process"] = short
            if not proc.get("id"):
                proc["id"] = short
        processes = trace_processes
    elif s3_files and outdir:
        processes = _build_processes_from_s3_files(s3_files, outdir, workflow_domain)
    else:
        processes = []

    progress = {**progress, "processes": processes}
    work_dir = info.get("work_dir", "")

    started_at: Optional[float] = info.get("started_at")
    completed_at: Optional[float] = info.get("completed_at")
    now = time.time()
    duration_s: Optional[int] = None
    if started_at:
        end = completed_at if completed_at else now
        duration_s = int(end - started_at)

    # S3 completion heuristic for Batch runs stuck in "running":
    # EventBridge sometimes fails to update status after Nextflow exits.
    # If ≥3 JSON/CSV output files exist AND >5 min elapsed → treat as completed.
    _info_status = info.get("status", "running")
    if _info_status == "running" and s3_files and started_at:
        _s3_data_files = [f for f in s3_files
                          if str(f.get("filename", "")).rsplit(".", 1)[-1].lower() in {"json", "csv", "html", "png", "pdf"}]
        _elapsed = now - started_at
        if len(_s3_data_files) >= 3 and _elapsed > 300:
            if not _looks_like_false_success(
                log_full_text=log_full_text,
                log_tail=log_tail,
                total_steps=progress.get("totalTasks", progress.get("totalSteps", 0)),
                duration_s=int(_elapsed),
                s3_output_files=s3_files,
                workflow_domain=workflow_domain,
                nextflow_path=info.get("nextflow_path", ""),
            ):
                log.info("[Nextflow] S3 completion heuristic (normal path): %d files, %.0fs → completed", len(_s3_data_files), _elapsed)
                _info_status = "completed"
                completed_at = completed_at or now

    if _info_status in ("succeeded", "completed") and _looks_like_false_success(
        log_full_text=log_full_text,
        log_tail=log_tail,
        total_steps=progress.get("totalTasks", progress.get("totalSteps", 0)),
        duration_s=duration_s,
        s3_output_files=s3_files,
        workflow_domain=workflow_domain,
        nextflow_path=info.get("nextflow_path", ""),
    ):
        log.warning(
            "[Nextflow] Downgrading false success for run %s (steps=%s, duration=%ss, outputs=%d)",
            run_id,
            progress.get("totalTasks", progress.get("totalSteps", 0)),
            duration_s,
            len(s3_files),
        )
        _info_status = "failed"

    _info_returncode = info.get("returncode")
    if _info_status == "failed" and _info_returncode in (0, None):
        _info_returncode = 1

    if _info_status == "failed" and _looks_like_false_failure(
        log_full_text=log_full_text,
        log_tail=log_tail,
        returncode=_info_returncode if _info_returncode is not None else info.get("returncode"),
        s3_output_files=s3_files,
        processes=processes,
    ):
        log.warning(
            "[Nextflow] Upgrading false failure for run %s (outputs=%d, processes=%d)",
            run_id,
            len(_non_pipeline_info_s3_outputs(s3_files)),
            len(processes),
        )
        _info_status = "succeeded"
        _info_returncode = 0

    # Build QC report from S3 JSON report files when run is terminal
    qc_report: Optional[Dict] = None
    if _info_status in ("succeeded", "completed") and s3_files and outdir:
        try:
            qc_report = _build_qc_report_from_s3_files(s3_files, outdir)
        except Exception:
            pass

    return {
        "run_id": run_id,
        "invocation_id": info["invocation_id"],
        "status": _info_status,
        "returncode": _info_returncode,
        "outdir": outdir,
        "work_dir": work_dir,
        "log_tail": log_tail,
        "is_batch": info.get("is_batch", False),
        "s3_output_files": s3_files,
        "qc_report": qc_report,
        "qc_gates": info.get("qc_gates", []),  # gate failures from S3 post-run evaluation
        "started_at": started_at,
        "completed_at": completed_at,
        "duration_s": duration_s,
        **progress,
    }


@router.get("/api/nextflow/outputs/download", summary="Generate presigned download URL for S3 output")
def download_s3_output(
    s3_uri: str,
    run_id: str,
    presigned_only: int = 0,
) -> Any:
    """
    Generate a presigned S3 GET URL for a workflow output file.

    Security: the requested s3_uri must belong to the outdir of the given run_id.
    Returns a 302 redirect to the presigned URL (15-minute expiry).
    If presigned_only=1, returns JSON {"url": "..."} instead of redirecting.
    """
    from starlette.responses import RedirectResponse

    with _runs_lock:
        info = _runs.get(run_id)
    if info is None:
        # Same multi-worker fallback as get_nextflow_status: reconstruct from disk
        work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
        output_dir = work_base / run_id / "output"
        if output_dir.exists():
            info = {"outdir": str(output_dir), "invocation_id": run_id}
        else:
            raise HTTPException(status_code=404, detail=f"Run not found: {run_id}")

    outdir = str(info.get("outdir", ""))
    if not outdir.startswith("s3://"):
        raise HTTPException(status_code=400, detail="This run does not have S3 outputs.")

    # Auth guard: requested key must be within this run's outdir.
    if not s3_uri.startswith(outdir.rstrip("/") + "/"):
        raise HTTPException(
            status_code=403,
            detail="Requested S3 key is not within this run's output directory.",
        )

    try:
        import boto3
        parts = s3_uri[len("s3://"):].split("/", 1)
        bucket, key = parts[0], parts[1]
        s3 = boto3.client("s3", region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
        url = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": bucket, "Key": key},
            ExpiresIn=900,  # 15 minutes
        )
        if presigned_only:
            return {"url": url}
        return RedirectResponse(url, status_code=302)
    except ImportError:
        raise HTTPException(status_code=503, detail="boto3 not installed — S3 downloads unavailable.")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to generate presigned URL: {exc}")


@router.get("/api/nextflow/runs/{run_id}/output_files", summary="List output files with presigned download URLs")
def list_run_output_files(run_id: str) -> Any:
    """
    List all output files for a completed run, with presigned S3 download URLs.
    Returns [{name, s3_uri, size, extension, download_url}].
    """
    with _runs_lock:
        info = _runs.get(run_id)
    if info is None:
        work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
        output_dir = work_base / run_id / "output"
        if output_dir.exists():
            # Local run — list files directly
            files = []
            for f in sorted(output_dir.rglob("*")):
                if f.is_file():
                    name = f.name
                    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
                    files.append({
                        "name": name,
                        "s3_uri": None,
                        "size": f.stat().st_size,
                        "extension": ext,
                        "download_url": f"/api/nextflow/outputs/download?s3_uri={str(f)}&run_id={run_id}",
                    })
            return {"run_id": run_id, "files": files}
        raise HTTPException(status_code=404, detail=f"Run not found: {run_id}")

    outdir = str(info.get("outdir", ""))
    if not outdir.startswith("s3://"):
        return {"run_id": run_id, "files": [], "note": "Local run — no S3 outputs"}

    raw_files = _list_s3_output_files(outdir)
    if not raw_files:
        return {"run_id": run_id, "files": []}

    # Generate presigned URLs for each file
    try:
        import boto3
        s3 = boto3.client("s3", region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
    except ImportError:
        return {"run_id": run_id, "files": raw_files, "note": "boto3 not available — no download URLs"}

    enriched = []
    for f in raw_files:
        s3_uri = f["s3_uri"]
        try:
            parts = s3_uri[len("s3://"):].split("/", 1)
            bucket, key = parts[0], parts[1]
            url = s3.generate_presigned_url(
                "get_object",
                Params={"Bucket": bucket, "Key": key},
                ExpiresIn=3600,  # 1 hour
            )
        except Exception:
            url = None
        enriched.append({**f, "download_url": url})

    return {"run_id": run_id, "files": enriched}


@router.get("/api/qc/profiles", summary="List available named QC profiles")
async def list_qc_profiles() -> Dict[str, Any]:
    """
    Return all available named QC profiles (Layer 3 — curated threshold sets).

    Each profile includes:
      - id:          str  — profile identifier for use in qc_profile field
      - description: str  — human-readable summary
      - domain_hint: str  — primary workflow domain
      - overrides:   dict — threshold keys and values applied when profile is selected
      - references:  list — primary literature / guideline citations

    This is an async endpoint so it runs in the event loop (not the thread pool),
    ensuring it responds quickly even when worker threads are busy with AI calls.
    """
    try:
        from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler, QC_RED_LINES
        profiles = NextflowQCGateHandler.list_profiles()
        defaults = QC_RED_LINES
    except ImportError:
        profiles = []
        defaults = {}
    return {
        "profiles": profiles,
        "count": len(profiles),
        "defaults": defaults,
    }


@router.get("/api/invocations/{invocation_id}/qc-events",
            summary="Get QC event log for a workflow invocation")
def get_invocation_qc_events(
    invocation_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
):
    """
    Return all QC gate and warning events recorded for a workflow invocation.

    Includes:
    - All blocking gate events (type='gate') with failures, metrics, suggestions
    - All near-threshold warning events (type='warning')
    - A methods_text paragraph suitable for inserting into paper methods sections
    - Summary counts (gates_triggered, warnings_emitted)
    """
    try:
        from galaxy.jobs.runners.nextflow_monitor import get_monitor_service
        monitor_service = get_monitor_service(trans.app)

        # Try integer lookup first (Galaxy invocation IDs), then string
        monitor = None
        for key in (invocation_id, int(invocation_id) if invocation_id.isdigit() else None):
            if key is None:
                continue
            monitor = monitor_service.monitors.get(key)
            if monitor:
                break

        if monitor is None or monitor.qc_handler is None:
            # Attempt to locate a persisted JSONL audit log even if monitor is gone
            import json as _json
            jobs_dir = getattr(getattr(trans.app, 'config', None), 'root', None)
            if jobs_dir:
                from pathlib import Path as _Path
                audit_path = (_Path(jobs_dir) / 'database' / 'jobs_directory'
                              / 'nextflow_workflows' / f"workflow_{invocation_id}"
                              / "qc_overrides_audit.jsonl")
                if audit_path.exists():
                    entries = []
                    for line in audit_path.read_text().splitlines():
                        try:
                            entries.append(_json.loads(line))
                        except Exception:
                            pass
                    return {
                        "invocation_id": invocation_id,
                        "source": "audit_jsonl",
                        "gates_triggered": sum(1 for e in entries if e.get("event_type") == "gate_triggered"),
                        "warnings_emitted": 0,
                        "events": entries,
                        "methods_text": "QC governance applied (see audit log for details).",
                    }
            return {
                "invocation_id": invocation_id,
                "source": "not_found",
                "gates_triggered": 0,
                "warnings_emitted": 0,
                "events": [],
                "methods_text": "No QC events recorded for this invocation.",
            }

        report = monitor.qc_handler.get_qc_report()
        report["source"] = "live_monitor"
        return report

    except Exception as e:
        log.error(f"[QC Events] Failed to retrieve events for {invocation_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to retrieve QC events: {e}")


@router.get("/api/invocations/{invocation_id}/qc-audit-download",
            summary="Download QC audit log as JSONL")
def download_invocation_qc_audit(
    invocation_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
):
    """
    Download the full QC event log for a workflow invocation as a JSONL file.
    Each line is a JSON object representing one QC event.
    """
    import json as _json
    try:
        from galaxy.jobs.runners.nextflow_monitor import get_monitor_service
        monitor_service = get_monitor_service(trans.app)

        monitor = None
        for key in (invocation_id, int(invocation_id) if invocation_id.isdigit() else None):
            if key is None:
                continue
            monitor = monitor_service.monitors.get(key)
            if monitor:
                break

        events: list = []
        if monitor is not None and monitor.qc_handler is not None:
            report = monitor.qc_handler.get_qc_report()
            events = report.get("events", [])
        else:
            jobs_dir = getattr(getattr(trans.app, 'config', None), 'root', None)
            if jobs_dir:
                from pathlib import Path as _Path
                audit_path = (_Path(jobs_dir) / 'database' / 'jobs_directory'
                              / 'nextflow_workflows' / f"workflow_{invocation_id}"
                              / "qc_overrides_audit.jsonl")
                if audit_path.exists():
                    for line in audit_path.read_text().splitlines():
                        try:
                            events.append(_json.loads(line))
                        except Exception:
                            pass

        lines = "\n".join(_json.dumps(e) for e in events)
        return Response(
            content=lines,
            media_type="application/x-ndjson",
            headers={
                "Content-Disposition": f'attachment; filename="qc_audit_{invocation_id}.jsonl"',
            },
        )

    except Exception as e:
        log.error(f"[QC Audit Download] Failed for {invocation_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to download QC audit: {e}")


@router.get("/api/invocations/{invocation_id}/autoloop-suggestions",
            summary="Return auto-loop remediation suggestions for a workflow invocation")
def get_autoloop_suggestions(
    invocation_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
):
    """
    Return the latest auto-loop remediation suggestions computed during QC monitoring.

    These are produced when a drug-discovery phase (ADMET, docking, CYP DDI, NCA-PK)
    fails its auto-loop gates.  Each suggestion contains:
    - domain: which auto-loop package flagged the failure
    - phase: which phase failed
    - failed_gates: list of gate names that triggered HALT
    - remediations: list of EnrichedRemediation dicts (param_changes + rationale + citations)

    Returns 404 when no suggestions are available (phase passed or not yet evaluated).
    """
    try:
        from experiments.autoloop_bridge import get_suggestions
    except ImportError:
        raise HTTPException(status_code=503, detail="Auto-loop bridge not available")

    suggestions = get_suggestions(invocation_id)
    if suggestions is None:
        raise HTTPException(
            status_code=404,
            detail=f"No auto-loop suggestions for invocation {invocation_id!r} — phase passed or not yet evaluated",
        )
    return {"invocation_id": invocation_id, **suggestions}


@router.post("/api/invocations/{invocation_id}/autoloop-dismiss",
             summary="Dismiss (clear) auto-loop suggestions for an invocation")
def dismiss_autoloop_suggestions(
    invocation_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
):
    """
    Clear stored auto-loop suggestions for an invocation.

    Call this after the user has acknowledged or applied the suggestions so they
    don't reappear on the next page load.
    """
    try:
        from experiments.autoloop_bridge import pop_suggestions
    except ImportError:
        raise HTTPException(status_code=503, detail="Auto-loop bridge not available")

    popped = pop_suggestions(invocation_id)
    return {"invocation_id": invocation_id, "cleared": popped is not None}


@router.get("/api/invocations/{invocation_id}/software",
            summary="Per-run software versions for the AfterRunReport Software tab")
def get_invocation_software(invocation_id: str) -> Dict[str, Any]:
    """
    Walk a completed run's work directory for ``**/versions.yml`` files (the
    nf-core / Nextflow module convention) and merge them into a flat
    ``{tool_name: version}`` dict. Prefers the consolidated
    ``pipeline_info/software_versions.yml`` when present (single nf-core file).

    Returns ``{"versions": {tool: ver}, "count": N}``. Empty dict + 200 OK
    when nothing found — the AfterRunReport's Software tab hides itself in
    that case.
    """
    import glob as _glob
    import yaml as _yaml

    run = _runs.get(invocation_id) or {}
    workdir = run.get("nextflowOutputDir") or run.get("work_dir") or \
        os.path.join("/tmp/nextflow_runs", invocation_id)

    versions: dict = {}

    # Prefer the nf-core consolidated file when present.
    consolidated = os.path.join(workdir, "pipeline_info", "software_versions.yml")
    if os.path.exists(consolidated):
        try:
            with open(consolidated) as fh:
                parsed = _yaml.safe_load(fh) or {}
            for section, tools in parsed.items():
                if isinstance(tools, dict):
                    for k, v in tools.items():
                        versions[str(k)] = str(v)
                else:
                    versions[str(section)] = str(tools)
        except Exception:
            pass

    # Fall back: glob the work dir for any versions.yml emitted by modules.
    if not versions and os.path.isdir(workdir):
        for path in _glob.glob(os.path.join(workdir, "**", "versions.yml"), recursive=True):
            try:
                with open(path) as fh:
                    parsed = _yaml.safe_load(fh) or {}
                for section, tools in parsed.items():
                    if isinstance(tools, dict):
                        for k, v in tools.items():
                            versions[str(k)] = str(v)
                    else:
                        versions[str(section)] = str(tools)
            except Exception:
                continue

    return {"versions": versions, "count": len(versions)}


# Workflow-name → qc_evidence domain. Substring match isn't enough
# (e.g. cryosparc_standard_spa has tokens {cryosparc, standard, spa} which
# don't intersect {cryo, em}). Map covers the realistic mismatches.
_WORKFLOW_DOMAIN_ALIASES: Dict[str, str] = {
    # cryo-EM
    "cryosparc": "cryo_em", "spa": "cryo_em", "cryolo": "cryo_em",
    "topaz": "cryo_em", "motioncor": "cryo_em", "ctf": "cryo_em",
    "relion": "cryo_em", "helical": "cryo_em",
    # cryo-ET
    "tomo": "cryo_et", "warp": "cryo_et", "aretomo": "cryo_et",
    # drug discovery sub-domains → admet / docking / cyp_ddi / pbpk / nca_pk
    "predict_admet": "admet", "tox": "admet",
    "vina": "docking", "glide": "docking", "diffdock": "docking", "moe": "docking",
    "cyp": "cyp_ddi", "ddi": "cyp_ddi", "transporter": "cyp_ddi",
    "pbpk": "pbpk", "pk_sim": "pbpk",
    "nca": "nca_pk", "pknca": "nca_pk", "nonmem": "nca_pk", "nlmixr": "nca_pk",
    "amber": "structure_prediction", "gromacs": "structure_prediction",
    "alphafold": "structure_prediction", "boltz": "structure_prediction",
    "chai": "structure_prediction", "esmfold": "structure_prediction",
    # clinical / pharmacology
    "boin": "clinical_trial", "trial_sim": "clinical_trial",
    "ich_s5": "ich_s5", "ich_s7": "ich_s7",
}


def _resolve_qc_evidence_domain(workflow_name: str, available_domains: list) -> Optional[str]:
    """Pick the best-matching qc_evidence domain for a workflow name.
    Returns None when no plausible match — citations endpoint then returns empty."""
    import re as _re
    wf_low = workflow_name.lower()
    # 1) Direct alias hit
    for keyword, domain in _WORKFLOW_DOMAIN_ALIASES.items():
        if keyword in wf_low and domain in available_domains:
            return domain
    # 2) Substring match: any domain name whose normalised form appears in wf_name
    for domain in available_domains:
        d_norm = domain.replace("_", "").lower()
        if d_norm and d_norm in wf_low.replace("_", "").replace("-", ""):
            return domain
    # 3) Token-intersection fallback
    wf_tokens = set(_re.split(r"[_\-./]", wf_low))
    for domain in available_domains:
        if set(_re.split(r"[_\-]", domain.lower())) & wf_tokens:
            return domain
    return None


@router.get("/api/workflows/{workflow_name}/citations",
            summary="Workflow-level paper citations for the AfterRunReport Citations tab")
def get_workflow_citations(workflow_name: str) -> Dict[str, Any]:
    """
    Assemble citations for a workflow from qc_evidence.yaml.

    qc_evidence.yaml shape is ``{domain: {gate_name: [{paper_doi, paper_ref, ...}, ...]}}``.
    For each evidence item in any gate of the matching domain we emit one
    citation with the DOI deduped across items.

    Returns ``{"citations": [{title, doi, url}], "count": N}``. Empty list +
    HTTP 200 when no qc_evidence domain matches — Citations tab then hides.
    """
    import yaml as _yaml

    citations: list = []
    seen_dois: set = set()

    qc_evidence_path = os.path.normpath(os.path.join(
        os.path.dirname(__file__), "..", "..", "..", "..", "..", "config", "qc_evidence.yaml"
    ))
    if not os.path.exists(qc_evidence_path):
        return {"citations": [], "count": 0}

    try:
        with open(qc_evidence_path) as fh:
            ev = _yaml.safe_load(fh) or {}
    except Exception:
        return {"citations": [], "count": 0}

    domain = _resolve_qc_evidence_domain(workflow_name, list(ev.keys()))
    if not domain:
        return {"citations": [], "count": 0}

    section = ev.get(domain) or {}
    if not isinstance(section, dict):
        return {"citations": [], "count": 0}

    # Each gate maps to a list of evidence items; each item has paper_ref +
    # paper_doi (plus paper_supports, finding, etc. we don't need here).
    for gate_name, items in section.items():
        if not isinstance(items, list):
            continue
        for item in items:
            if not isinstance(item, dict):
                continue
            doi = item.get("paper_doi")
            ref = item.get("paper_ref")
            # Skip rows without enough info to render.
            if not (doi or ref):
                continue
            key = doi or ref
            if key in seen_dois:
                continue
            seen_dois.add(key)
            citations.append({
                "title": ref or gate_name,
                "doi": doi,
                "url": f"https://doi.org/{doi}" if doi else None,
                "gate": gate_name,
            })

    return {"citations": citations, "count": len(citations), "domain": domain}


@router.get("/api/invocations/{invocation_id}/methods-report",
            summary="Download methods report as plain text")
def download_invocation_methods_report(
    invocation_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
):
    """
    Download a plain-text methods report for a workflow invocation.
    Includes run ID, invocation ID, date, tool versions (if available),
    and the QC methods_text paragraph.
    """
    import json as _json
    from datetime import datetime as _datetime
    try:
        from galaxy.jobs.runners.nextflow_monitor import get_monitor_service
        monitor_service = get_monitor_service(trans.app)

        monitor = None
        for key in (invocation_id, int(invocation_id) if invocation_id.isdigit() else None):
            if key is None:
                continue
            monitor = monitor_service.monitors.get(key)
            if monitor:
                break

        methods_text = "No QC events recorded for this invocation."
        tool_versions: dict = {}
        run_id = "n/a"

        if monitor is not None and monitor.qc_handler is not None:
            report = monitor.qc_handler.get_qc_report()
            methods_text = report.get("methods_text", methods_text)
            for event in report.get("events", []):
                tv = event.get("tool_versions") or event.get("versions")
                if tv and isinstance(tv, dict):
                    tool_versions.update(tv)
        else:
            jobs_dir = getattr(getattr(trans.app, 'config', None), 'root', None)
            if jobs_dir:
                from pathlib import Path as _Path
                audit_path = (_Path(jobs_dir) / 'database' / 'jobs_directory'
                              / 'nextflow_workflows' / f"workflow_{invocation_id}"
                              / "qc_overrides_audit.jsonl")
                if audit_path.exists():
                    methods_text = "QC governance applied (see audit log for details)."
                    for line in audit_path.read_text().splitlines():
                        try:
                            event = _json.loads(line)
                            tv = event.get("tool_versions") or event.get("versions")
                            if tv and isinstance(tv, dict):
                                tool_versions.update(tv)
                            if event.get("run_id"):
                                run_id = event["run_id"]
                        except Exception:
                            pass

        # Look up run_id from in-process registry
        if run_id == "n/a":
            with _runs_lock:
                for rid, info in _runs.items():
                    if info.get("invocation_id") == invocation_id:
                        run_id = rid
                        break

        lines = [
            "BioMate AI — Methods Report",
            "=" * 40,
            f"Date:          {_datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}",
            f"Invocation ID: {invocation_id}",
            f"Run ID:        {run_id}",
        ]
        if tool_versions:
            lines.append("")
            lines.append("Tool versions:")
            for tool, version in sorted(tool_versions.items()):
                lines.append(f"  {tool}: {version}")
        lines.append("")
        lines.append("Methods:")
        lines.append(methods_text)

        return Response(
            content="\n".join(lines),
            media_type="text/plain",
            headers={
                "Content-Disposition": f'attachment; filename="methods_report_{invocation_id}.txt"',
            },
        )

    except Exception as e:
        log.error(f"[Methods Report] Failed for {invocation_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to generate methods report: {e}")


# ---------------------------------------------------------------------------
# QC Report Export
# ---------------------------------------------------------------------------

class QCReportExportRequest(BaseModel):
    invocation_id: str
    format: str = "html"


def _lookup_work_dir_for_invocation(invocation_id: str) -> Optional[Path]:
    """
    Resolve the Nextflow work directory for a given invocation_id.

    Searches the in-process _runs registry (keyed by run_id) for a run whose
    invocation_id matches.  Returns None if no matching run is found.
    """
    with _runs_lock:
        for run_info in _runs.values():
            if run_info.get("invocation_id") == invocation_id:
                wd = run_info.get("work_dir")
                return Path(wd) if wd else None
    return None


def _build_qc_report_from_jsonl(invocation_id: str, audit_path: Path) -> Dict[str, Any]:
    """
    Reconstruct a minimal QC report from a persisted JSONL audit file.

    The audit file records override/profile initialisation and gate-trigger events.
    It does NOT contain full metric snapshots, so the reconstructed report has
    less detail than the live in-memory version.
    """
    import json as _json

    entries = []
    try:
        for line in audit_path.read_text(errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(_json.loads(line))
            except Exception:
                pass
    except OSError:
        pass

    gate_entries = [e for e in entries if e.get("event_type") == "gate_triggered"]
    active_profile = next(
        (e.get("active_profile") for e in entries if e.get("active_profile")), None
    )
    active_overrides = next(
        (e.get("configured_overrides", {}) for e in entries), {}
    )

    events = []
    for e in gate_entries:
        events.append({
            "type": "gate",
            "process_name": e.get("applied_overrides", {}).get("process_name", "unknown"),
            "timestamp": e.get("timestamp", ""),
            "metrics": {},
            "failures": [],
            "suggestions": [],
            "active_profile": e.get("active_profile"),
        })

    return {
        "invocation_id": invocation_id,
        "active_profile": active_profile,
        "active_overrides": active_overrides,
        "gates_triggered": len(gate_entries),
        "warnings_emitted": 0,
        "events": events,
        "methods_text": "QC governance applied (see audit log for details).",
        "source": "audit_jsonl",
    }


def _html_escape(value: Any) -> str:
    """Minimal HTML escaping for values embedded in table cells."""
    s = str(value)
    return (
        s.replace("&", "&amp;")
         .replace("<", "&lt;")
         .replace(">", "&gt;")
         .replace('"', "&quot;")
    )


def _render_qc_report_html(report: Dict[str, Any]) -> str:
    """
    Generate a self-contained HTML QC report from a structured report dict.

    The report dict is the same shape returned by NextflowQCGateHandler.get_qc_report().
    """
    from datetime import datetime as _dt, timezone as _tz

    invocation_id = report.get("invocation_id", "unknown")
    active_profile = report.get("active_profile") or "none"
    active_overrides = report.get("active_overrides", {})
    gates_triggered = report.get("gates_triggered", 0)
    warnings_emitted = report.get("warnings_emitted", 0)
    events = report.get("events", [])
    methods_text = _html_escape(report.get("methods_text", ""))
    source = report.get("source", "unknown")

    generated_at = _dt.now(_tz.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    # Summary counts
    gate_events = [e for e in events if e.get("type") == "gate"]
    warn_events = [e for e in events if e.get("type") == "warning"]
    total_steps = len(set(e.get("process_name", "") for e in events))
    failed_steps = len(set(e.get("process_name", "") for e in gate_events))
    warning_steps = len(set(e.get("process_name", "") for e in warn_events))
    passed_steps = total_steps - failed_steps

    # Build overrides table rows
    overrides_rows = ""
    if active_overrides:
        for metric, val in sorted(active_overrides.items()):
            overrides_rows += (
                f"<tr><td>{_html_escape(metric)}</td>"
                f"<td>{_html_escape(val)}</td></tr>\n"
            )
    else:
        overrides_rows = '<tr><td colspan="2" class="none">No custom overrides applied</td></tr>'

    # Build per-step event rows
    step_rows = ""
    for event in events:
        etype = event.get("type", "")
        process_name = _html_escape(event.get("process_name", "unknown"))
        timestamp = _html_escape(event.get("timestamp", ""))
        profile_used = _html_escape(event.get("active_profile") or "none")

        if etype == "gate":
            status_cell = '<td class="status-failed">FAILED</td>'
            row_class = "row-failed"
            failures = event.get("failures", [])
            detail_cells = _render_failures_cells(failures)
        elif etype == "warning":
            status_cell = '<td class="status-warning">WARNING</td>'
            row_class = "row-warning"
            warnings_list = event.get("warnings", [])
            detail_cells = _render_warnings_cells(warnings_list)
        else:
            status_cell = '<td class="status-passed">PASSED</td>'
            row_class = "row-passed"
            detail_cells = "<td>-</td><td>-</td><td>-</td><td>-</td>"

        step_rows += (
            f'<tr class="{row_class}">'
            f"<td>{process_name}</td>"
            f"{status_cell}"
            f"<td>{timestamp}</td>"
            f"<td>{profile_used}</td>"
            f"{detail_cells}"
            f"</tr>\n"
        )

    if not step_rows:
        step_rows = (
            '<tr><td colspan="8" class="none">'
            "No QC events recorded — all processes passed automatically."
            "</td></tr>"
        )

    # Build suggestions section (only if any gate events have suggestions)
    suggestions_section = ""
    all_suggestions = []
    for event in gate_events:
        for s in event.get("suggestions", []):
            all_suggestions.append((event.get("process_name", ""), s))

    if all_suggestions:
        sug_rows = ""
        for proc, s in all_suggestions:
            sug_rows += (
                f"<tr>"
                f"<td>{_html_escape(proc)}</td>"
                f"<td>{_html_escape(s.get('parameter', ''))}</td>"
                f"<td>{_html_escape(s.get('currentValue', ''))}</td>"
                f"<td>{_html_escape(s.get('suggestedValue', ''))}</td>"
                f"<td>{_html_escape(s.get('reason', ''))}</td>"
                f"<td>{_html_escape(s.get('confidence', ''))}</td>"
                f"</tr>\n"
            )
        suggestions_section = f"""
        <h2>Parameter Suggestions</h2>
        <table>
          <thead>
            <tr>
              <th>Process</th><th>Parameter</th><th>Current Value</th>
              <th>Suggested Value</th><th>Reason</th><th>Confidence</th>
            </tr>
          </thead>
          <tbody>{sug_rows}</tbody>
        </table>
        """

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>BioMate QC Report — {_html_escape(invocation_id)}</title>
  <style>
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      font-size: 14px;
      color: #1a1a1a;
      background: #f5f5f5;
      margin: 0;
      padding: 24px;
    }}
    .container {{
      max-width: 1200px;
      margin: 0 auto;
      background: #fff;
      border-radius: 8px;
      box-shadow: 0 1px 4px rgba(0,0,0,0.1);
      padding: 32px;
    }}
    h1 {{
      font-size: 22px;
      font-weight: 700;
      margin: 0 0 4px;
      color: #111;
    }}
    h2 {{
      font-size: 16px;
      font-weight: 600;
      margin: 28px 0 10px;
      border-bottom: 1px solid #e0e0e0;
      padding-bottom: 6px;
      color: #333;
    }}
    .meta {{
      font-size: 12px;
      color: #666;
      margin-bottom: 24px;
    }}
    .meta span {{ margin-right: 18px; }}
    .summary-grid {{
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 12px;
      margin-bottom: 24px;
    }}
    .summary-card {{
      border-radius: 6px;
      padding: 14px 18px;
      text-align: center;
    }}
    .card-total   {{ background: #f0f4ff; border: 1px solid #c5d3f7; }}
    .card-passed  {{ background: #f0faf4; border: 1px solid #a8d5b8; }}
    .card-failed  {{ background: #fff4f4; border: 1px solid #f5c5c5; }}
    .card-warning {{ background: #fff9ec; border: 1px solid #f5dfa5; }}
    .summary-card .number {{
      font-size: 28px;
      font-weight: 700;
      line-height: 1.2;
    }}
    .summary-card .label {{
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: #555;
      margin-top: 2px;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
      margin-bottom: 16px;
    }}
    th {{
      background: #f5f5f5;
      text-align: left;
      padding: 8px 10px;
      border: 1px solid #ddd;
      font-weight: 600;
      white-space: nowrap;
    }}
    td {{
      padding: 7px 10px;
      border: 1px solid #e8e8e8;
      vertical-align: top;
    }}
    tr:hover td {{ background: #fafafa; }}
    .row-failed td {{ background: #fff8f8; }}
    .row-warning td {{ background: #fffbf0; }}
    .row-passed td {{ background: #f8fff9; }}
    .status-passed  {{ color: #1a7f3c; font-weight: 600; }}
    .status-failed  {{ color: #b91c1c; font-weight: 600; }}
    .status-warning {{ color: #b45309; font-weight: 600; }}
    .tier-gold   {{ color: #b45309; font-weight: 600; }}
    .tier-silver {{ color: #64748b; font-weight: 600; }}
    .tier-bronze {{ color: #92400e; font-weight: 600; }}
    .advisory    {{ color: #6d4c41; font-style: italic; }}
    .methods-box {{
      background: #f8faff;
      border: 1px solid #d0d9f0;
      border-radius: 6px;
      padding: 14px 18px;
      font-size: 13px;
      line-height: 1.6;
      margin-bottom: 24px;
    }}
    .overrides-small {{
      font-size: 12px;
      color: #555;
    }}
    .none {{
      color: #888;
      font-style: italic;
    }}
    .footer {{
      margin-top: 32px;
      padding-top: 14px;
      border-top: 1px solid #e8e8e8;
      font-size: 11px;
      color: #999;
      text-align: center;
    }}
    .badge {{
      display: inline-block;
      padding: 1px 7px;
      border-radius: 9px;
      font-size: 10px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }}
    .badge-source {{
      background: #e8f0fe;
      color: #1a73e8;
    }}
  </style>
</head>
<body>
<div class="container">

  <h1>BioMate QC Governance Report</h1>
  <div class="meta">
    <span><strong>Invocation ID:</strong> {_html_escape(invocation_id)}</span>
    <span><strong>Generated:</strong> {generated_at}</span>
    <span><strong>QC Profile:</strong> {_html_escape(active_profile)}</span>
    <span><span class="badge badge-source">{_html_escape(source)}</span></span>
  </div>

  <h2>Summary</h2>
  <div class="summary-grid">
    <div class="summary-card card-total">
      <div class="number">{total_steps}</div>
      <div class="label">Total Steps with QC Events</div>
    </div>
    <div class="summary-card card-passed">
      <div class="number">{passed_steps}</div>
      <div class="label">Passed Steps</div>
    </div>
    <div class="summary-card card-failed">
      <div class="number">{failed_steps}</div>
      <div class="label">Failed Steps</div>
    </div>
    <div class="summary-card card-warning">
      <div class="number">{warning_steps + warnings_emitted}</div>
      <div class="label">Advisory Warnings</div>
    </div>
  </div>

  <h2>Methods Summary</h2>
  <div class="methods-box">{methods_text}</div>

  <h2>Per-Step QC Gate Results</h2>
  <table>
    <thead>
      <tr>
        <th>Process Name</th>
        <th>Status</th>
        <th>Timestamp</th>
        <th>Profile</th>
        <th>Metric</th>
        <th>Value</th>
        <th>Threshold</th>
        <th>Tier</th>
      </tr>
    </thead>
    <tbody>
      {step_rows}
    </tbody>
  </table>

  {suggestions_section}

  <h2>Active Threshold Overrides</h2>
  <table class="overrides-small">
    <thead>
      <tr><th>Metric</th><th>Override Value</th></tr>
    </thead>
    <tbody>
      {overrides_rows}
    </tbody>
  </table>

  <div class="footer">
    Generated by BioMate QC Governance Engine &mdash;
    <a href="https://biomate.ai" style="color:#999;">biomate.ai</a>
  </div>

</div>
</body>
</html>"""

    return html


def _render_failures_cells(failures: list) -> str:
    """Render the Metric / Value / Threshold / Tier table cells for gate failures."""
    if not failures:
        return "<td>-</td><td>-</td><td>-</td><td>-</td>"

    metric_parts, value_parts, threshold_parts, tier_parts = [], [], [], []
    for f in failures:
        metric = _html_escape(f.get("metric", ""))
        value = _html_escape(f.get("value", ""))
        threshold = _html_escape(f.get("threshold", ""))
        tier = _html_escape(f.get("tier", f.get("severity", "")))
        advisory = f.get("advisory", False)
        msg = _html_escape(f.get("message", ""))

        tier_class = ""
        if "GOLD" in tier.upper():
            tier_class = "tier-gold"
        elif "SILVER" in tier.upper():
            tier_class = "tier-silver"
        elif "BRONZE" in tier.upper():
            tier_class = "tier-bronze"

        adv_note = ' <span class="advisory">(advisory)</span>' if advisory else ""

        metric_parts.append(f"{metric}{adv_note}")
        value_parts.append(str(value))
        threshold_parts.append(f"{threshold} &mdash; {msg}" if msg else str(threshold))
        tier_parts.append(f'<span class="{tier_class}">{tier}</span>' if tier_class else tier)

    sep = "<br>"
    return (
        f"<td>{sep.join(metric_parts)}</td>"
        f"<td>{sep.join(value_parts)}</td>"
        f"<td>{sep.join(threshold_parts)}</td>"
        f"<td>{sep.join(tier_parts)}</td>"
    )


def _render_warnings_cells(warnings: list) -> str:
    """Render the Metric / Value / Threshold / Tier table cells for near-threshold warnings."""
    if not warnings:
        return "<td>-</td><td>-</td><td>-</td><td>-</td>"

    metric_parts, value_parts, threshold_parts, tier_parts = [], [], [], []
    for w in warnings:
        metric = _html_escape(w.get("metric", ""))
        value = _html_escape(w.get("value", ""))
        threshold = _html_escape(w.get("threshold", ""))
        severity = _html_escape(w.get("severity", "near_threshold"))
        msg = _html_escape(w.get("message", ""))

        metric_parts.append(metric)
        value_parts.append(str(value))
        threshold_parts.append(f"{threshold} &mdash; {msg}" if msg else str(threshold))
        tier_parts.append(severity)

    sep = "<br>"
    return (
        f"<td>{sep.join(metric_parts)}</td>"
        f"<td>{sep.join(value_parts)}</td>"
        f"<td>{sep.join(threshold_parts)}</td>"
        f"<td>{sep.join(tier_parts)}</td>"
    )


@router.post(
    "/api/export/qc_report",
    summary="Export QC governance report as HTML",
    response_class=HTMLResponse,
)
def export_qc_report(
    request: QCReportExportRequest,
) -> HTMLResponse:
    """
    Generate and return an HTML QC governance report for a workflow invocation.

    Lookup order:
      1. In-memory QC handler registry (_qc_handlers) — populated when the workflow
         is launched via POST /api/nextflow/execute.
      2. Persisted JSONL audit log at <work_dir>/qc_overrides_audit.jsonl — used when
         the handler has been evicted or the process was launched in a previous session.

    Accepted formats: "html" (only format supported in v1).

    Returns Content-Type: text/html.
    """
    invocation_id = request.invocation_id.strip()
    fmt = (request.format or "html").lower()

    if fmt != "html":
        raise HTTPException(
            status_code=422,
            detail=f"Unsupported format '{fmt}'. Only 'html' is supported.",
        )

    if not invocation_id:
        raise HTTPException(status_code=422, detail="invocation_id must not be empty.")

    report: Optional[Dict[str, Any]] = None

    # --- Path 1: live in-memory handler ---
    with _qc_handlers_lock:
        handler = _qc_handlers.get(invocation_id)

    if handler is not None:
        try:
            report = handler.get_qc_report()
            report["source"] = "live_handler"
        except Exception as exc:
            log.warning(f"[QC Export] Failed to get report from live handler: {exc}")

    # --- Path 2: persisted JSONL audit file ---
    if report is None:
        work_dir = _lookup_work_dir_for_invocation(invocation_id)
        if work_dir is not None:
            audit_path = work_dir / "qc_overrides_audit.jsonl"
            if audit_path.exists():
                report = _build_qc_report_from_jsonl(invocation_id, audit_path)

    # --- Path 3: empty report (no QC data recorded yet) ---
    if report is None:
        report = {
            "invocation_id": invocation_id,
            "active_profile": None,
            "active_overrides": {},
            "gates_triggered": 0,
            "warnings_emitted": 0,
            "events": [],
            "methods_text": (
                "No QC events have been recorded for this invocation. "
                "The workflow may still be running, or QC monitoring was not enabled."
            ),
            "source": "not_found",
        }

    try:
        html_content = _render_qc_report_html(report)
    except Exception as exc:
        log.error(f"[QC Export] HTML rendering failed for {invocation_id}: {exc}")
        raise HTTPException(status_code=500, detail=f"HTML rendering failed: {exc}")

    return HTMLResponse(content=html_content, status_code=200)


# ---------------------------------------------------------------------------
# Pipeline Manifest
# ---------------------------------------------------------------------------

@router.get(
    "/api/nextflow/invocations/{invocation_id}/manifest",
    summary="Get pipeline output manifest for a completed invocation",
)
def get_invocation_manifest(
    invocation_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    """
    Return the workflow_outputs.json manifest written by the PIPELINE_MANIFEST
    Nextflow process at pipeline completion.

    Returns 404 if the invocation is unknown or the manifest file has not yet
    been written (pipeline still running / manifest step not reached).
    """
    import json as _json

    # Locate outdir for this invocation from the in-process run registry
    outdir: Optional[Path] = None
    with _runs_lock:
        for run_info in _runs.values():
            if run_info.get("invocation_id") == invocation_id:
                raw = run_info.get("outdir")
                outdir = Path(raw) if raw else None
                break

    if outdir is None:
        raise HTTPException(
            status_code=404,
            detail=f"Invocation '{invocation_id}' not found.",
        )

    manifest_path = outdir / "workflow_outputs.json"
    if not manifest_path.exists():
        raise HTTPException(
            status_code=404,
            detail=(
                f"Manifest not yet available for invocation '{invocation_id}'. "
                "The pipeline may still be running or the PIPELINE_MANIFEST step has not completed."
            ),
        )

    try:
        manifest = _json.loads(manifest_path.read_text())
    except Exception as exc:
        log.error(f"[Manifest] Failed to read manifest for {invocation_id}: {exc}")
        raise HTTPException(status_code=500, detail=f"Failed to read manifest: {exc}")

    return manifest


# ---------------------------------------------------------------------------
# CryoSPARC direct execution routes
# ---------------------------------------------------------------------------

class CryoSPARCExecuteRequest(BaseModel):
    parameters: Optional[Dict[str, Any]] = None
    user_id: Optional[str] = None
    history_id: Optional[str] = None
    license_key: Optional[str] = None  # overrides CRYOSPARC_LICENSE env var for this run


def _make_cryosparc_sse_callback(run_id: str):
    """Build a progress_callback that forwards CryoSPARC events to the Node SSE bus."""
    import urllib.request as _urllib_req
    import json as _json

    node_sse_url = "http://localhost:3000/internal/sse-inject"

    def _inject(event_type: str, data: dict):
        try:
            body = _json.dumps({
                "invocation_id": run_id,
                "event_type": event_type,
                "data": data,
            }).encode()
            req = _urllib_req.Request(
                node_sse_url, data=body,
                headers={"Content-Type": "application/json"}, method="POST"
            )
            _urllib_req.urlopen(req, timeout=2)
        except Exception:
            pass  # SSE delivery is best-effort; never block the pipeline

    def _cb(pct: int, msg: str):
        # pct == -1 signals a structured event (msg is JSON)
        if pct == -1:
            try:
                payload = _json.loads(msg)
                ev_type = payload.get("type", "cryosparc_event")
                _inject(ev_type, payload)
                return
            except Exception:
                pass
        _inject("cryosparc_progress", {"percent": pct, "message": msg})

    return _cb


def _stage_s3_movies_on_cryosparc(s3_url: str, instance_ip: str, ssh_key: str, ssh_user: str) -> str:
    """
    Download S3 movie files to the CryoSPARC EC2 instance so CryoSPARC can read them locally.

    The CryoSPARC instance must have IAM credentials (CryoEMBenchmarkProfile) for S3 access.
    Returns the local path on the CryoSPARC instance (preserving any trailing glob pattern).

    Handles both plain paths (s3://bucket/dir/) and glob patterns (s3://bucket/dir/*.mrcs).
    """
    import subprocess, re, hashlib

    if not ssh_key or not instance_ip or instance_ip in ("localhost", "127.0.0.1"):
        log.warning("[CryoSPARC] Cannot stage S3 movies: no ssh_key or local instance — using path as-is")
        return s3_url

    # Split into directory prefix + optional glob filename pattern
    # e.g. s3://bucket/path/00[1-5]_movie.mrcs → ("s3://bucket/path/", "00[1-5]_movie.mrcs")
    last_slash = s3_url.rfind("/")
    s3_dir = s3_url[:last_slash + 1]              # "s3://bucket/path/"
    filename_pattern = s3_url[last_slash + 1:]    # "00[1-5]_movie.mrcs" or ""

    # Deterministic local staging dir keyed on S3 directory
    dir_hash = hashlib.md5(s3_dir.encode()).hexdigest()[:10]
    local_dir = f"/home/ubuntu/biomate_movies/{dir_hash}"

    # Build aws s3 sync command with optional --include filter
    sync_cmd = f"mkdir -p {local_dir}"
    if filename_pattern:
        # Sync only files matching the glob pattern
        sync_cmd += f" && aws s3 sync {s3_dir} {local_dir}/ --exclude '*' --include '{filename_pattern}' --region us-east-1 --no-progress"
    else:
        sync_cmd += f" && aws s3 sync {s3_dir} {local_dir}/ --region us-east-1 --no-progress"

    log.info("[CryoSPARC] Staging S3 movies to %s:%s from %s ...", instance_ip, local_dir, s3_url)
    try:
        result = subprocess.run(
            ["ssh", "-i", ssh_key, "-o", "StrictHostKeyChecking=no",
             "-o", "ConnectTimeout=30", "-o", "ServerAliveInterval=30",
             f"{ssh_user}@{instance_ip}", sync_cmd],
            capture_output=True, text=True, timeout=600,
        )
        if result.returncode != 0:
            log.error("[CryoSPARC] S3 staging failed (rc=%d): %s", result.returncode, result.stderr[:500])
        else:
            log.info("[CryoSPARC] S3 staging complete: %s", result.stdout.strip()[:200])
    except Exception as exc:
        log.error("[CryoSPARC] S3 staging exception: %s", exc)

    # Always return the directory: CryoSPARC doesn't support [n-m] glob syntax.
    # Files were already filtered during staging, so *.mrcs will match them all.
    # Detect extension from filename_pattern to avoid hardcoding *.mrcs.
    if filename_pattern:
        import re as _re_ext
        _ext_m = _re_ext.search(r'\.(mrcs?|tif|tiff|eer|mrc)$', filename_pattern, _re_ext.IGNORECASE)
        _ext = _ext_m.group(0) if _ext_m else ".mrcs"
        return f"{local_dir}/*{_ext}"
    return f"{local_dir}/"


def _create_movie_batch_dirs(
    movies_path: str, instance_ip: str, ssh_key: str, ssh_user: str,
    num_workers: int, batch_size: int,
) -> List[Dict[str, Any]]:
    """SSH to the CryoSPARC instance and create per-batch symlink directories.

    Returns a list of dicts: [{"batch_id": "batch_0000", "dir": "/path/batch_0000", "num_movies": 5}, ...]
    Each dir contains symlinks to the movie files for that batch.  INIT_CRYOSPARC_PROJECT
    reads this list to create one CryoSPARC workspace + import_movies job per batch,
    enabling truly parallel motion correction across GPUs.
    """
    import subprocess, time as _time, os as _os
    if not ssh_key or not instance_ip or instance_ip in ("localhost", "127.0.0.1"):
        return []
    try:
        # List all movie files (sorted so batches are deterministic)
        ls_result = subprocess.run(
            ["ssh", "-i", ssh_key, "-o", "StrictHostKeyChecking=no",
             "-o", "ConnectTimeout=15", f"{ssh_user}@{instance_ip}",
             f"ls {movies_path} 2>/dev/null | sort"],
            capture_output=True, text=True, timeout=30,
        )
        if ls_result.returncode != 0 or not ls_result.stdout.strip():
            log.warning("[CryoSPARC] ls %s returned empty — skipping per-batch dirs", movies_path)
            return []
        movies = [f.strip() for f in ls_result.stdout.strip().split('\n') if f.strip()]

        # Resolve the movies directory (strip glob/trailing wildcard)
        movies_dir = _os.path.dirname(movies_path.rstrip('/*'))

        run_tag = _time.strftime("%Y%m%d-%H%M%S")
        batches: List[Dict[str, Any]] = []
        for i in range(0, len(movies), batch_size):
            batch_files = movies[i:i + batch_size]
            batch_idx   = i // batch_size
            batch_id    = f"batch_{batch_idx:04d}"
            batch_dir   = f"/home/{ssh_user}/biomate_batches/{run_tag}/{batch_id}"

            # Build symlinks: create dir then ln -sf each movie into it
            symlink_cmds = [f"mkdir -p {batch_dir}"]
            for fname in batch_files:
                # fname may be absolute or relative; resolve to absolute
                full_path = fname if fname.startswith("/") else f"{movies_dir}/{fname}"
                symlink_cmds.append(f"ln -sf {full_path} {batch_dir}/")

            cmd_str = " && ".join(symlink_cmds)
            subprocess.run(
                ["ssh", "-i", ssh_key, "-o", "StrictHostKeyChecking=no",
                 f"{ssh_user}@{instance_ip}", cmd_str],
                capture_output=True, timeout=60,
            )
            batches.append({
                "batch_id":   batch_id,
                "dir":        batch_dir,
                "num_movies": len(batch_files),
            })
            log.info("[CryoSPARC] Created batch dir %s (%d movies)", batch_dir, len(batch_files))

        return batches
    except Exception as exc:
        log.warning("[CryoSPARC] _create_movie_batch_dirs failed: %s", exc)
        return []


def _count_movies_on_cryosparc(movies_path: str, instance_ip: str, ssh_key: str, ssh_user: str) -> int:
    """SSH to CryoSPARC instance and count movie files matching the glob path.
    Returns 0 on failure (caller falls back to default instance type).
    """
    import subprocess
    if not ssh_key or not instance_ip or instance_ip in ("localhost", "127.0.0.1"):
        return 0
    try:
        result = subprocess.run(
            ["ssh", "-i", ssh_key, "-o", "StrictHostKeyChecking=no",
             "-o", "ConnectTimeout=15", f"{ssh_user}@{instance_ip}",
             f"ls {movies_path} 2>/dev/null | wc -l"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            n = int(result.stdout.strip())
            log.info("[CryoSPARC] Counted %d movie files at %s", n, movies_path)
            return n
    except Exception as exc:
        log.warning("[CryoSPARC] Could not count movies (%s) — using default instance type", exc)
    return 0


# Dataset-size → instance type table.
#
# Design principle: always use multi-GPU for real cryo-EM work.
# The 3-5× speedup from 4× L4 lanes far outweighs the 1.75× cost difference
# ($1.50/h g6.12xlarge vs $0.85/h g6.2xlarge). g6.2xlarge is reserved for
# CI/mock-mode tests only (num_movies == 0 AND import_particles mode with <1K
# particles, i.e. truly synthetic/test data).
#
# import_particles mode (num_movies=0): treated as 51 to land on g6.12xlarge
# since particle pipelines are equally compute-bound as movie pipelines.
#
# L4 GPU (Ada Lovelace, 31.2 TFLOPS FP32) outperforms V100 for cryo-EM.
# V100 (Volta, 900 GB/s HBM2) only wins for >1M particles, box>512px.
_CRYOSPARC_FLEET: List[Dict[str, Any]] = [
    {"max_movies": 20,   "instance_type": "g6.2xlarge",  "num_gpu": 1, "label": "CI/test (1× L4, ≤20 movies)"},
    {"max_movies": 500,  "instance_type": "g6.12xlarge", "num_gpu": 4, "label": "standard (4× L4)"},
    {"max_movies": 2000, "instance_type": "g6.48xlarge", "num_gpu": 8, "label": "large campaign (8× L4)"},
    {"max_movies": 9999, "instance_type": "p3.16xlarge",  "num_gpu": 8, "label": "bandwidth-bound (8× V100 HBM2)"},
]


def _select_cryosparc_instance(num_movies: int, import_mode: str = "movies") -> Dict[str, Any]:
    """Return fleet entry (instance_type, num_gpu, label) for the given movie count.

    import_particles mode (num_movies=0) is treated as 51 so it lands on
    g6.12xlarge — particle-stage jobs are equally GPU-bound as movie pipelines
    and benefit from the same multi-lane parallelism.
    """
    effective = num_movies if num_movies > 0 else (51 if import_mode == "import_particles" else 0)
    for entry in _CRYOSPARC_FLEET:
        if effective <= entry["max_movies"]:
            return entry
    return _CRYOSPARC_FLEET[-1]


@router.post("/api/cryosparc/execute", summary="Launch a real CryoSPARC SPA pipeline directly on the GPU EC2 instance")
def execute_cryosparc(
    request: CryoSPARCExecuteRequest,
) -> Dict[str, Any]:
    """
    Launch the CryoSPARC SPA pipeline via the direct executor (no AWS Batch).

    Architecture:
    1. Start the CryoSPARC GPU EC2 instance and wait for it to be ready.
    2. Stage S3 movies to the instance local filesystem if needed.
    3. Build NF params and call execute_nextflow() — launches main.nf on AWS Batch
       with up to 20 parallel micrograph-batch tasks (5.9× speedup).
    4. Return the run_id — the frontend monitors via /api/workflows/runs/:runId/status.
    """
    from galaxy.webapps.galaxy.api import cryosparc_executor as cs_exec

    params = dict(request.parameters or {})
    user_id = request.user_id or ""
    license_key = request.license_key or os.environ.get("CRYOSPARC_LICENSE", "")

    # ── Step 1: resolve movies_path early so we can count movies before provisioning ──
    # We duplicate the resolution logic here (Step 2 repeats for S3 staging) so
    # the movie count is available before start_instance() selects instance type.
    _early_movies_path = (params.get("movie_dir") or params.get("movies_path") or
                          params.get("input_movies") or params.get("data_path") or "")
    if not _early_movies_path:
        try:
            from dotenv import dotenv_values as _dotenv_values
            _live_env0 = _dotenv_values(_backend_root / ".env") if "_backend_root" in dir() else {}
        except Exception:
            _live_env0 = {}
        _early_movies_path = (_live_env0.get("CRYOSPARC_DEFAULT_MOVIE_DIR") or
                              os.environ.get("CRYOSPARC_DEFAULT_MOVIE_DIR", ""))

    # ── Step 1b: dataset sizing — count movies → select instance type ─────────
    _num_movies_param = int(params.get("num_movies", 0))
    if _num_movies_param > 0:
        _num_movies = _num_movies_param
    elif _early_movies_path and not _early_movies_path.startswith("s3://"):
        # Count local files on CryoSPARC instance
        _glob_path = (_early_movies_path.rstrip("/") + "/*.mrcs"
                      if not any(c in _early_movies_path for c in ("*", "?", "["))
                      else _early_movies_path)
        _num_movies = _count_movies_on_cryosparc(
            _glob_path,
            instance_ip=cs_exec.CRYOSPARC_HOST,
            ssh_key=os.environ.get("CRYOSPARC_SSH_KEY", ""),
            ssh_user=os.environ.get("CRYOSPARC_SSH_USER", "ubuntu"),
        )
    else:
        _num_movies = 0

    _input_mode_early = params.get("mode", "movies")
    _fleet_entry = _select_cryosparc_instance(_num_movies, import_mode=_input_mode_early)
    _selected_instance_type = params.get("instance_type") or _fleet_entry["instance_type"]
    _selected_num_gpu       = int(params.get("num_gpu", 0)) or _fleet_entry["num_gpu"]
    # Auto-set num_cs_workers to match the GPU count unless caller overrides.
    # This ensures multi-GPU instances always use all lanes for parallel execution.
    if "num_cs_workers" not in params:
        params["num_cs_workers"] = _selected_num_gpu
    log.info("[CryoSPARC] Dataset sizing: %d movies (mode=%s) → instance=%s (%d GPU, %d workers, %s)",
             _num_movies, _input_mode_early, _selected_instance_type, _selected_num_gpu,
             params["num_cs_workers"], _fleet_entry["label"])

    # Override the module-level instance type so start_instance() launches the right size
    cs_exec.CRYOSPARC_INSTANCE_TYPE = _selected_instance_type

    # ── Step 1c: provision the CryoSPARC GPU instance ────────────────────────
    # When CRYOSPARC_SKIP_PROVISION=1, the server is already running at CRYOSPARC_HOST
    # and no EC2 provisioning is needed (e.g. dev/staging with a permanent CryoSPARC host).
    if os.environ.get("CRYOSPARC_SKIP_PROVISION", "").strip() in ("1", "true", "yes"):
        log.info("[CryoSPARC] CRYOSPARC_SKIP_PROVISION=1 — using existing host %s", cs_exec.CRYOSPARC_HOST)
    else:
        log.info("[CryoSPARC] Provisioning %s GPU instance for direct execution...", _selected_instance_type)
        try:
            instance_ip = cs_exec.start_instance(wait=True)
            cs_exec.CRYOSPARC_HOST = instance_ip or cs_exec.CRYOSPARC_HOST
            log.info("[CryoSPARC] Instance ready at %s", cs_exec.CRYOSPARC_HOST)
        except Exception as exc:
            raise HTTPException(status_code=503,
                                detail=f"Failed to provision CryoSPARC GPU instance: {exc}")

    # ── Step 2: resolve movies_path — stage from S3 if needed ────────────────
    movies_path_raw = (params.get("movie_dir") or params.get("movies_path") or
                       params.get("input_movies") or params.get("data_path") or "")
    if not movies_path_raw:
        # Re-read .env at request time so movies path changes take effect without
        # restarting gunicorn (load_dotenv at import time doesn't help if the parent
        # process env was set before the .env change).
        try:
            from dotenv import dotenv_values as _dotenv_values
            _live_env = _dotenv_values(_backend_root / ".env") if "_backend_root" in dir() else {}
        except Exception:
            _live_env = {}
        s3_default    = _live_env.get("CRYOSPARC_MOVIES_S3") or os.environ.get("CRYOSPARC_MOVIES_S3", "")
        local_default = _live_env.get("CRYOSPARC_DEFAULT_MOVIE_DIR") or os.environ.get("CRYOSPARC_DEFAULT_MOVIE_DIR", "")
        movies_path_raw = local_default or s3_default
        if movies_path_raw:
            log.info("[CryoSPARC] movies_path not in params — using env default: %s", movies_path_raw)
    if movies_path_raw.startswith("s3://") and not movies_path_raw.endswith("/") and \
            not any(c in movies_path_raw.split("/")[-1] for c in ("*", "?", "[")):
        movies_path_raw += "/"
    s3_movies_url: str = ""  # preserved for retry inside pipeline thread
    if movies_path_raw.startswith("s3://"):
        s3_movies_url = movies_path_raw   # save for retry
        movies_path_raw = _stage_s3_movies_on_cryosparc(
            s3_url=movies_path_raw,
            instance_ip=cs_exec.CRYOSPARC_HOST,
            ssh_key=os.environ.get("CRYOSPARC_SSH_KEY", ""),
            ssh_user=os.environ.get("CRYOSPARC_SSH_USER", "ubuntu"),
        )
        log.info("[CryoSPARC] movies staged to local: %s", movies_path_raw)

    # For local paths (on CryoSPARC EC2): append glob if not already present.
    # Batch containers in us-west-2 cannot check isdir on the CryoSPARC EC2
    # filesystem (us-east-1), so glob must be resolved here on the backend server.
    if movies_path_raw and not movies_path_raw.startswith("s3://") and \
            not any(c in movies_path_raw for c in ("*", "?", "[")):
        movies_path_raw = movies_path_raw.rstrip("/") + "/*.mrcs"
        log.info("[CryoSPARC] Appended glob pattern to local movies path: %s", movies_path_raw)

    # ── Step 3: build params for NF execute_nextflow call ───────────────────
    spa_params: Dict[str, Any] = {
        "movie_dir":              movies_path_raw,
        "s3_movies_url":          s3_movies_url or None,  # for retry in pipeline thread
        "pixel_size":             float(params.get("pixel_size", params.get("micrograph_pixel_size", 1.0))),
        "voltage":                int(params.get("voltage", 300)),
        "cs":                     float(params.get("spherical_aberration", params.get("cs", 2.7))),
        "amplitude_contrast":     float(params.get("amplitude_contrast", 0.1)),
        "particle_diameter":      float(params.get("particle_diameter_angstroms",
                                                   params.get("particle_diameter", 180))),
        "symmetry":               params.get("symmetry", "C1"),
        "num_movies":             int(params.get("num_movies", 0)),
        "num_ab_initio_classes":  int(params.get("num_ab_initio_classes", 3)),
        "molecular_weight_kda":   float(params.get("molecular_weight_kda", 0)) or None,
    }
    spa_params = {k: v for k, v in spa_params.items() if v is not None}

    # ── Step 4: launch via Nextflow ──────────────────────────────────────────────
    # Parallelism: each micrograph batch is an independent AWS Batch task.
    # With num_cs_workers > 1 and a multi-GPU instance that has N CryoSPARC workers
    # registered (cryosparcm addworker), batches are routed to separate lanes and run
    # simultaneously.  Default (num_cs_workers=1) is backwards-compatible: single lane.
    max_parallel   = int(params.get("max_parallel_jobs", 20))
    batch_size     = int(params.get("micrograph_batch_size", 200))
    num_cs_workers = int(params.get("num_cs_workers", 1))

    # ── Part A: per-batch movie directory setup (multi-worker movies mode only) ──
    # When num_cs_workers > 1 and processing raw movies, SSH to the CryoSPARC instance
    # before launching Nextflow to create per-batch symlink directories.  Each batch
    # gets its own CryoSPARC workspace + import_movies job, enabling truly parallel
    # motion correction across GPUs rather than all batches sharing one import job.
    _movie_batch_dirs: str = ""  # JSON-encoded list of per-batch dir info
    input_mode = params.get("mode", "import_movies")
    if num_cs_workers > 1 and input_mode != "import_particles" and movies_path_raw:
        _ssh_key_mb  = os.environ.get("CRYOSPARC_SSH_KEY", "")
        _ssh_user_mb = os.environ.get("CRYOSPARC_SSH_USER", "ubuntu")
        _inst_ip_mb  = cs_exec.CRYOSPARC_HOST
        if _ssh_key_mb:
            try:
                _batch_dirs = _create_movie_batch_dirs(
                    movies_path=movies_path_raw,
                    instance_ip=_inst_ip_mb,
                    ssh_key=_ssh_key_mb,
                    ssh_user=_ssh_user_mb,
                    num_workers=num_cs_workers,
                    batch_size=batch_size,
                )
                if _batch_dirs:
                    import json as _json
                    _movie_batch_dirs = _json.dumps(_batch_dirs)
                    log.info("[CryoSPARC] Created %d per-batch movie dirs on %s",
                             len(_batch_dirs), _inst_ip_mb)
            except Exception as _mbd_err:
                log.warning("[CryoSPARC] Per-batch movie dir setup failed (%s) — "
                            "falling back to single-batch mode", _mbd_err)

    # ── import_particles mode: start from pre-extracted particle stacks ─────────
    # star_file / particle_dir_s3 may be S3 URIs; we sync them to the instance
    # local filesystem so CryoSPARC can read them.  The STAR file's embedded
    # paths are rewritten to match the local staging directory.
    input_mode      = params.get("mode", "import_movies")
    star_file       = params.get("star_file", "")
    particle_dir_s3 = params.get("particle_dir_s3", "")
    particle_dir    = params.get("particle_dir", "")

    if input_mode == "import_particles":
        _ssh_key  = os.environ.get("CRYOSPARC_SSH_KEY", "")
        _ssh_user = os.environ.get("CRYOSPARC_SSH_USER", "ubuntu")
        _inst_ip  = cs_exec.CRYOSPARC_HOST

        # Stage particle stacks from S3 if provided
        if particle_dir_s3 and particle_dir_s3.startswith("s3://"):
            log.info("[CryoSPARC] Syncing particle stacks from S3: %s", particle_dir_s3)
            # _stage_s3_movies_on_cryosparc syncs a whole S3 prefix to local dir
            particle_dir = _stage_s3_movies_on_cryosparc(
                s3_url=particle_dir_s3.rstrip("/") + "/",
                instance_ip=_inst_ip,
                ssh_key=_ssh_key,
                ssh_user=_ssh_user,
            ).rstrip("/*.mrcs")  # strip glob appended by staging helper

        # Stage and rewrite STAR file paths if it's an S3 URI
        if star_file.startswith("s3://"):
            import subprocess as _sub
            _star_local = f"/home/{_ssh_user}/particles/{star_file.split('/')[-1]}"
            _cp_cmd = f"aws s3 cp {star_file} {_star_local}"
            _sub.run(["ssh", "-i", _ssh_key, "-o", "StrictHostKeyChecking=no",
                      f"{_ssh_user}@{_inst_ip}", _cp_cmd],
                     capture_output=True, timeout=60)
            star_file = _star_local
            log.info("[CryoSPARC] STAR file staged to: %s", star_file)

        # If particle_dir is set, rewrite absolute paths in STAR file to match local dir
        if particle_dir and star_file:
            _rewrite_cmd = (
                f"python3 -c \""
                f"import re; "
                f"txt=open('{star_file}').read(); "
                f"txt2=re.sub(r'/home/ubuntu/particles/', '{particle_dir.rstrip(chr(47))}/', txt); "
                f"open('{star_file}','w').write(txt2); "
                f"print('Rewrote paths in', '{star_file}')\""
            )
            import subprocess as _sub2
            _sub2.run(["ssh", "-i", _ssh_key, "-o", "StrictHostKeyChecking=no",
                       f"{_ssh_user}@{_inst_ip}", _rewrite_cmd],
                      capture_output=True, timeout=30)
            log.info("[CryoSPARC] Rewrote STAR paths → %s", particle_dir)

    nf_params: Dict[str, Any] = {
        "pixel_size":                  spa_params["pixel_size"],
        "voltage":                     spa_params["voltage"],
        "spherical_aberration":        spa_params["cs"],
        "total_dose":                  float(params.get("total_dose", params.get("total_dose_e_per_A2", 50.0))),
        "particle_diameter_angstroms": spa_params["particle_diameter"],
        "symmetry":                    spa_params["symmetry"],
        "num_ab_initio_classes":       spa_params["num_ab_initio_classes"],
        "use_cryosparc":               True,
        "num_gpu":                     _selected_num_gpu,
        # CryoSPARC connection — live instance IP provisioned above
        "cryosparc_host":     cs_exec.CRYOSPARC_HOST,
        "cryosparc_port":     int(os.environ.get("CRYOSPARC_DIRECT_PORT", "30000")),
        "cryosparc_email":    os.environ.get("CRYOSPARC_EMAIL", "admin@biomate.ai"),
        "cryosparc_license":  license_key,
        # Parallelism — multi-lane routing
        "max_parallel_jobs":      max_parallel,
        "micrograph_batch_size":  batch_size,
        "num_cs_workers":         num_cs_workers,
        "mock_mode":              False,
        # Per-batch movie directories (non-empty only when num_cs_workers>1 and movies mode)
        "movie_batch_dirs":       _movie_batch_dirs or "",
    }

    if input_mode == "import_particles" and star_file:
        # Start from pre-extracted particles: skip motion/CTF/picking phases
        nf_params["movies_path"]       = ""          # not used in particle mode
        nf_params["import_mode"]       = "particles"
        nf_params["particle_star_file"] = star_file
        nf_params["particle_blob_path"] = particle_dir or ""
        log.info("[CryoSPARC] import_particles mode: star_file=%s, blob_path=%s",
                 star_file, nf_params["particle_blob_path"])
    else:
        nf_params["movies_path"] = movies_path_raw

    if spa_params.get("molecular_weight_kda"):
        nf_params["molecular_weight_kda"] = spa_params["molecular_weight_kda"]
    nf_params = {k: v for k, v in nf_params.items() if v is not None and v != ""}

    nf_request = NextflowExecuteRequest(
        nextflow_path="cryo_em/cryosparc_standard_spa/main.nf",
        parameters=nf_params,
        compute_config={"executor": "awsbatch"},
        workflow_domain="cryo_em",
        user_id=user_id,
    )
    nf_result = execute_nextflow(nf_request)
    run_id = nf_result["run_id"]
    log.info("[CryoSPARC] Nextflow SPA run %s started (instance=%s [%s, %d GPU, %d workers], "
             "mode=%s, parallel_jobs=%s, batch_size=%s)",
             run_id, cs_exec.CRYOSPARC_HOST, _selected_instance_type, _selected_num_gpu,
             num_cs_workers, input_mode, max_parallel, batch_size)

    return {
        "success":          True,
        "run_id":           run_id,
        "invocation_id":    nf_result.get("invocation_id", run_id),
        "executor":         "nextflow",
        "execution_engine": "nextflow_cryosparc",
        "message": (
            f"CryoSPARC SPA launched via Nextflow (≤{max_parallel} parallel Batch jobs, "
            f"5.9× speedup) on {cs_exec.CRYOSPARC_HOST}"
        ),
    }


@router.get("/api/cryosparc/gpu_metrics", summary="Get live GPU utilization from the CryoSPARC instance")
def get_cryosparc_gpu_metrics() -> Dict[str, Any]:
    """Return per-GPU utilization, memory, and temperature from the active CryoSPARC instance."""
    try:
        from galaxy.webapps.galaxy.api import cryosparc_executor as cs_exec
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=f"CryoSPARC executor not available: {exc}")
    return cs_exec.get_gpu_metrics()


@router.get("/api/cryosparc/status/{run_id}", summary="Get CryoSPARC run status")
def get_cryosparc_status(run_id: str) -> Dict[str, Any]:
    """Return current status of a CryoSPARC run."""
    try:
        from galaxy.webapps.galaxy.api import cryosparc_executor as cs_exec
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=f"CryoSPARC executor not available: {exc}")

    status = cs_exec.get_run_status(run_id)
    if status is None:
        raise HTTPException(status_code=404, detail=f"CryoSPARC run not found: {run_id}")

    return status


@router.get("/api/cryosparc/instances", summary="List active CryoSPARC runs and instance state")
def get_cryosparc_instances() -> Dict[str, Any]:
    """Return all known runs plus the current EC2 instance state.

    Use this endpoint to detect duplicate instances and diagnose stuck runs.
    """
    try:
        from galaxy.webapps.galaxy.api import cryosparc_executor as cs_exec
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=f"CryoSPARC executor not available: {exc}")

    active_runs = [
        cs_exec.get_run_status(rid)
        for rid, r in cs_exec._cs_runs.items()
        if r.status in ("queued", "running")
    ]
    all_runs = cs_exec.list_runs()

    try:
        instance_state = cs_exec.get_instance_state()
        instance_ip = cs_exec.CRYOSPARC_HOST
        instance_id = cs_exec._active_instance_id or cs_exec.CRYOSPARC_INSTANCE_ID
    except Exception as _e:
        instance_state = f"error: {_e}"
        instance_ip = ""
        instance_id = ""

    return {
        "instance": {
            "id":    instance_id,
            "ip":    instance_ip,
            "state": instance_state,
        },
        "active_runs":  active_runs,
        "all_runs":     all_runs,
        "lock_held":    cs_exec._INSTANCE_LOCK.locked(),
    }


# ---------------------------------------------------------------------------
# Index health check
# ---------------------------------------------------------------------------

@router.get("/api/admin/index-health", summary="Workflow index health by source")
def get_index_health() -> Dict[str, Any]:
    """Returns workflow index counts by source and staleness flags.

    A source is considered stale if its most-recent ``indexed_at`` timestamp
    is older than 7 days (or if no ``indexed_at`` value exists).
    """
    import sqlite3 as _sqlite3
    from datetime import datetime as _dt, timedelta as _td

    stale_threshold = _dt.utcnow() - _td(days=7)
    db_path = Path(__file__).resolve().parents[5] / "database" / "galaxy_ai_tools.db"

    if not db_path.exists():
        raise HTTPException(status_code=503, detail=f"Workflow database not found at {db_path}")

    try:
        conn = _sqlite3.connect(str(db_path))
        rows = conn.execute(
            "SELECT source, COUNT(*), MAX(indexed_at) FROM workflows GROUP BY source ORDER BY COUNT(*) DESC"
        ).fetchall()
        conn.close()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB query failed: {exc}")

    sources = []
    any_stale = False
    for source, count, last_indexed in rows:
        if last_indexed:
            try:
                last_dt = _dt.fromisoformat(last_indexed.replace("Z", "+00:00").replace("+00:00", ""))
            except ValueError:
                last_dt = None
        else:
            last_dt = None

        is_stale = (last_dt is None) or (last_dt < stale_threshold)
        if is_stale:
            any_stale = True

        sources.append({
            "source": source,
            "count": count,
            "last_indexed": last_indexed,
            "is_stale": is_stale,
        })

    return {
        "sources": sources,
        "total": sum(s["count"] for s in sources),
        "health": "stale" if any_stale else "ok",
        "stale_threshold_days": 7,
        "checked_at": _dt.utcnow().isoformat() + "Z",
    }


# ---------------------------------------------------------------------------
# C1 — Preflight with pilot_analysis detection
# ---------------------------------------------------------------------------

class PreflightRequest(BaseModel):
    workflow_path: Optional[str] = None
    workflow_name: Optional[str] = None
    parameters: Optional[Dict[str, Any]] = None
    input_files: Optional[List[str]] = None
    required_params: Optional[List[Dict[str, Any]]] = None


def _detect_pilot_analyzers(input_files: List[str]) -> List[Dict[str, Any]]:
    """Return pilot analyzers applicable to the given input files based on extension."""
    from galaxy.ai.pilot_analysis.registry import PILOT_ANALYZERS

    ext_map: Dict[str, List[str]] = {}
    for f in input_files:
        ext = Path(f).suffix.lower().lstrip(".")
        ext_map.setdefault(ext, []).append(f)

    applicable = []
    seen: set = set()
    for name, spec in PILOT_ANALYZERS.items():
        required_type = spec.get("input_type", "")
        if required_type in ext_map and name not in seen:
            seen.add(name)
            applicable.append({
                "name": name,
                "description": spec.get("description", ""),
                "input_type": required_type,
                "runtime_estimate": spec.get("runtime_estimate", "~30s"),
                "max_runtime_seconds": spec.get("max_runtime_seconds", 60),
                "category": spec.get("category", "general"),
                "matched_files": ext_map[required_type],
            })
    return applicable


# C2 — File-type-based parameter suggestion table
# Maps file extension (or normalized type) → list of parameter suggestions.
# Each suggestion: {param_id, suggested_value, confidence, rationale}
_FILE_TYPE_PARAM_SUGGESTIONS: Dict[str, List[Dict[str, Any]]] = {
    # FASTQ / gzipped FASTQ
    "fastq": [
        {"param_id": "strandedness", "suggested_value": "auto", "confidence": 0.7,
         "rationale": "Auto-detect strandedness is recommended for FASTQ inputs unless library prep is known"},
        {"param_id": "skip_fastqc", "suggested_value": False, "confidence": 0.8,
         "rationale": "FastQC QC is always recommended for FASTQ data"},
    ],
    "fq": [
        {"param_id": "strandedness", "suggested_value": "auto", "confidence": 0.7,
         "rationale": "Auto-detect strandedness is recommended for FASTQ inputs"},
    ],
    "gz": [  # handles .fastq.gz / .fq.gz
        {"param_id": "strandedness", "suggested_value": "auto", "confidence": 0.65,
         "rationale": "Likely compressed FASTQ — auto-detecting strandedness recommended"},
    ],
    # BAM / CRAM
    "bam": [
        {"param_id": "skip_alignment", "suggested_value": True, "confidence": 0.9,
         "rationale": "Input is already aligned (BAM) — skip re-alignment step"},
        {"param_id": "aligner", "suggested_value": None, "confidence": 0.85,
         "rationale": "BAM is pre-aligned; aligner choice is not needed"},
    ],
    "cram": [
        {"param_id": "skip_alignment", "suggested_value": True, "confidence": 0.9,
         "rationale": "CRAM is a pre-aligned format — skip re-alignment"},
    ],
    # VCF
    "vcf": [
        {"param_id": "variant_caller", "suggested_value": "gatk", "confidence": 0.6,
         "rationale": "VCF files are typically from GATK or compatible callers"},
    ],
    # CSV / sample sheet
    "csv": [
        {"param_id": "input", "suggested_value": "<uploaded CSV>", "confidence": 0.8,
         "rationale": "CSV files are commonly used as nf-core sample sheets — set --input to this file"},
        {"param_id": "samplesheet", "suggested_value": "<uploaded CSV>", "confidence": 0.75,
         "rationale": "This CSV file may be the samplesheet for the workflow"},
    ],
    # FASTA
    "fasta": [
        {"param_id": "fasta", "suggested_value": "<uploaded FASTA>", "confidence": 0.8,
         "rationale": "FASTA file detected — likely the reference genome or sequence input"},
    ],
    "fa": [
        {"param_id": "fasta", "suggested_value": "<uploaded FASTA>", "confidence": 0.75,
         "rationale": "FASTA file detected — commonly used as reference or sequence input"},
    ],
    # H5AD (single-cell)
    "h5ad": [
        {"param_id": "input_format", "suggested_value": "h5ad", "confidence": 0.95,
         "rationale": "H5AD is AnnData format — standard for single-cell workflows"},
        {"param_id": "normalization_method", "suggested_value": "scran", "confidence": 0.6,
         "rationale": "Scran normalization is recommended for scRNA-seq data"},
    ],
    # MRC (Cryo-EM)
    "mrc": [
        {"param_id": "pixel_size", "suggested_value": None, "confidence": 0.5,
         "rationale": "MRC micrograph detected — pixel size (Å/pixel) is required"},
        {"param_id": "microscope_voltage", "suggested_value": 300, "confidence": 0.6,
         "rationale": "Most modern cryo-EM data is acquired at 300 kV"},
    ],
    # PDB (structural biology)
    "pdb": [
        {"param_id": "structure_file", "suggested_value": "<uploaded PDB>", "confidence": 0.9,
         "rationale": "PDB file is the protein structure input"},
    ],
}


def _infer_param_suggestions(input_files: List[str]) -> List[Dict[str, Any]]:
    """
    Return parameter suggestions derived purely from file extensions (no tool execution).
    This is C2 Phase 1: fast, zero-cost heuristic suggestions.
    """
    suggestions: List[Dict[str, Any]] = []
    seen_params: set = set()
    for f in input_files:
        fname = Path(f).name.lower()
        # Handle double extensions like .fastq.gz
        if fname.endswith(".fastq.gz") or fname.endswith(".fq.gz"):
            ext = "fastq"
        else:
            ext = Path(f).suffix.lower().lstrip(".")
        for suggestion in _FILE_TYPE_PARAM_SUGGESTIONS.get(ext, []):
            pid = suggestion["param_id"]
            if pid not in seen_params:
                seen_params.add(pid)
                suggestions.append({**suggestion, "source_file": Path(f).name})
    return suggestions


@router.post("/api/workflows/preflight", summary="Pre-flight validation with pilot analysis detection")
def workflow_preflight(request: PreflightRequest) -> Dict[str, Any]:
    """Three-phase preflight check plus pilot-analysis detector.

    Phases:
      1. parameters  — all required params present
      2. inputs      — input file types recognised; applicable pilot analyzers listed
      3. structure   — workflow path resolvable or known in catalog
    """
    phases: List[Dict[str, Any]] = []
    params = request.parameters or {}
    input_files = request.input_files or []
    required = request.required_params or []

    # Phase 1 — required parameters
    missing = [
        p.get("id") or p.get("name")
        for p in required
        if not (params.get(p.get("id") or p.get("name") or ""))
    ]
    phases.append({
        "id": "parameters",
        "status": "pass" if not missing else "fail",
        "message": (
            "All required parameters present"
            if not missing
            else f"Missing required parameters: {', '.join(str(m) for m in missing)}"
        ),
    })

    # Phase 2 — input files + pilot analysis detection + C2 parameter suggestions
    try:
        applicable = _detect_pilot_analyzers(input_files) if input_files else []
        total_est = sum(a["max_runtime_seconds"] for a in applicable)
        # C2: infer parameter suggestions from file types (no tool execution needed)
        param_suggestions = _infer_param_suggestions(input_files) if input_files else []
        phases.append({
            "id": "inputs",
            "status": "pass",
            "message": (
                f"Input files recognised — {len(applicable)} pilot analyzer(s) available"
                if applicable
                else "Input file types checked (no pilot analyzers matched)"
            ),
            "applicable_analyzers": applicable,
            "estimated_characterization_seconds": total_est,
            "parameter_suggestions": param_suggestions,
        })
    except Exception as exc:
        log.warning("preflight: pilot analyzer detection failed: %s", exc)
        phases.append({
            "id": "inputs",
            "status": "pass",
            "message": "Input file accessibility check complete",
            "applicable_analyzers": [],
            "parameter_suggestions": [],
        })

    # Phase 3 — workflow structure
    wf_path = request.workflow_path or ""
    path_ok = bool(wf_path) and Path(wf_path).exists() if wf_path else False
    if not wf_path:
        phases.append({
            "id": "structure",
            "status": "pass",
            "message": "Workflow structure valid (no path provided — catalog workflow)",
        })
    elif path_ok:
        phases.append({
            "id": "structure",
            "status": "pass",
            "message": f"Workflow path exists: {wf_path}",
        })
    else:
        phases.append({
            "id": "structure",
            "status": "warn",
            "message": f"Workflow path not found locally (may be remote): {wf_path}",
        })

    ready = all(p["status"] in ("pass", "warn") for p in phases) and all(
        p["status"] == "pass" for p in phases if p["id"] == "parameters"
    )
    return {"phases": phases, "ready": ready}


# ---------------------------------------------------------------------------
# D1 — Pre-run cost estimation
# ---------------------------------------------------------------------------

# AWS Batch on-demand instance cost table (USD/hr, approximate 2026 rates)
_BATCH_INSTANCE_COST_PER_HOUR: Dict[str, float] = {
    "c5.xlarge": 0.17,
    "c5.2xlarge": 0.34,
    "c5.4xlarge": 0.68,
    "c5.9xlarge": 1.53,
    "c5.18xlarge": 3.06,
    "r5.xlarge": 0.252,
    "r5.2xlarge": 0.504,
    "r5.4xlarge": 1.008,
    "r5.8xlarge": 2.016,
    "m5.xlarge": 0.192,
    "m5.2xlarge": 0.384,
    "m5.4xlarge": 0.768,
    "m5.8xlarge": 1.536,
    "g4dn.xlarge": 0.526,
    "g4dn.2xlarge": 0.752,
    "g4dn.4xlarge": 1.204,
}

# Rough domain → typical instance + hours range mapping
_DOMAIN_RUNTIME_HINTS: Dict[str, Dict[str, Any]] = {
    "rnaseq":     {"instance": "c5.4xlarge",  "min_h": 0.5, "max_h": 2.0},
    "chipseq":    {"instance": "c5.4xlarge",  "min_h": 1.0, "max_h": 4.0},
    "atacseq":    {"instance": "c5.2xlarge",  "min_h": 0.5, "max_h": 3.0},
    "sarek":      {"instance": "c5.9xlarge",  "min_h": 4.0, "max_h": 12.0},
    "scrnaseq":   {"instance": "r5.4xlarge",  "min_h": 1.0, "max_h": 6.0},
    "methylseq":  {"instance": "c5.9xlarge",  "min_h": 2.0, "max_h": 8.0},
    "cryoem":     {"instance": "g4dn.4xlarge","min_h": 2.0, "max_h": 8.0},
    "cryosparc":  {"instance": "g4dn.4xlarge","min_h": 1.0, "max_h": 6.0},
    "proteomics": {"instance": "c5.4xlarge",  "min_h": 0.5, "max_h": 2.0},
    "metagenomics":{"instance": "r5.4xlarge", "min_h": 2.0, "max_h": 10.0},
    "alphafold":  {"instance": "g4dn.4xlarge","min_h": 4.0, "max_h": 24.0},
    "default":    {"instance": "c5.2xlarge",  "min_h": 0.5, "max_h": 3.0},
}


class CostEstimateRequest(BaseModel):
    nextflow_path: Optional[str] = None
    workflow_name: Optional[str] = None
    params: Optional[Dict[str, Any]] = None


@router.post("/api/workflows/estimate_cost", summary="Estimate AWS Batch run cost before execution")
def estimate_workflow_cost(request: CostEstimateRequest) -> Dict[str, Any]:
    """Static pre-run cost estimate based on workflow domain and typical runtimes.

    Returns min/max USD range and assumptions used.
    """
    path = (request.nextflow_path or request.workflow_name or "").lower()

    # Pick domain hint by longest keyword match on path/name (more specific wins)
    hint = _DOMAIN_RUNTIME_HINTS["default"]
    best_len = 0
    for domain, h in _DOMAIN_RUNTIME_HINTS.items():
        if domain != "default" and domain in path and len(domain) > best_len:
            hint = h
            best_len = len(domain)

    instance = hint["instance"]
    cost_per_hour = _BATCH_INSTANCE_COST_PER_HOUR.get(instance, 0.34)
    min_cost = round(hint["min_h"] * cost_per_hour, 2)
    max_cost = round(hint["max_h"] * cost_per_hour * 1.15, 2)  # 15% buffer

    # Try to pull runtime_estimate from pilot_analysis registry for known tools
    try:
        from galaxy.ai.pilot_analysis.registry import PILOT_ANALYZERS
        relevant = [
            a for a in PILOT_ANALYZERS.values()
            if a.get("category", "") in path or path in a.get("category", "")
        ]
        if relevant:
            max_analyzer_s = max(a.get("max_runtime_seconds", 60) for a in relevant)
            if max_analyzer_s > 300:
                max_cost = round(max_cost * 1.3, 2)
    except Exception:
        pass

    return {
        "min_usd": min_cost,
        "max_usd": max_cost,
        "instance_type": instance,
        "cost_per_hour_usd": cost_per_hour,
        "assumptions": [
            f"Instance type: {instance} (${cost_per_hour:.3f}/hr on-demand)",
            f"Estimated runtime: {hint['min_h']:.1f}–{hint['max_h']:.1f} hours",
            "Does not include S3 data transfer costs (~$0.09/GB egress)",
            "AWS Spot pricing may reduce cost by 60–80%",
        ],
    }


# ---------------------------------------------------------------------------
# C3 — nf-core test profile runner
# ---------------------------------------------------------------------------

class ValidateProfileRequest(BaseModel):
    nextflow_path: str
    profile: Optional[str] = "test"
    timeout_seconds: Optional[int] = 300


@router.post("/api/workflows/validate_profile", summary="Validate pipeline runs with nf-core test profile")
def validate_workflow_profile(request: ValidateProfileRequest) -> Dict[str, Any]:
    """Run ``nextflow run {path} -profile test,docker`` on the smallest Batch
    instance to confirm the pipeline environment works end-to-end.

    Returns:
        status: "pass" | "fail" | "timeout" | "skipped"
        message: Human-readable summary
        log_tail: Last 20 lines of stdout/stderr
        duration_seconds: Actual wall time used
    """
    nf_path = request.nextflow_path.strip()
    if not nf_path:
        raise HTTPException(status_code=400, detail="nextflow_path is required")

    profile = request.profile or "test"
    timeout = min(max(int(request.timeout_seconds or 300), 30), 600)

    # Safety: only allow test/docker/singularity profiles; never run user data
    safe_profiles = {"test", "docker", "singularity", "podman", "conda", "test_full", "test_cache"}
    profile_parts = {p.strip() for p in profile.split(",")}
    if not profile_parts.issubset(safe_profiles):
        raise HTTPException(
            status_code=400,
            detail=f"Only safe profiles allowed: {safe_profiles}. Got: {profile_parts - safe_profiles}",
        )

    # Resolve pipeline path
    resolved_path = nf_path
    if not Path(nf_path).exists():
        # Try known nf-core local paths
        base = Path(__file__).resolve().parents[5] / "nf-core-workflows"
        pipeline_name = nf_path.split("/")[-1].replace("nf-core/", "")
        candidate = base / pipeline_name
        if candidate.exists():
            resolved_path = str(candidate)
        # Otherwise pass through as remote (nf-core/<name>) and let Nextflow resolve

    import time as _time
    cmd = ["nextflow", "run", resolved_path, f"-profile", profile, "--outdir", "/tmp/biomate_test_run"]
    start = _time.time()
    log_lines: List[str] = []
    status = "pass"
    message = ""

    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        duration = round(_time.time() - start, 1)
        combined_output = (proc.stdout or "") + (proc.stderr or "")
        log_lines = [c for l in combined_output.splitlines()[-40:] if (c := _clean_log_line(l))][-20:]

        if proc.returncode == 0:
            status = "pass"
            message = f"Pipeline environment validated in {duration}s — runs end-to-end"
        else:
            status = "fail"
            # Extract first error line from Nextflow output
            err_line = next(
                (l for l in combined_output.splitlines() if "ERROR" in l or "error" in l.lower()),
                f"Exit code {proc.returncode}"
            )
            message = f"Validation failed: {err_line[:200]}"

    except subprocess.TimeoutExpired:
        duration = timeout
        status = "timeout"
        message = f"Validation timed out after {timeout}s — pipeline may require more resources"
    except FileNotFoundError:
        duration = 0.0
        status = "skipped"
        message = "Nextflow binary not found — cannot validate profile locally"
    except Exception as exc:
        duration = round(_time.time() - start, 1)
        status = "fail"
        message = f"Unexpected error: {exc}"

    return {
        "status": status,
        "message": message,
        "log_tail": log_lines,
        "duration_seconds": duration,
        "profile_used": profile,
        "nextflow_path": nf_path,
    }


# ── Output Intelligence ──────────────────────────────────────────────────────────

@router.post("/api/nextflow/analyze-outputs", summary="Analyze Nextflow run outputs and generate findings report")
async def analyze_outputs(request: Request) -> Dict[str, Any]:
    """
    Analyze output files from a completed Nextflow run.

    Runs OutputAnalyzer to classify and parse output files, optionally
    searches PubMed for supporting citations, then writes findings_report.md
    to the output directory.

    Request body:
        run_id: UUID of the execution run
        workflow_id: Workflow identifier (optional)
        output_dir: Local path to the run output directory
        output_files: list of {"name": str, "path": str, "type": str} (optional override)

    Returns:
        Structured findings JSON + path to findings_report.md
    """
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    run_id = body.get("run_id", "")
    workflow_id = body.get("workflow_id", "")
    output_dir = body.get("output_dir", "")
    provided_files = body.get("output_files")  # optional override

    if not run_id:
        raise HTTPException(status_code=400, detail="run_id is required")

    # ── Discover output files if not provided ────────────────────────────────────
    output_files: List[Dict] = []
    if provided_files:
        output_files = provided_files
    elif output_dir and os.path.isdir(output_dir):
        for fname in os.listdir(output_dir):
            fpath = os.path.join(output_dir, fname)
            if os.path.isfile(fpath) and not fname.startswith("."):
                output_files.append({"name": fname, "path": fpath, "type": ""})
    else:
        # Try standard local run directory
        candidate = f"/tmp/nextflow_runs/{run_id}/output"
        if os.path.isdir(candidate):
            output_dir = candidate
            for fname in os.listdir(candidate):
                fpath = os.path.join(candidate, fname)
                if os.path.isfile(fpath) and not fname.startswith("."):
                    output_files.append({"name": fname, "path": fpath, "type": ""})

    if not output_dir:
        output_dir = f"/tmp/nextflow_runs/{run_id}/output"

    # ── Run OutputAnalyzer ───────────────────────────────────────────────────────
    try:
        from galaxy.ai.output_analyzer import OutputAnalyzer
        analyzer = OutputAnalyzer()
        analysis = analyzer.analyze(run_id, workflow_id, output_files)
    except Exception as exc:
        logger.error("[analyze-outputs] OutputAnalyzer failed for run %s: %s", run_id, exc)
        raise HTTPException(status_code=500, detail=f"Analysis failed: {exc}")

    # ── Citation Search (best-effort) ────────────────────────────────────────────
    citations_serialized: List[Dict] = []
    try:
        from galaxy.ai.finding_reporter import FindingReporter, Citation
        reporter = FindingReporter()
        raw_citations = reporter.search_citations(analysis.search_queries, max_per_query=3)
        citations_serialized = [
            {"pmid": c.pmid, "title": c.title, "year": c.year, "relevance": c.relevance}
            for c in raw_citations
        ]
        report = reporter.generate(analysis, raw_citations)
    except Exception as exc:
        logger.warning("[analyze-outputs] Citation/report generation failed: %s", exc)
        # Build report without citations
        from galaxy.ai.finding_reporter import FindingReporter
        reporter = FindingReporter()
        report = reporter.generate(analysis, [])

    # ── Save findings_report.md ──────────────────────────────────────────────────
    report_path: Optional[str] = None
    try:
        report_path = reporter.save_report(report, output_dir)
    except Exception as exc:
        logger.warning("[analyze-outputs] Could not save findings_report.md: %s", exc)

    # ── Save findings_data.json sidecar (structured data for frontend) ───────────
    structured_payload = {
        "run_id": run_id,
        "status": "ready",
        "output_type": analysis.output_type,
        "summary": analysis.summary,
        "key_results": analysis.key_results,
        "citations": citations_serialized,
        "caveats": analysis.caveats,
        "next_steps": analysis.next_steps,
    }
    try:
        import json as _json
        os.makedirs(output_dir, exist_ok=True)
        json_path = os.path.join(output_dir, "findings_data.json")
        with open(json_path, "w", encoding="utf-8") as fh:
            _json.dump(structured_payload, fh, ensure_ascii=False)
    except Exception as exc:
        logger.warning("[analyze-outputs] Could not save findings_data.json: %s", exc)

    return {**structured_payload, "report_path": report_path}


# ---------------------------------------------------------------------------
# Track 3D: LLM-powered workflow error parser
# ---------------------------------------------------------------------------

@router.post("/api/nextflow/parse_error")
async def parse_workflow_error(request: Request):
    """
    Parse Nextflow error logs into a human-friendly summary with suggested fix.
    Uses Claude Haiku.
    """
    import os as _os
    import anthropic as _anthropic

    body = await request.json()
    log_tail = body.get("log_tail", "")
    workflow_path = body.get("workflow_path", "")

    if not log_tail:
        return {"error_type": "unknown", "summary": "No log provided", "can_resume": False}

    PARSE_SYSTEM = """\
You are a bioinformatics workflow error analyst. Given the last lines of a Nextflow workflow log,
output JSON with:
{
  "error_type": "missing_file" | "oom" | "container_pull" | "aws_permission" | "process_failed" | "config_error" | "unknown",
  "failed_process": "PROCESS_NAME or null",
  "human_summary": "1-2 sentence plain English description of what went wrong",
  "suggested_fix": "1-2 sentences on how to fix it",
  "can_resume": true/false
}
"""
    try:
        from galaxy.ai.gemini_flash import call_gemini_flash as _gemini_flash
        import re as _re, json as _json
        text = _gemini_flash(
            messages=[{"role": "user", "content": f"Workflow: {workflow_path}\n\nLog tail:\n{log_tail[-3000:]}"}],
            system=PARSE_SYSTEM,
            max_tokens=300,
            temperature=0.0,
        )
        m = _re.search(r'\{.*\}', text, _re.DOTALL)
        if m:
            return _json.loads(m.group())
    except Exception as e:
        log.warning("[parse_error] LLM parse failed: %s", e)

    return {
        "error_type": "unknown",
        "failed_process": None,
        "human_summary": "Workflow failed. Check logs for details.",
        "suggested_fix": "Review the error log and check parameter values.",
        "can_resume": True,
    }


# ---------------------------------------------------------------------------
# Track 3D: Pre-run cost estimation (GET variant for CostEstimateBadge)
# ---------------------------------------------------------------------------

@router.get("/api/nextflow/estimate_cost")
async def estimate_workflow_cost_get(nextflow_path: str = "", sample_count: int = 10):
    """
    Static cost estimate for a Nextflow workflow before running (GET variant).
    Used by the CostEstimateBadge component.
    """
    import os as _os

    INSTANCE_COSTS = {
        "optimal":        0.10,
        "c5.xlarge":      0.17,
        "c5.2xlarge":     0.34,
        "r5.xlarge":      0.252,
        "m5.xlarge":      0.192,
        "g4dn.xlarge":    0.526,
    }
    RUNTIME_PER_SAMPLE = {
        "rnaseq":             0.25,
        "sarek":              1.5,
        "chipseq":            0.33,
        "methylseq":          0.5,
        "admet":              0.03,
        "cryosparc":          4.0,
        "gromacs":            2.0,
        "default":            0.3,
    }

    instance_type = "optimal"
    cost_per_hour = INSTANCE_COSTS.get(instance_type, 0.10)

    path_lower = (nextflow_path or "").lower()
    runtime_hrs = RUNTIME_PER_SAMPLE["default"]
    matched_wf = "default"
    for wf_key, hrs in RUNTIME_PER_SAMPLE.items():
        if wf_key in path_lower:
            runtime_hrs = hrs
            matched_wf = wf_key
            break

    total_runtime_hrs = runtime_hrs * max(1, sample_count) * 1.2

    return {
        "nextflow_path": nextflow_path,
        "sample_count": sample_count,
        "instance_type": instance_type,
        "matched_workflow": matched_wf,
        "estimated_runtime_hours": round(total_runtime_hrs, 2),
        "cost_min_usd": round(total_runtime_hrs * cost_per_hour * 0.7, 2),
        "cost_max_usd": round(total_runtime_hrs * cost_per_hour * 1.5, 2),
        "assumptions": [
            f"Instance type: {instance_type} (${cost_per_hour}/hr)",
            f"Runtime model: {runtime_hrs}h/sample x {sample_count} samples x 1.2 overhead",
            "Min = spot pricing (70%); Max = on-demand (150%)",
        ],
    }


# ---------------------------------------------------------------------------
# Track 3C: Reproducibility export bundle
# ---------------------------------------------------------------------------

@router.get("/api/nextflow/runs/{run_id}/reproducibility")
async def get_reproducibility_bundle(run_id: str):
    """
    Generate a reproducibility export bundle for a completed Nextflow run.
    Returns a dict of filename -> content for all key run artifacts.
    """
    import os as _os, json as _json, glob as _glob

    output_dir = _os.path.join("/tmp/nextflow_runs", run_id)
    files: dict = {}

    # Collect key reproducibility files
    patterns = [
        "nextflow.config",
        "*.command.sh",
        "*.command.run",
        "*.log",
        "*/versions.yml",
        "pipeline_info/*.html",
        "pipeline_info/*.json",
    ]
    for pattern in patterns:
        for path in _glob.glob(_os.path.join(output_dir, "**", pattern), recursive=True):
            try:
                rel = _os.path.relpath(path, output_dir)
                with open(path) as fh:
                    files[rel] = fh.read()
            except Exception:
                pass

    # Add parameter summary if run is in memory
    run = _runs.get(run_id)
    if run:
        files["run_params.json"] = _json.dumps({
            "run_id": run_id,
            "workflow_path": getattr(run, "nextflow_path", ""),
            "params": getattr(run, "params", {}),
            "started_at": str(getattr(run, "started_at", "")),
        }, indent=2)

    return {"run_id": run_id, "files": files}


# ---------------------------------------------------------------------------
# Liveness probe — is this Nextflow run's process still alive?
# ---------------------------------------------------------------------------

@router.get("/api/nextflow/alive/{run_id}", summary="Check whether a Nextflow run is still alive")
async def get_run_liveness(run_id: str):
    """
    Returns whether the Nextflow process for *run_id* is believed to be running.

    Checks (in order):
    1. _runs dict — process object, poll returncode
    2. timing.json — completed_at present → terminal; log stale → interrupted
    3. nextflow.log mtime — if not updated in >10 min while status=running → likely dead

    Use this for health checks and to detect silent Nextflow deaths.
    """
    import json as _json

    work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
    run_dir   = work_base / run_id
    now       = time.time()

    # ── In-memory check ──────────────────────────────────────────────────────
    with _runs_lock:
        info = _runs.get(run_id)

    if info:
        proc: Optional[subprocess.Popen] = info.get("process")
        if proc is not None:
            rc = proc.poll()
            if rc is None:
                return {"run_id": run_id, "alive": True, "source": "process", "pid": proc.pid}
            return {
                "run_id": run_id, "alive": False, "source": "process",
                "returncode": rc, "status": info.get("status"),
            }
        status = info.get("status", "unknown")
        if status in ("succeeded", "failed", "interrupted"):
            return {"run_id": run_id, "alive": False, "source": "memory", "status": status}

    # ── Disk fallback ────────────────────────────────────────────────────────
    timing_path = run_dir / "timing.json"
    if timing_path.exists():
        try:
            timing = _json.loads(timing_path.read_text())
        except Exception:
            timing = {}
        if timing.get("completed_at"):
            return {
                "run_id": run_id, "alive": False, "source": "timing.json",
                "status": timing.get("status", "terminal"),
                "completed_at": timing["completed_at"],
            }
        nf_log = run_dir / "nextflow.log"
        if nf_log.exists():
            age_s = now - nf_log.stat().st_mtime
            if age_s > 600:
                log.warning(
                    "[liveness] run %s nextflow.log not updated for %.0fs — process likely dead",
                    run_id, age_s,
                )
                return {
                    "run_id": run_id, "alive": False, "source": "log_stale",
                    "log_age_seconds": round(age_s), "status": "interrupted",
                }
            return {
                "run_id": run_id, "alive": True, "source": "log_fresh",
                "log_age_seconds": round(age_s),
            }

    return {"run_id": run_id, "alive": None, "source": "unknown", "status": "not_found"}


def _scrape_batch_job_ids(run_id: str) -> None:
    """Parse .nextflow.log to extract AWS Batch job IDs and emit structured log lines."""
    import re as _re
    work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
    nf_daemon_log = work_base / run_id / "work" / ".nextflow.log"
    if not nf_daemon_log.exists():
        return
    pattern = _re.compile(
        r"Process `([^`]+)` submitted > job=([0-9a-f\-]{36}); work-dir=(\S+)"
    )
    seen: set = set()
    try:
        with open(nf_daemon_log) as fh:
            for line in fh:
                m = pattern.search(line)
                if m and m.group(2) not in seen:
                    seen.add(m.group(2))
                    log.info(
                        "[Nextflow run %s] Batch job submitted: process=%s job_id=%s work_dir=%s",
                        run_id, m.group(1), m.group(2), m.group(3),
                    )
    except Exception as _e:
        log.debug("[Nextflow run %s] Could not scrape Batch job IDs: %s", run_id, _e)
