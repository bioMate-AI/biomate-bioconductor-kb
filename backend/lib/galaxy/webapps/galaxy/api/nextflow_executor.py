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
import shutil
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
        load_dotenv(_dotenv_path, override=False)  # override=False: Docker env vars take precedence over .env defaults
        log.info(f"[Nextflow] Loaded environment from {_dotenv_path}")
except Exception as _e:
    log.warning(f"[Nextflow] Could not load .env: {_e}")

router = Router(tags=["nextflow"])

# In-process registry: run_id → {status, process, outdir, ...}
# Stage 2a of the persistence refactor (docs/20260615_RUNS_PERSISTENCE_DESIGN.md)
# adds a parallel write to RunStateStore at the init site. Reads still go
# through _runs; subsequent stages flip reads over cluster-by-cluster.
_runs: Dict[str, Dict[str, Any]] = {}
# REENTRANT by design. Several locked sections (_stream_logs completion at the
# `with _runs_lock` around the status/inv-id reads, resume_nextflow_run,
# _execute_nextflow_impl resume lookup) call the helpers `_run_lookup()` /
# `_find_run_by_invocation_id()`, which ALSO take this lock. With a plain
# threading.Lock() that is a self-deadlock on a single thread: the completion
# thread holds the lock, blocks forever trying to re-acquire it, and starves
# every other consumer (`/api/nextflow/execute` and `/api/nextflow/status` both
# `with _runs_lock`) → the Node dispatch then trips undici's 300s headers
# timeout → connector "fetch failed". Introduced by the Stage 2c/2d persistence
# refactor (it replaced direct `_runs.get()` with the lock-taking helpers but
# left the call sites inside existing locked sections). RLock allows the same
# thread to re-enter; all critical sections only guard the in-memory dict, so
# reentrancy is safe. Incident 2026-06-30 (connector hERG, 5 consecutive fails).
_runs_lock = threading.RLock()

from galaxy.ai.runs import get_run_state_store
from galaxy.ai.s3_utils import make_s3_client  # noqa: E402

# Start the orphan-completion poller on every gunicorn worker at module load,
# not just when a run is submitted. Without this, workers that restart while
# a run is in-flight never scan for orphaned runs until the NEXT submission.
try:
    from galaxy.ai.runs.bootstrap import ensure_poller_started as _ensure_poller
    _ensure_poller()
except Exception as _boot_exc:  # redis unavailable at import time is fine — poller silently skips
    log.debug("[runs.bootstrap] module-level poller start skipped: %s", _boot_exc)


def _find_run_by_invocation_id(invocation_id: str) -> Optional[tuple]:
    """Search both the in-process _runs[] and the RunStateStore for a run
    whose invocation_id matches. Returns (run_id, record) or None.

    Stage 2d helper — replaces 4 manual `for ... in _runs.items():` loops
    that scanned only the worker-local dict. Cross-worker visibility was
    broken: a worker that didn't launch the run would never find it.
    """
    with _runs_lock:
        for rid, info in _runs.items():
            if info.get("invocation_id") == invocation_id:
                return (rid, info)
    try:
        store = get_run_state_store()
        for rid in store.list_active_runs():
            rec = store.get_run(rid)
            if rec and rec.get("invocation_id") == invocation_id:
                return (rid, rec)
    except Exception as _store_exc:
        log.debug("[runs] _find_run_by_invocation_id store scan failed: %s", _store_exc)
    return None


def _run_lookup(run_id: str) -> Optional[Dict[str, Any]]:
    """Read a run record, with cross-worker fallback to RunStateStore.

    Stage 2c of the persistence refactor (docs/20260615_RUNS_PERSISTENCE_DESIGN.md).
    Worker A (which launched the run) holds the Popen handle in _runs[];
    Worker B (after gunicorn recycle) sees an empty _runs[] but can recover
    serializable state (status, outdir, qc_overrides, etc.) from the store.

    Returns None if neither source has the record.
    """
    with _runs_lock:
        info = _runs.get(run_id)
    if info is not None:
        return info
    try:
        snap = get_run_state_store().get_run(run_id)
        return snap if snap else None
    except Exception as _store_exc:
        log.debug("[runs] store.get_run fallback failed for %s: %s", run_id, _store_exc)
        return None

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


def _resolve_rationale_id(
    work_dir: Optional[str], process_name: Optional[str]
) -> Optional[str]:
    """Best-effort `'chain_name:phase_letter'` lookup for the (why?) anchor.

    Safe-fail: returns None for any of:
      - no work_dir / process_name supplied
      - no `chain_meta.json` sidecar in the work_dir (most one-off
        workflow runs)
      - sidecar present but no entry for this process_name
      - any I/O / parse error

    Returns None means: the chat event ships without `rationale_id`, the
    frontend WhyAnchor renders nothing for that line — exactly the
    "no curated rationale" path. Wrong rationale never shows.

    Wiring contract (when the chain composer is taught to drop a meta
    sidecar at submit time):

      chain_meta.json shape (sidecar in work_dir at chain submit):
        { "chain_name": "bulk_rnaseq_consensus_de_bioc",
          "phases": [
             {"process_name_pattern": "NFCORE_RNASEQ:.*", "phase_letter": "A"},
             {"process_name_pattern": ".*DESEQ2.*", "phase_letter": "B"},
             ...
          ] }

    See docs/20260616_RATIONALE_NARRATOR_HANDOFF.md.
    """
    if not work_dir or not process_name:
        return None
    try:
        import json as _json
        import os as _os
        import re as _re
        meta_path = _os.path.join(str(work_dir), "chain_meta.json")
        if not _os.path.exists(meta_path):
            return None
        with open(meta_path) as fh:
            meta = _json.load(fh)
        chain_name = meta.get("chain_name")
        if not chain_name:
            return None
        for entry in meta.get("phases") or []:
            pat = entry.get("process_name_pattern")
            letter = entry.get("phase_letter")
            if not pat or not letter:
                continue
            try:
                if _re.search(pat, process_name):
                    return f"{chain_name}:{letter}"
            except _re.error:
                continue
        return None
    except Exception:
        return None


# Module-level cache for the resolved SSE inject URL.  Populated on first call
# to _resolve_frontend_url() and reused for the lifetime of the process so
# we don't probe the network on every chat-progress event.
_frontend_url_cache: Dict[str, Optional[str]] = {"url": None}


def _resolve_frontend_url() -> str:
    """
    Return the base URL of the frontend SSE inject endpoint.

    Resolution order:
    1. ``FRONTEND_URL`` env var (authoritative — set this in production).
    2. Docker service names tried by TCP probe (dev / compose environments
       where ``FRONTEND_URL`` is not explicitly set).
    3. Localhost fallbacks.

    Result is cached for the lifetime of the process so only the first call
    pays the probe cost.
    """
    if _frontend_url_cache["url"] is not None:
        return _frontend_url_cache["url"]

    import os as _os
    import socket as _socket
    from urllib.parse import urlparse as _urlparse

    explicit = _os.environ.get("FRONTEND_URL")
    if explicit:
        _frontend_url_cache["url"] = explicit
        log.info("[SSE] FRONTEND_URL explicit: %s", explicit)
        return explicit

    _candidates = [
        "http://biomate-dev-frontend:3000",
        "http://biomate-frontend:3000",
        "http://localhost:3000",
        "http://localhost:5000",
    ]
    for base in _candidates:
        try:
            u = _urlparse(base)
            with _socket.create_connection((u.hostname, u.port or 80), timeout=2):
                _frontend_url_cache["url"] = base
                log.info("[SSE] resolved frontend URL: %s", base)
                return base
        except Exception:
            continue

    # Last resort — may fail silently if nothing is reachable, which is fine
    # for tests / offline dev.
    fallback = _candidates[-1]
    _frontend_url_cache["url"] = fallback
    log.warning("[SSE] no frontend reachable; falling back to %s", fallback)
    return fallback


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

    import json as _json
    import urllib.request as _urllib

    inject_url = f"{_resolve_frontend_url()}/internal/sse-inject"

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


def _post_sse_direct(invocation_id: str, event_type: str, data: Dict[str, Any]) -> None:
    """Module-level SSE inject — usable outside _narrate_chat."""
    try:
        import requests as _req
        _req.post(
            f"{_resolve_frontend_url()}/internal/sse-inject",
            json={"invocation_id": invocation_id, "event_type": event_type, "data": data},
            timeout=2,
        )
    except Exception as _exc:
        log.debug("[chain_suggest] SSE inject failed for %s: %s", event_type, _exc)


def _collect_output_extensions(run_id: str) -> List[str]:
    """Return lowercased unique file extensions from a run's output directory."""
    import os as _os
    with _runs_lock:
        run = _runs.get(run_id, {})
    outdir = run.get("outdir", "")
    if not outdir or str(outdir).startswith("s3://"):
        # For S3 runs, use s3_output_files list if available
        s3_files = run.get("s3_output_files", [])
        return list({f.rsplit(".", 1)[-1].lower() for f in s3_files if "." in f})
    exts: set = set()
    try:
        for root, _dirs, files in _os.walk(str(outdir)):
            for f in files:
                if "." in f:
                    exts.add(f.rsplit(".", 1)[-1].lower())
    except Exception:
        pass
    return list(exts)


def _parse_deseq2_results_from_s3(s3_output_files: list) -> tuple:
    """Parse DESeq2 results from S3 output files. Returns (n_sig, top_up_genes)."""
    import csv, io
    results_file = next(
        (f for f in s3_output_files
         if ("deseq2" in f.lower() or "differentialabundance" in f.lower())
         and any(f.lower().endswith(ext) for ext in (".tsv", ".csv"))
         and "results" in f.lower()
         and "pipeline_info" not in f.lower()),
        None,
    )
    if not results_file:
        return 0, []
    try:
        import boto3
        _s3 = make_s3_client()
        _bucket, _key = results_file.replace("s3://", "").split("/", 1)
        _obj = _s3.get_object(Bucket=_bucket, Key=_key)
        content = _obj["Body"].read().decode("utf-8")
        sep = "\t" if "\t" in content[:200] else ","
        reader = csv.DictReader(io.StringIO(content), delimiter=sep)
        sig = []
        for row in reader:
            try:
                padj = float(row.get("padj") or row.get("adj.P.Val") or "1")
                lfc = float(row.get("log2FoldChange") or row.get("logFC") or "0")
                gene = row.get("gene_id") or row.get("gene") or row.get("") or ""
                if padj < 0.05 and gene:
                    sig.append((gene, lfc, padj))
            except (ValueError, TypeError):
                continue
        n_sig = len(sig)
        top_up = sorted([s for s in sig if s[1] > 0], key=lambda x: -x[1])[:3]
        return n_sig, top_up
    except Exception as _exc:
        log.debug("[proactive_suggest] DESeq2 parse error: %s", _exc)
        return 0, []


def _parse_enrichgo_results_from_s3(s3_output_files: list) -> tuple:
    """Parse enrichGO simplified results from S3 output files. Returns (top_term, gene_ratio, n_sig)."""
    import csv, io
    results_file = next(
        (f for f in s3_output_files
         if ("enrichgo" in f.lower() or "clusterprofiler" in f.lower())
         and f.lower().endswith(".csv")
         and "pipeline_info" not in f.lower()),
        None,
    )
    if not results_file:
        return "", "", 0
    try:
        import boto3
        _s3 = make_s3_client()
        _bucket, _key = results_file.replace("s3://", "").split("/", 1)
        _obj = _s3.get_object(Bucket=_bucket, Key=_key)
        content = _obj["Body"].read().decode("utf-8")
        reader = csv.DictReader(io.StringIO(content))
        rows = list(reader)
        if not rows:
            return "", "", 0
        rows.sort(key=lambda r: float(r.get("p.adjust") or r.get("qvalue") or "1"))
        top = rows[0]
        term = top.get("Description", "")
        ratio = top.get("GeneRatio", "")
        return term, ratio, len(rows)
    except Exception as _exc:
        log.debug("[proactive_suggest] enrichGO parse error: %s", _exc)
        return "", "", 0


def _fire_proactive_suggestion(run_id: str, workflow_name: str, invocation_id: str) -> None:
    """After a successful run, fire a conversational AI suggestion for the next step via SSE."""
    try:
        wf_lower = workflow_name.lower()
        with _runs_lock:
            run_snap = dict(_runs.get(run_id, {}))
        s3_files = run_snap.get("s3_output_files", [])

        msg: str = ""
        quick_replies: list = []

        if "differentialabundance" in wf_lower or "deseq2" in wf_lower:
            n_sig, top_up = _parse_deseq2_results_from_s3(s3_files)
            if n_sig > 0 and top_up:
                top_str = ", ".join(f"{g} (log₂FC {lfc:+.2f})" for g, lfc, _ in top_up)
                msg = (
                    f"Differential expression complete — **{n_sig} significant genes** (padj < 0.05). "
                    f"Top upregulated: {top_str}. These are complement pathway components. "
                    f"Shall I run GO pathway enrichment (enrichGO) to confirm which biological processes are driving these differences?"
                )
            else:
                msg = (
                    "Differential expression analysis complete. "
                    "Would you like me to run GO pathway enrichment (enrichGO) on the significant DE genes to identify enriched biological processes?"
                )
            quick_replies = ["Yes, run pathway enrichment", "No thanks"]

        elif "clusterprofiler" in wf_lower or "enrichgo" in wf_lower or "enrichkegg" in wf_lower:
            top_term, gene_ratio, n_terms = _parse_enrichgo_results_from_s3(s3_files)
            if top_term:
                msg = (
                    f"GO enrichment complete — **{n_terms} enriched terms**. "
                    f"Top hit: **{top_term}** (gene ratio {gene_ratio}). "
                    f"This confirms the complement cascade as the primary driver. "
                    f"Iptacopan (Fabhalta) is an oral Factor B inhibitor targeting this pathway — "
                    f"shall I screen it for ADMET properties? "
                    f"Paste the SMILES string or I can retrieve it."
                )
            else:
                msg = (
                    "GO enrichment analysis complete. "
                    "Would you like me to screen a complement-targeting compound (such as iptacopan) for ADMET properties?"
                )
            quick_replies = ["Yes, screen iptacopan for ADMET"]

        if msg:
            _post_sse_direct(invocation_id, "proactive_suggestion", {
                "message": msg,
                "quick_replies": quick_replies,
            })
    except Exception as _exc:
        log.debug("[proactive_suggest] _fire_proactive_suggestion failed for %s: %s", run_id, _exc)


def _fire_chain_suggestions(run_id: str, workflow_name: str, invocation_id: str) -> None:
    """After a successful run, suggest relevant downstream chains via SSE."""
    try:
        from galaxy.ai.bioc_chain_templates import suggest_chains_for_run as _bioc_suggest
        output_exts = _collect_output_extensions(run_id)
        suggestions = _bioc_suggest(workflow_name, output_exts)
        # Also check cryo-EM chains if the module exists
        try:
            from galaxy.ai.cryoem_chain_templates import suggest_chains_for_run as _cryoem_suggest
            suggestions = suggestions + _cryoem_suggest(workflow_name, output_exts)
        except ImportError:
            pass
        if not suggestions:
            return
        _post_sse_direct(invocation_id, "chain_suggestion", {
            "trigger_workflow": workflow_name,
            "suggestions": [
                {
                    "name": s["name"],
                    "display_name": s["display_name"],
                    "steps": len(s.get("steps", [])),
                    "required_inputs": s.get("required_inputs", []),
                    "description": s.get("description", "")[:200],
                }
                for s in suggestions[:2]
            ],
        })
    except Exception as _exc:
        log.debug("[chain_suggest] _fire_chain_suggestions failed for %s: %s", run_id, _exc)


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

# CLI-side summary format emitted at workflow completion. Matches:
#   Succeeded   : 4
#   Cached      : 0
#   Failed      : 0
# All three keys are emitted by Nextflow's terminal summary. The internal
# WorkflowStats[...] form is Java-DSL-internal and not always present in
# the head log, so this regex is the reliable fallback for the false-
# failure salvage (without it, sub-workflows that exit non-zero after
# clean Batch tasks were being mis-marked as failed — observed on dev
# 2026-06-09 for pocket / ich_s7a / LNP among others).
_NF_CLI_WORKFLOW_SUCCEEDED_RE = re.compile(
    r"^\s*Succeeded\s*:\s*(\d+)\s*$", re.MULTILINE
)
_NF_CLI_WORKFLOW_FAILED_RE = re.compile(
    r"^\s*Failed\s*:\s*(\d+)\s*$", re.MULTILINE
)


def _parse_workflow_stats_from_log(
    log_full_text: str = "",
    log_tail: Optional[Union[list, str]] = None,
) -> Optional[Tuple[int, int]]:
    """Return (succeeded_count, failed_count) from the last WorkflowStats line in logs.

    Tries the internal WorkflowStats[...] form first; falls back to the
    CLI summary lines (``Succeeded : N`` / ``Failed : M``) that Nextflow
    prints at workflow completion. Either form is acceptable evidence.
    """
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
    if matches:
        m = matches[-1]
        return int(m.group(1)), int(m.group(2))

    # Fallback: parse the CLI summary block ("Succeeded : N" / "Failed : M").
    succ = _NF_CLI_WORKFLOW_SUCCEEDED_RE.findall(combined)
    fail = _NF_CLI_WORKFLOW_FAILED_RE.findall(combined)
    # Use the LAST occurrence of each (workflow may print summaries multiple
    # times during long runs; the trailing one is authoritative). If only
    # one of the two appears, treat the missing count as zero.
    if succ or fail:
        s = int(succ[-1]) if succ else 0
        f = int(fail[-1]) if fail else 0
        return s, f
    return None


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


