# Generative Response Composition — Architecture

**Date:** 2026-10-23
**Purpose:** the engineering direction behind "the harness + LLM **compose** the
response from primitives" (not per-workflow templates). This is the counterpart to the
Claude Design handoff: Design owns the **finite** primitives + design system; this doc
is how the **infinite** part (the actual response) gets composed and rendered safely.
See `feedback_llm_composes_response_from_primitives` and the handoff manifest
`docs/20261023_CLAUDE_DESIGN_HANDOFF_MANIFEST.md`.

Grounded in an audit of the live pipeline (file:line below are from that audit).

---

## 1. Current state (honest)

BioMate today is **rule-routed + per-workflow-templated, not LLM-composed**:
- The LLM emits **free text + tool calls + a few fixed-schema JSON payloads** (intent
  decomposition; findings JSON). **It never emits a UI layout.**
- Which card/figure/panel appears is decided by **hardcoded branches**:
  `inferActionsFromType()` maps an LLM label → boolean action categories
  (`galaxy-assistant.ts:1457-1507`); `chat-message.tsx:803-1126` is a metadata `switch`
  → fixed React cards; `resolveViewer(ext)` picks a viewer by **file extension**
  (`step-output-preview.tsx:99-115`); findings use a **fixed** `{summary, key_results,
  figures}` schema and a closed `FindingsFigure = bars|composition|qc` enum.
- Per-workflow templates (`output_analyzer.py`, `preProcessForFindings`) and name-regex
  branches decide content. This is the brittleness the product keeps hitting.

## 2. What's already built (the good news — reuse, don't rebuild)

The hard, safety-critical parts exist; they're just bound to fixed templates:
- **Artifact/viewer resolver** — `resolveViewer(ext)` → ~13 viewer kinds incl.
  domain charts (`PlddtChart`, `PaeHeatmap`, `HitGrid`, `DensityMapViewer`, VCF/BED
  tables, 3Dmol structure, table, sequence tracks) (`step-output-preview.tsx:24-35,99-115`).
- **Grounded-number guardrails** — every finding number must appear verbatim in outputs
  or is dropped (`routes.ts:14773-14783`); `source_file` must name a real sampled file
  or is stripped (`:14784-14794`); fabricated citations deleted (`:14798`); **findings-
  as-links** so a number opens its source (`findings-card.tsx:56-95`); figures inherit
  `source_file` only when metrics agree (`findings-figures.ts:8-9,31-34`).
- **Provenance substrate** — output-file manifest `GET /api/workflows/runs/:id/output_files`
  `{name,path,s3,ext,step,size}`; findings `/findings`; QC events `/qc-events`; software
  `/software`; methods `/methods-report`; checksums (`cloud_data_reference.py:60-88`).
- **Hide-when-empty / named-objects-only** discipline across `AfterRunReport.tsx` hooks.

So the viewers, the grounding validators, and the provenance are done. **The missing
piece is only the indirection layer** that lets the model choose and fill them.

## 3. Target architecture — the indirection layer

```
run outputs + context + provenance
        │
        ▼
   LLM composes  ──►  blocks: Block[]     (the composition — what to show, in order, with which data)
        │
        ▼
   Harness render+validate layer
        │   • resolve each block → a registered primitive component
        │   • GATE on guardrails (every outputRef/number must trace to a real artifact; else drop/repair)
        │   • pick the viewer via the (semantic) resolver
        ▼
   Design-system primitives render   (Table / Figure / Structure / Report / Log / …)
```

### 3a. The block catalog (composition vocabulary — the finite, designed part)
A stable, versioned catalog of blocks, each = a **design primitive + a typed data
contract + one registered renderer**. Built from the existing raw material (the
`ViewerKind` union, the `FindingsFigure` union, the FindingsCard sub-sections), unified
and made addressable by the model. Starting set:

| Block | Data contract (all carry `source` provenance) | Renders via |
|---|---|---|
| `prose` | markdown (numbers linkify to sources) | ReactMarkdown + `linkifyFindings` |
| `keyResult` | `{entity?, metric, value, interpretation, source}` | key-result row (entity-aware) |
| `table` | `{columns, rows, source}` | `InlineTableViewer` |
| `figure` | `{kind: bars\|composition\|qc\|curve\|heatmap\|…, data, source}` | the chart registry |
| `structure` | `{path, ext, confidence?, source}` | 3Dmol + `PlddtChart` + `PaeHeatmap` |
| `outputRef` | `{path, ext, step, source}` | `resolveViewer` → the right viewer |
| `callout` | `{severity, title, body, source?}` | verdict/alert (safe / HALT / boundary) |
| `citation` | `{title, id, url}` | citation row |
| `report` | `{markdown, versioned}` | Report/Document viewer (Spec 12) |

