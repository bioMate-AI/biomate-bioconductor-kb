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

## Open follow-ups
- **Fix remote_mcp :8848 on dev** (currently 502 → `/mcp` transport down).
- **Single-source the 3 adapter switch statements.** Manifest is single-source for
  schemas, but ChatGPT `/tools/:operationId`, Open Claw `executeOpenClaudeTool`,
  and MCP dispatch each hand-maintain a per-tool switch — a tool added to the
  manifest but not to a switch is still a drift class (the contract test now
  catches it, but generating the dispatch from the manifest would prevent it).
- **Promote the connector canary to a rollback gate** once proven across syncs.
- **Add the synthetic monitor** above.
