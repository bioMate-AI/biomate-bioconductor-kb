# v2 GAP Analysis — Run-surface / Step view / Workflow panel / Panes

**Date:** 2026-09-09
**Scope:** Deployed BioMate run-surface family vs `claude_design/data_centroid_design_v2`, including the four brand-new v2 chapters (07, 08, 13, 14) and the revised chapters (02, RunSurface.jsx +190, StepDeep.jsx).
**Mode:** READ-ONLY audit. No source edited or committed.

> **2026-09-12 interpretation update:** this is retained as point-in-time
> implementation evidence. The accepted product no longer targets the
> split-stage/eight-tab result design; it targets Summary, Outputs, and a
> Reproducibility record. Read its priorities with
> [`20260912_V2_GAP_REBASE_AFTER_SIMPLIFICATION.md`](20260912_V2_GAP_REBASE_AFTER_SIMPLIFICATION.md).

## Reference sets

| Set | Path |
|---|---|
| NEW v2 spec + dataui | `/Users/kky/biomate-review/reference/claude_design/data_centroid_design_v2/` |
| OLD (diff base) | `…/scratchpad/old_design/reference/claude_design/data_centroid_design/` |
| DEPLOYED | `/Users/kky/biomate-review/frontend/client/src/` |

## Method

For the **NEW chapters (07, 08, 13, 14)** — no old equivalent, so every element is a full gap check. For the **revised** files (02, `RunSurface.jsx`, `StepDeep.jsx`) — diffed old→v2 first to isolate what's new, then compared only the delta. Status legend: **DONE** = element present and functional; **PARTIAL** = present but missing a required sub-element or behaviour; **UNDONE** = not implemented. "New-in-v2?" flags whether the element is a v2 addition (vs already in the old design and possibly already deployed).

Deployed counterparts audited: `nextflow-workflow-viewer.tsx`, `v2/WorkflowPanel.tsx`, `v2/AfterRunReport.tsx`, `v2/PhaseCard.tsx`, `v2/AutoLoop.tsx`, `components/steps/step-detail.tsx`, `components/step-output-preview.tsx`, `components/skip-dependency.tsx`, `components/auto-loop-panel.tsx`, `components/viewers/*`, `components/chat-with-artifacts.tsx`.

---

## Executive summary

The deployed run surface is **substantially aligned** with v2 on the workflow-panel governance layer — the two headline v2 additions, the **human approval gate (7.6)** and the **agent trajectory (7.7)**, are both deployed, as are the roles/permissions card, the verification-pattern card, and the skip-dependency (spec 02 §2.5.1 / spec 13 §13.5) three-state model. The biggest structural divergence is deliberate: v2's `RunSurface.jsx` uses a **split stage** (phases pane above + after-run pane below, with a fold button); the deployed panel keeps the older **tabbed** model (Settings / Phases / After-run tabs). This is an architecture choice, not a bug, but every v2 element that depends on the split (fold button, status legend, simultaneous report) is consequently absent.

The **weakest areas** are:
1. **The full step view (spec 08)** — deployed `step-detail.tsx` covers provenance, rendered/raw toggle, and origin-badged resolved params, but lacks step-position header ("step n of N"), dock/full mode switch, the **number→source card**, cache-arithmetic re-run, and per-state rendering (running/pending/skipped/failed).
2. **Panes (spec 14)** — almost entirely UNDONE. There is a resize grip but no width persistence, no chat-collapse-to-rail, no reveal chip, no <880px auto-collapse, no reveal-swap.
3. **Domain viewers (spec 08 §8.5 / Viewers.jsx)** — `PlddtChart`, `PaeHeatmap`, `SeqTracks`, `HitGrid` all exist as components but are **not wired into the structure viewer** (no pLDDT-hover → 3D-centre link).
4. **Domain-routed run cards (spec 13)** — deployed panel derives kicker from `domain` but does **not** override run *kind* ("Design run" / "Training run" / "Ad-hoc · sandbox" / "Model training run"); every routed run still reads as "Workflow".

### Coverage checklist (by surface)

