# Schema-Grounded Extraction — Phase 1 Implementation Report

**Branch:** `worktree-schema-grounded` (worktree at `.claude/worktrees/schema-grounded-extraction`)
**Status:** Phase 1 server + UI implemented, all local tests green, awaiting sync green-light.

---

## What landed

### New modules

| File | Lines | Purpose |
|---|---|---|
| `frontend/server/lib/paramSchema.ts` | 172 | Adapter from `workflow_ga.required_params/optional_params` to `WorkflowSchema`. Schema is read from the backend's response — no `.nf` or `nextflow_schema.json` re-parsing. |
| `frontend/server/lib/paramRules.ts` | 251 | Stage 3a rule pass (synonyms + enum normalization) + Stage 3c validator + `hasParameterSignal()` heuristic. |
| `frontend/server/lib/schemaGroundedExtractor.ts` | 273 | Stage 3 orchestrator. Rules → optional LLM resolver (Haiku via existing `llmGenerate`) → validation. Returns canonical-keyed params + provenance + clarifications + confidence. |
| `frontend/client/src/components/param-clarification-card.tsx` | 169 | Inline chat card. Quick-reply chips for enum violations; param-name + hint + examples for missing-required. Skip escape on every clarification. |

### Wiring

| File | Change |
|---|---|
| `frontend/server/galaxy-assistant.ts` | • `groundInlineParameters()` wrapper (flag-gated, drop-in replacement for `remapInlineParametersForWorkflow`)<br>• `AgentToolEvent` type extended with `'status'` variant<br>• Single- and multi-intent callsites switched to the wrapper + `onStatus` callback wired through to `onToolEvent` (→ SSE `tool_event`)<br>• `GalaxyAssistantResponse.paramClarifications` field added + populated when extraction surfaces clarifications |
| `frontend/server/routes.ts` | `paramClarifications` forwarded from `assistantResponse` to `metadata` on the assistant message persisted to the client |
| `frontend/client/src/components/chat-message.tsx` | ParamClarificationCard rendered when `message.metadata.paramClarifications` is non-empty. Click → CustomEvent dispatch. |
| `frontend/client/src/components/chat-with-artifacts.tsx` | New effect: listens for `biomate:param-clarification-resolved`, patches the picked value into the open workflow's `inline_parameters` |

### Feature flag

`SCHEMA_GROUNDED_EXTRACTION=1` enables the new path. When unset, behavior is identical to `master` — `remapInlineParametersForWorkflow` runs unchanged. Every safety net falls back to legacy:
- Flag off → legacy
- Flag on, but workflow_ga has no schema → legacy
- Flag on, but extractor throws → legacy + warning logged

---

## Generalizability audit (revisited)

In response to "do not hardcode for short-term goals":

**Removed (duplicated backend functionality):**
- `parseNextflowParams()` — backend already has `_parse_nextflow_params`
- `buildWorkflowSchemaFromFile()` + `resolveNfPath()` — filesystem coupling
- `ACCESSION_PATTERNS` + `applyAccessionSweeps()` — backend already has `_extract_sra_accession`, `_extract_genome_build`, `_inject_sra_into_params`, `_IGENOMES_REFERENCE`

**Kept (genuinely new):**
- `SYNONYM_GROUPS` — small (8 cross-workflow rows). The LLM handles the long tail using the schema's own descriptions. Path to zero hardcode (Phase 3): derive synonyms from param descriptions automatically.
- `hasParameterSignal()` heuristic — uses the schema's own vocabulary (param names, enum values) + a generic uppercase-ID pattern. No per-workflow rules.
- Schema-grounded LLM prompt template — workflow-agnostic; rendered per-call with the chosen workflow's schema.

**Coverage:** any workflow for which the backend's `_get_workflow_params()` succeeds — i.e. all nf-core upstream pipelines (via `nextflow_schema.json`) AND all biomate-ai-tools modules (via `.nf` comment parsing). Not just the 5 tier-0 demos.

---

## Local test results

| Test | Result |
|---|---|
| `server/lib/__tests__/schemaGroundedExtractor.local.ts` | **13/13 cases all-green, 23/23 keys correct** |
| `server/lib/__tests__/wrapper.smoke.ts` | 4/4 dispatch paths PASS |
| Full project `tsc --noEmit` | clean |
| Full `vitest run` | 564 pass, 4 skipped, 2 pre-existing DATABASE_URL failures (unrelated) |
| `vite build` | succeeds (11.13s) |

### Use cases covered by the 13 extractor tests

1. tier0-T01 bispecific — PD-1 × VEGF for NSCLC
2. tier0-T02 CAR-T — CD19 / DLBCL / T cells / transient
3. tier0-T03 base-edit — PCSK9 knockout / hypercholesterolemia
4. tier0-T04 GLP-1 — MASH (`indication` primary, `disease` is alias; correctly avoided)
5. tier0-T05 modality triage — BCMA oncology
6. Synonym graph — raw `target`/`disease` → canonical `car_target`/`indication`
7. User mentions out-of-enum ("B cells") → enum-violation clarification fires
8. Validator catches out-of-enum from upstream rawParams
9. No-signal graceful — missing-required clarifications, no LLM hallucination
10. Alias-of respected (`glp1_modality_bakeoff`: value lands in `indication`, never `disease`)
11. Rule-pass direct hit (zero LLM)
12. Rule enum normalization ("T cells" → "T_cell", zero LLM)
13. **Gate skips generic query** ("please start it now" — no schema keywords, no IDs → LLM call skipped)