Design's job (handoff) = the **visual** of each primitive + the design system; this
catalog is the contract between the model and those primitives.

### 3b. The composition format (what the LLM emits)
Add one field — `blocks: Block[]` — to the response (alongside, then replacing, the
fixed fields in `GalaxyAssistantResponse` `galaxy-assistant.ts:1560-1645`). The LLM
authors the ordered block list; it does **not** author HTML/CSS. Each block is one of
the catalog entries with its typed data. This replaces the hardcoded cascade in
`chat-message.tsx` and the fixed tabs in `AfterRunReport.tsx` with **one renderer that
walks `blocks`**.

### 3c. The harness render + validate layer (the gate)
The validators already exist — **re-wire them from per-template to a gate on arbitrary
composed output**:
- every `outputRef`/`source` must resolve to a real run artifact (reuse the
  `output_files` manifest + `run-access.ts`/`output-access.ts` auth);
- every numeric claim must trace to a sampled number (reuse `outputNumbers`
  `routes.ts:14773-14783`); unresolved → drop or send back for repair;
- the viewer is chosen by the resolver (reuse `resolveViewer`), not by the model;
- no fabricated citations (reuse the existing strip).
The LLM's freedom is **bounded by this gate**, not by a script. A block that fails the
gate is removed or regenerated — the model can be creative in *composition*, never in
*provenance*.

### 3d. Semantic evidence-class resolver (Spec §14.2)
Replace extension-only resolution with the scientific kinds the model names — **Table /
Figure / Structure / Report / Log / Document / Model** — mapped by the harness to
viewers. Adds the `document` (versioned, edit-in-place, Spec 12) and `model artefact`
classes the spec promises but code lacks.

## 3e. Relevance — the composition is conditioned on intent + task + pattern

The provenance gate (3c) makes a response **truthful**; it does not make it **relevant**.
Relevance is a first-class **input** to the composer, not an emergent property — the
response must *answer the user's question*, not render every output.

The composer is conditioned on three inputs beyond the raw outputs:
1. **User query / intent** — specificity and focus follow the ask. "Is terfenadine
   safe?" foregrounds the one verdict; "screen these" gives the overview.
2. **Task + workflow pattern** — the pattern decides what the *answer* is and what leads:
   QC-gated screen → the **gate verdict + liabilities**; generative loop → **ranked
   candidates**; prediction → **metric vs its floor**; DMTA round → **predicted-vs-
   measured**. (Ties to the pattern-router / workflow-pattern taxonomy.)
3. **Outputs + provenance** — the material, **filtered and ordered** by (1) and (2),
   never dumped.

**The regression risk this guards against:** today's per-workflow templates
(`output_analyzer.py`) *implicitly* encode relevance — each already knows its workflow's
answer and shows it. A generative layer that renders all outputs would **lose** that. So
intent + task + pattern are explicit composer inputs, and the **quality bar includes
relevance** — *answers the intent · foregrounds the task's key result · follows the
pattern* — alongside the honesty guardrails. The migration A/B (section 4) must check
relevance, not only that nothing was fabricated: the composed response should answer the
query **as well as or better than** the template it replaces.

Full pipeline: **select & order for relevance (intent + task + pattern) → compose blocks
→ gate for honesty (provenance) → render through exact primitives.**

## 4. Migration path (incremental, low-risk)

1. **Start at the result presentation** (highest value, most templated): introduce the
   block catalog + `blocks` field for the **after-run result**; have the LLM compose the
   result from the real outputs + provenance; render via the walker; gate with the
   existing validators. Retire `output_analyzer.py` + `preProcessForFindings` +
   `FindingsCard`'s fixed table + the `FindingsFigure` enum behind a flag.
2. **Then chat cards**: move the `chat-message.tsx` metadata switch to the block walker;
   keep the fixed cards as registered renderers during transition.
3. **Then the data-plane**: promote `run_code`-produced figures/tables to real artifacts
   with provenance (today they die in a stdout `CodeExecutionBlock`), so the composer can
   reference them as `figure`/`table` blocks.
4. Keep every step **flag-gated** and **A/B against the templated path** (honesty +
   legibility must not regress).

## 5. Division of labor

**The line: content/structure is composed; visual styling is design-exact.** The LLM
composes **what** to show and **in what order** (block kinds + data + sequence). The
**visual** of every block — color, font, spacing, tokens, component look — lives in the
design-system primitive and is used **exactly**; neither the LLM nor the harness invents
or overrides styling. So composition freedom is *structural*, never *aesthetic*.

- **Claude Design:** the exact visual of each block primitive (color/font/spacing/tokens)
  + the design system + 2–3 exemplars of a well-composed response + the quality bar.
