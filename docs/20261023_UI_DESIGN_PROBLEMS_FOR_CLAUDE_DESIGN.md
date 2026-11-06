# UI Design Problems — a brief for Claude Design

**Date:** 2026-10-23
**For:** Claude Design.
**Framing — design the SYSTEM, not every use case.** It is impossible to pre-design a
UI for every use case; the space is infinite. So the division of responsibility is:

- **Design owns the FINITE part:** the composable **presentation primitives** + design
  system — the evidence-class viewers (**Table / Figure / Structure / Report / Log**),
  tokens/cards/badges/states, a small set of **composition patterns**, and **2–3 worked
  exemplars** of a well-composed response. Design these well and write them down.
- **The harness + LLM own the INFINITE part:** the actual response. Given the raw
  outputs + context + provenance, the LLM **composes** the answer — picks which
  primitives, fills them with real data, sequences and visualizes them — guided by the
  design *principles and exemplars*, **not a per-use-case template** (the LLM can't
  follow templates literally, and shouldn't).
- **Quality bar (the LLM's composition must honor):** real entity identities, every
  number linked to its source, no bare predicted numbers, the right evidence-class
  viewer, honest live-vs-aspirational. These are principles, not scripts.

So the items below are requests for **primitives + patterns + exemplars** (the finite,
designable part) and the **quality bar** — NOT a template for every use case. Where an
item reads like a specific screen, treat it as "the primitive + an exemplar of using it
well," which the LLM then composes from per run.

**For each item:** think it through, design the primitive/pattern, and **write it down
clearly in text** (a spec Claude Code can implement) — **not a one-off visual mockup**.
Pointers to existing components + the data-centroid-v2 spec are given.

Guardrails that still apply (from `SIMPLIFICATION_DECISIONS.md`): no bespoke per-task
UI; after-run = Summary / Outputs / Reproducibility; output types = Table / Figure /
Structure / Report / Log; never a bare predicted number; one control per screen.

---

## 2026-10-24 — STATUS UPDATE (read this first; supersedes older proposals below where they conflict)

A parallel engineering pass (PR [#298](https://github.com/bioMate-AI/biomate/pull/298),
branch `codex/qc-assessment-findings`) shipped a **first production slice of Problem 1**
plus the QC-vs-execution semantics the problems below depend on, and the user signed off
on a set of decisions that **supersede** any conflicting proposal in the Problem sections
that follow. This workstream is now owned here; the authoritative, most-recent specs are
Codex's `docs/20261024_*` set (see the manifest's new Group A0). **Read those first.**

**Latest accepted decisions (these are the binding brief now):**
- **Keep the full analysis-plan content inline.** It opens the *same* unfolded, scrolling
  stream as the subsequent live updates, inside its owning BioMate response. Keep its
  formatting/links. Do **not** fold it under "Analysis plan" / "Activity · N updates",
  hoist it to the top of the whole chat, or repeat it as separate prose.
- **One answer, one owner.** Progress and findings associate with their exact run across
  concurrency/reload (by message/run identity, not name/adjacency). The completion answer
  follows *below* the same stream and owns the response controls; no second BioMate header.
  Follow new lines only while the reader is at the bottom.
- **Remove redundant labels/chrome** — "Cloud · Workflow", "ADMET · progress", repeated
  tool/model headings. Necessary metadata lives in the reproducibility record. Do **not**
  add the rejected sentence *"This is a model prediction, not a measured toxicity result."*
- **A completed standalone screen is finished.** Retain threshold flags as *findings*; do
  **not** invent downstream work, a pending decision, exclusion/threshold suggestions, or
  Resume/Cancel controls. Earlier paused/remediation mockups are superseded. *Actual*
  enforced intermediate holds (real confirmed backend pauses, chain approvals, genuine
  CryoSPARC halts) remain appropriate — design those as real states, never manufactured.
- **Convey identity + provenance honestly** — compound identity, measurement, units,
  effective threshold/comparison, and source, clearly; preserve the complete report/output
  record. Do **not** claim identity is unavailable when a companion per-compound output
  supplies it. A passing DILI check is **not** an overall safety conclusion.
- Keep the existing workflow-panel QC layout unless a specific verified deviation warrants
  it. Keep chat concise — no extra dashboard cards, no duplicate controls.
- Preserve the four entry points; exactly **Summary / Outputs / Reproducibility record**;
  **Table / Figure / Structure / Report / Log**; persistent file identity/version; one
  owner per control. Design **reusable primitives + examples**, never bespoke per-workflow screens.

**Problem state after this pass:**

| # | Problem | State / next requirement |
|---|---|---|
| 1 | Coherent response | **First production slice delivered** (full-plan log retention, run ownership, completion continuation, reader-controlled scrolling, fewer duplicate controls/hints). **Live-lifecycle verification remains** (SSE reconnect, concurrent runs, full restore, delayed/unavailable findings, failure/cancel, genuine holds). |
| 2 | Findings / provenance | **NEXT PRIORITY.** Reusable entity/result/source primitive; missing/partial states; a field contract; real end-to-end propagation. See refined Problem 2 below. |
| 3 | Reproducibility | Surface retained; QC records/exports corrected. One six-section audit doc, immutable original, truthful bundle/edit/version availability remain. |
| 4 | Consistency | v2 tokens used here. Still need an inventory of actual light/dark/narrow/wide deviations across shared surfaces. |
| 5 | Molecular viewers | Queued: Table/Figure/Structure states for uncertainty, confidence, pose/score, cycles, censored/OOD/missing data. |
| 6 | Run-step schema | Queued: shared schema with real tool/version, consumed params, outputs, status. |
| 7 | QC controls | Assessment/control semantics fixed in code. Design *real* hold/approval states with named pending work + recorded decisions; do **not** manufacture completed-run gates. |
| 8 | Campaign / Rounds | Queued: audit APIs/persistence, then model/version, partial-assay and bench-wait states. |
| 9 | Ranked evidence | Queued: channel/source identity, evidence tiers, conflicts/vetoes, ranking boundaries. |

**Honesty guardrails (do not overstate):** the attractive compound table / batch-QC
summary in the preview is a **design reference, NOT an implemented generalized production
findings renderer**. Do not hardcode the example compounds or per-workflow answer layouts.
LLM block-composition is **not** delivered by PR #298. Do not mark all nine problems
complete. Requirements describe *intended* capabilities — confirm the backend contract
with engineering before depicting an unsupported action.

**Fixtures (use these exact values; invent no identities/versions/citations):**
`docs/qa/20261003-tutorial-release/{qc_metrics.json,toxicity_report.json}` — DILI
probabilities aspirin **0.855**, caffeine **0.875**, ibuprofen **0.487**, criterion
**0.5**. Identity uses input/SMILES mapping + companion per-compound output; the aggregate
QC JSON alone names no compound. The batch hERG IC50 **432.4246 µM** does not belong to a
named individual compound. Do not mix this three-compound fixture with the older
two-compound example.

---

## Problem 1 — The chat response for a workflow run is fragmented (highest priority)

> **2026-10-24:** First production slice delivered (PR #298) — see the status update
> above and Codex's `20261024_WORKFLOW_RESPONSE_DESIGN_SPEC.md`. What remains is the
> live-lifecycle state/interaction review, not the static layout. The analysis below
> stated the original problem; the accepted decisions above are the binding resolution.

**Observed (ADMET run, the left chat column).** A single interaction — ask → BioMate
routes → the workflow runs → findings come back — is rendered as a stack of
**disjointed, mismatched boxes**:
1. a collapse/expand **arrow** at the top of the response (a "Working · N updates" fold);
2. a **panel box with a row of tiny buttons** — it reads as if the chat *stops* there;
3. a **separate, visually ugly progress box** right below it for the live step stream;
4. then **another BioMate message** showing the findings.

It feels like four unrelated widgets stacked, not one answer. It is the single biggest
"the UI is confusing / not neat" offender.

**Design question.** How should **one workflow interaction read as one coherent
thread** — the intent, the routed workflow, the live progress, and the result — so it
scans as a single BioMate response rather than a pile of boxes? What is folded vs.
always shown; where does the progress stream live relative to the workflow card and the
findings; what is the transition from "running" to "done" inside the chat?

**What exists / pointers.** `frontend/client/src/components/chat-with-artifacts.tsx`
(chat + right panel), `chat-message.tsx` (message rendering), the SSE live-progress
rendering (the "Working · N updates" fold), `findings-card.tsx`; v2 spec `06 The
composer.html`, `07 The workflow panel.html`, `14 Panes and output previews.html`.
Note the two-lane framing (Instant vs Cloud) and that a Cloud run opens a run object in
the right panel — so clarify what belongs in the **chat thread** vs. the **panel**.

---

## Problem 2 — The Findings presentation (NEXT DESIGN DELIVERABLE)

> **2026-10-24:** This is the next Design deliverable after Problem 1's lifecycle review.
> Scope it as a **reusable entity-aware findings + shared-provenance primitive**, not an
> ADMET-specific table. Required by the accepted decisions:
> - **Entity identity is real and comes from the data.** Map each result to a named
>   compound via input/SMILES + the companion per-compound output; the aggregate QC JSON
>   alone names no compound, so the primitive must have **missing / partial-identity
>   states** (e.g. the batch hERG IC50 **432.4246 µM** belongs to no individual compound —
>   show it as batch-level, not mislabeled to a compound).
> - **Provenance without redundancy.** Convey measurement, **units**, the effective
>   **threshold/comparison**, and **source file + version** once — not a filename reprinted
>   per row. Link to the complete report/output record; the chat answer stays concise.
> - **Honest framing.** A passing DILI check (e.g. ibuprofen **0.487** < **0.5**) is not an
>   overall safety conclusion; do not add the rejected "model prediction, not measured"
>   boilerplate. Fixture values: aspirin 0.855, caffeine 0.875, ibuprofen 0.487 (crit 0.5).
> - **Deliverable:** a concise written component spec + an inspectable mockup — regions,
>   data fields, immutable source refs, missing/error/partial states, accessibility, token
>   mapping, acceptance examples. State which fields exist today vs. which backend contract
>   is still missing (agree the contract with engineering before depicting any action).
>   Not a generalized production renderer yet; do not hardcode the example compounds.

**Observed (ADMET Findings).** A flat `Metric / Value / Interpretation / Source` table;
the **Source column reprints the same filename on every row** (redundant); rows are
labelled **"Compound 1 / 2 / 3"** with no real identity, so no one can tell which
compound a number belongs to; the card is plain (`bg-blue-50/30`), never styled to v2.

**Design question.** How should per-entity scientific findings (e.g. ADMET across
several compounds) be presented so the **answer is scannable, each result is tied to a
real, named entity, and the source is shown without redundancy** — within the after-run
**Summary** tab, in the v2 evidence-class styling?

**Code prerequisite (partly shipped).** The backend findings generator used to embed
"(Compound N)" in free-text interpretation. A first cut now emits the **real compound
identity** as a structured `entity` field (`routes.ts::_parseAdmetOutput`, consumed by
`findings-card.tsx`, commit `0c1b24ade`). Problem 2's design should build on that
`entity` contract and tell engineering exactly which additional fields the primitive
needs (units, threshold, source+version, partial-identity flag) so the contract can be
completed end-to-end. (`findings-card.tsx`, the backend findings parser.)

**Pointers.** `frontend/client/src/components/findings-card.tsx`;
`frontend/client/src/v2/AfterRunReport.tsx` (Summary tab); v2 spec `07`/`12`/`14`.

---

## Problem 3 — The Reproducibility (replication) record tab

**Observed.** Its content and layout were improvised in code rather than designed —
plain, unclear, and it competes with the other after-run content.

**Design question.** Per the v2 decision, after-run has **three tabs: Summary / Outputs
/ Reproducibility record**, and the reproducibility record holds **Methods, resolved
Parameters, Software, Citations, QC audit, Trajectory as expandable sections**. How
should those sections be laid out and styled so the record reads as one clean,
audit-grade document (and how do the immutable run-original + the reproducibility bundle
download fit, per Spec 12 — without implying ask-to-edit/versioning is live yet)?

**Pointers.** `frontend/client/src/v2/AfterRunReport.tsx` (MethodsTab and the record
sections); v2 spec `07 The workflow panel.html` (§ after-run), `12 Reports as editable
files.html`.

---

## Problem 4 — Overall neatness & consistency

**Observed.** The product has accumulated **inconsistent, cluttered, mismatched
elements** across surfaces (uneven spacing/typography, plain cards next to designed
ones, redundant chrome). The main workflow panel is polished; stepping off it feels
inconsistent.

**Design question.** A **consistency pass**: what are the canonical card / table /
badge / tab / empty-state patterns, and where do current surfaces deviate? Produce a
short written **"neatness spec"** (the patterns + the deviations to fix) Claude Code can
apply surface by surface.

**Pointers.** v2 spec `00 Foundations and the cold start.html` (tokens, status
vocabulary) and the whole `spec/` set; the current components under
`frontend/client/src/components/` and `frontend/client/src/v2/`.

---

## Missing detailed UIs beneath the top-level design

The v2 spec defines the **top-level surfaces**; the **detailed components below them are
missing or marked unbuilt**. These are the ones the drug-dev tutorials need. For each I
state **what's needed (states / data / behaviour)** — Design specs the visual.

### Problem 5 — Molecular evidence-class viewers (shared primitives, every molecular task)
Spec names these but marks figure previews "thumbnails only / full viewer unbuilt." They
are the Structure/Figure/Table **instances for molecules**, reused across d2–d7 + drug-dev:
- **3D structure** with a **linked per-residue confidence (pLDDT) chart + pairwise-error
  heatmap** (fold predictions); low-confidence regions named in words.
- **Docking pose** viewer — pose shown **with its score**; pose plausibility distinct from score.
- **2D molecular depiction grid** (candidate sets; toggle with the ranked table).
- **ΔΔG network/edges** — each edge carries **± SEM**; cycle-closure shown.
- **Multi-objective bars** — per-objective, each keeping its own units/target; **hard
  safety gate, no blended score**; rejected candidates stay visible with the reason.
- **QC-gate metrics** render — measured vs threshold, verdict.
**Design question:** for each, what does it show, what **states** (confident / low-
confidence / out-of-domain / **censored `> 30 µM`** / held), and what interaction
(hover/click → source output)? **Pointers:** spec `03 §3.8`, `05 §5.5`, `14`;
`frontend/client/src/components/step-output-preview.tsx`.

### Problem 6 — Per-domain run-card step detail (drug-discovery + training)
Spec 13: *only the transcriptomics run has fixtured step-level detail; design/training is
an open item.* Needed: the **canonical step rows** (step name, tool+version, two headline
params, outputs, status) for ADMET, docking, FEP, generative, stability, novelty, and the
training run — so each run card isn't empty. **Design question:** what are the step rows
per domain? **Pointer:** spec `13 Run cards by domain.html`.

### Problem 7 — QC-gate card + auto-loop remediation card
The gate **halt card** (measured / threshold / verdict, evidence level) + the **before→after
remediation diff** + three actions (apply / keep my parameters / cancel) + the retry cadence
(3 attempts, review window, on by default). Spec 07 describes it in prose only. **Design
question:** the detailed states (pass / advisory / halt / regulatory-halt-no-tweak) and
layout. **Pointers:** spec `07` (§ gate); `frontend/client/src/components/auto-loop-panel.tsx`.

### Problem 8 — The continuous-loop campaign object (Models → Rounds)
Per the architecture note (`…CAPABILITY_DEMOS_INFOFLOW_FOR_CLAUDE_DESIGN.md` §2): the
Rounds track as a **durable, persistent campaign** spanning weeks. Needed states: the round
timeline (**Proposed → Ordered → At the bench → Results in → Refit**); **"waiting on the
world"** (day-count + expected return + notify-on-land, never a spinner); order sheet +
plate map; intake with **censored / partial / no-data** rows; refit → **new model version**
(supersede, not delete). Spec 03 §3.7 is detailed in prose but marked "new." **Design
question:** the detailed layout + states for a long-lived campaign object (not a run page).
**Pointers:** spec `03 §3.2.3/§3.6/§3.7`; `frontend/client/src/components/models/models-panel.tsx`.

### Problem 9 — Target-ID evidence answer (ranked-entity variant)
A variant of the search/evidence answer: a **ranked target table with tier / conflict /
veto badges + per-channel provenance chips + a boundary note**. The evidence-answer surface
exists (`lit_evidence`) but not this ranked-entity form. **Design question:** how to render
ranked entities with multi-source provenance + an honest boundary within the evidence
answer. **Honesty:** it ranks *by OpenTargets* (no fusion win) — frame as corroboration, not
a ranking claim. **Pointers:** spec `01`/`09`; `data_centroid_design_v2/dataui/SearchAnswer.jsx`.

---

## What I need back from Claude Design
For each problem: a **written design spec** (regions, states, what's folded vs shown,
the patterns and tokens to use), clear enough to implement directly — not a single
rendered screen. I'll implement from the spec and keep the data honest (real identities,
real sources, live-vs-aspirational flags).
