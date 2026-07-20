#!/usr/bin/env python3
"""
BioMate MCP Server  —  DEPRECATED (v1.0.0)
==========================================

.. deprecated:: 1.0.0
    This standalone v1.0.0 stdio server is **superseded** and no longer
    maintained. The current, maintained MCP server lives in the separate
    connector repository:

        github.com/bioMate-AI/biomate-connector  →  mcp/biomate_mcp_server.py (v2.0.0)

    That server is schema-driven from a single ``tools_manifest.py`` (17 tools
    with Directory-compliant ``title`` + ``annotations``), ships OAuth 2.1 +
    PKCE, and is what is published as ``@biomate/connect`` and submitted to the
    Anthropic Claude Directory.

    This file's tool set is stale and is not wired into any deployment. It is
    kept only so historical ``python -m backend.lib.mcp`` / Claude Desktop
    configs do not hard-break. Do not add features here — make changes in the
    connector repo. Removal is tracked; migrate any local config to
    ``npx @biomate/connect`` before it is deleted.
    (The sibling ``backend/mcp/biomate_mcp_server.py`` v1.1.0 is also deprecated.)

Exposes BioMate's scientific workflow capabilities as MCP (Model Context Protocol) tools,
enabling any MCP-compatible AI client (Claude Desktop, Cursor, etc.) to invoke BioMate
workflows, search databases, and retrieve results.

Transport: stdio (JSON-RPC 2.0, newline-delimited)

Usage:
    python -m biomate_mcp_server
    # or directly:
    python backend/lib/mcp/biomate_mcp_server.py

Configuration (environment variables):
    BIOMATE_API_URL     BioMate server URL (default: http://localhost:5000)
    BIOMATE_API_KEY     User API key for authentication
    BIOMATE_USER_EMAIL  User email (alternative to API key)

MCP tools exposed:
    search_workflow     Search BioMate workflow catalog by natural language query
    run_workflow        Execute a workflow with parameters on AWS Batch
    get_run_status      Poll status of a running workflow execution
    get_run_results     Retrieve output files from a completed run
    query_database      Query a biological database (UniProt, PDB, NCBI Gene, etc.)
    analyze_file        Run lightweight data analysis on an S3 key or inline data
    biomate_session     End-to-end: NL goal → route → execute → poll → return outputs
"""

import json
import sys
import os
import logging
import time
import threading
import warnings
from typing import Any, Dict, List, Optional

import requests

# ──────────────────────────────────────────────────────────────────────────────
# Config
# ──────────────────────────────────────────────────────────────────────────────

BIOMATE_API_URL = os.environ.get("BIOMATE_API_URL", "http://localhost:5000")
BIOMATE_API_KEY = os.environ.get("BIOMATE_API_KEY", "")
SERVER_NAME = "biomate"
SERVER_VERSION = "2.0.0"
PROTOCOL_VERSION = "2024-11-05"

# Thread-safe stdout — progress notifications are emitted from worker threads
# while the main loop continues reading stdin.
_send_lock = threading.Lock()

