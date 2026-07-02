#!/usr/bin/env python3
"""
BioMate MCP Server — stdio transport (MCP protocol 2024-11-05)  —  DEPRECATED (v1.1.0)

.. deprecated:: 1.1.0
    This in-repo stdio server is **superseded** and no longer maintained. The
    current, maintained MCP server lives in the separate connector repository:

        github.com/bioMate-AI/biomate-connector  →  mcp/biomate_mcp_server.py (v2.0.0)

    That server is schema-driven from a single ``tools_manifest.py`` (17 tools
    with Directory-compliant ``title`` + ``annotations``), ships OAuth 2.1 +
    PKCE, and is what is published as ``@biomate/connect`` and submitted to the
    Anthropic Claude Directory.

    This file (8 tools, no annotations, hardcoded tool list) is kept only so
    historical Claude Desktop / Claude Code configs do not hard-break. Do not add
    features here — make changes in the connector repo. Migrate any local config
    to ``npx @biomate/connect`` before this is removed.

    (The older sibling ``backend/lib/mcp/biomate_mcp_server.py`` v1.0.0 is also
    deprecated.)

Exposes BioMate's AI assistant and workflow capabilities to Claude Code CLI
and any other MCP-compatible client. Reads JSON-RPC 2.0 messages from stdin,
writes responses to stdout.

Usage:
    python3 biomate_mcp_server.py

Environment variables:
    BIOMATE_URL         Base URL for the BioMate frontend server
                        (default: http://localhost:5000)
    BIOMATE_API_TOKEN   Bearer token. Generate one at BioMate → Settings → API Keys,
                        or copy the JWT from a browser dev-tools session.
    BIOMATE_MCP_DEBUG   Set to '1' to emit debug logs to stderr.

Add to Claude Code:
    claude mcp add biomate -- python3 /path/to/biomate_mcp_server.py

Then from Claude Code you can say:
    "Ask BioMate to run WGS germline variant calling for sample SRR1518169"
    "Search BioMate for RNA-seq differential expression workflows"
    "What's the status of my last workflow run?"
"""

import json
import os
import sys
import sqlite3
import time
import warnings
from pathlib import Path

import requests

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
BIOMATE_URL = os.environ.get("BIOMATE_URL", "http://localhost:5000").rstrip("/")
BIOMATE_TOKEN = os.environ.get("BIOMATE_API_TOKEN", "")
DB_PATH = Path(__file__).resolve().parents[1] / "galaxy_ai_tools.db"
DEBUG = os.environ.get("BIOMATE_MCP_DEBUG", "") == "1"

MCP_PROTOCOL_VERSION = "2024-11-05"
SERVER_INFO = {"name": "biomate", "version": "1.1.0"}


def _log(msg: str) -> None:
    if DEBUG:
        print(f"[biomate-mcp] {msg}", file=sys.stderr, flush=True)


def _auth_headers() -> dict:
    h = {"Content-Type": "application/json"}
    if BIOMATE_TOKEN:
        h["Authorization"] = f"Bearer {BIOMATE_TOKEN}"
    return h


def _api(method: str, path: str, **kwargs) -> requests.Response:
    url = f"{BIOMATE_URL}{path}"
    _log(f"{method} {url}")
    return requests.request(method, url, headers=_auth_headers(), timeout=30, **kwargs)


# ---------------------------------------------------------------------------
# Tool: chat
# ---------------------------------------------------------------------------

