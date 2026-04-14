# Domain Knowledge Integration Design

**Date**: 2026-04-04  
**Context**: Audit of all prompts and domain knowledge assets in BioMate

---

## What the Audit Found: A $750K Library with No Card Catalog

BioMate has collected substantial domain knowledge, but most of it is disconnected from the LLM:

| Asset | Size | Status |
|---|---|---|
| Expert knowledge JSON files (7 domains) | 750 KB, highly structured | **Not connected to LLM** |
| QC governance profiles (40+ profiles) | Literature-backed, per-assay | **Not auto-selected** |
| Cryo-EM protocol + parameter DB | SQLite, zero-LLM-cost lookup | Connected (RAG built) |
| Domain specialist guidance strings | 200–1800 chars per domain | Always-on, coarse injection |
| Workflow catalogs | 951+ workflows | Connected (FTS search) |
| QC red lines and gold metrics | Hardcoded thresholds | Connected (enforced) |

The expert knowledge JSON files alone contain structured, literature-backed, situation-specific parameter guidance for 7 domains — with "when/why/source" reasoning for every parameter choice. They are BioMate's most valuable and most wasted asset.

---

## What Each Asset Contains

### Expert Knowledge JSONs (750 KB, currently unused by LLM)

Structure for every parameter in every tool:
```json
"gene_set_size_min": {
  "situations": {
    "default_recommended": {
      "value_or_range": "15",
      "when": "Standard GSEA with 10K-20K gene features",
      "why": "Gene sets <10-15 genes have inaccurate NES; 15 is the balanced minimum",
      "source": "Subramanian et al. 2005, PNAS"
    },
    "sparse_transcriptome": {
      "value_or_range": "5",
      "when": "scRNA-seq or low-coverage RNA-seq (<5M reads)",
      "why": "Small gene set sizes still informative when transcriptome is sparse",
      "source": "Korotkevich et al. 2021, Nature Methods"
    },
    "clinical_targeted_panel": {
      "value_or_range": "3",
      "when": "Targeted gene panel (50–500 genes)",
      "why": "Panel too small for standard cutoffs; must accept small gene sets",
      "source": "TCGA Consortium 2012"
    }
  },
  "common_mistakes": [
    "Using size_min=1 (noise amplification)",
    "Not adjusting for scRNA-seq (high sparsity)"
  ]
}
```

This is not static documentation — it's decision logic. The "when/why" structure maps directly to the context a researcher provides. A research context like "10x Genomics single-cell with 3000 cells" should automatically route to `sparse_transcriptome` settings, not `default_recommended`.

### QC Profiles (40+, currently manual)

Each profile is biology-specific and literature-backed:
- `scrna_cardiac`: mitochondrial fraction threshold 40% (not 20%) — because cardiomyocytes are genuinely mitochondria-rich
- `metagenomics_soil`: classified fraction threshold 3% (not 30%) — because soil "dark matter" is expected
- `wgs_somatic_tumor_only`: coverage requirement 80× (not 30×) — because GATK Mutect2 requires it

The 40 profiles encode knowledge that most bioinformaticians would have to look up. Currently they require a user to manually specify a profile name. Nobody does this.

---

## The Three Broken Connections

### 1. Workflow generation does not use expert knowledge

When the LLM generates a workflow, it fills parameters from the tool schema (name, type, default, allowed values). It does NOT consult:
- The expert knowledge JSON for that tool
- Which situation-specific value applies to this user's context
- What the common mistakes are for this parameter choice

Result: Parameters are schema-valid but not context-appropriate. A DESeq2 workflow generated for a 3-sample pilot study will use the same defaults as a 100-sample clinical trial.

### 2. QC profiles are never automatically matched

