# Claude Design — Hand-off Manifest (2026-10-23)

Everything to give Claude Design for the drug-dev tutorials + UI work. Base path:
`/Users/kky/biomate-review/`. **Read Group A first** (the requirements), using Group D
as the design source of truth and Group B as the current state to improve on.

Governing principle (A1 expands it): design the **SYSTEM** (composable primitives +
patterns + exemplars + quality bar), not a UI per use case — the harness + LLM compose
each response from the primitives. No per-task/per-use-case templates.

**Two halves of the generative direction** (read together): **Design** owns the finite
part — the block primitives + design system (Group A1). **The harness/LLM** owns the
infinite part — composing each response from those primitives, specified in the
engineering counterpart `docs/20261023_GENERATIVE_RESPONSE_COMPOSITION_ARCHITECTURE.md`
(the block catalog Design's primitives must satisfy, the compose→render→validate gate).
Design reads it for context on how its primitives get used; it is not a Design task.

> **2026-10-24 UPDATE:** A parallel engineering pass (PR #298, branch
> `codex/qc-assessment-findings`) shipped a first production slice of Problem 1 + the
> QC-vs-execution semantics, and the user accepted a set of decisions that **supersede**
> conflicting older proposals. Read **Group A0 first** — it is the current, binding state;
> the Group A requirement docs below remain valid as background except where A0 overrides.

---

## A0. Current authoritative state (2026-10-24) — read before Group A
These live on branch `codex/qc-assessment-findings` (PR
[#298](https://github.com/bioMate-AI/biomate/pull/298)); pull the branch or read them there.
1. `docs/20261024_CLAUDE_DESIGN_TAKEOVER.md` — **the binding brief now.** Latest accepted
   decisions, the Problem 1–9 delivered/remaining table, fixtures, the portable
   completed-response preview, and the next deliverable (Problem 2). Supersedes conflicting
   older proposals in Group A.
2. `docs/20261024_WORKFLOW_RESPONSE_DESIGN_SPEC.md` — the current response specification
   (the coherent-thread resolution for Problem 1).
3. `docs/20261024_DESIGN_HANDOFF_EXECUTION_PLAN.md` — execution plan / sequencing.
4. `docs/20261024_CROSS_WORKFLOW_QC_GATE_AUDIT.md` — QC-gate semantics across workflows
   (what is a finding vs. a real enforced hold).
5. `docs/20261024_CLAUDE_CODE_TAKEOVER.md` — engineering inventory (what PR #298 changed,
   validation, what remains). Context for the data contract, not a Design task.
6. Preview: `docs/design/20261024_workflow_response_preview.html` (+ `_fragment.html`) —
   openable completed-response preview; supersedes the older paused/exclusion mockup. It is
   simulated, not a production screenshot; source-file views are excerpts.

The `docs/20261023_UI_DESIGN_PROBLEMS_FOR_CLAUDE_DESIGN.md` brief in Group A now carries a
2026-10-24 status block at its top mirroring these decisions and the problem-state table.

---

## A. Requirements (this session) — read in this order
1. `docs/20261023_UI_DESIGN_PROBLEMS_FOR_CLAUDE_DESIGN.md` — **primary brief.** The
   design-the-system framing + 9 concrete needs (chat flow, findings, reproducibility
   tab, neatness, molecular evidence-class viewers, per-domain run-card steps,
   QC-gate/auto-loop card, continuous-loop campaign object, target-ID answer). States
   *what's needed* (states/data/behavior), not visual solutions.
2. `docs/20261023_DRUGDEV_TUTORIAL_INFOFLOW_FOR_CLAUDE_DESIGN.md` — the **9 workflow use
   cases** (d1–d7, drug-dev, b1): input→intermediate→output mapped to v2 surfaces, with
   §3A **literal worked-example data** (real run values for d2/drug-dev; the decks'
   illustrative values elsewhere; d5/d6/d7 flagged thin) and §3B findings-as-a-problem.
3. `docs/20261023_CAPABILITY_DEMOS_INFOFLOW_FOR_CLAUDE_DESIGN.md` — the **4 capability
   demos** (dry loop · dry→wet loop · target-ID · adaptive intelligence), each routed to
   an existing category (no custom UI), plus **§2 the continuous-loop campaign object**
   architecture note.
4. `docs/20261023_ML_DL_CAPABILITY_MAP_FOR_UI_ENRICHMENT.md` — the **ML/DL platform +
   Galaxy ML toolset** capability map with honest wiring status (for the Models/training
   surfaces).

## B. Current HTML tutorials (the state to improve; source of the worked-example data)
Fully renderable offline = the deck HTMLs + the CSS + the two `assets/` dirs.
- 6 v2-design decks (EN + `.zh.html` in each folder):
  - `reference/claude_design/tutorials_v2_design/d1-qsar-classical-ml/d1-qsar-classical-ml-walkthrough.html`
  - `reference/claude_design/tutorials_v2_design/d2-admet-deep-learning/d2-admet-deep-learning-walkthrough.html`
  - `reference/claude_design/tutorials_v2_design/d3-generative-lead-design/d3-generative-lead-design-walkthrough.html`
  - `reference/claude_design/tutorials_v2_design/d4-binding-free-energy/d4-binding-free-energy-walkthrough.html`
  - `reference/claude_design/tutorials_v2_design/drug-dev/drug-dev-walkthrough.html`
  - `reference/claude_design/tutorials_v2_design/b1-train-custom-model/b1-train-custom-model-walkthrough.html`
- Shared CSS (linked as `../_v2lib.css`): `reference/claude_design/tutorials_v2_design/_v2lib.css`
- Images: `reference/claude_design/tutorials_v2_design/assets/` (`live/*.png` + `biomate-logo.png`)
- 3 older-dir decks (EN + `.zh.html`; self-contained, inline CSS; off-v2-design — rebuild target):
  - `reference/claude_design/tutorials/d5-molecular-docking-walkthrough.html`
  - `reference/claude_design/tutorials/d6-novelty-fto-walkthrough.html`
  - `reference/claude_design/tutorials/d7-accelerated-stability-walkthrough.html`
  - Images: `reference/claude_design/tutorials/assets/`

## C. Narrations (vetted content grounding — every number traces to a real source)
- `reference/claude_design/tutorials_v2_design/narration/{d1-qsar-classical-ml,d2-admet-deep-learning,d3-generative-lead-design,d4-binding-free-energy,drug-dev,b1-train-custom-model}.en.md` (+ `.zh.md`)
- `reference/claude_design/tutorials/{d5-molecular-docking,d6-novelty-fto,d7-accelerated-stability}-narration.md` (+ `.zh.md`)

## D. Design source of truth — data-centroid v2 (Design's own reference)
- `reference/claude_design/data_centroid_design_v2/SIMPLIFICATION_DECISIONS.md` — the canonical design decisions.
- `reference/claude_design/data_centroid_design_v2/spec/*.html` — 15 spec pages; most relevant:
  `00 Foundations and the cold start`, `03 Models`, `05 Design and generate`,
  `07 The workflow panel`, `08 The full step view`, `10 Worked examples - model use cases`,
  `12 Reports as editable files`, `13 Run cards by domain`, `14 Panes and output previews`.
- `reference/claude_design/data_centroid_design_v2/dataui/` — the React prototype components.

## E. Format reference (how to write a handoff)
- `reference/claude_design/research_agents/HANDOFF_RESEARCH_AGENT_UI.md`
- `reference/claude_design/research_agents/Demo Narratives.md`

## F. Current UI components (what exists in code, for the "what to improve" pointers)
- `frontend/client/src/components/nextflow-workflow-viewer.tsx` — workflow panel
- `frontend/client/src/v2/AfterRunReport.tsx` — after-run (Summary/Outputs/Reproducibility)
- `frontend/client/src/components/findings-card.tsx` — findings card (the weak spot)
- `frontend/client/src/components/step-output-preview.tsx` — output/evidence previews
- `frontend/client/src/components/chat-with-artifacts.tsx` + `chat-message.tsx` — chat + panel
- `frontend/client/src/components/auto-loop-panel.tsx` — QC gate / remediation
- `frontend/client/src/components/models/models-panel.tsx` — Models (Train/Rounds/Registry)