def chat(
    message: str,
    session_id: str = "",
    previous_messages: list[dict] | None = None,
    auto_execute: bool = False,
) -> dict:
    """
    Send a natural-language message to the BioMate AI assistant via SSE stream.

    Consumes the full Server-Sent Events stream and returns:
    - The assistant's text response
    - Any workflow generated (workflowDefinition)
    - A run_id if auto_execute=True and BioMate submitted a workflow run

    This is the primary interface. It handles intent classification, workflow
    selection, parameter auto-filling, prerequisite validation, and optionally
    execution — all in one call.
    """
    body = {
        "message": message,
        "context": {
            "previousMessages": previous_messages or [],
        },
    }
    if session_id:
        body["context"]["sessionId"] = session_id

    try:
        resp = requests.post(
            f"{BIOMATE_URL}/api/chat/stream",
            headers=_auth_headers(),
            json=body,
            stream=True,
            timeout=120,
        )
        if resp.status_code != 200:
            return {"error": f"HTTP {resp.status_code}", "detail": resp.text[:300]}
    except requests.RequestException as e:
        return {"error": f"Connection error: {e}"}

    # Parse SSE stream
    text_chunks: list[str] = []
    workflow_definition: dict | None = None
    run_id: str | None = None
    event_type = ""

    for raw in resp.iter_lines():
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8")
        if raw.startswith("event:"):
            event_type = raw[len("event:"):].strip()
        elif raw.startswith("data:"):
            data_str = raw[len("data:"):].strip()
            try:
                data = json.loads(data_str)
            except json.JSONDecodeError:
                continue

            if event_type == "delta":
                text_chunks.append(data.get("text", ""))

            elif event_type == "tool_event":
                # Workflow generation events carry the workflowDefinition
                if data.get("type") in ("workflow_generated", "nextflow_workflow"):
                    workflow_definition = data.get("workflowDefinition") or data.get("payload")
                # Execution started event carries a runId
                if data.get("type") == "execution_started":
                    run_id = data.get("runId") or data.get("run_id")

            elif event_type == "done":
                # Final done event has the complete message + any generated workflow
                if not workflow_definition:
                    gw = data.get("generatedWorkflow") or data.get("workflowDefinition")
                    if gw:
                        workflow_definition = gw

    full_text = "".join(text_chunks)

    result: dict = {"response": full_text}

    if workflow_definition:
        result["workflow_generated"] = True
        result["workflow_name"] = workflow_definition.get("name") or workflow_definition.get("annotation", "")
        result["workflow_params"] = _extract_params(workflow_definition)

        if auto_execute and not run_id:
            _log(f"auto_execute: submitting workflow {result['workflow_name']}")
            exec_result = _execute_workflow_definition(workflow_definition)
            run_id = exec_result.get("run_id")
            result["execution"] = exec_result

    if run_id:
        result["run_id"] = run_id
        result["hint"] = f"Use get_run_status('{run_id}') to poll progress."

    return result


def _extract_params(wf_def: dict) -> dict:
    """Pull out the user-facing parameters from a workflowDefinition object."""
    params = {}
    for p in (wf_def.get("required_params") or []):
        params[p.get("name", p.get("id", ""))] = p.get("value") or p.get("default")
    for p in (wf_def.get("optional_params") or []):
        params[p.get("name", p.get("id", ""))] = p.get("value") or p.get("default")
    # Also check generated_parameters flat dict
    gp = wf_def.get("generated_parameters", {})
    if isinstance(gp, dict):
        params.update(gp)
    return params


def _execute_workflow_definition(wf_def: dict) -> dict:
    """Submit a workflowDefinition to /api/workflows/execute. Returns {run_id, status}."""
    resp = _api("POST", "/api/workflows/execute", json={"workflowDefinition": wf_def})
    if resp.status_code == 200:
        data = resp.json()
        return {
            "run_id": data.get("runId") or data.get("id"),
            "status": data.get("status", "submitted"),
        }
    return {"error": f"HTTP {resp.status_code}", "detail": resp.text[:300]}


# ---------------------------------------------------------------------------
# Tool: search_workflows
# ---------------------------------------------------------------------------

def search_workflows(query: str, limit: int = 10) -> list[dict]:
    """Full-text search the BioMate workflow registry (direct SQLite FTS query)."""
    try:
        conn = sqlite3.connect(str(DB_PATH))
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        try:
            cur.execute(
                """
                SELECT w.id, w.name, w.domain, w.description, w.filename
                FROM workflows_fts fts
                JOIN workflows w ON fts.rowid = w.id
                WHERE workflows_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """,
                (query, limit),
            )
        except sqlite3.OperationalError:
            cur.execute(
                "SELECT id, name, domain, description, filename FROM workflows "
                "WHERE name LIKE ? OR description LIKE ? LIMIT ?",
                (f"%{query}%", f"%{query}%", limit),
            )
        rows = cur.fetchall()
        conn.close()
        return [
            {
                "id": r["id"],
                "name": r["name"],
                "domain": r["domain"] or "unknown",
                "description": (r["description"] or "")[:200],
                "filename": r["filename"],
            }
            for r in rows
        ]
    except Exception as e:
        return [{"error": str(e)}]


# ---------------------------------------------------------------------------
# Tool: get_workflow_params
# ---------------------------------------------------------------------------

