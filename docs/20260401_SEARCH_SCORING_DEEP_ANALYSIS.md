# Search & Scoring Deep Analysis

**Date:** 2026-04-01  
**Branch:** integration/next-phase  
**Files:** `unified_workflow_search.py`, `ai_assistant.py`

---

## 1. Pipeline Overview

```
User query
  │
  ├─ FE intent classifier → preferred_domains, penalized_domains, key_terms
  │
  ▼
generate_workflow_unified(user_intent, key_terms, preferred_domains)
  │
  ├─ Step 0: search_chains(user_intent, min_score=0.35)
  │   Jaccard overlap across example_queries + description + tags
  │   → chain hit → return early (best case)
  │
  ├─ Step 1: _build_intent_trials(user_intent, key_terms)
  │   → [user_intent, user_intent + extra_key_terms]  (at most 2 trials)
  │
  ├─ For each trial:
  │   workflow_search.search(trial, preferred_domains=preferred_domains, key_terms=key_terms)
  │   │
  │   ├─ Pass-0: LLM catalog browse (60 FTS candidates → LLM ranks top 10)
  │   ├─ FTS5 BM25 with abbreviation expansion + key_terms augmentation
  │   ├─ Re-ranking: _calculate_score() for each FTS candidate
  │   ├─ Pass-0 boost: graded +3.0 to +0.3 for LLM-ranked results
  │   └─ Pass-0 rescue: fetch LLM-ranked IDs not in FTS results
  │
  └─ Best result → high/medium/low_confidence → route to Nextflow reuse / adapt / compose
```

---

## 2. Scoring Function Analysis

`_calculate_score()` is a linear sum of 7 independent signals — no normalization:

| Signal | Formula | Typical range | Notes |
|---|---|---|---|
| FTS BM25 | `abs(bm25) * 1.5` | 0–10 | Negative in SQLite; abs applied |
| Keyword match | `sum(weight for matched keywords)` | 0–40+ | 200+ keyword→weight pairs |
| Phrase match | `5.0 + 3.0 * n_phrase_matches` if any | 0 or 8–17+ | Base 5 even for single match |
| Name overlap | `n_common_words * 1.5` | 0–6+ | Query words vs name words |
| Exact name | `+15.0` (exact) / `+8.0` (prefix) | 0 or 8/15 | After nf-core/ stripping |
| Source priority | `SOURCE_PRIORITY[source] / 15` | 0.33–6.67 | nfcore=6.67, bioconductor=5.0 |
| Pipeline intent boost | `±8.0` / `±5.0` | 0, ±5, ±8 | "my data" / "process my FASTQ" |
| Domain bias | `±4.0` | -4 to +4 | from preferred_domains or rule-based |
| User profile | `+2.0` | 0–2 | Only when no other domain signal |

**High confidence threshold: ≥12.0.** A query matching 2 keywords (e.g., `rnaseq`+`star`=5.5) + one phrase + nfcore source + pipeline intent = 0 + 5.5 + 8 + 1.5 + 6.67 + 8 = **29.7**. Scores easily reach 20–40 for good matches.

**Medium confidence threshold: ≥6.0.** Achievable with just FTS + source priority (2 + 6.67 = 8.67). Threshold calibration is not wrong — it correctly separates "has something relevant" from "nothing found" — but the high threshold (12) is very easy to hit for any query with explicit tool names.

---

## 3. Strengths of the Current Design

### 3.1 Two-tier LLM augmentation
- **Pass-0 catalog browse**: An LLM looks at 60 FTS candidates and picks the 10 most semantically relevant. This catches cases where keyword matching and BM25 disagree (e.g., a workflow named differently from what the user called it).
- **Pass-0 rescue**: Directly fetches LLM-selected IDs that ranked below the FTS top-50. This handles the case where the correct workflow has low FTS score but high semantic relevance.

### 3.2 Abbreviation expansion
`ABBREVIATION_MAP` correctly handles domain-specific abbreviations: `wgs → whole genome sequencing`, `rnaseq → rna seq transcriptome`. Both the FTS query and keyword matching use expansion.

### 3.3 Pipeline intent detection
`_detect_pipeline_intent()` with 30+ signals correctly distinguishes "I have FASTQ files" (wants a pipeline) from "explain DESeq2" (wants information). The ±8.0/±5.0 source boost is large and effectively prevents Bioconductor R packages from winning over nf-core pipelines for execution requests.

### 3.4 Key_terms augmentation
`key_terms` from LLM intent decomposition are now used at three levels:
1. Trial query augmentation (`_build_intent_trials`)
2. FTS query string extension in `search()` (deduplication prevents double-counting)
3. NextflowComposer tool retrieval L1

### 3.5 preferred_domains domain bias
With the fix applied today, `preferred_domains` from LLM intent now reaches `_calculate_score()`. Domain alignment adds +4.0, which is meaningful but not overwhelming (~13% of a typical high-confidence score).

---

## 4. Gaps and Weaknesses

### 4.1 `penalized_domains` never used (Gap A — open)

