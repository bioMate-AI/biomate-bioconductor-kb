# Connector/MCP stability: runtime contract test + deploy gate

Date: 2026-07-23
Branch: integration/next-phase

## The question this answers
"MCP was tested earlier this week, yet we still fixed many issues yesterday — is
it unstable? How do we make it stable? Should we monitor it?"

## Diagnosis: it's integration-fragile, not logic-flaky
Every connector fix from 2026-07-13…22 was an **integration / wiring / build /
deployment** issue, not a tool-logic bug:

| Fix | Class |
|---|---|
| `readFileSync vs require (ESM bundle)`, `static http import` | build / module-format |
| `add /oauth/* proxy routes` | missing transport route |
| `recall_memory uses GET`, `export_report → findings/report` | wrong verb / wrong path |
| `remove Phase-2 stubs blocking preview_file, upload_file` | stub shipped as real tool |
| `ChatGPT adapter not deployed` | deployment gap |
| `MCP tool count 19 → 14` | manifest drift |

Root cause: the connector is an assembled stack — two transports (`/mcp` remote
+ `/tools/*` ChatGPT adapter), OAuth, an ESM bundle, a cross-repo manifest, and
per-tool endpoint wiring across **three separate adapter switch statements**
(ChatGPT `/tools/:operationId`, Open Claw `executeOpenClaudeTool`, MCP dispatch).
The existing coverage tested the **parts**, not the assembled whole against a
running server:
- `backend/tests/test_tools_manifest.py` + `.github/workflows/tools-manifest-drift.yml`
  are **static** — they check the manifest JSON matches its Python source and the
  schema shapes are valid. They never hit a live endpoint.
- `scripts/sync_to_dev.sh` smoke-tested workflow-gen and DB-search but had **zero**
  connector checks — a deploy could break a connector route silently.

So "tested a tool" ≠ "tested the deployed connector against a real client."

## What was built
### 1. Runtime contract test — `scripts/connector_contract_test.mjs`
Reads the canonical manifest (`backend/lib/mcp/tools_manifest.json`) and, against
a running server, for **each** of the 19 tools:
- probes the declared `backend_method backend_path` (no auth → write tools hit the
  auth gate and never actually run), and
- probes the ChatGPT adapter `POST /tools/{name}`,

classifying each: a 404/405/501, a `Cannot <VERB>` (Express unregistered route),
an `{"error":"NotFound"}` API-404, an SPA-fallthrough (`text/html`), or a
`not implemented / unknown operation` body → **FAIL**; a domain 404 (dummy id not
found) or any 200/400/401/402/422/429 → OK; 502/503/504/timeout → inconclusive.
Also checks `/mcp` reachability and that the **deployed** OpenAPI tool count
matches the manifest (live drift).

Usage: `node scripts/connector_contract_test.mjs [BASE_URL]`
(default `$BIOMATE_URL` or `https://dev-public.biomate.ai`).

### 2. Deploy gate — `smoke_test_connector()` in `sync_to_dev.sh`
Runs the contract test after the post-sync health gate, **WARN-ONLY** (same policy
as the db-search canary): a transient 502/timeout is inconclusive and never rolls
back; a definitive contract violation logs a loud `⚠ WARNING … deploy KEPT`.
Promote to a rollback gate once proven across real syncs.

## What the test found on its first live run (and I fixed)
Against dev it immediately caught **4 real manifest verb/path bugs** the static
drift test could not (the manifest was internally consistent but disagreed with
the actual routes — the server + all 3 adapters were correct, the manifest was
the stale outlier):

| Tool | Server route (truth) | Manifest said | Fixed manifest → |
|---|---|---|---|
| `search_literature` | `POST /api/literature/search` | GET | POST |
| `resolve_accession` | `POST /api/accession/resolve` | GET | POST |
| `recall_memory` | `GET /api/memory/relevant` | POST | GET |
| `export_report` | `GET /api/workflows/runs/{id}/findings/report` | POST | GET |

Also fixed the stale `we ship 14` → `19` comment. Regenerated all manifest copies
(`tools_manifest.json` ×2). After the fix the contract test is **0 failed**.

It also surfaced a real infra gap (reported, not yet fixed): **`/mcp` returns 502
on dev — the remote_mcp service on :8848 is down**, so the Claude-Desktop MCP
transport is currently unreachable. This is exactly the kind of thing the canary
now flags at deploy time.

