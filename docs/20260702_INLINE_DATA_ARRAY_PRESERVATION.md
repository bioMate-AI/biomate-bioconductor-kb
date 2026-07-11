# Inline Data Array Preservation — Session Notes 2026-07-02

## What Was Changed

### 1. `frontend/server/galaxy-assistant.ts` — `extractInlineDataWithLLM` array fix

**Problem:** When Gemini Flash returned an array for an extracted field (e.g. `smiles: ["CC(=O)...", "Cn1cnc..."]`), the function silently dropped it. Only string values were kept. Multi-compound inputs were reduced to nothing in `inlineDataMap`.

**Fix:** Arrays are now serialized to JSON strings so they survive the `InlineDataMap` (which is `Record<string, string>`):
```typescript
} else if (Array.isArray(v) && v.length > 0) {
  const strings = v.filter((item): item is string => typeof item === 'string' && item.trim() !== '');
  if (strings.length > 0) result[k] = JSON.stringify(strings);
}
```
The downstream consumer (system-prompt builder) already reads the value as a string and passes it verbatim to the LLM context, so no other changes were needed.

**Why arrays occur:** Nextflow processes each array element in parallel. When a user pastes a table of 5 compounds, the Galaxy backend wants `smiles` as a JSON array so each SMILES can be dispatched to a separate parallel process instance.

### 2. `extractInlineDataWithLLM` — logging

Added a log line after extraction (both LLM path and regex fallback path) so server logs can be used as E2E proof:
```
[extractInlineData] result keys=smiles arrayKeys=smiles map={"smiles":"[\"CC(=O)...\",\"Cn1cnc...\"]"}
```
The `arrayKeys` field makes it easy to grep for array-preserved cases.

### 3. Intent parse JSON fallback — `analyzeIntent`

**Problem:** When the Gemini intent classifier returned malformed JSON (parse error), the fallback hardcoded `type: 'tool_search'`. For messages containing inline omics data, this caused `mustGenerateWorkflow` to never fire → `shouldGenerate=false` → empty response → "having trouble" error.

**Fix:** Fallback now detects inline data patterns in the raw message and sets `type: 'workflow_generation'` accordingly:
```typescript
const _fallbackHasInlineData = (
  /\b((SRR|ERR|DRR|...)\d+)\b/i.test(message) ||   // accession IDs
  /\b((?:s3|gs|ftp|...)\/\S+|\/\S+\.(?:fastq|...))\b/i.test(message) || // file paths
  /[=#\[\]\/\\@(][A-Za-z0-9@=#\-+\[\]()\/.\\]{4,}/.test(message) ||    // inline data tokens
  (() => { /* multi-column table detection */ })()
);
const _fallbackType = _fallbackHasInlineData ? 'workflow_generation' : 'tool_search';
```
The inline-data detection is intentionally generic — it covers accessions, file paths, structured tables, and inline tokens without being SMILES-specific.

### 4. `frontend/.env` — `GEMINI_API_KEY` alias

`gemini-flash.ts` reads `process.env.GEMINI_API_KEY` specifically. `.env` only had `GOOGLE_API_KEY` (same value). Added:
```
GEMINI_API_KEY=AIzaSyDoFJyQuwTYsfhoLO4DBL1ME9Ojl7VpFHI
```
Without this, `extractInlineDataWithLLM` always fell back to regex locally, never exercising the Gemini array path.

### 5. `frontend/e2e/inline-omics-routing.e2e.ts` — UC-6 and UC-6b

**UC-6:** Compound CSV table (5 compounds, no ADMET keywords) → verifies workflow generation is triggered without relying on the ADMET fast path.

**UC-6b:** Server-log-based proof that `extractInlineDataWithLLM` hit the array branch:
- Records log file size before sending the message
- Sends a multi-SMILES CSV input
- Reads new log content after response
- Asserts `[extractInlineData]` lines were emitted
- Asserts at least one key has `arrayKeys` non-empty
- Asserts the array values are present in the serialized map JSON

---

## What Was Tested

| UC | Scenario | Result |
|----|----------|--------|
| UC-1 | SRR accession → RNA-seq workflow | PASS |
| UC-2 | GSE accession → workflow generation (not tool_search) | PASS |
| UC-3 | SMILES + ADMET keywords → ADMET fast path, no re-ask | PASS |
| UC-4 | Literature query → research agent | PASS |
| UC-5 | Two-turn RNA-seq protocol context | PASS |
| UC-6 | Compound CSV table (no ADMET keywords) → workflow generation | PASS |
| UC-6b | Server log proves array branch hit and values preserved | PASS |

UC-6b output from passing run:
```
[extractInlineData] result keys=smiles arrayKeys=smiles map={"smiles":"[\"CC(=O)Oc1ccccc1C(=O)O\",\"Cn1cnc2c1c(=O)n(C)c(=O)n2C\",\"CC(C)Cc1ccc(cc1)C(=O)O\"]"}
```

---

## Commits in This Session

- `e78290cf6` — array preservation fix + regex fallback log line + UC-6b test
- `43ab06f49` — merge (integration/next-phase)

---

## Known Open Issues

- The second `[extractInlineData]` log line in the UC-6b run showed `arrayKeys=none` (single-SMILES, string path). This is correct behavior — a follow-up message in the same session used a single compound; only multi-value inputs go through the array branch.
- `GEMINI_API_KEY` is set in local `.env` only. Dev EC2 has `GOOGLE_API_KEY` but not `GEMINI_API_KEY` — if `extractInlineDataWithLLM` is needed on dev, add the alias to the EC2 environment or update `gemini-flash.ts` to also accept `GOOGLE_API_KEY`.

---

## Next Steps

- Verify dev EC2 has `GEMINI_API_KEY` set (or patch `gemini-flash.ts` to fall back to `GOOGLE_API_KEY`)
- Run UC-1..6b against dev after next sync
- UC-6b log-proof pattern can be reused for other inline data types (accessions, file paths) if regression coverage is needed