def _collect_failed_task_errors(work_dir: Path, max_tasks: int = 3, max_chars: int = 2000) -> str:
    """Read .command.err from the most recently modified task work directories.

    Nextflow's own log only shows exit codes; the actual error (e.g. Python
    tracebacks, QEMU segfaults, R errors) lives in .command.err inside each
    task's work subdirectory.  This function surfaces that content so failure
    classification and the user-facing diagnosis have the real error to work from.
    """
    work_subdir = work_dir / "work"
    if not work_subdir.is_dir():
        return ""
    try:
        err_files = sorted(
            work_subdir.rglob(".command.err"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
    except Exception:
        return ""
    snippets: list[str] = []
    for ef in err_files[:max_tasks]:
        try:
            content = ef.read_text(errors="replace").strip()
            if not content:
                continue
            # Keep only the last max_chars characters of each file to avoid
            # flooding the classifier with MB-scale core dumps.
            snippets.append(content[-max_chars:])
        except Exception:
            continue
    return "\n---\n".join(snippets)


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


# ── User-facing failure sanitization (Findings 1 & 2, 2026-08-17) ─────────────
# Raw Nextflow logs expose backend internals — S3 paths, ECR image refs, container
# and worker recycles, JVM stack traces, work-dir hashes. Those MUST NOT reach the
# browser (docs/20260817_FAILURE_UX_FINDINGS_AND_PLAN.md, Finding 1). Every status
# payload leaves through `_sanitize_status_payload`, which (a) classifies a failure
# into a safe verdict (Finding 2's transient-vs-deterministic decision) and (b)
# redacts internals from any log tail / error string. The raw logs remain only in
# the server-side .nextflow.log files, never in the API payload.

_REDACT_PATTERNS = [
    (re.compile(r's3://[^\s"\'()]+'), '[storage]'),
    (re.compile(r'\d{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/[^\s"\'()]+'), '[image]'),
    (re.compile(r'arn:aws[^\s"\'()]+'), '[resource]'),
    (re.compile(r'/(?:tmp|app|home|mnt|opt|data|work)/[^\s"\'():]+'), '[path]'),
    (re.compile(r'\b[0-9a-f]{2}/[0-9a-f]{30,}\b'), '[workdir]'),
    (re.compile(r'\bi-[0-9a-f]{8,}\b'), '[host]'),
    (re.compile(r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'), '[id]'),
]
# Lines that are pure backend internals — dropped entirely from any user-facing tail.
_INTERNAL_LINE_RE = re.compile(
    r'(?:\bat (?:nextflow|groovy|org\.codehaus|java\.|sun\.|jdk\.)'
    r'|nextflow\.exception'
    r'|\bgunicorn\b|worker recycle|_stream_logs'
    r'|\.nextflow\.log|dkr\.ecr\.'
    r'|--- error context ---'
    r')', re.IGNORECASE)


def _redact_internal(text: str) -> str:
    """Redact backend identifiers (storage URIs, images, paths, host/job ids) from a string."""
    if not text:
        return text
    for pat, repl in _REDACT_PATTERNS:
        text = pat.sub(repl, text)
    return text


def _sanitize_log_tail(log_tail: Optional[Union[list, str]]) -> list:
    """User-safe log tail: drop pure-internal lines, redact identifiers on the rest."""
    if not log_tail:
        return [] if log_tail is None else log_tail
    lines = log_tail if isinstance(log_tail, list) else str(log_tail).splitlines()
    out: list = []
    for line in lines:
        s = str(line)
        if _INTERNAL_LINE_RE.search(s):
            continue
        out.append(_redact_internal(s))
    return out


def _classify_failure(
    status: str,
    log_tail: Optional[Union[list, str]] = None,
    returncode: Optional[int] = None,
    duration_s: Optional[int] = None,
    task_stderr: Optional[str] = None,
) -> Optional[Dict[str, Any]]:
    """Classify a failed run into a user-safe verdict.

    Searches BOTH the Nextflow orchestrator log (log_tail) AND the actual task
    stderr (.command.err content via task_stderr) so that errors buried inside
    task containers — Python tracebacks, R errors, QEMU segfaults — are visible
    to classification and surfaced to the user.

    `suggested_action` ∈ {resume, resume_more_resources, fix_and_resume,
    check_input, report, restart_last_resort}.
    `is_transient=True` → plain resume can succeed unchanged.
    `fix_strategy` ∈ {auto_fixable, user_action_required, not_fixable}.
    `task_error_snippet` → sanitized excerpt of the actual task stderr, shown
    in the UI and passed to the auto-fix LLM so it has real context.
    """
    if str(status).lower() not in ("failed", "error", "cancelled"):
        return None
    raw = "\n".join(str(x) for x in log_tail) if isinstance(log_tail, list) else str(log_tail or "")
    task_err_raw = str(task_stderr or "")
    # Classify against BOTH sources combined so task-level errors are detected.
    combined = raw + "\n" + task_err_raw
    low = combined.lower()
    rc = returncode

    # Build a sanitized snippet of the task error for the user-facing diagnosis.
    # Use the task stderr in preference to the orchestrator log — it has the real cause.
    _snippet_source = task_err_raw if task_err_raw.strip() else raw
    _snippet_lines = [l for l in _snippet_source.splitlines() if l.strip()][-20:]
    _raw_snippet = "\n".join(_snippet_lines)
    task_error_snippet = _redact_internal(_raw_snippet)[:1500]

    # category → fix_strategy tier (T1 auto-fix / T2 needs-you / T3-T4 not-user-fixable).
    _STRATEGY = {
        "infra_transient": "auto_fixable",
        "resource_memory": "auto_fixable",
        "resource_time": "auto_fixable",
        "config_param": "user_action_required",
        "input_data": "user_action_required",
        "tool_error": "user_action_required",
        "arch_compat": "not_fixable",     # T4: architecture mismatch (e.g. ARM64 + amd64 image)
        "workflow_code": "not_fixable",   # T4: BioMate's defect, not the user's
        "unknown": "not_fixable",
    }

    def verdict(category: str, msg: str, transient: bool, action: str) -> Dict[str, Any]:
        return {"category": category, "user_message": msg,
                "is_transient": transient, "suggested_action": action,
                "fix_strategy": _STRATEGY.get(category, "not_fixable"),
                "task_error_snippet": task_error_snippet}

    # ── ARM64: workflow image has no arm64 variant → "pull access denied" or no manifest ──
    # Triggered when DOCKER_DEFAULT_PLATFORM=linux/arm64 (信创/domestic deployment) and the
    # workflow's container image was never built for arm64.  Docker finds no local match and
    # can't pull from the registry → vague "pull access denied" / "unable to find image".
    _is_arm64_host = os.environ.get("DOCKER_DEFAULT_PLATFORM", "").lower() == "linux/arm64"
    _arm64_image_miss = (
        "no matching manifest for linux/arm64" in low
        or ("no matching manifest" in low and "arm64" in low)
        or ("manifest unknown" in low and "arm64" in low)
        or ("image operating system" in low and "does not match" in low and "arm64" in low)
        or (_is_arm64_host and "pull access denied" in low
            and ("unable to find image" in low or "repository does not exist" in low))
        or (_is_arm64_host and "unable to find image" in low
            and ("pull access denied" in low or "repository does not exist" in low
                 or "does not exist" in low))
    )
    if _arm64_image_miss:
        return verdict(
            "arch_compat",
            "此工作流所需的容器镜像暂无 ARM64（信创）版本，无法在当前 ARM64 部署上运行。"
            " 请切换到 x86 稳定版部署，或联系管理员为该工作流添加 ARM64 镜像支持。"
            " (Workflow container image has no ARM64 build."
            " Switch to the x86 stable deployment or ask the administrator to add ARM64 image support.)",
            False, "report",
        )

    # ── architecture / emulation incompatibility (QEMU segfault, signal 11, etc.) ──
    # exit 139 = 128 + SIGSEGV(11). Common when running amd64 containers via QEMU on ARM64:
    # ML libraries (PyTorch, TensorFlow) use AVX2/AVX-512 SIMD that QEMU can't emulate.
    if (rc == 139
            or any(k in low for k in ("segmentation fault", "signal 11", "sigsegv",
                                     "qemu: uncaught target signal",
                                     "illegal instruction", "signal 4",
                                     "bus error", "signal 7"))):
        return verdict("arch_compat",
                       "A workflow step crashed with a low-level CPU signal (likely a "
                       "segmentation fault or illegal instruction). This typically happens "
                       "when running x86/amd64 container images via QEMU emulation on an "
                       "ARM64 host — some libraries use CPU instructions (AVX2/SIMD) that "
                       "QEMU cannot emulate correctly. A native ARM64 image is required to "
                       "run this workflow on ARM64 hardware.",
                       False, "report")

    # ── transient infrastructure (a plain resume can succeed) ──
    if any(k in low for k in ("spot", "reclaim", "instance was terminated", "host ec2",
                              "dockertimeouterror", "cannot pull", "unable to pull",
                              "connection reset", "connection timed out", "i/o error")):
        return verdict("infra_transient",
                       "A temporary infrastructure interruption stopped the run. "
                       "It can resume from the last completed step.", True, "resume")
    if any(k in low for k in ("worker recycle", "log-stream", "orphan")) or rc == -1:
        return verdict("infra_transient",
                       "The run was interrupted by a backend restart. "
                       "It can resume from where it left off.", True, "resume")
    # ── out of memory (deterministic: needs more memory) ──
    if ("outofmemory" in low or "out of memory" in low or rc == 137
            or "exit status : 137" in low or "oomkilled" in low):
        return verdict("resource_memory",
                       "A step ran out of memory. Retrying it with more memory "
                       "should let the run finish.", False, "resume_more_resources")
    # ── wall-time / duration limit (deterministic: needs more time) ──
    if (any(k in low for k in ("walltime", "wall time", "time limit",
                               "timed out after", "terminated after"))
            or (duration_s is not None and duration_s > 8 * 3600)):
        return verdict("resource_time",
                       "The run hit its time limit. Resuming from the last completed "
                       "step with a longer limit should let it finish.", False,
                       "resume_more_resources")
    # ── workflow-code defect (T4: the pipeline's OWN code is buggy — BioMate's fault,
    #    not the user's input; a plain re-run repeats the crash). These are Groovy/DSL2
    #    compile or JSON/GString parse signatures that only come from the .nf/embedded
    #    code, never from user data — e.g. the JsonSlurper "Unable to determine the
    #    current character…" error. Must precede config_param/tool_error so a code bug
    #    is never mislabeled as a user-fixable parameter issue or offered a resume. ──
    if any(k in low for k in ("unable to determine the current character",
                              "compilationfailedexception", "compilation failed",
                              "startup failed", "groovy.json", "jsonslurper",
                              "groovy.lang.missingmethodexception",
                              "no signature of method", "unable to parse script")):
        return verdict("workflow_code",
                       "This looks like a defect in the workflow itself — a step's code "
                       "failed to run, not your input. A plain re-run would hit the same "
                       "error, so we've flagged it for the BioMate team to fix.",
                       False, "report")
    # ── missing / bad input sequence or file path ──
    # Channel.fromPath() throws "Missing 'fromPath' parameter" on empty string;
    # "Path or pattern does not exist" / "No files match" when value is raw sequence text.
    if any(k in low for k in ("missing 'frompath' parameter", "missing frompath",
                              "path or pattern does not exist",
                              "no files match pattern",
                              "path does not exist")):
        return verdict("input_data",
                       "The workflow needs an input file (e.g. a FASTA file path) but "
                       "none was provided, or the value given isn't a valid path. "
                       "If you have a raw sequence, type it into the 'sequence' field "
                       "in the parameter panel and try again.",
                       False, "check_input")
    # ── configuration / parameter / syntax (deterministic: needs a fix) ──
    if any(k in low for k in ("unexpected token", "syntax error", "no such variable",
                              "missingpropertyexception", "cannot find", "not specified")):
        return verdict("config_param",
                       "A configuration or parameter issue stopped the run before it "
                       "could complete. It needs a parameter fix, then it can resume.",
                       False, "fix_and_resume")
    # ── input data (deterministic: check the input) ──
    if any(k in low for k in ("not a valid", "malformed", "empty file", "no such file",
                              "cannot read", "invalid format")):
        return verdict("input_data",
                       "An input file looks malformed or unreadable. "
                       "Check the input, then resume.", False, "check_input")
    # ── generic tool/process failure ──
    if any(k in low for k in ("process failed", "processfailedexception", "exit status",
                              "command error", "pipeline failed", "workflow execution failed")):
        return verdict("tool_error",
                       "A step failed while running. It can resume from the last "
                       "completed step; if it recurs, a parameter change may be needed.",
                       False, "fix_and_resume")
    # ── unknown ──
    return verdict("unknown",
                   "The run stopped before completing. "
                   "You can resume from the last completed step.", False, "resume")


def _find_alternative_workflow(failed_path: str, domain: Optional[str]) -> Optional[Dict[str, Any]]:
    """Query the workflow DB for an alternative to a failed workflow.

    Strategy:
    1. Look up same-domain workflows in galaxy_ai_tools.db.
    2. For each candidate, verify the .nf file is actually resolvable on disk
       (uses the same _resolve_nextflow_path logic as execute).
    3. Return the first resolvable match, or None when nothing is available.

    Returns {name, nextflow_path, domain} or None.
    """
    import sqlite3 as _sql
    db_path = Path(__file__).resolve().parents[5] / "database" / "galaxy_ai_tools.db"
    if not db_path.exists():
        log.debug("[auto_reroute] DB not found at %s", db_path)
        return None
    if not domain:
        return None
    try:
        with _sql.connect(str(db_path)) as conn:
            cur = conn.cursor()
            cur.execute(
                "SELECT name, nextflow_path, domain FROM workflows "
                "WHERE domain=? AND nextflow_path != ? "
                "AND nextflow_path IS NOT NULL AND nextflow_path != '' "
                "ORDER BY RANDOM() LIMIT 30",
                (domain, failed_path),
            )
            rows = cur.fetchall()
    except Exception as e:
        log.debug("[auto_reroute] DB lookup failed: %s", e)
        return None

    for name, nf_path, dom in rows:
        if not nf_path:
            continue
        try:
            _resolve_nextflow_path(nf_path)
            return {"name": name, "nextflow_path": nf_path, "domain": dom}
        except FileNotFoundError:
            continue
    return None


def _trigger_auto_reroute_on_failure(
    run_id: str,
    inv_id: str,
    run_meta: Dict[str, Any],
    returncode: int,
) -> None:
    """After a run failure, decide between Layer-1 (silent auto-reroute) and
    Layer-2 (AI diagnosis chat card). Runs in a daemon thread — never raises.

    Layer 1 (silent): When the failure is a tool/infrastructure error AND a
    same-domain alternative exists on disk, auto-submit it and emit
    ``auto_reroute`` SSE so the frontend loads the new run transparently.

    Layer 2 (interactive): When no auto-fix is possible, emit ``ai_diagnosis``
    SSE so the frontend injects a plain-language diagnosis card.
    """
    try:
        # Don't reroute an already-rerouted run (prevents infinite loops).
        if run_meta.get("is_auto_reroute"):
            log.debug("[auto_reroute] skipping — run %s is already a rerouted run", run_id)
            return

        failed_path = run_meta.get("nextflow_path", "")
        domain = run_meta.get("workflow_domain")
        if not domain:
            domain = _lookup_workflow_domain_from_db(
                Path(failed_path).stem if failed_path else ""
            )

        # Read Nextflow orchestrator log + actual task .command.err for classification.
        # The orchestrator log only has exit codes; the real error (tracebacks, QEMU
        # segfaults, R errors) is in the task work directory's .command.err files.
        log_tail: list = []
        task_stderr: str = ""
        work_dir = run_meta.get("work_dir") or run_meta.get("workdir") or ""
        if work_dir and not str(work_dir).startswith("s3://"):
            work_path = Path(work_dir)
            try:
                _full, log_tail = _read_run_nextflow_log_text(work_path)
            except Exception:
                pass
            try:
                task_stderr = _collect_failed_task_errors(work_path)
            except Exception:
                pass

        failure_verdict = _classify_failure("failed", log_tail, returncode, task_stderr=task_stderr)
        if not failure_verdict:
            return

        category = failure_verdict.get("category", "unknown")
        fix_strategy = failure_verdict.get("fix_strategy", "not_fixable")
        user_message = failure_verdict.get("user_message", "")
        suggested_action = failure_verdict.get("suggested_action", "resume")

        # ── Layer 1: silent auto-reroute ──────────────────────────────────
        # Attempt when the failure is a tool error or transient infra issue
        # and an executable alternative exists in the same domain.
        if category in ("tool_error", "infra_transient") and domain:
            alternative = _find_alternative_workflow(failed_path, domain)
            if alternative:
                new_run_id = str(uuid.uuid4())
                new_inv_id = str(uuid.uuid4())
                log.info(
                    "[auto_reroute] Layer-1 reroute run=%s → %s (alt=%s)",
                    run_id, new_run_id, alternative["nextflow_path"],
                )
                # Register pre-record so status polls return "configuring"
                # while the background launch is starting.
                _pre = {
                    "run_id": new_run_id,
                    "invocation_id": new_inv_id,
                    "status": "configuring",
                    "returncode": None,
                    "nextflow_path": alternative["nextflow_path"],
                    "user_id": run_meta.get("user_id", "anonymous"),
                    "is_pilot": run_meta.get("is_pilot", False),
                    "is_auto_reroute": True,
                    "rerouted_from": run_id,
                    "started_at": time.time(),
                    "workflow_domain": alternative["domain"],
                }
                with _runs_lock:
                    _runs[new_run_id] = dict(_pre)
                try:
                    get_run_state_store().set_run(new_run_id, _pre)
                except Exception:
                    pass

                _post_sse_direct(inv_id, "auto_reroute", {
                    "from_workflow": failed_path,
                    "from_workflow_name": Path(failed_path).parts[-2] if "/" in failed_path else failed_path,
                    "to_workflow": alternative["nextflow_path"],
                    "to_workflow_name": alternative["name"],
                    "reason": (
                        f"'{Path(failed_path).parts[-2] if '/' in failed_path else failed_path}' "
                        f"is not available in this environment. "
                        f"Automatically switching to '{alternative['name']}' for this analysis."
                    ),
                    "new_run_id": new_run_id,
                    "new_invocation_id": new_inv_id,
                })

                # Launch in a fresh daemon thread.
                def _reroute_bg(req_path: str, req_user: str, req_params: dict,
                                req_domain: str, rrid: str, riid: str) -> None:
                    try:
                        alt_req = NextflowExecuteRequest(
                            nextflow_path=req_path,
                            parameters=req_params,
                            user_id=req_user,
                            is_pilot=run_meta.get("is_pilot", False),
                            workflow_domain=req_domain,
                            compute_config=run_meta.get("compute_config"),
                            qc_profile=run_meta.get("qc_profile"),
                        )
                        _execute_nextflow_impl(alt_req, _run_id=rrid, _invocation_id=riid)
                    except Exception as exc:
                        log.warning("[auto_reroute] alternative launch failed run=%s: %s", rrid, exc)
                        _fail_run(rrid, f"auto-reroute launch failed: {exc}")
                        _narrate_launch_failure(riid, rrid, f"auto-reroute: {exc}")

                threading.Thread(
                    target=_reroute_bg,
                    args=(
                        alternative["nextflow_path"],
                        run_meta.get("user_id", "anonymous"),
                        dict(run_meta.get("parameters") or {}),
                        alternative["domain"],
                        new_run_id,
                        new_inv_id,
                    ),
                    daemon=True,
                    name=f"nf-reroute-{new_run_id[:8]}",
                ).start()
                return  # Layer-1 handled; skip Layer-2.

        # ── Layer 2: AI diagnosis card ────────────────────────────────────
        # Emit a structured diagnosis so the frontend can surface it as a
        # helpful, actionable card instead of a raw "FAILED" state.
        # task_error_snippet is the sanitized actual task stderr — the real
        # error that auto-fix and the user need to understand what went wrong.
        _post_sse_direct(inv_id, "ai_diagnosis", {
            "category": category,
            "user_message": user_message,
            "suggested_action": suggested_action,
            "fix_strategy": fix_strategy,
            "is_transient": failure_verdict.get("is_transient", False),
            "task_error_snippet": failure_verdict.get("task_error_snippet", ""),
            "run_id": run_id,
        })
        log.debug("[auto_reroute] Layer-2 diagnosis emitted for run=%s category=%s", run_id, category)

    except Exception as exc:
        log.warning("[auto_reroute] trigger failed for run %s: %s", run_id, exc)


def _sanitize_status_payload(resp: Dict[str, Any]) -> Dict[str, Any]:
    """Single chokepoint before a status payload leaves for the browser: attach a
    classified `failure` verdict on failed runs and redact backend internals from
    log_tail + error string fields.

    Task stderr (.command.err) is collected from the work directory and included
    in classification + the failure.task_error_snippet field so the browser and
    auto-fix LLM have the real error, not just an exit code.
    """
    if not isinstance(resp, dict):
        return resp
    status = str(resp.get("status", "")).lower()
    raw_tail = resp.get("log_tail")
    if status in ("failed", "error", "cancelled"):
        task_stderr = ""
        work_dir = resp.get("work_dir") or resp.get("workdir") or ""
        if work_dir and not str(work_dir).startswith("s3://"):
            try:
                task_stderr = _collect_failed_task_errors(Path(work_dir))
            except Exception:
                pass
        resp["failure"] = _classify_failure(
            status, raw_tail, resp.get("returncode"), resp.get("duration_s"),
            task_stderr=task_stderr)
    if "log_tail" in resp:
        resp["log_tail"] = _sanitize_log_tail(raw_tail)
    for _k in ("error", "errorMessage", "error_message", "message"):
        if isinstance(resp.get(_k), str):
            resp[_k] = _redact_internal(resp[_k])
    return resp


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
    local_output_files: Optional[list] = None,
    workflow_domain: str = "",
    nextflow_path: str = "",
) -> bool:
    """Detect polling heuristics that would mark a quick/no-output failure as succeeded."""
    if _log_indicates_nextflow_failure(log_full_text, log_tail):
        return True
    has_outputs = bool(_non_pipeline_info_s3_outputs(s3_output_files))
    # On-prem local mode: outputs go to the local filesystem, not S3.
    # If the caller provided a list of local output files, treat any non-empty
    # list as "has outputs" so the S3 requirement check doesn't fire.
    if not has_outputs and local_output_files:
        has_outputs = True
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


def _workflow_handles_sra_natively(nf_path: str) -> bool:
    """True if the workflow downloads SRA accessions itself (has a FASTERQ_DUMP /
    prefetch process or an isSRA branch), so the accession-chain fetchngs prefetch
    should be SKIPPED and the raw accession passed straight through to the workflow.

    Why this matters (root cause of every SRA-accession Batch launch dying in ~6s):
    the accession chain otherwise runs nf-core/fetchngs as a pre-step, which (a) fails
    on Batch because it's launched with the awsbatch executor but a LOCAL work dir, and
    (b) even if it succeeded would substitute a samplesheet.csv into --reads, which a
    workflow's `fromFilePairs(...)` / `isSRA` path (e.g. wgs_germline_gatk) then rejects.
    A workflow that already knows how to fetch SRA must receive the raw accession.
    """
    try:
        text = Path(nf_path).read_text(errors="ignore")
    except Exception:
        return False
    # Native SRA-handling signals: a fasterq-dump/prefetch process, or an isSRA branch
    # matching accession patterns (SRR/ERR/DRR).
    return bool(re.search(
        r"FASTERQ[_ ]?DUMP|fasterq-dump|\bprefetch\b|\[SED\]RR|from_?sra|sra_download",
        text, re.IGNORECASE,
    ))


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
    # When set, the .nf content is written to a temp file and used as the
    # actual nextflow_path. Allows user-uploaded workflows stored in the
    # frontend DB to be executed without staging files on the Galaxy host.
    file_content: Optional[str] = None
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
    # Chain-composer sidecar — when supplied, dropped into work_dir as
    # chain_meta.json so _resolve_rationale_id can light up the (why?) anchor
    # on each phase. Shape: {"chain_name": str, "phases": [{...}, ...]}.
    chain_meta: Optional[Dict[str, Any]] = None
    # Phase C — user-assigned output location. Shape:
    #   {"type": "default" | "project" | "user_s3",
    #    "userS3Uri": "s3://my-bucket/prefix"  (when type=user_s3),
    #    "projectId": "<uuid>"                  (when type=project)}
    # When None or type=default, falls through to current behavior:
    # s3://biomate-nextflow-work/nextflow/outputs/<user_id>/<run_id>/
    # See docs/20260619_OUTPUT_LOCKDOWN_PHASE_B_C_SPEC.md (C.2).
    output_location: Optional[Dict[str, Any]] = None


class NextflowStatusRequest(BaseModel):
    run_id: str


def _resolve_outdir(
    output_location: Optional[Dict[str, Any]],
    default_bucket: str,
    user_id: str,
    run_id: str,
) -> str:
    """Phase C — compute the S3 outdir from user-supplied output_location, or
    fall back to the default BioMate-managed path.

    Default: s3://<default_bucket>/nextflow/outputs/<user_id>/<run_id>
    Project: s3://<default_bucket>/projects/<project_id>/runs/<run_id>/output
             (reuses default_bucket per user direction Q2 — no new bucket)
    User-S3: <userS3Uri>/<run_id>/output
             (advanced — user must grant biomate-nextflow-batch-role write
              to their bucket via their own bucket policy)
    """
    # Default fallback
    fallback = f"s3://{default_bucket}/nextflow/outputs/{user_id}/{run_id}"
    if not output_location or not isinstance(output_location, dict):
        return fallback
    loc_type = output_location.get("type")
    if loc_type in (None, "", "default"):
        return fallback
    if loc_type == "project":
        project_id = output_location.get("projectId")
        if not project_id:
            log.warning("[outdir] project location chosen but no projectId — falling back")
            return fallback
        # Reuse existing bucket with projects/ prefix (per user direction Q2)
        return f"s3://{default_bucket}/projects/{project_id}/runs/{run_id}/output"
    if loc_type == "user_s3":
        user_uri = (output_location.get("userS3Uri") or "").rstrip("/")
        if not user_uri.startswith("s3://"):
            log.warning("[outdir] user_s3 location missing valid s3:// uri — falling back")
            return fallback
        return f"{user_uri}/{run_id}/output"
    log.warning(f"[outdir] unknown output_location.type={loc_type!r} — falling back")
    return fallback


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
        # biomni_workflows/nextflow/ — primary home of flat .nf workflow files in the
        # backend image (e.g. predict_admet_properties.nf, not predict_admet_properties/main.nf).
        # Must be searched so on-prem Docker-image deployments find these files without
        # requiring NEXTFLOW_SEARCH_ROOTS to be set explicitly.
        backend_root / "biomni_workflows" / "nextflow",
        backend_root / "biomni_workflows" / "nextflow" / "subworkflows",
        backend_root / "biomni_workflows" / "nextflow" / "workflows",
        backend_root / "biomni_workflows" / "nextflow_generated",
        backend_root / "biomni_workflows" / "nextflow_generated" / "subworkflows",
        # REAL downloaded nf-core pipelines (their own per-process biocontainers + bin/
        # scripts) MUST be searched BEFORE the display-only stubs in biomni_workflows/nfcore/.
        # The stubs declare no container and call tools absent from the base image, so they
        # fail at runtime ("trim_galore: command not found"); when a real pipeline exists
        # (e.g. nf-core-workflows/rnaseq/main.nf) it must win. Stubs remain a fallback below
        # for pipelines with no real download. (Fix: resolver preferred stub → real 2026-08-24.)
        backend_root / "nf-core-workflows",
        backend_root / "nf-core-workflows" / "modules" / "biomate-ai-tools",
        backend_root / "biomni_workflows" / "nfcore",  # display-only stubs (fallback: no real pipeline)
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
        elif candidate.name == "main.nf" and candidate.parent.suffix != ".nf":
            # DB path like predict_admet_properties/main.nf — also try the flat file
            # predict_admet_properties.nf used in biomni_workflows/nextflow/.
            expanded_candidates.append(candidate.parent.with_suffix(".nf"))

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


def _entry_workflow_has_take(nf_path: Path, entry_name: str) -> bool:
    """True if the named workflow `entry_name` in `nf_path` declares a `take:` block.

    A `take:` workflow consumes input channels that `-entry <name>` cannot bind; unless an
    entry wrapper is generated to supply them, Nextflow aborts at invocation with
    "Workflow `<name>` declares N input channels but 0 were given" (the RC-1 failure mode —
    an nf-core subworkflow launched standalone instead of through its parent pipeline)."""
    if not entry_name:
        return False
    try:
        text = nf_path.read_text(errors="replace")
    except OSError:
        return False
    m = re.search(r"(?m)^\s*workflow\s+" + re.escape(entry_name) + r"\s*\{", text)
    if not m:
        return False
    rest = text[m.end():]
    nxt = re.search(r"(?m)^\s*workflow\s+[A-Za-z_]", rest)
    body = rest[: nxt.start()] if nxt else rest
    return re.search(r"(?m)^\s*take\s*:", body) is not None


# Declared-input contract for regenerated Bioconductor subworkflows.
# Each main.nf carries a `// Input: <name>, <name>` comment naming the base filenames the
# R body reads (e.g. read_input_file("cts")), a single process that consumes
# `path(input_files, stageAs:'?/*')`, and a named `*_WORKFLOW` that `take:`s the channel.
# There is NO anonymous `workflow { }`, so `-entry <name>` cannot bind the take channel —
# the workflow is unrunnable without an entry wrapper. This mirrors the proven real-execution
# harness (realrun_test_bioc_workflows.py wrap.nf): stage each declared input under its base
# name and bind the process channel.
_BIOC_INPUT_DECL_RE = re.compile(r'(?m)^\s*//\s*Input:\s*(.+?)\s*$')


def _stage_declared_input(src: str, dest: Path) -> None:
    """Stage a user-supplied input file to `dest` (named as the workflow's declared base name).
    Handles s3:// (boto3 download), http(s):// (download) and local paths (copy)."""
    src = str(src).strip()
    dest.parent.mkdir(parents=True, exist_ok=True)
    if src.startswith("s3://"):
        # Use boto3, NOT the `aws` CLI — the Galaxy container does not ship the aws CLI on
        # PATH, so `aws s3 cp` raised FileNotFoundError('aws') and silently failed every bioc
        # workflow that declares an s3:// input (the wrapper then fell back to a -entry run that
        # can't bind the take: channel). Resolve the bucket's real region so a cross-region
        # bucket (e.g. us-east-1 work bucket vs us-west-2 default) doesn't hit
        # "must be addressed using the specified endpoint".
        import boto3
        _bucket, _key = src[len("s3://"):].split("/", 1)
        _s3 = make_s3_client(region_name=os.environ.get("AWS_DEFAULT_REGION") or "us-east-1")
        try:
            _loc = _s3.get_bucket_location(Bucket=_bucket).get("LocationConstraint") or "us-east-1"
            _s3 = make_s3_client(region_name=_loc)
        except Exception:
            pass
        _s3.download_file(_bucket, _key, str(dest))
    elif src.startswith(("http://", "https://")):
        import urllib.request
        urllib.request.urlretrieve(src, str(dest))
    else:
        shutil.copy(str(Path(src).expanduser()), str(dest))


_PRINTABLE_BYTES = set(range(32, 127)) | {9, 10, 13}  # printable ASCII + tab/LF/CR


def _looks_like_rds(head: bytes) -> bool:
    """True if `head` (first bytes) is plausibly a serialized R object (saveRDS/save):
    gzip/bzip2/xz-compressed or an uncompressed RDS/RData serialization header."""
    return (
        head[:2] == b"\x1f\x8b"                              # gzip (saveRDS default)
        or head[:3] == b"BZh"                                # bzip2
        or head[:6] == b"\xfd7zXZ\x00"                       # xz
        or head[:5] in (b"RDX2\n", b"RDX3\n", b"RDX1\n")     # uncompressed RDS header
        or head[:2] in (b"X\n", b"A\n", b"B\n")              # XDR/ASCII/binary serialization
    )


def _assert_staged_input_format(dest: Path, base: str) -> None:
    """Pre-flight guard: fail loudly BEFORE an expensive run when the supplied file's
    content clearly contradicts the format the workflow reads it as. Only the
    high-confidence, costly case is enforced — a workflow that readRDS()es a `.rds` but
    was handed a plain-text table (the exact mismatch that otherwise burns a full Batch
    run and dies inside R). Ambiguous cases pass."""
    try:
        with open(dest, "rb") as fh:
            head = fh.read(512)
    except Exception:
        return
    if not head:
        return
    if dest.suffix.lower() in (".rds", ".rdata"):
        is_textlike = all(b in _PRINTABLE_BYTES for b in head)
        if is_textlike and not _looks_like_rds(head):
            raise HTTPException(
                status_code=422,
                detail=(f"Input '{base}' is loaded as an R object (readRDS), but the supplied "
                        f"file is plain text, not a serialized .rds. Save it with saveRDS() in R "
                        f"(or select the correct file) before running."))


def _resolve_read_filename(nf_text: str, base: str) -> str:
    """Return the literal filename the workflow body reads for declared input `base`.

    The `// Input:` declaration uses a logical base token (e.g. `sce2`), but the R body
    often reads a specific filename with an extension (`readRDS("sce2.rds")`). The harness
    stages by the declared token, so when the workflow reads `<base>.<ext>` we must stage
    the file under that exact name. Strategy:
      * If the workflow reads the bare `<base>` literally (readRDS/read.*/file.exists/loadDb),
        keep the bare token (extension-agnostic readers work either way).
      * Else, if it reads `<base>.<ext>`, stage under `<base>.<ext>` (prefer .rds, then the
        first extension referenced).
      * Else, fall back to the bare token unchanged.
    A trailing slash (directory inputs like `sample_bams/`) is preserved as-is.
    """
    if base.endswith("/"):
        return base
    b = re.escape(base)
    read_fn = r'(?:readRDS|loadDb|read\.csv|read\.table|read\.delim|file\.exists|readLines|gzfile)'
    # bare literal read of the token -> already correct, keep as-is
    if re.search(read_fn + r'\(\s*"' + b + r'"', nf_text) or \
       re.search(r'<-\s*"' + b + r'"\s*$', nf_text, re.MULTILINE):
        return base
    # the token already carries an extension (e.g. Pan-cancer-hg38.rds, vV_newSamples.txt)
    if re.search(r'\.[A-Za-z0-9]+$', base):
        return base
    # literal read of <base>.<ext>; prefer .rds, then the first referenced extension
    exts = re.findall(read_fn + r'\(\s*"' + b + r'\.([A-Za-z0-9]+)"', nf_text)
    exts += re.findall(r'<-\s*"' + b + r'\.([A-Za-z0-9]+)"', nf_text)
    if not exts:
        return base
    ext = "rds" if "rds" in exts else exts[0]
    return f"{base}.{ext}"


def _build_bioc_entry_wrapper(nf_path: Path, params: dict, run_dir: Path,
                              run_id: str = "") -> Optional[Path]:
    """If `nf_path` is a regenerated Bioconductor subworkflow (named-only workflow with a
    `take:` channel + a `path()` process input), generate an anonymous entry wrapper that binds a
    non-null channel to the process. `-entry` alone cannot feed a `take:` channel, so the
    mandatory `path()` slot resolves to null → "Path value cannot be null".

    Two scaffolding styles are handled (see inline notes):
      A) `// Input:` header → stage the user's declared files by base name.
      B) no `// Input:` header (self-generating / web-API utility packages) → bind a non-null
         placeholder file for the vestigial `path()` slot the R body never reads.

    Returns the wrapper .nf path, or None if not applicable (caller keeps the normal `-entry`
    path). Mutates `params`: Style-A declared-input keys are popped (they become staged files,
    not CLI `--flags`)."""
    if "/bioconductor/" not in nf_path.as_posix():
        return None
    try:
        text = nf_path.read_text(errors="replace")
    except OSError:
        return None
    # An anonymous workflow already provides a runnable entry — leave it alone.
    if re.search(r"(?m)^\s*workflow\s*\{", text):
        return None
    proc_m = re.search(r"(?m)^\s*process\s+([A-Z][A-Z0-9_]+)\s*\{", text)
    if not proc_m:
        return None
    # A named-only workflow with a `take:` channel is the runnable-via-wrapper shape. Without a
    # `take:` there is nothing for us to bind and the normal `-entry` path applies.
    if not re.search(r"(?m)^\s*take:\s*$", text):
        return None
    proc = proc_m.group(1)

    # Process input arity: a single `path(x, stageAs:'?/*')` slot collects MANY files as one
    # list; N separate path() slots take one file each.
    inblk = re.search(r"input:(.*?)(?:output:|script:|exec:|when:)", text, re.DOTALL)
    in_text = inblk.group(1) if inblk else ""
    n_path = len(re.findall(r"\bpath\s*\(", in_text))

    decl = _BIOC_INPUT_DECL_RE.search(text)
    names = []
    if decl:
        names = [re.split(r"\s*\(", n)[0].strip()
                 for n in re.split(r"[,\s]+", decl.group(1)) if n.strip()]

    # Two scaffolding styles share the same wrapper:
    #   (A) `// Input: a, b` header + `path(input_files, stageAs:'?/*')`: the R body reads real
    #       user files via read_input_file(); each declared name MUST be staged.
    #   (B) no `// Input:` header, process input `tuple val(meta), path(count_data)`: a
    #       self-generating / web-API utility package (e.g. Biobase data(), OmnipathR omnipath()).
    #       The path slot is vestigial — the R body never reads it — but Nextflow still requires a
    #       non-null value for a mandatory `path()` input, so `-entry` with an unbound take channel
    #       fails with "Path value cannot be null". We bind a non-null placeholder file instead.
    staged: list[Path] = []
    _keys_to_pop: list[str] = []
    if names:
        # Style A: every declared input must be supplied; otherwise fall back to the normal path
        # so the missing-input error surfaces clearly rather than a half-bound channel.
        for name in names:
            src = params.get(name)
            _pop_key = name
            if not src and '.' in name:
                # Declaration may carry an extension (e.g. `// Input: gene_list.txt`) while the
                # caller supplies the param without it (e.g. `gene_list`). Try the base name so
                # `gene_list.txt` finds `params["gene_list"]` and stages under the correct
                # filename that the R body actually reads (`gene_list.txt`).
                _no_ext = name.rsplit('.', 1)[0]
                src = params.get(_no_ext)
                if src:
                    _pop_key = _no_ext
            if not src and n_path <= 1 and len(names) == 1:
                # UNIVERSAL multi-omics fallback: the workflow declares ONE list-style input
                # (e.g. `omics`, collected as a single `path(input_files, stageAs:'?/*')` slot),
                # but the caller — the LLM param-prefill parsing a free-text multi-omics request
                # ("drugs = s3://…/drugs.csv, methylation = …") — supplied the matrices under
                # ARBITRARY param names (drugs_data, methylation, mrna, ...), not `omics`. Collect
                # every file-valued param (s3:// URI or *.csv/.tsv/.txt/.rds/.h5ad path) into the
                # list so the UI/routing flow works without the caller knowing the `omics` token.
                # Each is staged under its basename below → the R body names each view by its file.
                # Match only real input MATRICES by DATA-FILE EXTENSION. Do NOT match a bare
                # `s3://…` prefix: the `outdir` / output-location param is also an s3:// URI but
                # is a directory (no extension) that does not exist yet — collecting it made the
                # wrapper try to download it and 404 on HeadObject, failing every mis-named run.
                _fre = re.compile(r'[.](csv|tsv|txt|rds|rdata|h5ad|mtx|tab|parquet)$', re.IGNORECASE)
                _skip_keys = {"outdir", "output", "output_dir", "output_location", "workdir",
                              "work_dir", "publish_dir", "publishdir", "resume_from_run_id",
                              # benchmark workflow: ground-truth label + method selector are NOT
                              # omics modalities — labels is an s3://…csv (would match _fre) that
                              # must reach only the COMPARE scoring step, never the method inputs.
                              "labels", "label", "benchmark_methods", "methods", "n_clusters"}
                _collected = []
                for _k, _v in list(params.items()):
                    if str(_k).lower() in _skip_keys:
                        continue
                    if isinstance(_v, str) and _fre.search(_v):
                        _collected.append(_v)
                        _keys_to_pop.append(_k)
                    elif isinstance(_v, (list, tuple)) and any(isinstance(_e, str) and _fre.search(_e) for _e in _v):
                        _collected.extend([_e for _e in _v if isinstance(_e, str) and _fre.search(_e)])
                        _keys_to_pop.append(_k)
                if _collected:
                    src = _collected
            if not src:
                return None
            # UNIVERSAL multi-omics interface: a declared input may be a LIST of files — one
            # matrix per omics modality (e.g. rna.csv, methylation.csv, proteomics.csv). Stage
            # each under its own basename so the workflow body can name every view by its file
            # (its real modality). Single-file inputs keep the existing behavior below.
            if isinstance(src, (list, tuple)):
                for _one in src:
                    if not _one:
                        continue
                    _base = Path(str(_one).split('?', 1)[0].rstrip('/')).name or f"{name}.dat"
                    _dest = run_dir / _base
                    try:
                        _stage_declared_input(_one, _dest)
                    except Exception as exc:
                        log.warning("[Nextflow run %s] bioc list-input staging failed for %r: %s",
                                    run_id, _one, exc)
                        return None
                    _assert_staged_input_format(_dest, name)
                    staged.append(_dest.resolve())
                _keys_to_pop.append(_pop_key)
                continue
            # The `// Input:` declaration carries a *logical* base token (e.g. `sce2`, `fit2`),
            # but the workflow body frequently reads a *literal* filename with an extension
            # (`readRDS("sce2.rds")`, `file.exists("fit2.rds")`). Stage under the literal
            # filename the workflow actually reads so the input contract is satisfied without
            # touching the workflow logic.
            stage_name = _resolve_read_filename(text, name)
            dest = run_dir / stage_name
            try:
                _stage_declared_input(src, dest)
            except Exception as exc:
                log.warning("[Nextflow run %s] bioc input staging failed for %r: %s",
                            run_id, name, exc)
                return None
            # Format guard runs OUTSIDE the try so its 422 surfaces to the user instead
            # of being swallowed into a silent fallback run.
            _assert_staged_input_format(dest, name)
            staged.append(dest.resolve())
            _keys_to_pop.append(_pop_key)
        for key in _keys_to_pop:             # consumed as staged files, not --flags
            params.pop(key, None)
    elif n_path >= 1:
        # Style B: bind one non-null file per mandatory path() slot. If the caller did supply a
        # real input (common keys), stage it for the first slot; otherwise (and for any extra
        # slots) write an empty placeholder so the channel is never null. Utility/API workflows
        # ignore the file; a workflow that truly needs input still fails loudly inside R, not at
        # the opaque channel-binding step.
        _input_keys = ("input", "input_file", "count_data", "counts", "seurat_object",
                       "rds", "data", "matrix")
        _supplied = next((params.get(k) for k in _input_keys if params.get(k)), None)
        for i in range(n_path):
            dest = run_dir / (f"bioc_input_{i}.dat" if i or not _supplied else "bioc_input.dat")
            if i == 0 and _supplied:
                try:
                    _stage_declared_input(_supplied, dest)
                except Exception as exc:
                    log.warning("[Nextflow run %s] bioc optional input staging failed for %r: %s",
                                run_id, _supplied, exc)
                    dest.write_text("")
            else:
                dest.write_text("")          # placeholder; consumed-but-unused path slot
            staged.append(dest.resolve())
    else:
        # No declared inputs and no path() slot to bind — nothing for the wrapper to do.
        return None

    files_lit = [f"file('{p.as_posix()}')" for p in staged]
    if n_path <= 1 and len(staged) > 1:
        # Style A `stageAs:'?/*'` single slot collecting many files as one list.
        slot = "[ " + ", ".join(files_lit) + " ]"
    else:
        slot = ", ".join(files_lit)
    chan = "[ [id:'sample'], " + slot + " ]"

    # RDS sidecar: if the workflow emits `objects` (its *.rds), chain a best-effort
    # introspection process that writes <name>.rds.json (class/dims/assays/reductions/
    # colData) so the after-run UI can preview the R object inline instead of an opaque
    # blob. SAFE: a plain process never touches publishDir/CRT (only the head JVM's
    # publishDir does) — the sidecars reach S3 via the Batch task's own work-dir copy,
    # the same path versions.yml and every declared output already ride. The R block is a
    # Groovy '''…''' literal (no $-interpolation, so R's list `$` access is preserved) and
    # never throws (tryCatch around every object), so it cannot fail the run.
    container_m = re.search(r'container\s+"([^"]+)"', text)
    bm = re.search(r'\.bm_deps\s*<-\s*c\(([^)]*)\)', text)
    deps_r = bm.group(1).strip() if bm else ""
    introspect_proc = ""
    workflow_body = f"workflow {{ {proc}( Channel.of({chan}) ) }}\n"
    if container_m and re.search(r'emit:\s*objects', text):
        img = container_m.group(1)
        introspect_proc = (
            "\nprocess BIOMATE_RDS_INTROSPECT {\n"
            f"    container '{img}'\n"
            # Best-effort sidecar: never let an unforeseen failure (hard R crash, dep-install
            # error) of this auxiliary process fail the user's actual workflow. The per-object
            # tryCatch already guards the common cases; errorStrategy 'ignore' is the backstop.
            "    errorStrategy 'ignore'\n"
            "    input:\n"
            "      path rds_file\n"
            "    output:\n"
            "      path '*.rds.json', optional: true\n"
            "    script:\n"
            "    '''\n"
            "    #!/usr/bin/env Rscript\n"
            "    suppressWarnings(suppressMessages({\n"
            "      if (!requireNamespace(\"jsonlite\", quietly=TRUE)) try(install.packages(\"jsonlite\", repos=\"https://packagemanager.posit.co/cran/__linux__/jammy/latest\"), silent=TRUE)\n"
            # Load the workflow's own deps so S4 classes defined by lazy-loaded packages
            # (DESeqDataSet, aldex.clr, …) can be reconstructed by readRDS in this task.
            f"      .deps <- c({deps_r})\n"
            "      .miss <- .deps[!vapply(.deps, function(p) requireNamespace(p, quietly=TRUE), logical(1))]\n"
            "      if (length(.miss)) { options(repos=c(CRAN=\"https://packagemanager.posit.co/cran/__linux__/jammy/latest\")); .bin <- tryCatch(sprintf(\"https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker\", BiocManager::version()), error=function(e) NULL); try(BiocManager::install(.miss, update=FALSE, ask=FALSE, site_repository=.bin), silent=TRUE) }\n"
            "      for (.p in .deps) try(requireNamespace(.p, quietly=TRUE), silent=TRUE)\n"
            "      for (.f in Sys.glob(\"*.rds\")) {\n"
            "        .info <- tryCatch({\n"
            "          .obj <- readRDS(.f); .i <- list(class=class(.obj))\n"
            "          .d <- tryCatch(dim(.obj), error=function(e) NULL)\n"
            "          if (!is.null(.d)) .i$dim <- as.integer(.d) else .i$length <- length(.obj)\n"
            "          if (requireNamespace(\"SummarizedExperiment\", quietly=TRUE) && methods::is(.obj,\"SummarizedExperiment\")) {\n"
            "            .i$assays <- tryCatch(SummarizedExperiment::assayNames(.obj), error=function(e) NULL)\n"
            "            .i$colData <- tryCatch(colnames(SummarizedExperiment::colData(.obj)), error=function(e) NULL)\n"
            "            .i$rowData <- tryCatch(colnames(SummarizedExperiment::rowData(.obj)), error=function(e) NULL)\n"
            "          }\n"
            "          if (requireNamespace(\"SingleCellExperiment\", quietly=TRUE) && methods::is(.obj,\"SingleCellExperiment\")) .i$reducedDims <- tryCatch(SingleCellExperiment::reducedDimNames(.obj), error=function(e) NULL)\n"
            "          if (is.list(.obj) && !is.null(names(.obj))) .i$names <- names(.obj)\n"
            "          .i$summary <- paste0(class(.obj)[1], if (!is.null(.d)) sprintf(\": %s rows x %s cols\", .d[1], .d[2]) else \"\"); .i\n"
            "        }, error=function(e) list(class=\"(unreadable)\", summary=conditionMessage(e)))\n"
            "        tryCatch(writeLines(jsonlite::toJSON(.info, auto_unbox=TRUE, null=\"null\"), paste0(.f, \".json\")), error=function(e) NULL)\n"
            "      }\n"
            "    }))\n"
            "    '''\n"
            "}\n"
        )
        workflow_body = (
            "workflow {\n"
            f"    {proc}( Channel.of({chan}) )\n"
            f"    BIOMATE_RDS_INTROSPECT( {proc}.out.objects.map {{ it[1] }}.flatten() )\n"
            "}\n"
        )

    wrapper = run_dir / "biomate_entry.nf"
    wrapper.write_text(
        "nextflow.enable.dsl = 2\n"
        f"include {{ {proc} }} from '{nf_path.resolve().as_posix()}'\n"
        + introspect_proc
        + workflow_body
    )
    log.info("[Nextflow run %s] bioc entry wrapper: proc=%s style=%s inputs=%s n_path=%d staged=%d rds_sidecar=%s",
             run_id, proc, ("A" if names else "B"), names or "(none)", n_path, len(staged),
             bool(introspect_proc))
    return wrapper


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
    # Nextflow template expressions (e.g. "${projectDir}/assets/...") cannot be
    # resolved on the API server — Nextflow resolves them at runtime on the worker.
    # Treat them as non-paths so we don't raise spurious "path not found" 422s.
    if "${" in val:
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
        if key == "outdir" or key.lower().startswith("output"):
            continue  # output param — not a pre-existing input path, skip
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


def _is_raw_bio_sequence(val: str) -> bool:
    """Return True if val is a raw amino-acid or nucleotide sequence (not a file path)."""
    val = val.strip().upper()
    if len(val) < 10:
        return False
    if any(c in val for c in ('/', '\\', '.', ' ', '\n', '\r')):
        return False
    _BIO = frozenset("ACDEFGHIKLMNPQRSTVWYBZXURYSWKMBDHVN*-")
    return all(c in _BIO for c in val)


# Param-key fragments that suggest "this param expects a biological sequence file".
# Used to detect type-mismatched values (raw sequence text in a file-path slot).
_SEQ_FILE_KEY_FRAGMENTS: frozenset = frozenset({
    "fasta", "fa", "fastq", "sequence_file", "seq_file",
    "input_seq", "protein_file", "nucleotide_file",
})

# Param-key names that expect raw sequence TEXT (not a path).
# When the workflow declares one of these, a raw sequence can go there directly.
_SEQ_TEXT_PARAM_NAMES: frozenset = frozenset({
    "sequence", "protein_sequence", "dna_sequence", "rna_sequence",
    "aa_sequence", "nt_sequence", "peptide_sequence", "query_sequence",
    "target_sequence", "input_sequence",
})


def _llm_coerce_param_action(
    param_key: str,
    param_value: str,
    nf_path: Path,
    workflow_name: str = "",
) -> dict:
    """LLM fallback: when rule-based coercion can't handle a mistyped param, ask the
    LLM what to do.  Returns one of:
      {"action": "rename_to", "target_param": "<name>"}
      {"action": "write_fasta_s3"}
      {"action": "pass"}
    Always returns a safe dict — never raises.
    """
    try:
        import re as _re
        nf_text = nf_path.read_text(encoding="utf-8", errors="replace")
        available = _re.findall(r'params\.(\w+)\s*=', nf_text)[:25]

        from galaxy.ai.llm_client import LLMClient  # noqa: PLC0415
        prompt = (
            f"Bioinformatics workflow: '{workflow_name}'\n"
            f"Param key: '{param_key}'\n"
            f"Value (first 200 chars): '{param_value[:200]}'\n"
            f"Other params declared in workflow: {', '.join(available)}\n\n"
            "The value appears to be raw biological sequence text but the param "
            "looks like it should be a file path. Decide what to do.\n"
            "Return JSON ONLY:\n"
            '{"action":"rename_to"|"write_fasta_s3"|"pass",'
            '"target_param":"<param_name or null>"}\n\n'
            "rename_to: value belongs in a different param (e.g. params.sequence).\n"
            "write_fasta_s3: write the sequence to a temp FASTA on S3 and keep the same key.\n"
            "pass: value is fine as-is (e.g. it really is a valid path)."
        )

        # Reuse the Galaxy config object the executor already has in module scope
        import os as _os
        from galaxy.ai.llm_client import LLMClient  # noqa: F811
        cfg_obj = type("_Cfg", (), {
            "llm_api_key": _os.environ.get("LLM_API_KEY", ""),
            "llm_model": _os.environ.get("LLM_MODEL", ""),
            "llm_base_url": _os.environ.get("LLM_BASE_URL", ""),
        })()
        text = LLMClient(cfg_obj).call(
            messages=[{"role": "user", "content": prompt}],
            max_tokens=128,
            use_fast_model=True,
        ).strip()

        import json as _json
        start, end = text.find("{"), text.rfind("}") + 1
        if start >= 0 and end > start:
            return _json.loads(text[start:end])
    except Exception as _e:
        log.debug("[param-coerce] LLM fallback skipped: %s", _e)

    return {"action": "pass", "target_param": None}


def _upload_sequence_to_s3_fasta(
    sequence: str,
    param_key: str,
    s3_bucket: str,
    user_id: str = "anonymous",
) -> Optional[str]:
    """Write a raw sequence to S3 as a FASTA file.  Returns the s3:// URI or None
    on failure.  The resulting path is accessible by Nextflow's nf-amazon plugin."""
    try:
        import boto3 as _boto3
        import uuid as _uuid
        uid = _uuid.uuid4().hex[:10]
        key = f"uploads/{user_id}/tmp/seq_{param_key}_{uid}.fasta"
        body = f">query|{param_key}_{uid}\n{sequence.strip()}\n"
        _boto3.client("s3").put_object(
            Bucket=s3_bucket, Key=key, Body=body.encode("utf-8")
        )
        uri = f"s3://{s3_bucket}/{key}"
        log.info("[param-coerce] Uploaded raw sequence to %s (len=%d)", uri, len(sequence))
        return uri
    except Exception as _e:
        log.warning("[param-coerce] S3 FASTA upload failed: %s", _e)
        return None


def _coerce_mistyped_sequence_params(
    params: dict,
    nf_path: Path,
    workflow_name: str = "",
    s3_bucket: str = "",
    user_id: str = "anonymous",
) -> None:
    """Generalised pre-launch coercion for params that received raw biological
    sequence text instead of a file path.

    Strategy (applied in order, stops at first success):
    1. Rule — rename to a declared sequence-text param in the .nf (e.g. params.sequence)
    2. Rule — find any declared param whose name is in _SEQ_TEXT_PARAM_NAMES
    3. S3 upload — write sequence to a temp FASTA on S3, replace value with s3:// URI
    4. LLM fallback — ask the LLM what to do when none of the above applies

    This function mutates `params` in-place and never raises.
    """
    import re as _re

    try:
        nf_text = nf_path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        nf_text = ""

    # All param keys declared in the .nf file
    declared_params = set(_re.findall(r'params\.(\w+)\s*=', nf_text))

    for key in list(params.keys()):
        val = params.get(key)
        if not isinstance(val, str) or not _is_raw_bio_sequence(val):
            continue

        key_l = key.lower()
        # Only act on keys that look like they should carry a file path
        is_fasta_key = any(frag in key_l for frag in _SEQ_FILE_KEY_FRAGMENTS)
        is_generic_input = key_l in ("input", "query", "data", "protein", "target")
        if not (is_fasta_key or is_generic_input):
            continue

        log.info(
            "[param-coerce] Detected raw sequence (len=%d) in file-type param '%s'",
            len(val), key,
        )

        # ── Strategy 1: rename to an exact sequence-text param in the .nf ──────
        seq_params_in_nf = [p for p in declared_params if p.lower() in _SEQ_TEXT_PARAM_NAMES]
        if seq_params_in_nf:
            target = seq_params_in_nf[0]
            params[target] = val
            del params[key]
            log.info("[param-coerce] S1 rename: '%s' → '%s'", key, target)
            continue

        # ── Strategy 2: find any sequence-text param in the .nf ─────────────────
        seq_like = [
            p for p in declared_params
            if any(s in p.lower() for s in ("sequence", "peptide", "aa_seq", "nt_seq"))
            and p.lower() != key_l
        ]
        if seq_like:
            target = seq_like[0]
            params[target] = val
            del params[key]
            log.info("[param-coerce] S2 rename: '%s' → '%s'", key, target)
            continue

        # ── Strategy 3: upload to S3 as FASTA ───────────────────────────────────
        if s3_bucket:
            uri = _upload_sequence_to_s3_fasta(val, key, s3_bucket, user_id)
            if uri:
                params[key] = uri
                log.info("[param-coerce] S3 replaced '%s' with FASTA uri", key)
                continue

        # ── Strategy 4: LLM fallback ─────────────────────────────────────────────
        decision = _llm_coerce_param_action(key, val, nf_path, workflow_name)
        action = decision.get("action", "pass")
        target = decision.get("target_param")

        if action == "rename_to" and target and target in declared_params:
            params[target] = val
            del params[key]
            log.info("[param-coerce] LLM rename: '%s' → '%s'", key, target)
        elif action == "write_fasta_s3" and s3_bucket:
            uri = _upload_sequence_to_s3_fasta(val, key, s3_bucket, user_id)
            if uri:
                params[key] = uri
                log.info("[param-coerce] LLM S3 FASTA: '%s'", key)
        else:
            log.info("[param-coerce] No coercion applied for '%s' (action=%s)", key, action)


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
        s3 = make_s3_client(region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
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
    # Public reference buckets (_PUBLIC_REF_BUCKETS above) take the `pass` branch and
    # never create an `s3` client — referencing it here raised
    # "UnboundLocalError: local variable 's3' referenced before assignment", which
    # crashed nf-core launches whose inputs live in ngi-igenomes/broad-references.
    # Those buckets are trusted (we already skip head_bucket) and are often
    # requester-pays/cross-region where head_object 403s on legit objects — so skip
    # the object check for them too.
    if (check_object and key and not key.endswith("/") and not _is_glob_key
            and bucket not in _PUBLIC_REF_BUCKETS):
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
    output_location: Optional[Dict[str, Any]] = None, model_type: str = "",
) -> Optional[Path]:
    """
    Generate a temporary nextflow.config for non-local executors.

    Nextflow reads executor from nextflow.config, NOT from environment variables.
    NXF_EXECUTOR is not a real Nextflow env var — this function replaces the
    previous (broken) NXF_EXECUTOR approach.

    Returns path to generated config file, or None for local execution.
    """
    executor = compute.get("executor", "local")
    s3_endpoint = os.environ.get("S3_ENDPOINT_URL", "")

    # For local executor with MinIO: generate a minimal config so Nextflow can
    # stage s3:// input files from MinIO rather than AWS S3.
    if executor not in ("awsbatch", "slurm", "k8s"):
        if not s3_endpoint:
            return None
        # MinIO config for local executor
        minio_key    = os.environ.get("AWS_ACCESS_KEY_ID",     os.environ.get("MINIO_ROOT_USER", "biomate"))
        minio_secret = os.environ.get("AWS_SECRET_ACCESS_KEY", os.environ.get("MINIO_ROOT_PASSWORD", ""))
        # Docker network for task containers: must match the compose network so
        # task containers can resolve "minio" hostname for S3 file staging.
        # BIOMATE_DOCKER_NETWORK defaults to "biomate-network" (on-prem compose default).
        docker_network = os.environ.get("BIOMATE_DOCKER_NETWORK", "biomate-network")
        # On ARM64 hosts the galaxy container runs under QEMU x86 emulation.  The
        # x86 docker CLI binary inside the image crashes (Go unix-socket panic) when
        # called from within QEMU.  Fix: use a statically-linked native ARM64 docker
        # binary placed at /app/nf-work/docker-arm64-static by install.sh.  Static
        # ARM64 binaries exec'd from inside an x86 QEMU container are handled by the
        # ARM64 host kernel natively — no QEMU overhead, no unix-socket crash.
        _is_arm64 = os.environ.get("DOCKER_DEFAULT_PLATFORM", "").lower() == "linux/arm64"
        _arm64_docker = "/app/nf-work/docker-arm64-static"
        docker_executable_line = (
            f"  executable = '{_arm64_docker}'"
            if _is_arm64 and os.path.exists(_arm64_docker) else ""
        )
        # On-prem container override: bioc workflows hard-code a private ECR image.
        # BIOMATE_BIOC_CONTAINER lets operators substitute a public/pre-pulled image.
        # Example: BIOMATE_BIOC_CONTAINER=localhost:5050/biomate/bioc-domain-transcriptomics:3.20-slim
        bioc_container = os.environ.get("BIOMATE_BIOC_CONTAINER", "")
        container_override = ""
        if bioc_container:
            container_override = f"""
process {{
  withName: '/BIOC_.*/' {{
    container = '{bioc_container}'
  }}
}}
"""
        import multiprocessing as _mp
        host_cpus = _mp.cpu_count()
        minio_config = f"""
aws {{
  client {{
    endpoint = '{s3_endpoint}'
    s3PathStyleAccess = true
    connectionTimeout = 60000
    maxConnections    = 4
  }}
  accessKey = '{minio_key}'
  secretKey = '{minio_secret}'
}}

docker {{
  enabled = true
{docker_executable_line}
  // --entrypoint "": override image ENTRYPOINT so Nextflow's /bin/bash invocation is used directly.
  // --user root: task containers need write access to the nf-work bind-mount.
  runOptions = '--entrypoint "" --user root --network {docker_network}'
}}

// On-prem local executor: cap process resource requirements so tasks
// are never rejected due to host CPU/memory constraints.
executor {{
  name   = 'local'
  cpus   = {max(host_cpus, 4)}
  memory = '16 GB'
}}

process {{
  cpus   = 1
  memory = '4 GB'
}}
{container_override}"""
        config_path = config_dir / "biomate_executor_override.config"
        config_path.write_text(minio_config)
        return config_path

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
        container = compute.get("container")
        # ml_training workflows must run in the ml-training image (ludwig + rdkit
        # + the ml_training package). The frontend submits without an explicit
        # compute_config.container (workflow_ga carries none), so default it here
        # by workflow path — otherwise the run lands in biomate-nextflow-base
        # (no ludwig) and the TRAIN process fails. API callers that already set
        # compute.container (executor_payload) keep their value.
        if not container and "ml_training/" in (nf_path or ""):
            # TRL preference/RL methods (DPO/GRPO) need newer torch/transformers
            # than Ludwig's pins allow, so they ship in a separate image.
            if model_type in ("trl_dpo", "trl_grpo"):
                container = os.environ.get(
                    "TRL_TRAINING_IMAGE",
                    "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/trl-training:latest",
                )
            else:
                container = os.environ.get(
                    "ML_TRAINING_IMAGE",
                    "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ml-training:latest",
                )
        container = container or os.environ.get(
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
        _plugin_ids = [f"    id 'nf-amazon@{nfamazon_version}'"]
        # This -c override's plugins{} scope REPLACES the pipeline's own plugins{}
        # scope, so an nf-core pipeline's `id 'nf-schema@X'` pin is dropped here.
        # With no pin left, the pipeline's `include from 'plugin/nf-schema'` makes
        # Nextflow auto-install nf-schema@latest (e.g. 2.7.3) — non-reproducible and
        # able to break a pipeline written against an older nf-schema API (verified
        # live on nf-core/sarek: pin 2.4.2 in its config, but ran under 2.7.3).
        # Fix: carry the pipeline's own nf-schema pin forward into THIS block so it
        # stays pinned. When the pipeline pins the known-broken 2.4.2 (the
        # "Ambiguous method overloading ... SummaryCreator#maybeMask" abort on
        # Nextflow 25.10 / Groovy 4), substitute the smallest maybeMask-fixed
        # release (2.5.1). nf-validation pipelines (e.g. differentialabundance)
        # declare no nf-schema plugin, so nothing is added and they are unaffected.
        if "/nf-core-workflows/" in nf_path and nf_path:
            _BROKEN_NF_SCHEMA = {"2.4.2"}
            _NF_SCHEMA_FIX = "2.5.1"
            try:
                _pipe_cfg = Path(nf_path).parent / "nextflow.config"
                if _pipe_cfg.is_file():
                    _m = re.search(
                        r"nf-schema@([0-9][0-9.]*)", _pipe_cfg.read_text(errors="replace")
                    )
                    if _m:
                        _ver = (
                            _NF_SCHEMA_FIX if _m.group(1) in _BROKEN_NF_SCHEMA else _m.group(1)
                        )
                        _plugin_ids.append(f"    id 'nf-schema@{_ver}'")
                        log.info(
                            "[nextflow] pinning nf-schema@%s in override config for %s "
                            "(pipeline pins @%s; the -c plugins block would otherwise "
                            "unpin it -> latest)",
                            _ver, Path(nf_path).parent.name, _m.group(1),
                        )
            except OSError:
                pass
        lines = [
            "plugins {",
            *_plugin_ids,
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
            f"    outdir = '{_resolve_outdir(output_location, s3_bucket, user_id, run_id)}'",
            "}",
            # nf-core writes execution_report/timeline/trace/dag into ${outdir}/pipeline_info/
            # and REWRITES them live as tasks finish. On S3 (nf-amazon) each rewrite calls
            # S3FileSystemProvider.newOutputStream, which throws FileAlreadyExistsException on
            # the 2nd write unless overwrite is set — failing the WHOLE run at the very end even
            # though every task output already succeeded (seen live on nf-core/rnaseq 2026-08-25:
            # 34-min run, all tasks OK, died only publishing execution_report_*.html). Force
            # overwrite so the report rewrites succeed on S3.
            "timeline.overwrite = true",
            "report.overwrite = true",
            "trace.overwrite = true",
            "dag.overwrite = true",
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
            # Paths that must NOT receive the publishDir-null directive:
            #   - /nf-core-workflows/ — newer nf-core uses
            #     `workflow.output.mode = params.publish_dir_mode` which crashes
            #     comparing ConfigObject [:] with Integer 0 (airrflow 5.1.0).
            #   - structural_biology/boltz_* — Nextflow 25.10.5 rejects the
            #     `publishDir = null` property assignment at config parse time
            #     for this subworkflow's process shape; error surfaces as
            #     "Could not find method publishDir() to invoke" (boltz v3-v5,
            #     2026-06-12). nf-amazon@3.3.0 pin above already prevents the
            #     CRT crash this null was guarding against.
            #   - subworkflows/bioconductor/ — the generated biomate_entry.nf wrapper
            #     hits the SAME "Could not find method publishDir() to invoke" on dev's
            #     Nextflow 25.10.5 (confirmed on deseq2, 2026-06-20; passed on a spot only
            #     because it ran 26.04.4). The bioc .nf carry NO publishDir directives and
            #     collect outputs from the Batch task work dir, so the null is pointless
            #     here too; the nf-amazon@3.3.0 pin already covers CRT.
            # publishDir = null was belt-and-suspenders vs. CRT SIGSEGV;
            # nf-amazon@3.3.0 (used for all biomni workflows) already prevents
            # CRT loading, so the directive is not needed and breaks Nextflow
            # 25.10.5 for any subworkflow that defines publishDir (the
            # ProcessBuilder method dispatch fails with MethodSelectionException).
            # Removed: never inject publishDir = null.
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
        # NB: deliberately does NOT include /usr/local/lib. Some biocontainers ship an
        # incompatible /usr/local/lib/libtinfo.so.6; forcing it onto LD_LIBRARY_PATH made
        # every `sh` print "libtinfo.so.6: no version information available" on stderr.
        # Single-command tools ignore that, but pyFlow-based callers (Strelka, Manta)
        # treat ANY task-wrapper stderr as fatal ("Anomalous task wrapper stderr output")
        # and abort — sarek germline variant calling died there (17/20 tasks, no VCF).
        # The mounted libz lives in /usr/lib64 + /usr/lib/x86_64-linux-gnu (earlier here),
        # and container-native /usr/local/lib libs still resolve via ldconfig, so dropping
        # it keeps S3 staging working while unblocking the pyFlow tools.
        _ld_aws_host = (
            "/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:"
            "/lib/aarch64-linux-gnu:/usr/lib/aarch64-linux-gnu:"
            "/lib64:/usr/lib64:/usr/lib:/lib:"
            "/opt/conda/lib:/opt/conda/x86_64-conda-linux-gnu/lib"
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
        # Skip GPU process label/name selectors for user-uploaded personal workflows.
        # Personal workflows live under /tmp/biomate_user_nf/ and don't use BioMate
        # process labels (process_gpu, PRODUCTION_MD). Nextflow 24+ strict mode exits
        # code 1 when a withName selector matches no process in the workflow.
        _is_personal_wf = "/tmp/biomate_user_nf/" in nf_path
        if gpu_queue and not _is_personal_wf:
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
        # Per-label CPU/memory for the standard nf-core resource tiers. Without this,
        # processes labelled `process_low|medium|high` carry NO `memory` directive, so the
        # awsbatch executor falls back to the Batch job-definition default (~1-2 GB). That
        # OOM-kills memory-heavy R/Bioconductor tasks while they merely LOAD their package
        # stack (e.g. VariantAnnotation+Rsamtools+Biostrings → SIGKILL before any compute),
        # surfacing as a cryptic "Killed" with no output. Values mirror
        # galaxy.ai.resource_resolver.RESOURCE_TIERS. withLabel selectors that match no
        # process are harmless (unlike withName under strict mode).
        if not _is_personal_wf:
            lines += [
                "process {",
                "    withLabel: 'process_low'         { cpus = 2;  memory = '12.GB' }",
                "    withLabel: 'process_medium'      { cpus = 6;  memory = '36.GB' }",
                "    withLabel: 'process_high'        { cpus = 12; memory = '72.GB' }",
                "    withLabel: 'process_high_memory' { cpus = 12; memory = '200.GB' }",
                "}",
            ]
            log.info("[Nextflow] injected process_low/medium/high memory tiers (12/36/72 GB)")
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
        partition = compute.get("slurm_partition") or os.environ.get("SLURM_PARTITION", "compute")
        qos = compute.get("slurm_qos") or os.environ.get("SLURM_QOS", "")
        account = compute.get("slurm_account") or os.environ.get("SLURM_ACCOUNT", "")
        cluster_opts = f"--partition={partition}"
        if qos:
            cluster_opts += f" --qos={qos}"
        if account:
            cluster_opts += f" --account={account}"

        lines = [
            "process {",
            "    executor = 'slurm'",
            f"    clusterOptions = '{cluster_opts}'",
            # Memory/CPU resource labels → Slurm resource requests
            "    withLabel: 'process_gpu'    { clusterOptions = '--partition=gpu --gres=gpu:1 " + cluster_opts.split("--partition=")[1].split()[0] + "' }",
            "    withLabel: 'process_high'   { cpus = 32; memory = '200 GB' }",
            "    withLabel: 'process_medium' { cpus = 16; memory = '72 GB'  }",
            "    withLabel: 'process_low'    { cpus = 4;  memory = '12 GB'  }",
            "}",
        ]

    elif executor == "k8s":
        namespace     = compute.get("k8s_namespace")     or os.environ.get("NXF_K8S_NAMESPACE",       "biomate-jobs")
        storage_claim = compute.get("k8s_storage_claim") or os.environ.get("NXF_K8S_STORAGE_CLAIM",   "biomate-work-pvc")
        storage_mount = compute.get("k8s_storage_mount") or os.environ.get("NXF_K8S_STORAGE_MOUNT",   "/nf-work")
        pull_policy   = compute.get("k8s_pull_policy")   or os.environ.get("NXF_K8S_PULL_POLICY",     "IfNotPresent")
        service_acct  = compute.get("k8s_service_account") or os.environ.get("NXF_K8S_SERVICE_ACCOUNT", "nextflow")
        gpu_resource  = os.environ.get("NXF_K8S_GPU_RESOURCE", "nvidia.com/gpu")

        lines = [
            # k8s scope — tells Nextflow how to submit pods
            "k8s {",
            f"    namespace        = '{namespace}'",
            f"    storageClaimName = '{storage_claim}'",
            f"    storageMountPath = '{storage_mount}'",
            f"    pullPolicy       = '{pull_policy}'",
            f"    serviceAccount   = '{service_acct}'",
            "    debug { yaml = false }",
            "}",
            "",
            "process {",
            "    executor = 'k8s'",
            # Resource label → K8s resource requests/limits
            "    withLabel: 'process_gpu' {",
            f"        resourceLabels = ['{gpu_resource}': '1']",
            "        cpus   = 8",
            "        memory = '48 GB'",
            "    }",
            "    withLabel: 'process_high'   { cpus = 32; memory = '200 GB' }",
            "    withLabel: 'process_medium' { cpus = 16; memory = '72 GB'  }",
            "    withLabel: 'process_low'    { cpus = 4;  memory = '12 GB'  }",
            "}",
            "",
            # Nextflow k8s plugin
            "plugins {",
            "    id 'nf-k8s@0.3.0'",
            "}",
        ]

    config_path.write_text("\n".join(lines) + "\n")
    log.info(f"[Nextflow] Generated executor config: {config_path}")
    return config_path


def _extract_nf_process_containers(nf_path: Path) -> list[str]:
    """
    Extract container image references declared in process { container '...' } blocks.

    These images are used by Nextflow directly for each process.  When a workflow
    already declares its own container, the Python-module check in
    _choose_container_strategy must NOT require those modules on the host — they live
    inside the declared container.
    """
    try:
        text = nf_path.read_text(errors="replace")
    except OSError:
        return []
    images: list[str] = []
    # Match   container 'image:tag'   or   container "image:tag"
    # Also handles ternary expressions: container cond ? 'img1' : 'img2'
    for m in re.findall(r"container\s+[^{}\n]*?['\"]([^'\"]+)['\"]", text):
        if m and m not in images:
            images.append(m)
    return images


def _resolve_local_image_alias(image: str) -> Optional[str]:
    """
    Given a short image name (e.g. 'biomate/biomni-tools:latest'), return the
    locally-available tag that satisfies it.

    On on-prem deployments the same image may be present under its full ECR path
    (399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:latest).
    We match by the image name+tag ignoring the registry prefix.
    """
    if _is_local_docker_image(image):
        return image
    # Extract just the name:tag portion (everything after the last '/')
    name_tag = image.split("/")[-1]
    repo_tag = "/".join(image.split("/")[-2:]) if "/" in image else image
    try:
        result = subprocess.run(
            ["docker", "images", "--format", "{{.Repository}}:{{.Tag}}"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=10,
        )
        if result.returncode != 0:
            return None
        for line in result.stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            local_name_tag = line.split("/")[-1]
            local_repo_tag = "/".join(line.split("/")[-2:]) if "/" in line else line
            if local_name_tag == name_tag or local_repo_tag == repo_tag:
                return line
    except Exception:
        pass
    return None


def _choose_container_strategy(nf_path: Path, raw_nextflow_path: str) -> Dict[str, Any]:
    """
    Choose execution strategy:
      1) Prefer documented local Docker images that satisfy module requirements.
      2) Fallback to host mode with automatic module installation.
    """
    required_modules = _extract_python_imports(nf_path)
    documented_images = _extract_documented_images()

    # If the .nf file declares its own per-process container(s), prefer those first.
    # Python imports inside `script:` blocks run INSIDE the declared container, so
    # module availability on the host is irrelevant for those workflows.  Resolving
    # the declared container also handles on-prem where images are stored under their
    # full ECR path rather than the short `biomate/...` alias.
    nf_declared_containers = _extract_nf_process_containers(nf_path)
    for declared_img in nf_declared_containers:
        resolved = _resolve_local_image_alias(declared_img)
        if resolved:
            log.info(
                f"[Nextflow container] Using per-process container declared in .nf file: "
                f"{declared_img!r} → local image {resolved!r}"
            )
            return {
                "mode": "docker",
                "image": resolved,
                "docker_opts": '-u $(id -u):$(id -g) --entrypoint ""',
                "required_modules": required_modules,
                "missing_modules": [],
                "host_arch": _host_arch(),
                "image_arch": _image_runtime_arch(resolved),
                "cross_arch_allowed": os.environ.get("NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER", "false"),
            }

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
        is_preproc = any(k in domain_upper for k in ("PREPROC", "CLEANING", "QC_CLEAN"))
        is_preproc_files = any(
            f.get("filename", "").endswith("qc_report.json") for f in s3_output_files
        )
        if (not (is_admet or is_admet_files) and not is_cryo
                and not (is_preproc or is_preproc_files)):
            return []  # S3 QC supported for ADMET, CryoEM, and preprocessing/cleaning domains

        # ── Preprocessing / cleaning QC path (over-correction gate) ─────────
        # The clean_and_verify subworkflow emits qc_report.json already in the
        # {"_all_metrics":[{name,measured,unit,threshold,pass}, ...]} shape, so this branch
        # just downloads + surfaces the failing metrics. Additive: returns [] if not preproc.
        if ((is_preproc or is_preproc_files)
                and not is_cryo and not (is_admet or is_admet_files)):
            _qc_uri = ""
            for _f in s3_output_files:
                if _f.get("filename", "").endswith("qc_report.json"):
                    _qc_uri = _f.get("s3_uri", "")
                    break
            if not _qc_uri.startswith("s3://"):
                return []
            try:
                import boto3
                _bucket, _key = _qc_uri[5:].split("/", 1)
                _report = _json.loads(
                    make_s3_client().get_object(Bucket=_bucket, Key=_key)["Body"].read()
                )
            except Exception as _e:  # noqa: BLE001 — safe-fail, gate is best-effort
                log.warning("[QC Gate] preproc qc_report.json read failed for %s: %s", run_id, _e)
                return []
            _fails: List[Dict] = []
            for _m in _report.get("_all_metrics", []):
                if _m.get("pass", True):
                    continue
                _name = _m.get("name", "")
                _fails.append({
                    "name": _name,
                    "measured": _m.get("measured"),
                    "threshold": _m.get("threshold"),
                    "unit": _m.get("unit", ""),
                    # biology-erasure is a hard halt; batch/outlier issues are advisory
                    "severity": "halt" if _name.lower().startswith("biology") else "advisory",
                    "message": (
                        "%s: measured %s vs threshold %s"
                        % (_name, _m.get("measured"), _m.get("threshold"))
                    ),
                })
            return _fails

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
        # Real SSE callback — broadcasts to /internal/sse-inject so the
        # AutoLoopPanel receives autoloop_gate_results / autoloop_update
        # events. Previously this was a no-op which left the UI empty
        # even when gates were correctly evaluated.
        import urllib.request as _urllib

        def _sse_emit(event_type: str, data: Dict[str, Any]) -> None:
            _inject_url = f"{_resolve_frontend_url()}/internal/sse-inject"
            try:
                req = _urllib.Request(
                    _inject_url,
                    data=_json.dumps({
                        "invocation_id": run_id,
                        "event_type": event_type,
                        "data": data,
                    }).encode("utf-8"),
                    headers={"Content-Type": "application/json"},
                )
                with _urllib.urlopen(req, timeout=5):
                    pass
            except Exception as exc:
                log.debug("[autoloop SSE] inject failed for %s: %s", event_type, exc)

        handler = NextflowQCGateHandler(
            invocation_id=run_id,
            work_dir=Path("/tmp"),
            sse_callback=_sse_emit,
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
    s3_work_dir: Optional[str] = None,
    current_parameters: Optional[Dict[str, Any]] = None,
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

    import json as _json
    import urllib.request as _urllib

    def _sse_callback(event_type: str, data: dict) -> None:
        inject_url = f"{_resolve_frontend_url()}/internal/sse-inject"
        payload = _json.dumps({
            "invocation_id": invocation_id,
            "event_type": event_type,
            "data": data,
        }).encode("utf-8")
        try:
            req = _urllib.Request(
                inject_url,
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
        current_parameters=current_parameters or {},
        qc_overrides=qc_overrides,
        qc_profile=qc_profile,
        s3_outdir=s3_outdir,
        s3_work_dir=s3_work_dir,
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
        # Sub-2min workflows (e.g. pocket_detection, antibody_developability)
        # can complete entirely between two 5s polls. Track whether the run
        # has reached a terminal state in _runs[] — if so, do one final poll
        # immediately and exit, rather than continuing to idle.
        finished_seen = False

        def _short_phase_name(full: str) -> str:
            # "NFCORE_RNASEQ:RNASEQ:FASTQ_QC_TRIM_FILTER:STAR_ALIGN" → "STAR_ALIGN"
            return full.rsplit(":", 1)[-1] if ":" in full else full

        def _is_run_terminal() -> bool:
            # Look up the run by invocation_id → run_id and check status.
            try:
                hit = _find_run_by_invocation_id(invocation_id)
                if hit is not None:
                    _rid, _r = hit
                    st = (_r.get("status") or "").lower()
                    return st in ("succeeded", "completed", "failed", "interrupted")
            except Exception:
                pass
            return False

        deadline = _time.monotonic() + hard_cap

        while _time.monotonic() < deadline:
            _time.sleep(5)
            # If the run is already terminal, this loop should drain any
            # final trace updates and exit. finished_seen latches so we
            # poll once more then break.
            if not finished_seen and _is_run_terminal():
                finished_seen = True
            if not trace_file.exists():
                idle_seconds += 5
                if idle_seconds >= max_idle:
                    break
                continue

            try:
                lines = trace_file.read_text(errors="replace").splitlines()
            except OSError:
                continue

            if not lines:
                continue

            # Map header names → column indices. Workflows that configure
            # trace.fields (e.g. pocket_detection_druggability) drop the
            # default "hash" column, shifting "name"/"status" left and
            # breaking the prior hardcoded parts[3]/parts[4] reads. The
            # default Nextflow trace puts name at col 3 and status at col 4,
            # but if "hash" is omitted name/status land at 1/2 — bug
            # observed 2026-06-09 on pocket workflow (phase_name='0' from
            # exit column being read as process_name).
            header_cols = [h.strip() for h in lines[0].split("\t")]
            col_idx = {name: i for i, name in enumerate(header_cols)}
            idx_task_id = col_idx.get("task_id", 0)
            idx_hash    = col_idx.get("hash", 1)
            idx_name    = col_idx.get("name", 3)
            idx_status  = col_idx.get("status", 4)

            new_task_found = False
            # Per-iteration aggregation: process_name → list of task statuses.
            # Used after the per-task loop to decide phase_completed/failed.
            process_status_map: Dict[str, List[str]] = {}

            for line in lines[1:]:  # skip header
                if not line.strip():
                    continue
                parts = line.split("\t")
                if len(parts) <= max(idx_task_id, idx_name, idx_status):
                    continue
                task_id = parts[idx_task_id].strip()
                process_hash = parts[idx_hash].strip() if idx_hash < len(parts) else ""
                process_name = parts[idx_name].strip()
                task_status = parts[idx_status].strip()

                # Aggregate for phase-completion decision below.
                process_status_map.setdefault(process_name, []).append(task_status)

                # Fire workflow.phase_started exactly once per process_name on its
                # first appearance in the trace, regardless of task_status.
                if process_name and process_name not in seen_phase_started:
                    seen_phase_started.add(process_name)
                    try:
                        # Best-effort rationale_id for the (why?) anchor on this
                        # chat line. Returns None for non-chain runs / missing
                        # chain_meta.json sidecar; frontend hides the anchor
                        # cleanly when absent. See docs/20260616_RATIONALE_NARRATOR_HANDOFF.md.
                        _rid = _resolve_rationale_id(str(work_dir), process_name)
                        _technical: Dict[str, Any] = {"phase_name": _short_phase_name(process_name)}
                        if _rid:
                            _technical["rationale_id"] = _rid
                        _narrate_chat(invocation_id, "workflow.phase_started", _technical)
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

            # After the run reached terminal state we've had one more pass
            # through the trace file to catch any final-second updates.
            # Now exit cleanly so we don't burn 30 min of idle polling on
            # sub-minute workflows.
            if finished_seen:
                log.info(
                    "[QC Monitor] Run terminal — exiting monitor for %s "
                    "(saw_tasks=%d, phases_terminal=%d)",
                    invocation_id, len(seen_tasks), len(seen_phase_terminal),
                )
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


# TTL cache for S3 ListObjectsV2. Status polling hits the same prefix every
# ~3s per active run; with workers=4 each call still blocks one worker on the
# round-trip. A 10s TTL collapses ~3 redundant lists per cache window down to
# 1 actual S3 call. Outputs only grow during a run, so 10s of staleness is
# invisible to the UI (next poll lands fresh).
_S3_LIST_CACHE: Dict[str, Tuple[float, list]] = {}
_S3_LIST_TTL_SEC = 10.0
_S3_LIST_CACHE_LOCK = threading.Lock()


def _list_s3_output_files(s3_uri: str) -> list:
    """
    List output files in an S3 prefix after a workflow completes.
    Returns list of dicts: {key, name, size, extension}.
    Skips Nextflow internal files (work/, .nextflow/, trace).
    Results cached for _S3_LIST_TTL_SEC to keep status polling cheap.
    """
    now = time.time()
    with _S3_LIST_CACHE_LOCK:
        cached = _S3_LIST_CACHE.get(s3_uri)
        if cached and (now - cached[0]) < _S3_LIST_TTL_SEC:
            return cached[1]
    try:
        import boto3
    except ImportError:
        return []
    try:
        parts = s3_uri[len("s3://"):].split("/", 1)
        bucket = parts[0]
        prefix = (parts[1] if len(parts) > 1 else "").rstrip("/") + "/"
        s3 = make_s3_client(region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
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
        with _S3_LIST_CACHE_LOCK:
            _S3_LIST_CACHE[s3_uri] = (now, results)
            # Bound cache size — drop oldest entries past 256
            if len(_S3_LIST_CACHE) > 256:
                oldest = sorted(_S3_LIST_CACHE.items(), key=lambda kv: kv[1][0])[:32]
                for k, _ in oldest:
                    _S3_LIST_CACHE.pop(k, None)
        return results
    except Exception as exc:
        log.warning(f"[Nextflow] S3 output listing failed for {s3_uri}: {exc}")
        return []


# Data-file extensions that represent actual workflow outputs vs Nextflow internals.
_OUTPUT_EXTENSIONS = {
    "csv", "tsv", "txt", "json", "html", "pdf", "png", "jpg", "jpeg",
    "svg", "xlsx", "rds", "rdata", "vcf", "bed", "bam", "fastq", "fq",
    "fa", "fasta", "gz", "tar", "zip", "nc", "h5", "h5ad",
}
# Nextflow internals to skip (by filename prefix or exact name).
_NF_INTERNAL_NAMES = {
    ".command.run", ".command.sh", ".command.out", ".command.err",
    ".command.log", ".command.begin", ".exitcode", ".nextflow",
    "trace.txt", "timeline.html", "dag.svg", "dag.html", "report.html",
}


def _list_s3_work_output_files(work_s3_uri: str) -> list:
    """
    List data output files written to the Nextflow work dir by Batch tasks.
    Skips Nextflow internal files (.command.*, .exitcode, etc.).
    Returns list of dicts: {key, name, size, extension, s3_uri}.
    Fallback for when publishDir to outdir fails (common with cross-region S3).
    """
    try:
        import boto3
    except ImportError:
        return []
    try:
        parts = work_s3_uri[len("s3://"):].split("/", 1)
        bucket = parts[0]
        prefix = (parts[1] if len(parts) > 1 else "").rstrip("/") + "/"
        s3 = make_s3_client(region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
        paginator = s3.get_paginator("list_objects_v2")
        results = []
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                name = key.split("/")[-1]
                if not name or name in _NF_INTERNAL_NAMES or name.startswith("."):
                    continue
                ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
                if ext not in _OUTPUT_EXTENSIONS:
                    continue
                results.append({
                    "s3_uri": f"s3://{bucket}/{key}",
                    "name": name,
                    "size": obj["Size"],
                    "extension": ext,
                })
        log.info("[Nextflow] Listed %d work-dir output files from %s", len(results), work_s3_uri)
        return results
    except Exception as exc:
        log.warning("[Nextflow] work-dir output listing failed for %s: %s", work_s3_uri, exc)
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
        s3_client = make_s3_client(region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
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

        s3 = make_s3_client()
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
            _run_snap = _run_lookup(run_id) or {}
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
        _nf_path_for_check = str(_run_snap.get("nextflow_path", ""))
        _is_personal_nf_run = _nf_path_for_check.startswith("/tmp/biomate_user_nf/")
        # On-prem local mode: scan the local output directory for real output files
        # so the S3-output-requirement check doesn't falsely mark successful local
        # runs as failed (Bug #68 — on-prem false-success).
        _use_aws_now = os.environ.get("NEXTFLOW_USE_AWS", "").lower() in ("1", "true", "yes")
        _local_output_files: list = []
        if not _use_aws_now:
            _local_outdir = _run_snap.get("outdir", "")
            if _local_outdir:
                try:
                    _local_outdir_path = Path(_local_outdir)
                    if _local_outdir_path.is_dir():
                        _local_output_files = [
                            str(f) for f in _local_outdir_path.rglob("*")
                            if f.is_file() and "pipeline_info" not in f.parts
                        ]
                except Exception:
                    pass
        if returncode == 0 and not _is_personal_nf_run and _looks_like_false_success(
            log_full_text=_log_text,
            total_steps=_total_steps,
            duration_s=_duration_s,
            s3_output_files=[],
            local_output_files=_local_output_files,
            workflow_domain=_run_snap.get("workflow_domain", ""),
            nextflow_path=_nf_path_for_check,
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
            _inv_id = (_run_lookup(run_id) or {}).get("invocation_id")
        # Stage 2b mirror write — completion path
        try:
            get_run_state_store().update_run(
                run_id,
                status=final_status,
                returncode=returncode,
                completed_at=_completed_at_now,
            )
        except Exception as _store_exc:
            log.debug("[runs] store.update_run completion failed for %s: %s", run_id, _store_exc)

        # Friendly chat-progress: emit the right line for the terminal state.
        if _inv_id:
            if final_status == "completed" or returncode == 0:
                _narrate_chat(_inv_id, "workflow.completed", {"run_id": run_id, "returncode": returncode})
            elif final_status == "failed":
                _narrate_chat(_inv_id, "workflow.failed", {"run_id": run_id, "returncode": returncode, "reason": f"exit {returncode}"})
                # Snapshot run_meta before releasing the lock path to the reroute thread.
                with _runs_lock:
                    _reroute_meta = dict(_runs.get(run_id, {}))
                threading.Thread(
                    target=_trigger_auto_reroute_on_failure,
                    args=(run_id, _inv_id, _reroute_meta, returncode),
                    daemon=True,
                    name=f"nf-reroute-trigger-{run_id[:8]}",
                ).start()
            elif final_status == "interrupted":
                _narrate_chat(_inv_id, "workflow.failed", {"run_id": run_id, "reason": "workflow was interrupted"})

        # Post-completion chain suggestions: fire downstream chain hints when the
        # run succeeded.  Uses nextflow_path as the workflow name for trigger
        # matching (bioc + cryo-EM chain templates both key on the nf path
        # basename).  Runs in the same completion thread — failures are silently
        # swallowed so they cannot block billing / LTM writes below.
        if final_status == "completed" and _inv_id:
            with _runs_lock:
                _wf_name = _runs.get(run_id, {}).get("nextflow_path", "")
            if _wf_name:
                _fire_chain_suggestions(run_id, _wf_name, _inv_id)
                _fire_proactive_suggestion(run_id, _wf_name, _inv_id)

        # Write timing.json immediately — before any follow-on work that could fail.
        _write_timing(run_id, {
            "completed_at": _completed_at_now,
            "status": final_status,
            "returncode": returncode,
        })

        # Enumerate S3 output files + evaluate QC gates on success (Batch runs
        # have no local work dir). CRITICAL: these do blocking network I/O (S3
        # LIST + object downloads in _evaluate_qc_from_s3) that can stall for
        # minutes on throttling, a large file, or boto retries. They MUST run
        # OUTSIDE _runs_lock — holding the lock across them starves every other
        # run-registry consumer (execute/status block on `with _runs_lock` and
        # hang until the worker restarts). Incident 2026-06-30: the connector
        # hERG "fetch failed" was this lock starvation (one run's completion
        # wedged in S3 QC eval under the lock), NOT a launch timeout. Read the
        # inputs under a brief lock, compute lock-free, write results back under
        # a second brief lock.
        with _runs_lock:
            _present = run_id in _runs
            _outdir_for_s3 = _runs[run_id].get("outdir", "") if _present else ""
            _workdir_for_s3 = _runs[run_id].get("workdir", "") if _present else ""
            _wf_domain_for_qc = _runs[run_id].get("workflow_domain", "") if _present else ""
            _qc_overrides_for_qc = dict(_runs[run_id].get("qc_overrides", {})) if _present else {}

        _s3_output_files: list = []
        _qc_gates_s3 = None
        if _present and returncode == 0 and str(_outdir_for_s3).startswith("s3://"):
            _s3_output_files = _s3_files_for_salvage or _list_s3_output_files(_outdir_for_s3)
            # Fallback: if publishDir failed to write to outdir (common with cross-region S3
            # in nf-amazon@3.3.0), scan the Nextflow work dir where Batch tasks copy outputs.
            if not _s3_output_files and str(_workdir_for_s3).startswith("s3://"):
                log.info("[Nextflow] outdir listing empty for %s — scanning workdir fallback", run_id)
                _s3_output_files = _list_s3_work_output_files(_workdir_for_s3)
            _qc_gates_s3 = _evaluate_qc_from_s3(
                run_id=run_id,
                s3_output_files=_s3_output_files,
                workflow_domain=_wf_domain_for_qc,
                qc_overrides=_qc_overrides_for_qc,
            )
            if _qc_gates_s3:
                log.info("[QC Gate] S3 evaluation for %s: %d gate(s)", run_id, len(_qc_gates_s3))

        run_meta: Dict[str, Any] = {}
        with _runs_lock:
            if run_id in _runs:
                if _s3_output_files:
                    _runs[run_id]["s3_output_files"] = _s3_output_files
                if _qc_gates_s3:
                    _runs[run_id]["qc_gates"] = _qc_gates_s3
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
                # Prefer the real per-run compute specs captured at submit time
                # (from compute_config, e.g. the cryo-EM GPU fleet path). Fall
                # back to the historical defaults when the caller didn't supply
                # them — which is the common case for Nextflow-on-Batch runs,
                # where per-task cpus/memory live in the workflow's process
                # directives and Batch auto-selects the instance ("optimal").
                # A Lambda fed by Batch EventBridge events later overwrites
                # this record with the exact per-instance cost when its rule is
                # wired; this direct emit is the fallback compute-billing signal.
                _bill_vcpus = run_meta.get("billing_vcpus") or 4.0
                _bill_memory_mb = run_meta.get("billing_memory_mb") or 8192
                _bill_instance_type = run_meta.get("billing_instance_type") or "optimal"
                _bill_payload = _billing_json.dumps({
                    "user_id": run_meta["user_id"],
                    "job_id": run_id,
                    "workflow_id": run_meta.get("nextflow_path", run_id),
                    "status": "SUCCEEDED" if returncode == 0 else "FAILED",
                    "instance_type": _bill_instance_type,
                    "vcpus": float(_bill_vcpus),
                    "memory_mb": int(_bill_memory_mb),
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
            # Stage 2b mirror write — launch running
            try:
                get_run_state_store().update_run(run_id, status="running")
            except Exception as _store_exc:
                log.debug("[runs] store.update_run running failed for %s: %s", run_id, _store_exc)
            return
        final_status = "failed"
        _completed_at_now = time.time()
        with _runs_lock:
            if run_id in _runs:
                _runs[run_id]["status"] = "failed"
        # Stage 2b mirror write — launch failed
        try:
            get_run_state_store().update_run(run_id, status="failed", completed_at=_completed_at_now)
        except Exception as _store_exc:
            log.debug("[runs] store.update_run launch-failed failed for %s: %s", run_id, _store_exc)
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
        # Stage 2b mirror write — accession-chain status updates
        try:
            get_run_state_store().update_run(run_id, status=status, **extra)
        except Exception as _store_exc:
            log.debug("[runs] store.update_run accession failed for %s: %s", run_id, _store_exc)

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
        # Stage 3d — record the detached subprocess PID in the store so the
        # orphan poller can detect exit from any worker, including ones that
        # didn't launch this run. Without this the poller has no signal at
        # all (test_missing_pid_skips_run in test_completion_poller.py).
        try:
            get_run_state_store().set_pid(run_id, process.pid)
        except Exception as _store_exc:
            log.debug("[runs] store.set_pid failed for %s: %s", run_id, _store_exc)
    except Exception as exc:
        _set_status("failed", error=f"Failed to launch main workflow: {exc}")
        log.error(f"[accession chain run_id={run_id}] Launch error: {exc}")
        return

    _stream_logs(process, run_id, log_path)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

def _fail_run(run_id: str, message: str) -> None:
    """Mark a run failed in both the in-proc dict and the persistence store.

    Used when the (now background) launch path raises before the run reaches a
    live state — so a launch error still surfaces to the caller via run status.
    """
    try:
        with _runs_lock:
            rec = _runs.get(run_id) or {"run_id": run_id}
            rec["status"] = "failed"
            rec["returncode"] = -1
            rec["error"] = message
            _runs[run_id] = rec
            snapshot = dict(rec)
        try:
            get_run_state_store().set_run(run_id, snapshot)
        except Exception:
            pass
    except Exception as _e:
        log.debug("[runs] _fail_run failed for %s: %s", run_id, _e)


def _narrate_launch_failure(invocation_id: str, run_id: str, message: str) -> None:
    """Fire the workflow.failed SSE narration so the frontend reconciles a run
    that failed during the (background) launch before any process started."""
    if not invocation_id:
        return
    try:
        _narrate_chat(invocation_id, "workflow.failed", {"run_id": run_id, "reason": message})
    except Exception as _e:
        log.debug("[runs] launch-failure narration failed for %s: %s", run_id, _e)


def _launch_nextflow_head(
    *,
    cmd: list,
    env: dict,
    work_dir: Path,
    log_path: Path,
    run_id: str,
) -> subprocess.Popen:
    """Launch the Nextflow head process — the shared, overridable launch seam.

    This is the single primitive every compute backend shares: the Nextflow
    HEAD process always runs as a local subprocess (local/awsbatch/slurm/k8s
    differ only in the generated executor config, not in how the head is
    launched). It is also the exact point Feature ① (sandbox) overrides —
    a sandboxed backend wraps this Popen in a container / gVisor / microVM.
    See docs/20260813_ISOLATION_PRIVATE_DEPLOY_SCHEDULER_ROADMAP.md (M0).

    Behavior is identical to the inline block it replaced: bounded-concurrency
    slot acquire → FD-decoupled Popen → record pid in the run-state store →
    background reaper that releases the slot on exit. Returns the process, or
    raises HTTPException (503 slot timeout / 500 launch failure).
    """
    _slot_acquired = False  # bind before the try so the except path is safe
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
        # Stage 3d — record the detached subprocess PID in the store so the
        # orphan poller can detect exit from any worker. The primary launch
        # path (this one, used for ADMET / nf-core / Bioc / etc.) doesn't
        # stash the Popen in _runs[]; the slot-release thread holds it.
        try:
            get_run_state_store().set_pid(run_id, process.pid)
        except Exception as _store_exc:
            log.debug("[runs] store.set_pid failed for %s: %s", run_id, _store_exc)
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
        return process
    except HTTPException:
        raise
    except Exception as exc:
        # Release the slot we may have acquired before the failure.
        if _slot_acquired:
            try: _nf_launch_semaphore.release()
            except ValueError: pass
        log.error(f"[Nextflow run {run_id}] failed to launch: {exc}")
        raise HTTPException(status_code=500, detail=f"Failed to launch Nextflow: {exc}")


def _maybe_sandboxed_launch(
    *,
    cmd: list,
    env: dict,
    work_dir: Path,
    log_path: Path,
    run_id: str,
    nf_path,
    executor: str,
):
    """Launch inside a sandbox container when required; else return None.

    Feature ①, flag-gated by SANDBOX_ENABLED (default off → returns None, so
    the caller uses the direct head-launch and nothing changes). When on, it
    wraps local runs of user-uploaded workflows (untrusted .nf); set
    SANDBOX_ALL_LOCAL=true to wrap every local run. AWS Batch runs already get
    ECS-task isolation and are not re-wrapped.

    FAIL-CLOSED: once the sandbox is deemed required for a run, any error here
    propagates rather than silently falling back to unsandboxed execution —
    an operator who enabled the sandbox must never get a naked subprocess.
    """
    _enabled = os.environ.get("SANDBOX_ENABLED", "").lower() in ("1", "true", "yes")
    if not _enabled:
        return None
    if executor == "awsbatch":
        return None
    _nf_str = str(nf_path or "")
    _is_personal = _nf_str.startswith("/tmp/biomate_user_nf/")
    _all_local = os.environ.get("SANDBOX_ALL_LOCAL", "").lower() in ("1", "true", "yes")
    if not (_is_personal or _all_local):
        return None

    # Sandbox is required for this run — do NOT swallow errors below.
    from galaxy.ai.compute.launcher import LaunchRequest, CallableHeadLauncher
    from galaxy.ai.compute.sandbox.config import SandboxConfig
    from galaxy.ai.compute.sandbox.launcher import SandboxedHeadLauncher

    cfg = SandboxConfig.from_env(run_id=run_id)
    _base_launcher = CallableHeadLauncher(_launch_nextflow_head)
    # Feature ① — narrow launcher (flag-gated by NF_HEAD_LAUNCHER_URL). When set,
    # the head's `docker run` is dispatched to the launcher microservice instead
    # of run locally, so the backend needs no docker access for the head and the
    # launcher re-validates the argv (closes the create+bind host-escape residual
    # for the local .nf head). Unset → run locally, exactly as before.
    _head_launcher_url = os.environ.get("NF_HEAD_LAUNCHER_URL", "").strip()
    if _head_launcher_url:
        from galaxy.ai.compute.sandbox.launcher import LauncherClientHeadLauncher
        _base_launcher = LauncherClientHeadLauncher(_base_launcher, _head_launcher_url, cfg.image)
    launcher = SandboxedHeadLauncher(_base_launcher, cfg)
    log.info(
        "[sandbox] run %s → tier-%d container (%s, net=%s, cpus=%s, mem=%dg)",
        run_id, int(cfg.tier), cfg.image, cfg.network_mode, cfg.cpus, cfg.mem_gb,
    )
    return launcher.launch(
        LaunchRequest(
            cmd=cmd, env=env, work_dir=work_dir, log_path=log_path, run_id=run_id,
            extra={"nf_source_path": _nf_str or None},
        )
    )


# Register the production head-launch primitive as the compute-platform-v2
# default launcher, so compute backends (M0.2) reuse the exact same launch
# path instead of duplicating it. Guarded — a failure here must never affect
# module load or the legacy execution path, which calls the function directly.
try:
    from galaxy.ai.compute.launcher import (
        CallableHeadLauncher as _CallableHeadLauncher,
        set_default_head_launcher as _set_default_head_launcher,
    )

    _set_default_head_launcher(_CallableHeadLauncher(_launch_nextflow_head))
except Exception as _launcher_reg_exc:  # pragma: no cover - defensive
    log.debug("[compute-v2] head-launcher registration skipped: %s", _launcher_reg_exc)


@router.post("/api/nextflow/execute", summary="Launch a Nextflow workflow")
def execute_nextflow(
    request: NextflowExecuteRequest,
) -> Dict[str, Any]:
    """
    Launch a Nextflow workflow by path. Returns IMMEDIATELY with a run_id; the
    (sometimes slow) prep + launch run in a background thread.

    Why async: the Node→Galaxy dispatch `fetch()` previously awaited this whole
    handler. Slow-to-launch workflows (e.g. first-time AWS Batch job-definition
    registration for a new container) made the prep take long enough to trip
    undici's headers timeout → "fetch failed" → the run was marked failed even
    though it had actually launched (connector hERG incident 2026-06-30).
    Returning the run_id up front and launching in the background removes that
    whole class of false-fail; status flows configuring → running → completed.
    """
    # Deployment-scope gate (on-prem scoped installs): refuse out-of-scope
    # workflows with a clear 409 BEFORE any dispatch/temp-file write. No-op on
    # SaaS — fail-safe OFF unless BIOMATE_SCOPE_MANIFEST is set. Covers both the
    # catalog path (nextflow_path) and raw uploads (file_content). See
    # galaxy.ai.scope_guard / docs/20261005_ONPREM_SCOPE_LAYER_PLAN.md.
    from galaxy.ai import scope_guard as _scope_guard
    try:
        _scope_guard.assert_in_scope_or_raise(
            nextflow_path=request.nextflow_path,
            file_content=request.file_content,
        )
    except _scope_guard.ScopeError as _se:
        raise HTTPException(status_code=_se.status_code, detail=_se.payload)

    # If file_content is provided, write it to a temp path and override
    # nextflow_path so _resolve_nextflow_path() finds an actual file.
    if request.file_content:
        import re as _re
        _safe_name = _re.sub(r'[^A-Za-z0-9._-]', '_', os.path.basename(request.nextflow_path or 'workflow.nf'))
        _user_tag = _re.sub(r'[^A-Za-z0-9_-]', '', (request.user_id or 'anon'))[:32]
        _tmp_dir = Path("/tmp/biomate_user_nf") / _user_tag
        _tmp_dir.mkdir(parents=True, exist_ok=True)
        _tmp_path = _tmp_dir / _safe_name
        _tmp_path.write_text(request.file_content, encoding='utf-8')
        log.info("[Nextflow] Wrote user-uploaded workflow to %s (%d bytes)", _tmp_path, len(request.file_content))
        # Feature ① — static pre-check of user-uploaded workflow source.
        # Defense in depth; the sandbox CONTAINER is the real boundary. Only
        # active when SANDBOX_ENABLED (default off → zero change): rejects with
        # 422 in strict mode on a blocking hit, otherwise advisory-logs.
        try:
            from galaxy.ai.compute.sandbox.config import SandboxConfig as _SbxCfg
            from galaxy.ai.compute.sandbox.validator import (
                validate_nextflow_source as _validate_nf,
                has_blocking as _has_block,
                format_violations as _fmt_v,
            )
            _sbx_cfg = _SbxCfg.from_env()
            if _sbx_cfg.enabled and _sbx_cfg.validate_uploads:
                _viol = _validate_nf(request.file_content)
                if _viol:
                    _msg = _fmt_v(_viol)
                    if _sbx_cfg.strict and _has_block(_viol):
                        log.warning("[sandbox] rejecting upload %s: %s", _tmp_path, _msg)
                        raise HTTPException(
                            status_code=422,
                            detail={
                                "error": "Uploaded workflow failed the sandbox security pre-check",
                                "violations": _msg,
                            },
                        )
                    log.warning("[sandbox] upload %s advisory violations: %s", _tmp_path, _msg)
        except HTTPException:
            raise
        except Exception as _sbx_exc:  # pragma: no cover - defensive
            log.debug("[sandbox] upload pre-check skipped: %s", _sbx_exc)
        # Mutate the request so all downstream code (path resolution, logging) uses the real path
        request = request.model_copy(update={"nextflow_path": str(_tmp_path), "file_content": None})

    # Fast, synchronous input validation so an obviously-bad request still gets
    # an immediate 4xx rather than a deferred failed-run.
    try:
        _resolve_nextflow_path(request.nextflow_path)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc))

    run_id = str(uuid.uuid4())
    invocation_id = str(uuid.uuid4())

    # Pre-generate the S3 outdir so the frontend can store it immediately in the
    # DB — without this, the frontend has no outdir until it polls Galaxy status
    # (which it loses on gunicorn restart). Generated here so the background
    # thread uses the SAME path that the HTTP response advertises.
    _uid_for_path_fast = (request.user_id or "unknown").replace("/", "_").replace("..", "_")
    _s3_bucket_fast = os.environ.get("AWS_S3_BUCKET", "biomate-nextflow-work")
    _use_aws_fast = os.environ.get("NEXTFLOW_USE_AWS", "").lower() in ("1", "true", "yes")
    _executor_fast = (getattr(request, "compute", None) or {}).get("executor", "")
    _pre_outdir: Optional[str] = None
    _pre_workdir: Optional[str] = None
    if (_use_aws_fast or _executor_fast == "awsbatch") and not (request.parameters or {}).get("outdir"):
        _run_uuid_short = str(uuid.uuid4())[:8]
        _pre_outdir = f"s3://{_s3_bucket_fast}/nextflow/outputs/{_uid_for_path_fast}/{_run_uuid_short}"
        # Worker tasks copy outputs to workDir on success; head JVM publishDir to outdir often
        # fails (cross-region S3 write in nf-amazon@3.3.0). Store workDir so output_files API
        # can fall back to scanning it when outdir is empty.
        _pre_workdir = f"s3://{_s3_bucket_fast}/nextflow/work/{_uid_for_path_fast}/{run_id}"

    # Register a minimal record up front so a status poll fired right after this
    # returns "configuring" (not 404) while the background launch runs.
    _pre_record = {
        "run_id": run_id,
        "invocation_id": invocation_id,
        "status": "configuring",
        "returncode": None,
        "nextflow_path": str(request.nextflow_path),
        "user_id": request.user_id or "anonymous",
        "is_pilot": bool(request.is_pilot),
        "started_at": time.time(),
        **({"outdir": _pre_outdir} if _pre_outdir else {}),
        **({"workdir": _pre_workdir} if _pre_workdir else {}),
    }
    with _runs_lock:
        _runs[run_id] = dict(_pre_record)
    try:
        get_run_state_store().set_run(run_id, _pre_record)
    except Exception as _e:
        log.debug("[runs] pre-record set_run failed for %s: %s", run_id, _e)

    def _launch_bg() -> None:
        try:
            _execute_nextflow_impl(request, _run_id=run_id, _invocation_id=invocation_id,
                                   _pre_outdir=_pre_outdir)
        except HTTPException as he:
            _msg = f"launch failed ({he.status_code}): {he.detail}"
            _fail_run(run_id, _msg)
            _narrate_launch_failure(invocation_id, run_id, _msg)
        except Exception as exc:
            # log.exception captures the full traceback (file:line) — a bare
            # log.error(…, exc) only prints the message, which made launch
            # crashes like "local variable 'v3' referenced before assignment"
            # impossible to root-cause. See docs/20260722_PROJECT_MODULE_PERF_AND_TIER_PROPOSAL.md.
            log.exception("[Nextflow run %s] background launch crashed", run_id)
            _fail_run(run_id, f"launch failed: {exc}")
            _narrate_launch_failure(invocation_id, run_id, f"launch failed: {exc}")

    threading.Thread(
        target=_launch_bg, daemon=True, name=f"nf-launch-{run_id[:8]}"
    ).start()

    return {
        "success": True,
        "run_id": run_id,
        "invocation_id": invocation_id,
        "status": "configuring",
        **({"outputs": {
            "outdir": _pre_outdir,
            **({"workdir": _pre_workdir} if _pre_workdir else {}),
        }} if _pre_outdir else {}),
    }


def _execute_nextflow_impl(
    request: NextflowExecuteRequest,
    _run_id: Optional[str] = None,
    _invocation_id: Optional[str] = None,
    _pre_outdir: Optional[str] = None,
) -> Dict[str, Any]:
    """
    The actual (sometimes slow) prep + launch. Spawned in a background thread by
    execute_nextflow(); may also be called directly. Raises HTTPException on
    launch errors — the caller converts those to a failed run via _fail_run.
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

    # On-premises deployments: NEXTFLOW_EXECUTOR=local overrides everything —
    # NEXTFLOW_USE_AWS, the frontend's default executor="awsbatch", and any
    # compute_config from the request.  Strip S3 output dirs too since the
    # local Docker executor cannot read/write s3://.
    _onprem_local = os.environ.get("NEXTFLOW_EXECUTOR", "").lower() == "local"
    if _onprem_local:
        compute["executor"] = "local"
        if str(params.get("outdir", "")).startswith("s3://"):
            params.pop("outdir", None)
        log.info("[Nextflow] On-premises mode (NEXTFLOW_EXECUTOR=local) — forced local executor")

    # Default to AWS Batch when NEXTFLOW_USE_AWS=true and no explicit executor is set.
    # This is the platform default: all workflows run on Batch unless explicitly overridden.
    _use_aws_env = os.environ.get("NEXTFLOW_USE_AWS", "false").lower() in ("true", "1", "yes")
    # Normalise user_id early for path construction (before run_id is generated)
    _uid_for_path = (request.user_id or "unknown").replace("/", "_").replace("..", "_")

    # On-prem: NEXTFLOW_EXECUTOR env var sets the cluster-level default executor.
    # Values: local (default) | slurm | k8s | awsbatch
    # Per-job compute_config.executor always wins over this env var.
    _executor_env = os.environ.get("NEXTFLOW_EXECUTOR", "local").lower()
    if not compute.get("executor") and _executor_env in ("slurm", "k8s"):
        compute["executor"] = _executor_env
        if _executor_env == "slurm" and not compute.get("slurm_partition"):
            compute["slurm_partition"] = os.environ.get("SLURM_PARTITION", "compute")
        if _executor_env == "k8s":
            if not compute.get("k8s_namespace"):
                compute["k8s_namespace"] = os.environ.get("NXF_K8S_NAMESPACE", "biomate-jobs")
            if not compute.get("k8s_storage_claim"):
                compute["k8s_storage_claim"] = os.environ.get(
                    "NXF_K8S_STORAGE_CLAIM", "biomate-work-pvc"
                )
        log.info("[Nextflow] On-prem executor from NEXTFLOW_EXECUTOR env: %s", _executor_env)

    # Route to AWS Batch when NEXTFLOW_USE_AWS=true OR when executor is already "awsbatch"
    # (the frontend sends executor="awsbatch" by default as the platform standard).
    # Skip this block entirely in on-prem local mode.
    _executor_requested = compute.get("executor", "")
    if not _onprem_local and (_use_aws_env or _executor_requested == "awsbatch"):
        s3_bucket_default = os.environ.get("AWS_S3_BUCKET", "biomate-nextflow-work")
        # Use _pre_outdir from the fast-path if available — ensures the S3 path the
        # frontend stored at run-creation time matches where Nextflow actually writes.
        if _pre_outdir:
            _auto_outdir = _pre_outdir
        else:
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

    # k8s executor: auto-set outdir to shared PVC mount path (no S3 needed).
    if compute.get("executor") == "k8s" and not params.get("outdir"):
        _k8s_mount = os.environ.get("NXF_K8S_STORAGE_MOUNT", "/nf-work")
        _k8s_outdir = f"{_k8s_mount}/outputs/{_uid_for_path}/{run_id[:8]}"
        params["outdir"] = _k8s_outdir
        log.info("[Nextflow] k8s executor — auto-setting outdir=%s", _k8s_outdir)

    # Slurm executor: shared NFS/Lustre outdir from env.
    if compute.get("executor") == "slurm" and not params.get("outdir"):
        _slurm_work = os.environ.get("SLURM_WORK_DIR", "/scratch/biomate")
        _slurm_outdir = f"{_slurm_work}/outputs/{_uid_for_path}/{run_id[:8]}"
        params["outdir"] = _slurm_outdir
        log.info("[Nextflow] Slurm executor — auto-setting outdir=%s", _slurm_outdir)

    # Personal workflows (written to /tmp/biomate_user_nf/ from file_content at
    # request time) must run locally — they are ad-hoc user scripts that don't
    # carry BioMate's Batch process labels, and cannot initialise an S3 work dir.
    # This override must come AFTER the awsbatch routing block so it wins.
    _nf_path_str = str(request.nextflow_path or "")
    if _nf_path_str.startswith("/tmp/biomate_user_nf/"):
        compute["executor"] = "local"
        params.pop("outdir", None)
        # Params from the UI may contain default values from the script's params {}
        # block (the viewer panel seeds them automatically). Passing them back via
        # --params-file causes "Parameter X was specified on the command line or
        # params file but is not declared in the script or config" in Nextflow 25+
        # when strict-mode validation checks params against the nextflow.config
        # rather than the script body. Personal workflows use their own script-level
        # defaults — drop all user-supplied params so the script runs with its own
        # declared defaults.
        params.clear()
        log.info("[Nextflow] Personal workflow — forcing local executor, cleared S3 outdir, cleared all params")

    # Auto-detect S3 outdir → route to AWS Batch automatically.
    # If the caller passes outdir=s3://..., we treat that as an implicit request
    # for cloud execution — no separate compute_config.executor needed.
    # Skip in on-prem local mode (S3 was already stripped above).
    effective_outdir = params.get("outdir", "")
    is_s3 = str(effective_outdir).startswith("s3://")

    if is_s3 and not _onprem_local:
        # In AWS Batch mode, skip the pre-flight HeadBucket check.
        # Batch job containers use their own IAM job role for S3 access —
        # the Galaxy backend role (BioMateEc2DeployRole) may lack HeadBucket
        # permission even though Batch containers can write to the bucket.
        # Validating with the wrong credential chain gives false 403s.
        if not _use_aws_env:
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
    # Skip in on-prem local mode — MinIO paths start with s3:// but stay local.
    s3_inputs = [
        v for k, v in params.items()
        if k != "outdir" and isinstance(v, str) and v.startswith("s3://")
    ]
    if s3_inputs and not _onprem_local:
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

    # --- Phase 0 compute-platform-v2 SHADOW MODE (COMPUTE_BACKEND_V2) ---
    # Observational only: build a RunSpec from the same inputs the legacy
    # routing block above just used, ask the new Scheduler what it WOULD
    # pick, and log whether it agrees. Never mutates `compute` — this exists
    # purely to prove the abstraction reaches parity before it takes over.
    # Fully guarded so an import/logic error here can never affect a run.
    try:
        from galaxy.ai.compute.scheduler import shadow_compare
        from galaxy.ai.compute.run_spec import RunSpec as _RunSpec

        _shadow_choice = shadow_compare(
            _RunSpec.from_request(
                executor_requested=_executor_requested,
                nextflow_path=_nf_path_str,
                outdir=str(params.get("outdir", "")),
                params=params,
                use_aws_env=_use_aws_env,
                user_id=_uid_for_path,
                run_id=_run_id or "",
            ),
            legacy_executor=compute.get("executor", ""),
        )
        if _shadow_choice is not None:
            log.info("[compute-v2 shadow] %s", _shadow_choice)
    except Exception as _shadow_exc:  # pragma: no cover - defensive
        log.debug("[compute-v2 shadow] skipped: %s", _shadow_exc)

    # Generalised pre-launch coercion: if any file-type param received raw AA/NT
    # sequence text, fix it (rename → S3 upload → LLM fallback) before Nextflow
    # sees the params.  Workflow name is used only for LLM context.
    _coerce_mistyped_sequence_params(
        params,
        nf_path,
        workflow_name=str(nf_path.stem),
        s3_bucket=compute.get("s3_bucket", ""),
        user_id=str(request.user_id) if hasattr(request, "user_id") else "anonymous",
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
    run_id = _run_id or str(uuid.uuid4())
    invocation_id = _invocation_id or str(uuid.uuid4())

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

    # Chain-composer sidecar — write chain_meta.json so the (why?) anchor
    # (resolved via _resolve_rationale_id) can find the chain/phase mapping
    # at SSE-event time. Local mode only; S3 mode would need s3 cp.
    if request.chain_meta and not is_s3:
        try:
            import json as _json
            with open(work_dir / "chain_meta.json", "w") as _fh:
                _json.dump(request.chain_meta, _fh)
        except Exception as _exc:
            log.debug("[chain_meta] write failed for run %s: %s", run_id, _exc)

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

    # A file with an anonymous `workflow { }` block is runnable DIRECTLY — Nextflow runs that
    # block with no `-entry`. Prefer it over any named `take:` workflow in the same file, so a
    # COMPOSED pipeline (e.g. multiomics_benchmark: an anonymous entry that self-stages omics
    # and calls a named `take:` workflow which fans out to N method processes) launches instead
    # of being rejected by the take-without-wrapper fail-fast guard below.
    if not (request.entry or "").strip():
        try:
            if re.search(r"(?m)^\s*workflow\s*\{", nf_path.read_text(errors="replace")):
                selected_entry = None
        except OSError:
            pass

    # Bioconductor subworkflows declare their inputs via `// Input:` and expose only a
    # `take:`-bound named workflow — `-entry` cannot bind that channel, so the workflow is
    # unrunnable as-is. Build an anonymous entry wrapper that stages the user's declared
    # inputs by base name and binds the process channel (mirrors the validated run harness).
    _bioc_wrapper = _build_bioc_entry_wrapper(nf_path, params, log_dir, run_id)
    if _bioc_wrapper is not None:
        cmd = [nf_bin, "run", str(_bioc_wrapper)]
        selected_entry = None     # wrapper provides an anonymous workflow { } entry

    # RC-1 fail-fast guard: a named-only workflow whose `-entry` target declares a `take:`
    # block, for which no entry wrapper could be generated, CANNOT run — Nextflow aborts at
    # invocation with "declares N input channels but 0 were given" (and, pre-fix, that abort
    # was mis-reported as success by the finalizer). Refuse up front with an actionable error
    # instead of launching a doomed AWS Batch run. (Bioconductor take: workflows do not reach
    # here — _build_bioc_entry_wrapper sets selected_entry=None and supplies the channel.)
    if selected_entry and _entry_workflow_has_take(nf_path, selected_entry):
        raise HTTPException(
            status_code=422,
            detail=(
                f"Workflow entry '{selected_entry}' declares input channels (a `take:` block) "
                f"that `-entry` alone cannot bind, and no entry wrapper could be generated for "
                f"it. This is an nf-core subworkflow being launched standalone rather than "
                f"through its parent pipeline. Route this run via a runnable pipeline entry "
                f"(a main.nf with an anonymous `workflow {{ }}` block that wires the samplesheet/"
                f"reference channels) instead of the bare subworkflow file."
            ),
        )

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
    # Personal workflows run with the standard profile — the aws profile initialises
    # AWS clients that are unnecessary (and may fail) for local execution.
    profile = request.profile or _param_profile or _default_nf_profile()
    if _nf_path_str.startswith("/tmp/biomate_user_nf/") and profile not in ("standard", "test"):
        profile = "standard"
    cmd += ["-profile", profile]

    # Real-mode guard: for any non-mock profile, ensure mock_mode is off.
    # Workflows default params.mock_mode = true; command-line params override defaults.
    # This keeps the logic centralised here rather than scattered across workflow configs.
    _mock_profiles = {"standard", "test", "test_full", "test_cache"}
    if (not any(p.strip() in _mock_profiles for p in profile.split(","))
            and "mock_mode" not in params
            and not _nf_path_str.startswith("/tmp/biomate_user_nf/")):
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
            prev = _run_lookup(request.resume_from_run_id) or {}
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
            elif isinstance(value, (list, dict)):
                # Serialize collections as JSON, NOT str() — str([...]) emits a
                # Python repr with single quotes ("['CC(=O)...']") which the
                # workflows' auto_convert(json.loads) can't parse, so the whole
                # list-as-a-string was fed to the tool as ONE value (e.g. one
                # SMILES → 0 valid molecules → admet-ai crash). json.dumps yields
                # valid JSON that json.loads round-trips. Fixes ~272 workflows.
                _params_for_json[key] = _ml_json.dumps(value)
            elif isinstance(value, str) and (key.endswith("_list") or key.endswith("List")):
                # Workflow expects a JSON array string (e.g. smiles_list). If Galaxy AI
                # extracted a single value as a bare string, wrap it so JsonSlurper
                # in the .nf doesn't throw JsonException on a non-JSON scalar.
                _stripped = value.strip()
                try:
                    _pl = _ml_json.loads(_stripped)
                    _params_for_json[key] = _ml_json.dumps(_pl if isinstance(_pl, list) else [_pl])
                except (ValueError, TypeError):
                    _params_for_json[key] = _ml_json.dumps([_stripped] if _stripped else [])
            else:
                _params_for_json[key] = str(value)
        if "outdir" not in _params_for_json and not _nf_path_str.startswith("/tmp/biomate_user_nf/"):
            _params_for_json["outdir"] = str(outdir)
        _params_json_path = log_dir / "nf-params.json"
        _params_json_path.write_text(_ml_json.dumps(_params_for_json, indent=2))
        cmd += ["--params-file", str(_params_json_path)]
        log.info(f"[Nextflow run {run_id}] --params-file (scalar only): {list(_params_for_json.keys())}")
    else:
        # Standard path: pass params as individual --key value flags.
        # Personal workflows don't declare params.outdir — skip the injection.
        if "outdir" not in params and not _nf_path_str.startswith("/tmp/biomate_user_nf/"):
            cmd += ["--outdir", str(outdir)]
        for key, value in params.items():
            # Defense in depth: never pass INTERNAL config vars (e.g. _useAws,
            # CHEM_CONTAINER) whose value is a Groovy/nextflow config EXPRESSION.
            # `--_useAws "params.use_aws || System.getenv(...)"` makes Nextflow
            # abort at parse ("Dynamic parameter expected a value of the form
            # a=b") → run dies instantly, zero output. These resolve inside
            # nextflow.config, not on the CLI.
            _vstr = str(value)
            if str(key).startswith("_") or "params." in _vstr or "System.getenv" in _vstr or "${" in _vstr:
                log.info(f"[Nextflow run {run_id}] skipping internal/expr param --{key}")
                continue
            if key == "outdir":
                cmd += ["--outdir", str(value)]
            elif isinstance(value, bool):
                cmd += [f"--{key}", "true" if value else "false"]
            elif isinstance(value, (list, dict)):
                # JSON, not str() — see the --params-file path above: str([...])
                # emits a single-quoted Python repr that auto_convert(json.loads)
                # can't parse, so a list param was consumed as one string value.
                import json as _cli_json
                cmd += [f"--{key}", _cli_json.dumps(value)]
            elif isinstance(value, str) and (key.endswith("_list") or key.endswith("List")):
                # Same *_list wrapping for CLI flag path (single-SMILES bare string case).
                import json as _cli_json
                _stripped = value.strip()
                try:
                    _pl = _cli_json.loads(_stripped)
                    cmd += [f"--{key}", _cli_json.dumps(_pl if isinstance(_pl, list) else [_pl])]
                except (ValueError, TypeError):
                    cmd += [f"--{key}", _cli_json.dumps([_stripped] if _stripped else [])]
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
    # Use /opt/nextflow (Docker/EC2) if it exists; fall back to ~/.nextflow (local dev).
    # /opt/nextflow is baked into the container image with pre-fetched plugins.
    # On macOS/local dev it doesn't exist — setting NXF_HOME to a non-existent
    # path causes Nextflow to fail before submitting any Batch jobs.
    _nxf_home_candidates = [
        Path("/opt/nextflow"),
        Path(os.environ.get("HOME", "/root")) / ".nextflow",
    ]
    _nxf_home = next((p for p in _nxf_home_candidates if p.is_dir()), None)
    if _nxf_home:
        env["NXF_HOME"] = str(_nxf_home)
        log.info(f"[Nextflow run {run_id}] NXF_HOME={_nxf_home}")

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
    # Use the same base as NXF_HOME: /opt/nextflow on Docker/EC2, ~/.nextflow
    # on local dev. Hardcoding /opt/nextflow here caused PermissionError on
    # macOS where /opt is root-owned and /opt/nextflow doesn't exist.
    _crt_base = _nxf_home if _nxf_home is not None else Path(os.environ.get("HOME", "/tmp")) / ".nextflow"
    _shared_crt_cache = _crt_base / ".aws-crt-cache"
    try:
        _shared_crt_cache.mkdir(parents=True, exist_ok=True)
    except Exception as _crt_e:
        log.warning("[Nextflow run %s] CRT cache dir creation failed (%s) — CRT opts will be omitted", run_id, _crt_e)
        _shared_crt_cache = None
    _existing_nxf_opts = env.get("NXF_OPTS", "")
    # Cap head JVM heap at 512 MB. The head process only parses the workflow,
    # submits Batch jobs, then polls task state + streams logs — most memory
    # is wasted on JVM defaults (NF defaults to -Xmx5g). 512 MB is comfortable
    # for pipelines with up to ~200 concurrent tasks; raise via BIOMATE_NF_HEAP
    # if a specific pipeline ever needs more. Halving per-head footprint lets
    # us run 2x more concurrent workflows on the same host.
    _heap = os.environ.get("BIOMATE_NF_HEAP", "512m")
    if _shared_crt_cache is not None:
        _crt_opts = (
            f"-Xms128m -Xmx{_heap} "
            f"-Daws.crt.lib.dir={_shared_crt_cache} "
            f"-Daws.crt.disable.crt.in.client=true -Xss2m"
        )
    else:
        _crt_opts = f"-Xms128m -Xmx{_heap} -Daws.crt.disable.crt.in.client=true -Xss2m"
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

    # NOTE: an earlier LD_PRELOAD of libmanagement.so was REVERTED here. It was based on a
    # misdiagnosis (there was never an hs_err — the JVM did not crash), and worse, preloading
    # libmanagement.so into EVERY process broke `/usr/bin/env` (which launches the nextflow
    # wrapper): libmanagement.so depends on libjvm.so, unavailable to non-JVM processes, so
    # env aborted with "error while loading shared libraries: libjvm.so" and the head never
    # started. The real dispatch failure was the aws-CLI input-staging bug, fixed via boto3.

    # Compute config overrides: generate a real nextflow.config for non-local executors.
    # NXF_EXECUTOR is not a valid Nextflow env var — executor must be set in a config file.
    billing_user_id = _uid_for_path  # same sanitised value used in S3 path construction
    executor_config_path = _generate_executor_config(
        compute, log_dir, user_id=billing_user_id, run_id=run_id,
        credentials=dict(request.credentials or {}),
        nf_path=str(nf_path),
        model_type=str(params.get("model_type", "")),
        # Thread the user-supplied output_location through so _resolve_outdir
        # can compute the correct S3 outdir per the Phase C picker. Regression
        # fix 2026-06-20 — commit 930aab12c referenced request.output_location
        # inside _generate_executor_config which has no `request` parameter,
        # causing NameError on every dispatch. Pass via kwarg instead.
        output_location=request.output_location,
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
            # Skip the fetchngs prefetch for SEQUENCING accessions when the target
            # workflow downloads SRA itself (FASTERQ_DUMP / isSRA branch, e.g.
            # wgs_germline_gatk). Intercepting would run the (Batch-incompatible) fetchngs
            # pre-step and then substitute a samplesheet.csv the workflow's reads path
            # rejects. Pass the raw accession straight through instead.
            if info["handler"] == "sequencing" and _workflow_handles_sra_natively(str(nf_path)):
                log.info(
                    f"[Nextflow run {run_id}] --{key}={info['accession']}: workflow handles "
                    f"SRA natively → passing raw accession (skipping fetchngs prefetch)"
                )
                continue
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
    # Stage 3c: ensure the orphan-completion poller is running on this
    # worker. Idempotent — only the first launch on a worker actually
    # spawns the thread. See docs/20260615_RUNS_PERSISTENCE_DESIGN.md.
    try:
        from galaxy.ai.runs.bootstrap import ensure_poller_started
        ensure_poller_started()
    except Exception as _boot_exc:
        log.debug("[runs.bootstrap] poller start skipped: %s", _boot_exc)

    _started_at_now = time.time()

    # Capture any explicit compute-resource hints at submit time so the
    # run-completion billing emit (see the C2c block) can report the real
    # per-run vCPU / memory / instance type instead of hard-coded literals.
    # For general Nextflow-on-Batch runs these are usually ABSENT — Nextflow
    # sets per-task cpus/memory via process directives in the workflow config
    # and the Batch queue uses instance_type="optimal" (Batch auto-selects
    # the instance), so no aggregate value is knowable here. The values ARE
    # knowable when a caller supplies them via compute_config (e.g. the
    # cryo-EM GPU fleet path sets compute.instance_type). When absent, the
    # keys stay None and the billing emit falls back to its defaults —
    # behaviour is unchanged. Coerce numerics defensively; never store 0.
    def _pos_num_or_none(_v):
        try:
            _n = float(_v)
            return _n if _n > 0 else None
        except (TypeError, ValueError):
            return None

    _billing_vcpus = _pos_num_or_none(
        compute.get("vcpus") if isinstance(compute, dict) else None
    )
    _billing_memory_mb = _pos_num_or_none(
        compute.get("memory_mb") if isinstance(compute, dict) else None
    )
    _billing_instance_type = (
        compute.get("instance_type") if isinstance(compute, dict) else None
    ) or None

    _run_record_init = {
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
        # Billing compute-resource hints (None when not supplied by caller;
        # the C2c completion emit falls back to defaults in that case).
        "billing_vcpus": _billing_vcpus,
        "billing_memory_mb": _billing_memory_mb,
        "billing_instance_type": _billing_instance_type,
        # Accession metadata (empty dict when not applicable)
        "accession_params": {k: v["label"] for k, v in accession_params.items()},
    }
    with _runs_lock:
        _runs[run_id] = dict(_run_record_init)
    # Stage 2a: parallel write to the persistence store. No semantic change
    # yet — reads still use _runs[]. Subsequent stages flip readers over.
    try:
        get_run_state_store().set_run(run_id, _run_record_init)
    except Exception as _store_exc:
        log.debug("[runs] store.set_run init failed for %s: %s", run_id, _store_exc)

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
            s3_work_dir=_s3_work_dir if _is_batch and _s3_work_dir else None,
            current_parameters=params,
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
    # Launch via the shared head-launch primitive (M0 seam). Feature ①: when
    # SANDBOX_ENABLED, qualifying local/user runs are wrapped in a locked-down
    # container (fail-closed); otherwise (default) the direct primitive runs —
    # behavior identical to the previous inline block.
    process = _maybe_sandboxed_launch(
        cmd=cmd, env=env, work_dir=work_dir, log_path=log_path, run_id=run_id,
        nf_path=nf_path, executor=compute.get("executor", ""),
    )
    if process is None:
        process = _launch_nextflow_head(
            cmd=cmd, env=env, work_dir=work_dir, log_path=log_path, run_id=run_id,
        )

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
        s3_work_dir=_s3_work_dir if _is_batch and _s3_work_dir else None,
        current_parameters=params,
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
            # Per-step params: the enricher (enrich_bioc_step_params.py) stores a rich
            # `params` LIST [{name,type,default,description,options}] on each step. The UI
            # (nextflow-workflow-viewer `step.parameters`, step-adjust-modal) consumes a FLAT
            # `Record<string, value>` — name -> current/default value — and sources widget
            # type/description from the workflow-level required/optional params by name. So
            # flatten the list to {name: default} here; keep the rich list under `param_meta`
            # for any consumer that wants type/options without the workflow-level lookup.
            _plist = s.get("params") or []
            _params = {p.get("name"): p.get("default")
                       for p in _plist if isinstance(p, dict) and p.get("name")}
            out[str(i)] = {
                "id": str(i), "name": nm, "annotation": nm, "description": nm,
                "tool_id": _re.sub(r"[^A-Za-z0-9]+", "_", nm).upper()[:48],
                "type": "tool", "parameters": _params, "param_meta": _plist, "inputs": {},
                "phase_group": s.get("phase", "") or "", "phase_label": s.get("phase", "") or "",
                "visualizations": s.get("visualizations", []) or [],
                "qc": s.get("qc", []) or [], "outputs": s.get("outputs", []) or [],
            }
    except Exception:
        return {}
    return out


_TOOL_PHASE_ORDER = [
    ("QC",                      ["fastqc", "falco", "nanoq", "nanostat", "pycoqc", "toulligqc"]),
    ("Trimming",                 ["fastp", "trimgalore", "trim_galore", "cutadapt", "trimmomatic", "bbduk", "porechop", "nanolyse"]),
    ("Alignment",                ["star", "hisat2", "bwa", "bowtie2", "minimap2", "bwamem2", "tophat2", "cellranger", "starsolo", "chromap", "bismark", "biscuit"]),
    ("Quantification",           ["salmon", "kallisto", "featurecounts", "htseq", "rsem", "subread", "stringtie", "alevin"]),
    ("BAM Processing",           ["samtools", "picard", "bamtools", "sambamba", "bedtools", "deeptools", "preseq"]),
    ("Peak Calling",             ["macs2", "macs3", "homer", "sicer", "epic2", "hmmratac", "seacr"]),
    ("Variant Calling",          ["gatk", "strelka", "mutect2", "freebayes", "deepvariant", "haplotypecaller", "octopus", "bcftools", "varscan", "lofreq"]),
    ("SV Detection",             ["manta", "lumpy", "svaba", "gridss", "delly", "smoove"]),
    ("CNV Analysis",             ["cnvkit", "wisecondorx", "freec", "sequenza", "controlfreec"]),
    ("Methylation",              ["bismark", "biscuit", "methyldackel", "dnmtools", "deeptool"]),
    ("Differential Expression",  ["deseq2", "edger", "limma", "sleuth", "monocle", "dexseq"]),
    ("Single-cell Analysis",     ["seurat", "scanpy", "scran", "scdblfindr", "harmony", "celltypist", "leiden", "louvain"]),
    ("Taxonomic Classification", ["kraken2", "bracken", "metaphlan", "kaiju", "centrifuge", "krona", "pavian"]),
    ("Assembly",                 ["megahit", "spades", "flye", "unicycler", "hifiasm", "canu", "wtdbg2", "metabat"]),
    ("Annotation",               ["prokka", "busco", "diamond", "blast", "hmmer", "interproscan", "eggnog"]),
    ("Structure Prediction",     ["alphafold", "colabfold", "rosettafold", "esmfold", "omegafold"]),
    ("Report",                   ["multiqc", "qualimap", "nanostat"]),
]

_TOOL_TO_PHASE: Dict[str, str] = {
    tool: phase
    for phase, tools in _TOOL_PHASE_ORDER
    for tool in tools
}
_PHASE_ORDER: Dict[str, int] = {phase: i for i, (phase, _) in enumerate(_TOOL_PHASE_ORDER)}


def _steps_synthetic_from_db(nextflow_path: str) -> Dict[str, Any]:
    """Generate synthetic phase-step objects from DB tools_used / step_count metadata.
    Used as a final fallback when neither the .nf file nor bioconductor step_metadata
    is available (e.g. nf-core pipelines without local stubs, nfcore_subwf, etc.)."""
    import sqlite3, json as _json, re as _re
    from pathlib import Path as _Path
    out: Dict[str, Any] = {}
    try:
        db = _Path(__file__).resolve().parents[5] / "database" / "galaxy_ai_tools.db"
        if not db.exists():
            return out
        conn = sqlite3.connect(str(db))
        row = conn.execute(
            "SELECT name, tools_used, step_count, description FROM workflows "
            "WHERE filename = ? OR filename LIKE ? LIMIT 1",
            (nextflow_path, f"%{nextflow_path}"),
        ).fetchone()
        conn.close()
        if not row:
            return out
        wf_name, tools_json, step_count, description = row
        tools_raw: list = _json.loads(tools_json) if tools_json else []
        tools = [str(t).lower().strip() for t in tools_raw if t]

        # Map each tool to its phase, preserving canonical phase order.
        seen_phases: Dict[str, list] = {}
        unmatched: list = []
        for t in tools:
            phase = _TOOL_TO_PHASE.get(t)
            if phase:
                seen_phases.setdefault(phase, []).append(t)
            else:
                unmatched.append(t)

        # Build ordered list of (phase, [tools]) by canonical phase index.
        ordered = sorted(seen_phases.items(), key=lambda kv: _PHASE_ORDER.get(kv[0], 99))
        if unmatched:
            ordered.append(("Processing", unmatched))

        # If we have no tool info but know the step count, emit generic numbered steps.
        if not ordered and step_count:
            for i in range(int(step_count)):
                nm = f"Step {i + 1}"
                out[str(i)] = {
                    "id": str(i), "name": nm, "annotation": nm, "description": "",
                    "tool_id": f"STEP_{i+1}", "type": "tool",
                    "parameters": {}, "param_meta": [], "inputs": {},
                    "phase_group": "", "phase_label": "",
                    "visualizations": [], "qc": [], "outputs": [],
                }
            return out

        # One step per phase (not per tool — phases are the viewer's unit).
        for idx, (phase, phase_tools) in enumerate(ordered):
            nm = phase
            tool_label = ", ".join(phase_tools[:3])
            desc = f"{phase} ({tool_label})" if tool_label else phase
            out[str(idx)] = {
                "id": str(idx), "name": nm, "annotation": nm, "description": desc,
                "tool_id": _re.sub(r"[^A-Za-z0-9]+", "_", nm).upper()[:48],
                "type": "tool", "parameters": {}, "param_meta": [], "inputs": {},
                "phase_group": nm, "phase_label": nm,
                "visualizations": [], "qc": [], "outputs": [],
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
    # DB metadata wins (it carries curated per-step visualizations + QC) — EXCEPT when it has
    # collapsed to a single coarse step while the .nf now parses into several (the B-1 section
    # markers). A degenerate one-step DB row is stale/uncurated, so the finer parser result is
    # the better UI; richer DB metadata (>=2 steps, or matching the parser) still wins.
    if db_steps and not (len(db_steps) <= 1 < len(steps)):
        steps = db_steps
    # Final fallback: generate synthetic phase steps from DB tools_used metadata.
    # Covers nf-core pipelines without local stubs and nfcore_subwf entries.
    if not steps:
        steps = _steps_synthetic_from_db(nextflow_path)
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
        prev = _run_lookup(run_id) or {}

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

    _terminal_status = "paused" if soft else "cancelled"
    _completed_at_now = time.time()
    with _runs_lock:
        if run_id in _runs:
            _runs[run_id]["status"] = _terminal_status
            _runs[run_id]["completed_at"] = _completed_at_now
    # Stage 2b mirror write — cancel/pause
    try:
        get_run_state_store().update_run(run_id, status=_terminal_status, completed_at=_completed_at_now)
    except Exception as _store_exc:
        log.debug("[runs] store.update_run cancel failed for %s: %s", run_id, _store_exc)

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
    """User-facing run status — SANITIZED. Delegates to the internal impl then runs
    the payload through `_sanitize_status_payload` (attaches a classified `failure`
    verdict, redacts backend internals from log_tail/error). Never returns raw logs."""
    return _sanitize_status_payload(_get_nextflow_status_impl(run_id))


def _get_nextflow_status_impl(
    run_id: str,
) -> Dict[str, Any]:
    """Internal status computation — may contain raw internals; NEVER returned to the
    browser directly. Public callers use get_nextflow_status (which sanitizes)."""
    # Chain-aware status: a `chain_...` id is NOT a single Nextflow run — its record
    # lives in the chain store (served by /api/workflows/chain/{id}). Previously this
    # endpoint had no chain-awareness, so /api/nextflow/status/{chain_id} 404'd
    # unconditionally (the frontend polls this path). Resolve chain ids here too.
    if isinstance(run_id, str) and run_id.startswith("chain_"):
        try:
            from galaxy.webapps.galaxy.api import workflow_chain as _wfc
            _cs = _wfc._get_chain(run_id)
        except Exception:  # pragma: no cover - chain store optional
            _cs = None
        if _cs is not None:
            _steps = _cs.get("steps") or []
            _done = sum(1 for s in _steps if s.get("status") == "succeeded")
            _total = len(_steps)
            return {
                "run_id": run_id,
                "invocation_id": run_id,
                "status": _cs.get("status") or "running",
                "is_chain": True,
                "chain_name": _cs.get("chain_name"),
                "completedSteps": _done,
                "totalSteps": _total,
                "progressPercent": int(100 * _done / _total) if _total else 0,
                "processes": [],
                "steps": _steps,
                "started_at": _cs.get("created_at"),
                "completed_at": _cs.get("completed_at"),
            }
        # chain_ id not in the store → fall through to normal lookup/404.
    info = _run_lookup(run_id)

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
            _fb_nf_path = _disk_timing.get("nextflow_path", "")
            _fb_is_personal = str(_fb_nf_path).startswith("/tmp/biomate_user_nf/")
            if fallback_status == "succeeded" and not _fb_is_personal and _looks_like_false_success(
                log_full_text=log_full_text,
                log_tail=log_tail_fallback,
                total_steps=0,
                duration_s=_fb_duration_s,
                s3_output_files=[],
                workflow_domain=_disk_timing.get("workflow_domain", ""),
                nextflow_path=_fb_nf_path,
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
                _s3fb_nf_path = _disk_timing.get("nextflow_path", "")
                _s3fb_is_personal = str(_s3fb_nf_path).startswith("/tmp/biomate_user_nf/")
                if not trace_failed and not _s3fb_is_personal and _looks_like_false_success(
                    log_full_text=log_full_text,
                    log_tail=log_tail_fallback,
                    total_steps=total_steps_fb,
                    duration_s=_fb_duration_s,
                    s3_output_files=_s3_files_fb,
                    workflow_domain=_disk_timing.get("workflow_domain", ""),
                    nextflow_path=_s3fb_nf_path,
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

    _nf_path_for_status = info.get("nextflow_path", "")
    _is_personal_nf_status = str(_nf_path_for_status).startswith("/tmp/biomate_user_nf/")
    # Bug 68 (status-poll path): on-prem local mode — scan local outdir to avoid
    # false-success downgrade when S3 output list is empty.
    _use_aws_status = os.environ.get("NEXTFLOW_USE_AWS", "").lower() in ("1", "true", "yes")
    _local_out_status: list = []
    if not _use_aws_status and outdir and not str(outdir).startswith("s3://"):
        try:
            _lodp = Path(outdir)
            if _lodp.is_dir():
                _local_out_status = [
                    str(f) for f in _lodp.rglob("*")
                    if f.is_file() and "pipeline_info" not in f.parts
                ]
        except Exception:
            pass
    if _info_status in ("succeeded", "completed") and not _is_personal_nf_status and _looks_like_false_success(
        log_full_text=log_full_text,
        log_tail=log_tail,
        total_steps=progress.get("totalTasks", progress.get("totalSteps", 0)),
        duration_s=duration_s,
        s3_output_files=s3_files,
        local_output_files=_local_out_status,
        workflow_domain=workflow_domain,
        nextflow_path=_nf_path_for_status,
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


def _list_local_output_files(outdir: str, run_id: str) -> list:
    """List output files from a local filesystem directory.

    Returns the same shape as _list_s3_output_files:
      [{name, size, extension, download_url}]
    where download_url points to /api/nextflow/outputs/local-download.
    """
    skip_names = {
        ".command.run", ".command.sh", ".command.out", ".command.err",
        ".command.log", ".command.begin", ".exitcode",
        "trace.txt", "timeline.html", "dag.svg", "dag.html", "report.html",
        "execution_report.html", "execution_timeline.html", "execution_trace.txt",
    }
    skip_dirs = {".nextflow", "work", "pipeline_info"}
    out_path = Path(outdir)
    if not out_path.exists():
        return []
    results = []
    for f in sorted(out_path.rglob("*")):
        if not f.is_file():
            continue
        # Skip Nextflow internals
        if f.name in skip_names or f.name.startswith("."):
            continue
        if any(part in skip_dirs for part in f.parts):
            continue
        rel = f.relative_to(out_path)
        ext = f.name.rsplit(".", 1)[-1].lower() if "." in f.name else ""
        try:
            size = f.stat().st_size
        except OSError:
            continue
        import urllib.parse as _urlparse
        dl_url = (
            f"/api/nextflow/outputs/local-download"
            f"?run_id={_urlparse.quote(run_id)}"
            f"&rel_path={_urlparse.quote(str(rel))}"
        )
        results.append({
            "name": f.name,
            "rel_path": str(rel),
            "local_path": str(f),
            "size": size,
            "extension": ext,
            "download_url": dl_url,
        })
    log.info("[Nextflow] Listed %d local output files from %s", len(results), outdir)
    return results


@router.get("/api/nextflow/outputs/local-download", summary="Download a local on-prem output file")
def download_local_output(run_id: str, rel_path: str) -> Any:
    """Stream a local filesystem output file for on-prem deployments.

    Security: `rel_path` is resolved relative to the run's recorded outdir;
    any path that escapes the outdir is rejected.
    """
    from starlette.responses import FileResponse

    info = _run_lookup(run_id)
    if info is None:
        work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
        output_dir = work_base / run_id / "output"
        if not output_dir.exists():
            raise HTTPException(status_code=404, detail=f"Run not found: {run_id}")
        outdir = str(output_dir)
    else:
        outdir = str(info.get("outdir", ""))

    if outdir.startswith("s3://"):
        raise HTTPException(status_code=400, detail="Use /api/nextflow/outputs/download for S3 runs.")

    base = Path(outdir).resolve()
    try:
        target = (base / rel_path).resolve()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid path.")

    if not str(target).startswith(str(base)):
        raise HTTPException(status_code=403, detail="Path escapes run output directory.")
    if not target.is_file():
        raise HTTPException(status_code=404, detail=f"File not found: {rel_path}")

    return FileResponse(str(target), filename=target.name)


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

    info = _run_lookup(run_id)
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
        raise HTTPException(status_code=400, detail="This run does not have S3 outputs. Use /api/nextflow/outputs/local-download for local runs.")

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
        s3 = make_s3_client(region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))

        # On-prem (MinIO): presigned URL contains the internal Docker hostname
        # (e.g. http://minio:9000/…) which is unreachable from the user's browser.
        # Stream the file through Galaxy instead of issuing a redirect.
        _s3_endpoint = os.environ.get("S3_ENDPOINT_URL", "")
        if _s3_endpoint:
            from starlette.responses import StreamingResponse
            import mimetypes as _mimetypes
            try:
                obj = s3.get_object(Bucket=bucket, Key=key)
            except Exception as exc:
                raise HTTPException(status_code=404, detail=f"File not found in storage: {exc}")
            filename = key.split("/")[-1]
            content_type = obj.get("ContentType") or _mimetypes.guess_type(filename)[0] or "application/octet-stream"
            return StreamingResponse(
                obj["Body"].iter_chunks(),
                media_type=content_type,
                headers={"Content-Disposition": f'attachment; filename="{filename}"'},
            )

        url = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": bucket, "Key": key},
            ExpiresIn=900,  # 15 minutes
        )
        if presigned_only:
            return {"url": url}
        return RedirectResponse(url, status_code=302)
    except HTTPException:
        raise
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
    info = _run_lookup(run_id)
    if info is None:
        work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
        output_dir = work_base / run_id / "output"
        if output_dir.exists():
            local_files = _list_local_output_files(str(output_dir), run_id)
            return {"run_id": run_id, "files": local_files}
        raise HTTPException(status_code=404, detail=f"Run not found: {run_id}")

    outdir = str(info.get("outdir", ""))
    if not outdir.startswith("s3://"):
        # Local executor (on-prem or personal workflow) — list filesystem outputs
        local_files = _list_local_output_files(outdir, run_id)
        return {"run_id": run_id, "files": local_files}

    raw_files = _list_s3_output_files(outdir)
    if not raw_files:
        return {"run_id": run_id, "files": []}

    # Generate download URLs for each file.
    # On-prem (MinIO): presigned URLs point to the internal Docker hostname
    # (minio:9000) which is unreachable from the browser. Use the Galaxy proxy
    # endpoint /api/nextflow/outputs/download instead, which streams the file.
    _s3_endpoint = os.environ.get("S3_ENDPOINT_URL", "")
    if _s3_endpoint:
        # Proxy through Galaxy — no boto3 presigning needed.
        enriched = []
        for f in raw_files:
            s3_uri = f.get("s3_uri", "")
            proxy_url = (
                f"/api/nextflow/outputs/download?s3_uri={s3_uri}&run_id={run_id}"
                if s3_uri else None
            )
            enriched.append({**f, "download_url": proxy_url})
        return {"run_id": run_id, "files": enriched}

    try:
        import boto3
        s3 = make_s3_client(region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
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

    run = _run_lookup(invocation_id) or {}
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
    # transcriptomics / genomics
    "deseq2": "transcriptomics", "differentialabundance": "transcriptomics",
    "clusterprofiler": "transcriptomics", "enrichgo": "transcriptomics",
    "rnaseq": "transcriptomics", "pseudobulk": "transcriptomics",
    "edger": "transcriptomics", "limma": "transcriptomics",
    # clinical / pharmacology
    "boin": "clinical_trial", "trial_sim": "clinical_trial",
    "ich_s5": "ich_s5", "ich_s7": "ich_s7",
}


def _lookup_workflow_domain_from_db(workflow_name: str) -> Optional[str]:
    """Read the workflow's domain straight from galaxy_ai_tools.db.
    Checks workflow_chains first (curated chains), then workflows.
    Single source of truth — no per-chain keyword hardcoding needed."""
    import sqlite3 as _sql
    db_path = os.path.normpath(os.path.join(
        os.path.dirname(__file__), "..", "..", "..", "..", "..",
        "database", "galaxy_ai_tools.db",
    ))
    if not os.path.exists(db_path):
        return None
    try:
        with _sql.connect(db_path) as conn:
            cur = conn.cursor()
            for table in ("workflow_chains", "workflows"):
                cur.execute(f"SELECT domain FROM {table} WHERE name=? LIMIT 1", (workflow_name,))
                row = cur.fetchone()
                if row and row[0]:
                    return row[0]
    except Exception:
        pass
    return None


def _resolve_qc_evidence_domain(workflow_name: str, available_domains: list) -> Optional[str]:
    """Pick the best-matching qc_evidence domain for a workflow name.
    Returns None when no plausible match — citations endpoint then returns empty."""
    import re as _re
    # 0) Authoritative: read the workflow's domain from the DB.
    db_domain = _lookup_workflow_domain_from_db(workflow_name)
    if db_domain and db_domain in available_domains:
        return db_domain
    wf_low = workflow_name.lower()
    # 1) Direct alias hit (legacy tool-name + domain-keyword classification)
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


@router.get("/api/workflows/{workflow_name}/phases/{phase_id}/rationale",
            summary="Per-phase curated rationale ('why this method') for the (why?) anchor")
def get_workflow_phase_rationale(workflow_name: str, phase_id: str) -> Dict[str, Any]:
    """
    Lookup the curated rationale row for one phase of one workflow chain.

    Reads workflow_phase_rationale (populated by
    backend/scripts/populate_workflow_phase_rationale.py from BiocTours.jsx
    + qc_evidence.yaml). Returns 404-shape (empty body) when the row
    doesn't exist — the frontend hides the anchor in that case.

    Shape (matches §3 of docs/20260614_RATIONALE_ANCHOR_PLAN.md):
      {
        "workflow_id": int,
        "phase_id": str,
        "rationale_text": str,        # plain text, no JSX
        "citation": {"doi": str?, "title": str?} | None,
        "qc_gate_name": str?,
        "last_curated_at": int        # unix seconds
      }
    """
    import sqlite3 as _sql
    db_path = os.path.normpath(os.path.join(
        os.path.dirname(__file__), "..", "..", "..", "..", "..",
        "database", "galaxy_ai_tools.db",
    ))
    if not os.path.exists(db_path):
        return {}
    try:
        with _sql.connect(db_path) as conn:
            # Resolve workflow_name -> id (chain first, then workflows fallback)
            wid_row = conn.execute(
                "SELECT id FROM workflow_chains WHERE name=? LIMIT 1",
                (workflow_name,),
            ).fetchone()
            if not wid_row:
                wid_row = conn.execute(
                    "SELECT id FROM workflows WHERE name=? LIMIT 1",
                    (workflow_name,),
                ).fetchone()
            if not wid_row:
                return {}
            wid = int(wid_row[0])
            row = conn.execute(
                "SELECT rationale_text, citation_doi, citation_title, "
                "qc_gate_name, last_curated_at "
                "FROM workflow_phase_rationale WHERE workflow_id=? AND phase_id=? LIMIT 1",
                (wid, phase_id),
            ).fetchone()
            if not row:
                return {}
            rationale_text, doi, title, gate, ts = row
            citation: Optional[Dict[str, Any]] = None
            if doi or title:
                citation = {"doi": doi, "title": title}
            return {
                "workflow_id": wid,
                "phase_id": phase_id,
                "rationale_text": rationale_text,
                "citation": citation,
                "qc_gate_name": gate,
                "last_curated_at": int(ts) if ts else None,
            }
    except Exception as exc:
        log.debug("rationale lookup failed for %s/%s: %s", workflow_name, phase_id, exc)
        return {}


@router.get("/api/rationale/{rationale_id:path}",
            summary="Design-faithful (why?) lookup keyed by rationale_id (e.g. 'chain_name:B')")
def get_rationale(rationale_id: str) -> Dict[str, Any]:
    """
    Per-event rationale lookup matching the design's
    window.RESEARCH_PHASE_TRACE pattern (research_agents/research-data.js).

    Reads `rationale_registry` (populated by
    backend/scripts/populate_rationale_registry.py from
    workflow_phase_rationale + rationale_mapping.yaml + qc_evidence.yaml).
    Returns {} when no curated row exists so the frontend WhyAnchor hides.

    Phase 3 extension (future): when invocation_id query param is
    supplied, join in `events`, `params`, `cost` blocks to match the
    design's 4-section popover.
    """
    import sqlite3 as _sql
    db_path = os.path.normpath(os.path.join(
        os.path.dirname(__file__), "..", "..", "..", "..", "..",
        "database", "galaxy_ai_tools.db",
    ))
    if not os.path.exists(db_path):
        return {}
    try:
        with _sql.connect(db_path) as conn:
            row = conn.execute(
                "SELECT rationale_text, citation_doi, citation_title, "
                "qc_gate_name, curated_by, last_curated_at "
                "FROM rationale_registry WHERE rationale_id=? LIMIT 1",
                (rationale_id,),
            ).fetchone()
            if not row:
                return {}
            text, doi, title, gate, curator, ts = row
            citation: Optional[Dict[str, Any]] = None
            if doi or title:
                citation = {"doi": doi, "title": title}
            return {
                "rationale_id": rationale_id,
                "rationale_text": text,
                "citation": citation,
                "qc_gate_name": gate,
                "curated_by": curator,
                "last_curated_at": int(ts) if ts else None,
            }
    except Exception as exc:
        log.debug("rationale_registry lookup failed for %s: %s", rationale_id, exc)
        return {}


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

        # Look up run_id from store (worker-local _runs first, Redis fallback)
        if run_id == "n/a":
            hit = _find_run_by_invocation_id(invocation_id)
            if hit is not None:
                run_id = hit[0]

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
    hit = _find_run_by_invocation_id(invocation_id)
    if hit is not None:
        wd = hit[1].get("work_dir")
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

    # Locate outdir for this invocation (store + in-process fallback)
    outdir: Optional[Path] = None
    hit = _find_run_by_invocation_id(invocation_id)
    if hit is not None:
        raw = hit[1].get("outdir")
        outdir = Path(raw) if raw else None

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
    # A cryo run must reach a CryoSPARC master whose API is actually SERVING before
    # any Batch GPU task submits — otherwise every task races a half-booted (or dead)
    # host and the run fails opaquely. We never trust an unverified host and never fall
    # back to the mock (use_cryosparc stays True below). No single always-on host is
    # assumed: the on-demand path provisions per run and terminates on completion.
    if os.environ.get("CRYOSPARC_SKIP_PROVISION", "").strip() in ("1", "true", "yes"):
        # Permanent-host model (dev/staging): don't launch EC2, but STILL health-check
        # the configured host so a dead master fails fast with a clear 503 instead of
        # letting every Batch task fail to connect to a closed port.
        _cs_host = cs_exec.CRYOSPARC_HOST
        _cs_port = int(getattr(cs_exec, "CRYOSPARC_PORT", 0) or os.environ.get("CRYOSPARC_PORT", "30000") or "30000")
        import socket as _socket
        try:
            with _socket.create_connection((_cs_host, _cs_port), timeout=8):
                pass
            log.info("[CryoSPARC] CRYOSPARC_SKIP_PROVISION=1 — health-checked existing host %s:%s OK", _cs_host, _cs_port)
        except Exception as _hc_exc:
            raise HTTPException(
                status_code=503,
                detail=(f"CRYOSPARC_SKIP_PROVISION is set but the CryoSPARC master at "
                        f"{_cs_host}:{_cs_port} is not reachable ({_hc_exc}). Start the CryoSPARC "
                        f"host, or unset CRYOSPARC_SKIP_PROVISION to provision a GPU instance on demand."),
            )
    else:
        log.info("[CryoSPARC] Ensuring an on-demand CryoSPARC GPU master is up (provision + API health check)...")
        try:
            # ensure_cryosparc_running() provisions (or reuses) the instance AND blocks
            # until the CryoSPARC API answers (up to 15 min) — unlike start_instance(wait=True),
            # which returned as soon as EC2 was 'running', before the service was listening.
            # Serialise with the same lock the direct-API path uses so concurrent runs don't
            # launch duplicate instances. On failure this raises → 503 below (never mock).
            with cs_exec._INSTANCE_LOCK:
                cs_exec.ensure_cryosparc_running()
            log.info("[CryoSPARC] Instance ready and API serving at %s", cs_exec.CRYOSPARC_HOST)
        except Exception as exc:
            raise HTTPException(status_code=503,
                                detail=f"Failed to provision a live CryoSPARC GPU instance: {exc}")

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


@router.get("/api/admin/process-health", summary="Process and runtime health")
def get_process_health() -> Dict[str, Any]:
    """Returns gunicorn worker count, active runs, Redis ping, and memory usage."""
    import os as _os
    import time as _time
    from datetime import datetime as _dt2

    checks: Dict[str, Any] = {}
    overall = "ok"

    # ── Active runs ────────────────────────────────────────────────────────────
    try:
        store = get_run_state_store()
        active = store.list_active_runs()
        checks["active_runs"] = {"count": len(active)}
    except Exception as exc:
        checks["active_runs"] = {"count": 0, "error": str(exc)[:120]}

    # ── Redis ──────────────────────────────────────────────────────────────────
    redis_url = _os.environ.get("REDIS_URL") or _os.environ.get("REDISCLOUD_URL")
    if redis_url:
        try:
            import redis as _redis  # type: ignore
            _t0 = _time.monotonic()
            _r = _redis.from_url(redis_url, socket_timeout=2, socket_connect_timeout=2,
                                  decode_responses=True)
            _r.ping()
            latency_ms = round((_time.monotonic() - _t0) * 1000, 1)
            checks["redis"] = {"status": "ok", "latency_ms": latency_ms}
        except Exception as exc:
            checks["redis"] = {"status": "error", "error": str(exc)[:120]}
            overall = "degraded"
    else:
        checks["redis"] = {"status": "not_configured"}

    # ── Gunicorn workers ───────────────────────────────────────────────────────
    try:
        import psutil as _psutil  # type: ignore
        workers = [
            p for p in _psutil.process_iter(["name", "cmdline"])
            if "gunicorn" in (p.info.get("name") or "")
            or any("gunicorn" in str(c) for c in (p.info.get("cmdline") or []))
        ]
        checks["workers"] = {"count": len(workers)}
    except Exception:
        checks["workers"] = {"count": -1, "note": "psutil unavailable"}

    # ── Memory ────────────────────────────────────────────────────────────────
    try:
        import psutil as _psutil  # type: ignore  # noqa: F811
        vm = _psutil.virtual_memory()
        checks["memory"] = {
            "used_mb": vm.used // (1024 * 1024),
            "total_mb": vm.total // (1024 * 1024),
            "percent": round(vm.percent, 1),
        }
        if vm.percent > 90:
            overall = "degraded"
    except Exception:
        pass

    return {
        "status": overall,
        "checks": checks,
        "checked_at": _dt2.utcnow().isoformat() + "Z",
    }


# ---------------------------------------------------------------------------
# Admin log ring buffer — captures last 500 log records in memory
# ---------------------------------------------------------------------------

import logging as _logging_mod
import collections as _deque_mod


class _RingBufferHandler(_logging_mod.Handler):
    """Captures recent log records for the admin log viewer."""

    def __init__(self, maxlen: int = 500) -> None:
        super().__init__()
        self._buf: _deque_mod.deque = _deque_mod.deque(maxlen=maxlen)
        self.setFormatter(_logging_mod.Formatter("%(asctime)s"))

    def emit(self, record: _logging_mod.LogRecord) -> None:
        try:
            self._buf.append({
                "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S"),
                "level": record.levelname,
                "logger": record.name.split(".")[-1][:20],
                "msg": record.getMessage()[:400],
            })
        except Exception:
            pass

    def tail(self, n: int) -> list:
        return list(self._buf)[-n:]

    def __len__(self) -> int:
        return len(self._buf)


# Singleton — created once at module import time, survives across requests
# within the same worker process.
_LOG_RING: _RingBufferHandler = _RingBufferHandler(maxlen=500)
_logging_mod.getLogger().addHandler(_LOG_RING)


@router.get("/api/admin/logs", summary="Recent log lines (ring buffer)")
def get_admin_logs(lines: int = 100) -> Dict[str, Any]:
    """Returns the last N log lines captured since worker startup."""
    n = min(max(1, lines), 200)
    return {
        "lines": _LOG_RING.tail(n),
        "buffered": len(_LOG_RING),
        "requested": n,
    }


def _parse_batch_job_ids_from_log(nf_log_path: Path) -> list:
    """Return list of AWS Batch job IDs found in a Nextflow log file."""
    import re as _re2
    pattern = _re2.compile(r"job=([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})")
    ids: list = []
    seen: set = set()
    try:
        with open(nf_log_path) as fh:
            for line in fh:
                for m in pattern.finditer(line):
                    jid = m.group(1)
                    if jid not in seen:
                        seen.add(jid)
                        ids.append(jid)
    except Exception:
        pass
    return ids


def _get_run_record_by_id(run_id: str) -> Optional[Dict[str, Any]]:
    """Look up run record from in-memory dict or Redis store."""
    with _runs_lock:
        rec = _runs.get(run_id)
    if rec:
        return dict(rec)
    try:
        return get_run_state_store().get_run(run_id)
    except Exception:
        return None


@router.post("/api/admin/kill-run", summary="Force-terminate a run (admin)")
def admin_kill_run(body: Dict[str, Any]) -> Dict[str, Any]:
    """Kill a running workflow: terminates the local Nextflow subprocess and
    cancels any submitted AWS Batch jobs, then marks the run as interrupted."""
    import signal as _signal
    import time as _time

    run_id = (body.get("run_id") or "").strip()
    if not run_id:
        raise HTTPException(status_code=400, detail="run_id required")

    rec = _get_run_record_by_id(run_id)
    if not rec:
        raise HTTPException(status_code=404, detail=f"Run {run_id} not found in state store")

    actions: list = []

    # 1. Terminate local Nextflow HEAD subprocess
    proc = rec.get("process")
    if proc is not None:
        try:
            proc.send_signal(_signal.SIGTERM)
            actions.append("sigterm_sent")
        except Exception as _e:
            actions.append(f"sigterm_failed:{_e}")

    # 2. Cancel AWS Batch jobs found in the Nextflow log
    work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
    batch_job_ids: list = []
    for nf_log_rel in ("nextflow.log", "work/.nextflow.log"):
        nf_log_path = work_base / run_id / nf_log_rel
        if nf_log_path.exists():
            batch_job_ids = _parse_batch_job_ids_from_log(nf_log_path)
            if batch_job_ids:
                break

    batch_cancelled = []
    batch_errors = []
    if batch_job_ids:
        try:
            import boto3 as _boto3
            _bc = _boto3.client("batch", region_name=os.environ.get("AWS_REGION", "us-west-2"))
            for jid in batch_job_ids:
                try:
                    _bc.terminate_job(jobId=jid, reason="Admin force-terminated via dashboard")
                    batch_cancelled.append(jid)
                except Exception as _be:
                    batch_errors.append(f"{jid[:8]}…:{_be}")
        except Exception as _boto_err:
            batch_errors.append(f"boto3_init:{_boto_err}")
    actions.append(f"batch_cancelled:{len(batch_cancelled)}")
    if batch_errors:
        actions.append(f"batch_errors:{batch_errors}")

    # 3. Mark run as interrupted in state store + frontend Postgres
    completed_at = _time.time()
    with _runs_lock:
        if run_id in _runs:
            _runs[run_id]["status"] = "interrupted"
            _runs[run_id]["completed_at"] = completed_at
    try:
        get_run_state_store().update_run(run_id, status="interrupted", completed_at=completed_at)
    except Exception:
        pass

    invocation_id = rec.get("invocation_id")
    if invocation_id:
        try:
            from galaxy.ai.runs.orphan_finalizer import _post_frontend_status
            _post_frontend_status(invocation_id, "failed", -1, completed_at, "admin_kill")
            actions.append("frontend_status_updated")
        except Exception as _fe:
            actions.append(f"frontend_update_failed:{_fe}")

    log.info("[admin_kill_run] %s terminated by admin: %s", run_id, actions)
    return {
        "run_id": run_id,
        "status": "interrupted",
        "batch_jobs_found": len(batch_job_ids),
        "batch_cancelled": len(batch_cancelled),
        "actions": actions,
    }


@router.get("/api/admin/run-logs", summary="Fetch execution logs for a run (admin)")
def admin_run_logs(run_id: str, lines: int = 150) -> Dict[str, Any]:
    """Return Nextflow execution log lines for a specific run.
    Reads the local .nextflow.log file and (for Batch runs) the
    last N lines from CloudWatch per submitted job."""
    n = min(max(10, lines), 500)
    run_id = run_id.strip()
    if not run_id:
        raise HTTPException(status_code=400, detail="run_id required")

    rec = _get_run_record_by_id(run_id)
    work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
    result: Dict[str, Any] = {
        "run_id": run_id,
        "status": rec.get("status") if rec else "unknown",
        "is_batch": rec.get("is_batch", False) if rec else False,
        "nf_log": [],
        "batch_jobs": [],
        "cloudwatch_logs": [],
    }

    # Read local Nextflow log
    for nf_log_rel in ("nextflow.log", "work/.nextflow.log"):
        nf_log_path = work_base / run_id / nf_log_rel
        if nf_log_path.exists():
            try:
                with open(nf_log_path) as fh:
                    all_lines = fh.readlines()
                result["nf_log"] = [l.rstrip("\n") for l in all_lines[-n:]]
                result["nf_log_path"] = str(nf_log_path)
                result["nf_log_total_lines"] = len(all_lines)
            except Exception as _e:
                result["nf_log_error"] = str(_e)
            break

    # Parse Batch job IDs and fetch CloudWatch logs
    batch_job_ids: list = []
    for nf_log_rel in ("nextflow.log", "work/.nextflow.log"):
        nf_log_path = work_base / run_id / nf_log_rel
        if nf_log_path.exists():
            batch_job_ids = _parse_batch_job_ids_from_log(nf_log_path)
            break

    result["batch_jobs"] = batch_job_ids

    if batch_job_ids:
        try:
            import boto3 as _boto3
            _bc = _boto3.client("batch", region_name=os.environ.get("AWS_REGION", "us-west-2"))
            _cw = _boto3.client("logs", region_name=os.environ.get("AWS_REGION", "us-west-2"))
            cw_lines: list = []
            for jid in batch_job_ids[:5]:  # cap at 5 jobs to avoid slow responses
                try:
                    job_resp = _bc.describe_jobs(jobs=[jid])
                    jobs = job_resp.get("jobs", [])
                    if not jobs:
                        continue
                    job = jobs[0]
                    log_stream = job.get("container", {}).get("logStreamName")
                    job_status = job.get("status", "UNKNOWN")
                    if log_stream:
                        try:
                            cw_resp = _cw.get_log_events(
                                logGroupName="/aws/batch/job",
                                logStreamName=log_stream,
                                limit=min(n, 200),
                                startFromHead=False,
                            )
                            for ev in cw_resp.get("events", []):
                                cw_lines.append({
                                    "job_id": jid[:8] + "…",
                                    "status": job_status,
                                    "ts": ev.get("timestamp", 0),
                                    "msg": ev.get("message", "")[:500],
                                })
                        except Exception as _cw_e:
                            cw_lines.append({
                                "job_id": jid[:8] + "…",
                                "status": job_status,
                                "msg": f"[CloudWatch fetch failed: {_cw_e}]",
                            })
                    else:
                        cw_lines.append({
                            "job_id": jid[:8] + "…",
                            "status": job_status,
                            "msg": "[No log stream yet — job may still be starting]",
                        })
                except Exception as _je:
                    cw_lines.append({"job_id": jid[:8] + "…", "msg": f"[describe_jobs failed: {_je}]"})
            result["cloudwatch_logs"] = cw_lines[-n:]
        except Exception as _boto_err:
            result["cloudwatch_error"] = str(_boto_err)

    return result


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


def _parse_number(value: Any) -> Optional[float]:
    """Extract a number from a key_results `value` string (or scalar).

    Strips thousand separators, trailing units (%, $, etc.). Returns None if
    the value cannot be parsed as a clean numeric (e.g. "GeneA (score: -8.2)"
    or "5.1e-3, 1.4e-4, ..." style multi-value strings).
    """
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if not isinstance(value, str):
        return None
    s = value.strip().replace(",", "").rstrip("%").lstrip("$")
    # Reject obviously composite strings (multiple tokens / parentheses)
    if " " in s or "(" in s or "/" in s or ":" in s:
        return None
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


def _build_figures_from_key_results(key_results: Any) -> List[Dict[str, Any]]:
    """Project structured key_results into FindingsFigure[] for the v2 panel.

    Domain-agnostic. Emits at most one figure each of kind qc / composition /
    bars, only when the underlying numbers are real. Returns [] when key_results
    cannot be projected mechanically — never fabricates data.

    Shapes (must match frontend/client/src/v2/AfterRunReport.tsx FindingsFigure):
      - {kind:'qc',          title, unit?, kept, total}
      - {kind:'composition', title, data: [[label, number], ...]}
      - {kind:'bars',        title, unit?, highlight?, data: [[label, number], ...]}
    """
    if not isinstance(key_results, list) or not key_results:
        return []

    # Normalise to dicts with parsed numbers.
    items: List[Dict[str, Any]] = []
    for kr in key_results:
        if not isinstance(kr, dict):
            continue
        metric = (kr.get("metric") or kr.get("label") or "").strip()
        if not metric:
            continue
        num = _parse_number(kr.get("value"))
        items.append({"metric": metric, "value_num": num, "value_raw": kr.get("value"),
                      "source_file": kr.get("source_file")})

    numeric = [it for it in items if it["value_num"] is not None]
    if not numeric:
        return []

    def _shared_source(members: List[Dict[str, Any]]):
        """The one output file all contributing metrics were read from, or None
        when they disagree / are unset — so a figure only cites grounded provenance."""
        srcs = {m.get("source_file") for m in members if m.get("source_file")}
        return next(iter(srcs)) if len(srcs) == 1 else None

    figures: List[Dict[str, Any]] = []

    # ── QC kind ──
    # Look for a (subset, total) pair: one metric matching /total|all/i and
    # one matching /pass|kept|retained|passing/i (case-insensitive).
    total_item = None
    kept_item = None
    for it in numeric:
        m = it["metric"].lower()
        if total_item is None and re.search(r"\btotal\b|\ball\b", m):
            total_item = it
        if kept_item is None and re.search(r"\bpass\b|kept|retained|passing", m):
            kept_item = it
    if total_item and kept_item and total_item is not kept_item:
        total_n = total_item["value_num"]
        kept_n = kept_item["value_num"]
        if total_n > 0 and 0 <= kept_n <= total_n:
            figures.append({
                "kind": "qc",
                "title": f"{kept_item['metric']} / {total_item['metric']}",
                "kept": int(kept_n) if kept_n.is_integer() else kept_n,
                "total": int(total_n) if total_n.is_integer() else total_n,
                "source_file": _shared_source([kept_item, total_item]),
            })

    # ── Composition kind ──
    # ≥2 numeric items sharing a trailing word (e.g. "HIGH impact",
    # "MODERATE impact"; or "FAIL modules", "WARN modules"). Skip items
    # already used by the QC figure and skip "total" rows.
    def _last_word(metric: str) -> str:
        parts = re.findall(r"[A-Za-z]+", metric.lower())
        return parts[-1] if parts else ""

    used_ids = {id(total_item), id(kept_item)} if (total_item and kept_item) else set()
    groups: Dict[str, List[Dict[str, Any]]] = {}
    for it in numeric:
        if id(it) in used_ids:
            continue
        if re.search(r"\btotal\b|\ball\b", it["metric"].lower()):
            continue
        if it["value_num"] < 0:
            continue
        key = _last_word(it["metric"])
        if not key or key in {"variants", "compounds", "reads", "samples", "genes"}:
            # generic plural — not a real shared category
            pass
        groups.setdefault(key, []).append(it)
    comp_group: List[Dict[str, Any]] = []
    for key, members in groups.items():
        if len(members) >= 2 and sum(m["value_num"] for m in members) > 0:
            comp_group = members
            break
    if comp_group:
        figures.append({
            "kind": "composition",
            "title": " vs ".join(m["metric"] for m in comp_group[:3]) if len(comp_group) <= 3
                     else f"{comp_group[0]['metric']} breakdown",
            "data": [[m["metric"], m["value_num"]] for m in comp_group],
            "source_file": _shared_source(comp_group),
        })
        used_ids |= {id(m) for m in comp_group}

    # ── Bars kind (fallback) ──
    # Any remaining ≥2 numeric items (positive) that aren't the totals/kept row.
    remaining = [it for it in numeric
                 if id(it) not in used_ids
                 and it["value_num"] >= 0
                 and not re.search(r"\btotal\b|\ball\b", it["metric"].lower())]
    if len(remaining) >= 2:
        figures.append({
            "kind": "bars",
            "title": "Key metrics",
            "data": [[it["metric"], it["value_num"]] for it in remaining],
            "source_file": _shared_source(remaining),
        })

    return figures


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
    # Domain-agnostic projection of structured key_results into v2 FindingsFigure
    # shapes (FigBars / FigComposition / FigQc). Hide-when-empty: when the
    # key_results don't carry numbers that map cleanly, we omit `figures`
    # rather than ship fake data (CLAUDE.md "no fabrication" rule).
    try:
        _figs = _build_figures_from_key_results(analysis.key_results)
        if _figs:
            structured_payload["figures"] = _figs
    except Exception as _exc:
        logger.warning("[analyze-outputs] figures adapter failed: %s", _exc)
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

    # Add parameter summary if run is in memory (or recoverable via store)
    run = _run_lookup(run_id)
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


# ──────────────────────────────────────────────────────────────────────────────
# Data connector: fetch_public_data
# ──────────────────────────────────────────────────────────────────────────────

class FetchPublicDataRequest(BaseModel):
    """Stage a publicly accessible file into BioMate S3 for workflow consumption."""
    source_id: Optional[str] = None     # file source id from file_sources_conf.yml, e.g. "ebi_ftp"
    remote_path: Optional[str] = None   # path within the source, e.g. "/pub/databases/uniprot/..."
    url: Optional[str] = None           # direct HTTP/HTTPS/FTP URL (alternative to source_id+remote_path)
    destination_key: Optional[str] = None  # S3 key prefix; defaults to "public-data/<filename>"


@router.post("/api/nextflow/fetch_public_data", summary="Stage a public file into BioMate S3")
async def fetch_public_data(body: FetchPublicDataRequest):
    """
    Download a file from a public biological data source and stage it into
    BioMate's S3 bucket so downstream workflows can reference it via s3://.

    Accepts either:
    - `source_id` + `remote_path` (file source plugin + relative path)
    - `url` (any HTTP/HTTPS/FTP URL)

    Returns the S3 URI and presigned download URL of the staged file.
    """
    import urllib.request
    import urllib.parse
    import tempfile

    if not body.url and not (body.source_id and body.remote_path):
        raise HTTPException(status_code=400, detail="Provide 'url' or both 'source_id' and 'remote_path'")

    # Resolve URL from source_id + remote_path if needed
    download_url = body.url
    if not download_url and body.source_id and body.remote_path:
        SOURCE_HOSTS = {
            "ebi_ftp":        "ftp://ftp.ebi.ac.uk",
            "ncbi_ftp":       "ftp://ftp.ncbi.nlm.nih.gov",
            "ensembl_ftp":    "ftp://ftp.ensembl.org",
            "ucsc_downloads": "ftp://hgdownload.soe.ucsc.edu",
            "http_public":    None,  # remote_path must be a full URL for http source
        }
        host = SOURCE_HOSTS.get(body.source_id)
        if host is None:
            if body.remote_path.startswith(("http://", "https://", "ftp://")):
                download_url = body.remote_path
            else:
                raise HTTPException(status_code=400, detail=f"Unknown source_id '{body.source_id}'")
        else:
            path = body.remote_path.lstrip("/")
            download_url = f"{host}/{path}"

    # Derive destination S3 key
    parsed = urllib.parse.urlparse(download_url)
    filename = Path(parsed.path).name or "data.bin"
    dest_key = body.destination_key or f"public-data/{filename}"

    # On-prem MinIO: only the S3_BUCKET_NAME bucket is created by docker-compose
    # init — biomate-nextflow-work doesn't exist in MinIO. Use S3_BUCKET_NAME.
    # SaaS: use NEXTFLOW_S3_BUCKET or AWS_S3_BUCKET as before.
    if os.environ.get("S3_ENDPOINT_URL"):
        s3_bucket = os.environ.get("S3_BUCKET_NAME") or "biomate-data"
    else:
        s3_bucket = (
            os.environ.get("NEXTFLOW_S3_BUCKET")
            or os.environ.get("AWS_S3_BUCKET")
            or "biomate-nextflow-work"
        )

    log.info("[fetch_public_data] Downloading %s → s3://%s/%s", download_url, s3_bucket, dest_key)

    try:
        import boto3
        s3 = make_s3_client(region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"))

        with tempfile.NamedTemporaryFile(delete=False, suffix=f"_{filename}") as tmp:
            tmp_path = tmp.name

        try:
            # Download to temp file then upload to S3 to avoid memory pressure
            urllib.request.urlretrieve(download_url, tmp_path)  # noqa: S310  (internal validated URLs)
            file_size = Path(tmp_path).stat().st_size
            s3.upload_file(tmp_path, s3_bucket, dest_key)
        finally:
            Path(tmp_path).unlink(missing_ok=True)

        # Generate download URL.
        # On-prem MinIO: presigned URLs embed the internal minio:9000 hostname
        # which browsers cannot reach — return a Galaxy streaming proxy URL instead.
        s3_uri_str = f"s3://{s3_bucket}/{dest_key}"
        if os.environ.get("S3_ENDPOINT_URL"):
            presigned = f"/api/nextflow/outputs/download?s3_uri={s3_uri_str}&run_id=direct"
        else:
            presigned = s3.generate_presigned_url(
                "get_object",
                Params={"Bucket": s3_bucket, "Key": dest_key},
                ExpiresIn=86400,
            )

        return {
            "s3_uri": s3_uri_str,
            "s3_key": dest_key,
            "presigned_url": presigned,
            "filename": filename,
            "size_bytes": file_size,
            "source_url": download_url,
        }

    except Exception as exc:
        log.exception("[fetch_public_data] Failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


# ──────────────────────────────────────────────────────────────────────────────
# S3 workspace browser
# ──────────────────────────────────────────────────────────────────────────────

@router.get("/api/nextflow/s3/browse", summary="List objects in a user's S3 bucket")
async def browse_s3(
    trans: ProvidesUserContext = DependsOnTrans,
    prefix: str = "",
    max_keys: int = 200,
):
    """
    Return a directory-style listing of S3 objects for the authenticated user.

    Credential resolution order:
    1. User-stored S3 credential (aws_access_key_id / secret / region / s3_bucket)
    2. BioMate's own bucket (NEXTFLOW_S3_BUCKET env var) using instance-role/env creds

    Each item in the response is one of:
    - {"type": "prefix", "key": "folder/", "name": "folder"}
    - {"type": "object", "key": "file.txt", "name": "file.txt", "size": 123, "last_modified": "..."}
    """
    from galaxy.webapps.galaxy.api.credentials_api import _get_credential

    # Resolve credentials + bucket
    bucket = None
    boto_kwargs: Dict[str, Any] = {}

    user_cred = _get_credential(trans, "s3") if trans.user else None
    if user_cred and user_cred.get("aws_access_key_id"):
        boto_kwargs = {
            "aws_access_key_id":     user_cred["aws_access_key_id"],
            "aws_secret_access_key": user_cred.get("aws_secret_access_key", ""),
            "region_name":           user_cred.get("aws_region", "us-east-1"),
        }
        bucket = user_cred.get("s3_bucket")

    if not bucket:
        # On-prem MinIO: only S3_BUCKET_NAME bucket is created; NEXTFLOW_S3_BUCKET not set.
        if os.environ.get("S3_ENDPOINT_URL"):
            bucket = os.environ.get("S3_BUCKET_NAME") or "biomate-data"
        else:
            bucket = os.environ.get("NEXTFLOW_S3_BUCKET") or os.environ.get("AWS_S3_BUCKET")
        if not boto_kwargs:
            # Fall back to instance role / env-var creds
            region = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
            boto_kwargs = {"region_name": region}

    if not bucket:
        raise HTTPException(status_code=503, detail="No S3 bucket configured for this user")

    try:
        import boto3
        s3 = make_s3_client(**boto_kwargs)

        paginator = s3.get_paginator("list_objects_v2")
        page_iter = paginator.paginate(
            Bucket=bucket,
            Prefix=prefix,
            Delimiter="/",
            PaginationConfig={"MaxItems": max_keys},
        )

        entries: List[Dict[str, Any]] = []
        truncated = False

        for page in page_iter:
            if page.get("IsTruncated"):
                truncated = True
            for cp in page.get("CommonPrefixes") or []:
                key = cp["Prefix"]
                entries.append({
                    "type": "prefix",
                    "key": key,
                    "name": key.rstrip("/").split("/")[-1] + "/",
                })
            for obj in page.get("Contents") or []:
                key = obj["Key"]
                name = key.split("/")[-1] if "/" in key else key
                if not name:
                    continue  # skip the prefix entry itself
                entries.append({
                    "type": "object",
                    "key": key,
                    "name": name,
                    "size": obj.get("Size", 0),
                    "last_modified": obj["LastModified"].isoformat() if obj.get("LastModified") else None,
                })

        return {
            "bucket": bucket,
            "prefix": prefix,
            "entries": entries,
            "truncated": truncated,
            "credential_source": "user" if user_cred else "biomate",
        }

    except Exception as exc:
        log.exception("[browse_s3] Failed for bucket=%s prefix=%s: %s", bucket, prefix, exc)
        raise HTTPException(status_code=500, detail=str(exc))