**Current state:** The TypeScript intent classifier returns `penalized_domains` but they are dropped:
- `galaxy-assistant.ts` line 2113–2114: only `preferred_domains` and `key_terms` extracted
- Backend `AIRequestModel`: no `penalized_domains` field
- `search()` hardcodes `penalized_domains = None` when `preferred_domains` is provided

**Impact:** Cross-domain penalization only works via the rule-based `_infer_domain_preferences()` fallback (covers 4 domain combinations). For others — e.g., germline query with `penalized_domains=["cancer_biology", "metagenomics"]` — the penalization is silently dropped.

**Fix needed:**
1. `galaxy-assistant.ts`: extract `penalized_domains` from intent decomposition result
2. `galaxy-api-proxy.ts`: include `penalized_domains` in backend request
3. `AIRequestModel`: add `penalized_domains: Optional[List[str]] = None`
4. `generate_workflow_unified`: accept and forward `penalized_domains`
5. `search()` method: change `penalized_domains = None` hardcode → use passed value
6. `_calculate_score`: already uses `penalized_domains` correctly

**Effort:** ~30 min. 5 files, mechanical wiring.

### 4.2 Keyword weight dictionary has non-discriminative terms (Gap B — cosmetic)

`keyword_weights` includes low-discrimination terms like:
- `'analysis': 1.0` — appears in virtually all queries AND all workflow descriptions → no signal
- `'pipeline': 1.5` — same problem
- `'workflow': 1.0` — same
- `'single': 1.5` — appears in "single-cell" AND "single particle" AND "single sample" → false matches

These terms add score noise. They don't cause incorrect top-1 selection (because good matches accumulate much more from specific terms), but they inflate the medium-confidence boundary.

**Recommendation:** Remove weight entries for generic terms. No code change is urgent — doesn't affect correctness.

### 4.3 Phrase match base bonus is front-loaded (Gap C — design)

`score += 5.0 + phrase_matches * 3.0` means a single phrase match gives a +8 bonus on top of other signals. For a workflow with exactly one phrase overlap, this almost guarantees medium-confidence. This is intentional (phrase matches are strong signals), but the flat 5.0 base could be replaced with the per-phrase value: `score += phrase_matches * 8.0` — same total for one match but cleaner semantics.

**Impact:** Minimal. Both formulas give identical results for n=1.

### 4.4 `_is_executable_nextflow_match` and `_pick_best_executable_nextflow_match` — tier selection logic

These functions filter the search results to find an executable Nextflow workflow (not just a library subworkflow). The current approach returns nf-core full pipelines and BioMate domain workflows but not nf-core library subworkflows. This is correct for standalone execution.

However, when `best_match` is a non-executable subworkflow (Tier-2), the code falls back to `executable_nextflow_match` which picks the highest-scoring executable. This fallback doesn't check if the executable match is topically related — it could substitute a different-domain workflow.

**Recommendation:** After using `executable_nextflow_match`, verify its score is within 30% of `best_match.score`. If the gap is too large, log a warning (may indicate the top result is irrelevant).

### 4.5 Medium-confidence Galaxy .ga reference in NextflowComposer (Gap D — quality)

When a Galaxy .ga match triggers NextflowComposer (medium-confidence, galaxy_ga format), the `reference_match.tools` field contains opaque Galaxy tool IDs (e.g., `toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73+galaxy0`). The LLM receives these as:
```
## REFERENCE WORKFLOW (medium-confidence match — use as structural guide)
Tools used: ['toolshed.g2.bx.psu.edu/repos/devteam/fastqc/...', ...]
```

