# Team brief — Backend + DevOps

**You own:** the OAuth server, MCP server, surface bridges, staging + prod deploys.

## What's done (you don't need to touch)

- **OAuth 2.1 + PKCE server** — `backend/lib/galaxy/connectors/oauth/`
  - 7 modules (scopes, pkce, tokens, store, server, router, __init__)
  - SQLite store; HS256 JWT access tokens (30 min); opaque refresh tokens hashed at rest (HMAC-SHA256); rotation on use
  - FastAPI router at `/oauth/{authorize,token,revoke,grants}`
  - Tested: 32 cases (7 core + 15 router + 10 security) — green
- **Tools manifest** — `backend/lib/mcp/tools_manifest.py` (single source of truth, 14 tools across 3 tiers)
- **MCP server** — `backend/lib/mcp/biomate_mcp_server.py` (streaming `biomate_session`, primitives, outputs)
- **Drift CI** — `backend/tests/test_tools_manifest.py` + `tests/test_connector_sandbox.py` (35 SDK-validation cases)

## What you own this week — pre-GA backend work (~1 week)

Priority order. Each is independently mergeable.

### 1. Add `report_ready` event branch *(unblocks Slack/ChatGPT/WeChat report delivery)*

File: `backend/lib/mcp/biomate_mcp_server.py:347` — `_normalize_sse_event`

Add a branch that emits:
```python
{"kind": "report_ready", "summary_md": "...",
 "view_url": "https://biomate.ai/runs/<id>",
 "delta": {"pdf_url": "<signed>", "docx_url": "<signed>"}}
```

`report_ready` is already declared in `_PROGRESS_KINDS` (line 342) but never emitted.

### 2. Slack `files.upload_v2` bridge

Path: `connectors/slack/bridge.py` (new file)

On `report_ready` events, call `export_report(fmt="pdf")` then Slack's [files.upload_v2 flow](https://api.slack.com/methods/files.uploadV2). Post into originating channel/thread. Also post volcano/FSC thumbnails on `finding` events.

The README at `connectors/slack/README.md:25` currently claims this works — **the claim is false until #1 + #2 ship**.

### 3. Open Claw `thumbnail_png_b64` forwarding

File: the WeChat bridge (look for the dispatcher that drops `thumbnail_png_b64`). WeChat **does** render inline images in service-account messages — the current drop is overcautious. Drop only PDF, keep PNGs. Use the message-image API.

### 4. Codex CLI ASCII renderer

Codex has zero image fidelity. Server-side render volcano / FSC / ROC plots to Unicode-block ASCII (~80×24) and include in `summary_md` when the client advertises no image support. Add a `client_capabilities` field to the MCP `initialize` handshake; default from `clientInfo`.

### 5. Flip the 2 xfail security tests

- **Rate limiting** on `/oauth/token` — add `slowapi` middleware, 30 req/min/IP
- **Refresh-token-family revocation** — add `family_id` column on `refresh_tokens`; revoke whole family on replay detection. See `connectors/test-docs/oauth_security.md` for exact tests to flip.

## DevOps — staging deploy checklist

The connector branch is **not** wired into the existing Galaxy ASGI app yet. Wiring is one line:

```python
# In backend/lib/galaxy/webapps/galaxy/buildapp.py or wherever the ASGI app boots
from galaxy.connectors.oauth.router import router as oauth_router
from galaxy.connectors.oauth import OAuthServer, OAuthStore
from galaxy.connectors.oauth.router import set_server

app.include_router(oauth_router)
set_server(OAuthServer(OAuthStore()))  # uses BIOMATE_OAUTH_DB path
```

Then seed the clients:

```bash
PYTHONPATH=backend/lib python backend/scripts/seed_oauth_clients.py
```

### Required env vars on staging + prod

| Var | What | Example |
|---|---|---|
| `BIOMATE_OAUTH_SIGNING_KEY` | HS256 JWT key | 64 random bytes, base64. **Generate via `python -c "import secrets,base64;print(base64.urlsafe_b64encode(secrets.token_bytes(64)).decode())"`. Store in AWS Secrets Manager. Never commit.** |
| `BIOMATE_OAUTH_DB` | SQLite path | `/var/lib/biomate/oauth.db` — needs persistent volume |

### Monitoring

Add to your existing Galaxy backend dashboard:
- Counter: `/oauth/token` requests by grant_type and HTTP status
- Histogram: `/oauth/token` latency p50/p95 (target <50ms / <200ms)
- Counter: refresh-token rotations / day
- Alert: spike in `invalid_grant` (>10/min for >5 min) → possible attack

### Signing-key rotation procedure (untested in prod!)

The OAuth code reads `BIOMATE_OAUTH_SIGNING_KEY` per-call via `_signing_key()` — rotation is just an env-var swap + restart. **But** every active access token becomes invalid immediately; clients then refresh (still works since refresh tokens aren't signed). Plan a rotation drill in staging first.

### DNS / staging

`api.biomate.ai` and `staging.biomate.ai` not resolving from internal dev machines as of 2026-05-25. Verify with your DNS / VPN setup before the team starts Phase 1 testing.

## Reference

- `docs/20260513_CONNECTOR_ARCHITECTURE_V2.md` — design rationale
- `docs/20260525_SESSION_SUMMARY.md` — full work index
- `connectors/test-docs/oauth_*.md` — per-suite test docs with SEV-level remediation tables

## How to run tests locally

```bash
cd /home/yzhang/biomate_worktrees/connectors_v2
BIOMATE_OAUTH_SIGNING_KEY=$(python -c "import secrets,base64;print(base64.urlsafe_b64encode(secrets.token_bytes(64)).decode())") \
  BIOMATE_OAUTH_DB=/tmp/biomate-test.db \
  PYTHONPATH=backend/lib \
  python -m pytest backend/tests/connectors/ -v
# expect: 30 passed, 2 xfailed (xfails track items #5 above)
```

## Open questions for you

1. Which Postgres / SQLAlchemy backend should `OAuthStore` migrate to for prod? Currently SQLite — fine for <1M tokens but not for HA.
2. Does the existing Galaxy session middleware set `request.state.user_id`? If not, you'll need a small shim before mounting the router.
3. Should the OAuth service run in-process with Galaxy or as a separate uvicorn? `set_server()` supports both — pick a deploy model and lock it.
