# NextflowComposer Gaps — Analysis and Fixes

**Date:** 2026-04-01  
**Branch:** integration/next-phase  
**File:** `backend/lib/galaxy/ai/nextflow_composer.py`

---

## Background

`NextflowComposer` is the fallback workflow generator used for medium-confidence Galaxy
matches (no matching Nextflow template) and low-confidence / no-match cases.  It runs a
4-level pipeline: L0 cache → L1 tool retrieval (FTS) → L2 wrapper validation → L3 LLM
DSL2 generation → L4 syntax validation.

Three gaps were identified during the deep flow audit of 2026-04-01.

---

## Gap 1 — `key_terms` not used in tool retrieval (L1)

**Problem:**  
`generate_workflow_unified()` now accepts `key_terms` (LLM-extracted domain terms from the
intent decomposition step).  These terms were passed all the way to the `compose_workflow()`
call but ignored — `_retrieve_tools()` searched only `user_intent`, missing extra domain
vocabulary the LLM had identified.

**Example:**  
User: "analyse my ATAC-seq data"  
key_terms: ["chromatin accessibility", "peak calling", "MACS2", "deepTools"]  
Without fix: FTS query = "analyse my ATAC-seq data" → misses "MACS2", "deepTools"  
With fix: FTS query = "analyse my ATAC-seq data chromatin accessibility peak calling MACS2 deepTools" → better recall

**Fix:**
- Added `key_terms: Optional[List[str]] = None` param to both `_retrieve_tools()` and `compose_workflow()`
- `_retrieve_tools()` appends key_terms that are not already present in `user_intent`
- Both call sites in `ai_assistant.py` (medium + low confidence) now pass `key_terms=key_terms`

**Cost:** Zero extra calls. FTS query string is slightly longer.

---

## Gap 2 — No retry loop when include paths are missing (L4)

**Problem:**  
After L4 validation, if the LLM hallucinated `include{}` paths outside the validated tool
list, the code logged a warning and wrote the broken file to disk anyway.  The user would
see a workflow that fails at Nextflow parse time because the include targets don't exist.

**Fix:**  
`compose_workflow()` now runs L3+L4 in a `for attempt in range(2)` loop:

- Attempt 0 (normal path): if validation passes → break immediately, zero extra cost
- If `missing_includes` found on attempt 0: append `CORRECTION REQUIRED` block to the prompt
  listing the broken paths and instructing the LLM to replace those `include{}` directives
  with inline `process` blocks (GENERATE style)
- Attempt 1: re-run LLM with corrected prompt; if still missing → write best-effort result

**Cost:** +1 LLM call only when include paths are missing (hallucination case). Zero cost on
the normal path.

**Pattern:** Mirrors the validation retry in `galaxy_workflow_generator.py` (added for
invalid tool IDs) — same bounded-retry principle, different failure mode.

---

## Gap 3 — Wrong `_INCLUDE_PREFIX` constants (path resolution off by one level)

**Problem:**  
All three `_INCLUDE_PREFIX` constants had one extra `../` hop, causing every include path
embedded in generated workflows to point to the wrong directory.

Workflow location: `backend/biomni_workflows/nextflow_generated/{ts}_{slug}/main.nf`

From that directory:
- `../` → `nextflow_generated/`
- `../../` → `biomni_workflows/`  ← bioc + biomni live here
- `../../../` → `backend/`  ← nf-core-modules live here

| Constant | Old (wrong) | New (correct) |
|---|---|---|
| `_BIOC_INCLUDE_PREFIX` | `../../../nextflow_nfcore/subworkflows/bioconductor` | `../../nextflow_nfcore/subworkflows/bioconductor` |
| `_NFCORE_INCLUDE_PREFIX` | `../../../../nf-core-modules/modules/nf-core` | `../../../nf-core-modules/modules/nf-core` |
| `_BIOMNI_INCLUDE_PREFIX` | `../../../nextflow_nfcore/subworkflows` | `../../nextflow_nfcore/subworkflows` |

**Impact:** All generated workflows with `include{}` directives previously embedded wrong
paths.  With the old constants, validation in `validate_workflow()` also used `dummy_slug`
as the reference dir (producing the same wrong resolution), so the bug was masked — both
validation AND the generated file were systematically wrong in the same way.

**Secondary fix:** `validate_workflow()` now uses `_validation_ref` instead of `dummy_slug`
as the placeholder dir name, and adds a comment making the one-level-deep assumption explicit.

---

---

## Gap 4 — `preferred_domains` not forwarded to workflow search

**Problem:**  
`preferred_domains` (LLM-extracted domain classification from intent decomposition) was
available in the API request model (`AIRequestModel.preferred_domains`) but never passed
into `generate_workflow_unified()` or into the `workflow_search.search()` call inside it.

The search engine accepts `preferred_domains` and uses them for domain bias scoring
(`+4.0` for preferred domain, `-4.0` for penalized domain). Without them, every search ran
with `preferred_domains=None`, falling back to the rule-based `_infer_domain_preferences()`
which only covers 4 domain categories. For all other domains the bias was 0.

**Example:**  
User: "run single-cell ATAC-seq peak calling"  
LLM classifies `preferred_domains=["single_cell", "genomics"]`  
Without fix: ATAC-seq bulk pipelines and transcriptomics workflows compete equally  
With fix: single_cell domain gets +4.0 → single-cell ATAC tools rank higher

**Fix:**
- Added `preferred_domains: Optional[List[str]] = None` param to `generate_workflow_unified()`
- `workflow_search.search()` call now passes `preferred_domains=preferred_domains or None`
  and `key_terms=key_terms or None` (key_terms was also missing from the search call)
- API handler now passes `preferred_domains=request.preferred_domains or None`
- Fixed stale comment saying thresholds are 8.0/4.0 (actual: 12.0/6.0 in `_classify_match`)

**Files:** `ai_assistant.py` (both the class method and the webapps API handler)

---

## Summary

| Gap | Severity | Files | Status |
|---|---|---|---|
| 1 — key_terms not passed to NextflowComposer L1 FTS | Medium | `nextflow_composer.py`, `ai_assistant.py` | Fixed |
| 2 — No include-path retry loop in L3/L4 | High | `nextflow_composer.py` | Fixed |
| 3 — Wrong include prefix constants (off by one `../`) | Critical | `nextflow_composer.py` | Fixed |
| 4 — `preferred_domains` not forwarded to workflow search | Medium | `ai_assistant.py` (both files) | Fixed |

All fixes are backward-compatible. No pipeline restructuring. Syntax check passes.