def get_workflow_params(workflow_name: str) -> dict:
    """
    Return the parameter schema for a workflow by querying BioMate's backend.
    This shows what parameters a workflow accepts, their types, defaults, and
    which are required — useful before calling chat() with specific params.
    """
    # Find the workflow in the DB
    try:
        conn = sqlite3.connect(str(DB_PATH))
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        cur.execute(
            "SELECT id, name, filename FROM workflows WHERE name LIKE ? LIMIT 3",
            (f"%{workflow_name}%",),
        )
        rows = cur.fetchall()
        conn.close()
    except Exception as e:
        return {"error": str(e)}

    if not rows:
        return {"error": f"No workflow found matching '{workflow_name}'"}

    # Try to read nextflow_schema.json from the workflow directory
    backend_root = Path(__file__).resolve().parents[1]
    results = []
    for row in rows:
        filename = row["filename"]
        # Resolve file path using the same logic as _find_nf_file in ai_assistant.py
        candidates = [
            backend_root / "biomni_workflows" / "nextflow_nfcore" / filename,
            backend_root / "biomni_workflows" / filename,
            backend_root / filename,
        ]
        nf_path = next((c for c in candidates if c.exists()), None)
        schema: dict = {}
        if nf_path:
            schema_path = nf_path.parent / "nextflow_schema.json"
            if schema_path.exists():
                try:
                    raw = json.loads(schema_path.read_text())
                    defs = raw.get("$defs") or raw.get("definitions") or {}
                    params = {}
                    for group_name, group in defs.items():
                        if isinstance(group, dict) and "properties" in group:
                            for pname, pdef in group["properties"].items():
                                if pdef.get("hidden"):
                                    continue
                                params[pname] = {
                                    "description": pdef.get("description", ""),
                                    "type": pdef.get("type", "string"),
                                    "default": pdef.get("default"),
                                    "enum": pdef.get("enum"),
                                    "required": pname in group.get("required", []),
                                    "group": group.get("title", group_name),
                                }
                    schema = {"source": "nextflow_schema.json", "params": params}
                except Exception as e:
                    schema = {"source": "nextflow_schema.json", "error": str(e)}
            else:
                # Fall back: parse params.X = Y lines from main.nf
                import re
                try:
                    text = nf_path.read_text(encoding="utf-8", errors="replace")
                    params = {}
                    for m in re.finditer(r"^\s*params\.(\w+)\s*=\s*(.+?)(?:\s*//.*)?$", text, re.MULTILINE):
                        name, raw_val = m.group(1), m.group(2).strip().strip("'\"")
                        params[name] = {"default": None if raw_val == "null" else raw_val, "required": raw_val == "null"}
                    schema = {"source": "main.nf (parsed)", "params": params}
                except Exception as e:
                    schema = {"source": "main.nf (parsed)", "error": str(e)}

        results.append({
            "id": row["id"],
            "name": row["name"],
            "filename": filename,
            **schema,
        })

    return {"matches": results}


# ---------------------------------------------------------------------------
# Tool: list_runs
# ---------------------------------------------------------------------------

def list_runs(limit: int = 20) -> list[dict]:
    """List recent workflow runs for the authenticated user."""
    resp = _api("GET", f"/api/invocations?limit={limit}")
    if resp.status_code == 200:
        runs = resp.json()
        if isinstance(runs, list):
            return [
                {
                    "run_id": r.get("id"),
                    "workflow_name": r.get("workflowName") or (r.get("workflowDefinition") or {}).get("name"),
                    "status": r.get("status"),
                    "created_at": r.get("createdAt"),
                    "updated_at": r.get("updatedAt"),
                }
                for r in runs
            ]
    return [{"error": f"HTTP {resp.status_code}"}]


# ---------------------------------------------------------------------------
# Tool: get_run_status
# ---------------------------------------------------------------------------

def get_run_status(run_id: str) -> dict:
    """Poll the status of a workflow run."""
    # Try Nextflow-specific status endpoint first (richer)
    resp = _api("GET", f"/api/invocations/{run_id}/nextflow/status")
    if resp.status_code == 200:
        data = resp.json()
        return {
            "run_id": run_id,
            "status": data.get("status", "unknown"),
            "progress": data.get("progress", {}),
            "nextflow_run_id": data.get("nextflowRunId"),
            "started_at": data.get("startedAt"),
            "updated_at": data.get("updatedAt"),
        }
    # Generic invocation fallback
    resp2 = _api("GET", f"/api/invocations/{run_id}")
    if resp2.status_code == 200:
        data = resp2.json()
        wf_def = data.get("workflowDefinition") or {}
        return {
            "run_id": run_id,
            "status": data.get("status", "unknown"),
            "workflow_name": data.get("workflowName") or wf_def.get("name"),
            "created_at": data.get("createdAt"),
        }
    return {"error": f"HTTP {resp.status_code}", "run_id": run_id}


