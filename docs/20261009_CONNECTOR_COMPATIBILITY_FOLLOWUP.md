# Connector compatibility follow-up — 2026-10-09

## Result

The repaired deployed workflow path still works, but the connectors are not ready for a blanket release approval. Additional live checks against published `@biomate/mcp-server@0.1.0` passed **9 of 11** assertions. This is a compatibility test count, not a scientific accuracy score or proof that every connector client works.

Evidence: `qa/20261009-connector-workflows/compatibility/results.json`. Harness: `scripts/connector-compatibility-proof.ts`. The timestamp is October 10 UTC / October 9 America/Chicago. These checks reused run `80992e6c-d483-49ed-a730-b698d2d0f2e0`; no new workflow or instrument protocol was executed.

| Check | Result |
| --- | --- |
| Run details with findings excluded | Pass |
| Default findings and canonical output references | Pass |
| watch_run snapshot | Pass; streaming not tested or implemented by this adapter |
| Explicit Markdown findings export | Pass |
| PDF and DOCX rejection | Two passes; these formats remain unsupported |
| Unsupported report-section rejection | Pass |
| Nonexistent run rejected | Pass |
| Instrument discovery | Fail: Unknown operationId: list_instruments |
| Instrument status | Fail: Unknown operationId: get_instrument_status |
| Invalid credential denied | Pass |

Previous live evidence also covers a fresh workflow from discovery through execution, outputs, report preparation and file preview, plus personal API-key creation/use/revocation. The previous full application suite passed 1,670 tests. No product implementation changed in this follow-up, so that suite was not rerun.

## Updates needed

1. **Align published capabilities with the deployed implementation.** npm advertises 22 tools while the main manifest/REST contract has 19. Two read-only instrument operations now demonstrably fail; protocol execution was deliberately not invoked. Remove unavailable tools from the published surface or implement and validate them before advertising them. Extend drift checks to the actual published package, not only repository copies.
2. **Repair and test installer OAuth.** `connectors/installer/src/surfaces.ts` configures BIOMATE_REFRESH_TOKEN. The published client selects that value as a fallback API_KEY and sends it directly as an Authorization bearer token. Source inspection found no refresh-token exchange or rotation implementation. Implement the access-token exchange and rotation contract, then test installation, expiry, refresh, revocation and account isolation. This is a source-confirmed protocol gap, not a completed live OAuth test.
3. **Integrate dependency-based multi-workflow execution.** The recent chain route accepts max_parallel, coverage_axes, per-step depends_on and dimensions. The connector's biomate_session adapter currently reduces the chat stream to text, one workflow_ga object and one run_id, with empty context. It does not expose a structured chain contract. Add explicit plan/branch/dependency/run tracking and preserve session context, then test a bounded real branched workflow. Full chain execution via connectors has not been verified.
4. **Make progress and export promises accurate.** watch_run currently returns a snapshot; the published manifest promises progress notifications. PDF/DOCX and non-findings report sections are advertised but rejected. Either implement these capabilities or narrow the schemas and descriptions to supported behavior. Markdown findings export is the verified report path. Report editing and chat-based revisions need their own end-to-end tests.
5. **Verify the remote MCP surface independently.** Existing live evidence lists only search_workflow, get_run and list_runs. The remote Python implementation is separate from the repaired npm-to-Node route. Source inspection shows fallback to a default client when no caller identity or resolved user key is available; this needs an account-isolation audit before expanding tools. This does not establish unauthorized private-data access. No such claim is made and no write tools were enabled.

These issues are not all caused by the latest system changes. The dependency/parallel-execution integration is directly relevant to the recent changes; several other capability and authentication gaps appear older.

## Recording gate

Keep recording on hold until the relevant client authorization path, supported capabilities, report behavior and workflow UI pass. Chinese recordings must use the implemented Chinese UI. Scientific review remains separate: numeric agreement of the three-compound ADMET report with source outputs does not validate probability-to-potency heuristics or reassuring safety interpretations in generated prose.

The previous repair is committed and deployed to dev. Its GitHub push remains blocked by an OAuth credential lacking workflow scope for a workflow file in inherited branch history. This follow-up does not alter credentials or unrelated work.

## Continuation: session response repair

Implemented `frontend/server/connector-session.ts` and wired it into the Node biomate_session route. The old adapter ignored the actual `final` event, whose payload contains `workflow`, `subIntentResults`, `isMultiIntent` and clarification metadata. It instead searched for a top-level workflow_ga field that the final response does not provide. The new adapter preserves the public workflow/branch payload, prerequisites and clarification fields, uses the final response text, and rejects HTTP errors, non-SSE responses, failed events and truncated streams. It does not expose the final payload's thinking_content. This is a response-contract repair; it does not add automatic chain execution or client progress notifications, nor fix ignored structured inputs/session context.

Four parser regression tests pass, covering byte-split Chinese UTF-8, dependency/branch preservation, multiline CRLF SSE framing, clarification, incomplete data and failure propagation. Together with the existing run-tool tests, eight focused tests pass. A real authenticated dev chat response also passed the local parser (`compatibility/session-proof.json`, 1,334 response characters). This is a local-module/live-service integration test, not evidence that the changed route is deployed or a real branched workflow has executed.

Extended `scripts/connector_docs_drift_test.mjs` with optional CONNECTOR_PACKAGE_MANIFEST comparison. The repository-only check passes; the published 0.1.0 package correctly fails for all three unsupported instrument tools. Release automation must supply the unpacked package manifest to activate this check.

Further OAuth tracing confirms the integration requires both sides: the Python issuer uses BIOMATE_OAUTH_SIGNING_KEY, issuer/audience and a sub claim; Node verifies with JWT_SECRET and resolves payload.userId. A refresh-only client patch cannot establish interoperability or scope enforcement. No authentication weakening or credentials change was made. OAuth remains unresolved.

Review note: the complete route/parser diff was inspected. Success requires an HTTP-success SSE response containing a valid final object and a successful done event. Errors and truncation must throw; the actual chat route emits final then done, confirmed by the live test. Branch structure is preserved from the public final workflow payload, without launching execution. TypeScript validation passed. The first full-suite run had 1,675 passing tests and one existing five-second bcrypt test timeout; all 13 authentication tests passed on isolated rerun. A lower-concurrency full-suite rerun was started to resolve the remaining validation gate. No deployment was attempted in this continuation.

The lower-concurrency full-suite rerun completed successfully (exit 0). The timeout did not reproduce. Local regression validation is complete; deployment, npm publication, client OAuth and real branched execution remain separate outstanding gates.