| Surface | DONE | PARTIAL | UNDONE |
|---|---|---|---|
| Spec 07 — Workflow panel | 8 | 7 | 3 |
| Spec 08 — Full step view | 3 | 4 | 6 |
| Spec 13 — Run cards by domain | 2 | 3 | 3 |
| Spec 14 — Panes & previews | 2 | 3 | 8 |
| Spec 02 — Data analysis (revised delta) | 2 | 2 | 3 |
| RunSurface.jsx delta (split/output-grid/legend) | 1 | 2 | 4 |
| StepDeep.jsx delta | 1 | 0 | 0 |
| Viewers.jsx (domain viewers) | 4 | 1 | 1 |
| **Totals** | **23** | **22** | **28** |

**UNDONE: 28 · PARTIAL: 22.**

---

## Surface 1 — Spec 07: The workflow panel (NEW chapter)

**Highlights.** The governance spine is deployed: approval gate, trajectory, roles, verification pattern, collapsed QC-gates block, auto-loop. Gaps concentrate in (a) parameter *provenance origins* — deployed shows an `autoFilled` badge but not the five-origin taxonomy (default/inherited/recommended/confirmed/edited), (b) the QC gate's **evidence-level** row + explicit 3-action pattern, and (c) the split-stage / fold structure (deferred by the tabbed design).

| Element | v2 spec says | New-in-v2? | Deployed status | Evidence (file:line) | Priority |
|---|---|---|---|---|---|
| panel-head (kicker + name + `project · version · provenance` subline) | §7.1 fixed head; version line is the audit anchor | No | PARTIAL | `nextflow-workflow-viewer.tsx:2491-2497` kicker+name+`panel-sub`; subline is phase-count/description, **not** `project · version · input provenance` | P2 |
| run-bar with state WORD (Ready/Running/Halted/Awaiting approval/Completed) | §7.1, §7.9; colour never sole carrier | No (Awaiting-approval word is new) | PARTIAL | `WorkflowPanel.tsx:214-216` words Ready/Running/Completed/Failed; prod run-bar commented out; **Halted / Awaiting approval words absent** | P2 |
| section tabs Settings/Phases/After-run; After-run disabled+tooltip+dot till complete | §7.1 | No | PARTIAL | `nextflow-workflow-viewer.tsx:1051-1072` auto-switch; After-run simply hidden till complete — no disabled+tooltip+report-ready dot | P3 |
| panel-foot primary action Confirm-and-run / Cancel run / Run again | §7.1 | No | DONE | `nextflow-workflow-viewer.tsx:3560-3590`; `WorkflowPanel.tsx:331-345` | — |
| Blocker block *next to* primary action + remedy | §7.1 Blocker rule | No | PARTIAL | LicenseGate/ExecutionBlockedAlert render in body (`~2855-2930`, `~3550-3580`), not adjacent to the footer button | P3 |
| Global params as param-rows with **provenance badge** (5 origins) + `why`+citation | §7.2, §7.4 | Partly (origin taxonomy formalised) | PARTIAL | `GlobalParamsPanel` `~1949-2100` shows `autoFilled` badge + rationale; **no 5-origin badge, no expandable why+citation** | P1 |
| Clarification card first in settings | §7.2(1) | No | UNDONE | No clarification/disambiguation card in settings tab | P2 |
| Inputs resolved from project files (slots resolved/unresolved/blocked) | §7.2(3), Spec 02 §2.4.2 | No | PARTIAL | `GalaxyDatasetBrowser` `~1082-1154` resolves paths; no resolved/unresolved/blocked slot badges | P2 |
| Phases-to-run skip switches + live step count | §7.2(4) | No | PARTIAL | `SkipDependency` rendered `~2745-2800`; DAG analysis fetched; live "18 of 22 steps" count not confirmed rendered | P2 |
| Auto-loop on QC failure (cap 3, review window, on by default, always visible) | §7.2 | No | DONE | `nextflow-workflow-viewer.tsx:818-902` + `auto-loop-panel.tsx`; default-on, cap 3 | — |
| Permissions / roles card (capability rows name role, disabled-not-hidden) | §7.3 | No | DONE | `nextflow-workflow-viewer.tsx:2989` `<RolesCard/>` (from `roles-verify.tsx`) | — |
| Verification-pattern card (five checks stated once) | §7.3 | No | DONE | `nextflow-workflow-viewer.tsx:2983-2990` `<VerifyPattern/>` with QC/approval/license kinds | — |
| Quality gate: measured rows + **evidence level** + suggested-change diff + 3 actions (apply/keep/cancel) + override→QC audit | §7.5.1 | No | PARTIAL | QC block `818-863` metric/op/threshold/observed/verdict; `auto-loop-panel.tsx` shows was→now diff; **no evidence-level row, no explicit keep/cancel triad, override-audit not surfaced in panel** | P1 |
| Collapsed "QC gates" block showing every threshold incl passed | §7.5.1 | No | DONE | `nextflow-workflow-viewer.tsx:819-887` renders all thresholds incl passed | — |
| **Human approval gate** (what/why/cost/measured/who + Approve/Deny/Ask-reviewer, pauses never times out, "Awaiting approval") | §7.6 **new** | **Yes** | DONE | `nextflow-workflow-viewer.tsx:2710-2750` `<ApprovalGate>` on `status==='pending_review'`; what/why/cost/measured/who + 3 decisions | — |
| **Agent trajectory** (Decision/Tool-call/Your-answer/What-it-told-you/Gate; filterable; after-run tab) | §7.7 **new** | **Yes** | DONE | `AfterRunReport.tsx:158,312-315` `useFetchTrajectory`+`TrajectoryView`; kinds enforced (`:709`) | — |
| After-run tabs (Findings/Outputs/Methods/Params/Software/Citations/QC audit/Trajectory + v2 Report-as-editable-doc first tab) | §7.8 eight tabs; v2 adds Report | Report tab is new-in-v2 | PARTIAL | `AfterRunReport.tsx:175-185` renders Outputs/Findings/QC/Methods/Citations/Params/Software/Trajectory (8); **no editable Report/DocEditor tab** | P2 |
| Findings: every number is a LINK to its output | §7.8, Spec 08 §8.6 | No | PARTIAL | Findings figures carry `source_file` (`AfterRunReport.tsx:543-545`) → outputs; per-*number* inline anchor + claim card not implemented | P1 |

