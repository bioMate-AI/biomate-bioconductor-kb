# Complete Workflow Generation Flow Review & Improvements

**Date:** 2026-01-19 16:00
**Status:** Complete Review with Bug Fixes

---

## Complete Flow: User Request → Workflow Output

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        USER REQUEST                                      │
│  "Analyze my RNA-seq data for differential expression"                  │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  1. API ENTRY POINT                                                      │
│  POST /api/ai_assistant/generate_workflow                               │
│  File: lib/galaxy/webapps/galaxy/api/ai_assistant.py                   │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  2. INTENT CLASSIFICATION (Optional - for routing)                      │
│  File: lib/galaxy/ai/agents/unified_intent_router.py                   │
│                                                                          │
│  ├─ Keyword Pattern Matching (fast)                                     │
│  │   • "workflow", "pipeline" → workflow_generation                     │
│  │   • "compare", "vs" → result_comparison                              │
│  │   • "benchmark" → benchmark_query                                    │
│  │                                                                       │
│  └─ LLM Fallback (if confidence < 0.6)                                  │
│      Returns: UserIntent + confidence + entities                        │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  3. UNIFIED WORKFLOW GENERATION                                         │
│  File: lib/galaxy/ai/ai_assistant.py:1362                              │
│  Method: generate_workflow_unified()                                    │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│ STEP 3a:      │     │ STEP 3b:      │     │ STEP 3c:      │
│ WORKFLOW      │     │ WORKFLOW      │     │ WORKFLOW      │
│ SEARCH        │     │ SEARCH        │     │ SEARCH        │
│ (951+ in DB)  │     │ (951+ in DB)  │     │ (951+ in DB)  │
│               │     │               │     │               │
│ UnifiedWork-  │     │ UnifiedWork-  │     │ UnifiedWork-  │
│ flowSearch    │     │ flowSearch    │     │ flowSearch    │
│ FTS5 + boost  │     │ FTS5 + boost  │     │ FTS5 + boost  │
│               │     │               │     │               │
│ Score > 0.8   │     │ 0.5 < Score   │     │ Score < 0.5   │
│ HIGH CONF     │     │ < 0.8 MEDIUM  │     │ LOW CONF      │
└───────┬───────┘     └───────┬───────┘     └───────┬───────┘
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│ TEMPLATE      │     │ TEMPLATE      │     │ GENERATE      │
│ REUSE         │     │ ADAPTATION    │     │ FROM SCRATCH  │
│               │     │               │     │               │
│ Use existing  │     │ Enhanced      │     │ GalaxyWork-   │
│ workflow JSON │     │ Workflow      │     │ flowGenerator │
│               │     │ Generator     │     │               │
│               │     │ (multi-strat) │     │ ├─ Domain     │
│               │     │               │     │ │  Detection  │
│               │     │               │     │ ├─ Tool Search│
│               │     │               │     │ ├─ LLM Design │
│               │     │               │     │ ├─ Validation │
│               │     │               │     │ └─ JSON Build │
└───────┬───────┘     └───────┬───────┘     └───────┬───────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  4. DATASET ASSIGNMENT                                                   │
│  File: lib/galaxy/ai/workflow_dataset_selector.py                       │
│  • Map uploaded datasets to workflow input slots                        │
│  • Handle data type conversions                                         │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  5. TOOL VALIDATION & INSTALLATION                                      │
│  • Check if tools exist in Galaxy                                       │
│  • Auto-install from Tool Shed if missing                              │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  6. RETURN RESPONSE                                                      │
│  {                                                                       │
│    success: true,                                                        │
│    workflow_ga: {...},  // Galaxy .ga JSON                              │
│    source: 'template_reuse|template_adapt|tool_constrained',           │
│    confidence: 0.0-1.0,                                                  │
│    generated_parameters: [...],                                         │
│    compatibility_validated: true,                                        │
│    compatibility_warnings: [...],                                        │
│    citations: [...]                                                      │
│  }                                                                       │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## GalaxyWorkflowGenerator Internal Flow (Low Confidence Path)

