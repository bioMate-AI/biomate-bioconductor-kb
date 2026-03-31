# BioMate Rule-Based & Keyword-Based Methods Audit
**Date:** 2026-03-30  
**Purpose:** Pre-release inventory of every non-LLM decision rule in the system

---

## Executive Summary

BioMate's non-ML logic is concentrated in **five areas**: workflow search scoring, frontend routing, QC gate enforcement, error classification fallbacks, and parameter inference from file types. The QC gate is intentionally rule-based and represents a feature (cited thresholds, auditability). The search scoring is the most complex rule engine and the most fragile — it depends on carefully tuned keyword weights and stopword lists. Several rules are English-centric and would need internationalization for non-English users.

---

## 1. Workflow Search Scoring (`unified_workflow_search.py`)

This is the largest rule engine in the system. It runs on every query to rank ~2,445 workflows.

### 1.1 Source Priority Table
```python
SOURCE_PRIORITY = {
    "nfcore":        100,  # Full nf-core pipelines
    "nfcore_subwf":   95,  # nf-core composite subworkflows
    "biomni_nextflow": 85, # BioMate domain workflows
    "bioconductor":   75,  # Bioconductor R package NF wrappers
    "biomate":        70,
    "galaxy_biomni":  35,
}
```
**What it controls:** Adds a fixed bonus to every workflow score based on its catalog source.  
**Assessment:** Correct priority order. Risk: Bioconductor penalty (-25 vs nfcore) is large enough that a highly specific Bioconductor workflow may be outranked by a vague nf-core one.

### 1.2 Keyword Weight Dictionary
A manually curated dictionary mapping ~80 domain terms to numeric weights. Examples:
- `"rna-seq"`, `"rnaseq"`, `"transcriptomics"` → high weight
- `"molecular dynamics"`, `"gromacs"`, `"amber"` → high weight
- `"metagenomics"`, `"16s"`, `"amplicon"` → high weight

**Logic:** If a keyword appears in both the expanded query AND the workflow record (name, description, tools, tags), its weight is added to the score.  
**Assessment:** The dictionary is comprehensive but manually maintained. Adding a new assay type (e.g. spatial proteomics) requires a manual update. Substring matching means `"de"` could match both "differential expression" and "de novo assembly".

### 1.3 FTS Query Builder (`_build_fts_query`)
```python
tokens = re.findall(r"[a-z0-9]+", query.lower())
tokens = [t for t in tokens if t not in STOPWORDS and len(t) > 1]
tokens = expand_via_abbreviation_map(tokens)
fts_query = " OR ".join(deduplicated_tokens)
```
**Stopwords:** `{'i', 'want', 'to', 'the', 'a', 'an', 'run', 'using', 'with', 'on', 'for', 'my', 'some', ...}`  
**Assessment:** OR-query maximizes recall at cost of precision. "run nf-core/rnaseq" → FTS for `rnaseq OR nfcore` which is good. But "analyze my samples" → FTS for `analyze OR samples` which is very broad.

### 1.4 Abbreviation Map (`ABBREVIATION_MAP`)
Maps short forms to expansions:
- `"rnaseq"` → `["rna-seq", "rna_seq", "transcriptomics"]`
- `"de"` → `["differential", "expression"]`
- `"wgs"` → `["whole", "genome", "sequencing"]`
- `"qc"` → `["quality", "control", "fastqc", "multiqc"]`

**Assessment:** Covers common abbreviations. Gap: spatial transcriptomics abbreviations ("visium", "merfish", "seqfish") are not represented.

### 1.5 Pipeline Intent Signals (`_PIPELINE_INTENT_SIGNALS`)
```python
PIPELINE_INTENT_SIGNALS = [
    "i have", "i have data", "i want to run", "run a pipeline",
    "nextflow run", "fastq", "bam files", "raw reads",
    "my samples", "input data", "process my",
]
```
**Logic:** Any signal present → `+8` to nfcore/biomni_nextflow scores, `-5` to bioconductor.  
**Edge cases:**
- `"fastq"` triggers even in "what is a fastq file?" (informational query)
- `"i have"` triggers on "I have a question about..." 
- English-only; "我有FASTQ数据" would not match

### 1.6 Domain Preference Heuristic (`_infer_domain_preferences`)
Nested token-matching logic:
```python
if any(t in query for t in ["wes", "exome", "somatic", "tumor"]):
    preferred = ["genomics", "variant_calling"]
    penalized = ["microbiology"]
elif any(t in query for t in ["16s", "microbiome", "metagenomics"]):
    preferred = ["microbiology", "metagenomics"]
elif any(t in query for t in ["drug", "smiles", "compound", "docking", "admet"]):
    preferred = ["pharmacology", "drug_discovery"]
    penalized = ["microbiology", "metagenomics"]
```
**Score impact:** `±4` per domain match  
**Assessment:** Correct domain groupings. Risk: "cancer" is in the somatic block but could be relevant for single-cell, RNA-seq, or even metagenomics in tumor microenvironment studies.

