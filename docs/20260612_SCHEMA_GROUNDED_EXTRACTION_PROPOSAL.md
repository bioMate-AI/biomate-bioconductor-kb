# Schema-Grounded Parameter Extraction — Design Proposal

**Author:** session 2026-06-12
**Branch:** `worktree-schema-grounded`
**Status:** proposal, with offline probe demonstrating 13/13 success on tier-0 demos

---

## TL;DR

The current pipeline asks one LLM to extract "scientific parameters" with no knowledge of which workflow will run, producing keys like `target`, `disease`, `target_cells`. A second stage (`WORKFLOW_PARAM_ALIASES` in `frontend/server/galaxy-assistant.ts:716`) hand-translates those keys to each workflow's canonical names.

This is an O(N×K) table that grows with every workflow and every LLM word choice. Earlier this session I added three more alias rows to make tier-0 demos T02/T04/T05 pass — including a direction flip in `glp1_modality_bakeoff` that would have silently broken any caller relying on the previous mapping. That is the "fix the test, break the system" antipattern.

**Proposal:** replace the alias table with **schema-grounded extraction** — a second LLM pass that runs *after* routing has chosen a workflow, given the workflow's parameter schema verbatim. The LLM becomes the mapper; no per-workflow table required.

**Probe result (this session):** with a generic prompt template + parsed `.nf` params, Claude Haiku 4.5 extracted **13/13** expected keys across all 5 tier-0 demos. No aliases, no per-workflow tuning, ~$0.02 in API cost.

---

## 1. Problem

### Where it lives today

`frontend/server/galaxy-assistant.ts:716` defines `WORKFLOW_PARAM_ALIASES`:

```ts
const WORKFLOW_PARAM_ALIASES: Record<string, Record<string, string>> = {
  in_vivo_cart_codesign: {
    target: 'car_target', antigen: 'car_target', car: 'car_target', ...
    cell: 'delivery_cell', target_cells: 'delivery_cell', cells: 'delivery_cell', ...
    disease: 'indication', ...
  },
  glp1_modality_bakeoff: {
    indication: 'disease', condition: 'disease',  // ← direction flipped this week to pass T04
    ...
  },
  ...
};
```

`remapInlineParametersForWorkflow()` (~line 800) rewrites the keys of the LLM's first-pass `inlineParameters` to match `required_params`. Workflows not in the table pass through unchanged.

### Why it fails

1. **Every new workflow needs a hand-written block.** There are 2,463 workflows in the DB; the table covers ~13.
2. **Every new LLM phrasing reopens the bug.** `target_cells` vs `cells` vs `delivery_cells` vs `cell_type` — each variant is a separate row, and the LLM picks freely based on user wording.
3. **Direction flips silently break callers.** `indication → disease` vs `disease → indication` look symmetric but are not; whoever asserts on the "losing" key just regressed.
4. **Per-workflow context is duplicated.** The .nf file already declares `params.delivery_cell = 'T_cell'   // T_cell | NK_cell | macrophage`. The alias table re-encodes the same fact in a less rigorous form (no types, no enums).

### Root cause

The intent decomposer (system prompt at `galaxy-assistant.ts:3668`) emits `inlineParameters` *before* a workflow has been chosen. It has no way to know which key names the eventual workflow expects, so it makes them up from few-shot examples (`sequence`, `reads`, `hpo_term`, `phenotype`, …). The alias table exists to repair that mismatch one workflow at a time.

---

## 2. Proposed architecture

Add a third stage to the pipeline:

```
                     ┌──────────────────────┐
user message ───────▶│ 1. Intent decompose  │ (existing) — picks type, keywords,
                     └──────────────────────┘   workflow-agnostic raw params
                                │
                                ▼
                     ┌──────────────────────┐
                     │ 2. Routing           │ (existing) — selects workflow
                     └──────────────────────┘
                                │
                                ▼
                     ┌──────────────────────┐
                     │ 3. Schema grounding  │ ◀── NEW
                     │    (workflow-aware)  │
                     └──────────────────────┘
                                │
                                ▼
                          inlineParameters
                          (canonical keys)
```

