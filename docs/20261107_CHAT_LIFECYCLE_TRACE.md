# Chat lifecycle duplication and reopening trace — 2026-11-07

Scope: repository and existing QA artifacts only. No private-user records, live account data, or new workflow execution was read or started for this trace.

## Exact screenshot candidate

`docs/20261102_ACCESSION_LAUNCH_INFO_FLOW_ISSUE_AND_FIX.md` documents the same identifying combination as the supplied screenshots: **GSE12345**, project **RNA-seq Differential Expression**, workflow **nf-core/differentialabundance**, empty inputs and a launch/work-directory failure. Its trigger was `failed_workflow.png`. This is strong prior evidence of the same scenario, but it does **not** record a session UUID, run UUID, message IDs, SSE tape, or calendar date for the 5:37 PM message. It cannot uniquely identify the saved chat.

No exact GSE12345 session/run identifier was found in `scripts/recording`, `frontend/e2e`, `docs/qa`, or `docs/real_run_harness` artifacts searched. Generic GSE12345 documentation/tutorial placeholders are not execution evidence.

The November 2 document already identifies a separate execution problem: a GEO accession was not resolved/staged before a direct differentialabundance launch, and an incomplete required-input schema let an empty launch proceed. This is not explained by a missing chat date or screenshot styling. Its historical diagnosis needs validation against the current launch path; this trace does not claim that fix is deployed.

## Known reproducible baseline, distinct from the screenshot

`docs/real_run_harness/20261005_233228_rnaseq.log` records:

- Project `42a6b0b3-663b-4d00-b9a6-b043e70703ed`.
- Run `4dbcc0cf-ce6f-4ef0-9c1f-2b98b02343ea`, terminal `completed`.
- `nf-core/differentialabundance`, report 4,624 bytes, screenshots `CAP_01_files_uploaded` through `CAP_04_after_run`.
- Source `frontend/e2e/project-real-run-capstone.e2e.ts`: curated **GSE227835** counts/metadata/contrasts, project upload, chat routing, execution, report assertions.

This is a different accession and completed case, not proof about the GSE12345 failure. The test dynamically creates its project and deletes it in `afterAll`; a historical project ID is therefore not a promise that it remains reopenable. The log has no saved chat/session UUID. The test also does not assert full saved-message/attachment identity on reopening or lifecycle uniqueness after reconnect.

## Current persistence and rendering boundaries

1. `nextflow-workflow-viewer.tsx` receives `chat_progress` SSE, forwards kind, friendly message, timestamp and invocation identity to the host.
2. `chat-interface.tsx:handleWorkflowProgress` and `chat-with-artifacts.tsx:handlePanelWorkflowProgress` independently accept their relevant viewer callbacks. Both create `progress-<invocation>-<kind>-<ts>` message IDs and reject an exact ID already in the session. Missing timestamps use receipt time, so replay idempotence then lacks a durable event identity. This is an unresolved producer-contract boundary, not proof that the screenshot used timestamp-less events.
3. `chat-history.ts` serializes `metadata` and `invocation_id`; its backend load restores both. Historical records saved before that support may lack owner/type metadata, but no data-loss claim is established here.
4. `chat-progress-fold.tsx:groupWorkflowResponses` attaches narrator entries only to an unambiguous workflow owner by explicit persisted run/invocation IDs. It does not strip matching text from the assistant response. Legacy or ambiguous ownership deliberately remains chronological.
5. `chat-message.tsx` renders the workflow response prose and attached progress in the compact progress box. It cannot safely decide that matching prose is a duplicate persisted event.
6. The server streaming persistence in `routes.ts:persistAssistantMessage` upserts accumulated assistant content by `message_id`; workflow metadata is separately attached. This is a distinct write path from client progress records and needs correlation with the affected message IDs before attributing the duplication.

No source path was found in the traced client modules that explicitly copies `Got it — starting your workflow now` or `Workflow hit an error` into workflow-response prose. The screenshot proves repeated visible text, but not whether it came from two saved records, historical grouping, streamed prose, or replay. Heuristic text deletion would risk removing meaningful user-visible content and was not added.

## Repairs prepared in the first batch

- Stop persisting `Generating workflow…` after generation already succeeded.
- Align recovery guidance with actual resume eligibility.
- Do not render or enqueue scientific findings for a failed run with diagnostic files only.
- Preserve metadata-only output visibility; label untouched phases Not started and avoid duplicated phase prefixes.

These repairs do not establish that the exact historical duplicate is resolved.

## Next acceptance check

Use an existing synthetic QA project and deterministic local SSE fixture: clarification → workflow generation → explicit launch → failure; replay the same durable event, reconnect, save/reload, and reopen the workflow from history. Assert each event identity appears once, user turns retain chronology, progress retains run ownership, the original response is not mutated, and both old and rerun statuses/results remain reachable. Separately validate the bare-GEO input gate without executing a costly workflow. Capture the saved message IDs/metadata and event tape with synthetic content only. No new access to unrelated user histories is necessary.
