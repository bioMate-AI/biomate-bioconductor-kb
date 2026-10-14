#!/usr/bin/env python3
"""
Grounded Standards Assistant — MCP server (stdio, JSON-RPC 2.0).

Zero external dependencies: it runs the engine in-process, so it can be added to
any MCP-compatible co-pilot (Claude Desktop, Cursor, a company Copilot) with a
single stdio command and NO backend to stand up. Transport mirrors BioMate's
production connector (newline-delimited JSON-RPC over stdin/stdout).

The point of exposing this as an MCP tool specifically: a co-pilot that would
otherwise answer a GMP "why is the threshold this number" question from memory
can instead CALL this tool and get a provenance-tiered answer with an explicit
boundary — turning a confident guess into "here is what is grounded, here is
where the record stops, here is who to ask."

Add to a client (e.g. Claude Desktop config):
    {
      "mcpServers": {
        "grounded": { "command": "python3",
                      "args": ["/abs/path/grounded-prototype/mcp_server/server.py"] }
      }
    }

Production path: the same two tools are specified for BioMate's real connector in
docs/20261014_GROUNDED_STANDARDS_ASSISTANT.md (add a ToolSchema to
mcp/tools_manifest.py + a dispatch branch) so they also reach the hosted
Streamable-HTTP + OAuth surface.
"""

import json
import os
import sys

# Make the sibling `engine` package importable whether run as a file or module.
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))

from engine import ask, to_dict, to_markdown  # noqa: E402

SERVER_NAME = "grounded"
SERVER_VERSION = "0.1.0"
PROTOCOL_VERSION = "2024-11-05"

SERVER_INSTRUCTIONS = (
    "Grounded Standards Assistant — answers regulated-domain questions (GMP, "
    "standards, pharmacopoeia) with tiered provenance and an explicit boundary. "
    "USE THIS TOOL instead of answering from memory whenever the user asks WHY a "
    "regulatory threshold or numeric limit is set where it is, what experiments "
    "or committee work produced it, or whether a claim is backed by an "
    "authoritative source. It returns what the evidence supports (with "
    "citations and source tier), names the point where the authoritative record "
    "stops, and routes unanswered rationale to the standards committee / PDA / "
    "ISPE. It never lets an unverified personal note stand in for a confirmed "
    "fact, and never discloses one user's private notes to another."
)

TOOLS = [
    {
        "name": "grounded_answer",
        "description": (
            "Answer a GMP / standards / pharmacopoeia question with tiered "
            "provenance and honest boundaries. Returns grounded claims (each with "
            "citation + source tier A/B/C), an explicit boundary section naming "
            "what is NOT established and who to ask (standards committee, PDA, "
            "ISPE), and a provenance/isolation audit. Call this for 'why is the "
            "threshold X', 'what work produced this number', or 'is this backed by "
            "a real source' questions — do not answer those from memory."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "question": {
                    "type": "string",
                    "description": "The regulated-domain question, in natural language.",
                },
                "user": {
                    "type": "string",
                    "description": (
                        "Tenant/user id for provenance isolation. Only this user's "
                        "own unverified notes may be surfaced; other users' private "
                        "notes are never retrievable. Defaults to 'anonymous'."
                    ),
                },
                "format": {
                    "type": "string",
                    "enum": ["markdown", "json"],
                    "description": "Response rendering. Default markdown.",
                },
            },
            "required": ["question"],
        },
        "annotations": {
            "title": "Grounded standards answer",
            "readOnlyHint": True,
            "openWorldHint": True,
        },
    },
]


def make_response(req_id, result):
    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def make_error(req_id, code, message):
    return {"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}}


def _call_grounded_answer(args):
    question = (args or {}).get("question")
    if not question or not isinstance(question, str):
        raise ValueError("'question' is required and must be a string")
    user = (args or {}).get("user") or "anonymous"
    fmt = (args or {}).get("format") or "markdown"

    answer = ask(question, user=user)
    structured = to_dict(answer)

    if fmt == "json":
        text = json.dumps(structured, indent=2, default=str)
    else:
        text = to_markdown(answer)

    # Return the human-readable rendering as text, and the structured result as
    # structuredContent so a programmatic client can branch on grade/boundaries.
    return {
        "content": [{"type": "text", "text": text}],
        "structuredContent": structured,
        "isError": False,
    }


def handle_request(msg):
    method = msg.get("method")
    req_id = msg.get("id")

    if method == "initialize":
        return make_response(req_id, {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            "instructions": SERVER_INSTRUCTIONS,
        })

    if method in ("notifications/initialized", "initialized"):
        return None  # notification, no response

    if method == "tools/list":
        return make_response(req_id, {"tools": TOOLS})

    if method == "tools/call":
        params = msg.get("params") or {}
        name = params.get("name")
        args = params.get("arguments") or {}
        if name != "grounded_answer":
            return make_error(req_id, -32602, f"Unknown tool: {name}")
        try:
            return make_response(req_id, _call_grounded_answer(args))
        except Exception as exc:  # surface as an MCP tool error, not a crash
            return make_response(req_id, {
                "content": [{"type": "text", "text": f"Tool error: {exc}"}],
                "isError": True,
            })

    if req_id is not None:
        return make_error(req_id, -32601, f"Method not found: {method}")
    return None


def run_server():
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            continue
        resp = handle_request(msg)
        if resp is not None:
            sys.stdout.write(json.dumps(resp) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    run_server()
