# 2026-06-19 Connector Test Fixes + SessionRunner API Redesign

## Summary

This session completed the work on making the `bioMate-AI/biomate-connector` public
repo test suite fully runnable, and redesigned the `SessionRunner` SSE event
handling to use a clean, documented public API.

---

## What Was Done

### 1. Test Suite — 231/231 Passing (0 failures)

**Root problems fixed:**

| Problem | Fix |
|---|---|
| `oauth-server/` had a hyphen → not importable as Python package | `git mv oauth-server oauth_server` |
| `biomate_connector.oauth.*` monkeypatching didn't affect `oauth_server.oauth.*` | Used `sys.modules` aliasing + `setattr` on package to make them the SAME module object |
| All test `patch()` calls used `backend.lib.integrations.*` paths | Changed to `connectors.*` or `lab_instruments.*` |
| `backend.lib.mcp.*` import in test files | Changed to `mcp.*` |
| `mcp/biomate_mcp_server.py` fallback `from tools_manifest import` failed when imported as package | Changed to 3-level try: `backend.lib.mcp` → `.tools_manifest` (relative) → `tools_manifest` |
| PyJWT not installed | `pip install PyJWT` (added to `requirements.txt` / `setup.cfg`) |
| `mcp/tools_manifest.py` wrote openapi.json to wrong path | Fixed path calculation (repo root = `mcp/tools_manifest.py`.parent.parent) |
| `generated_from` field still said `backend/lib/mcp/tools_manifest.py` | Updated to `mcp/tools_manifest.py` |

**Files changed in `biomate-connector` repo:**

- `oauth_server/` — renamed from `oauth-server/`
- `biomate_connector/__init__.py` — top-level shim
- `biomate_connector/oauth/__init__.py` — sys.modules aliasing for correct monkeypatching
- `connectors/{chatgpt,coze,slack,wechat}/__init__.py` — make importable as packages
- `lab_instruments/__init__.py` — make importable as package
- `tests/conftest.py` — added repo root to sys.path
- All 9 test files — fixed import paths
- `mcp/biomate_mcp_server.py` — import fallback, open_claw_stream endpoint, SessionRunner
- `mcp/tools_manifest.py` — path fixes
- `mcp/tools_manifest.json` — regenerated
- `connectors/chatgpt/openapi.json` — regenerated
- `.gitignore` — added `__pycache__/`, `*.pyc`

**Commits:**
- `7c7757a` — fix(tests): make full test suite runnable from the public connector repo
- `cc98ce3` — chore: remove __pycache__ and .pyc files from git tracking

---

### 2. SessionRunner + `_normalize_sse_event` Redesign

The test suite defined a clean public SSE event contract for `/api/open-claw/stream`.
Implemented it properly:

**New event types in `_normalize_sse_event`:**

| SSE event | `kind` | Notes |
|---|---|---|
| `text_delta` | `text_delta` | `data.text` or raw string |
| `workflow_phase` | `phase_started` / `phase_completed` / `phase_failed` | Based on `data.status` |
| `workflow_step` | `step_completed` / `step_failed` | Based on `data.status` |
| `qc_gate` | `qc_gate` | `data.metric`, `data.value`, `data.verdict` |
| `auto_loop` | `auto_loop_remediation` | `data.param`, `data.was`, `data.now` |
| `done` | `done` | Terminal event; triggers final response |
| `finding` | `finding` | (already existed) |

Old internal BioMate SSE format (`chat_progress`, `qc_gate_triggered`, etc.) is
retained below the new handlers for backwards compatibility.

**`open_claw_stream` endpoint change:**
- Was: `POST /api/chat/stream` (internal BioMate chat format)
- Now: `POST /api/open-claw/stream` (clean public format)

**`SessionRunner._run_impl()` simplified:**

Old: 3-phase (chat stream → execute workflow → events stream)
New: Single loop over `open_claw_stream` events:
1. Extract `run_id`/`view_url` from any event's `data` dict
2. Call `_normalize_sse_event` → emit `notifications/progress` if non-None
3. Break on `done` event → send final tools/call response

---

### 3. `biomate_connector.oauth` sys.modules Aliasing

The critical insight: when tests do:
```python
from biomate_connector.oauth import router as oauth_router_mod
monkeypatch.setattr(oauth_router_mod, "current_user_id", lambda r: "user-42")
```

For this to affect `oauth_server.oauth.router.current_user_id`, both must be the
SAME Python module object. Achieved via:

```python
# biomate_connector/oauth/__init__.py
import sys, importlib

for bc_sub, os_sub in (
    ("biomate_connector.oauth.router", "oauth_server.oauth.router"),
    ("biomate_connector.oauth.store",  "oauth_server.oauth.store"),
    ...
):
    mod = importlib.import_module(os_sub)
    sys.modules[bc_sub] = mod
    setattr(this_module, bc_sub.split(".")[-1], mod)  # needed for getattr traversal
```

Key: must also `setattr` the module on the parent package object, otherwise
pytest's `annotated_getattr` traversal fails when trying `getattr(oauth_pkg, "store")`.

---

## What Remains (Next Session)

### Phase 0 parallel implementation (in `/Users/kky/biomate`):

**A1** — `backend/config/file_sources_conf.yml`: enable public data source plugins
(EBI FTP, NCBI FTP, Ensembl, Zenodo, HTTP) + wire into `galaxy.yml`

**A2** — `frontend/server/auth-middleware.ts`: add `authenticateStaticApiKey`
middleware for headless/API-key auth (Claude Code, Cursor, CI mode)

**A3** — `GET /api/workflows/runs/:id` response: add `inline_findings` and
`output_files[]` so the `get_run` MCP tool returns complete data without
a second round-trip

**A4** — MCP server: add `sampling/createMessage` capability to `initialize`
response for inline disambiguation

**B1** (after A1) — `browse_data` MCP tool + `GET /api/data/sources` and
`GET /api/data/browse` routes

**C1** (after A1+B1) — `fetch_public_data` MCP tool + `POST /api/data/fetch_public`

**D1** — thread API key auth through all new routes

See `docs/20260618_DATA_CONNECTOR_LANDSCAPE.md` for full design rationale.