# ---------------------------------------------------------------------------
# Tool: get_output_files
# ---------------------------------------------------------------------------

def get_output_files(run_id: str) -> list[dict]:
    """List output files produced by a completed workflow run."""
    resp = _api("GET", f"/api/invocations/{run_id}/outputs")
    if resp.status_code == 200:
        outputs = resp.json()
        if isinstance(outputs, list):
            return [
                {
                    "id": o.get("id"),
                    "name": o.get("name"),
                    "file_type": o.get("fileType") or o.get("file_type"),
                    "size_bytes": o.get("fileSize") or o.get("size"),
                    "download_url": f"{BIOMATE_URL}/api/outputs/{o['id']}/download" if o.get("id") else None,
                    "preview_url": f"{BIOMATE_URL}/api/outputs/{o['id']}/preview" if o.get("id") else None,
                }
                for o in outputs
            ]
        if isinstance(outputs, dict) and "outputs" in outputs:
            return outputs["outputs"]
    return [{"error": f"HTTP {resp.status_code}"}]


# ---------------------------------------------------------------------------
# Tool: upload_file
# ---------------------------------------------------------------------------

def upload_file(local_path: str, file_type: str = "auto") -> dict:
    """Upload a local file to BioMate's dataset store for use as workflow input."""
    path = Path(local_path)
    if not path.exists():
        return {"error": f"File not found: {local_path}"}
    try:
        with path.open("rb") as f:
            resp = requests.post(
                f"{BIOMATE_URL}/api/datasets/upload",
                headers={"Authorization": f"Bearer {BIOMATE_TOKEN}"} if BIOMATE_TOKEN else {},
                files={"file": (path.name, f)},
                data={"file_type": file_type},
                timeout=120,
            )
        if resp.status_code == 200:
            data = resp.json()
            return {
                "file_id": data.get("id"),
                "name": data.get("name") or path.name,
                "file_path": data.get("file_path"),
                "file_type": data.get("file_type") or file_type,
                "size_bytes": path.stat().st_size,
                "hint": "Pass file_path as a workflow parameter value for file-type inputs.",
            }
        return {"error": f"HTTP {resp.status_code}", "detail": resp.text[:300]}
    except Exception as e:
        return {"error": str(e)}


# ---------------------------------------------------------------------------
# Tool: research_query
# ---------------------------------------------------------------------------

def research_query(question: str, max_results: int = 5) -> dict:
    """
    Ask BioMate to search scientific literature (PubMed, Semantic Scholar)
    and return a synthesised answer with citations.
    """
    resp = _api(
        "POST",
        "/api/ai_assistant/research_query",
        json={"query": question, "maxResults": max_results},
    )
    if resp.status_code == 200:
        data = resp.json()
        return {
            "answer": data.get("answer") or data.get("response", ""),
            "citations": data.get("citations", []),
            "sources": data.get("sources", []),
        }
    return {"error": f"HTTP {resp.status_code}", "detail": resp.text[:300]}


# ---------------------------------------------------------------------------
# Tool: rerun_workflow
# ---------------------------------------------------------------------------

def rerun_workflow(run_id: str) -> dict:
    """
    Resume a failed or stopped workflow run using Nextflow -resume.
    BioMate restarts from the last successful checkpoint — failed tasks are
    re-executed, completed tasks are cached.
    """
    resp = _api("POST", f"/api/workflows/runs/{run_id}/rerun", json={})
    if resp.status_code == 200:
        data = resp.json()
        new_run_id = data.get("runId") or data.get("id") or run_id
        return {
            "new_run_id": new_run_id,
            "status": data.get("status", "submitted"),
            "hint": f"Use get_run_status('{new_run_id}') to poll progress.",
        }
    return {"error": f"HTTP {resp.status_code}", "detail": resp.text[:300]}


# ---------------------------------------------------------------------------
# Tool registry
# ---------------------------------------------------------------------------

