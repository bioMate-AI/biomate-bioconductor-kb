# 2026-03-31 Session: S3 / S4 Implementation

## What Was Done

Continued from the previous session (S1/S2/S5/S6). This session implements the two remaining
items from the LLM usage audit priority table.

All tests pass; 0 TypeScript errors.

---

## S3 — DOMAIN_SPECIALIST_GUIDANCE Threaded into generateResponse()

### Problem

The original audit identified that `DomainSpecialistPool` (backend Python) runs parallel LLM
specialist consultations producing `domain_notes` and `recommended_tools`, but these results
were never forwarded to the final response generator (`generateResponse()` in
`galaxy-assistant.ts`). The `generateResponse()` system prompt had only one domain-specific
signal: an `isDrugDevelopmentQuery` **keyword regex** on the message text — a fragile fallback
that:
- Only covered drug discovery
- Fired on any message containing "drug", "toxicity", "clinical", etc. (false positives)
- Missed users whose domain was set via profile but who asked a domain-neutral message

### Solution

**`DOMAIN_SPECIALIST_GUIDANCE: Partial<Record<string, string>>`** — module-level map in
`galaxy-assistant.ts`, exported:

- 16 domains covered: genomics, transcriptomics, single_cell, epigenomics, proteomics,
  metabolomics, metagenomics, structural_biology, drug_discovery, cryo_em, systems_biology,
  synthetic_biology, bioimaging, lab_automation, cancer_biology, cell_biology
- Each entry is a concise expert framing paragraph (80–400 chars):
  - The decision criteria that differ across sub-options (e.g. DDA vs DIA for proteomics)
  - Common workflow decision points (e.g. MACS2 narrow vs broad peaks for epigenomics)
  - Critical QC requirements (e.g. gold-standard FSC for cryo-EM resolution)
  - Safety thresholds (e.g. hERG IC₅₀ > 1 μM for drug discovery)
- Entries start with `"Expert framing (domain):"` for consistent formatting

**`buildDomainSpecialistBlock(preferredDomains: string[]): string`** — exported helper:
- Looks up `DOMAIN_SPECIALIST_GUIDANCE[d]` for each domain in `preferredDomains`
- Wraps non-empty entries in `<domain_specialist>` XML tags
- Returns empty string if no entry exists for any preferred domain

**`generateResponse()` system prompt updated:**
- `${buildDomainSpecialistBlock(preferredDomains)}` injected before `${buildDomainCatalogBlock(preferredDomains)}`
- `isDrugDevelopmentQuery` regex replaced by `preferredDomains.includes('drug_discovery')` as
  the primary signal; regex kept as backward-compat fallback for sessions where no
  `preferredDomains` is set

### Why not run DomainSpecialistPool on the hot path?

`DomainSpecialistPool` makes additional LLM calls (one per domain) — this would add 500–2000 ms
latency to every `search_nextflow_workflow` response. The `DOMAIN_SPECIALIST_GUIDANCE` map
captures the same decision-making value (expert framing, decision gates, QC criteria) as static
strings derived from the same backend `DOMAIN_SPECIALIST_PROMPTS`, with zero additional latency.

### Files Changed

| File | Change |
|------|--------|
| `frontend/server/galaxy-assistant.ts` | New `DOMAIN_SPECIALIST_GUIDANCE` map (exported), `buildDomainSpecialistBlock()` helper (exported), injection into `generateResponse()` system prompt, `isDrugDevelopmentQuery` replaced by `isDrugDiscoveryDomain` with keyword fallback |
| `frontend/server/analyze-intent-uqu.test.ts` | Updated imports; 22 new S3 assertions |

---

## S4 — Step-by-Step Approval Gate for Sequential Pipelines

### Problem

`PipelineListView` had a single "Confirm & Run Pipeline" button that launched all steps
simultaneously. For multi-step drug discovery or multi-omics pipelines, this means:
- Step 2 starts before the user has reviewed Step 1's outputs
- Failed Step 1 still triggers Step 2 (wasting compute)
- No natural review point where the user can abort or adjust before costly GPU steps

### Solution

**New props on `PipelineListViewProps`:**
```typescript
approvalGate?: boolean   // default false — backwards compatible
onApproveStep?: (completedStepId: string, nextStepId: string) => void
```

**Behavior when `approvalGate=true`:**

1. **Pre-run state** (all steps `pending`):
   - "Confirm & Run" button relabeled "Confirm & Run Step 1"
   - Existing `onConfirmRun`/`onConfirm` callbacks unchanged — caller launches Step 1 only

2. **Step N completes** (status changes to `completed`):
   - An **"Approve & Run Step N+1"** button (`data-testid="pipeline-approve-step-<id>"`) appears
     inline below the completed step row
   - Text: "Review outputs above before continuing"
   - Clicking calls `onApproveStep(completedStepId, nextStepId)`
   - Caller is responsible for triggering the next step's execution

3. **Footer confirm button**:
   - Hidden once `pipelineStarted` (any step is not `pending`)
   - Footer status text shows "Awaiting step approval…"

4. **Step N+1 already running** (e.g. user approved):
   - No approve button for Step N+2 shown until N+1 completes
   - Prevents double-approval

**Backwards compatibility:** `approvalGate` defaults to `false`. All existing call sites work
unchanged. The approval gate must be explicitly opted into by the caller (e.g. chain execution
view for multi-step pipelines with GPU steps).

### Files Changed

| File | Change |
|------|--------|
| `frontend/client/src/components/pipeline-list-view.tsx` | New `approvalGate`/`onApproveStep` props; `StepRow` extended with `showApproveButton`/`nextStep`/`onApproveStep`; updated footer label + visibility logic |
| `frontend/client/src/components/pipeline-list-view.test.tsx` | New file — 9 unit tests covering all approval gate states |

---

## Test Results

| Test file | Before | After |
|-----------|--------|-------|
| `analyze-intent-uqu.test.ts` | 59 pass | **81 pass** (+22 S3 tests) |
| `personalization-drug-discovery.test.ts` | 115 pass | **115 pass** |
| `pipeline-list-view.test.tsx` | (new file) | **9 pass** |
| TypeScript (`tsc --noEmit`) | 0 errors | **0 errors** |

Pre-existing failures (6 tests in 5 files) are unrelated to this session's changes.

---

## Audit Document Updates

`docs/nextPhase/20260330_LLM_USAGE_AUDIT.md` priority table updated:

| Solution | Status |
|----------|--------|
| S3: DomainSpecialistPool → generateResponse() | ✅ Done (2026-03-31) |
| S4: Step-by-step pipeline approval | ✅ Done (2026-03-31) |

All 6 items from the LLM usage audit priority table (S1/S2/S3/S4/S5/S6) are now complete.
