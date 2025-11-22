# Failure Analysis - Clinical & Non-Clinical Use Case Tests

**Date:** 2025-11-06
**Test Run:** 20 scenarios from 10 documented use cases
**Result:** 16/20 passed (80.0%)
**Status:** Needs refinement for production (target: ≥85%)

---

## Failed Tests Analysis

### Failure 1: UC3 - Specific CRISPR (AgriGenomics)
**Query:** "Generate CRISPR sgRNAs for rice OsSWEET14 gene using CHOPCHOP with PAM NGG"
- **Expected:** Legacy
- **Got:** Iterative
- **Reason:** Low confidence

**Root Cause:**
- This query IS very specific (mentions CHOPCHOP tool, PAM NGG parameter, specific gene)
- But `isVerySpecific` detection requires BOTH:
  - `hasSpecificParameters`: `/--[\w-]+|=[\w\.]+|-[a-z]\s+\w+/i` (needs dashes/equals)
  - `mentionsSpecificTools`: `/using\s+\w+|with\s+\w+\s+(aligner|tool|software)/i`

- "with PAM NGG" doesn't match the pattern (should match "with" but PAM is not recognized as aligner/tool/software)
- "using CHOPCHOP" DOES match
- But "PAM NGG" doesn't have `--` or `=` format

**Fix Needed:**
- Broaden `hasSpecificParameters` to include non-flag parameters
- OR recognize tool names (CHOPCHOP, QIIME2, DESeq2) as indicators of specificity

---

### Failure 2: UC5 - Quick DESeq2 (Academic)
**Query:** "Quick differential expression analysis with DESeq2"
- **Expected:** Legacy
- **Got:** Iterative
- **Reason:** Complex query (FALSE POSITIVE - "analysis" triggering complexity)

**Root Cause:**
- Has "quick" → `isSimple = true`
- Has "with DESeq2" → mentions specific tool
- Has high confidence (differential expression keyword)
- BUT: Classified as `analysis_request` instead of `workflow_generation`
- Intent detection sees "analysis" without "workflow/pipeline/build"
- Rule 7 catches it: "Analysis request - clarify if workflow is needed"

**The Problem:**
- "analysis" in query doesn't mean it's ambiguous if user says "quick" or "standard"
- "Quick X analysis" should be treated as workflow generation, not analysis request

**Fix Needed:**
- Don't classify as `analysis_request` if query has `isSimple` indicators
- OR Rule 5 should fire before Rule 7

---

### Failure 3: UC8 - Quick 16S (Core Facility)
**Query:** "Quick 16S rRNA microbiome analysis with QIIME2"
- **Expected:** Legacy
- **Got:** Iterative
- **Reason:** Analysis request

**Root Cause:** Same as Failure 2
- Has "quick" → `isSimple = true`
- Mentions specific tool (QIIME2)
- But classified as `analysis_request`
- Rule 7 sends it to iterative

**Fix Needed:** Same as Failure 2

---

### Failure 4: UC9 - Standard trend (Patient Monitoring)
**Query:** "Generate standard trend analysis for patient lab results"
- **Expected:** Legacy
- **Got:** Iterative
- **Reason:** Low confidence

**Root Cause:**
- Has "standard" → `isSimple = true`
- Has "generate" → should boost confidence
- But classified as `analysis_request`? Or low confidence workflow?

Let's check confidence calculation:
- Base: 0.5
- +0.4 for "workflow|pipeline" (NO - doesn't have these)
- +0.2 for "generate" (YES) → 0.7
- No RNA-seq/proteomics keywords → stays 0.7

So confidence = 0.7, which is < 0.75 threshold
- Rule 3 fires: "Low confidence (0.70) - need clarification"

**The Problem:**
- "Generate standard X" should be high confidence
- "standard" + "generate" should be treated as simple workflow
- But confidence calculation doesn't account for "standard" modifier

**Fix Needed:**
- Boost confidence when "standard" is present
- OR check `isSimple` before applying low confidence rule

---

## Pattern Summary

**Common Issues:**
1. **"analysis" keyword too aggressive** (2/4 failures)
   - Queries with "quick/simple/standard + analysis" being sent to iterative
   - Should be legacy if combined with simplicity indicators

2. **Confidence calculation doesn't account for simplicity** (2/4 failures)
   - "Standard X" and "Quick X" should boost confidence
   - Current logic only checks workflow keywords, not modifiers

3. **Very specific detection too narrow** (1/4 failures)
   - Requires exact `--flag` or `=value` format
   - Misses tool names and non-flag parameters

---

## Recommended Fixes

### Fix 1: Adjust Rule Order (Quick Win)
**Change:** Check `isSimple + high confidence` BEFORE checking `analysis_request`

```javascript
// Current order:
// Rule 5: Simple + high confidence → legacy
// ...
// Rule 7: Analysis request → iterative

// Proposed order:
// Rule 5: Simple + high confidence → legacy (move earlier or enhance)
// Rule 7: Analysis request → iterative (but skip if isSimple)
```

### Fix 2: Enhance Confidence Calculation
**Add:**
```javascript
// In calculateConfidence()
if (/quick|simple|basic|standard/.test(lower)) confidence += 0.2;
```

This would make:
- "Quick DESeq2 analysis" → 0.5 base + 0.2 (generate) + 0.2 (quick) = 0.9 ✅
- "Standard trend analysis" → 0.5 + 0.2 (generate) + 0.2 (standard) = 0.9 ✅

### Fix 3: Refine Analysis Request Detection
**Change:**
```javascript
// In analyzeIntent()
} else if (/analyze|analysis|process/.test(lower)) {
  // Don't classify as analysis_request if has simplicity indicators
  if (/quick|simple|basic|standard/.test(lower)) {
    type = 'workflow_generation';
  } else {
    type = /workflow|pipeline/.test(lower) ? 'workflow_generation' : 'analysis_request';
  }
}
```

### Fix 4: Broaden Very Specific Detection
**Change:**
```javascript
// In analyzeIntent()
const hasSpecificParameters = /--[\w-]+|=[\w\.]+|-[a-z]\s+\w+|PAM|parameter|option/i.test(message);
const mentionsSpecificTools = /using\s+\w+|with\s+(\w+\s+)?(aligner|tool|software|CHOPCHOP|QIIME2|DESeq2|STAR|HISAT2)/i.test(message);
```

---

## Implementation Priority

### Phase 1: Quick Fixes (15 minutes)
1. ✅ Add simplicity modifiers to confidence calculation
2. ✅ Refine analysis_request classification to check isSimple

**Expected Impact:** Should fix 3/4 failures (UC5, UC8, UC9)

### Phase 2: Specific Detection (10 minutes)
1. ✅ Broaden tool name detection
2. ✅ Add common parameter keywords

**Expected Impact:** Should fix 1/4 failures (UC3)

### Total Time: ~25 minutes
**Expected New Pass Rate:** 20/20 (100%)

---

## Re-Test Plan

1. Apply Phase 1 fixes
2. Re-run 20-test suite
3. If ≥90% (18/20), proceed to Phase 2
4. Apply Phase 2 fixes
5. Re-run full 20-test suite
6. Target: 100% (20/20)

---

## Production Readiness Criteria

- ✅ Pass rate ≥ 90% (18/20): Ready for beta testing
- ✅ Pass rate ≥ 95% (19/20): Ready for production
- ✅ Pass rate = 100% (20/20): Excellent, deploy with confidence

**Current Status:** 80% → Needs Phase 1 + Phase 2 fixes

---

**Next Action:** Apply fixes and re-test