---

## Surface 2 — Spec 08: The full step view (NEW chapter)

**Highlights.** Deployed `step-detail.tsx` nails the two hardest honesty controls — the **rendered/raw two-position switch** with the "Raw first…" copy, and **origin-badged resolved parameters with per-row revert**. But it is a *display-only* surface: it has no step-position header, no dock/full mode switch, no state rendering, no cache-aware re-run, and — critically for the whole product's auditability claim — **no number→source card**. The domain viewers exist but are unwired.

| Element | v2 spec says | New-in-v2? | Deployed status | Evidence (file:line) | Priority |
|---|---|---|---|---|---|
| deephd head: phase letter + "step n of N" + step name | §8.2 | Chapter new | UNDONE | `step-detail.tsx:296` "Full step view" label; no "step N of M" / phase letter | P2 |
| mode switch full-window ⇄ dock-right | §8.2 | Chapter new | UNDONE | Modal-only (`onClose`); no dock mode | P3 |
| provrow `ran with → tool version → n outputs` + duration; input chips are dataset objects | §8.2, §8.3 | Chapter new | PARTIAL | `step-detail.tsx:313-337` inputs+tool+version(honest "version n/a")+outcount+duration; inputs are strings, not openable dataset objects | P2 |
| outtabs: one tab per output with evidence badge + filename | §8.2 | Chapter new | PARTIAL | `step-detail.tsx:348-360` tabs with FileText+filename; **no evidence badge** | P2 |
| rendered/raw two-position switch + "Raw first…" copy | §8.2, §8.5 | Chapter new | DONE | `step-detail.tsx:362-385` toggle; `:410` "Raw first: the summary above is derived from these bytes…" | — |
| Resolved params: non-default count in header; name+origin badge+editable value+reason; per-row Revert; apply disabled till change; "re-run this step + downstream" copy | §8.4 | Chapter new | PARTIAL | `step-detail.tsx:422-468` count "X not default", `OriginBadge`, editable `fmtVal`, per-row Revert, honesty copy; **no batched apply button** (changes are live) | P2 |
| Viewer by evidence class: Perceptual image-stage (fit/100/200/full-bleed), Quantitative table + **column stats**, Symbolic record browser, Procedural console follow-tail | §8.5 | Chapter new | PARTIAL | Delegated to `step-output-preview.tsx:792-849` (image lightbox / table / text-tail / structure); **image stage lacks fit/100/200/full-bleed; table lacks column stats** (`csv-table-viewer.tsx` detects numeric but no stats) | P1 |
| Domain viewers: 3D structure WITH pLDDT chart + PAE heatmap; per-base tracks | §8.5, Spec 03 §3.8 | Chapter new | PARTIAL | `viewers/plddt-chart.tsx`, `pae-heatmap.tsx`, `seq-tracks.tsx`, `hit-grid.tsx` all built + exported (`viewers/index.ts`); **NOT integrated** into `InlineStructureViewer` (`step-output-preview.tsx:857-935` never calls onSelectResidue) | P1 |
| number→source card (claim/how-computed/value/output-badge/step + "Open the output it came from") | §8.6 Claim rule | Chapter new | UNDONE | Not implemented; step-detail is output-centric, no claim card | P1 |
| Re-run from here: was→now diff, cache arithmetic in words, alternate output beside original | §8.7 | Chapter new | PARTIAL | `step-detail.tsx:301-304` "Re-run from here" → `onAdjustAndRerun`; **no diff, no cache arithmetic, no side-by-side alternate output** | P2 |
| States: Completed / Running (follow-tail) / Pending (params it WILL run) / Skipped (neutral not red) / Failed (log at failure) / Binary (download) | §8.8 | Chapter new | UNDONE | `step-detail.tsx` is stateless display; renders no per-state variant (running-tail/pending/failed-at-line). Binary handled in preview (`step-output-preview.tsx:842-846`) | P1 |
| StepDeep copy delta (viewer chosen by evidence class "resolved from the output itself…same on every surface") | §8.5 v2 copy tweak | Yes (copy only) | DONE (copy differs but semantics present) | Old→v2 diff is a one-line copy change only; deployed already uses evidence-class routing | — |