### 1.7 Exact/Near Name Match Bonus
```python
if query_bare == name_bare:   score += 15  # exact
elif name_bare.startswith(query_bare): score += 8  # prefix
```
Where `name_bare` = workflow name with `nf-core/` stripped.  
**Assessment:** This is the strongest signal. "nf-core/rnaseq" in the query will always surface the rnaseq pipeline first regardless of other scores.

### 1.8 Match Tier Classification
```python
if score >= 12: tier = "high_confidence"
elif score >= 6: tier = "medium"
else: tier = "low"
```
**Assessment:** Thresholds are empirical. A score of 11.9 is classified "medium" even if it's clearly the best match among 2,445 workflows. Consider making tier relative to score distribution.

### 1.9 Workflow Chain Search (`search_chains`)
Jaccard similarity between query tokens and chain metadata:
```python
score = |intersection| / |union|  # Jaccard
threshold = 0.15
```
**Assessment:** Jaccard on bag-of-words is noisy. "drug discovery ADMET screening" → Jaccard score may not distinguish between the ADMET chain and the full target-to-lead chain. A user asking for "just the ADMET part" may get the full 6-step chain recommended.

---

## 2. Frontend Routing (`galaxy-assistant.ts`)

### 2.1 Intent → Action Mapping (`inferActionsFromType`)
A lookup table mapping intent string to which backend services to activate:
```typescript
const defaults = {
  workflow_generation: { needsWorkflowGeneration: true, needsToolSearch: false, ... },
  tool_search:         { needsToolSearch: true, needsWorkflowGeneration: false, ... },
  research_question:   { needsLLMReasoning: true, needsResearch: true, ... },
  drug_discovery:      { needsWorkflowGeneration: true, needsBenchmark: false, ... },
  // ...
}
```
**Assessment:** Hard mapping. If the LLM routes to `tool_search` but the user actually needs a workflow, the system won't attempt workflow generation. The overlap between intent types is handled by multi-intent decomposition, but routing errors are not recoverable within a turn.

### 2.2 Extended Thinking Enabler (`shouldEnableThinking`)
**Simple patterns** (thinking OFF):
```typescript
const simplePatterns = [
  /^(hi|hello|hey|thanks|thank you)/i,
  /what can you do/i,
  /^(yes|no|ok|sure|okay)/i,
]
```
**Complex patterns** (thinking ON):
```typescript
const complexPatterns = [
  /design\s+(a\s+)?.*pipeline/i,
  /compare\s+.*\s+(vs|versus|or)\s+/i,
  /troubleshoot/i,
  /explain\s+.*\s+(mechanism|pathway|process)/i,
]
```
**Assessment:** The list is reasonable but the logic is: simplePatterns first (fast NO), then complexPatterns (YES), then `intent === 'workflow_generation'` (YES). Short queries to workflow generation still get thinking enabled. Consider: thinking for simple "run nf-core/rnaseq" adds latency without benefit.

### 2.3 Doom Loop Detection
```typescript
if (this.consecutiveWorkflowFailures >= 3) {
    // Force a recovery mode
}
```
**Assessment:** Good safety valve. The threshold of 3 is reasonable — prevents infinite retry loops.

---

## 3. QC Gate (`qc_trace_monitor.py`)

The QC gate is the most complex and most valuable rule engine. It is **intentionally** rule-based because the rules are cited to regulatory/publication standards.

### 3.1 Red Lines (non-overridable minimum thresholds)
```python
QC_RED_LINES = {
    "reads_surviving_pct": {"min": 50, "reason": "< 50% reads surviving = likely chemistry failure"},
    "alignment_rate":       {"min": 5,  "reason": "< 5% = catastrophic mapping failure"},
    "fit_quality":          {"min": 0.5, "reason": "< 0.5 correlation = likely wrong model"},
    "mito_fraction_pct":    {"max": 80, "reason": "> 80% mito = dead cells"},
}
```
**Assessment:** Correct and defensible. These are absolute minimum sanity checks, not science-grade thresholds.

### 3.2 Gold Metrics (non-overridable, evidence-grade)
```python
QC_GOLD_METRICS = ["mapped_pct", "tss_enrichment", "nrf_score"]
```
These metrics use evidence-graded thresholds from publications. Users cannot override them.  
**Assessment:** Good governance. Clear distinction between "this would be insane" (red lines) and "published benchmarks say this is the minimum acceptable" (gold).

### 3.3 Named QC Profiles
14 named profiles including: `rnaseq_default`, `rnaseq_ffpe` (relaxed), `wgs_30x`, `scrnaseq_10x`, `metagenomics_default`, `cryoem_spa`, `proteomics_dda`, `cheminformatics_default`, `pharmacogenomics_pgx`.

Each profile has domain-specific threshold overrides and citation strings.  
**Assessment:** Excellent. This is exactly how clinical-grade QC should work — named, versioned, cited. Gap: no version numbers on profiles; if thresholds are updated, historical runs can't easily be re-evaluated.

