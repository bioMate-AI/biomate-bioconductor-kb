# MT-5 Fix, Inline-Data Refactor, and E2E Tester Documentation
**Date:** 2026-07-01  
**Branch:** integration/next-phase  
**Session commits:** `e3226f914`, `1d6278958`

---

## Summary

This session fixed the MT-5 Playwright E2E test, refactored the tabular-data detection logic that the fix introduced, and produced two QA test documents.

---

## Timeline

### ~09:00 — MT-5 failing: `needs_input` instead of `workflow_ready`

**Symptom:** `chat-multiturn-research.e2e.ts` MT-5 ("wf-chip shows 'In panel' badge when workflow panel is open") returned:
```
Could not generate workflow — The automated pipeline generator encountered an error
while parsing the inline CSV data structure directly into a Nextflow samplesheet.
```
The backend returned `needs_input` (clarification-request path) instead of `workflow_ready`.

**Root cause 1 — Gemini didn't classify count matrices:**  
`extractInlineDataWithLLM` in `frontend/server/galaxy-assistant.ts` called Gemini Flash to detect typed data (SMILES, accessions, etc.) from the user message. The prompt did not include `count_matrix` as a recognised type, so Gemini returned an empty `InlineDataMap`. With `hasInlineData = false`, the Claude prompt chose the "Clarification needed" framing, and the Galaxy backend returned `needs_input`.

**Root cause 2 — Galaxy startup missing `ANTHROPIC_API_KEY`:**  
On the first repro attempt the Galaxy backend returned `{"detail": "AI Assistant not available"}` because it was started without `ANTHROPIC_API_KEY`. Restarted with correct env vars.

### ~09:30 — First fix: `count_matrix` in Gemini prompt + `_hasTabularData` IIFE

Added `count_matrix` to the Gemini `extractInlineDataWithLLM` prompt. Also added a temporary inline IIFE (`_hasTabularData`) at the call site that applied a regex to detect tabular input when Gemini returned empty.

Commit `e3226f914` also:
- Increased `sendMessage` composer wait from 10 s → 30 s
- Forced `waitForAssistant` to explicitly `.waitFor({ state: "attached" })`
- Added explicit `{ timeout: LLM_TIMEOUT }` on `textContent()` to prevent the 60 s actionTimeout killing cold starts

**MT full-suite result:** 6/7 pass → 7/7 pass (11.1 min).

### ~10:00 — Refactor: remove `_hasTabularData` IIFE

User flagged: "This hard coding is very ad hoc."

The IIFE was at the call site and did not populate `inlineDataMap`, so downstream code couldn't use the detected value. Moved detection into `extractInlineDataWithLLM`'s regex fallback section (alongside other pattern-based fallbacks):

```typescript
// galaxy-assistant.ts ~line 1850
const tabularLines = message.split('\n').map((l: string) => l.trim()).filter(Boolean);
const numericTabularRows = tabularLines.filter((line: string) => {
  const cols = line.split(/[,\t]/);
  return cols.length >= 2 && cols.some((c: string) => /^\d+(\.\d+)?$/.test(c.trim()));
});
if (numericTabularRows.length >= 2) fallback.count_matrix = message.trim();
```

Removed the IIFE. `hasInlineData` now derives naturally from `Object.keys(inlineDataMap).length > 0` as before.

TypeScript check: `npx tsc --noEmit` — no errors.  
MT-5 re-run (single test): 1/1 pass (1.9 min).

Commit `1d6278958`.

### ~10:30 — E2E use-case document (technical, for automators)

Created `docs/20260701_E2E_USE_CASES_EXPANDED.md` covering 14 use cases (UC-1 through UC-14) with:
- Full SSE stream protocol and TypeScript interfaces
- Panel DOM contract with `data-testid` tree and state machine
- Helper functions (`parseChatStream`, `waitForPanelState`, `waitForPhaseStatus`)
- JSON report format
- Execution commands

