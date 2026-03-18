# Tiered Clarification & Domain Knowledge Activation Plan

**Date:** 2026-03-10  
**Problem:** 70% of `EnhancedToolSearch` scoring logic is dormant because `user_context`
(research_domain, num_samples, num_replicates, expertise_level) is never collected.
The DB contains the requirements; the pipeline to collect them from the user is missing.

**Goal:** Collect the minimum user attributes needed to activate domain knowledge scoring —
without adding friction to the common (unambiguous) case.

---

## Background: Where Domain Knowledge Is Stored

BioMate's `galaxy_ai_tools.db` carries three layers of domain knowledge per tool:

### 1. `tools.scientific_context` (JSON, 100% of tools)

A structured JSON blob with five sub-sections:

```
omics_applicability:
  primary_omics:      ["transcriptomics", "cancer genomics"]
  suitable_designs:   ["RNA-seq studies focused on fusion transcript detection"]
  not_suitable:       ["Single-end RNA-seq data", "Long-read sequencing (PacBio, ONT)"]
  data_requirements:
    min_samples:      null | int
    min_replicates:   null | "≥3" | int
    notes:            "free text with caveats"

tool_selection:
  best_for:           ["differential expression with small N", ...]
  not_recommended_for:["when n < 3 per group", ...]

scientific_guidance:
  common_pitfalls:    [{error, cause, fix}, ...]
  key_parameters:     [{name, description, default}, ...]

scientific_assumptions:
  [{assumption: "reads are strand-specific", impact: "..."}]

common_errors:
  [{error: "low mapping rate", cause: "...", fix: "..."}]
```

**Real examples from the DB:**
- `methylKit`: min_replicates = *"≥2 per group; ≥3 recommended for overdispersion correction"*
- `ctat_edger_differential_expression`: min_replicates = *"≥2 per group; n=2 supported but power is very low"*
- `ctat_star_fusion`: not_suitable includes *"Single-end RNA-seq data"*

### 2. `tools.best_practice_functions` (JSON, Bioconductor tools)

An ordered dict of function names → step metadata:
```json
{
  "DESeqDataSetFromMatrix": {
    "step": "1. Create DESeq2 dataset",
    "inputs": ["count_matrix", "col_data", "design_formula"],
    "outputs": ["DESeqDataSet"],
    "description": "..."
  },
  "DESeq": { "step": "2. Run DESeq2 normalization and testing", ... }
}
```
Used by `NextflowComposer._ToolContext.step_summary()` — this is the most consistently active use of domain knowledge. It is embedded in LLM prompts to guide `.nf` file generation.

### 3. `tool_knowledge` table (curated subset)

Richer hand-curated records for key tools:
- `use_cases`: when to use this tool
- `limitations`: when NOT to use it
- `recommended_parameters`: param → {recommended_value, description, evidence_source}
- `common_pitfalls`: structured error/cause/fix records

Used by `_build_scientific_rationale()` to annotate workflow responses.

### 4. `tools.execution_info` (JSON)

Per-tool hardware hints:
```json
{"gpu_required": false, "min_memory_gb": 32, "preferred_cpu": 8}
```
Used by `_collect_workflow_hardware_requirements()` → `execution-env-policy.ts` (active gate).

---

## Background: Where Domain Knowledge Is Currently Used

### A. `NextflowComposer._ToolContext` → LLM prompt enrichment ✅ Active

`best_practice_functions` and `scientific_context` are read per-tool in `_enrich_from_db()`.
Fed into the LLM prompt via:
- `step_summary()` → ordered function sequence with I/O types
- `primary_inputs()` → `omics_applicability.primary_omics`
- `to_llm_block()` → combines all into one tool description block

This directly shapes what the LLM generates in the `.nf` file.

### B. `_build_scientific_rationale()` → Response annotation ✅ Active (high/medium confidence only)

Called in `generate_workflow_unified()` for high- and medium-confidence Nextflow matches.
Reads from both `tool_knowledge` and `tools.scientific_context` to produce:
```
{
  tools_used:       ["DESeq2", "STAR"],
  when_to_use:      ["bulk RNA-seq differential expression", ...],
  do_not_use_when:  ["fewer than 3 replicates per group", ...],
  data_requirements:{min_replicates: "≥3", organism_specific: true},
  key_assumptions:  ["reads are strand-specific", ...],
  common_pitfalls:  [{error, cause, fix}, ...],
  parameter_hints:  [{param, recommended, rationale, tool}, ...]
}
```
Embedded in the workflow response and rendered in the UI.
**Not triggered for low-confidence / composed workflows.**