logging.basicConfig(
    stream=sys.stderr,
    level=logging.DEBUG if os.environ.get("MCP_DEBUG") else logging.WARNING,
    format="[BioMate MCP] %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)

# ──────────────────────────────────────────────────────────────────────────────
# Tool definitions — sourced from the canonical manifest
# ──────────────────────────────────────────────────────────────────────────────
# Single source of truth lives in backend/lib/mcp/tools_manifest.py. All other
# surfaces (Open Claw, Slack, WeChat, ChatGPT GPT, Claude Skill catalog) are
# generated from the same module. See docs/20260513_CONNECTOR_ARCHITECTURE_V2.md.

from backend.lib.mcp.tools_manifest import (
    to_mcp as _manifest_to_mcp,
    get_tool as _manifest_get_tool,
)

TOOLS: List[Dict[str, Any]] = _manifest_to_mcp()

# Schema definitions live exclusively in backend/lib/mcp/tools_manifest.py.
# Legacy inline definition kept as fallback comment only.
_TOOLS_LEGACY_HEAD: List[Dict[str, Any]] = [
    {
        "name": "search_workflow",
        "description": (
            "Search the BioMate scientific workflow catalog using a natural language query. "
            "Returns a ranked list of matching workflows with descriptions, required inputs, "
            "and estimated compute time. Use this before run_workflow to find the right workflow ID."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Natural language description of what you want to do. "
                                   "Examples: 'run ADMET screening on these SMILES', "
                                   "'variant calling from FASTQ files', 'protein structure prediction'",
                },
                "limit": {
                    "type": "integer",
                    "description": "Maximum number of results to return (default: 5, max: 20)",
                    "default": 5,
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "run_workflow",
        "description": (
            "Execute a BioMate scientific workflow on AWS Batch. "
            "Returns a run_id you can poll with get_run_status. "
            "Use search_workflow first to find the workflow_id and required parameters."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "workflow_id": {
                    "type": "string",
                    "description": "Workflow identifier from search_workflow results (e.g. 'assay_ingestion_and_ranking')",
                },
                "params": {
                    "type": "object",
                    "description": "Workflow parameters as key-value pairs. "
                                   "Required params vary by workflow — check search_workflow output.",
                    "additionalProperties": True,
                },
                "session_message": {
                    "type": "string",
                    "description": "Optional: natural language message describing what you want. "
                                   "BioMate AI will auto-fill parameters from this if params are incomplete.",
                },
            },
            "required": ["workflow_id"],
        },
    },
    {
        "name": "get_run_status",
        "description": (
            "Poll the status of a BioMate workflow run. "
            "Returns status (pending | running | completed | failed), "
            "step progress (N/total), elapsed time, and any error message."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "run_id": {
                    "type": "string",
                    "description": "Run ID returned by run_workflow",
                },
            },
            "required": ["run_id"],
        },
    },
    {
        "name": "get_run_results",
        "description": (
            "Retrieve output files and summary data from a completed BioMate run. "
            "Returns a list of output files with download URLs, file types, and sizes. "
            "Only call this after get_run_status returns status='completed'."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "run_id": {
                    "type": "string",
                    "description": "Run ID of a completed run",
                },
            },
            "required": ["run_id"],
        },
    },
    {
        "name": "query_database",
        "description": (
            "Query a biological/chemical database by accession, name, or structured query. "
            "Returns structured data cards: protein info (UniProt), structure (PDB/AlphaFold), "
            "gene info (NCBI Gene), variants (dbSNP/ClinVar), pathways (KEGG), "
            "compounds (ChEBI/PubChem), phenotypes (HPO), interactions (STRING)."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "database": {
                    "type": "string",
                    "enum": [
                        "uniprot", "pdb", "alphafold", "ncbi_gene",
                        "dbsnp", "clinvar", "gnomad",
                        "kegg", "reactome",
                        "chebi", "pubchem",
                        "hpo", "omim",
                        "string",
                    ],
                    "description": "Target database to query",
                },
                "query": {
                    "type": "string",
                    "description": "Accession number, gene symbol, compound name, or search query. "
                                   "Examples: 'P04637' (UniProt), 'BRCA1' (gene), 'ibuprofen' (compound), "
                                   "'1TUP' (PDB), 'rs7412' (dbSNP)",
                },
            },
            "required": ["database", "query"],
        },
    },
    {
        "name": "analyze_file",
        "description": (
            "Run lightweight data analysis on an uploaded file. "
            "Returns format-specific QC metrics: "
            "FASTQ (read count, quality distribution, adapter contamination), "
            "CSV/TSV (row count, column names, data preview, missing value counts), "
            "VCF (variant count, chromosome distribution, FILTER pass rate), "
            "FASTA (sequence count, length distribution, GC content)."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "s3_key": {
                    "type": "string",
                    "description": "S3 key of the file to analyze (s3://bucket/path/to/file)",
                },
                "inline_data": {
                    "type": "string",
                    "description": "Small file content passed inline (max 50KB). Use s3_key for larger files.",
                },
                "file_type": {
                    "type": "string",
                    "enum": ["fastq", "csv", "tsv", "vcf", "fasta", "bam", "auto"],
                    "description": "File type hint (default: auto-detect from extension or content)",
                    "default": "auto",
                },
            },
        },
    },
    {
        "name": "cancel_run",
        "description": (
            "Cancel a running or queued BioMate workflow job on AWS Batch. "
            "Use when the user wants to stop a run, or before launching a corrected replacement."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "run_id": {"type": "string", "description": "Run ID to cancel"},
            },
            "required": ["run_id"],
        },
    },
    {
        "name": "list_runs",
        "description": (
            "List the user's recent BioMate workflow runs with status and timestamps. "
            "Useful for checking what jobs are currently running or recently completed."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "limit": {"type": "integer", "description": "Max runs to return (default 10)", "default": 10},
                "status": {
                    "type": "string",
                    "enum": ["all", "running", "completed", "failed", "pending"],
                    "description": "Filter by status (default: all)",
                    "default": "all",
                },
            },
        },
    },
    {
        "name": "analyze_results",
        "description": (
            "Ask BioMate's AI to interpret and summarize outputs from a completed run. "
            "Returns a natural language analysis: key findings, quality metrics, "
            "scientific interpretation, and recommended next steps."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "run_id": {"type": "string", "description": "Run ID of a completed run"},
                "question": {
                    "type": "string",
                    "description": "Optional specific question, e.g. 'which compounds passed ADMET filters?'",
                },
            },
            "required": ["run_id"],
        },
    },
    {
        "name": "explain_error",
        "description": (
            "Ask BioMate's AI to diagnose why a failed workflow run failed. "
            "Returns the likely root cause (genome mismatch, missing input, resource OOM, etc.) "
            "and the specific fix to apply."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "run_id": {"type": "string", "description": "Run ID of a failed run to diagnose"},
                "error_log": {
                    "type": "string",
                    "description": "Optional: paste the error log directly if run_id lookup is unavailable",
                },
            },
            "required": ["run_id"],
        },
    },
    {
        "name": "biomate_session",
        "description": (
            "Run a complete BioMate scientific session end-to-end from a natural-language goal. "
            "BioMate automatically: (1) routes to the correct workflow, (2) extracts parameters "
            "from context, (3) executes on AWS Batch, (4) waits for completion, (5) returns "
            "outputs, QC results, findings, and a link to the live results panel. "
            "Use this for hands-free execution when you know the scientific goal but not the "
            "exact workflow ID or parameter names."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "goal": {
                    "type": "string",
                    "description": (
                        "Natural language description of the analysis to run. "
                        "Examples: 'Run DESeq2 differential expression on treated vs control', "
                        "'Screen these SMILES for ADMET liabilities', "
                        "'Predict the structure of this protein sequence with AlphaFold'."
                    ),
                },
                "inputs": {
                    "type": "object",
                    "description": (
                        "Optional structured inputs to merge with auto-extracted params. "
                        "Use this to pass file paths, sample lists, SMILES strings, etc."
                    ),
                    "additionalProperties": True,
                },
            },
            "required": ["goal"],
        },
    },
]