Stage 3 input: `(userQuery, workflowDef)`. Output: `Record<canonicalKey, value>`.

### Stage 3 algorithm

For each param in `workflowDef.required_params ∪ optional_params`:

**(a) Rule-based first pass — zero LLM cost.**
- Direct hit: `raw[param.name]` exists → use it.
- Global synonym graph: small, shared table like
  ```ts
  const SYNONYMS = {
    indication: ['disease', 'condition', 'disease_area', 'therapeutic_area'],
    delivery_cell: ['cells', 'cell_type', 'target_cells'],
    car_target: ['target', 'antigen'],
    target_gene: ['gene', 'target'],
  };
  ```
  Applied as fallback only — schema-canonical keys always win.
- Unit conversions, boolean negations, enum normalization (`"T cells" → "T_cell"` when the param has an enum).

**(b) LLM resolver for what's left.** Build the prompt from the workflow's param block:

```
You extract scientific parameters for the workflow "<name>" from a user's request.

Extract values for ONLY these parameters (use the EXACT key names below;
omit any parameter the user did not mention or imply):

- car_target — the antigen the CAR recognizes (e.g. CD19, BCMA)
- indication — disease being treated
- delivery_cell (allowed: T_cell | NK_cell | macrophage)
- lnp_targeting (allowed: spleen_C12-200 | anti_CD8 | anti_CD5 | anti_CD3 | untargeted_MC3 | auto)
- persistence (allowed: transient | persistent)

Rules:
- Normalize obvious synonyms ("T cells" → "T_cell") when an allowed-values list exists.
- If a parameter has an "alias of X" note, store the value under X.
- Return ONLY a JSON object. No prose. No invented keys.

User request: "<query>"

JSON:
```