When a workflow runs, the QC monitor applies default thresholds unless the user explicitly names a profile. This means:
- A cardiac scRNA-seq run fails QC at 25% mitochondrial fraction (default threshold 20%) — a false positive
- A soil metagenomics run passes QC at 5% classification rate (default 30%) — a false negative
- A FFPE RNA-seq run is flagged for low alignment rate (50%, which is normal for FFPE)

The knowledge to handle all three cases exists in the 40+ profiles. It's just never used automatically.

### 3. Domain specialist guidance is coarse and always-on

When a user asks a cryo-EM question, they get ~1800 chars of cryo-EM guidance. When they ask an RNA-seq question, they get ~280 chars. The guidance is uniform regardless of the specific question — a question about CTF estimation and a question about nanodisc reconstitution both get the same block.

More critically: the other 6 expert knowledge JSON files (genomics, pharmacology, bioimaging, etc.) are never injected at all — only the DOMAIN_SPECIALIST_GUIDANCE strings (100-400 chars) are used. So the 750 KB of structured parameter guidance is completely invisible to the LLM.

---

## Solution: Three New Tool Calls

### Tool 1: `query_expert_knowledge`

Connects the 750 KB expert knowledge JSON to the LLM.

```typescript
const QUERY_EXPERT_KNOWLEDGE = {
  name: "query_expert_knowledge",
  description: `Look up BioMate's curated parameter guidance for a specific tool or analysis step.
Returns situation-specific parameter values with "when", "why", and literature citations.
Call this when setting parameters for any analysis tool — especially when you have context 
about sample type, organism, coverage, assay protocol, or experimental design.`,
  input_schema: {
    type: "object",
    properties: {
      tool_or_analysis: { type: "string", description: "e.g. 'DESeq2', 'GATK HaplotypeCaller', 'GSEA', 'kraken2'" },
      context: { type: "string", description: "Experimental context — sample type, organism, assay, coverage, etc." },
      parameters: { type: "array", items: { type: "string" }, description: "Specific parameters to look up (optional)" },
    },
    required: ["tool_or_analysis", "context"],
  },
};
```

Backend: semantic search over the expert knowledge JSON files by tool name + context. Returns the matching `situations` entries with their when/why/source reasoning.

**Impact on workflow generation**: Instead of "fill from schema", the LLM can now ask "what is the right `gene_set_size_min` for my sparse scRNA-seq data?" and get back "5, because gene sets still informative when transcriptome is sparse (Korotkevich 2021)."

### Tool 2: `select_qc_profile`

Connects the 40+ QC profiles to automatic selection.

```typescript
const SELECT_QC_PROFILE = {
  name: "select_qc_profile",
  description: `Select the appropriate QC profile for a workflow based on experimental context.
QC thresholds are biology-specific — the same metric has different acceptable ranges 
depending on sample type and assay. Call this before any analysis run that will
have QC gates enforced.`,
  input_schema: {
    type: "object",
    properties: {
      workflow_type: { type: "string", description: "e.g. 'rnaseq', 'wgs', 'scrna', 'metagenomics'" },
      sample_context: { type: "string", description: "Tissue type, preservation method, organism, coverage target" },
    },
    required: ["workflow_type", "sample_context"],
  },
};
```

Backend: fuzzy match against the 40+ profile metadata (description + domain_hint). Returns `profile_id`, its threshold overrides, and the citations that justify them.

**Impact on QC**: A cardiac scRNA-seq run automatically gets `scrna_cardiac` profile (mito 40%). A FFPE WGS run gets `wgs_ffpe` (alignment 50%, duplicate 65%). False positives and false negatives both eliminated without user intervention.

### Tool 3: `get_workflow_parameter_template`

Combines workflow search result + expert knowledge + sample context → pre-filled parameter set.

```typescript
const GET_WORKFLOW_PARAMETER_TEMPLATE = {
  name: "get_workflow_parameter_template",
  description: `Get a context-appropriate parameter template for a workflow.