# ──────────────────────────────────────────────────────────────────────────────
# HTTP client to BioMate API
# ──────────────────────────────────────────────────────────────────────────────

class BioMateClient:
    def __init__(self, base_url: str, api_key: str):
        self.base_url = base_url.rstrip("/")
        self.session = requests.Session()
        if api_key:
            self.session.headers["Authorization"] = f"Bearer {api_key}"
        self.session.headers["Content-Type"] = "application/json"
        self.session.headers["User-Agent"] = f"BioMate-MCP/{SERVER_VERSION}"

    def _url(self, path: str) -> str:
        return f"{self.base_url}{path}"

    def search_workflow(self, query: str, limit: int = 5) -> Dict[str, Any]:
        try:
            r = self.session.post(
                self._url("/api/workflows/search"),
                json={"query": query, "limit": limit},
                timeout=15,
            )
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc), "results": []}

    def run_workflow(self, workflow_id: str, params: dict, session_message: Optional[str] = None) -> Dict[str, Any]:
        # workflow_id should be the nextflow_path from search_workflow (e.g.
        # "pharmacology/herg_cardiac_safety_qsar/main.nf").
        # POST /api/workflows/execute expects a workflowDefinition envelope.
        payload: Dict[str, Any] = {
            "workflowDefinition": {
                "nextflow_path": workflow_id,
                "workflow_type": "nextflow",
                "parameters": params or {},
            }
        }
        if session_message:
            payload["workflowDefinition"]["description"] = session_message
        try:
            r = self.session.post(
                self._url("/api/workflows/execute"),
                json=payload,
                timeout=60,
            )
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc)}

    def get_run_status(self, run_id: str) -> Dict[str, Any]:
        try:
            r = self.session.get(
                self._url(f"/api/nextflow/runs/{run_id}/status"),
                timeout=10,
            )
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc), "run_id": run_id}

    def get_run_results(self, run_id: str) -> Dict[str, Any]:
        try:
            r = self.session.get(
                self._url(f"/api/nextflow/runs/{run_id}/outputs"),
                timeout=15,
            )
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc), "run_id": run_id}

    def query_database(self, database: str, query: str) -> Dict[str, Any]:
        try:
            r = self.session.post(
                self._url("/api/databases/query"),
                json={"database": database, "query": query},
                timeout=20,
            )
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc), "database": database, "query": query}

    def analyze_file(self, s3_key: Optional[str], inline_data: Optional[str], file_type: str = "auto") -> Dict[str, Any]:
        payload: Dict[str, Any] = {"file_type": file_type}
        if s3_key:
            payload["s3_key"] = s3_key
        if inline_data:
            payload["inline_data"] = inline_data
        try:
            r = self.session.post(self._url("/api/data/analyze"), json=payload, timeout=60)
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc)}

    def cancel_run(self, run_id: str) -> Dict[str, Any]:
        try:
            r = self.session.post(self._url(f"/api/workflows/runs/{run_id}/cancel"), json={}, timeout=15)
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc), "run_id": run_id}

    def list_runs(self, limit: int = 10, status: str = "all") -> Dict[str, Any]:
        params: Dict[str, str] = {"limit": str(limit)}
        if status != "all":
            params["status"] = status
        try:
            r = self.session.get(self._url("/api/workflows/runs"), params=params, timeout=15)
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc)}

    def analyze_results(self, run_id: str, question: str) -> Dict[str, Any]:
        try:
            r = self.session.post(
                self._url(f"/api/workflows/runs/{run_id}/ai/analyze"),
                json={"question": question},
                timeout=60,
            )
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc), "run_id": run_id}

    def explain_error(self, run_id: str, error_log: str = "") -> Dict[str, Any]:
        try:
            r = self.session.post(
                self._url("/api/workflows/explain_error"),
                json={"run_id": run_id, "error_log": error_log},
                timeout=30,
            )
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc), "run_id": run_id}

    def biomate_session(self, goal: str, inputs: Optional[dict] = None) -> Dict[str, Any]:
        """End-to-end session: route NL goal → execute workflow → poll → return outputs."""
        # Step 1: Route NL goal to the best matching workflow via search
        log.warning(f"biomate_session: routing goal: {goal[:80]}")
        try:
            r = self.session.post(
                self._url("/api/workflows/search"),
                json={"query": goal, "limit": 1},
                timeout=30,
            )
            r.raise_for_status()
            wf_data = r.json()
        except Exception as exc:
            return {"error": f"Workflow routing failed: {exc}", "goal": goal}

        if not wf_data.get("success"):
            return {
                "error": "No workflow matched the goal",
                "goal": goal,
                "routing_response": wf_data,
            }

        # Extract workflow identifier — prefer human-readable name over path
        workflow_name = (
            wf_data.get("chain_name")
            or wf_data.get("workflow_name")
        )
        # Prefer chain_name / workflow_name as the invoke key; fall back to nextflow_path
        workflow_id = workflow_name or wf_data.get("nextflow_path")
        if not workflow_id:
            return {
                "error": "No workflow_id could be determined from routing result",
                "goal": goal,
                "routing_response": wf_data,
            }

        # Step 2: Merge auto-extracted default params with caller-supplied inputs
        generated_params: Dict[str, Any] = {}
        for p in wf_data.get("generated_parameters", []):
            if p.get("default") is not None:
                generated_params[p["name"]] = p["default"]
        if inputs:
            generated_params.update(inputs)

        nextflow_path = wf_data.get("nextflow_path") or workflow_id
        workflow_type = wf_data.get("workflow_type", "nextflow")
        log.warning(
            f"biomate_session: invoking nextflow_path={nextflow_path} "
            f"params={list(generated_params.keys())}"
        )

        # Step 3: Invoke via /api/workflows/execute with workflowDefinition envelope
        try:
            r = self.session.post(
                self._url("/api/workflows/execute"),
                json={
                    "workflowDefinition": {
                        "nextflow_path": nextflow_path,
                        "workflow_type": workflow_type,
                        "parameters": generated_params,
                    }
                },
                timeout=60,
            )
            r.raise_for_status()
            invoke_data = r.json()
        except Exception as exc:
            return {"error": f"Invocation failed: {exc}", "workflow_id": workflow_id}

        run_id = (
            invoke_data.get("run_id")
            or invoke_data.get("runId")
            or invoke_data.get("id")
        )
        if not run_id:
            return {"error": "No run_id in invocation response", "invoke_response": invoke_data}

        log.warning(f"biomate_session: run_id={run_id} — polling for completion")

        # Step 4: Poll until terminal state (max ~30 min)
        status_data: Dict[str, Any] = {}
        final_status = "unknown"
        terminal = {"completed", "failed", "error", "cancelled"}
        for _ in range(120):  # 120 * 15s = 30 min ceiling
            time.sleep(15)
            status_data = self.get_run_status(run_id)
            final_status = status_data.get("status", "unknown")
            if final_status in terminal:
                break

        log.warning(f"biomate_session: final_status={final_status}")

        # Step 5: Fetch outputs on success
        outputs: Dict[str, Any] = {}
        if final_status == "completed":
            try:
                outputs = self.get_run_results(run_id)
            except Exception as exc:
                outputs = {"error": str(exc)}

        return {
            "goal": goal,
            "workflow_name": workflow_name,
            "workflow_id": workflow_id,
            "run_id": run_id,
            "status": final_status,
            "outputs": outputs,
            "panel_url": f"{self.base_url}/runs/{run_id}",
            "raw_status": status_data,
        }

    # ── Tier 2/3 (v2 manifest) ────────────────────────────────────────────────

    def get_workflow_spec(self, workflow_id: str) -> Dict[str, Any]:
        try:
            r = self.session.get(
                self._url("/api/workflows/spec"),
                params={"workflow_id": workflow_id},
                timeout=15,
            )
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc), "workflow_id": workflow_id}

    def get_run(self, run_id: str, include_findings: bool = True) -> Dict[str, Any]:
        try:
            r = self.session.get(
                self._url(f"/api/workflows/runs/{run_id}"),
                params={"include_findings": "true" if include_findings else "false"},
                timeout=15,
            )
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc), "run_id": run_id}

    def preview_file(self, s3_key: str, run_id: Optional[str] = None, max_rows: int = 100) -> Dict[str, Any]:
        payload: Dict[str, Any] = {"s3_key": s3_key, "max_rows": max_rows}
        if run_id:
            payload["run_id"] = run_id
        try:
            r = self.session.post(self._url("/api/files/preview"), json=payload, timeout=30)
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc), "s3_key": s3_key}

    def export_report(self, run_id: str, fmt: str = "pdf", sections: Optional[List[str]] = None) -> Dict[str, Any]:
        payload: Dict[str, Any] = {"format": fmt}
        if sections:
            payload["sections"] = sections
        try:
            r = self.session.post(
                self._url(f"/api/workflows/runs/{run_id}/findings/report"),
                json=payload,
                timeout=120,
            )
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc), "run_id": run_id}

    def recall_memory(self, query: str, scope: str = "all", limit: int = 5) -> Dict[str, Any]:
        try:
            r = self.session.post(
                self._url("/api/memory/relevant"),
                json={"query": query, "scope": scope, "limit": limit},
                timeout=20,
            )
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc)}

    def upload_signed_url(self, filename: str, size_bytes: Optional[int], content_type: Optional[str]) -> Dict[str, Any]:
        payload: Dict[str, Any] = {"filename": filename}
        if size_bytes is not None:
            payload["size_bytes"] = size_bytes
        if content_type:
            payload["content_type"] = content_type
        try:
            r = self.session.post(self._url("/api/uploads/signed_url"), json=payload, timeout=15)
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"error": str(exc), "filename": filename}

    def open_claw_stream(self, goal: str, inputs: Optional[Dict[str, Any]], experiment_id: Optional[str]):
        """Generator yielding SSE events from /api/open-claw/stream.

        Each yielded dict has shape: {event: <name>, data: <parsed json or str>}.
        The bridge in SessionRunner converts these into MCP progress notifications.
        """
        messages = [{"role": "user", "content": goal}]
        payload: Dict[str, Any] = {"messages": messages}
        if inputs:
            payload["inputs"] = inputs
        if experiment_id:
            payload["experiment_id"] = experiment_id

        headers = dict(self.session.headers)
        headers["Accept"] = "text/event-stream"

        with self.session.post(
            self._url("/api/open-claw/stream"),
            json=payload,
            headers=headers,
            stream=True,
            timeout=(30, 600),  # 10-min idle limit
        ) as resp:
            resp.raise_for_status()
            current_event = "message"
            for raw_line in resp.iter_lines(decode_unicode=True):
                if not raw_line:
                    continue
                if raw_line.startswith(":"):
                    continue  # SSE comment / keep-alive
                if raw_line.startswith("event:"):
                    current_event = raw_line[6:].strip()
                    continue
                if raw_line.startswith("data:"):
                    data_str = raw_line[5:].strip()
                    try:
                        data = json.loads(data_str)
                    except json.JSONDecodeError:
                        data = data_str
                    yield {"event": current_event, "data": data}


