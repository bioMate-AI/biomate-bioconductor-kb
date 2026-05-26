# Phase 0 — local smoke test results (2026-05-25)

**Branch:** `connectors-v2-launch`
**Worktree:** `/home/yzhang/biomate_worktrees/connectors_v2`
**Status:** ✅ **PASS** — proceed to Phase 1 (Anthropic Workbench)

## What was tested

Started a real OAuth 2.1 + PKCE server from the worktree (`/tmp/run_oauth_server.py` mounting `galaxy.connectors.oauth.router` on FastAPI / uvicorn on `127.0.0.1:8090`) with 6 OAuth clients seeded. Then exercised:

1. The OAuth protocol end-to-end via raw HTTP (`/tmp/phase0_test.py`)
2. The installer's `surfaces.install()` functions with real tokens fetched from the live server (`/tmp/phase0_install_direct.js`)

This is **the first time the OAuth code path runs against a real network socket** outside of unit tests — the unit tests use Starlette TestClient + in-process calls, which can mask bugs in serialization, header handling, and redirect behavior.

## Results

### Phase 0.A — OAuth protocol (6/6 PASS)

| # | Step | Result |
|---|---|---|
| 1 | `GET /oauth/authorize` returns 302 with code | ✓ 32-char code, state echoed |
| 2 | `POST /oauth/token` (auth code grant) returns access + refresh tokens | ✓ scope: 8 scopes, expires_in 1800 |
| 3 | Access token JWT decodes with correct claims | ✓ sub, surface, scopes, client_id, jti |
| 4 | `POST /oauth/token` (refresh grant) rotates tokens | ✓ new refresh ≠ old refresh |
| 5 | Replaying rotated refresh token rejected | ✓ 400 invalid_grant |
| 6 | `POST /oauth/revoke` invalidates | ✓ 200 silent success per RFC 7009; subsequent refresh fails |

### Phase 0.B — Surface installer (4/4 PASS)

| Surface | OAuth flow | Config file written | biomate entry present |
|---|---|---|---|
| `claude-code` | ✓ access(480 bytes) refresh(43 bytes) | ✓ `.claude.json` (296 bytes) | ✓ |
| `claude-desktop` | ✓ | ✓ `.config/Claude/claude_desktop_config.json` (296 bytes) | ✓ |
| `cursor` | ✓ | ✓ `.cursor/mcp.json` (296 bytes) | ✓ |
| `codex` | ✓ | ✓ `.codex/config.toml` (216 bytes) | ✓ |

Sample `.claude.json` written:

```json
{
  "mcpServers": {
    "biomate": {
      "command": "npx",
      "args": ["-y", "@biomate/mcp-server"],
      "env": {
        "BIOMATE_API_BASE": "http://127.0.0.1:8090",
        "BIOMATE_REFRESH_TOKEN": "1LP97o3sKLJeGLb_zprb3ylOYA7CVjy_0vi0RziktaY"
      }
    }
  }
}
```

Sample `.codex/config.toml`:

```toml
[mcp_servers.biomate]
command = "npx"
args = ["-y", "@biomate/mcp-server"]

[mcp_servers.biomate.env]
BIOMATE_API_BASE = "http://127.0.0.1:8090"
BIOMATE_REFRESH_TOKEN = "0bf8sYjqHKweWbLdR0CdoGAF-mIEpyUPC-km3QwQsuU"
```

## Test artifacts

| Artifact | Path | Purpose |
|---|---|---|
| OAuth server | `/tmp/run_oauth_server.py` | Standalone FastAPI app, auto-approve consent (user="user-phase0") |
| Protocol test | `/tmp/phase0_test.py` | 6-step OAuth flow over raw HTTP |
| Installer test | `/tmp/phase0_install_direct.js` | 4-surface install with real tokens from the server |
| Test DB | `/tmp/biomate-phase0.db` | SQLite, deletable |

All artifacts are intentionally in `/tmp/` — they are not committed and can be recreated from this doc at any time.

## Bugs found in Phase 0

**None.** All assertions passed first try.

## What this does NOT cover

- Real browser flow (UI-initiated OAuth) — only verified that the headless flow matches the spec
- Real Anthropic / OpenAI / Cursor / Codex clients picking up the written config — requires a real client running locally, deferred to Phase 2
- Token signing-key rotation across server restarts — deferred
- HTTPS / certificate behavior — deferred (will test in staging deploy)
- Slack and WeChat surfaces — they don't use the file-writing installer; deferred to phases 4 & 5

## Time + cost

- Setup: ~5 min (server start, seed clients)
- Test run: ~10 sec
- Cost: $0
- Tests are repeatable: same scripts work on any machine with Python 3.12, Node 18+, the worktree, and `connectors/installer/node_modules/`.

## Next: Phase 1 — Anthropic Workbench

Tomorrow: probe all 14 BioMate tools with 42 representative prompts in `console.anthropic.com/workbench` to validate LLM tool-selection accuracy. Target: ≥39/42 correct routing.

Setup script forthcoming.
