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

## Second repair batch — source and local regression coverage

The client now accepts a durable producer `event_id` or SSE `lastEventId`, forwards it through the viewer callback and persists it as message metadata. Both chat hosts use the same run-scoped identity helper. A timestamp-less replay with the same event identity is rejected after serialization/reload; distinct attempt event IDs remain distinct even when their words match. Legacy timestamp identity remains compatible. Legacy events with neither producer identity nor timestamp are deliberately not deduplicated by prose. The producer must preserve an event's identity across replay; the root integration owns that server change.

Typed response readiness is shared by message rendering and panel opening. Explicit `success:false` is no longer treated as a successful generation merely because an `error` field is absent. Disambiguation, pending feedback and typed intent/parameter clarification remain questions; they do not produce a runnable workflow card or citation evidence card. This is a client presentation gate; server execute validation remains independently necessary.

Embedded After run content no longer repeats its parent tab heading. The action header wraps at narrow widths. Workflow intent within the progress box uses normal UI typography; technical log lines remain compact. Historical chat message labels include calendar dates and offer full timezone-bearing timestamps.

Local validation: eight targeted suites, **80 passed / 19 existing skipped**, log `/tmp/workflow-chat-final-tests.log`; whitespace diff check passed. Tests cover durable replay identity, distinct attempts, explicit failure/clarification readiness, actual viewer event forwarding, no runnable card/citations during pending feedback, embedded hierarchy and historical dates. Browser visuals and deployed behavior are not established by these component tests and remain the release acceptance step.

## Citation/source-reader reconciliation

Inspection confirmed earlier batch fixes already exist: literature panels omit the workflow tabs, empty APA/BibTeX actions are hidden, abstracts are passed into the reader, and the old fixed blank reader box is removed. The next patch additionally:

- Omits the redundant Tool Citations/Methods tab strip when a workflow panel has no methods context.
- Keeps retrieval details closed initially with a wrapping summary and compact textual counts, instead of full-width comparison bars. Invalid negative or kept-greater-than-found counts are not presented as valid statistics.
- Shows available author/year/journal metadata without fabricating `Unknown et al.`; does not repeat the same title in an expanded literature row. Available abstracts appear there too.
- Supports an explicitly supplied retrieved excerpt, labels absent content, and retains source/previous/next navigation with a scrolling body. DOI metadata already expressed as a DOI URL is normalized rather than producing a doubled URL. Missing source links are stated plainly.
- Whitespace-only BibTeX does not expose an empty export action. No citation format is fabricated from poor metadata.

Six citation/reader/chat integration suites: **36 passed**, log `/tmp/citation-reader-tests.log`. No new retrieval provider calls or fetched abstracts were invented. The UI iterates the supplied retrieval rows; it is not hardcoded to three providers. The backend `agents/research_agent.py` maps PubMed, Europe PMC, Semantic Scholar, OpenAlex, arXiv and bioRxiv display names and also handles unknown names. Its federated-search path comments describe querying PubMed/Europe PMC/Semantic Scholar/OpenAlex. Those source comments are not evidence that every provider was available or searched for the screenshot's particular query; exact provider availability and relevance require the real retrieval record.

## Producer identity and owner preservation

The producer contract is now implemented in source. Python narrator emissions receive a UUID event identity and can retain an explicitly provided identity during replay. Node narrator emissions likewise include UUID identities. Node raw SSE injection preserves a valid supplied identity or generates one once before client fan-out, then writes both `id:` and JSON `event_id`. CR/LF/NUL cannot become injected SSE ID lines.

An additional ownership defect was found while tracing the event: the viewer discarded the producer's `invocation_id`, and host wrappers replaced it with their current run. The viewer and both wrappers now preserve producer identity, with stream/current identity used only as a legacy fallback. This prevents the same event from acquiring different run ownership while the panel changes.

Four targeted Node/client suites: **116 passed**, `/tmp/sse-producer-tests.log`. Python narrator suite: **21 passed**, `/tmp/narrator-producer-tests.log`. A stale existing test expected a bare exit code despite the canonical cleaner explicitly excluding those codes; the test now verifies meaningful reasons survive while bare exit codes and unproven “auto-fixing” claims do not. Python 3.9 is not installed locally. The module imports on available Python 3.14 and parses with Python 3.9 grammar; that is not a claim of an actual Python 3.9 runtime import.

Scope limit: this change makes delivered/replayed events idempotent; it does not implement a server-side SSE replay archive. `injectRawEvent` still drops raw events when no client is connected. Saved chat entries and execution/status/result records must therefore be checked separately when reopening. No historical records were rewritten or silently deleted.