**(c) Validate against allowed values.** Drop any key not in the schema; coerce enums; flag invalid ones (don't silently drop — surface for the form to highlight).

### Where the schema comes from

Three sources, in priority order:

1. **`.nf` file inline comments.** Confirmed this session — `params.delivery_cell = 'T_cell'   // T_cell | NK_cell | macrophage` is the prevailing convention across the 5 tier-0 workflows audited (and `glp1_modality_bakeoff` even has `// alias for indication` on `params.disease`, which the schema-grounded prompt picked up correctly). Parse with a single regex.
2. **`workflows.params_schema` column** (currently NULL for tier-0 — needs backfill). Once populated, supersedes (1).
3. **`workflows.annotation` JSON** — fallback; only has bare name arrays, so the LLM gets less help.

A one-time backfill script can populate `params_schema` for all 2,463 workflows by parsing their `.nf` files.

---

## 3. Probe results (offline, this session)

Script: `/tmp/sge_probe/probe.mjs`. Model: `claude-haiku-4-5-20251001`. Cost: ~$0.02 total.

| Workflow                    | Query | Expected keys hit |
|-----------------------------|-------|-------------------|
| `bispecific_format_triage`  | "Design a PD-1 x VEGF bispecific in CrossMab format for NSCLC"                                  | 3/3 — `target_a=PD-1`, `target_b=VEGF`, `indication=NSCLC` |
| `in_vivo_cart_codesign`     | "Co-design an in-vivo CD19 CAR-T for DLBCL with LNP delivery to T cells, transient persistence" | 4/4 — `car_target=CD19`, `indication=DLBCL`, `delivery_cell=T_cell`, `persistence=transient` |
| `in_vivo_base_edit_design`  | "Design an in-vivo base-edit knockout of PCSK9 for hypercholesterolemia"                        | 3/3 — `target_gene=PCSK9`, `edit_goal=knockout`, `indication=hypercholesterolemia` |
| `glp1_modality_bakeoff`     | "Compare GLP-1 modalities for MASH — peptide vs mRNA vs gene therapy"                           | 1/1 — `indication=mash` (the `disease` alias was correctly skipped) |
| `modality_triage`           | "Triage modalities for a BCMA oncology target — try all options"                                | 2/2 — `target_gene=BCMA`, `indication=oncology` |
| **TOTAL**                   |                                                                                                 | **13/13** |

Compare to the current pipeline (also measured this session via chat-stream probe): T02, T04, T05 all failed on at least one canonical key (`delivery_cell`, `indication`, `indication`) and required the alias-table patches.

### What the model did right without help

- Picked enum-correct values: "T cells" → `T_cell` (matched against the allowed list).
- Respected the alias comment in `glp1_modality_bakeoff`: the user said "MASH" and the model put it under `indication` (primary), not `disease` (alias of).
- Self-limited: omitted parameters the query didn't address (`mechanism` for bispecific was filled with a reasonable enum value, but `editor_preference`, `delivery_pref`, `modalities` were either correctly inferred from "try all options" or omitted).

---

## 3.5 Information flow & user-in-the-loop

The pipeline runs in four stages. Each stage emits a user-visible status update (via the existing SSE stream) and has a defined clarification path when the model is uncertain.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ USER MESSAGE                                                                 │
│   e.g. "Co-design an in-vivo CD19 CAR-T for DLBCL with LNP delivery to       │
│         T cells, transient persistence"                                      │
└──────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ STAGE 1 — INTENT DECOMPOSITION   (existing LLM call, modified)              │
│   UI: "Analyzing your request…"                                              │
│   Input:  user message + session memory                                      │
│   Output: { type, keywords, has_parameter_signal: bool, sub_query }          │
│                                                                              │
│   NEW: instead of emitting inlineParameters with guessed keys, return        │
│     a boolean: does this message contain extractable scientific              │
│     parameters (targets, diseases, doses, files, modalities, …)?             │
│                                                                              │
│   Few-shot examples:                                                         │
│     "Run RNA-seq"                          → has_parameter_signal: false     │
│     "Run RNA-seq on SRR12345"              → has_parameter_signal: true      │
│     "Design a PD-1 x VEGF bispecific…"     → has_parameter_signal: true      │
│     "What's a good QC threshold?"          → has_parameter_signal: false     │
│                                                                              │
│   Clarification trigger:                                                     │
│     - intent type is genuinely ambiguous (workflow vs research_question)     │
│       → existing chat-message clarifier path; no change                      │
└──────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ STAGE 2 — ROUTING                  (existing)                                │
│   UI: "Finding the right workflow…"                                          │
│   Output: workflow_ga                                                        │
│                                                                              │
│   Clarification trigger:                                                     │
│     - ≥2 candidates score ≥6.0 with <3.0 gap                                 │
│       → emit DisambiguationCard with up to 4 candidates (existing path)      │
│       → halt downstream until user picks                                     │
└──────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
                          has_parameter_signal?
                          ┌─────┴─────┐
                         NO          YES
                          │           │
                          │           ▼
                          │  ┌────────────────────────────────────────────────┐
                          │  │ STAGE 3 — SCHEMA-GROUNDED EXTRACTION   (NEW)   │
                          │  │ UI: "Extracting parameters from your request…" │
                          │  │                                                │
                          │  │   3a. Rule pass (zero LLM)                     │
                          │  │     - direct key hits                          │
                          │  │     - global synonym graph (small, shared)     │
                          │  │     - unit/enum normalization                  │
                          │  │     - file path / accession ID regex           │
                          │  │                                                │
                          │  │   3b. LLM resolver (only if unresolved keys)   │
                          │  │     - inject ONLY this workflow's schema       │
                          │  │     - filter optional_params by query keyword  │
                          │  │       hit (cap prompt at ~2K tokens)           │
                          │  │     - return canonical-keyed JSON              │
                          │  │                                                │
                          │  │   3c. Validate                                 │
                          │  │     - drop unknown keys                        │
                          │  │     - coerce enum values                       │
                          │  │     - flag invalid enums                       │
                          │  │                                                │
                          │  │ Clarification triggers (raised to chat):       │
                          │  │   (i) required param missing AND no signal in  │
                          │  │       user query → "I need <param> (e.g. <ex>) │
                          │  │       to run this. What should I use?"         │
                          │  │   (ii) extracted value violates enum →         │
                          │  │       "You said 'B cells' but this workflow    │
                          │  │       supports T_cell, NK_cell, macrophage —   │
                          │  │       which is closest?"                       │
                          │  │   (iii) ambiguous match (multiple plausible    │
                          │  │       enum values, no clear winner) → list 2-3 │
                          │  │       options as quick-reply chips             │
                          │  └────────────────────────────────────────────────┘
                          │           │
                          ▼           ▼
                       inlineParameters = {}     inlineParameters = {canonical}
                          │           │
                          └─────┬─────┘
                                ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ STAGE 4 — FORM POPULATION       (existing UI)                                │
│   UI: workflow panel opens; "Ready to run" / "Fix N required params"         │
│   Behaviour:                                                                 │
│     - Render workflow panel with required + optional fields                  │
│     - Pre-fill from inlineParameters                                         │
│     - Each pre-filled field gets a small "from your message" hint badge so   │
│       the user can see WHY a value is there                                  │
│     - Missing required → blocked + "Fix now" (existing)                      │
│     - User edits → userOverriddenParams set                                  │
└──────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
              ┌───────────────────┴───────────────────┐
              │ Follow-up message arrives later?      │
              │   e.g. "actually use BCMA not CD19"   │
              └───────────────────┬───────────────────┘
                                  │
                                  ▼
                       Loop back to STAGE 1
                       Stage 1 routes as "workflow_modification" →
                       Stage 2 short-circuits to the open workflow →
                       Stage 3 runs with userOverriddenParams excluded
                       from the keys it's allowed to set →
                       diff vs current params surfaced in chat
                       ("Updating car_target: CD19 → BCMA. OK?")
```

### Status messages — exact strings

The SSE stream already supports `status` events. The schema-grounded path should emit one per stage transition. Default strings (configurable for i18n later):

| Stage entry             | Message                                                |
|-------------------------|--------------------------------------------------------|
| Stage 1 begin           | _"Analyzing your request…"_                            |
| Stage 2 begin           | _"Finding the right workflow…"_                        |
| Stage 2 disambiguation  | _"Found multiple matches — please choose:"_ (card)     |
| Stage 3 begin           | _"Reading the workflow's parameter schema…"_           |
| Stage 3 rule pass done  | _"Extracted N parameters from your message"_           |
| Stage 3 LLM resolver    | _"Resolving remaining parameters…"_                    |
| Stage 3 clarification   | inline chat question (see triggers (i)–(iii))          |
| Stage 4 panel ready     | _"Workflow panel ready — review parameters and run"_   |

These give the user a clear timeline. The current pipeline jumps from "Analyzing…" straight to "Workflow ready" with no intermediate signal — a 6–15s opaque pause that users have flagged.

### Clarification design principles

1. **Ask only when the LLM is genuinely uncertain.** Confidence threshold (>0.7) → don't ask; show pre-fill with the "from your message" hint and let the user edit if wrong. Uncertainty (<0.7 confidence or enum violation) → ask.
2. **Inline in chat, never modal.** Maintains conversational flow. The chat-message component already supports `workflow_type: 'disambiguation'`; add `workflow_type: 'param_clarification'` with the same chip-style UI.
3. **Always offer a "skip / fill it in the panel" escape.** User in control; the model shouldn't block progress on a clarification dialog.
4. **Quick-reply chips for enum mismatches.** Showing the 3 valid enum values as one-click chips is faster than typing.
5. **One question per turn.** If multiple clarifications are needed, queue them and ask sequentially — never blast a list.
6. **Persist answers per-workflow as preferences.** "Last time you ran ADMET, you used Lipinski Ro5" → next ADMET run, pre-fill that and don't ask.

### Where each stage's code lives

| Stage | New code | Existing code touched |
|-------|----------|----------------------|
| 1     | (modify existing prompt only — drop `inlineParameters` few-shots, add `has_parameter_signal`) | `galaxy-assistant.ts:3668` (intent prompt) |
| 2     | none — existing routing unchanged | n/a |
| 3a    | `frontend/server/lib/paramRules.ts` (rules + synonym graph) | new file |
| 3b    | `frontend/server/lib/schemaGroundedExtractor.ts` (LLM resolver) | new file |
| 3c    | same file as 3b | n/a |
| Param schema parser | `frontend/server/lib/paramSchema.ts` (reads `.nf` or `params_schema` column) | new file |
| Status events | `frontend/server/galaxy-assistant.ts` (emit SSE status at each stage) | existing SSE stream |
| Clarification card | `frontend/client/src/components/param-clarification-card.tsx` | new file, mirrors disambiguation card |
| Chat-message switch | `frontend/client/src/components/chat-message.tsx` | add `workflow_type: 'param_clarification'` branch |

---

## 4. Implementation plan

### Phase 1 — minimal viable replacement (this branch, ~1–2 days)

1. **Add `lib/paramSchema.ts`**: parse `.nf` params block into `{name, default, type, enum?, alias_of?, note?}[]`. Cache per workflow.
2. **Add `lib/paramRules.ts`**: rule pass (Stage 3a) — direct hits, global synonym graph, unit/enum normalization, file/accession regex.
3. **Add `lib/schemaGroundedExtractor.ts`**: orchestrator + LLM resolver (Stage 3b) + validation (Stage 3c). Returns `{ params, confidence, missing_required, enum_violations }`.
4. **Modify intent prompt** in `galaxy-assistant.ts:3668`: drop `inlineParameters` few-shots, add `has_parameter_signal: bool`.
5. **Wire stages 3a–3c** into `galaxy-assistant.ts` at the 4 existing `remapInlineParametersForWorkflow` call sites. Behind feature flag `SCHEMA_GROUNDED_EXTRACTION=1` for side-by-side comparison.
6. **Emit SSE status events** at each stage transition (strings from §3.5 table).
7. **Add `param-clarification-card.tsx`** + `workflow_type: 'param_clarification'` branch in `chat-message.tsx`. Triggers: missing required, enum violation, ambiguous match.
8. **Shrink `WORKFLOW_PARAM_ALIASES`** to a TODO: leave it in place as a fallback when the flag is off, remove once the new path is validated.
9. **Re-run tier-0 E2E** (T01–T05) — expect all 5 form-prefill checks to pass without any alias rows AND that clarification card renders correctly for a deliberately-vague test query.
10. **Re-run param_prefill benchmark** — expect ≥+15pp over current 61.7% baseline.

### Phase 2 — broaden coverage (next sprint)

1. **Backfill `workflows.params_schema`** from `.nf` for all 2,463 workflows. One-time script, idempotent. Surface in `/api/ai_assistant/generate_workflow` so the frontend can render type-aware form fields.
2. **Description backfill** for params that have none. Either: (a) author guidelines for new workflows, (b) one-shot LLM rewrite using the .nf module name + context, gated by human review. Cost: a few cents per workflow.
3. **Delete `WORKFLOW_PARAM_ALIASES` entirely** once param_prefill ≥70% and tier-0 stays green for two consecutive sessions.

### Phase 3 — close the loop (later)

1. **Schema-aware few-shots in the intent decomposer** — currently it ships 30+ examples with ad-hoc keys (`sequence`, `reads`, `hpo_term`). Replace with examples that use canonical workflow keys. Reduces first-pass noise so the grounding stage has less work.
2. **Telemetry**: log per-call (workflow, missing required keys, extracted keys, override edits user made in the form). Use the log to grow the global synonym graph automatically.

---

## 5. Audit of past edits in this session

Reviewed my own commits 2026-06-03 through 2026-06-12 against the generalizability bar. Classifications: **generalizable** (architectural fix, applies to all callers), **scoped band-aid** (acceptable, narrow blast radius — typically test code), **non-generalizable** (test-driven hack in production code; must be replaced).

| Edit | File | Class | Notes |
|------|------|-------|-------|
| `WORKFLOW_PARAM_ALIASES` table additions for T02/T04/T05 | `galaxy-assistant.ts` | **non-generalizable** | The subject of this doc. Replace with schema-grounded extraction. |
| `glp1_modality_bakeoff: indication → disease` direction flip | `galaxy-assistant.ts` | **non-generalizable & actively risky** | Made the test pass but the .nf actually says `params.indication` is primary. My flip was wrong; the `.nf` truth and the test agree. Replace by removing the row entirely (schema grounding handles it). |
| Per-user Galaxy proxy (`userProxy(req)`, AsyncLocalStorage `_api()`) | `galaxy-assistant.ts`, `routes.ts` | **generalizable** | Fixes the provisioning gap globally. Every callsite benefits; no per-user special-casing. Keep. |
| Stale-key self-heal on login (probe `/api/whoami`, re-provision on 401) | `auth-service.ts` | **generalizable** | Closes the door on stuck stale keys for any user, any time. Keep. |
| `provisionGalaxyUser` returning `Promise<boolean>` so register awaits it | `auth-service.ts` | **generalizable** | Removes a race that affected first-action-after-register for everyone. Keep. |
| `autoOpenedWorkflowSignatureRef` (signature = `msgId\|sortedKeys`) | `chat-with-artifacts.tsx` | **generalizable** | Fixes a real race: chat-stream metadata growing after first auto-open. Helps any user receiving streamed inline params. Keep. |
| Lazy-step fetch retry with `[0,500,1500,4000,10000]` ms backoff | `nextflow-workflow-viewer.tsx` | **generalizable** | Standard exponential backoff. Keep. |
| Persist-terminal-status effect + session-restore reconciliation | `chat-with-artifacts.tsx`, `App.tsx` | **generalizable** | Handles React remount (SSE stream failure → AppWithAuthSync remount). Helps every user with a longer-than-stream-lifetime session. Keep. |
| Inline-parameter late-bind effect in viewer | `nextflow-workflow-viewer.tsx` | **generalizable** | Param state mounts before LLM-extracted values arrive. Effect handles arrival without user-override clobber. Keep. |
| Status normalization `'succeeded' → 'completed'` (`toValidRunStatus`) | `routes.ts` | **generalizable** | Galaxy's vocabulary vs Node's diverged. Single function fixes all status surfaces. Keep. |
| `data-status` attribute on phase cards (test-id stable) | `nextflow-workflow-viewer.tsx` | **generalizable** | Pure additive test hook; doesn't change behavior. Keep. |
| `phase-group-A/B/C/D` testids with `'all'` fallback | `nextflow-workflow-viewer.tsx` | **scoped band-aid** | The fallback fires when workflow steps lack phase metadata. It's a real concern (steps without phase grouping), but solving it properly means backfilling phase metadata on every workflow. Tracker: open. |
| `clickDownloadAndCaptureBytes` (direct `/api/invocations/:id/methods-report` fetch) | `tier0-full-e2e.e2e.ts` | **scoped band-aid** | Test code only. The underlying button uses `window.open` which Playwright's `waitForEvent('download')` doesn't reliably catch. Acceptable. |
| DOM-level click via `page.evaluate` for `.phase-head` / `phase-params-toggle-*` | `tier0-full-e2e.e2e.ts` | **scoped band-aid** | Test code only. Works around Playwright `.click({force:true})` no-op on elements without computed click handlers. Acceptable. |
| `T01_DEBUG=1`-gated diagnostic dump | `tier0-full-e2e.e2e.ts` | **generalizable** | Reusable test-side observability. Keep. |
| Methods-report local plain-text fallback | `routes.ts` | **scoped band-aid** | Fires only when Galaxy proxy fails. Right fix: Nextflow-native runs should register with the Galaxy methods-report service. Tracker: open. |
| `frontend/migrations/` added to `sync_to_dev.sh` tar include | `scripts/sync_to_dev.sh` | **generalizable** | Missing-from-deploy bug fixed at the script level. Keep. |
| `BUILD_RC` captured before piping to `tail` | `scripts/sync_to_dev.sh` | **generalizable** | Exit-code-through-pipeline pattern, generally applicable. Keep. |

**Summary:** the only **non-generalizable** rows are the `WORKFLOW_PARAM_ALIASES` additions and the direction flip — both addressed by this proposal. The two open band-aids (`phase-group 'all'` fallback, methods-report local fallback) are scoped and worth tracking as follow-ups but don't compromise correctness.

---

## 6. Risks & open questions

1. **Latency.** Schema-grounding adds an extra LLM call. Haiku 4.5 at ~200ms is acceptable; for higher-cost models we'd want to inline this into the routing call's tool-use turn instead of a separate request.
2. **Param description quality.** Tier-0 workflows have descriptions in their `.nf` comments. The 2,463-workflow long tail does not. Phase 2 backfill is prerequisite for full coverage.
3. **Token cost on large schemas.** `nf-core/sarek` has 80+ params. Filter to required + commonly-overridden; pass the long tail only when the user query hints at them. (Heuristic: keyword match between query and param name/description.)
4. **Compatibility with the intent decomposer's few-shots.** Phase 3 says "use canonical keys in examples" — but the decomposer doesn't know which workflow will be chosen. The examples should switch to a workflow-agnostic shape (just `{type, query, keywords}`) and drop `inlineParameters` entirely until the grounding stage runs.
5. **Override-respect.** The viewer's "late-bind" effect skips params the user manually edited (`userOverriddenParams` set). Schema-grounded output should flow through the same gate.
6. **What if the LLM hallucinates a key anyway?** Stage 3(c) validation drops unknown keys — silent. Should we instead surface "extracted these unknown keys; refusing" in dev mode? Open.

---

## 7. Decision points for the user

- (a) Implement Phase 1 on this branch now (probe already passes; ~1 day of work)?
- (b) Or land just the `glp1_modality_bakeoff` direction revert + the T02/T05 alias rows on `integration/next-phase` as a tactical fix while Phase 1 cooks?
- (c) Phase 2 backfill — script it now (fast, idempotent) or treat as future cleanup?

My recommendation: **(a) Phase 1 here + (b) revert the direction flip on integration/next-phase** to stop the regression in `disease`-asserting callers immediately. (c) can wait.

---

## Appendix A — probe artifact

The runnable probe lives at `/tmp/sge_probe/probe.mjs`. It:
1. Reads the 5 tier-0 `.nf` files
2. Parses `params.X = 'default' // optional comment`
3. Builds the schema-grounded prompt per workflow
4. Calls Claude Haiku once per demo
5. Checks each extracted value against the test's expected regex

Reproducer:
```bash
cd /tmp/sge_probe
node probe.mjs
# => TOTAL: 13/13 keys extracted correctly
```

## Appendix B — replicating the failure with the current pipeline

Three chat-stream probes from earlier this session (preserved in `/tmp/probe.txt`):

```
T02 in_vivo_cart_codesign:
  inlineParameters: {"car_target":"CD19","indication":"DLBCL","lnp_targeting":"LNP",
                     "target_cells":"T cells","persistence":"transient"}
  → form's `delivery_cell` slot stays empty (was: needed alias `target_cells → delivery_cell`)

T04 glp1_modality_bakeoff:
  inlineParameters: {"target":"GLP-1","disease":"MASH",
                     "modalities":["peptide","mRNA","gene therapy"]}
  → form's `indication` stays empty (was: alias mapped indication → disease, wrong direction)

T05 modality_triage:
  inlineParameters: {"target_gene":"BCMA","disease_area":"oncology"}
  → form's `indication` stays empty (was: needed alias `disease_area → indication`)
```

Schema-grounded extraction returns the correct canonical key in all three cases without any table entries.
