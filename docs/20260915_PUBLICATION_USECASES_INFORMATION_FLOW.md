# Publication use cases & the intuitive information flow (audit test spine)

**Date:** 2026-09-15
**Purpose:** Define the *intended* end-to-end information flow a researcher follows to finish **one publication**, expressed as concrete, runnable use cases. These use cases are the **test spine**: each stage handoff carries an explicit *linkage assertion* (what must stay referenceable/linked). The v2 UI gap audit is scored against these assertions — a gap is any place a use case's linkage assertion cannot be satisfied in the current UI.

All examples use **generic, standard public-style** material (illustrative datasets, textbook analyses). No collaborator identities, no specific lab/team framing, no private experimental data — only neutral public exemplars.

---

## Part 1 — The information-flow model (the spine)

Grounded in the `dataui/` reference (`App.jsx`): **the project is the container**, and everything a publication needs is a *persistent, referenceable object* scoped to that project. A chat may start unfiled; BioMate proposes a project from the first signal (attached data or a goal that matches a project's material).

### Object types (each has an immutable `id` and a `version`)

| Object | Created in stage | Carries | Back-links to |
|---|---|---|---|
| **Project** | (container) | standing instructions, capabilities, connectors, members | — |
| **Dataset/File** | ingest / output | quality verdict, schema/units, version | producing run + input versions |
| **Evidence answer** | 1 Literature | claims, external **citations**, caveat | the sources it cites |
| **Proposal / plan** | 2 Proposal | goal, hypotheses, referenced datasets + evidence, planned runs | evidence answers, datasets |
| **Run** | 3 Analysis | resolved inputs (by reference), params, QC decisions, trajectory | input dataset versions, proposal |
| **Output artifact** (Table/Figure/Structure/Report/Log) | 3–4 | the value it shows | its run + exact inputs + params |
| **Model** | 3 (Models) | training data, applicability, assessment | training dataset versions |
| **Report** | 5 Report | assembled artifacts, narrative, cited claims | every output + evidence it uses |
| **Manuscript** | 6 Manuscript | assembled reports/figures, sections | every report/figure/claim it embeds |

### Two invariants that make the flow "intuitive"

1. **Reference/attach everywhere.** Any object can be `@`-mentioned in the composer (`@counts.csv`, `@evidence:herg-liability`, `@run:admet-42`, `@fig:volcano`). The chip shows a human name but retains the immutable `id@version`. Before any operation the assistant **restates the resolved inputs and validates their roles/compatibility** (schema, units, coordinate system) and asks a *typed* mapping question only when a safe interpretation can't be inferred. `reference/attach` of project objects is distinct from `citation` of external literature.
2. **Every derived thing back-links to its sources.** A figure opens to its run; a run opens to its input dataset *versions* and the proposal; a report claim opens to the output and the literature it rests on; a manuscript paragraph opens to the report/figure it embeds. Reopening a link returns to the same object and its provenance — never a stale copy or a re-upload.

### The six stages (normal path stays small)

```
1 Literature survey → 2 Proposal → 3 Data analysis (run) → 4 Viz & analysis → 5 Report → 6 Manuscript
        │                  │                │                     │              │            │
     evidence           proposal            run               artifacts        report     manuscript
     answer  ──@ref──▶   object  ──@ref──▶  object ──produces▶  (Table/Fig) ──assemble▶ (editable) ─assemble▶ (export)
        └──────────────── every downstream object back-links to every upstream source ───────────────┘
```

Per accepted simplifications: after a run the surface is **three tabs — Summary, Outputs, Reproducibility record** (methods/params/software/citations/QC/trajectory live *inside* the record). Output names are **Table, Figure, Structure, Report, Log**. Lane selection is automatic and explained; switching is Advanced.

---

## Part 2 — Use cases (one per module, each a full publication arc)

Each use case lists: the researcher's goal, the six-stage walk, the objects produced, the `@`-references used, and the **linkage assertions to test**.

### UC-1 — Differential expression study (Data analysis module)

*Publication shape:* "Treatment X changes expression of pathway Y in tissue Z" — a standard bulk RNA-seq DE paper.

| Stage | Researcher action (intuitive) | Objects & links |
|---|---|---|
| 1 Literature | "What's known about pathway Y regulation under treatment X?" → evidence answer with grounded citations; **Save to project**. | `evidence:pathwayY` (cites external papers) |
| 2 Proposal | "Draft a plan: test whether X shifts pathway Y, using `@counts.csv` and `@design.tsv`, grounded in `@evidence:pathwayY`." | `proposal:UC1` → refs evidence + 2 datasets |
| 3 Analysis | "Run differential expression from the proposal." Assistant **restates inputs** (counts v3, design v1; contrast treated_vs_control; FDR 0.05) and validates the design table matches the counts columns before launching. | `run:de-1` (inputs bound by version) → back-links to proposal + dataset versions |
| 4 Viz & analysis | Open Outputs: **Table** (DE results), **Figure** (volcano, heatmap). "Highlight pathway Y genes on the volcano." Each figure opens to `run:de-1` and its exact inputs/params. | `fig:volcano@de-1`, `table:de@de-1` |
| 5 Report | "Generate a report from `@run:de-1`; discuss results against `@evidence:pathwayY`." Report embeds the volcano/heatmap/table as **linked** artifacts and cites both the outputs and the literature. | `report:UC1` → back-links to run outputs + evidence |
| 6 Manuscript | "Start a manuscript; use `@report:UC1` for Results and `@fig:volcano` as Figure 1." Export DOCX/PDF; every figure/claim still links to its source. | `manuscript:UC1` → embeds report + figures |

**Linkage assertions (test):**
- L1 An evidence answer can be **saved** and later `@`-referenced in a proposal, run request, and report.
- L2 The proposal references dataset **versions**; the run consumes *those same versions* with no re-upload.
- L3 The assistant restates resolved inputs + validates design↔counts compatibility before the run.
- L4 Each figure/table opens back to `run:de-1` → its input versions + params.
- L5 The report cites both an output artifact and the step-1 evidence, each as a live back-link.
- L6 The manuscript embeds the report/figure with links intact; export preserves the provenance.

### UC-2 — Small-molecule lead triage (Design & generate module)

*Publication shape:* "A prioritized series with predicted ADMET and rationale" — a med-chem triage/SAR note.

| Stage | Action | Objects & links |
|---|---|---|
| 1 Literature | "Known hERG liabilities for scaffold S?" → evidence answer; save. Optionally promote a claimed chemical space to an **exclusion**. | `evidence:herg-S` |
| 2 Proposal | "Prioritize `@series-4.smi` for oral exposure with hERG as a safety gate, excluding claims in `@evidence:herg-S`." | `proposal:UC2` → refs SMILES set + evidence |
| 3 Analysis | Run generate→predict→optimize→rank in one run; assistant restates the seed set, envelope, and gate before launching. | `run:admet-2` → outputs |
| 4 Viz & analysis | Outputs: ranked **Table** with per-objective values + confidence, held-out-of-domain marked; **Figure** (Pareto, on demand); depiction grid. | `table:shortlist@admet-2`, `fig:pareto@admet-2` |
| 5 Report | "Report the shortlist with rationale; cite `@evidence:herg-S` for the safety rationale; attach the order sheet." | `report:UC2` → outputs + evidence + order sheet |
| 6 Manuscript | Assemble SAR narrative referencing the shortlist table and rejection reasons. | `manuscript:UC2` |

**Linkage assertions:** as L1–L6, plus:
- L7 An evidence claim can be **promoted to a run constraint** (exclusion) and that provenance is recorded on the run.
- L8 A shortlist row links to its predicting **model + version** and (when available) the nearest measured analogue.

### UC-3 — Germline variant study (Data analysis / genomics)

*Publication shape:* "Variant catalog and candidate prioritization from short-read WGS."

| Stage | Action | Objects & links |
|---|---|---|
| 1 Literature | "Reported pathogenic variants in gene G?" → evidence; save. | `evidence:geneG` |
| 2 Proposal | "Call germline variants on `@sample.fastq` against GRCh38, then annotate and filter to gene G." | `proposal:UC3` |
| 3 Analysis | Run sarek-style pipeline; assistant restates reference build + read layout + sample sheet before launching; live SSE step transitions. | `run:wgs-3` → VCF outputs |
| 4 Viz & analysis | Outputs: VCF **Table** preview, annotation **Table**, coverage **Figure**; open a variant to its supporting reads. | `table:vcf@wgs-3` |
| 5 Report | Report the filtered variants, cite `@evidence:geneG` for interpretation. | `report:UC3` |
| 6 Manuscript | Methods auto-drawn from the reproducibility record; results reference the variant table. | `manuscript:UC3` |

**Linkage assertions:** L1–L6, plus:
- L9 The reproducibility record supplies a reusable **Methods** block the report/manuscript can embed (with software versions), rather than re-typed prose.

### UC-4 — Adapt & assess a property predictor (Models module)

*Publication shape:* "A project-adapted predictor and its held-out assessment."

| Stage | Action | Objects & links |
|---|---|---|
| 1 Literature | "Benchmarks for predicting property P?" → evidence; save. | `evidence:propP` |
| 2 Proposal | "Adapt the base P-predictor on `@assay-series.csv`; assess on a held-out split." | `proposal:UC4` |
| 3 Analysis | Train/adapt run; assistant restates the training set version + split policy; produces a **Model** object with an applicability region. | `model:P-adapted@1` → training data versions |
| 4 Viz & analysis | Assessment: calibration **Figure**, metric **Table** (on demand). Model object shows what it can/can't speak to. | `fig:calibration@model:P-adapted@1` |
| 5 Report | Report the model card + assessment; cite `@evidence:propP` for the benchmark comparison. | `report:UC4` |
| 6 Manuscript | Methods + model card embedded; the model is `@`-referenceable for reuse in UC-2's scoring. | `manuscript:UC4`; `model:P-adapted@1` reused by `run:admet-2` |

**Linkage assertions:** L1–L6, plus:
- L10 A trained model is a first-class object, `@`-referenceable in a later design/scoring run, and its outputs back-link to the model **version** used.

> Note: the accepted product override drops the *validated/project-adapted/heuristic* status **labels**; the underlying applicability/assessment information still lives on the model object. Absence of the label is intentional, not a gap.

### UC-5 — Finishing the publication as a team (collaboration + per-project rights)

*Publication shape:* a paper is finished by several people with different roles, not one user. This use case runs *across* UC-1…4 rather than beside them — every object above is shared under the project's membership, and every action is rights-checked.

| Role | Can | Cannot (control is disabled-not-hidden, and names the required role) |
|---|---|---|
| **Owner** | everything: invite/remove members, run, approve external/spend/publish gates, edit + publish reports/manuscript, manage instructions | — |
| **Editor** | run analyses, create/edit datasets, draft reports/manuscript, resolve QC overrides (recorded) | approve external transfer/order/spend or publish a shared record (→ "needs Owner") |
| **Viewer** | read every object + its provenance, download, `@`-reference in their own scratch | run, edit, or resolve any gate (each control shows "needs Editor/Owner") |
| **(future) Reviewer** | approve/deny the human-approval gate they're delegated | — |

Journey: the **Owner** invites collaborators (`/join/:token`) and assigns roles → an **Editor** runs UC-1's DE analysis and drafts the report → a **Viewer** opens the same run, figures, and reproducibility record read-only (run/edit controls disabled, each naming the role required) → an **external-transfer or publish** step (deposit data, publish the shared report/manuscript) **pauses at a human-approval gate that only the Owner can resolve**, recorded in the audit trail with name + reason.

**Linkage assertions (test) — L11–L14:**
- **L11** Every shared object (dataset, run, evidence answer, report, manuscript) carries its project's membership; a **stranger** gets 404 (not 403), a **member** resolves by role.
- **L12** A control the current role can't use is **disabled, not hidden**, and states the role required (no silent absence, no dead click).
- **L13** Approval gates for **external transfer / order / material spend / publishing or overwriting a shared record** route to the role that can resolve them and record who + why (QC overrides stay Editor-resolvable but recorded).
- **L14** Role is enforced **server-side per action** — the UI gate is a mirror of a real permission check, never the only guard (consistent with the closed IDOR/ownership model already in `output-access.ts` / `run-access.ts`).

---

## Part 3 — How these use cases test the UI

Each linkage assertion L1–L10 is a checkable behavior. The audit maps every assertion to the current component that should satisfy it and marks pass / partial / broken. The chain is only as strong as its weakest handoff — a single broken back-link (e.g. a figure that can't reopen its run, a chip that loses `id@version`) breaks the publication flow even if each stage works in isolation.

**Preliminary cross-references to audit findings (updated as auditors report):**
- **L2/L3 (restate + compatibility before run) — BROKEN (P0).** Composer audit: no "Inputs mapped" restatement/compatibility card; params render as a plain form. This is the single most load-bearing gap for the whole flow.
- **L1/L4/L5 (objects `@`-referenceable + back-links) — PARTIAL/BROKEN (P1).** Data chips carry a name only (no `id@version`), don't open the dataset object; outputs in the after-run report don't link back to source objects; `@`-mention is a modal browser, not inline resolution. Object identity holds *inside* `/files` but breaks across chat → run → report.
- **L7 (promote evidence → constraint) — BROKEN (P1).** Design audit: "From Search → exclusion" hand-off is navigate-only; no claim-to-constraint promotion.
- **L9/L6 (report/manuscript assembly with live links) — pending outputs/reports auditor.**
- **L10 (model reused downstream by reference) — pending models auditor.**

The stage-by-stage gap map (Part 4) and the designed remediation order (Part 5) follow, synthesized from an 8-way parallel audit of the current UI against `dataui/`.

---

## Part 4 — Stage-by-stage gap map (current UI vs `dataui/`)

Severity: **P0** = breaks the publication chain; **P1** = notable within a stage; **P2** = polish. "Intentional" = accepted simplification/override, not a gap.

### The connective-tissue chain (the answer to "where does it break?")

The single most important result: **object identity is well-modeled *inside* the Data Hub, but is not carried as a live, clickable reference across the surfaces that consume it, and the two artifacts the reference treats as first-class — the saved evidence answer and the plan — are demoted to text.** The chain breaks at the *handoffs*, in journey order:

| # | Stage / handoff | Assertion | Verdict | Root break |
|---|---|---|---|---|
| 1 | **1 Literature → save/reuse** | L1 | **P0** | Evidence answer saved as a project-notes **markdown blob** (`citation-panel.tsx` → `/memory/.../knowledge`), not an addressable `EvidenceAnswer(id, retrieval-record, citations[])`. Can't be `@`-referenced later. Live search path (`benchmark-evidence.tsx`) also has **no dedicated answer surface and no boundary** element; the rich answer anatomy exists but is **dead code** wired only to the workflow methods panel. |
| 2 | **2 Proposal** | L2 | **P1** | No plan/proposal **object**. `ideation-plan.tsx` is chat-message metadata only; `workflows` table has no `planId`. Runs can't cite the hypothesis that motivated them. |
| 3 | **3 Run — restate+validate inputs** | L3 | **P0** | The central "restate resolved inputs + validate schema/units/coordinate-system before running" card is **absent** on the live `nextflow-workflow-viewer.tsx`. `dataset-validation-dialog.tsx` is wired only to the legacy `workflow-artifact.tsx`; typed `clarify-card.tsx` exists but only in chat, not the run panel. Params render as a plain form. |
| — | **cross-cutting: one object everywhere** | L1/L4 | **P0** | The `DatasetObject` (`datasets/dataset-object.tsx` + `pages/data-hub.tsx`) is strong (versions/lineage/consumers/origin/RO-Crate), but every downstream **handle is inert**: composer chip is a tooltip only (`chat-input.tsx`), chat file pills and run/output/report chips don't deep-link back to it. Uploaded files use an **ephemeral timestamp id**, not an immutable `id@version`. `@`-mention is a modal browser, not inline resolution. |
| 4 | **4 Outputs → back-link + round-trip** | L4 | **P0** | Outputs link **forward** to `runId` only — no back-link to the exact **inputs+params**, no **"open as dataset →"** round-trip into Files. Number→source is a **heuristic string match** (`findings-card.tsx`), and the click-through (`onOpenOutput`) is scaffolding-only, not live end-to-end. No evidence-class badge. |
| 5 | **5 Report** | L5/L9 | **P0** | Report is a **transient view composite**, not a versioned object: edits save as a **local `.md`/DOCX download** and **sever the run link**; findings are copied as static prose; no `Claim → output+step` links in the body. Reproducibility record *does* supply a Methods block (L9 partial-OK). |
| 6 | **6 Manuscript** | L6 | **P0** | **Stage essentially missing.** Only the hard-coded IND pipeline (`ind-report.tsx`), whose numbers are **LLM prose with no run/output back-links**. No surface assembles arbitrary reports/figures/tables into a manuscript with live source links + export. |
| 7 | **Models reuse** | L10 | **P1** | Model object is first-class and well-built, but the worked `model-case.tsx` is **unrouted**, there's no "predicted column → model object" link in results, and reuse-by-reference downstream (a `model@version` scoring a design run) isn't surfaced. |
| 8 | **Evidence → constraint** | L7 | **P1** | "From Search → exclusion" hand-off is navigate-only; no claim-to-constraint promotion recorded on the run. |

### Per-module notable gaps (beyond the chain)

**Search & evidence** (P0/P1): no dedicated answer surface; **boundary element missing** (spec says always-present); retrieval-transparency, conflict rows, inline reference "marks", evidence table, locus, recency, source-reader, save-to-notes-with-answer, make-instruction all **exist but are dead on the live search path** (wired only to `workflow-artifact.tsx`). Follow-up buttons are a `console.log` no-op. Relevance scores shown on research answers (tension with the no-score rule). **Dominant fix = wiring, not construction.**

**Data analysis / Models** (P0/P1): **wet-lab return path (§3.7) entirely missing** from the Rounds track (P0); ad-hoc compute results lack a lane/sandbox chip, "show the code", and "save output to project"; Train track has no "new training run" config surface; pre-trained results don't distinguish published vs local spot-check. Model-status labels dropped = **intentional**.

**Design & generate** (P1): 2D **depictions are placeholders** (SMILES text, no rendered structure); **peptide/protein design captured but can't run** (honestly gated); entry-routes (dataset→series, model→re-score, Search→exclusion) and the wet-lab predicted-vs-measured intake are **stubs**; no patent-claim marking/exclude-by-default.

**Workflow / run panel** (P1): after-run is a **flat 8–9 tab strip**, not the accepted 3 tabs; **no Summary tab and no immutable "run original"**; typed clarify not in the panel; trajectory renders empty (no backend event feed); param provenance reduced to "recommended vs not" (no inherited/confirmed/edited origins); step view lacks prev/next traversal + the was→now cache-arithmetic re-run card; auto-loop toggle is inert ("coming soon"). Domain-adaptive run cards (spec 13) are a genuine strength.

**Output panes** (P1): **two divergent preview systems** — the after-run Outputs tab uses a weaker img/iframe/text overlay that **dead-ends `.csv/.vcf/.pdb`**, while `step-output-preview.tsx` (used elsewhere) renders them fully (13 kinds + 3Dmol/pLDDT). The primary post-run surface got the lesser previewer. No first-class "Report" output kind. Simple Table/Figure/Structure/Report/Log labels not used (implementation taxonomy exposed instead).

**Cold-start / shell** (P1): router route-box has **no "Start"/normalized-seed**; **no thin launcher / collapse** for returning users; **no project-scope line** on cold start; nav items carry subtitles (**violates the anchor-text rule**); **Connectors sits in primary nav** instead of Settings; `/capabilities` is an **off-spec marketing page** breaking the no-inventory rule; Instructions is a single free-text box (missing standing-instruction list / output templates / experts selector). Panes are collapse-only, not drag-resizable; sidebar fully hidden under 768px (forbidden). Connectors surface ships 2 of 4 kinds, no add-connector flow, no on-prem/mount/LIMS/warehouse/ELN sources.

### Honesty ledger (per CLAUDE.md — must not claim un-deployed capability)

**False working-capability claims to fix now (cheap, high-trust-impact):**
- QC prose asserts "content-addressed SHA-256 … tamper-evident manifest" (`AfterRunReport.tsx`) while the record's `sha256` fields are largely unpopulated. *(Note: the ADMET run now hashes 5/5 outputs — so this is populate-or-qualify, not remove.)*
- `tutorials.tsx` advertises run-report export as "DOCX, Markdown, or LaTeX" when only Markdown ships.
- Tour/tutorial copy promises "manuscript-ready export" that has no surface.

**Correctly honest (acceptable):** deferred report versioning / chat-edit-diff / file-tree presence are *not* claimed as working; the IND DOCX button is visibly disabled until backed — this is the pattern to follow.

### Intentional deviations (NOT gaps)
Model-status labels dropped (product decision); progress bar removed (2026-06-19 UX call); skip-phase control gated on missing backend API; sample-dataset badge is an addition; `v2/ResearchApp.tsx` is an unrouted prototype, out of scope.

---

## Part 5 — Designed remediation order (what unlocks the publication flow)

The flow is only as strong as its weakest handoff, so the fixes are sequenced by **how much of the chain each unlocks**, and each notes how much is *wiring existing code* vs new build.

1. **Shared object-reference primitive (`@ref` / live `DataChip`).** One clickable chip that resolves `id@version` and deep-links to the object's page, usable in composer, run slots, outputs, and reports. Unlocks the cross-cutting P0 and L1/L4. *Mostly wiring* — the `DatasetObject` page already exists; give uploaded files immutable versioned ids. **Highest leverage.**
2. **Pre-run restate + compatibility card (L3, P0).** Surface the "Inputs mapped" card on `nextflow-workflow-viewer.tsx`: restate each resolved input (name@version), validate schema/units/coordinate-system, ask a typed `clarify-card` question only when unsafe. *Wiring* `dataset-validation-dialog.tsx` + `clarify-card.tsx` into the live panel.
3. **EvidenceAnswer as an object + its two exits (L1/H1→2, P0).** Route real search results into the existing answer anatomy (`citation-panel.tsx`/`source-reader-pane.tsx`), add the always-present boundary, and add "Save as a document (→ Files, versioned)" and "Check against our data (→ run)". *Largely wiring dead code onto the live path.*
4. **Output → dataset round-trip + provenance back-link (L4/H3→4, P0).** On each output add "Add to project files / use as input"; record `derivedFromRun` + `usedInputs[]@version` + `resolvedParams`; make number→source a structured `Claim` map, not a string heuristic. Also unify on the stronger `step-output-preview.tsx` in the after-run Outputs tab.
5. **After-run 3-tab consolidation + immutable run-original (structural).** Collapse the 9 tabs into **Summary / Outputs / Reproducibility record** (nest Methods/params/software/citations/QC/trajectory inside the record); land on Summary; badge the run-original.
6. **Report as a versioned object with claim back-links (L5/H4→5, P0).** Generalize the IND persistence contract (`ind-report-api.ts` versions/snapshots — proven to exist) to generic run reports; embed outputs as linked artifacts with `Claim → output+step`; edit-by-asking with accept/reject diff.
7. **Manuscript assembler (L6/H5→6, P0).** A surface that references multiple Report/Figure/Table **objects** by id into a manuscript with live back-links and multi-format export.
8. **Plan/proposal object (L2, P1).** A `Plan(id, hypothesis, referenced datasets[], evidence[])` that runs record as `basedOnPlan` — enables "all runs under hypothesis X".
9. **Honesty fixes (immediate).** Populate or qualify the SHA-256 claim; correct the export-format and manuscript marketing copy to match what ships.

**Theme:** a large fraction of the highest-severity gaps are **wiring, not construction** — the correct components (dataset object, citation panel + source reader, validation dialog, clarify card, IND versioning) already exist but aren't connected to the live surfaces or promoted to first-class objects. The publication flow becomes coherent once (a) every object is a live clickable reference and (b) the evidence answer, the report, and the output-as-dataset are first-class objects rather than text/views.

