# BioMate Workflow Engine Overhaul — Team Update

**Date:** 2026-03-18  
**Author:** Engineering  
**Covers:** Work done since `docs/WORKFLOW_SOURCES_INVENTORY.md` (2026-03-10)  
**Commits:** `782808a6c` → `17b80d3db` (8 commits, 2026-03-17)

---

## Summary

This sprint completed two major workstreams: (1) a full overhaul of the workflow and tool index to correctly classify ~14,000 items across two tables, and (2) fixing the AI workflow generation fallback paths to generate Nextflow workflows instead of the deprecated Galaxy `.ga` format.

---

## 1. Workflow & Tool Index Overhaul (`galaxy_ai_tools.db`)

### Problem
The workflow index was architecturally wrong:
- Galaxy workflows were indexed but all had Nextflow equivalents — dead weight
- nf-core modules (individual tool wrappers) were incorrectly placed in the `workflows` table
- Bioconductor `.nf` files were treated as tool metadata only, never as indexable workflows
- 224 `nextflow_token` stub entries polluted the tools table (garbage from an old tokenizer run)

### What Changed

#### Table architecture clarified

| Table | Role |
|-------|------|
| `workflows` | Complete, executable analysis pipelines (multi-step) |
| `tools` | Individual tool/package executors — used for tool-level search and workflow composition |

#### `workflows` table — rebuilt from 466 → **2,284 entries**

| Source | Count | Priority | Description |
|--------|------:|:---:|---|
| `bioconductor` | **1,818** | 75 | **NEW.** Each Bioconductor `.nf` file is a complete DSL2 workflow (has both `process BIOC_<PKG>` + `workflow BIOC_<PKG>_WORKFLOW` blocks). These are runnable — analogous to `nfcore_subwf`. |
| `biomni_nextflow` | 268 | 85 | BioMate domain analysis workflows |
| `nfcore` | 100 | 100 | Full nf-core pipelines (rnaseq, sarek, chipseq, …) |
| `nfcore_subwf` | 93 | 95 | nf-core composite subworkflows |
| `galaxy_biomni` | 2 | 35 | 2 unique BioMate Galaxy workflows with no NF equivalent yet |

**Removed:** `galaxy_local` (93 entries — Galaxy copies of nf-core subworkflows, redundant), `biomni` legacy entries.

#### `tools` table — cleaned to **12,274 entries**

| Source | Count | Description |
|--------|------:|---|
| Galaxy ToolShed | 7,630 | Community CLI/R/Python tools |
| nf-core modules | **1,645** | **NEW.** Individual nf-core process wrappers (e.g. `nfcore/star/align`, `nfcore/samtools/sort`) — correctly moved here from `workflows` |
| Bioconductor packages | 2,273 | Rich R package metadata: `best_practice_functions` (98% coverage), vignette workflows, container specs |
| Galaxy nf-core wrappers | 231 | Galaxy XML wrappers of nf-core CLI tools |
| BioMate data lake | 726 | Reference datasets (DepMap, BindingDB, DisGeNET, …) |

**Removed:** 224 `nextflow_token` stub entries (garbage from an old workflow tokenizer).

#### `wrapper_path` linking
All 1,818 Bioconductor `.nf` files on disk are now linked to their `tools` table entries via the `wrapper_path` field. This enables the AI to emit `include{}` directives pointing at real files, rather than generating fictional module paths.

#### Re-indexer (`backend/scripts/index_all_workflows.py`)
Full rebuild takes ~7 seconds. New phases:
- Phase 6: `index_bioconductor_as_workflows()` — reads `.nf` files, extracts step count from vignette metadata, infers domain, inserts into `workflows`
- Phase 7: `index_nfcore_modules_as_tools()` — 1,645 nf-core modules → `tools`
- Phase 8: `link_bioconductor_nf_wrappers()` — populates `wrapper_path`

```bash
python3 backend/scripts/index_all_workflows.py --rebuild   # ~7s
```

---

## 2. AI Workflow Generation — Fallback Path Overhaul

### Problem
The three workflow generation confidence paths were all supposed to be Nextflow-native, but the medium and low confidence paths silently generated Galaxy `.ga` format workflows. This was:
- Wrong for all tools now indexed (Bioconductor, nf-core, biomni_nextflow are all Nextflow)
- Ignoring the `wrapper_path` field and `best_practice_functions` semantic data
- Claiming "Step 3: Validate and install tools for ALL paths" when in reality it only ran the Galaxy ToolShed installer, and all Nextflow paths returned early before reaching it

### The three paths (corrected)