These tool IDs carry no semantic meaning. The LLM already has the workflow description (and `workflow_steps` from the Galaxy .ga steps — but that's extracted in `ai_assistant.py`, not in `NextflowComposer`).

**Fix needed:** In `ai_assistant.py`, when building the compose_workflow call for a Galaxy .ga match, extract `workflow_steps` (step names/tool labels from Galaxy JSON) and pass them to `compose_workflow` as a `reference_steps` field. In `NextflowComposer._build_prompt()`, use `reference_steps` names in the reference block instead of tool IDs.

---

## 5. Chain Scoring

`search_chains()` uses Jaccard similarity on token overlap:
```
score = |query_tokens ∩ chain_tokens| / |query_tokens ∪ chain_tokens|
```

With `min_score=0.35` (set after the false positive incident on germline queries).

**Potential issue:** Jaccard divides by the union, so a long query with many words will have a lower Jaccard even if all the key terms match. Example:
- query = "perform whole genome sequencing germline variant calling with GATK HaplotypeCaller for rare disease patient NA12878"
- chain "rare_disease_multimodal_workup" has tokens from description + example_queries

This query has ~15 tokens; the chain might match 5 of them → Jaccard ≈ 5/20 = 0.25 (below threshold).

**Recommendation:** Consider using precision (overlap/query_tokens) rather than Jaccard, or a weighted combination. Higher recall at the chain step is better since the chain would be the best match — we'd rather show it and let users confirm than miss it.

---

## 6. Medium-Confidence Nextflow Path Analysis

The medium-confidence Nextflow path (score 6–11.99) directly returns the existing `.nf` template as a "template_adapt" result with `needs_user_feedback=True`. This is the correct behavior — the workflow may need adjustments.

**What happens:**
1. Best Nextflow match found (score 6–11.99)
2. `_return_nextflow_match()` called with `source='template_adapt'`
3. Returns the existing `.nf` file path — no modification
4. Viewer shows it with a yellow "needs review" badge

**Gap:** The system says "adapt template" but actually returns the template unchanged. The user sees the unmodified Nextflow workflow. True adaptation would require using `NextflowComposer` with the existing file as a reference. The current medium-confidence path for Nextflow effectively reuses the template (like high-confidence) but with a lower confidence signal to the user. This is acceptable but slightly misleading.

---

## 7. Low-Confidence / No-Match Path Analysis

When `match_type == "no_match"` or `"low_confidence"`, `NextflowComposer.compose_workflow()` is called. Analysis of the composition quality:

**L0 (cache):** Jaccard ≥ 0.75 on tool IDs — very strict threshold ensures cached results are truly structurally similar. Appropriate.

**L1 (tool retrieval):** FTS on the tools table (12,000+ entries). Now augmented by `key_terms`. Returns at most 30 tools (for low-confidence path).

**L2 (path validation):** Disk stat for each tool's `wrapper_path`. Good — catches stale DB entries.

**L3 (generation):** Single LLM call with pre-validated tool list. The 6 core rules are injected. The prompt structure is clean.

**L4 (validation):** With the include-prefix fix applied today, `validate_workflow()` now correctly resolves relative paths. The retry loop (new) handles remaining hallucinated includes.

**Remaining weakness:** L1 FTS on the tools table searches `name, description, category, language, usage_guide, best_practice_functions, scientific_context, nfcore_metadata`. The `unified_tool_search.py` (separate from `unified_workflow_search.py`) handles this. Its quality determines what tools are retrieved for composition. If the tool search is too broad, the LLM gets irrelevant tools to filter. If too narrow, it misses key tools.

---

## 8. Fixes Applied in This Session

| Fix | File(s) | Impact |
|---|---|---|
| `preferred_domains` wired through to `workflow_search.search()` | `ai_assistant.py` (class + API) | Domain bias now active for all searches |
| `key_terms` forwarded to search (was in signature, not passed) | `ai_assistant.py` | FTS query augmented by LLM terms |
| Corrected confidence threshold comment (8/4 → 12/6) | `ai_assistant.py` | Documentation fix |
| `_INCLUDE_PREFIX` constants off-by-one `../` | `nextflow_composer.py` | All generated include paths now correct |
| Missing include retry loop | `nextflow_composer.py` | LLM gets one correction on hallucinated paths |
| `key_terms` passed to `_retrieve_tools()` | `nextflow_composer.py` | Better tool recall for composed workflows |
| `penalized_domains` wired through 6 files (FE→BE→search) | `galaxy-assistant.ts`, `galaxy-api-proxy.ts`, `galaxy-types.ts`, `api/ai_assistant.py`, `ai_assistant.py`, `unified_workflow_search.py` | Cross-domain penalization now active |
| Galaxy .ga tool IDs → readable names in NextflowComposer | `nextflow_composer.py` | LLM gets `fastqc` not `toolshed.g2.bx.../fastqc/0.73+galaxy0` |
| Rule 7 added to `_build_prompt()` | `nextflow_composer.py` | All params declared in `params {}` block |
| Chain scoring: precision fallback + abbreviation expansion | `unified_workflow_search.py` | Long queries no longer under-scored vs concise chains |
| `AIRequestModel` missing fields (`preferred_domains`, `penalized_domains`, `key_terms`) | `api/ai_assistant.py` | Fixed `AttributeError` at runtime |
| E2E registration rate-limit bypass | `e2e/*.e2e.ts` | `page.setExtraHTTPHeaders` sends bypass token; tests survive >3 registrations/hr |
| Nextflow fallback status: `output_dir.exists()` → check for real result dirs | `nextflow_executor.py` | Failed runs (only `pipeline_info/` created) now correctly report "failed" not "succeeded" |
| `/api/workflows/runs/:id/output_files` reads `s3_output_files` and scans local disk | `routes.ts` | Local dev runs return actual files, not always empty |

## 9. Open Gaps (Not Fixed This Session)

| Gap | Priority | Effort | Status |
|---|---|---|---|
| A: `penalized_domains` not wired through (5 files) | Medium | 30 min | **Fixed** |
| B: Non-discriminative keywords in weight dict | Low | 10 min | Open |
| D: Galaxy .ga tool IDs opaque in NextflowComposer reference | Medium | 1 hour | **Fixed** |
| Chain scoring: Jaccard penalizes long queries + no abbrev expansion | Medium | 30 min | **Fixed** |
| Medium-confidence Nextflow: "adapt" is actually "reuse" | Cosmetic | Design decision | Open |
| NextflowComposer: missing `params {}` rule in generation prompt | Medium | 5 min | **Fixed** |

## 10. E2E Test Results (2026-04-03)

| Suite | Result |
|---|---|
| `germline-complete-e2e.e2e.ts` | **6/6 passing** |
| `full-workflow-e2e.e2e.ts` | Pending (running) |
