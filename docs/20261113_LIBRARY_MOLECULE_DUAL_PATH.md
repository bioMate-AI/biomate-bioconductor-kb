# 2026-11-13 — Library / molecule-design dual path

## Requirement

Both paths must work; do not force one or the other:

1. **Step-by-step** — task-by-task single workflows (`workflow_type:'pipeline'` +
   `pipeline_steps`). Do **not** invent / index ad-hoc compositions as catalog
   mega-chains.
2. **Mega-chain** — when a **real** `workflow_chains` row matches the intent,
   honour that curated chain (hasProposal / panel rebind intact).

## How each path is selected

Selector: `selectLibraryMoleculeRouting` / `applyLibraryMoleculeDualPath` in
`frontend/server/library-triage-sequential.ts`, applied after `analyzeIntent` in
`galaxy-assistant.ts`.

| Condition | Path | Result |
|---|---|---|
| Classifier `chain_hint` is a known library-related catalog chain **and** the current message supports it (and synthesise-now/park only if the slug is named in text) | **catalog mega-chain** | Decomposition with `chainHint=<name>`, `skipPipelineCollapse=true` (blocks Tier-1 Admet collapse), Tier-2 `_curatedChainResponse` builds curated card |
| Message fingerprints a real chain (e.g. “ADMET first then dock” → `drug_discovery_admet_gated_screening`) and is **not** synthesise-now/park | **catalog mega-chain** | Same as above |
| `isLibraryTriageRequest` (synthesise-now/park **or** triage+library) with **no** catalog match | **sequential step-by-step** | Docking → ADMET → pharmacophore intents, `chainHint=null`, Tier-2 no-ops, Tier-3 resolves each ordinary workflow independently |
| Neither | *(none)* | Leave normal `analyzeIntent` routing alone |

Known catalog chains (never invent new names):
`drug_discovery_admet_gated_screening`, `drug_discovery_screening`,
`admet_to_cipa_cardiac`, `target_to_lead_full`, `andv_inhibitor_track_v1`.

## Gating fixed

- Previous override **always** forced sequential + `chainHint=null` for any
  library-triage phrasing, which could steal catalog-matched screening intents.
- `skipPipelineCollapse` previously also **skipped Tier-2**. It now only skips
  Tier-1 single-workflow collapse; Tier-2 still runs when `chainHint` is set.

## FE presentation

`awaitsWorkflowInput` / `hasGeneratedWorkflow` already treat
`workflow_type` chain|pipeline and non-empty `pipeline_steps` / `chain_steps` as
proposals (including `needs_user_feedback`), so both paths rebind the panel.

## Prose ↔ payload

- Sequential path: multi-step prose over `pipeline_steps` of real single workflows.
- Mega-chain path: prose names the curated chain display name + its steps.
- Single orphan Admet Pred still gets `singleWorkflowGroundingDirective` when
  that is the sole bind.

## Tests

`frontend/server/library-triage-sequential.test.ts` — dual-path selection,
both decompositions, grounding quiet on pipeline payloads, hasProposal for
sequential + curated chain cards.

## Out of scope

- Do **not** add a new `workflow_chains` row for “Library Triage…”.
- Ranking / synthesise-now vs park integrator still deferred (no misuse of 12814).
- No `sync_to_dev` from this session (another agent owns deploy).
