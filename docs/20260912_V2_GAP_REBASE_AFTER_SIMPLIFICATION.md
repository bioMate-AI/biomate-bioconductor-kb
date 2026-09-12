# V2 gap rebase after simplification

**Date:** 2026-09-12  
**Purpose:** re-evaluate the three 2026-09-09 v2 gap audits after the accepted
product decisions in
[`SIMPLIFICATION_DECISIONS.md`](../reference/claude_design/data_centroid_design_v2/SIMPLIFICATION_DECISIONS.md).

This does not erase the earlier audits: they remain useful implementation
evidence. It changes the target. A missing feature is a delivery gap only when
it is still part of the accepted product, not merely because it appeared in an
older ambitious prototype.

## New product boundary

Keep four scientific entry points: **Search & evidence, Data analysis, Models,
Design & generate**. The normal flow is deliberately small:

> state goal → supply missing inputs → run → Summary → Outputs →
> Reproducibility record.

The default system chooses a lane. Workspace connections are settings, not a
research flow. A run report always retains an immutable original and is
distributed with its manifest and outputs; editable/versioned project reports
remain a retained capability whose delivery sequence needs product approval.

## What the Sep 9 audits no longer require

| Earlier gap | Rebased decision | Action |
|---|---|---|
| Eight/nine after-run tabs, split-stage fold, status legend | Replace with three tabs: Summary, Outputs, Reproducibility record. | Do not build the split-stage or old tab catalogue. |
| Report as editable file, chat edit diff, local versioning, PDF/DOCX/HTML menu | Retained capability. The old prototype's local editor must not be presented as deployment. | Preserve the immutable-original + bundle contract now; schedule persistence/editing explicitly. |
| Full-page Connectors with four tabs, request-level skill switching and complex add-on taxonomy | Settings & workspace connections; not a primary scientific flow. | Keep connection/residency correctness; sequence the richer surface explicitly. |
| Chat/panel rail choreography, reveal swap, 880px collapse rules, dock/full step modes | Polish beyond the normal scientific path. | Defer unless usability testing identifies a real obstruction. |
| Dense Design-card modality control, per-row action pills and card-status chips | The four-module dashboard stays; modality can be inferred from the goal or asked only when needed. | Do not add dashboard density just to match the old prototype. |
| Per-output notes, exhaustive output-grid furniture, generic cell-level editing | Not required for the Phase-1 workbench. | Defer. |

## Gaps that remain release-relevant

### P0 — scientific truth, safety, and reproducibility

| Gap | Required adjustment | Why it remains P0 |
|---|---|---|
| **Authenticated output truth** | Every output, finding, report, preview and download must use the same authorization and canonical run-output source. Dev must prove it with real output bytes, not fixture-only success. | A result that cannot be read, or can be read by the wrong user, invalidates the workbench. |
| **Real inputs bound before compute** | A workflow must state the resolved project dataset/version, reject incompatible or missing inputs, and never report success for an unbound/default workflow. | This is the principal false-positive risk in scientific execution. |
| **Report bundle** | Implement a real download containing immutable report/summary, resolved parameters, software/tool versions, citations, QC/approval decisions, output references or checksums, and run identifier. | This is the reproducibility artifact scientists need first; it complements, rather than replaces, retained report editing work. |
| **One output resolver** | Resolve output type consistently across AfterRunReport, step preview, Files, and downloads; show plain labels (Table/Figure/Structure/Report/Log) while using one internal resolver. | Prevents one file receiving conflicting previews or provenance claims. |
| **Claim-to-artifact navigation** | Summary findings must link a numeric/scientific claim to the source artifact and producing step. A lightweight linked artifact panel is sufficient; an elaborate separate card is not. | This is the core evidence promise, not UI decoration. |
| **Truthful model status** | Every model is visibly labelled **validated predictive**, **project-adapted**, or **heuristic**; show applicable validation/out-of-domain caveats. | Drug-development users must not mistake a heuristic score for validated prediction. |

### P1 — essential, but can follow the P0 evidence path