TOOLS = [
    {
        "name": "chat",
        "description": (
            "Send a natural-language message to the BioMate AI assistant. "
            "This is the primary interface — BioMate handles intent classification, "
            "workflow selection from 2,100+ bioinformatics pipelines, AI parameter "
            "auto-filling, prerequisite validation, and optionally submitting the run. "
            "Use this for: running workflows, asking scientific questions, "
            "getting workflow recommendations, and anything requiring BioMate's intelligence. "
            "Returns the AI's text response plus any generated workflow definition and run_id."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "message": {
                    "type": "string",
                    "description": (
                        "Natural-language request. Examples: "
                        "'Run WGS germline variant calling for sample SRR1518169 with GRCh38', "
                        "'Perform RNA-seq differential expression between treated vs control', "
                        "'What CRISPR screening workflows do you have?'"
                    ),
                },
                "session_id": {
                    "type": "string",
                    "description": "Optional session ID to maintain conversation continuity across turns.",
                },
                "previous_messages": {
                    "type": "array",
                    "description": "Prior conversation turns for multi-turn interactions.",
                    "items": {
                        "type": "object",
                        "properties": {
                            "role": {"type": "string", "enum": ["user", "assistant"]},
                            "content": {"type": "string"},
                        },
                    },
                },
                "auto_execute": {
                    "type": "boolean",
                    "description": (
                        "If true and BioMate generates a workflow, automatically submit it for execution. "
                        "Default false — BioMate generates the workflow plan and you decide whether to run it."
                    ),
                    "default": False,
                },
            },
            "required": ["message"],
        },
    },
    {
        "name": "search_workflows",
        "description": (
            "Search BioMate's workflow registry by keyword. Returns matching pipelines "
            "with ID, domain, and description. Use this to discover available workflows "
            "before calling chat() with a specific pipeline in mind. "
            "Covers 2,100+ workflows across genomics, drug discovery, proteomics, "
            "cryo-EM, immunology, systems biology, and more."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search terms, e.g. 'WGS germline', 'CRISPR screen', 'protein structure prediction'",
                },
                "limit": {"type": "integer", "default": 10},
            },
            "required": ["query"],
        },
    },
    {
        "name": "get_workflow_params",
        "description": (
            "Return the full parameter schema for a workflow — types, defaults, enums, "
            "required fields, and descriptions. Use this to understand what parameters "
            "a workflow accepts before crafting a chat() message with specific values."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "workflow_name": {
                    "type": "string",
                    "description": "Workflow name or partial name (e.g. 'germline', 'alphafold', 'reinvent4')",
                },
            },
            "required": ["workflow_name"],
        },
    },
    {
        "name": "list_runs",
        "description": "List recent workflow runs with their status. Useful for tracking active or recent submissions.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "limit": {"type": "integer", "description": "Max runs to return (default 20)", "default": 20},
            },
        },
    },
    {
        "name": "get_run_status",
        "description": (
            "Poll the status of a specific workflow run. "
            "Status values: pending → running → completed | failed. "
            "Returns progress metrics and the Nextflow run ID for direct log access."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "run_id": {"type": "string", "description": "UUID run identifier from chat() or list_runs()"},
            },
            "required": ["run_id"],
        },
    },
    {
        "name": "get_output_files",
        "description": (
            "List output files produced by a completed workflow run. "
            "Returns file names, types, sizes, and download/preview URLs. "
            "Call after get_run_status() shows status='completed'."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "run_id": {"type": "string"},
            },
            "required": ["run_id"],
        },
    },
    {
        "name": "upload_file",
        "description": (
            "Upload a local file to BioMate's dataset store. "
            "Returns a file_path that can be referenced in a chat() message "
            "as the input file for a workflow (e.g. 'use the file at /data/uploads/sample.fastq')."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "local_path": {
                    "type": "string",
                    "description": "Absolute path to the local file",
                },
                "file_type": {
                    "type": "string",
                    "description": "File type hint: 'fastq', 'bam', 'vcf', 'fasta', 'csv', 'auto'",
                    "default": "auto",
                },
            },
            "required": ["local_path"],
        },
    },
    {
        "name": "research_query",
        "description": (
            "Ask BioMate to search scientific literature and return a synthesised answer "
            "with citations. Covers PubMed, Semantic Scholar, and BioMate's curated corpus. "
            "Use for protocol rationale, method selection, or literature-backed parameter choices."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "question": {
                    "type": "string",
                    "description": "Scientific question, e.g. 'What is the recommended minimum coverage for WGS germline calling?'",
                },
                "max_results": {
                    "type": "integer",
                    "description": "Max citations to retrieve (default 5)",
                    "default": 5,
                },
            },
            "required": ["question"],
        },
    },
    {
        "name": "rerun_workflow",
        "description": (
            "Resume a failed or stopped workflow using Nextflow -resume. "
            "Re-executes only the failed/incomplete tasks — successful tasks are cached. "
            "Use after get_run_status() shows status='failed'."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "run_id": {"type": "string", "description": "UUID of the failed run"},
            },
            "required": ["run_id"],
        },
    },
]