### C. `_collect_workflow_hardware_requirements()` → Execution gating ✅ Active

Reads `execution_info` per tool, aggregates `gpu_required` + `min_memory_gb`.
Used by `execution-env-policy.ts` to block execution if compute config is insufficient.

### D. `EnhancedToolSearch.search_with_context()` → Scoring ❌ Dormant (70% of weights)

This is the most sophisticated piece — and it is completely bypassed.

The scoring algorithm has five weighted dimensions:

| Weight | Dimension | Source field | Status |
|--------|-----------|-------------|--------|
| 25% | Omics applicability | `scientific_context.omics_applicability.primary_omics` | ❌ Zero — `user_context.research_domain` never provided |
| 20% | Task suitability | `scientific_context.tool_selection.best_for` | ❌ Zero — `filters.suitable_for` never provided |
| 15% | Data requirements | `scientific_context.data_requirements.min_samples` | ❌ Zero — `user_context.num_samples` never collected |
| 10% | User expertise | `scientific_context.scientific_guidance` complexity | ❌ Zero — `user_context.expertise_level` never collected |
| 15% | nf-core validation | `nfcore_metadata.modules` | ✅ Active |

Every call to `create_unified_search()` passes `user_context=None`. The 25%+20%+15%+10% = **70% of scoring is permanently zero**. The not_suitable penalty (-0.40) and not_recommended_for penalty (-0.30) never fire.

The scoring code exists and is correct — it simply has no input to work with:

```python
# EnhancedToolSearch — these branches are always skipped
if user_context and 'research_domain' in user_context:   # ← always False
    if any(user_domain in str(omics).lower() for omics in primary_omics):
        score += 0.25   # never reached

if user_context and 'num_samples' in user_context:       # ← always False
    if user_context['num_samples'] >= min_samples:
        score += 0.12   # never reached
```

---

## Background: What the Clarification System Does Today

`galaxy-assistant.ts` detects **14 workflow-type ambiguities** via intent analysis and asks one
targeted clarifying question via Claude Haiku before calling `generateWorkflow()`:

| Ambiguity type | Question asked |
|----------------|---------------|
| `variant_type` | Germline (inherited) vs somatic (tumor) variant calling? |
| `rnaseq_type` | Bulk RNA-seq vs single-cell RNA-seq? |
| `assembly_type` | De novo vs reference-guided assembly? |
| `peak_calling_type` | ChIP-seq (antibody) vs ATAC-seq (transposase)? |
| `chip_target` | Transcription factor (narrow peaks) vs histone modification (broad)? |
| `proteomics_type` | DDA (MaxQuant) vs DIA (DIA-NN / Spectronaut)? |
| `cryoem_type` | Single-particle SPA vs cryo-ET? |
| `cryoem_sample` | Globular particle vs filamentous assembly? |
| `somatic_paired` | Matched tumor-normal vs tumor-only? |
| `metagenomics_type` | 16S amplicon (QIIME2) vs shotgun (Kraken2)? |
| `docking_type` | Blind docking (DiffDock) vs site-directed (AutoDock Vina)? |
| `rnaseq_focus` | mRNA bulk vs small RNA/miRNA? |
| `flow_cytometry_type` | Immunophenotyping vs unsupervised clustering? |
| `scrna_type` | CRISPR perturbation screen vs standard cell atlas? |

This Tier 1 system handles **workflow-type disambiguation** well. It is triggered when
`workflowAmbiguity` is detected in the intent object returned by `analyzeIntent()`.

**What it does not collect** — the data characteristics that `scientific_context` was built to use:

| Missing attribute | Why it matters | Knowledge field it would unlock |
|-------------------|---------------|--------------------------------|
| **Organism** | Determines genome build, annotation DB, reference indexes | `data_requirements.organism_specific` |
| **Sample count + replicates** | DESeq2 ≥3, edgeR ≥2, methylKit ≥3. Wrong → invalid analysis | `data_requirements.min_samples / min_replicates` (15% weight — currently 0%) |
| **Sequencing type** (paired/single, read length) | Aligner and trimming settings differ completely | `tool_selection.not_suitable` penalty (−0.40 — currently never fires) |
| **Experimental design** (simple, time-course, multi-factor) | Determines DE design matrix | `scientific_context.tool_selection` (20% weight — currently 0%) |
| **Reference genome version** | Causes `ReferenceGenomeFixer` to trigger at runtime if wrong | Not collected → fixed reactively |
| **Expertise level** | Should influence tool complexity and explanation depth | `scientific_guidance` (10% weight — currently 0%) |