| Gap | Required adjustment |
|---|---|
| **Three-tab result surface in the deployed client** | Replace the current many-tab `AfterRunReport` contract with Summary, Outputs, Reproducibility record. The record contains expandable methods, parameters, software, citations, QC and trajectory, and hides unavailable sections rather than showing placeholders. |
| **Domain-true run identity** | A design request must say Design run; training says Model training run; an ad-hoc calculation says Analysis. Do not label all scientific work “Workflow.” |
| **Parameter and QC explanation** | Preserve origin/rationale for material parameters; show evidence, threshold, verdict and any human override in the record. Approval gates only for external transfer/order, material cost, or shared-record publish/overwrite. |
| **Minimal Search & evidence result** | A routed evidence question should return a cited answer with a clear boundary/caveat and two exits: use it to configure an analysis, or save the evidence record. Animated retrieval bars, editable filters and a large standalone document editor are not P1 requirements. |
| **Dataset/run binding lineage** | In Files and the run record, show which input version was used and which outputs arose from it. Full RO-Crate and universal history UI can follow. |
| **Model/domain viewers where evidence needs them** | Keep confidence beside structural predictions, score tracks for sequence outputs, and ranked chemical candidates with held/rejected status. Current code already wires `ClarifyCard` and routes pLDDT/sequence/hit viewers; acceptance tests should prove them on real outputs. |

### Retained capabilities requiring an explicit sequencing decision

- Server-backed report/project-file editing, accepted AI diffs, version history,
  and formats beyond the reproducibility bundle.
- Full workspace connector page, MCP onboarding, and sophisticated add-on scope
  controls.
- Full responsive pane choreography, docked step view, output annotations, and
  cell-level dataset editing.
- Advanced design views such as Pareto exploration and rejection detail. The
  default can remain simple while the capability remains available.

## Corrections to the Sep 9 audit status

Two Sep 9 findings are stale in the current checkout and should not remain on
the active backlog:

| Earlier finding | Current evidence | Rebased status |
|---|---|---|
| `ClarifyCard` built but not wired | `frontend/client/src/components/chat-message.tsx` imports/renders it; a dedicated `chat-message.clarify-wiring.test.tsx` exists. | Closed subject to dev E2E. |
| Domain viewers built but unwired | `step-output-preview.tsx` imports and renders `PlddtChart`, `SeqTracks`, and `HitGrid`; dedicated preview tests exist. PAE still needs confirmation in the real structure-result path. | Partly reconciled: retain real-output acceptance testing and PAE integration verification. |
| “Reports as editable files” is the biggest v2 P0 | The immutable report bundle is P0; editing/versioning remain retained capabilities. `AfterRunReport.tsx` documents that server-backed versions/diffs/file-tree export are not yet built. | Keep both: ship the bundle and explicitly sequence the persistence/editing work. |
| Connectors must be a full primary page | The target changed: Settings & workspace owns connections. | Reclassify as P2 information architecture, while retaining residency/security correctness. |

## Documents to adjust

The Sep 9 audits should remain immutable evidence, but their priority summaries
must be read through this rebase:

1. `20260909_V2GAP_SEARCH_FILES_REPORTS_CONNECTORS.md`: replace **Reports as
   editable files P0** with **report bundle + output authorization P0**;
   identify the report bundle as P0 and place rich report editing in the
   retained-capability sequence for explicit product prioritisation.
2. `20260909_V2GAP_RUNSURFACE_STEP_PANES.md`: replace the after-run tab target
   with the three-tab record; demote split-stage/pane choreography; retain
   claim-to-artifact, domain-true run identity, QC evidence, and output
   resolver as P0/P1.
3. `20260909_V2GAP_COLDSTART_COMPOSER_CHAT.md`: retain four modules and
   goal-to-lane explanation, but demote visual modality controls, per-request
   add-on scopes, and rail choreography. Keep typed clarification and truthful
   post-run narration only when they affect a decision or record.

## Acceptance sequence

1. Exercise a real authenticated run on dev from input binding through output
   retrieval and report-bundle download.
2. Verify that one claim in Summary opens its exact source output/step and that
   the record reproduces parameters, software, citations and QC decisions.
3. Repeat for one model prediction and one Design & generate candidate list;
   verify their labels and scientific viewers do not overstate validation.
4. Decide, with the product owner, the delivery order for report editing,
   workspace features, and advanced scientific views; none is cancelled by this
   rebase.
