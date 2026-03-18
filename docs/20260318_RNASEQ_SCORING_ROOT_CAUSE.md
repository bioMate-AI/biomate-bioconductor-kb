# RNA-seq Workflow Search — Root Cause Analysis

**Date**: 2026-03-18
**Branch**: connection_formal
**Symptom**: `client-demo.e2e.ts` Scene 3 (RNA-seq) never shows a workflow card — shows "Recovery Mode" instead.

---

## Query Under Investigation

```
I want to identify differentially expressed genes in lung adenocarcinoma.
I have a publicly available RNA-seq dataset (GEO accession GSE68086)
comparing tumor vs normal lung tissue (n=58 samples).
Please run a complete RNA-seq differential expression and pathway enrichment
analysis with adjusted p-value < 0.05 and |log2FC| > 1.
```

Expected: `nf-core/rnaseq` workflow card (or equivalent full pipeline)
Actual: "Workflow Generation — Recovery Mode"

---

## Root Cause #1: nf-core/rnaseq has weak FTS score for this query

**File**: `backend/lib/galaxy/ai/unified_workflow_search.py`

### What the FTS query resolves to

`_build_fts_query()` tokenizes the query and builds an OR-joined FTS5 query. Key tokens:
`identify OR differentially OR expressed OR genes OR lung OR adenocarcinoma OR rna OR seq OR dataset OR geo OR accession OR gse68086 OR comparing OR tumor OR norm ...`

### FTS bm25 scores (nextflow-only filter)

| Rank | Workflow | bm25 score |
|------|----------|------------|
| 1 | Geo Data Connector | -30.74 |
| 2 | Transcriptomic Biomarker Discovery | -22.05 |
| 3 | nf-core/differentialabundance | -19.51 |
| ... | (subworkflows) | ... |
| **41** | **nf-core/rnaseq** | **-8.11** |

**Why rnaseq scores weak**: Its name/description/tools contain "rna", "seq", "transcriptomics" but NOT the query-specific terms like "differential", "enrichment", "adenocarcinoma", "GSE68086". The high-scoring results match those rare terms.

**Why Geo Data Connector scores highest**: Its description explicitly mentions GEO accession retrieval, RNA-seq datasets, etc. The query terms "geo", "accession", "gse68086" have high IDF (rare terms) → huge bm25 boost.

---

## Root Cause #2: nf-core/rnaseq is outside the LLM reranker window

After FTS + custom scoring, nf-core/rnaseq ranks **#13** (score=34.16 without API key, ~39 with LLM):

| Rank | Workflow | Score |
|------|----------|-------|
| 1 | Geo Data Connector | 59.82 |
| 2 | Differential Functional Enrichment | 51.62 |
| 3 | nf-core/differential_functional_enrichment | 51.52 |
| 4 | Transcriptomic Biomarker Discovery | 49.58 |
| 5 | nf-core/differentialabundance | 42.76 |
| ... | (somatic variant callers, ATAC-seq, ChIP-seq) | ... |
| **13** | **nf-core/rnaseq** | **34.16** |

The LLM reranker (`_llm_rerank_results`) only sees **top 10 candidates**:
```python
top_candidates = results[:10]  # rnaseq is at #13, never seen
reranked = self._llm_rerank_results(query, top_candidates)
```

The LLM never gets a chance to promote nf-core/rnaseq.

---

## Root Cause #3: `'de': 2.0` substring false positives

The keyword `'de'` (weight 2.0) in `keyword_weights` matches as a **substring** in:
- `differentially` (in query)
- `adenocarcinoma` (in query)
- Any workflow with "de" in names/descriptions/tools

This gives a false +2.0 boost to ALL workflows whose text contains "de" as substring, polluting the scoring.

---

## Root Cause #4: `search_nextflow_workflow` selects wrong fallback

In `api/ai_assistant.py`, when `best = results[0]` (Geo Data Connector) is not in `passed_workflows.txt`:
1. Looks for runnable+executable from remaining results
2. Finds `Transcriptomic Biomarker Discovery` (biomni_nf path, IS in passed_workflows.txt)
3. Returns **Transcriptomic Biomarker Discovery** — wrong for RNA-seq differential expression

