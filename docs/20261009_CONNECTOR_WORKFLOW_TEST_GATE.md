# Connector workflow tests before recording — 2026-10-09

## Decision

Latest status: the deployed repair and a fresh connector-only workflow passed the core journey (see the final verification section). The initial failure described below is historical. Additional compatibility testing passed 9 of 11 checks; two advertised instrument operations are unsupported. See `20261009_CONNECTOR_COMPATIBILITY_FOLLOWUP.md` for remaining updates. Recording remains HOLD.

**HOLD recording.** A real three-compound ADMET workflow launched through the published npm connector and completed, but the connector-only user journey failed at output discovery and report export. No new tutorial video was recorded or approved. Chinese editions must use the integrated Chinese UI, Chinese narration and reviewed Chinese captions.

This takes over the connector handoff supplied by the user. It does not mark other workflow tutorials or external client applications verified.

## Tested path

Installed `@biomate/mcp-server@0.1.0` from npm in `/private/tmp/biomate-connector-20261009` with lifecycle scripts disabled. Used the MCP SDK over actual stdio against `https://dev-public.biomate.ai`. No mocked scientific results. Shared fixture login once per harness invocation; credentials stayed in memory. A separate personal-key test created and revoked one temporary key.

Workflow: **Predict ADMET Properties (AI)**; explicit aspirin, caffeine and ibuprofen SMILES; MPNN parameter. Run `85e8bae6-8836-4abc-a062-44dd2fde30c2`; Nextflow `1376bf13-1b04-4923-a68d-49eb30376b26`. Source/spec review before execution confirmed the workflow path, parameters, two processing steps and prediction-versus-heuristic distinction. Expected output was three compounds plus QC and provenance files, not a clinical safety verdict.

## Results

| Check | Result | Scope |
|---|---|---|
| Existing installer suite | 20 passed, 3 files | Local tests; simulated authorization service, not live OAuth consent |
| Existing documentation drift check | Passed | Only compares repository docs to its 19-tool manifest |
| Published npm MCP initialize/list | Passed | **22 tools**, not the documented 19 |
| Workflow discovery and specification | Passed | Correct ADMET path and parameters returned |
| Launch through npm MCP | Passed | Real AWS Batch/Nextflow execution, two successful processes |
| Personal API key | Passed | Mint → read owned run through npm MCP → revoke → revoked key denied |
| `get_run` | Partial / contract failure | Returns identity/status but no `output_files` or findings, although `preview_file` instructs the client to use those outputs |
| `analyze_results` | Returned real analysis | Sampled five actual outputs; prose not fully scientifically validated |
| `export_report`, Markdown | **Failed** | 404 “Findings report not yet available,” both before and after `analyze_results` |
| Canonical output API diagnostics | Passed | Nine files listed; four small science/provenance files downloaded and hashed |
| Scientific consistency | 8 passed | Three exact inputs, valid probability ranges, aggregate consistency and failed DILI gate retained; not model validation |
| Remote HTTP MCP | Partial | Initialize/list succeeded; only `search_workflow`, `get_run`, `list_runs`; live OAuth not tested |
| Advertised production hosts | Failed from test environment | `api.biomate.ai` and `app.biomate.ai` DNS did not resolve; dev OpenAPI returned HTTP 200 with 19 tool operations |

The canonical run endpoint was called once during polling to diagnose progress and returned completed/succeeded. That endpoint may refresh stored status. Therefore this run does **not** prove autonomous connector status convergence. Further canonical reads/downloads were diagnostic and were not counted as connector journey passes.

## Root causes and required repairs

1. `get_run` and `watch_run` in `frontend/server/routes.ts` use `/api/runs/:id/meta`. `runsOutputsService.resolve` reads stored identity/status and does not return outputs or findings. The connector needs a current, complete run representation with retrievable output references. Test completion without a web UI or diagnostic read refreshing state.
2. `analyze_results` produces an analysis response, but the findings-report route reads a separately generated findings cache/local file. The tested sequence did not populate the report. Connect report preparation/readiness to the actual connector journey.
3. A second export defect is visible in source: `selfGet` always parses JSON, while the findings-report route returns Markdown when ready. This was **not reached in this live run**, which failed earlier with 404. Verify and fix content-type handling before calling export ready. PDF/DOCX and section selection are advertised in the package but not proven by this test.
4. The npm server treats `BIOMATE_REFRESH_TOKEN` as a Bearer credential directly; the installer writes a refresh token. No token-exchange/rotation implementation was observed in the published server. API-key success does not validate the installer OAuth path. Complete that live flow before installation recording.
5. Reconcile separate 22/19/3 tool surfaces with their actual supported capabilities. Do not simply replace every count with 22 or present public read calls as authorization proof.
6. Update production host/config documentation only when the intended deployment is verified. Do not silently substitute dev as a production installation.

No application code was deployed or changed during this test pass. Existing unrelated modifications were preserved. The published connector source lives in the separate `biomate-connector` repository; the handoff's `connectors/mcp-server` path does not exist in this worktree.

## Scientific presentation gate

Outputs report ADMET-AI predictions and a probability-to-IC50 heuristic. The fresh result now has consistent per-compound and panel IC50 aggregation, unlike the older captured evidence. That consistency does not establish a validated potency model. DILI values must remain classifier scores, not patient incidence. Do not reuse unverified citation years or numeric error/benchmark claims from the generated analysis.

