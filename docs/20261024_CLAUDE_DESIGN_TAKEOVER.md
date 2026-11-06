# Claude Design takeover — workflow information flow

Snapshot: **2026-10-24, America/Chicago**. Implementation: [PR #298](https://github.com/bioMate-AI/biomate/pull/298), branch `codex/qc-assessment-findings`. The [Claude Code handoff](20261024_CLAUDE_CODE_TAKEOVER.md) documents worktrees, integration, changes and checks.

## Read in this order

1. This document: the latest user decisions supersede conflicting older proposals.
2. [Data Centroid v2 simplification decisions](../reference/claude_design/data_centroid_design_v2/SIMPLIFICATION_DECISIONS.md): repository path `reference/claude_design/data_centroid_design_v2/SIMPLIFICATION_DECISIONS.md`.
3. [Current response specification](20261024_WORKFLOW_RESPONSE_DESIGN_SPEC.md) and [execution plan](20261024_DESIGN_HANDOFF_EXECUTION_PLAN.md).
4. [Original manifest](20261023_CLAUDE_DESIGN_HANDOFF_MANIFEST.md), followed by its four Group A requirement documents. The six original handoff/architecture documents are included in this branch.
5. The v2 prototype's `dataui/ChatView.jsx`, `dataui.css`, `themes.css` and relevant `spec/` pages. Start with `06 The composer.html`, `07 The workflow panel.html`, `14 Panes and output previews.html`; use specs 12/13 and domain examples for their corresponding problems.
6. [Composition architecture](20261023_GENERATIVE_RESPONSE_COMPOSITION_ARCHITECTURE.md): design owns reusable primitives/patterns, while the harness owns composition/validation. A visual grouping change does not complete that architecture.

The manifest's absolute base `/Users/kky/biomate-review` is the original checkout. In another worktree, resolve repository-relative resources against that worktree's root. Requirements describe intended capabilities; confirm current APIs before presenting one as implemented.

## Latest accepted decisions

- **Keep the full analysis-plan content.** It starts the same unfolded, scrolling stream as subsequent updates, inside its owning BioMate response. Retain formatting/links. Do not fold it under “Analysis plan” or “Activity · N updates”, move it to the top of the whole chat, or repeat it as separate prose.
- Associate progress/findings with their exact run across concurrency/reload. The completion answer follows below the stream. Follow new lines only while the reader is at the bottom.
- Remove redundant labels such as “Cloud · Workflow”, “ADMET · progress” and repeated tool/model headings. Necessary metadata belongs in the reproducibility record. Do not add the rejected sentence “This is a model prediction, not a measured toxicity result.”
- **A completed standalone screen is finished.** Retain threshold flags as findings; do not invent downstream work, a pending decision, exclusion/threshold suggestions or Resume/Cancel controls. Earlier paused/remediation mockups are superseded. Actual enforced intermediate holds remain appropriate when pending work depends on them.
- Convey compound identity, measurement, units, effective threshold/comparison and source clearly; preserve the complete report/output record. Do not claim identity is unavailable when companion output supplies it. A passing DILI check is not an overall safety conclusion.
- Keep the existing workflow-panel QC layout unless a specific verified deviation warrants correction. Keep chat concise; avoid extra dashboard cards and duplicate controls.
- Preserve four entry points; exactly **Summary / Outputs / Reproducibility record**; **Table / Figure / Structure / Report / Log**; persistent file identity/version; one owner per control. Design reusable primitives and examples rather than bespoke screens per workflow.

## Portable preview and source data

- [Openable completed-response preview](design/20261024_workflow_response_preview.html): standalone browser view with source/report navigation and panel recovery.
- [Editable conversation fragment](design/20261024_workflow_response_preview_fragment.html): inline source. Optional host state controls are not required for ordinary navigation.

This view supersedes the older local `workflow-response-preview.html` paused/exclusion mockup. It is simulated, not an active run or production screenshot. Source-file views contain excerpts rather than complete downloadable originals.

Tracked fixtures: `docs/qa/20261003-tutorial-release/qc_metrics.json` and `toxicity_report.json`. DILI probabilities: aspirin **0.855**, caffeine **0.875**, ibuprofen **0.487**, criterion **0.5**. Identity uses input/SMILES mapping plus companion per-compound output; the aggregate QC JSON alone names no compound. Do not mix this three-compound fixture with an older two-compound example. The batch hERG IC50 **432.4246 µM** does not belong to a named individual compound. Retain relevant model context without the rejected boilerplate sentence.

## Delivered and remaining

| Problem | Current state / next requirement |
| --- | --- |
| 1. Coherent response | First production slice: full-plan log, run ownership, completion continuation, reader-controlled scrolling, fewer duplicate controls/hints. Live lifecycle verification remains. |
| 2. Findings/provenance | Next priority: reusable entity/result/source primitive, missing/partial states, field contract and real end-to-end propagation. |
| 3. Reproducibility | Existing surface retained; QC records/exports corrected. One six-section audit document, immutable original and truthful bundle/edit/version availability remain. |
| 4. Consistency | Existing tokens used here. Inventory actual light/dark/narrow/wide deviations across shared surfaces. |
| 5. Molecular viewers | Queued: Table/Figure/Structure states for uncertainty, confidence, pose/score, cycles, censored/OOD/missing data. |
| 6. Run-step schema | Queued: shared schema with real tool/version, consumed parameters, outputs and status. |
| 7. QC controls | Shared assessment/control semantics fixed. Design actual hold/approval states with named pending work and recorded decisions; do not manufacture completed-run gates. |
| 8. Campaign/Rounds | Queued: audit APIs/persistence, then model/version, partial assay and bench-wait states. |
| 9. Ranked evidence | Queued: channel/source identity, evidence tiers, conflicts/vetoes and ranking boundaries. |

The attractive compound table/batch-QC summary is **not yet a generalized production scientific-findings renderer**. Engineering improved the container and QC records. Do not mark all nine problems complete or claim arbitrary LLM-composed UI blocks are validated and deployed.

## Next deliverable

Finish Problem 1's state/interaction review with engineering, then design **Problem 2: entity-aware findings and shared provenance**. Provide a concise written component specification and an inspectable mockup for new visual treatment. Specify regions, data fields, immutable source references, missing/error/partial states, accessibility, token mapping and acceptance examples. Keep the v2 shell; avoid additional top-level tabs and per-task templates.

Distinguish the concise chat answer from complete report/output evidence. State which fields already exist and which backend contract is missing. Link example values to fixtures; invent no identities, validation claims, versions, citations or capabilities. Agree the data contract with Claude Code before depicting unsupported actions.

Suggested opening request: “Read `docs/20261024_CLAUDE_DESIGN_TAKEOVER.md` and the Data Centroid v2 references first. Preserve the latest user decisions, review the completed-response preview, then produce the reusable Problem 2 findings/provenance specification and mockup with explicit implementation gaps.”