The frontend receives a genomics biomarker workflow instead of an RNA-seq pipeline. The AI assistant then generates "Recovery Mode" explanation because the returned workflow doesn't match the user's intent.

---

## Root Cause #5: `workflowAmbiguity` early-exit

In `galaxy-assistant.ts`, when the LLM intent classifier sets `workflowAmbiguity = "rnaseq_type"` (bulk vs single-cell ambiguity), the assistant **immediately returns clarifying questions** without calling `generateWorkflow()`. The test's question detection regex misses some AI question formats, so the demo loop gets stuck.

---

## Fix Plan

### Fix 1: Expand LLM reranker window (line ~317 of `unified_workflow_search.py`)
```python
# Before: top_candidates = results[:10]
top_candidates = results[:20]  # rnaseq at #13 now visible to LLM
```

### Fix 2: Add RNA-seq rules to `_RERANKER_SYSTEM` prompt
Add to the reranker system prompt:
```
- An RNA-seq query mentioning GEO accession, FASTQ files, or raw reads data needs
  nf-core/rnaseq (full upstream pipeline: alignment + quantification).
  Do NOT prefer nf-core/differentialabundance or standalone DE tools — those require
  pre-computed count matrices, not raw GEO data.
- Data fetching/connector workflows (geo_data_connector, archs4) are NOT analysis
  pipelines — never rank them as the primary result for an analysis query.
- Somatic variant calling workflows (bam_tumor_normal, bam_tumor_only) are for DNA
  mutation detection. Do NOT recommend them for RNA-seq/transcriptomics queries.
```

### Fix 3: Remove `'de': 2.0` false positive keyword
The keyword `'de'` is too short for substring matching. Remove it from `keyword_weights`.

### Fix 4: Fix `_nextflow_workflow_key` to recognize `nextflow_nfcore/` paths
Current: only handles `biomni_nf/` and `/subworkflows/` paths.
Add: handle `nextflow_nfcore/domain/workflow/main.nf` pattern.
This makes biomni workflows in the `nextflow_nfcore/` format appear as runnable.

---

## Scoring Trace (Reference)

For `nf-core/rnaseq` with FTS score = -8.11:
```
Step 1: FTS = 8.11 × 1.5 = 12.17
Step 2: keywords = 'rna'(+2.0) + 'expression'(+2.0) + 'de'(+2.0 substring bug) = 6.0
Step 3: phrase 'rna seq' = +8.0 (base 5 + 3×1)
Step 4: name overlap 'rna','seq' = 2 × 1.5 = 3.0
Step 5: source_priority nfcore = 100/50 = 2.0
Step 5a: tags bonus 'rnaseq'→'rna seq' matches query token 'rna' = +4.0
Step 6: LLM domain transcriptomics preferred = +4.0 (in production with API key)
Step 7: LLM key-terms 'rna-seq' in text = +1.5 (in production)
TOTAL (prod): ~40.67
```

For `Geo Data Connector` (FTS score = -30.74):
```
Step 1: FTS = 30.74 × 1.5 = 46.11
Step 2: keywords = 'expression'(+2.0) + 'rna'(+2.0) + 'de'(+2.0) + 'tumor'(+3.5) = 9.5
Step 3: phrase 'rna seq' maybe +8.0
Step 4: name overlap 'geo','data','seq' ≈ 2-3 words = +3.0-4.5
Step 5: biomni_nextflow = 85/50 = 1.7
Step 5a: tags bonus ≈ +4.0
Step 6: LLM domain genomics not preferred = +0
TOTAL (prod): ~72
```

Geo Data Connector dominates due to high FTS score from GEO-specific terms in its description.

---

## Files Changed

| File | Change |
|------|--------|
| `backend/lib/galaxy/ai/unified_workflow_search.py` | Expand reranker window to 20, add RNA-seq reranker rules, remove 'de' keyword, fix nextflow_nfcore path parsing |