```
High confidence (score ≥ 12)
  → Return matched .nf file path directly for Nextflow execution  ✅ (unchanged)

Medium confidence (score 6–11)
  → IF best_match.format is 'nextflow' or 'bioconductor_nf':
      Return the .nf file path (same as high confidence)
      needs_user_feedback=True + review warning            ✅ FIXED
  → IF best_match.format is 'galaxy_ga':
      Fall through to EnhancedWorkflowGenerator (Galaxy)   (unchanged, rare)

Low confidence / no match
  → NextflowComposer.compose_workflow()                    ✅ FIXED (was Galaxy generator)
      No Galaxy fallback — error surfaces cleanly
```

### New: `NextflowComposer` (`backend/lib/galaxy/ai/nextflow_composer.py`)

Replaces `GalaxyWorkflowGenerator` as the fallback for low-confidence or no-match cases.

**What it does:**
1. Searches the full `tools` table (12,274 entries) via `UnifiedToolSearch`
2. Enriches each result with `wrapper_path`, `best_practice_functions`, `scientific_context`
3. Splits tools into two groups:
   - **Composable** (3,463 tools with a `wrapper_path`): emit `include { PROCESS } from 'path/main.nf'` pointing at real files
   - **Ad-hoc** (tools without a `.nf` file): LLM generates a minimal `process { }` block
4. LLM writes a complete DSL2 `main.nf` using real `.nf` files as composable building blocks
5. Validates the output (see below)
6. Writes to `biomni_workflows/nextflow_generated/<timestamp_slug>/main.nf`
7. Returns the path for the Nextflow executor

### New: Nextflow validation (replaces Galaxy ToolShed installer for NF paths)

`NextflowComposer.validate_workflow()` checks what actually matters for Nextflow:

| Check | What it validates |
|-------|-------------------|
| DSL2 declaration | `nextflow.enable.dsl = 2` is present |
| Workflow block | At least one `workflow { }` block |
| Include paths | Every `include { X } from 'path'` resolves to a real `.nf` file on disk |
| Brace balance | `{` / `}` count sanity check |

Tool availability is not checked — container images handle it. The validation result is embedded in the API response as `validation.warnings` and `validation.missing_includes`.

### Tool catalog enrichment (`galaxy_workflow_generator.py`)

The LLM now sees the following per tool (previously only saw name, description, category, keywords, usage_guide):

| Field added | Coverage | Value |
|---|---|---|
| `wrapper_path` | 3,463 tools (28%) | Signals a real `.nf` file exists; suggests `include{}` directive |
| `best_practice_functions` | 3,727 tools (30%), 98% Bioconductor | Ordered step sequence with function names, inputs, outputs |
| `scientific_context` | 10,229 tools (83%) | Primary omics applicability, suitable analysis designs |
| `language` | most tools | Distinguishes R/Python/Nextflow tools for the LLM |

### Step 3 comment fix

The comment `"Step 3: Validate and install tools for ALL paths"` was wrong. Corrected to:
`"Galaxy ToolShed tool validation (Galaxy .ga fallback path only)"` — accurately reflecting that:
- All Nextflow paths return before Step 3
- Step 3 only runs for the galaxy_ga format medium-confidence path (rare case)
- Nextflow validation is now handled inside `NextflowComposer`

---

## 3. Files Changed

| File | Change |
|------|--------|
| `backend/scripts/index_all_workflows.py` | New phases 6–8; correct table routing for all sources |
| `backend/database/galaxy_ai_tools.db` | Rebuilt: 2,284 workflows, 12,274 tools |
| `backend/lib/galaxy/ai/nextflow_composer.py` | **New file.** NextflowComposer + NF validation |
| `backend/lib/galaxy/ai/ai_assistant.py` | Medium/low confidence paths fixed; Step 3 comment corrected |
| `backend/lib/galaxy/ai/galaxy_workflow_generator.py` | Tool catalog now exposes wrapper_path, best_practice_functions, scientific_context |
| `backend/lib/galaxy/ai/unified_workflow_search.py` | SOURCE_PRIORITY: bioconductor restored to 75 |
| `docs/WORKFLOW_SOURCES_INVENTORY.md` | Updated to reflect 2-table architecture and Bioconductor workflow indexing |

---

## 4. What Still Needs Work

| Item | Priority | Notes |
|------|:--------:|-------|
| Convert 2 remaining Galaxy-only workflows to Nextflow | Medium | `synthetic_biology/identify_fas_functional_domains`, `biophysics/predict_protein_disorder_regions` |
| Test `NextflowComposer` end-to-end with a real query | High | Need to verify LLM correctly uses `include{}` for composable tools vs generating process blocks |
| `best_practice_functions` coverage for nf-core modules | Low | Currently 0% — could be populated from nf-core `meta.yml` keywords + tool descriptions |
| Multi-step query splitting (`TaskDecomposer`) | Medium | Still bypassed in `generate_workflow_unified()` — compound queries handled as a single blob |
| Query queuing | Low | No client-side queue; input is disabled while AI is responding |