Combines the workflow's parameter schema with expert knowledge for the sample context.
Returns parameters pre-filled with situation-specific recommended values and their rationale.`,
  input_schema: {
    type: "object",
    properties: {
      workflow_name: { type: "string" },
      sample_context: { type: "string", description: "Everything known about the experiment" },
    },
    required: ["workflow_name", "sample_context"],
  },
};
```

Backend:
1. Fetch workflow parameter schema from DB
2. For each parameter, look up expert knowledge for that tool+parameter
3. Match user context to the best `situation` entry
4. Return filled parameters with `value`, `rationale`, `source` per parameter

---

## How the Three Problems Are Fixed

### Problem 1: Workflow generation — Before vs After

**Before**:
```
User: "Run DESeq2 on my cardiac scRNA-seq, 4 conditions, 3 replicates each"
→ LLM fills parameters from tool schema
→ padj=0.05, lfc=1.0, min_counts=10 (schema defaults — same for all experiments)
→ QC threshold: mito 20% (default — wrong for cardiac)
```

**After**:
```
User: "Run DESeq2 on my cardiac scRNA-seq, 4 conditions, 3 replicates each"
→ LLM calls query_expert_knowledge("DESeq2", "cardiac scRNA-seq, 4 conditions, 3 replicates")
  → returns: padj=0.05, lfc=1.5 (for single-cell data, stricter LFC recommended)
             min_counts=5 (sparse transcriptome — Korotkevich 2021)
→ LLM calls select_qc_profile("scrna", "cardiac tissue")
  → returns: scrna_cardiac profile (mito_fraction_pct=40, median_genes=300)
→ Workflow dispatched with context-appropriate parameters + correct QC profile
→ Parameters shown to user with rationale ("LFC=1.5 because scRNA-seq has high 
  biological noise — stricter threshold reduces false discoveries")
```

### Problem 2: QC — Before vs After

**Before**: User runs soil metagenomics → 5% classification rate → QC fails → user confused → manually overrides → no learning.

**After**: 
```
LLM calls select_qc_profile("metagenomics", "soil samples, environmental DNA")
→ returns: metagenomics_soil profile
   classified_pct_critical: 3% (not 30%)
   classified_pct_warning: 8%
   rationale: "Soil dark matter expected; TARA Oceans precedent"
→ QC applied with correct thresholds
→ If result is 5%, QC passes (as expected)
```

### Problem 3: Domain guidance — Before vs After

**Before**: All cryo-EM questions get the same 1800-char block. RNA-seq gets 280 chars. The 750 KB expert JSON is never seen.

**After**: 
```
User: "What GSEA gene set size should I use for my 10x single-cell data?"
→ LLM calls query_expert_knowledge("GSEA", "10x Genomics single-cell RNA-seq")
→ returns: gene_set_size_min=5, when="scRNA-seq or low-coverage RNA-seq",
           why="sparse transcriptome still informative with small gene sets",
           source="Korotkevich et al. 2021, Nature Methods"
→ Response: "For 10x scRNA-seq, use gene_set_size_min=5 (not the default 15).
  Single-cell transcriptomes are sparse and 5-gene sets are still informative.
  Reference: Korotkevich et al. 2021, Nature Methods."
```

The answer is specific, sourced, and correct for the context — not a generic domain block.

---

## What Stays in the System Prompt

The system prompt should retain:
1. **Identity and mission** (BioMate, life science AI)
2. **Tool definitions** (the 3 new tools above + run_code + read_file + dispatch_workflow)
3. **4 behavioral principles** (not 16 rules)
4. **Brief domain routing hints** (5-line workflow routing table — these improve first-turn dispatch speed)

What moves out of the system prompt:
- The static DOMAIN_SPECIALIST_GUIDANCE strings → replaced by query_expert_knowledge calls
- The static cryo-EM parameter table → already in DB, now callable as a tool
- The 12 hard constraint rules → replaced by 4 principles + tool-guided behavior