```
┌─────────────────────────────────────────────────────────────────────────┐
│  GalaxyWorkflowGenerator.generate_workflow()                            │
│  File: lib/galaxy/ai/galaxy_workflow_generator.py:105                  │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  STEP 1: DOMAIN DETECTION (5%)                                          │
│  detect_domain(user_intent)                                             │
│  • TRANSCRIPTOMICS, GENOMICS, PROTEOMICS, EPIGENOMICS                  │
│  • METAGENOMICS, METABOLOMICS, DATA_QUERY, GENERAL                     │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  STEP 2: TOOL RETRIEVAL (10-20%)                                        │
│  UnifiedToolSearch.search()                                             │
│  • LLM Query Analysis (entities, category)                              │
│  • Direct Entity Matching (SQL LIKE)                                    │
│  • Vector Similarity Search                                             │
│  • FTS5 Full-Text Search                                                │
│  • Reciprocal Rank Fusion                                               │
│  Returns: 30 relevant tools                                             │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  STEP 3: LLM WORKFLOW DESIGN (30-50%)                                   │
│  _generate_workflow_structure()                                         │
│  • Domain-specific phases (QC → Alignment → Quantification → DE)       │
│  • LLM constrained to ONLY use retrieved tools                          │
│  • Output: workflow_name, steps[], reasoning                            │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  STEP 4: COMPATIBILITY VALIDATION (55%)                        ← NEW    │
│  validate_workflow_compatibility()                                      │
│  • Check output/input format compatibility                              │
│  • Handle format aliases (fa↔fasta, fq↔fastq)                          │
│  • Returns: is_valid, warnings[]                                        │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  STEP 5: DATASET SELECTION (60-70%)                                     │
│  WorkflowDatasetSelector.select_datasets_for_workflow()                 │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  STEP 6: GALAXY JSON BUILD (80-90%)                                     │
│  _build_galaxy_workflow_json()                                          │
│  • Normalize tool IDs (biomni/ → biomni_)                               │
│  • Generate parameters for data source tools (LLM)          ← FIXED    │
│    - Detects biomate_ds_api_* tools                                    │
│  • Build step annotations                                               │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  STEP 7: CITATIONS & METHODS (95-100%)                                  │
│  ToolKnowledgeProvider + MethodsGenerator                               │
│  • Collect DOI/PMID for each tool                                       │
│  • Generate publication-ready methods text                              │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Bugs Fixed (2026-01-19)

### Bug 1: Missing `generated_parameters` Variable
**File:** `lib/galaxy/ai/ai_assistant.py:1405`
**Issue:** `generated_parameters` only defined in low-confidence path, but used in return for all paths
**Fix:** Added `generated_parameters = []` initialization

### Bug 2: Data Source Tool Detection Missing `biomate_ds_api_*`
**File:** `lib/galaxy/ai/galaxy_workflow_generator.py:953-956`
**Issue:** Galaxy data source tools not detected, missing LLM parameter generation
**Fix:** Added `biomate_ds_api_*` pattern check

---

## Improvements Added (2026-01-19)

### 1. Step Connection Validation
**File:** `lib/galaxy/ai/galaxy_workflow_generator.py:987-1096`
**Method:** `validate_workflow_compatibility()`
- Checks output/input format compatibility between steps
- Handles format aliases and compressed variants
- Integrated into generate_workflow() flow

### 2. Output Enrichment
Added to workflow generation output:
- `compatibility_validated`: bool
- `compatibility_warnings`: list

---

## Key Files

| File | Purpose |
|------|---------|
| `webapps/galaxy/api/ai_assistant.py` | API endpoints |
| `ai/ai_assistant.py` | Main orchestrator, generate_workflow_unified() |
| `ai/agents/unified_intent_router.py` | Intent classification |
| `ai/unified_workflow_search.py` | 951+ workflow search |
| `ai/galaxy_workflow_generator.py` | Tool-constrained generation |
| `ai/enhanced_workflow_generator.py` | Template adaptation |
| `ai/domain_workflow_patterns.py` | Domain detection & phases |
| `ai/workflow_dataset_selector.py` | Dataset assignment |
| `ai/unified_tool_search.py` | Multi-stage tool search |
| `ai/llm_parameter_generator.py` | LLM parameter inference |

---

## Testing Recommendations

1. **API Test:** POST to `/api/ai_assistant/generate_workflow` with RNA-seq intent
2. **High Confidence Path:** Test with exact workflow match
3. **Low Confidence Path:** Test with novel analysis request
4. **Validation:** Test with incompatible tool chains
5. **Data Source Tools:** Test with `biomate_ds_api_*` tools
