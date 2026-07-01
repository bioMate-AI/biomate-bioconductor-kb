#!/usr/bin/env python3
"""
BioMate MCP Server
==================
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
from typing import Any, Dict, List, Optional

import requests

# ──────────────────────────────────────────────────────────────────────────────
# Config
# ──────────────────────────────────────────────────────────────────────────────

BIOMATE_API_URL = os.environ.get("BIOMATE_API_URL", "http://localhost:5000")
BIOMATE_API_KEY = os.environ.get("BIOMATE_API_KEY", "")
SERVER_NAME = "biomate"
SERVER_VERSION = "1.0.0"
PROTOCOL_VERSION = "2024-11-05"

logging.basicConfig(
    stream=sys.stderr,
    level=logging.DEBUG if os.environ.get("MCP_DEBUG") else logging.WARNING,
    format="[BioMate MCP] %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)

# ──────────────────────────────────────────────────────────────────────────────
# Tool definitions (MCP schema)
# ──────────────────────────────────────────────────────────────────────────────

# Keep in sync with:
#   frontend/server/routes.ts  OPEN_CLAW_TOOLS
#   backend/lib/integrations/slack_bot.py
#   backend/lib/integrations/wechat_bot.py
# Doc: docs/20260412_BIOMATE_TOOLS_CAPABILITY_MAP.md
TOOLS: List[Dict[str, Any]] = [
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


# ──────────────────────────────────────────────────────────────────────────────
# Tool dispatcher
# ──────────────────────────────────────────────────────────────────────────────

def dispatch_tool(client: BioMateClient, tool_name: str, args: Dict[str, Any]) -> Any:
    """Execute a tool call and return JSON-serializable result."""
    if tool_name == "search_workflow":
        return client.search_workflow(
            query=args["query"],
            limit=int(args.get("limit", 5)),
        )

    elif tool_name == "run_workflow":
        return client.run_workflow(
            workflow_id=args["workflow_id"],
            params=args.get("params", {}),
            session_message=args.get("session_message"),
        )

    elif tool_name == "get_run_status":
        return client.get_run_status(run_id=args["run_id"])

    elif tool_name == "get_run_results":
        return client.get_run_results(run_id=args["run_id"])

    elif tool_name == "query_database":
        return client.query_database(
            database=args["database"],
            query=args["query"],
        )

    elif tool_name == "analyze_file":
        return client.analyze_file(
            s3_key=args.get("s3_key"),
            inline_data=args.get("inline_data"),
            file_type=args.get("file_type", "auto"),
        )

    elif tool_name == "cancel_run":
        return client.cancel_run(run_id=args["run_id"])

    elif tool_name == "list_runs":
        return client.list_runs(
            limit=int(args.get("limit", 10)),
            status=args.get("status", "all"),
        )

    elif tool_name == "analyze_results":
        return client.analyze_results(
            run_id=args["run_id"],
            question=args.get("question", "Summarize the key findings and scientific interpretation."),
        )

    elif tool_name == "explain_error":
        return client.explain_error(
            run_id=args["run_id"],
            error_log=args.get("error_log", ""),
        )

    elif tool_name == "biomate_session":
        return client.biomate_session(
            goal=args["goal"],
            inputs=args.get("inputs"),
        )

    else:
        raise ValueError(f"Unknown tool: {tool_name}")


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
    line = json.dumps(obj, separators=(",", ":"))
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
    log.warning(f"BioMate MCP Server {SERVER_VERSION} starting (api={BIOMATE_API_URL})")

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