## Evidence and reproducibility

- `scripts/connector-workflow-proof.ts`: published-package discovery/spec, explicit `--run` launch, resume using `CONNECTOR_RUN_ID`, optional `--analyze`; nonzero on detected failed checks. Launch once; resume the existing run rather than creating another.
- `scripts/connector-api-key-proof.ts`: real key creation/access/revocation check; never persists plaintext key.
- `docs/qa/20261009-connector-workflows/npm-workflow-proof.json`: sanitized nested attempts, tool responses, export errors and run ID.
- `api-key-proof.json`, `hosts.json`, `remote-mcp.json`: connection/auth evidence.
- `direct-run-diagnostic.json`, `diagnostic-output-downloads.json`: explicitly separate direct-API evidence.
- `science-consistency.json` and four downloaded files: numerical audit and source evidence.

Recording acceptance: complete intended authorization → discover/specify → execute → observe terminal state → preview actual outputs → analyze → export a usable report, then verify that exact journey in each intended client. Check EN and Chinese UI visually before bilingual recording. Direct MCP SDK success alone does not certify Codex, Claude Desktop, ChatGPT, Slack or WeChat UI integration. No external client account setup, public publication or client delivery was performed.

## Post-change recheck — October 9, 17:47 America/Chicago

Rechecked the pinned published npm package against the same completed run; no additional computation or model analysis was launched. Fresh evidence is `docs/qa/20261009-connector-workflows/post-change-recheck/npm-workflow-proof.json`. Discovery/specification and completed status passed again. The three failures persist: 22 published tools versus 19 documented, no output_files in get_run, and Markdown export returning 404 (findings report not yet available).

Git line history dates the get_run/watch_run → metadata mapping to `97f948bbf` (July 20), and export_report → findings/report mapping to `931143673` (July 20). The latest committed routes change inspected, `53d09e07c`, adds dependency/parallel-execution fields to the chain path, not these connector mappings. Thus the current evidence supports an older integration gap; it does not establish that the latest changes caused it. The exact deployed commit has not been verified (the inspected health routes do not expose it). Recording remains HOLD.

## Repair review and pre-deployment checks

The patch routes get_run/watch_run through the authorized live run refresh and canonical output inventory, mapping s3Uri to the published s3_uri field. Successful runs optionally trigger the existing findings preparation API. Export explicitly returns pending until findings are ready, then reads Markdown with content-type-aware decoding. Unsupported PDF/DOCX or non-findings sections fail explicitly rather than silently ignoring the requested format. Original source measurements are not modified.

Reviewed the complete diff and terminal-state conditions. Existing completed run 85e8bae6 should return output references, a ready Markdown report containing its ID, and a successful result preview. Ownership continues to be enforced by the existing backend endpoints; incoming Authorization is forwarded only to the configured BioMate API. A locally mounted copy of the exact module passed these operations using the published npm connector against real dev APIs. This is not deployed-route evidence. The 22/19 package-documentation mismatch remains a separate failed release check.

Pre-sync: TypeScript type check passed; full Vitest suite passed 140 files / 1,670 tests (2 files and 7 tests skipped). Four focused connector contract tests passed. The initial sandbox run failed local-server binding; the normal-network rerun passed. No Python modules changed. The live patched-module integration is the relevant domain check. Deployment must be frontend/Node only, retaining the existing Galaxy workflows and database.

## Deployment

Repair commit: `95a5e2dd4` (`fix(connectors): refresh run outputs and prepare Markdown findings exports`). The repository sync completed healthy at 18:02 America/Chicago. App image `sha256:69326d271df35a98904cf77ded5a53f39a30a4a9bedd0f950d5e913331339628` was built and a fresh container verified. The script also refreshed its remote MCP service. Workflow generation and connector route smoke checks passed (0 failed / 0 inconclusive). It did not ship workflow or database layers. The deployment's migration replay emitted an existing-table error on its initial migration; no new migration was required for this patch, and health checks passed. The Node engine warning did not prevent build completion.

GitHub push is blocked by inherited branch history: the OAuth credential lacks `workflow` scope for `.github/workflows/ind-pi-suite.yml`. No credentials or unrelated workflow files were changed to bypass that restriction. The repair is committed locally and deployed; it is not pushed.

## Fresh deployed workflow verification — passed core journey

Run `80992e6c-d483-49ed-a730-b698d2d0f2e0` was launched after deployment through the published npm MCP connector. No UI visit or separate diagnostic run read was used to refresh this run. Discovery → specification → launch → repeated get_run → completed → output discovery → report pending → report ready → preview_file all passed. The report includes the correct run ID, and DILI values in the exported Markdown match the previewed output for all three compounds.

Evidence: `docs/qa/20261009-connector-workflows/deployed-fresh-run/npm-workflow-proof.json` has `workflowJourneyPassed: true`. The overall harness still exits 1 deliberately: its separate package/docs tool-count assertion remains 22 versus 19. That is not a regression failure in the repaired journey and must not be hidden as an all-connectors release pass.

Recording is still not approved: review scientific interpretation in generated report prose, complete client-specific authorization/UI checks and verify the Chinese UI. This patch repairs workflow status/output/report plumbing; it does not add PDF/DOCX generation, comprehensive report editing, or certify the extra instrument tools advertised by the npm package.