---

## Current State Summary

**What works:**
- Tier 1 clarification: 14 workflow-type ambiguities → one Haiku-generated question
- `scientific_context` + `best_practice_functions` → fed into LLM prompts (NextflowComposer)
- `scientific_rationale` block built and shown for high/medium-confidence matches
- Hardware requirements gate: `execution_info` → `execution-env-policy.ts`

**What is dormant:**
- `EnhancedToolSearch.search_with_context()`: 4 of 5 scoring dimensions always return 0
- `data_requirements.min_samples / min_replicates` in DB — never validated against user's data
- `omics_applicability.not_suitable` penalty (−0.40) — never fires
- `tool_selection.not_recommended_for` penalty (−0.30) — never fires
- `scientific_rationale` not personalised (same output regardless of user's organism or design)

---

## Architecture

The solution is **three tiers of clarification**, each triggered only when relevant:

---

## Architecture

The solution is **three tiers of clarification**, each triggered only when relevant:

```
User query
    │
    ▼
Tier 1 (existing): Workflow-type disambiguation          ← already works
    │  e.g. "bulk RNA-seq vs single-cell RNA-seq?"
    │  Triggered: workflowAmbiguity detected in intent analysis
    │
    ▼
Tier 2 (NEW): Data characteristics collection            ← collects user_context
    │  e.g. "Organism? Sample count? Paired-end?"
    │  Triggered: needsWorkflowGeneration=true AND missing_context_fields detected
    │  Asks 1–3 questions in a single structured message
    │
    ▼
Tier 3 (NEW): Pre-generation validation warning          ← uses collected context
    │  e.g. "You have 2 replicates — DESeq2 needs ≥3. Continuing with edgeR instead."
    │  Triggered: collected context violates data_requirements of top-ranked tool
    │
    ▼
Workflow generation with full user_context passed to EnhancedToolSearch
    │  — omics_applicability scoring: 25% active
    │  — task_suitability scoring: 20% active
    │  — data_requirements scoring: 15% active
    │  — expertise_level scoring: 10% active
    │
    ▼
scientific_rationale block personalised to user's data characteristics
```

---

## What to Collect (Tier 2)

The questions are selected dynamically based on: (a) the detected workflow domain,
(b) which `data_requirements` fields are non-null in the top-ranked tools for that domain.

### Always collect (if workflow generation is triggered):

| Attribute | Question | Maps to user_context key |
|-----------|---------|--------------------------|
| **Organism** | "What organism is your data from?" (with common options: Human / Mouse / Other) | `organism` |
| **Sample count per condition** | "How many samples per group/condition?" | `num_samples` |
| **Replicates** | "How many biological replicates per group?" | `num_replicates` |

### Collect only for sequencing workflows (RNA-seq, ChIP-seq, ATAC-seq, WGS, WES):

| Attribute | Question | Maps to user_context key |
|-----------|---------|--------------------------|
| **Read type** | "Paired-end or single-end reads?" | `paired_end` |
| **Read length** | "Read length? (e.g. 75bp, 150bp)" | `read_length` |
| **Sequencing depth** (optional) | "Approximate sequencing depth? (e.g. 30M reads per sample)" | `sequencing_depth` |

### Collect only for variant calling / genome workflows:

| Attribute | Question | Maps to user_context key |
|-----------|---------|--------------------------|
| **Reference genome version** | "Reference genome version? (GRCh38 / GRCh37 / GRCm39 / other)" | `genome_version` |

### Collect only for drug discovery / structural biology:

| Attribute | Question | Maps to user_context key |
|-----------|---------|--------------------------|
| **Input format** | "Are your compounds in SMILES, SDF, or PDB format?" | `compound_format` |

### Always optional (expertise affects explanation depth, not tool selection):

| Attribute | Question | Maps to user_context key |
|-----------|---------|--------------------------|
| **Expertise level** | "Your bioinformatics experience: beginner / intermediate / expert?" | `expertise_level` |

---

## Implementation Plan

### Phase 1: Backend — Context extraction from DB (Week 1)

**File:** `backend/lib/galaxy/ai/unified_tool_search.py`

Add `_infer_required_context_fields(query: str, limit=10) -> List[str]`:
- Runs a quick search for the query (top 10 tools)
- For each tool, reads `scientific_context.data_requirements`
- Returns a list of field names that have non-null values in ≥50% of top results
- Example: for "RNA-seq differential expression" → `['num_replicates', 'organism', 'paired_end']`
- This drives which Tier 2 questions are generated — no hardcoded question lists

```python
def _infer_required_context_fields(self, query: str, limit: int = 10) -> List[str]:
    tools = self.search(query, limit=limit)
    field_counts: Dict[str, int] = {}
    total = len(tools)
    for tool in tools:
        sc = tool.get('scientific_context')
        if not sc:
            continue
        if isinstance(sc, str):
            try: sc = json.loads(sc)
            except: continue
        dr = sc.get('data_requirements') or sc.get('omics_applicability', {}).get('data_requirements', {})
        for field, val in (dr or {}).items():
            if val is not None:
                field_counts[field] = field_counts.get(field, 0) + 1
    # Return fields present in ≥50% of top tools
    return [f for f, count in field_counts.items() if count / max(total, 1) >= 0.5]
```

---

**File:** `backend/lib/galaxy/ai/unified_tool_search.py` — extend `search()` signature

```python
def search(
    self,
    query: str,
    limit: int = 20,
    user_context: Optional[Dict[str, Any]] = None,   # NEW
    filters: Optional[Dict[str, Any]] = None,         # NEW
) -> List[Dict]:
```

Pass `user_context` and `filters` through to `EnhancedToolSearch.search_with_context()`.
This activates the 70% dormant scoring immediately once context is provided.

---

### Phase 2: Backend — Data requirements validation (Week 1)

**File:** `backend/lib/galaxy/ai/ai_assistant.py`

Add `_validate_data_requirements(user_context, tools) -> List[str]`:
- Reads `data_requirements.min_replicates` for top tools
- If `user_context.num_replicates < min_replicates` → generates a warning message
- If a `not_suitable` condition matches the user's organism or design → filters that tool out and selects the next best
- Returns list of warning strings for Tier 3 display

```python
def _validate_data_requirements(
    self,
    user_context: Dict[str, Any],
    search_results: List[Any],
) -> List[str]:
    warnings = []
    num_rep = user_context.get('num_replicates')
    for match in search_results[:3]:
        sc = self._get_scientific_context(match)
        dr = sc.get('data_requirements', {})
        min_rep = dr.get('min_replicates')
        if min_rep and num_rep:
            # Parse "≥3" or "3" from min_replicates
            required = int(re.search(r'\d+', str(min_rep)).group())
            if num_rep < required:
                warnings.append(
                    f"{match.name} requires ≥{required} replicates per group "
                    f"(you have {num_rep}). Considering alternatives."
                )
    return warnings
```

---

### Phase 3: Frontend — Tier 2 question generation (Week 2)

**File:** `frontend/server/galaxy-assistant.ts`

After Tier 1 ambiguity is resolved (or absent), before calling `generateWorkflow()`:
1. Call new backend endpoint `POST /api/ai/required-context` with the query → get list of required field names
2. Check `conversationState` for already-known facts (organism, paired_end, etc. from prior turns)
3. For missing required fields: generate a single structured message with 1–3 questions

```typescript
// After Tier 1 ambiguity check, before workflow generation:
const requiredFields = await this._getRequiredContextFields(message);
const missingFields = requiredFields.filter(f => !this._getContextFact(context, f));

if (missingFields.length > 0 && actions.needsWorkflowGeneration) {
  const questions = this._buildContextQuestions(missingFields, detectedDomain);
  return {
    message: questions,
    awaitingContext: { fields: missingFields },
    // No workflow generated yet
  };
}

// If all context present: pass user_context to workflow generation
const userContext = this._buildUserContext(context);
// userContext = { organism: 'human', num_replicates: 4, paired_end: true, ... }
```

Questions are bundled into a single message, not sequential:

```
To generate the most accurate RNA-seq workflow, I need a few details:

1. **Organism?** Human / Mouse / Other: ___
2. **Biological replicates per group?** (e.g. 3, 4, 6+)
3. **Read type?** Paired-end / Single-end

You can answer all at once, e.g. "Human, 4 replicates, paired-end"
```

---

**File:** `frontend/server/conversation-state.ts`

Add new `FactCategory` values for the new context fields:

```typescript
export type FactCategory =
  | 'sequence' | 'gene' | 'data_type' | 'file_reference' | 'analysis_goal'
  | 'organism'           // NEW
  | 'num_samples'        // NEW
  | 'num_replicates'     // NEW
  | 'paired_end'         // NEW
  | 'read_length'        // NEW
  | 'genome_version'     // NEW
  | 'expertise_level'    // NEW
  | 'compound_format'    // NEW
  | 'other';
```

Extend the fact extraction prompt to parse these from user responses:
"Human, 4 replicates, paired-end" → three extracted facts automatically.

---

### Phase 4: Frontend — Tier 3 warning display (Week 2)

When the backend returns `data_requirement_warnings` in the workflow response:

```typescript
// In workflow-artifact.tsx or chat-message.tsx
if (response.data_requirement_warnings?.length > 0) {
  <Alert variant="warning">
    {warnings.map(w => <p>⚠️ {w}</p>)}
    <p>Proceeding with the best available tool given your data.</p>
  </Alert>
}
```

Example output:
```
⚠️ DESeq2 requires ≥3 biological replicates per group (you have 2).
   Using edgeR instead, which supports 2 replicates (low statistical power — consider adding samples).
```

---

### Phase 5: Context persistence across turns (Week 3)

Context collected in one turn should be remembered for the rest of the session
and used for follow-up queries without re-asking.

**File:** `frontend/server/memory-repository.ts`

Extend `UserPreferences` to store the domain-knowledge context attributes. When a user
says "now do the same analysis for the mouse data", the `organism` fact updates automatically
while `num_replicates` and `paired_end` are inherited.

```typescript
interface UserPreferences {
  // existing ...
  research_organism?: string;
  typical_replicates?: number;
  preferred_read_type?: 'paired' | 'single';
  genome_version?: string;
  expertise_level?: 'beginner' | 'intermediate' | 'expert';
}
```

---

### Phase 6: scientific_rationale personalisation (Week 3)

Currently `_build_scientific_rationale()` returns the same block regardless of the user's data.
With `user_context` available:

- **Filter `when_to_use`** to only show entries matching the user's omics/organism
- **Elevate `common_pitfalls`** that are relevant to the user's replicate count or design
- **Personalise `parameter_hints`** — show the `recommended_value` from `tool_knowledge.recommended_parameters`
  with context: *"For 4 replicates, DESeq2 `minCount = 10` is appropriate"*
- **Flag `do_not_use_when`** entries that match the user's context as active warnings

---

## Summary of Changes Per File

| File | Change | Phase |
|------|--------|-------|
| `backend/lib/galaxy/ai/unified_tool_search.py` | Add `_infer_required_context_fields()`, extend `search()` to accept `user_context` | 1 |
| `backend/lib/galaxy/ai/ai_assistant.py` | Add `_validate_data_requirements()`, pass `user_context` to tool search, add warnings to response | 2 |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | New endpoint `POST /api/ai/required-context` | 2 |
| `frontend/server/galaxy-assistant.ts` | Add Tier 2 question generation between Tier 1 and workflow generation | 3 |
| `frontend/server/conversation-state.ts` | New `FactCategory` values for data characteristics | 3 |
| `frontend/server/routes.ts` | Wire new `/api/ai/required-context` endpoint call | 3 |
| `frontend/client/src/components/chat-message.tsx` | Render `data_requirement_warnings` as Tier 3 alert | 4 |
| `frontend/server/memory-repository.ts` | Persist organism, replicates, read_type across turns | 5 |
| `backend/lib/galaxy/ai/ai_assistant.py` | Personalise `_build_scientific_rationale()` with `user_context` | 6 |

---

## What Gets Unlocked Per Phase

| Phase | Scoring unlocked | User experience |
|-------|-----------------|-----------------|
| 1–2 | Tool search omics (25%) + data_req (15%) | Tools ranked by data compatibility |
| 3 | Task suitability (20%) + expertise (10%) | Questions asked before generation |
| 4 | Data requirement validation | Warning when tools can't handle user's data |
| 5 | Context reuse | No re-asking across turns |
| 6 | Personalised scientific rationale | Pitfalls/hints specific to user's design |

**Total scoring activated: 70% of EnhancedToolSearch (currently 0%).**

---

## Design Principles

1. **Never ask when not needed.** If the query already implies the answer (e.g. "human RNA-seq"), extract it as a fact — don't ask.
2. **Bundle questions, never sequential.** All Tier 2 questions for a workflow are sent in a single message. Users answer in one free-text response.
3. **Parse answers naturally.** "Human, 4 replicates, paired" → three facts extracted by the fact extraction LLM. No form inputs required.
4. **Persist within session, offer to remember across sessions.** After the first workflow, never ask the same question twice for the same user unless the data changes.
5. **Warn, don't block.** If data requirements are violated (insufficient replicates), show a warning and proceed with the best available alternative — never reject the request.
6. **Questions driven by DB content.** The fields we ask about are determined by `data_requirements` in the DB, not hardcoded. As the DB grows, more questions become available automatically.
