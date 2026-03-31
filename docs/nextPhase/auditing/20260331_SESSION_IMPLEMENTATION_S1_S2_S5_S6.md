# 2026-03-31 Session: S1 / S2 / S5 / S6 Implementation

## What Was Done

This session implemented four improvements from the LLM usage audit priority table.
All 174 affected unit tests pass; 0 TypeScript errors.

---

## S5 — `CLARIFICATION_FALLBACKS` Completeness Test

**Problem:** The 15-entry `CLARIFICATION_FALLBACKS` dict lived _inside_ `processMessage()`,
so it was impossible to import in tests. No test verified that every fork-point type
defined in the system prompt had a corresponding fallback string.  If a developer added
a new fork-point to the system prompt but forgot to add a fallback, the gate would silently
fall through (no clarification question generated).

**Fix:**
- Moved `CLARIFICATION_FALLBACKS` to module level and exported it.
- Removed the duplicate inline definition inside `processMessage()`.
- Added 16 new assertions in `analyze-intent-uqu.test.ts` (describe block `S5: CLARIFICATION_FALLBACKS completeness`):
  - One test per fork-point from the system prompt ("Known fork points" section).
  - One test asserting no _extra_ stale keys exist.

**Files changed:**
- `frontend/server/galaxy-assistant.ts` — moved const to module level, added export
- `frontend/server/analyze-intent-uqu.test.ts` — added import + 16 assertions; 43 → 59 tests

---

## S1 — `_clarificationGate()` Extraction

**Problem:** The 30-line ambiguity gate was inline inside `processMessage()`.  Because it was
not a discrete function, there was no contractual guarantee it ran before workflow generation —
any future refactor touching the surrounding code could accidentally bypass it.

**Fix:** Extracted to `private async _clarificationGate(intent, actions, message, recommendedTools, recommendedDatasets): Promise<GalaxyAssistantResponse | null>`.

- Returns `null` if no gate fires (caller continues normally).
- Returns a full `GalaxyAssistantResponse` when a clarification is required (caller `return`s early).
- Uses module-level `CLARIFICATION_FALLBACKS` (now testable independently via S5).

The call site in `processMessage()` reduced from ~30 lines to:
```typescript
const clarificationResponse = await this._clarificationGate(...);
if (clarificationResponse) return clarificationResponse;
```

**Files changed:**
- `frontend/server/galaxy-assistant.ts` — new `_clarificationGate` method; simplified call site

---

## S2 — Confidence-Gated Session Memory Injection

**Problem:** `SessionMemory.key_decisions` and `open_questions` were plain `string[]`.
Haiku inferred items at varying confidence levels, but everything was injected into the
system prompt with equal weight — including speculative inferences. Low-confidence items
pollute the LLM context and can cause false premises.

**Fix:**

1. New interface `SessionMemoryItem { text: string; confidence: number }`.
2. `key_decisions` and `open_questions` changed to `SessionMemoryItem[]`.
3. `UPDATE_PROMPT` updated to ask Haiku for objects with explicit confidence:
   - `0.9` = explicit user statement
   - `0.7` = strong inference
   - `< 0.7` = speculation (suppressed from injection)
4. `_buildSessionMemoryBlock()` filters both arrays to `confidence >= 0.7` before injecting.
5. Backward-compatible: if Haiku returns a plain string (old format), it is coerced to
   `{ text: s, confidence: 0.7 }` so existing sessions continue working.

**Design rationale (why 0.7 threshold):**
- Items explicitly stated by the user always score ≥ 0.9.
- Reasonable technical inferences ("user is using paired-end data") score ~0.75–0.85.
- Items the LLM is uncertain about score < 0.7 — these should not appear as "facts" in
  the system prompt, but they remain stored in memory so the LLM can surface them as
  open questions when relevant.

**Files changed:**
- `frontend/server/galaxy-assistant.ts` — new `SessionMemoryItem` interface, updated
  `SessionMemory`, `UPDATE_PROMPT`, `_update()` validation, `_buildSessionMemoryBlock()`