### ~11:00 — UI tester document (manual, for human QA)

Created `docs/20260701_E2E_USE_CASES_UI_TESTER.md` with 20 manual test cases written for a non-technical tester. Each test has a Do/Expect table, explicit input data, screenshot naming, and pass/fail criteria.

### ~11:30 — Input data completeness audit

User asked: "Does the tester have all required input data?"  
Identified 7 gaps:

| # | Test | Gap |
|---|------|-----|
| 1 | T9 | VCF data uses tabs — tester might paste as spaces |
| 2 | T13, T16, T17, T18 | DESeq2 count matrix not embedded; tests said "complete Test 5 first" |
| 3 | T14 | Panel may be in Completed state from T13; no "Run again" step before editing params |
| 4 | T15 | hERG QC threshold setup steps entirely missing |
| 5 | T17 | "Study type" dropdown may not exist on differentialabundance panel |
| 6 | T19, T20 | No skip guidance when T13 didn't complete |
| 7 | T20 | No per-step skip instructions for missing file types |

### ~11:45 — Document fixes applied

**T9:** Added copy warning about tab characters.

**T13:** Replaced "complete Test 5 first" with an embedded count matrix code block + conditional setup (reuse existing panel or paste fresh).

**T14:** Added step 0 — "If panel shows Completed/Failed from T13, click Run again / Restart first."

**T15:** Added pre-run QC setup: open Settings tab → find QC Settings section → set hERG IC50 = 10 before clicking Run. Required because the gate only fires if a threshold is configured and the compound exceeds it.

**T16:** Added Setup section with embedded count matrix; step 1 changed to "confirm one card is visible."

**T17:** Replaced "find the Study type dropdown" (field may not exist) with "find any text input or dropdown that has a value."

**T18:** Added Setup section with embedded count matrix; step 1 changed to confirm step.

**T19:** Added skip instruction for when T13 did not complete.

**T20:** Added skip instruction + per-step conditional notes for each file type (`.png`, `.csv`, `.txt`) that may be absent.

---

## Open Issues

| Issue | Severity | Notes |
|-------|----------|-------|
| T15 QC Settings UI path uncertain | Medium | The test assumes a Settings tab → QC Settings section exists. If the panel layout differs, step 2-5 of the pre-run setup will not match. Verify against live UI before handing to tester. |
| T8 single-cell routing not guaranteed | Low | Workflow routing may return a bulk RNA-seq pipeline instead of scrnaseq for the barcoded matrix. Known ambiguity in the routing rules. |
| MT suite runtime ~11 min | Low | Single worker, real LLM calls. Acceptable for CI nightly but slow for iterative dev. |
| Biomni/ submodule deleted files | Low | `git status` shows many deleted files under `Biomni/`. Not related to this session — likely a submodule removal from earlier work. Not committed here. |

---

## Files Changed This Session

| File | Type | Change |
|------|------|--------|
| `frontend/server/galaxy-assistant.ts` | Modified | Added `count_matrix` to Gemini prompt; moved tabular detection into regex fallback; removed `_hasTabularData` IIFE |
| `frontend/e2e/chat-multiturn-research.e2e.ts` | Modified | 30 s composer wait; `waitFor attached`; explicit `textContent` timeout |
| `docs/20260701_E2E_USE_CASES_EXPANDED.md` | New | 14 technical use cases with SSE + DOM contract |
| `docs/20260701_E2E_USE_CASES_UI_TESTER.md` | New | 20 manual test cases for human QA tester |
| `docs/20260701_MT5_FIX_AND_E2E_TESTER_DOCS.md` | New | This document |

---

## Next Steps

1. Hand `docs/20260701_E2E_USE_CASES_UI_TESTER.md` to QA tester — all 20 tests now have complete input data.
2. Verify T15 QC Settings path in the live UI before the tester reaches that test.
3. Consider adding `count_matrix` E2E assertion to the automated suite (currently only covered by MT-5 indirectly).