## Should we monitor it? Yes — next step (not yet built)
CI/smoke catches deploy-time breakage; a **synthetic monitor** catches what CI
can't — OAuth token/cert expiry, upstream endpoint changes, container/worker
recycling, the remote_mcp process dying. Recommended: a cron every few minutes
running `connector_contract_test.mjs` (plus a real OAuth token-exchange probe)
and alerting through the SNS channel `sync_to_dev.sh` already uses
(`arn:aws:sns:us-west-2:399683337364:biomate-deploy-events`). The current 502 on
`/mcp` would already be firing.

## Root cause of the `/mcp` 502 — and the durable fix

Ground truth from the dev host (SSM, read-only):
- `biomate-dev-frontend` is **healthy** and proxies `/mcp → 127.0.0.1:8848`, but on a
  bridge network (`biomate-dev-net`) `127.0.0.1` is the **container's own loopback**.
- That container is a **Node-only image** (no Python, no uvicorn, no connector code),
  so the Python remote_mcp service **cannot run where the proxy points**.
- remote_mcp was running **nowhere**: nothing on host `:8848`, no process, **no
  systemd unit, no container, no supervisor**, and the connector code isn't on the
  host. The connector repo has **no deploy artifact** for it (no Dockerfile/.service).

So it wasn't crashing — **it was never deployed or supervised.** Any manual
`python -m remote_mcp.run` was a foreground process that died with the SSM session /
a reboot / a container swap, with nothing to restart it and nothing to re-establish
it on deploy. Hence "down again; simple start isn't enough."

**Fix (this commit) — run it as its own supervised container, deploy-integrated:**
- `biomate-connector/Dockerfile.remote_mcp` — packages remote_mcp (python3.11 +
  uvicorn + `mcp>=1.9` SDK, which is required for `StreamableHTTPSessionManager` /
  `TransportSecuritySettings`), COPYing the exact dirs it imports
  (`remote_mcp mcp oauth_server biomate_connector`) with `/app` as repo root so the
  `mcp`-shadow bootstrap resolves. A **build-time import guard** fails the *build*
  (not a runtime crash-loop) if the SDK is wrong or the shadow can't resolve.
  Binds `0.0.0.0:8848` (the default `127.0.0.1` was itself part of the problem).
- `routes.ts` — `MCP_UPSTREAM` now comes from `MCP_UPSTREAM_URL` (default
  `127.0.0.1:8848` for local dev); dev sets it to `http://biomate-remote-mcp:8848`.
- `sync_to_dev.sh` — `deploy_remote_mcp()` builds + `docker run --restart unless-stopped`
  on `biomate-dev-net`, generates/persists a signing key once (not committed),
  mounts `/var/lib/biomate` for the OAuth SQLite, then runs a **startup health check
  + end-to-end `/mcp` probe** and dumps container logs on failure. It runs after the
  frontend deploy (which now injects `MCP_UPSTREAM_URL`), is WARN-only (never aborts
  the sync), and `BIOMATE_MCP_REQUIRE_AUTH=0` keeps the handshake working without the
  key (which is only consumed at runtime, never at import).
- The connector canary now confirms `/mcp` is up on every deploy and pages if it dies.

This closes the class: supervised (survives crash/reboot/swap), correct topology
(proxy reaches it by DNS), deploy-integrated (re-established every sync), guarded.

## Open follow-ups
- **Verify remote_mcp is healthy on dev after the next sync** (build-guard + startup
  check will report; the canary confirms `/mcp` != 502).
- **Full OAuth flow correctness** (public issuer/resource URLs through the proxy) is
  beyond the handshake fix — REQUIRE_AUTH=0 for now.
- **Single-source the 3 adapter switch statements.** Manifest is single-source for
  schemas, but ChatGPT `/tools/:operationId`, Open Claw `executeOpenClaudeTool`,
  and MCP dispatch each hand-maintain a per-tool switch — a tool added to the
  manifest but not to a switch is still a drift class (the contract test now
  catches it, but generating the dispatch from the manifest would prevent it).
- **Promote the connector canary to a rollback gate** once proven across syncs.
- **Add the synthetic monitor** above.