TOOL_MAP = {t["name"]: t for t in TOOLS}


# ---------------------------------------------------------------------------
# JSON-RPC 2.0 / MCP dispatch
# ---------------------------------------------------------------------------

def _ok(req_id, result) -> dict:
    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def _err(req_id, code: int, message: str) -> dict:
    return {"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}}


def _call_tool(name: str, args: dict) -> dict | list:
    if name == "chat":
        return chat(
            message=args["message"],
            session_id=args.get("session_id", ""),
            previous_messages=args.get("previous_messages"),
            auto_execute=args.get("auto_execute", False),
        )
    elif name == "search_workflows":
        return search_workflows(args["query"], args.get("limit", 10))
    elif name == "get_workflow_params":
        return get_workflow_params(args["workflow_name"])
    elif name == "list_runs":
        return list_runs(args.get("limit", 20))
    elif name == "get_run_status":
        return get_run_status(args["run_id"])
    elif name == "get_output_files":
        return get_output_files(args["run_id"])
    elif name == "upload_file":
        return upload_file(args["local_path"], args.get("file_type", "auto"))
    elif name == "research_query":
        return research_query(args["question"], args.get("max_results", 5))
    elif name == "rerun_workflow":
        return rerun_workflow(args["run_id"])
    else:
        raise ValueError(f"Unknown tool: {name}")


def handle(msg: dict) -> dict | None:
    method = msg.get("method", "")
    req_id = msg.get("id")
    params = msg.get("params", {})

    if req_id is None:
        return None  # notification — no response

    if method == "initialize":
        return _ok(req_id, {
            "protocolVersion": MCP_PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": SERVER_INFO,
        })

    if method == "tools/list":
        return _ok(req_id, {"tools": TOOLS})

    if method == "tools/call":
        name = params.get("name")
        args = params.get("arguments", {})
        if name not in TOOL_MAP:
            return _err(req_id, -32601, f"Unknown tool: {name}")
        try:
            result = _call_tool(name, args)
            text = json.dumps(result, indent=2) if not isinstance(result, str) else result
            return _ok(req_id, {"content": [{"type": "text", "text": text}]})
        except Exception as e:
            _log(f"Tool error: {e}")
            return _err(req_id, -32603, f"Tool error in '{name}': {e}")

    if method == "ping":
        return _ok(req_id, {})

    return _err(req_id, -32601, f"Method not found: {method}")


# ---------------------------------------------------------------------------
# stdio event loop
# ---------------------------------------------------------------------------

def main():
    warnings.warn(
        "backend/mcp/biomate_mcp_server.py (v1.1.0) is DEPRECATED and "
        "unmaintained. Use the connector repo's mcp/biomate_mcp_server.py "
        "(v2.0.0) — install via `npx @biomate/connect`.",
        DeprecationWarning,
        stacklevel=2,
    )
    print(
        "[biomate-mcp] WARNING: this v1.1.0 server is DEPRECATED and superseded "
        "by the biomate-connector repo (v2.0.0). See module docstring / "
        "`npx @biomate/connect`.",
        file=sys.stderr,
        flush=True,
    )
    _log(f"BioMate MCP server starting. BIOMATE_URL={BIOMATE_URL}")
    for raw_line in sys.stdin:
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        try:
            msg = json.loads(raw_line)
        except json.JSONDecodeError as e:
            print(json.dumps(_err(None, -32700, f"Parse error: {e}")), flush=True)
            continue
        _log(f"→ method={msg.get('method')} id={msg.get('id')}")
        response = handle(msg)
        if response is not None:
            _log(f"← id={response.get('id')} {'result' if 'result' in response else 'error'}")
            print(json.dumps(response), flush=True)


if __name__ == "__main__":
    main()
