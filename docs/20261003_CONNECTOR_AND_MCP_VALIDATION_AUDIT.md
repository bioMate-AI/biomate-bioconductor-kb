# Connector and MCP Validation Audit — 2026-10-03

## Decision

The shared connector contract is coherent locally and its public, unauthenticated
dev surface is reachable.  Do **not** declare private database connections or
user-managed remote MCP servers ready in dev yet: their deployed API routes
return 404.  This is a deployment parity issue, not a reason to weaken the
end-to-end test.

No workflow was launched, no external MCP server was registered, and no user
data or credential was changed during this audit.

## Scope and source of truth

`backend/lib/mcp/tools_manifest.py` is the source of truth.  Its generated
manifest and OpenAPI mirrors currently expose 19 tools:

`biomate_session`, `search_workflow`, `get_workflow_spec`, `run_workflow`,
`get_run`, `cancel_run`, `list_runs`, `watch_run`, `preview_file`,
`export_report`, `analyze_results`, `explain_error`, `query_database`,
`resolve_accession`, `browse_data`, `fetch_public_data`, `search_literature`,
`recall_memory`, and `upload_file`.

The legacy `backend/lib/mcp/mcp_config.json` describes a historical v1.1
server and must not be used as a current connector contract.

## Evidence

| Surface | Result | Evidence |
| --- | --- | --- |
| Dev public connector routing | Pass | `connector_contract_test.mjs https://dev-public.biomate.ai`: MCP endpoint reachable; 19 backend routes and 19 ChatGPT adapter routes resolved; generated OpenAPI exposes the same 19 operations. |
| Manifest invariants | Pass | `backend/tests/test_tools_manifest.py`: 31 passed. |
| Connector documentation drift guard | Pass | `node scripts/connector_docs_drift_test.mjs`. |
| Installer package | Pass with environment note | 20 tests passed; TypeScript build completed.  On macOS ARM, the Rollup optional binary was omitted by this local `npm ci` and had to be supplied for the test run. |
| Private-DB and external-MCP security core | Pass | 80 tests passed plus the loopback client round-trip test passed when run outside the sandbox.  Coverage includes SELECT-only validation, secret redaction, ownership isolation, SSRF/private-address blocking, non-HTTP rejection, namespacing, and stdio rejection. |
| Connector dialog component tests | Pass | 16 focused frontend tests passed. |
| Dev browser E2E | Blocked by deployment parity | 5 of 6 checks passed.  The authenticated private-DB request `GET /api/db-connections` returned 404, where the product contract requires 200. |

## Corrections made in this change set

- Regenerated the manifest, frontend mirror, and ChatGPT OpenAPI from the
  canonical 19-tool definition.
- Updated connector guides that still claimed 14 tools; added the five missing
  tools to the central and Claude Code guides.
- Added a docs-drift guard so a stale tool count or omitted manifest tool fails
  locally.
- Removed unsupported pre-run cost/runtime wording from `search_workflow` and
  `get_workflow_spec`, and added a manifest test preventing that promise from
  returning.  This preserves the user's decision not to implement estimates
  now.
- Repaired the standalone private-DB test harness so it imports the target
  module rather than accidentally booting the full model stack.
- Replaced a false-positive browser selector with a role-based selector and
  replaced the obsolete Skills-tab E2E with a real private-DB/remote-MCP
  availability assertion.

## Release gates

1. Deploy the frontend proxy routes for `/api/db-connections` and
   `/api/mcp/servers`, together with their Galaxy/backend counterparts, to the
   dev environment.
2. Re-run `frontend/e2e/connectors-dialog.e2e.ts` against dev; all six tests
   must pass and the authenticated DB and MCP list endpoints must return 200.
3. Provision the pinned backend test environment before relying on the full
   connector/OAuth/sandbox suite.  The current local Python environment lacks
   `python-multipart` and has an old `jsonschema` without Draft 2020-12
   support, despite both being pinned in repository requirements.
4. Verify connector-release ownership.  The repository installer declares
   version `0.1.0`, while some documentation describes an external maintained
   `biomate-connector` version `2.0.0`.  Resolve that release/registry
   distinction before publishing installation guidance as a new release.
5. Treat the current npm audit advisories as a separate dependency review;
   do not apply blanket audit upgrades during this connector validation work.

## Product implications

The public tool contract is consistent across MCP, OpenAPI, and client guides.
The security implementation is well covered at unit level.  The remaining
material risk is operational: dev has not deployed the user-managed connection
routes that the UI and local backend already support.  Until gate 2 closes,
those capabilities should remain unavailable or explicitly marked as not yet
enabled in dev—not silently rendered as an empty connection list.