---

## Surface 3 — Spec 13: Run cards by domain (NEW chapter)

**Highlights.** The **skip / licence** governance from §13.5 is deployed. But the chapter's core rule — *the run card is a function of the routed domain and modality, so the panel can never contradict the preview* — is **not honoured**: the deployed panel overrides the kicker from `domain` but keeps kind = "Workflow" for every run. There is no design-run card, no training-run card, no sandbox card. The v2 reference wires this via `wfFor(dom, mod)` returning a per-domain `{kind, version, slots, params, phases, clarifications}`; the deployed panel has no equivalent.

| Element | v2 spec says | New-in-v2? | Deployed status | Evidence (file:line) | Priority |
|---|---|---|---|---|---|
| Card is a function of routed domain+modality (`wfFor(dom,mod)`), preview==panel | §13.1, §13.2 parity acceptance test | **Yes** | UNDONE | No `wfFor`; panel reads a single `workflowDefinition`; kicker from `domain` (`nextflow-workflow-viewer.tsx:2478-2482`) but no per-domain card shape | P1 |
| Kicker+name override run KIND ("Design run" / "Ad-hoc · sandbox" / "Model training run"), never "Workflow" for non-workflows | §13.4 | **Yes** | UNDONE | Kicker always `… · WORKFLOW` (`nextflow-workflow-viewer.tsx:2481`); no design/training/sandbox kinds | P1 |
| Version override (own pipeline version, not inherited v1.4.2) | §13.4 | **Yes** | PARTIAL | `workflowDefinition.version`/name used where present; no per-domain default table | P2 |
| Domain-true slots / params / phases / clarifications | §13.3, §13.4 | **Yes** | UNDONE | Panel renders generic params/phases from one definition; no per-domain slots or clarification sets | P2 |
| Licence gate in all three places (slot, phases banner, footer) gated on `needsLicence && !licensed` | §13.5 | Refined in v2 | PARTIAL | LicenseGate + ExecutionBlockedAlert render (`~2855-2930`); footer/phase/slot triple placement not confirmed all three | P3 |
| Skip capability declared by workflow (skippable/load-bearing/consequential) | §13.4 note, Spec 02 §2.5.1 | Yes | DONE | `skip-dependency.tsx:1-162` DAG-aware three-state; skippable-only-if-declared, block-if-downstream, advisory warn | — |
| Sandbox card (Python 3.12 pinned, isolated network, code-before-run, saved output→file object) | §13.6 | **Yes** | UNDONE | No sandbox/ad-hoc-compute run card in the panel | P2 |
| Step detail fixtured only for shipped transcriptomics run | §13.4 | Yes | DONE (by omission) | Deployed step-detail is generic; matches "don't borrow evidence" intent | — |