# ──────────────────────────────────────────────────────────────────────────────
# Streaming bridge — BioMate SSE → MCP notifications/progress
# ──────────────────────────────────────────────────────────────────────────────

# Event shape contract (see docs/20260513_CONNECTOR_ARCHITECTURE_V2.md):
#   {kind, summary_md, view_url, thumbnail_png_b64?, delta}
# We normalize whatever the Open Claw stream emits into this shape so every
# downstream surface (Claude Code, Codex poll, Slack relay) shares one schema.

_PROGRESS_KINDS = {
    "phase_started", "phase_completed",
    "step_started", "step_completed", "step_failed",
    "qc_gate", "auto_loop_remediation",
    "finding", "report_ready",
    "text_delta", "done",
}


def _normalize_sse_event(evt: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Map an Open Claw SSE event into the canonical progress payload."""
    name = evt.get("event") or ""
    data = evt.get("data") or {}
    if not isinstance(data, dict):
        data = {"raw": data}

    # Open Claw emits a heterogeneous mix: tool_use, tool_result, text_delta,
    # workflow_phase, workflow_step, qc_gate, finding. Map each to a kind.
    if name in ("text_delta", "delta"):
        return {
            "kind": "text_delta",
            "summary_md": data.get("text") or data.get("delta") or "",
            "delta": data,
        }
    if name in ("workflow_phase", "phase"):
        status = data.get("status", "running")
        return {
            "kind": f"phase_{status}" if status in ("started", "completed", "failed") else "phase_started",
            "summary_md": f"**Phase:** {data.get('name', '?')} — {status}",
            "view_url": data.get("view_url"),
            "delta": data,
        }
    if name in ("workflow_step", "step"):
        status = data.get("status", "running")
        kind = "step_completed" if status == "completed" else ("step_failed" if status == "failed" else "step_started")
        return {
            "kind": kind,
            "summary_md": f"- {data.get('name', '?')} ({status})",
            "view_url": data.get("view_url"),
            "delta": data,
        }
    if name == "qc_gate":
        verdict = data.get("verdict", "unknown")
        return {
            "kind": "qc_gate",
            "summary_md": f"**QC gate:** {data.get('metric','?')} = {data.get('value','?')} → {verdict}",
            "view_url": data.get("view_url"),
            "thumbnail_png_b64": data.get("thumbnail_png_b64"),
            "delta": data,
        }
    if name == "auto_loop":
        return {
            "kind": "auto_loop_remediation",
            "summary_md": (
                f"**Auto-loop fix:** {data.get('param','?')}: "
                f"`{data.get('was')}` → `{data.get('now')}`"
            ),
            "delta": data,
        }
    if name == "finding":
        return {
            "kind": "finding",
            "summary_md": data.get("summary_md") or f"**Finding:** {data.get('title','(untitled)')}",
            "view_url": data.get("view_url"),
            "thumbnail_png_b64": data.get("thumbnail_png_b64"),
            "delta": data,
        }
    if name in ("done", "complete", "end"):
        return {
            "kind": "done",
            "summary_md": data.get("summary_md") or "**Done.**",
            "view_url": data.get("view_url"),
            "delta": data,
        }
    # Tool calls and unknown events are ignored — they're internal to Open Claw.
    return None


class SessionRunner(threading.Thread):
    """Runs biomate_session (or run_workflow stream=true) on a worker thread.

    Reads SSE from Open Claw, emits MCP notifications/progress for each event,
    and finally sends the tools/call response itself. The main loop continues
    handling other requests in the meantime.
    """

    def __init__(
        self,
        client: "BioMateClient",
        req_id: Any,
        tool_name: str,
        tool_args: Dict[str, Any],
        progress_token: Optional[Any],
    ):
        super().__init__(daemon=True)
        self.client = client
        self.req_id = req_id
        self.tool_name = tool_name
        self.tool_args = tool_args
        self.progress_token = progress_token
        self._final_run_id: Optional[str] = None
        self._final_view_url: Optional[str] = None
        self._final_summary_md: List[str] = []

    def _emit_progress(self, payload: Dict[str, Any], n: int, total: Optional[int] = None) -> None:
        if self.progress_token is None:
            return  # Client didn't ask for progress notifications
        params: Dict[str, Any] = {
            "progressToken": self.progress_token,
            "progress": n,
            "message": payload.get("summary_md", ""),
            "_meta": {
                "kind": payload.get("kind"),
                "view_url": payload.get("view_url"),
                "thumbnail_png_b64": payload.get("thumbnail_png_b64"),
                "delta": payload.get("delta"),
            },
        }
        if total is not None:
            params["total"] = total
        send({"jsonrpc": "2.0", "method": "notifications/progress", "params": params})

    def run(self) -> None:
        try:
            n = 0
            for evt in self.client.open_claw_stream(
                goal=self.tool_args.get("goal") or self.tool_args.get("session_message") or "",
                inputs=self.tool_args.get("inputs"),
                experiment_id=self.tool_args.get("experiment_id"),
            ):
                payload = _normalize_sse_event(evt)
                if payload is None:
                    continue
                n += 1
                self._emit_progress(payload, n)
                if payload.get("delta", {}).get("run_id"):
                    self._final_run_id = payload["delta"]["run_id"]
                if payload.get("view_url"):
                    self._final_view_url = payload["view_url"]
                if payload.get("kind") == "text_delta":
                    self._final_summary_md.append(payload.get("summary_md", ""))
                if payload.get("kind") == "done":
                    break

            final_text = "".join(self._final_summary_md).strip() or "Session complete."
            result_payload: Dict[str, Any] = {
                "summary_md": final_text,
                "run_id": self._final_run_id,
                "view_url": self._final_view_url,
            }
            send(make_response(self.req_id, {
                "content": [{"type": "text", "text": json.dumps(result_payload, indent=2)}],
                "isError": False,
            }))
        except Exception as exc:
            log.exception(f"SessionRunner error for {self.tool_name}")
            send(make_error(self.req_id, -32603, "Streaming tool error", str(exc)))


# ──────────────────────────────────────────────────────────────────────────────
# Tool dispatcher
# ──────────────────────────────────────────────────────────────────────────────

def dispatch_tool(client: BioMateClient, tool_name: str, args: Dict[str, Any]) -> Any:
    """Execute a non-streaming tool call. Returns JSON-serializable result.

    Streaming tools (biomate_session, run_workflow with stream=true) are
    dispatched via SessionRunner from handle_request — they do not flow
    through this function.
    """
    if tool_name == "search_workflow":
        return client.search_workflow(query=args["query"], limit=int(args.get("limit", 5)))

    if tool_name == "get_workflow_spec":
        return client.get_workflow_spec(workflow_id=args["workflow_id"])

    if tool_name == "run_workflow":
        return client.run_workflow(
            workflow_id=args["workflow_id"],
            params=args.get("params", {}),
            session_message=args.get("session_message"),
        )

    if tool_name == "get_run":
        return client.get_run(
            run_id=args["run_id"],
            include_findings=bool(args.get("include_findings", True)),
        )

    if tool_name == "cancel_run":
        return client.cancel_run(run_id=args["run_id"])

    if tool_name == "list_runs":
        return client.list_runs(
            limit=int(args.get("limit", 10)),
            status=args.get("status", "all"),
        )

    if tool_name == "preview_file":
        return client.preview_file(
            s3_key=args["s3_key"],
            run_id=args.get("run_id"),
            max_rows=int(args.get("max_rows", 100)),
        )

    if tool_name == "export_report":
        return client.export_report(
            run_id=args["run_id"],
            fmt=args.get("format", "pdf"),
            sections=args.get("sections"),
        )

    if tool_name == "analyze_results":
        return client.analyze_results(
            run_id=args["run_id"],
            question=args.get("question", "Summarize the key findings and scientific interpretation."),
        )

    if tool_name == "explain_error":
        return client.explain_error(
            run_id=args["run_id"],
            error_log=args.get("error_log", ""),
        )

    if tool_name == "query_database":
        return client.query_database(database=args["database"], query=args["query"])

    if tool_name == "recall_memory":
        return client.recall_memory(
            query=args["query"],
            scope=args.get("scope", "all"),
            limit=int(args.get("limit", 5)),
        )

    if tool_name == "upload_file":
        return client.upload_signed_url(
            filename=args["filename"],
            size_bytes=args.get("size_bytes"),
            content_type=args.get("content_type"),
        )

    # ── Legacy aliases (deprecated; remove after Phase 2 rollout) ─────────────
    if tool_name == "get_run_status":
        return client.get_run_status(run_id=args["run_id"])
    if tool_name == "get_run_results":
        return client.get_run_results(run_id=args["run_id"])
    if tool_name == "analyze_file":
        return client.analyze_file(
            s3_key=args.get("s3_key"),
            inline_data=args.get("inline_data"),
            file_type=args.get("file_type", "auto"),
        )

    raise ValueError(f"Unknown tool: {tool_name}")


# Tools that emit notifications/progress instead of a single sync result.
_STREAMING_TOOLS = {"biomate_session", "run_workflow"}


def is_streaming_call(tool_name: str, tool_args: Dict[str, Any]) -> bool:
    if tool_name == "biomate_session":
        return bool(tool_args.get("stream", True))
    if tool_name == "run_workflow":
        return bool(tool_args.get("stream", False))
    return False


# ──────────────────────────────────────────────────────────────────────────────
# JSON-RPC 2.0 / MCP protocol handling
# ──────────────────────────────────────────────────────────────────────────────

def make_response(req_id: Any, result: Any) -> Dict[str, Any]:
    return {"jsonrpc": "2.0", "id": req_id, "result": result}

def make_error(req_id: Any, code: int, message: str, data: Any = None) -> Dict[str, Any]:
    error: Dict[str, Any] = {"code": code, "message": message}
    if data is not None:
        error["data"] = data
    return {"jsonrpc": "2.0", "id": req_id, "error": error}

def send(obj: Dict[str, Any]) -> None:
    """Thread-safe stdout write — SessionRunner threads emit notifications via this."""
    line = json.dumps(obj, separators=(",", ":"))
    with _send_lock:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()

def handle_request(client: BioMateClient, msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Handle one JSON-RPC message. Returns response or None for notifications."""
    method = msg.get("method", "")
    req_id = msg.get("id")  # None for notifications
    params = msg.get("params", {}) or {}

    log.debug(f"← {method} id={req_id}")

    # ── Lifecycle ─────────────────────────────────────────────────────────────
    if method == "initialize":
        # Capture client capabilities so we know if the host supports sampling.
        client_caps = params.get("capabilities", {}) or {}
        _client_supports_sampling = bool(client_caps.get("sampling"))
        return make_response(req_id, {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {
                "tools": {"listChanged": False},
                # Declare sampling support so hosts that support it can send
                # sampling/createMessage requests back for disambiguation.
                # Actual use: search_workflow asks the host LLM to choose
                # between ambiguous workflow matches when 2+ results are close.
                "sampling": {},
            },
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
        })

    if method == "notifications/initialized":
        # Fire-and-forget notification from client
        return None

    if method == "ping":
        return make_response(req_id, {})

    # ── Tools ─────────────────────────────────────────────────────────────────
    if method == "tools/list":
        return make_response(req_id, {"tools": TOOLS})

    if method == "tools/call":
        tool_name = params.get("name", "")
        tool_args = params.get("arguments", {}) or {}
        meta = params.get("_meta", {}) or {}
        progress_token = meta.get("progressToken")

        # Streaming tools: spawn a worker that emits notifications/progress and
        # sends the final tools/call response itself. Main loop returns None.
        if is_streaming_call(tool_name, tool_args):
            runner = SessionRunner(client, req_id, tool_name, tool_args, progress_token)
            runner.start()
            return None

        try:
            result = dispatch_tool(client, tool_name, tool_args)
            content_text = json.dumps(result, indent=2, default=str)
            return make_response(req_id, {
                "content": [{"type": "text", "text": content_text}],
                "isError": "error" in result if isinstance(result, dict) else False,
            })
        except ValueError as exc:
            return make_error(req_id, -32601, str(exc))
        except Exception as exc:
            log.exception(f"Tool call error: {tool_name}")
            return make_error(req_id, -32603, "Internal tool error", str(exc))

    # ── Resources / Prompts (not implemented, return capability not found) ────
    if method in ("resources/list", "resources/read", "prompts/list", "prompts/get"):
        return make_error(req_id, -32601, f"Method not implemented: {method}")

    # ── Unknown method ────────────────────────────────────────────────────────
    if req_id is not None:
        return make_error(req_id, -32601, f"Method not found: {method}")

    return None  # Unknown notification — ignore


# ──────────────────────────────────────────────────────────────────────────────
# Main loop (stdio transport)
# ──────────────────────────────────────────────────────────────────────────────

def run_server() -> None:
    client = BioMateClient(BIOMATE_API_URL, BIOMATE_API_KEY)
    warnings.warn(
        "backend/lib/mcp/biomate_mcp_server.py (v1.0.0) is DEPRECATED and "
        "unmaintained. Use the connector repo's mcp/biomate_mcp_server.py "
        "(v2.0.0) — install via `npx @biomate/connect`.",
        DeprecationWarning,
        stacklevel=2,
    )
    log.warning(
        f"BioMate MCP Server {SERVER_VERSION} starting (api={BIOMATE_API_URL}) "
        "— DEPRECATED: this v1.0.0 server is superseded by the biomate-connector "
        "repo (v2.0.0). See module docstring."
    )

    for raw_line in sys.stdin:
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        try:
            msg = json.loads(raw_line)
        except json.JSONDecodeError as exc:
            send(make_error(None, -32700, f"Parse error: {exc}"))
            continue

        response = handle_request(client, msg)
        if response is not None:
            log.debug(f"→ {json.dumps(response)[:120]}")
            send(response)


if __name__ == "__main__":
    run_server()
