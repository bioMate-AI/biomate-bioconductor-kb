# 07b · Connectors, MCP & Auto-Update

**Verified 2026-08-29.**

---

## 1. Where the connector code lives

The main repo (`/Users/kky/biomate`) holds only **`.mcp.json`** — a stdio MCP client config pointing Claude Code at the **separate** connector repo:
```
command: python3   args: [/Users/kky/biomate-connector/mcp/biomate_mcp_server.py]
BIOMATE_API_URL: https://dev-public.biomate.ai   BIOMATE_API_KEY: bm_live_...
```
There is **no MCP server code in the main backend**. The main repo's `connectors/` and `docker/` dirs are lab-instrument *services* + installer marketing, not the MCP server.

## 2. The connector repo (`/Users/kky/biomate-connector`)

### MCP server — 24 tools (not 19; the memory note is stale)
Single source of truth `mcp/tools_manifest.py` (`TOOL_SCHEMAS` L86–820), loaded by `mcp/biomate_mcp_server.py:122` via `_manifest_to_mcp()`. Four tiers:

- **Tier 1 (agentic):** `biomate_session`
- **Tier 2 (workflow, 9):** `search_workflow`, `get_workflow_spec`, `run_workflow`, `watch_run`, `get_run`, `cancel_run`, `list_runs`, `get_quota`, `get_usage`
- **Tier 3 (analysis/memory, 11):** `preview_file`, `export_report`, `analyze_results`, `explain_error`, `query_database`, `resolve_accession`, `browse_data`, `fetch_public_data`, `recall_memory`, `search_literature`, `upload_file`
- **Tier 4 (local-only instruments, 3):** `list_instruments`, `get_instrument_status`, `run_instrument_protocol`

(21 cloud + 3 local.)

### Lab instruments — 13 connectors (`lab_instruments/`)
Illumina BaseSpace, Nanopore MinKNOW, CryoEM (Titan Krios / Arctica / cryoARM), LC-MS (Thermo / Waters / Bruker / SCIEX), OpenTrons, qPCR, flow cytometer, plate reader, Benchling, SiLA2 adapter, `instrument_watcher`, `dbtl_controller`, `cyclic_peptide_dbtl`.

### Surfaces & auth
Surfaces (`connectors/`): claude-code, claude-desktop, cursor, chatgpt (`openapi.json` + adapter), slack (bot + Docker), wechat/open-claw; feishu/telegram/coze referenced. **Auth:** OAuth 2.1 + PKCE with RFC 7591 dynamic client registration; scope-gated per tool (`workflows:search`, `runs:read/write`, `reports:export`, `files:upload`, `memory:read/write`). **Remote/hosted MCP:** `Dockerfile.remote_mcp` (Python 3.11-slim + uvicorn/starlette + `mcp>=1.9`, StreamableHTTP transport, binds `0.0.0.0:8848`); reuses the same `tools_manifest.py` as stdio (no duplication). Entry `python -m remote_mcp.run`.

## 3. Auto-update system

Doc: `docs/06-auto-update/20260112_AUTO_UPDATE_SYSTEM.md`. Code: `auto_update/scripts/` (`add_tools_to_index.py`, `api_detector.py`, `api_wrapper_generator.py`, `citation_extractor.py`, …).

**6-stage daily pipeline** — `DETECT → FETCH → GENERATE → VALIDATE → TEST → INTEGRATE` (+ optional BLOG). Discovers GitHub bioinformatics tools, fetches docs, auto-generates a Galaxy XML wrapper, validates, container-tests, and integrates into the AI tool DB. Scheduled via cron `0 2 * * *` → `daily_update.sh`.

**Incremental embeddings** (`vector_search.py`): the doc-embedding source order is (1) `tools.embedding` BLOB — DB-native, "updated incrementally per tool at enrichment time"; (2) legacy `.npz` (being retired). A recipe-version constant forces recompute only when the embedded-text recipe changes, so unchanged rows keep their cached vectors — i.e. embeddings ride inside the DB and recompute per-tool rather than as a full 12k rebuild each run.

## Key locations

| Area | Path |
|------|------|
| MCP client config (main repo) | `/Users/kky/biomate/.mcp.json` |
| Connector repo | `/Users/kky/biomate-connector/` (separate git repo) |
| MCP tools manifest (SSOT) | `.../biomate-connector/mcp/tools_manifest.py:86` |
| MCP server (stdio) | `.../biomate-connector/mcp/biomate_mcp_server.py:122` |
| Remote MCP | `.../biomate-connector/Dockerfile.remote_mcp`, `remote_mcp/` |
| Lab instruments | `.../biomate-connector/lab_instruments/` (13 files) |
| Auto-update | `auto_update/scripts/daily_update.sh` |