---

## Surface 4 — Spec 14: Panes, previews & navigation (NEW chapter)

**Highlights.** This is the **least-covered** surface. The deployed shell (`chat-with-artifacts.tsx`) has a resize grip and open/closed persistence, but essentially none of §14.1's collapse choreography: no chat-to-46px-rail, no "Run panel" reveal chip, no <880px auto-collapse, no reveal-swap, and width is **not** persisted (only open/closed). §14.2 previews are file objects but lack the versions / ask-to-edit / open-in-Files affordances. The `Resize.jsx` reference (preference-vs-ceiling, apply-never-persist, session-only collapse, Reveal control) has **no deployed counterpart**.

| Element | v2 spec says | New-in-v2? | Deployed status | Evidence (file:line) | Priority |
|---|---|---|---|---|---|
| "Hide chat" → chat collapses to 46px rail with vertical Chat tab | §14.1 | **Yes** | UNDONE | No rail; chat is side-by-side, no collapse-to-rail (`chat-with-artifacts.tsx`) | P2 |
| Back on run panel → panel hides, chat gains "Run panel" chip to restore | §14.1 | **Yes** | UNDONE | No restore chip; close hides panel entirely | P2 |
| Stage <880px auto-collapse chat; widen restores only if auto-hidden | §14.1 | **Yes** | UNDONE | Only `isMobile <768` hides chat entirely (`:143-148,2149`); no 880 threshold, no auto/manual distinction | P2 |
| Reveal below threshold SWAPS which side is away | §14.1 | **Yes** | UNDONE | No reveal/swap logic | P3 |
| Panel resizable to 320px via grip; **preference persisted** in localStorage; collapse NOT persisted | §14.1, `Resize.jsx` | **Yes** | PARTIAL | Grip `chat-with-artifacts.tsx:2310-2316`, minWidth 320; localStorage persists **open/closed only** (`:159-164`), width NOT persisted | P2 |
| Collapsed pane always carries a reopen control (`Reveal`) | §14.1 rule, `Resize.jsx` Reveal | **Yes** | UNDONE | No Reveal button when panel closed | P2 |
| Topbar survives narrowness: crumb/title ellipsize, buttons→icons under ~520px | §14.1 | **Yes** | UNDONE | No crumb/title ellipsize / icon-drop behaviour | P3 |
| Output previews as file objects (table/document/figure/model/structure) with affordances (open-in-Files / versions / ask-to-edit / download) | §14.2 | **Yes** | PARTIAL | `step-output-preview.tsx` file-object props + "Open full step view" (`:698-709`) + download (`:842-846`); **no versions / ask-to-edit / open-in-Files** | P2 |
| "An artefact is a file object, not a picture of one" | §14.2 rule | **Yes** | DONE | `step-output-preview.tsx:482-484` "the artifact itself, unmodified" + external-link | — |
| Navigation crumbs on new pages; open-file resolves owning project + expands sidebar | §14.3, §14.4 | **Yes** | UNDONE | Not audited as present on run/step pages; no crumb infra on step-detail modal | P3 |

---

## Surface 5 — Spec 02: Data analysis (REVISED — delta only)

**Old→v2 delta:** spec 02 gained §2.5 **Skipping phases** and §2.5.1 the **declared-skip three-state rule** (both marked `new`), plus the two-gears framing (§2.1) and gear arbitration chip (§2.2). The skip machinery is the same one deployed for spec 07/13. The two-gears (ad-hoc compute vs validated workflow) and the escalate "Redo as validated run" path are the genuine gaps.