The domain knowledge is not removed. It becomes MORE accessible and MORE specific — retrievable on demand for the exact context, instead of injected wholesale for every query in the domain.

---

## Prompt Architecture: Before vs After

### Before (current)
```
System prompt (~1900 tokens):
  ├── Identity (50 tokens)
  ├── 16 constraint rules (400 tokens)
  ├── DATA-FIRST RULE (200 tokens)
  ├── Domain specialist blocks for detected domains (~800 tokens)
  ├── Workflow routing hints (100 tokens)
  └── Style guide (50 tokens)

Domain knowledge path:
  User query → domain detected → static block injected → same block for all questions in domain
  
Expert knowledge JSONs, QC profiles: NOT USED
```

### After (proposed)
```
System prompt (~600 tokens):
  ├── Identity (50 tokens)
  ├── 4 behavioral principles (80 tokens)
  ├── Tool definitions × 6 (350 tokens)
  └── Brief workflow routing table (120 tokens)

Domain knowledge path:
  User query
    → LLM reasons about context
    → calls query_expert_knowledge(tool, context) → situation-specific parameters + citations
    → calls select_qc_profile(workflow, sample) → biology-appropriate thresholds
    → calls get_workflow_parameter_template(workflow, context) → pre-filled parameters
    → final response is specific, sourced, and context-appropriate
```

---

## Maturity Gap by Domain

The audit reveals that cryo-EM is deeply integrated while most other domains are thin:

| Domain | Specialist guidance | Expert JSON | QC profiles | Workflow catalog |
|---|---|---|---|---|
| Cryo-EM | 1800 chars + SQLite DB | — | 2 profiles | 11 workflows |
| Genomics | 250 chars | ✅ 105 KB | ✅ 15+ profiles | 9 workflows |
| Transcriptomics | 280 chars | partial | ✅ 8 profiles | (within genomics) |
| Single-cell | 350 chars | partial | ✅ 5 profiles | 6 workflows |
| Drug discovery | 400 chars | ✅ 114 KB (pharmacology) | — | 5 workflows |
| Proteomics | 300 chars | partial | 1 profile | 1 workflow |
| Metagenomics | 250 chars | ✅ partial | ✅ 4 profiles | 0 workflows |
| Metabolomics | 280 chars | ✅ partial | — | 0 workflows |
| Bioimaging | 230 chars | ✅ 97 KB | — | 0 workflows |
| Structural biology | 280 chars | partial | — | 0 workflows |
| Systems biology | 200 chars | ✅ partial | — | 5 workflows |

The expert JSON files cover genomics, pharmacology, bioimaging, molecular_biology, cellbio_immuno, microbio_sysbio — 750 KB of structured knowledge — but none of it is being queried by the LLM.

---

## Implementation Notes

### Connecting expert knowledge JSONs

The 7 JSON files follow a consistent structure. A simple indexer:
1. Flattens all (tool → parameter → situation → value/when/why/source) entries into a searchable format
2. Embeds them in SQLite with FTS5 (or the existing sqlite-vec for semantic search)
3. Exposes via `query_expert_knowledge` tool handler

Estimated indexing time: < 1 minute. Retrieval cost: SQL + optional vector search, zero LLM cost.

### Auto-selecting QC profiles

The QC profile selection is a simple classification problem:
- Input: workflow_type (string) + sample_context (string)
- Output: best matching profile_id from 40+ profiles

A small Haiku call (5 tokens output: just the profile_id) or even keyword matching against profile `description` + `domain_hint` fields. Zero additional infrastructure needed.

### Parameter template generation

Already partially done — the `LLMParameterGenerator` exists. Extend it to:
1. First call `query_expert_knowledge` for each parameter
2. Return the situation-matched value + rationale
3. Show rationale to user in parameter panel ("LFC=1.5 — recommended for scRNA-seq to reduce noise")

This makes the parameter panel not just editable but *educational* — users understand why values were chosen.
