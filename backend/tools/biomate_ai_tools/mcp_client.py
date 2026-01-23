#!/usr/bin/env python3
"""
Biomate MCP Client - Direct interface to MCP servers
For immediate use of AlphaFold, Chai-1, and Boltz tools.
"""

import json
import subprocess
import os
from typing import Any, Dict, Optional
from pathlib import Path

MCP_SERVERS = {
    "alphafold": {
        "command": ["node", str(Path(__file__).parent.parent.parent.parent / "auto_update/mcp_servers/AlphaFold-MCP-Server/build/index.js")],
        "ready": True,
    },
    "chai1": {
        "command": ["python", str(Path(__file__).parent.parent.parent.parent / "auto_update/mcp_servers/chai1_mcp_server.py")],
        "ready": True,
        "requires_gpu": True,
    },
}


def call_mcp_tool(server: str, tool_name: str, arguments: Dict[str, Any], timeout: int = 60) -> Dict[str, Any]:
    """
    Call an MCP server tool directly.

    Args:
        server: Server name ('alphafold', 'chai1')
        tool_name: Tool to call (e.g., 'get_structure', 'chai1_predict')
        arguments: Tool arguments
        timeout: Timeout in seconds

    Returns:
        Tool result or error dict
    """
    if server not in MCP_SERVERS:
        return {"error": f"Unknown server: {server}. Available: {list(MCP_SERVERS.keys())}"}

    server_config = MCP_SERVERS[server]

    # Build JSON-RPC request
    request = {
        "jsonrpc": "2.0",
        "method": "tools/call",
        "params": {
            "name": tool_name,
            "arguments": arguments
        },
        "id": 1
    }

    try:
        # Call MCP server
        process = subprocess.Popen(
            server_config["command"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        stdout, stderr = process.communicate(
            input=json.dumps(request).encode(),
            timeout=timeout
        )

        # Parse response - check both stdout and stderr
        output = stdout.decode() + stderr.decode()
        lines = output.strip().split('\n')

        for line in lines:
            line = line.strip()
            if line.startswith('{') and '"jsonrpc"' in line:
                try:
                    response = json.loads(line)
                    if "result" in response:
                        content = response["result"].get("content", [])
                        if content and "text" in content[0]:
                            try:
                                return json.loads(content[0]["text"])
                            except json.JSONDecodeError:
                                return {"text": content[0]["text"]}
                        return response["result"]
                    elif "error" in response:
                        return {"error": response["error"]}
                except json.JSONDecodeError:
                    continue

        return {"error": "No valid response", "output": output[:500]}

    except subprocess.TimeoutExpired:
        process.kill()
        return {"error": f"Timeout after {timeout}s"}
    except Exception as e:
        return {"error": str(e)}


# =============================================================================
# ALPHAFOLD FUNCTIONS
# =============================================================================

def alphafold_get_structure(uniprot_id: str, format: str = "json") -> Dict[str, Any]:
    """Get AlphaFold structure by UniProt ID."""
    return call_mcp_tool("alphafold", "get_structure", {
        "uniprotId": uniprot_id,
        "format": format
    })


def alphafold_check_available(uniprot_id: str) -> Dict[str, Any]:
    """Check if AlphaFold structure is available."""
    return call_mcp_tool("alphafold", "check_availability", {
        "uniprotId": uniprot_id
    })


def alphafold_get_confidence(uniprot_id: str) -> Dict[str, Any]:
    """Get confidence scores for AlphaFold prediction."""
    return call_mcp_tool("alphafold", "get_confidence_scores", {
        "uniprotId": uniprot_id
    })


def alphafold_api_status() -> Dict[str, Any]:
    """Get AlphaFold API status."""
    return call_mcp_tool("alphafold", "get_api_status", {})


# =============================================================================
# QUICK TEST
# =============================================================================

if __name__ == "__main__":
    print("Testing AlphaFold MCP...")

    # Test API status
    status = alphafold_api_status()
    print(f"API Status: {status.get('apiStatus', 'unknown')}")
    print(f"Total structures: {status.get('databaseStats', {}).get('totalStructures', 'unknown')}")

    # Test availability check
    print("\nChecking P00533 (EGFR)...")
    avail = alphafold_check_available("P00533")
    print(f"Available: {avail.get('available', 'unknown')}")
    print(f"Versions: {avail.get('structureCount', 'unknown')}")