| Element | v2 spec says (delta) | New-in-v2? | Deployed status | Evidence (file:line) | Priority |
|---|---|---|---|---|---|
| Skipping phases first-class (before + during run; dashed/struck SKIPPED neutral grey never red; downstream gated row; QC-audit records skip) | §2.5 **new** | **Yes** | PARTIAL | `skip-dependency.tsx` before-run three-state present; during-run skip of pending phase + "never red" styling + QC-audit skip record not all confirmed | P2 |
| Declared-skip rule: skippable / load-bearing (disabled-not-absent) / skippable-but-consequential | §2.5.1 **new** | **Yes** | DONE | `skip-dependency.tsx:1-162` implements all three states with reasons | — |
| Two gears: ad-hoc compute vs validated workflow, one module | §2.1 | Yes | UNDONE | No unified data-analysis module; workflow panel only. Lane preview exists (`components/lane-preview.tsx`) | P2 |
| Gear arbitration chip ("● Instant · compute [use a validated workflow?]") | §2.2 | Yes | PARTIAL | `lane-preview.tsx` shows lane chips; full compute↔workflow arbitration + escape-hatch not confirmed | P2 |
| Escalation "Redo as validated run" (compute code → configuration, results side-by-side) | §2.2, §2.6 | Yes | UNDONE | No compute-result → validated-run escalation path | P2 |
| Ad-hoc result message (lane chip, output by evidence class, Show-the-code, Inputs chips, Save-output, Redo) | §2.3.1 | Yes | UNDONE | No ad-hoc sandbox result card | P3 |

---

## Surface 6 — `RunSurface.jsx` (REVISED, +190 lines — delta only)

**Old→v2 delta (from `diff`):** the v2 RunSurface added (1) **split stage** `wf-split` with `wf-top`/`wf-after` and a **fold button** + **foldsummary**; (2) a **status legend** (finished/running/waiting/skipped); (3) domain routing via `wfFor(dom,mod)`; (4) an inline **ClarifyCard**, **RolesCard**, **VerifyPattern**, **ApprovalGate**; (5) the **OutputGrid** with per-output notes (localStorage `bm-output-notes`), searchable, evidence-tagged; (6) a **Report** tab (`DocEditor`) as the first after-run tab and a **Trajectory** tab; (7) the skip-dependency `SKIPDEP` locked/consequential states; (8) RunHistory renamed to "Workflows" with an "Import a workflow" action. Roles/Verify/Approval/Trajectory are covered under Surface 1 (deployed). Remaining delta items:

| Element | v2 (delta) | New-in-v2? | Deployed status | Evidence (file:line) | Priority |
|---|---|---|---|---|---|
| Split stage: phases pane above + after-run pane below simultaneously (`wf-split/wf-top/wf-after`) | RunSurface v2 + `runsplit.css` | **Yes** | UNDONE | Deployed panel is tabbed (Settings/Phases/After-run), not split; no `wf-after` pane (`AfterRunReport.tsx` is a tab body) | P2 |
| Fold button (fold phases to give report room) + foldsummary chips | RunSurface v2 | **Yes** | UNDONE | No fold button / foldsummary | P3 |
| Status legend (finished / running / waiting / skipped) | RunSurface v2, `runsplit.css:.statuslegend` | **Yes** | UNDONE | Not rendered | P3 |
| **OutputGrid** — per-artifact card, searchable, evidence-tagged, **per-output notes** persisted | RunSurface v2 `OutputGrid`, `runsplit.css:.opv*` | **Yes** | PARTIAL | Deployed Outputs tab lists step files (`AfterRunReport.tsx` outputs) but **no note-per-output, no search-outputs box, no thumb-by-kind grid** | P2 |
| ClarifyCard inline in settings | RunSurface v2 | **Yes** | UNDONE | (Same as Surface 1 clarification-card gap) | P2 |
| RunHistory → "Workflows" + "Import a workflow" | RunSurface v2 | Yes | PARTIAL | Run history exists; import-workflow entry point not confirmed here | P3 |
| Report tab = editable DocEditor (first after-run tab) | RunSurface v2 | **Yes** | UNDONE | (Same as Surface 1 after-run gap) — 8 tabs but no editable Report | P2 |

