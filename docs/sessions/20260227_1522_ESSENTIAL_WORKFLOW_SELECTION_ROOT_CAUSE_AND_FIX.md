# Essential Workflow Selection Root Cause and Fix (2026-02-27 15:22)

## Why guardrail alone is not enough

The guardrail blocks obviously risky execution, but it does not improve core candidate ranking/generation quality by itself.
Core quality must be fixed at **selection time** so the top workflow is already domain-correct.

## Root causes found in workflow selection/generation

### 1) Query parsing was fragile for FTS search

- In `backend/lib/galaxy/ai/unified_workflow_search.py`, `_build_fts_query` previously used simple split/token logic.
- Queries with punctuation (e.g., trailing period, symbols) can break FTS query syntax and trigger fallback search.
- Evidence observed during reproduction:
  - `FTS search failed: fts5: syntax error near "."; falling back to LIKE search`
- Impact:
  - Fallback search lowers relevance quality and increases domain drift risk.

### 2) Domain filtering existed in API shape but was not applied from intent in ranking

- The search API supports `domain` filtering, but normal generation path did not pass domain filter from user intent.
- Ranking relied mostly on lexical keyword overlap, source bonus, and phrase matches.
- Impact:
  - Generic QC terms can pull cross-domain workflows when multiple domains share "quality control" vocabulary.

### 3) Domain taxonomy and intent taxonomy are partially misaligned

- Workflow DB domains include values like `variant_calling`, `microbiology`, `general`, etc.
- Pattern module (`domain_workflow_patterns.py`) uses broader scientific domains.
- Impact:
  - Without explicit domain preference mapping in ranking, query intent may not strongly bias final picks.

### 4) Two different signals are surfaced to users

- Tool recommendation text and workflow selection can come from different sub-paths.
- This can produce user-visible inconsistency (narrative says one thing, selected workflow follows another path).

## Core fix implemented (selection layer, not just guardrail)

File changed:
- `backend/lib/galaxy/ai/unified_workflow_search.py`

### A) Robust FTS-safe tokenization

- Replaced loose token split with regex tokenization:
  - strips punctuation safely
  - prevents malformed FTS query terms
- Result:
  - avoids unnecessary fallback to weaker LIKE search.

### B) Domain-aware ranking bias

- Added `_infer_domain_preferences(query)` returning preferred and penalized domain sets.
- Added domain bonus/penalty in `_calculate_score(...)`:
  - preferred domain: +4.0
  - penalized domain: -4.0
- Initial high-impact rule included:
  - WES/tumor-normal/exome/somatic queries prefer `genomics`, `variant_calling`, `cancer_biology`
  - penalize `microbiology`, `metagenomics` for these intents.

## Reproduction before/after behavior checks

After patch, direct search tests show stronger domain alignment for WES prompts:

- Query: `"I need quality control workflow for whole-exome sequencing BAM files from tumor-normal pairs."`
- Top results now consistently prioritize `variant_calling`/genomics workflows (tumor-normal somatic pipelines), instead of drifting to unrelated cross-domain candidates.

## Why this is more essential

This change improves upstream ranking quality, so:
- the selected workflow is more likely scientifically appropriate from the start,
- confidence becomes more meaningful,
- guardrails trigger less often because core matching is better.

## Remaining essential work

1. Expand domain preference rules to a broader ontology (not just WES guard case).
2. Unify domain labels between workflow DB and domain pattern module.
3. Add explicit scientific confidence output (separate from technical/execution confidence).
4. Route ambiguous queries through multi-agent workflow generation by default when confidence is borderline.