- **Harness (Claude Code):** the block catalog + the `blocks` schema + the render+validate
  walker + the semantic resolver + the data/provenance plumbing (mostly re-wiring what
  exists) + the migration flags. **Renders each block through its design primitive
  as-is; sets no colors/fonts/spacing.**
- **LLM:** composes the ordered blocks from the real outputs + context + provenance,
  guided by principles + exemplars — content and structure only.

**"design = source of truth" has two scopes:**
1. **Visual (color / font / spacing / tokens / component look): follow design EXACTLY.**
   Claude Code is weak here and must not improvise.
2. **Functional coverage: design is the reference but does not exhaust use cases.** Where
   a required function/response is not covered, the harness/LLM compose it — but still
   render it through the design's exact visual primitives.
**When a needed primitive / token / reference is missing from design, POINT IT OUT and
design provides a reference — never fill the visual in ad hoc.**

## 6. Guardrails (non-negotiable)
The model composes; it never invents. Every number traces to a sampled output; every
block's `source` resolves to a real, authorized artifact; viewers are resolver-chosen;
citations are real; unresolved → dropped/repaired. Honesty is enforced by the gate, so
composition freedom can be wide without risking fabrication.

## 7. Prior art — and why BioMate tailors it

The mainstream pattern in other harnesses is the one here, which validates the approach:
- **Tool-call → pre-built component** (Vercel AI SDK "Generative UI" / `streamUI`): model
  picks a component via a tool call; design owns the visual. ≈ our block ≈ tool-call.
- **Declarative card schema** (Microsoft Adaptive Cards): model emits declarative JSON;
  host renders in host-native styling. ≈ our `Block[]`.
- **Schema-constrained structured outputs** (OpenAI/Anthropic structured outputs / tool
  use): model fills a typed schema the app validates. ≈ our typed Block contracts + gate.
- **Code → artifacts** (Code Interpreter / notebook agents): compose by writing code that
  produces cells. ≈ our `run_code` data-plane path.
- **Grounded answers** (Gemini grounding, Perplexity): structured citations/provenance.
  ≈ our number→`source_file` gate.
- **Rejected anti-pattern** (websim / HTML-gen): the model authors raw HTML/CSS — owns
  aesthetics → inconsistent. Out by rule (LLM composes content/structure; design owns visual).

**Convergence:** everywhere the robust pattern is *the model emits a declarative, typed,
provenance-carrying structure that the host renders with its own design and validates* —
never the model authoring UI.

**Why BioMate's is tailored, not off-the-shelf:**
1. **Scientific vocabulary** — blocks are evidence-class viewers (3D structure + pLDDT +
   PAE, docking pose, ΔΔG network, 2D depiction grid, QC-gate measured/threshold/verdict,
   multi-objective bars) with domain semantics (censored IC50, applicability domain,
   confidence) — not generic cards.
2. **Relevance keyed to workflow patterns** (§3e) — the "answer" is defined by the
   pattern (QC-gated screen / generative / prediction-vs-floor / DMTA). Generic harnesses
   have no equivalent.
3. **Stricter provenance bar** — every number → an output file; no bare predicted number;
   censored stays `>`; validated-vs-heuristic visible. Higher than "cite a web source."
4. **Two surfaces + two lanes** — chat thread vs. workflow panel/after-run; Instant vs.
   Cloud. Generic harnesses have one chat surface.
5. **The run is the substrate** — composition draws on a run's outputs/manifest/QC/steps
   (and `run_code`-produced artifacts), not just retrieved text.

Borrow the declarative-blocks + validate + render-through-design pattern; tailor the
vocabulary, relevance patterns, provenance bar, surfaces, and run-substrate to our science.

## Source index (audit)
- Response path: `frontend/server/galaxy-assistant.ts` (`:1457-1507`, `:1560-1645`,
  `:2785-2806`, `:2942-2965`); backend `backend/lib/galaxy/ai/{ai_assistant,intent_parser,
  pattern_router,output_analyzer,finding_reporter}.py`.
- Rendering: `frontend/client/src/components/chat-message.tsx:803-1126`;
  `frontend/client/src/components/step-output-preview.tsx:24-35,99-115`;
  `frontend/client/src/components/findings-card.tsx:56-95,254-318`;
  `frontend/client/src/v2/AfterRunReport.tsx:151-382,606-610,2241-2271`.
- Grounding/provenance: `frontend/server/routes.ts:14708-14834,14773-14798`;
  `frontend/server/findings-figures.ts`; `cloud_data_reference.py:60-88`.
- Spec: `reference/claude_design/data_centroid_design_v2/spec/14 Panes and output previews.html` §14.2.