### 3.4 Profile Inference (`infer_qc_profile`)
```python
def infer_qc_profile(nextflow_path):
    path = nextflow_path.lower()
    if "drug" in path or "admet" in path or "docking" in path:
        return "cheminformatics_default"
    if "cryo" in path or "cryoem" in path:
        return "cryoem_spa"
    if "somatic" in path or "tumor" in path or "cancer" in path:
        return "wgs_30x"  # closest match
    # ... etc
```
**Assessment:** Keyword-based path inference. **Known false positive:** `"cancer_rnaseq"` would match the somatic profile, but cancer RNA-seq should use `rnaseq_default`. Should add `"rnaseq"` to the RNA-seq branch with higher priority than `"cancer"`.

### 3.5 Process Name → Metric Parser Routing
The largest rule table in the codebase. Maps process name substrings to parser functions:
```python
if "FASTQC" in process_name:    → parse_fastqc_output()
if "STAR_ALIGN" in process_name: → parse_star_output()
if "MOTION_CORRECTION" in process_name: → parse_motioncor_output()
# ~30+ more rules
```
**Assessment:** Maintainable but fragile against nf-core version changes. If nf-core renames `STAR_ALIGN` to `STAR_ALIGNREADS` in a future release, the QC gate silently stops working for that process. **Recommend:** Add a test that lists expected process names and alerts if a new workflow version introduces an unrecognized process name.

---

## 4. Error Classification Fallback (`ai_assistant.py`)

When `ANTHROPIC_API_KEY` is not set, error explanation uses keyword matching:
```python
if "no such file" in log or "file not found" in log:
    error_type = "missing_file"
elif "docker" in log and ("pull" in log or "error" in log):
    error_type = "docker_pull"
elif "memory" in log or "oom" in log or "out of memory" in log:
    error_type = "resource_limit"
elif "missing" in log and "param" in log:
    error_type = "missing_parameter"
else:
    error_type = "unknown"
```
**Assessment:** Very coarse. Most Nextflow errors are `process_error` (a process exited with non-zero) which doesn't match any of these patterns → always falls back to `unknown`. When `ANTHROPIC_API_KEY` is set (production), this code is never reached. This is only a gap for local dev/staging environments without an API key.

---

## 5. Parameter Suggestion from File Types (`nextflow_executor.py`)

```python
_FILE_TYPE_PARAM_SUGGESTIONS = {
    "fastq": [
        {"param_id": "strandedness", "suggested_value": "auto", "confidence": "medium"},
    ],
    "bam": [
        {"param_id": "skip_alignment", "suggested_value": True, "confidence": "high"},
    ],
    "vcf": [
        {"param_id": "skip_variantcalling", "suggested_value": False, "confidence": "medium"},
    ],
    "h5ad": [
        {"param_id": "input_format", "suggested_value": "h5ad", "confidence": "high"},
    ],
}
```
**Assessment:** Advisory only — shown as suggestions, not enforced. Very limited coverage. `fastq.gz` is correctly normalized to `fastq`. Gap: No suggestions for nf-core/rnaseq-specific parameters like `genome`, `aligner`.

---

## 6. Intent Classification Fallback (`ai_assistant.py`, `_simple_intent_classify`)

Used when `UnifiedIntentRouter` is unavailable:
```python
workflow_keywords = ["workflow", "pipeline", "run", "execute", "analyze", "analysis"]
compare_keywords = ["compare", "benchmark", "versus", "vs"]
tool_keywords = ["find tool", "what tool", "which tool", "best tool"]

if any(kw in query_lower for kw in workflow_keywords):
    return "workflow"
elif any(kw in query_lower for kw in compare_keywords):
    return "compare"
```
**Assessment:** Backstop only. "analyze" matches `workflow_keywords` so almost any analytical question routes to workflow generation — this is probably intentional as a safe default.

---

## 7. Frontend Thinking Detector (`thinking-detector.ts`)

Detects Claude's `<thinking>` blocks and separates them from `<answer>` blocks:
```typescript
const THINKING_REGEX = /<thinking>([\s\S]*?)<\/thinking>/g;
const ANSWER_REGEX = /<answer>([\s\S]*?)<\/answer>/g;
const BRIEF_THRESHOLD = 50;   // words
const DETAILED_THRESHOLD = 200; // words
```
**Assessment:** Simple and correct. No issues.

---

## Summary: Rules That Carry Release Risk

| Rule | Risk | Impact | Recommended Fix |
|------|------|--------|----------------|
| FTS OR-query broadness | Medium | Poor search quality for vague queries | Add AND for high-confidence exact matches |
| Pipeline intent on "fastq" keyword | Low | Informational queries misdirected | Require "fastq" + action verb |
| Cancer path → somatic QC profile | Medium | Wrong QC thresholds for cancer RNA-seq | Add RNA-seq detection before somatic |
| Process name substring matching in QC gate | High | Silent QC bypass on nf-core renames | Add process name registry test |
| 0.15 Jaccard threshold for chains | Medium | Wrong chain recommended | Use keyword overlap instead of Jaccard |
| Static capability counts in LLM prompt | Low | Stale capability claims | DB-backed count at startup |