---

## S6 — Domain Catalog Injection

### Original implementation (first cut, now replaced)

The initial cut injected a hardcoded `<drug_discovery_catalog>` block gated on
`isDrugDevelopmentQuery` — a keyword regex on the _message text_.

### Why that was wrong

1. **Wrong signal.** `isDrugDevelopmentQuery` fires on message keywords ("drug", "toxicity",
   "docking", "clinical"…). It does not use `preferredDomains`, which is the proper
   domain signal derived from the user's profile and intent classifier.
   - A drug-discovery user asking a genomics question → catalog NOT injected.
   - A random user asking "what is clinical significance?" → catalog injected (false positive).

2. **Not extensible.** As BioMate adds workflows for other domains (cryo-EM, lab automation…),
   a second hardcoded block would need to be added — no shared pattern.

### Correct implementation

**`DOMAIN_CATALOGS`** — a `Partial<Record<string, string>>` map at module level:
- Keyed by canonical domain name (e.g. `"drug_discovery"`).
- Contains a human-readable catalog string for each domain that has ≥4 BioMate-specific
  non-obvious workflows.
- Only `drug_discovery` is populated today. Other domains (genomics, transcriptomics…) are
  NOT listed because the LLM already knows standard tools (GATK, DESeq2, BWA) — a catalog
  adds no information. Add an entry only when BioMate has built workflows the LLM cannot infer.

**`buildDomainCatalogBlock(preferredDomains: string[]): string`** — exported helper:
- Looks up `DOMAIN_CATALOGS[d]` for each domain in `preferredDomains`.
- Wraps non-empty entries in `<domain_catalog>` XML tags.
- Returns empty string if no catalog entry exists for any preferred domain.

**`generateResponse()` signature extended:**
- Added `preferredDomains: string[] = []` parameter.
- Both call sites (single-intent in `processMessage`, multi-intent in `processMultiIntent`)
  now pass `decomposition.preferredDomains`.
- The catalog block is rendered via `${buildDomainCatalogBlock(preferredDomains)}` in the
  system prompt, replacing the old hardcoded block.

### When to add a new domain catalog entry

Add an entry to `DOMAIN_CATALOGS` when **all** of the following are true:
1. BioMate has built ≥4 workflows for the domain.
2. The workflows use tools or modes the LLM cannot infer from general bioinformatics knowledge.
3. Users commonly ask for those workflows by capability rather than by exact workflow name
   (so the LLM needs awareness of what's available to recommend them).

Current candidates for future entries:
- `cryo_em` — once CryoSPARC SPA + helical reconstruction + subtomogram workflows are built
- `lab_automation` — once PyLabRobot liquid handling workflows are published

**Files changed:**
- `frontend/server/galaxy-assistant.ts` — new `DOMAIN_CATALOGS` map, `buildDomainCatalogBlock()`
  helper, `generateResponse()` signature extended, both call sites updated

---

## Test Results

| Test file | Before | After |
|-----------|--------|-------|
| `analyze-intent-uqu.test.ts` | 43 pass | **59 pass** (+16 S5 completeness tests) |
| `personalization-drug-discovery.test.ts` | 115 pass | **115 pass** |
| TypeScript (`tsc --noEmit`) | 0 errors | **0 errors** |

Pre-existing failures in `workflow-notification-service.test.ts` (2 tests) are unrelated
to this session's changes — they existed before this session.

---

## Audit Document Updates Required

`docs/nextPhase/20260330_LLM_USAGE_AUDIT.md` priority table should be updated:

| Solution | Status |
|----------|--------|
| S5: Fallback-map completeness test | ✅ Done (2026-03-31) |
| S1: ClarificationGate function | ✅ Done (2026-03-31) |
| S2: Confidence-gated memory injection | ✅ Done (2026-03-31) |
| S6: Domain catalog index | ✅ Done (2026-03-31, generalized) |