---

## Surface 7 — `Viewers.jsx` (NEW dataui file — domain evidence viewers)

**Highlights.** The four domain viewers are **built and exported** (this is a real strength — deployed even has extra CryoEM viewers FSC/motion/CTF not in the reference). The single gap is **integration**: pLDDT/PAE/tracks render standalone but are not wired into the structure viewer or the step outputs, so the spec-08 promise "a structure picture with its confidence chart, shown together" is not realised on a real result.

| Element | v2 spec says | New-in-v2? | Deployed status | Evidence (file:line) | Priority |
|---|---|---|---|---|---|
| PlddtChart (per-residue confidence, bands, hover/click → centre 3D) | Viewers.jsx | **Yes** | DONE (standalone) | `viewers/plddt-chart.tsx` (212 lines); exported `viewers/index.ts` | — |
| PaeHeatmap (n×n, hover readout, reliable/unresolved verdict) | Viewers.jsx | **Yes** | DONE | `viewers/pae-heatmap.tsx` (122 lines) | — |
| SeqTracks (line/marks/ticks, shared coord domain, flagged intervals) | Viewers.jsx | **Yes** | DONE | `viewers/seq-tracks.tsx` (187 lines) | — |
| HitGrid (ranked hits table+depictions grid, verdict colours, held/out-of-domain) | Viewers.jsx | **Yes** | DONE | `viewers/hit-grid.tsx` (263 lines) | — |
| Structure viewer WITH pLDDT + PAE shown together (one output) / PretrainedTab | Viewers.jsx §8.5 | **Yes** | UNDONE | `InlineStructureViewer` (`step-output-preview.tsx:857-935`) uses 3Dmol.js but never wires pLDDT/PAE; no `PretrainedTab` deployed | P1 |

---

## Prioritised gap backlog

**P1 (auditability / core-claim gaps):**
1. **number→source claim card** (spec 08 §8.6) — the mechanism the whole "click a number, land on its output" claim rests on. UNDONE.
2. **Domain-viewer integration** — wire pLDDT/PAE into the structure viewer so a structure ships with its confidence chart (spec 08 §8.5). Built but unwired.
3. **Domain-routed run KIND** (spec 13 §13.4) — stop labelling design/training/sandbox runs "Workflow". UNDONE.
4. **Param provenance 5-origin badge + why+citation** (spec 07 §7.4). PARTIAL.
5. **QC gate evidence-level row + explicit keep/cancel triad + override→audit** (spec 07 §7.5.1). PARTIAL.
6. **Step-view per-state rendering** (running-tail / pending / failed-at-line) (spec 08 §8.8). UNDONE.
7. **Column stats in the quantitative viewer** (spec 08 §8.5). PARTIAL.

**P2 (structural / navigational):** split-stage + fold + status legend; OutputGrid with per-output notes; panes choreography (rail, reveal chip, 880 auto-collapse, width persistence, Reveal control); clarification card; editable Report tab; two-gears + escalate-to-validated; step "n of N" header + dataset-object input chips + evidence-badged outtabs; input-slot resolved/unresolved/blocked badges.

**P3 (polish):** dock/full mode switch; blocker-adjacent-to-button; after-run disabled+tooltip+dot; reveal-swap; topbar narrowness; navigation crumbs.

---

## Notes / caveats

- The **split-stage vs tabbed** divergence is the single largest structural difference. It is a legitimate architecture choice; treat every split-dependent v2 element (fold, legend, simultaneous report) as *conditional on adopting the split*, not as independent bugs.
- Several v2 governance additions (approval gate, trajectory, roles, verify, skip-dependency) are **already deployed** — the deployed panel is in some respects ahead of the *old* design and abreast of v2 here.
- Line numbers are from the files as read on 2026-09-09; they will drift with edits. Component identifiers (e.g. `ApprovalGate`, `RolesCard`, `VerifyPattern`, `OutputGrid`, `wfFor`, `Reveal`) are the stable anchors.
- Deployed viewers **exceed** the reference in one dimension: CryoEM FSC/motion/CTF charts and interactive-tool launchers have no `Viewers.jsx` equivalent.
