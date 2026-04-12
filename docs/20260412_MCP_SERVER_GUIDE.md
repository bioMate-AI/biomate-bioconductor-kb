# BioMate MCP Server — Installation & Usage Guide

## What is MCP?

The Model Context Protocol (MCP) is an open standard that allows AI clients
(Claude Desktop, Cursor, Cline, etc.) to use external tools provided by a server.
BioMate's MCP server exposes scientific workflow capabilities so any MCP-compatible
AI can invoke BioMate workflows, search databases, and retrieve results.

## Available Tools

| Tool | Description |
|------|-------------|
| `search_workflow` | Search the BioMate workflow catalog by natural language query |
| `run_workflow` | Execute a workflow on AWS Batch, returns a `run_id` |
| `get_run_status` | Poll status of a running workflow (`pending → running → completed`) |
| `get_run_results` | Retrieve output files from a completed run |
| `query_database` | Query UniProt, PDB, NCBI Gene, dbSNP, KEGG, ChEBI, HPO, STRING |
| `analyze_file` | Lightweight QC on FASTQ, CSV, VCF, FASTA, BAM |

## Installation

### Prerequisites
- Python 3.11+
- `requests` library: `pip install requests`
- BioMate server running (local or remote)
- BioMate API key (get from Settings → API Keys)

### Server file
```
backend/lib/mcp/biomate_mcp_server.py
```

### Environment variables
```bash
export BIOMATE_API_URL="https://app.biomate.ai"    # or http://localhost:5000 for dev
export BIOMATE_API_KEY="your-api-key-here"
# Optional:
export MCP_DEBUG=1   # Enable verbose logging to stderr
```

## Configuration: Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS)
or `%APPDATA%\Claude\claude_desktop_config.json` (Windows):

```json
{
  "mcpServers": {
    "biomate": {
      "command": "python",
      "args": ["/path/to/biomate/backend/lib/mcp/biomate_mcp_server.py"],
      "env": {
        "BIOMATE_API_URL": "https://app.biomate.ai",
        "BIOMATE_API_KEY": "your-api-key-here"
      }
    }
  }
}
```

Restart Claude Desktop. The BioMate tools will appear in the tool picker (hammer icon).

## Configuration: Cursor / VS Code (Cline)

```json
// .cursor/mcp.json  or  .vscode/cline_mcp_settings.json
{
  "mcpServers": {
    "biomate": {
      "command": "python",
      "args": ["backend/lib/mcp/biomate_mcp_server.py"],
      "env": {
        "BIOMATE_API_URL": "http://localhost:5000",
        "BIOMATE_API_KEY": "your-api-key"
      }
    }
  }
}
```

## Configuration: SSE Transport (Remote/Web)

The stdio transport is for local use. For remote access (web-based MCP clients),
BioMate can expose the MCP server over SSE by wrapping it in an HTTP endpoint.

Add to `backend/lib/mcp/biomate_mcp_sse_server.py`:
```python
# FastAPI SSE wrapper — serves MCP over HTTP POST + SSE
from fastapi import FastAPI
app = FastAPI()
# ... (SSE transport implementation)
```

Or use `mcp` Python SDK when available: `pip install mcp`

## Example Usage

### In Claude Desktop

With BioMate tools connected, Claude can:

```
User: Run ADMET screening on these compounds: aspirin, ibuprofen, naproxen

Claude: I'll use BioMate to run ADMET screening.
[calls search_workflow("ADMET screening SMILES")]
→ Returns: predict_admet_properties workflow

[calls run_workflow("predict_admet_properties", {"smiles_input": "..."})]
→ Returns: run_id = "abc123"

[calls get_run_status("abc123")] × polls until completed

[calls get_run_results("abc123")]
→ Returns: admet_results.csv with hERG, DILI, Caco-2, BBB, solubility, Ames scores

Claude: Here are the ADMET results for your three compounds:
| Compound | hERG IC50 | DILI Risk | Caco-2 | BBB |
|----------|-----------|-----------|--------|-----|
| Aspirin  | 18.2 µM   | Low       | +      | -   |
...
```

### Direct CLI test

```bash
# Test the server interactively (send JSON-RPC over stdin)
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | \
  python backend/lib/mcp/biomate_mcp_server.py

# List tools
echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | \
  python backend/lib/mcp/biomate_mcp_server.py

# Search workflows
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_workflow","arguments":{"query":"variant calling FASTQ"}}}' | \
  python backend/lib/mcp/biomate_mcp_server.py
```

## Protocol Details

The server implements MCP 2024-11-05 over stdio transport (JSON-RPC 2.0, newline-delimited):

| Method | Implemented | Notes |
|--------|-------------|-------|
| `initialize` | ✅ | Returns protocol version + capabilities |
| `notifications/initialized` | ✅ | No-op (acknowledgement) |
| `ping` | ✅ | Returns empty result |
| `tools/list` | ✅ | Returns 6 tools |
| `tools/call` | ✅ | Dispatches to BioMate API |
| `resources/list` | ❌ | Not implemented |
| `prompts/list` | ❌ | Not implemented |

## Security

- All tool calls go through BioMate's authentication layer (API key required)
- Rate limiting and quota enforcement apply identically to direct API calls
- Tool call content is validated before passing to BioMate
- No filesystem access; no code execution on the MCP server itself

## Troubleshooting

**"Error connecting to BioMate"**: Check `BIOMATE_API_URL` is reachable and API key is valid.
```bash
curl -H "Authorization: Bearer $BIOMATE_API_KEY" $BIOMATE_API_URL/api/health
```

**Tools not appearing in Claude Desktop**: Restart Claude Desktop after editing `claude_desktop_config.json`. Check stderr output with `MCP_DEBUG=1`.

**Slow tool calls**: The `run_workflow` tool starts an async job — it returns a `run_id` immediately. The AI must call `get_run_status` repeatedly until status is `completed` (usually 2–15 minutes for AWS Batch workflows).
