# Problem 1 — One coherent workflow response

Date: 2026-10-24. Status: first production slice implemented; full live lifecycle verification remains.

## Accepted behavior

One BioMate response contains its inline progress stream, run reference and completion answer. The complete analysis-plan content belongs at the beginning of that same stream, followed by live updates. Keep its Markdown and source links; do not remove its content or repeat it as separate prose. Progress stays unfolded in a scrolling text box. There is no “Activity · N updates” disclosure or extra progress heading. Follow the tail only while the reader is at the bottom; preserve the reading position in both the log and conversation when they inspect earlier content.

Completed scientific analyses retain threshold flags as findings. Execution success and check outcomes are separate. A completed standalone ADMET screen has no pending scientific steps: show the named-compound findings, report and output files. Do not show a pause alert, exclusion/threshold suggestions, Resume/Cancel controls or claims of downstream work. Genuine holds require confirmed execution control and actual pending consumers, as described in the cross-workflow QC audit.

Remove redundant lane/tool labels and literal progress headings from chat. Tool/version, resolved parameters and full audit information remain in the reproducibility record. Keep the existing workflow-panel QC format. Do not add “This is a model prediction, not a measured toxicity result.”

## Reference and composition

Use the accepted Data Centroid v2 simplification decisions and its conversation, workflow-panel and pane specifications (06, 07, 14). Keep Summary / Outputs / Reproducibility record navigation and the existing file identities. Use existing production tokens, workflow chip and result renderers. This is a reusable run container; domain-specific scientific layouts and invented measurements do not belong in its grouping logic.

The updated completed-response preview uses the tutorial-release `qc_metrics.json` and the companion `toxicity_report.json`: aspirin 0.855, caffeine 0.875 and ibuprofen 0.487 against the DILI criterion 0.5. The DILI table is a single check, not an overall safety conclusion. The QC summary's hERG IC50 432.4246 µM is a batch value; never attach it to an individual compound. Source file details in the preview are excerpts. The preview is simulated; no workflow or file mutation is performed.

## Implemented slice

- `chat-progress-fold.tsx` groups progress and completion findings under an unambiguous workflow owner. Ownership comes from persisted execution/invocation IDs or a verified current-run mapping. It never derives run ownership from names, adjacent messages, ambiguous message IDs, timestamps or compound text. Unknown legacy events stay chronological. Conflicting/ambiguous associations remain unattached. Original message records are retained.
- Stream keys use their first event identity so appended events do not remount the stream. Duplicate event IDs are rejected across the stored message history, including late replay. Grouping also deduplicates repeated attached records for display.
- `chat-interface.tsx` passes the triggering message ID when starting a run. The run is attached to that exact message (or its known panel owner), rather than the oldest matching workflow name. Conversation scrolling respects the reader's position, and explicitly mismatched historical messages do not borrow the current run's execution state.
- `chat-with-artifacts.tsx` records run/invocation aliases on workflow anchors, progress and findings. The existing bounded findings polling still upserts the same completion message; grouping places that message within the owning response. User turns keep their position.
- `chat-message.tsx` keeps the full workflow plan unfolded within the progress log inside the assistant response and renders findings without a second BioMate heading. The final answer owns response controls when available. The compact run reference drops repeated domain/subtitle/hint text and preserves actual terminal states.
- The stream is keyboard-focusable, wraps long lines and has an accessible log name. It does not announce every incoming line. This slice preserves existing research-streaming disclosure behavior and genuine workflow execution controls.

## State contract

| State | Response behavior |
| --- | --- |
| Ready | Readable intent and existing configuration; no fake progress |
| Running | Unfolded inline updates and actual run state |
| Completed, findings pending | Completed execution with the existing analyzing-results message |
| Completed, findings ready | Grounded answer under the same response; flags remain findings |
| Findings unavailable | Completed execution stays completed; existing output access remains |
| Failed/cancelled | Actual execution state; no synthetic successful findings |
| Genuine hold/approval | Existing enforced workflow controls; no hold inferred from a completed check |
| Missing/ambiguous ownership | Chronological standalone entry; never attributed by guesswork |

## Verification and remaining work

Focused tests cover two interleaved runs, intervening user turns, stable stream identity, persistence/reload, verified aliases, conflicting and ambiguous owners, deduplicated records, scroll-position preservation, full plan content inside the unfolded progress stream and final-answer control ownership. Existing research, clarification, pipeline-approval and composer-context tests are run separately to avoid their legacy shared-DOM cleanup behavior.

**35 focused frontend tests passed** across the grouping/stream/message, research, clarification, pipeline-approval and composer-context suites. TypeScript checking passed on the isolated PR branch. A combined legacy test run exposed shared-DOM cleanup collisions; the affected existing suites passed when run separately.

A local browser harness renders the actual production message and stream components. Inspect desktop and 375px layouts, light/dark appearance, keyboard accessibility and source navigation in the companion mockup. This is not a deployed end-to-end execution test. Live SSE reconnect, concurrent real workflows, failure/cancel/approval lifecycles and full application restore still need verification before Problem 1 is considered fully complete.

The preview's QC summary is a design reference. Entity-aware scientific findings generation and complete source-linked QC visualization are the next implementation slice (Problem 2); this container does not fabricate or hardcode those results.