---

## Stage 1 parameter-signal gate

Instead of modifying the heavily-tested intent prompt (which has dozens of few-shot examples with ad-hoc `inlineParameters` keys), the gate is implemented as `hasParameterSignal()` in `paramRules.ts`. It uses the **chosen workflow's schema** to decide:

```ts
function hasParameterSignal({ userQuery, schema, rawParams }) {
  if (Object.keys(rawParams).length > 0) return true;
  const q = userQuery.toLowerCase();
  for (const p of schema.params) {
    if (q.includes(p.name.toLowerCase())) return true;
    if (p.enum && p.enum.some(v => q.includes(String(v).toLowerCase()))) return true;
  }
  return /\b[A-Z][A-Z0-9-]{2,}\b/.test(userQuery); // CD19, BCMA, SRR12345…
}
```

Verified by the `gate-skips-generic-query` test case (`"please start it now"` → LLM call skipped, stages = rules+validation only).

---

## Information flow (recap)

```
user message
   │
   ▼
[Intent decompose] (existing)         — unchanged
   │
   ▼
[Routing] (existing)                  — unchanged
   │
   ▼
groundInlineParameters() ──────────────────┐
   │                                       │
   ├─ flag off → legacy alias              │
   ├─ schema empty → legacy alias          │
   │                                       │
   ├─ Stage 3a rule pass                   │ → SSE status:
   │   - direct / case-insensitive         │   "Reading parameter
   │   - synonym graph                     │    schema for X…"
   │   - enum normalization                │
   │                                       │ → SSE status:
   ├─ Stage 3b LLM resolver                │   "Extracting parameters
   │   - hasParameterSignal gate           │    from your message…"
   │   - workflow's schema in prompt       │
   │                                       │
   └─ Stage 3c validate                    │ → SSE status:
       - enum violations                   │   "Extracted N params"
       - missing required                  │   / "… M need your input"
   │
   ▼
{ params, clarifications, confidence, provenance }
   │
   ▼
GalaxyAssistantResponse
   │
   ▼
assistant message metadata.paramClarifications
   │
   ▼
<ParamClarificationCard /> inline in chat
   │
   click → CustomEvent
   ▼
chat-with-artifacts patches workflow panel inline_parameters
```

---

## What's NOT in Phase 1 (deferred)

1. **Client-side rendering of SSE status events** — events are emitted by the server but the chat UI doesn't surface them yet. Decision: a "live status" affordance is a separate UX call; emission alone gives observability and a hook for future opt-in.
2. **Removing `WORKFLOW_PARAM_ALIASES`** — kept as fallback for when flag is off, schema is empty, or extractor throws. Phase 2 task: shrink to zero once schema-grounded is the default.
3. **Live HTTP chat-stream smoke probe with flag on** — would require restarting the local dev server which is currently owned by a parallel session. Safer to run on dev EC2 after sync, where the container is isolated.
4. **`SYNONYM_GROUPS` auto-derivation from descriptions** — Phase 3.
5. **Intent prompt few-shot rewrite** — the existing prompt's `inlineParameters` few-shots are still there. Schema-grounded extractor doesn't care (it uses canonical keys via the schema). Cleaning up the prompt is Phase 3.

---

## Recommended sync plan

1. **Stage 1 (this branch first, no flag)** — merge the new modules + wiring + UI with `SCHEMA_GROUNDED_EXTRACTION` unset. Production behavior is bit-identical (`remapInlineParametersForWorkflow` still runs).
2. **Stage 2 (after a soak)** — set the env var on dev EC2 only: `SCHEMA_GROUNDED_EXTRACTION=1`. Run tier-0 E2E + a small set of nf-core demos. Monitor `[InlineParam Ground]` logs for `path: 'schema-grounded'` vs `'legacy-alias'` rate and the confidence distribution.
3. **Stage 3 (after dev validation)** — flip the flag on in prod. Remove `WORKFLOW_PARAM_ALIASES` entries that are now covered by schema grounding.

---

## Files changed

```
docs/20260612_SCHEMA_GROUNDED_EXTRACTION_PROPOSAL.md         (proposal — committed)
docs/20260612_PHASE_1_IMPLEMENTATION_REPORT.md               (this file)
docs/20260612_sge_probe.mjs                                  (original probe — kept for reproducibility)
frontend/client/src/components/chat-message.tsx              (clarification card render branch)
frontend/client/src/components/chat-with-artifacts.tsx       (clarification event handler)
frontend/client/src/components/param-clarification-card.tsx  (NEW)
frontend/server/galaxy-assistant.ts                          (wrapper + callsite wiring + response field)
frontend/server/lib/__tests__/schemaGroundedExtractor.local.ts (NEW — 13 cases)
frontend/server/lib/__tests__/wrapper.smoke.ts               (NEW — 4 paths)
frontend/server/lib/paramRules.ts                            (NEW)
frontend/server/lib/paramSchema.ts                           (NEW)
frontend/server/lib/schemaGroundedExtractor.ts               (NEW)
frontend/server/routes.ts                                    (paramClarifications forwarded to metadata)
```
