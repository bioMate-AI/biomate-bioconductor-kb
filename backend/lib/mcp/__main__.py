"""
Redirect shim — DEPRECATED.

Forwards `python -m backend.lib.mcp` to backend/mcp/biomate_mcp_server.py
(v1.1.0, 8 tools). Both in-repo servers are deprecated and unmaintained; the
maintained MCP server is in the separate biomate-connector repo (v2.0.0,
`npx @biomate/connect`). This shim is kept only so the documented entry point
does not hard-break for historical configs.
"""
import subprocess
import sys
from pathlib import Path

real_server = Path(__file__).resolve().parents[3] / "mcp" / "biomate_mcp_server.py"

if not real_server.exists():
    print(f"[biomate-mcp] ERROR: real server not found at {real_server}", file=sys.stderr)
    print(f"[biomate-mcp] Expected: {real_server}", file=sys.stderr)
    sys.exit(1)

subprocess.run(
    [sys.executable, str(real_server)],
    stdin=sys.stdin,
    stdout=sys.stdout,
    stderr=sys.stderr,
)
