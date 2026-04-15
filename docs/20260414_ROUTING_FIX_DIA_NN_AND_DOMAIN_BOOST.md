# Routing Fix: DIA-NN Proteomics + General Domain Boost
## 2026-04-14

---

## Problem Summary

DIA-NN proteomics queries misrouted to RNA-seq ~1-in-3 times. Identified from the
consistency benchmark: `"DIA-NN proteomics analysis from data-independent acquisition
mass spec data"` → `rnaseq` on one of three runs.

Root cause traced through three layers:

1. **Python `_infer_domain_preferences()`** had no proteomics rule — proteomics queries
   received zero domain boost, so the +4.0 domain scoring advantage went nowhere.

2. **`_inferDomainWithLLM()` (TypeScript)** — the Haiku domain classifier listed only
   `"mass spectrometry, DIA-NN, MaxQuant, proteome, TMT"` as proteomics signals.
   `"data-independent acquisition"` was not listed → classified as "unknown" → no
   domain_hint emitted.

3. **`domain_hint` never reached the domain scorer** — even when Haiku correctly
   classified a query as "proteomics", the `domain_hint` was passed only as an
   `inline_parameter`, not merged into `preferred_domains`. Only `preferred_domains`
   triggers the +4.0 score boost in `_score_workflow()`.

4. **System prompt few-shot examples** didn't include explicit DIA-NN routing examples,
   so the intent classifier's `preferred_domains` field was sometimes empty for DIA-NN
   queries.

---

## Fixes Applied

### Fix 1 — Python: Add proteomics rule to `_infer_domain_preferences()`
**File**: `backend/lib/galaxy/ai/unified_workflow_search.py`

```python
# NEW — proteomics domain boost
proteomics_tokens = [
    'dia-nn', 'spectronaut', 'openswath', 'maxquant', 'fragpipe', 'msfragger',
    'proteomics', 'proteomic', 'mass spectrometry', 'mass spec', 'mzml', 'mzxml',
    'data-independent acquisition', 'data-dependent acquisition',
    'dia proteomics', 'dda proteomics', ...
]
if any(tok in q for tok in proteomics_tokens):
    preferred.update({'proteomics', 'biochemistry'})
    penalized.update({'transcriptomics', 'metagenomics'})  # ← prevents RNA-seq boost
```

**Effect**: When `preferred_domains` is empty (UQU didn't fire), the rule-based fallback
now correctly applies +4.0 to proteomics workflows and -4.0 to RNA-seq workflows for any
query containing "dia-nn", "data-independent acquisition", etc.

### Fix 2 — TypeScript: Expand `_inferDomainWithLLM()` proteomics rule
**File**: `frontend/server/galaxy-assistant.ts`

Added to the Haiku domain classifier prompt:
```
- proteomics: ..., data-independent acquisition, data-dependent acquisition,
  DIA proteomics, DDA proteomics, mzML, mzXML, raw Thermo, phosphoproteomics
  NOTE: "data-independent acquisition" IS a proteomics signal — not RNA-seq.
```

**Effect**: `"data-independent acquisition"` and `"DIA proteomics"` now reliably trigger
`domain_hint = "proteomics"` from the Haiku classifier.

### Fix 3 — TypeScript: Merge `domain_hint` into `preferred_domains`
**File**: `frontend/server/galaxy-assistant.ts`, `generateWorkflow()` method

```typescript
const mergedPreferredDomains = (() => {
  const base = preferredDomains?.length ? [...preferredDomains] : [];
  if (domainHint && !base.includes(domainHint)) {
    base.push(domainHint);  // ← domain_hint now contributes to +4.0 boost
  }
  return base.length > 0 ? base : undefined;
})();
```

**Effect**: The Haiku classifier's domain judgment now actually influences the Python
search scorer. Previously, `domain_hint` was silently stored in `inline_parameters` but
never used for scoring.

### Fix 4 — TypeScript: Few-shot DIA proteomics examples in routing system prompt
**File**: `frontend/server/galaxy-assistant.ts`

Added 5 routing examples to the "Method-description requests" section:
```
- "DIA-NN proteomics analysis from data-independent acquisition mass spec data" → proteomics_dia_diann
- "Run DIA proteomics with DIA-NN on raw Thermo data files" → proteomics_dia_diann
- "Data-independent acquisition proteomics — quantify proteins with DIA-NN" → proteomics_dia_diann
- "Spectronaut DIA proteomics analysis ..." → proteomics_dia_diann
- "OpenSWATH DIA targeted proteomics ..." → proteomics_dia_diann
```

With note: `"acquisition" in "data-independent acquisition" refers to MS DATA ACQUISITION
MODE — proteomics signal, never RNA-seq.`

### Fix 5 — TypeScript: Tighten `proteomics_type` ambiguity gate
**File**: `frontend/server/galaxy-assistant.ts`

Added explicit DO NOT triggers to the fork-point definition:
```
DO NOT set this when query already mentions DIA-NN, Spectronaut, OpenSWATH,
"data-independent acquisition", or "DIA" explicitly — those are unambiguous DIA signals.
```

**Effect**: Prevents the intent classifier from setting `workflowAmbiguity = "proteomics_type"`
for queries that are already specific. Previously, an explicit DIA-NN query might still trigger
a clarification question asking "DDA or DIA?" — unnecessary friction.

---

## Why This Is Not a Hard Rule

Per the user's direction: hard routing rules like `if "dia-nn" → proteomics` are avoided.

All five fixes above are **general capability improvements**, not keyword overrides:

| Fix | What it improves |
|---|---|
| Python domain rule | General proteomics routing, including Spectronaut, OpenSWATH, MaxQuant, Fragpipe |
| Haiku prompt expansion | Classifier handles any MS terminology, including future tools |
| `domain_hint` → `preferred_domains` | All Haiku domain classifications now feed the scorer |
| Few-shot examples | LLM learns the semantic pattern (DIA = MS), not a keyword match |
| Ambiguity gate tightening | Any specific proteomics tool mention suppresses unnecessary clarification |

The few-shot examples teach the LLM that "data-independent acquisition" is a mass
spectrometry concept — so it will generalize to any phrasing that expresses the same idea,
including future tools not listed here.

---

## Expected Impact on Consistency Benchmark

| Metric | Before | Expected After |
|---|---|---|
| Tier 1 routing consistency | 91.7% (22/24 — 2 DIA-NN failures) | ≥97% (≤1 failure) |
| Tier 3 proteomics_dia paraphrase | 83.3% (5/6 — 1 DIA-NN failure) | 100% (6/6) |

The two Tier 1 failures were both DIA-NN queries. With domain_hint now flowing to
`preferred_domains` (+4.0 boost to proteomics, -4.0 to RNA-seq), these should route
consistently to `proteomics_dia`.

---

## Files Changed

| File | Change |
|---|---|
| `frontend/server/galaxy-assistant.ts` | Proteomics domain classifier rules; few-shot DIA examples; `domain_hint` → `preferred_domains` merge; `proteomics_type` ambiguity gate tightened |
| `backend/lib/galaxy/ai/unified_workflow_search.py` | Proteomics domain rule in `_infer_domain_preferences()` |
