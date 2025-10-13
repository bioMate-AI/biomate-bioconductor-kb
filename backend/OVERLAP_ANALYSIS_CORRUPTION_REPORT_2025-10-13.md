# Overlap Analysis Corruption Report

**Date:** 2025-10-13
**Analyst:** Claude Code

## Executive Summary

Multiple overlap analysis files contain corrupted or incorrect data, leading to wrong tool counts and incomplete missing tools lists. This resulted in generating 1,616 nf-core tools when only 568 should have been generated.

---

## Files Analyzed

### 1. `tool_overlap_analysis_2025-10-12.json` ❌ WRONG
**Location:** `/Users/jingqiwang/biomate/backend/`
**Status:** OLD, CORRUPTED DATA

**Issues:**
- Uses wrong Galaxy database (6,544 tools instead of correct 6,654)
- BioMni: Counts 258 Python FUNCTIONS instead of actual tools
- nf-core: Reports 1,145 missing (should be 568)

**Data:**
```
Galaxy tools: 6,544
BioMni: 258 functions, 4 in Galaxy, 254 missing
nf-core: 1,629 modules, 484 in Galaxy, 1,145 missing
```

**Root Cause:** Used wrong matching algorithm and older Galaxy crawler data

---

### 2. `tool_overlap_analysis_corrected_2025-10-12.json` ⚠️ TRUNCATED
**Location:** `/Users/jingqiwang/biomate/backend/`
**Status:** CORRECT COUNTS, TRUNCATED LISTS

**Issues:**
- Lists are truncated to only 20 items each
- `in_galaxy_list`: Only shows 20 matches (should show all 1,068 for nf-core)
- `missing_list`: Only shows 20 missing (should show all 568 for nf-core)

**Data:**
```
Galaxy tools: 6,654 ✓
BioMni: 100 software, 66 in Galaxy, 34 missing ✓
nf-core: 1,636 modules, 1,068 in Galaxy, 568 missing ✓
```

**Root Cause:** Code in `analyze_tool_overlap.py` had `[:20]` truncation when saving lists

---

### 3. `biomni_galaxy_overlap_corrected.json` ✓ CORRECT (PARTIAL)
**Location:** `/Users/jingqiwang/lcms-platform/galaxy_tools/`
**Status:** CORRECT for BioMni PACKAGES, but incomplete

**Data:**
```
Total BioMni: 161 tools (software packages)
Exact matches: 43
Partial matches: 12
Total in Galaxy: 55
Missing: 106
```

**Issues:**
- Only contains the 55 tools that match Galaxy
- Missing 106 tools are not explicitly listed (only count provided)
- Does NOT analyze the 258 BioMni FUNCTIONS

**Note:** User clarified that the 258 BioMni functions are WORKFLOWS that call actual tools. Need to parse the function code to extract which tools are used internally.

---

### 4. `CORRECTED_MISSING_TOOLS_SUMMARY_2025-10-13.md` ✓ CORRECT COUNTS
**Location:** `/Users/jingqiwang/biomate/backend/`
**Status:** CORRECT SUMMARY

**Data:**
```
nf-core: 1,636 total, 1,068 in Galaxy, 568 missing (65.3% coverage)
BioMni: 100 software, 66 in Galaxy, 34 missing (66.0% coverage)
TOTAL MISSING: 602 tools
```

**Note:** This is the SOURCE OF TRUTH for nf-core numbers. BioMni numbers need recalculation based on actual tool extraction from code.

---

## What Went Wrong

### Error 1: Generated 1,616 tools instead of 568
- Used wrong source file `TRULY_MISSING_TOOLS_2025-10-13.json`
- That file was based on corrupted overlap analysis with 1,145 missing nf-core tools
- Should have used `CORRECTED_MISSING_TOOLS_SUMMARY_2025-10-13.md` which clearly states 568 missing

### Error 2: Misunderstood BioMni tool granularity
- Counted 258 Python functions in `/Users/jingqiwang/Biomni/biomni/tool/` as tools to convert
- These functions are actually WORKFLOWS that execute bioinformatics operations
- Need to parse the function code to extract which actual command-line tools and library functions are called
- Example: `annotate_celltype_scRNA()` calls `scanpy.tl.rank_genes_groups`, `gget`, `gseapy` - these are the actual tools

### Error 3: List truncation in overlap analysis
- Code had `[:20]` slicing when saving complete lists
- Fixed by removing truncation, but entire analysis logic needs rewrite for BioMni

---

## Correct Data Sources

### For nf-core:
- **Total modules:** 1,636 (from `/tmp/nfcore-modules/modules/nf-core/`)
- **In Galaxy:** 1,068
- **Missing:** 568
- **Source:** `CORRECTED_MISSING_TOOLS_SUMMARY_2025-10-13.md`

### For BioMni:
- **Total functions:** 258 (in `/Users/jingqiwang/Biomni/biomni/tool/`)
- **Total packages:** 161 (from `biomni_galaxy_overlap_corrected.json`)
- **Need to extract:** Actual tool calls from the 258 functions
- **Source:** Parse BioMni code with AST to extract tool usage

### For Galaxy:
- **Total tools:** 6,654 (should be higher with complete crawler)
- **Source:** `/Users/jingqiwang/lcms-platform/galaxy_tools/latest_tools_complete/parallel_crawler_merged.json`

---

## Next Steps

### 1. Parse BioMni Code for Tool Extraction ⚠️ CRITICAL
Create script to:
- Parse all 19 BioMni modules in `/Users/jingqiwang/Biomni/biomni/tool/`
- Extract import statements (e.g., `import scanpy`, `import gget`)
- Extract function calls (e.g., `sc.tl.rank_genes_groups`, `gget.search`)
- Extract subprocess/os.system calls for command-line tools
- Map to Galaxy tool equivalents
- Check which are missing from Galaxy

### 2. Rebuild Complete Overlap Analysis
- Use correct Galaxy data (parallel_crawler_merged.json)
- Use extracted BioMni tool usage (after step 1)
- Use correct nf-core modules list (1,636)
- Save COMPLETE lists (no truncation)

### 3. Generate Missing Tools
- Generate 568 nf-core tools (NOT 1,616)
- Generate missing BioMni tool wrappers (count TBD after extraction)
- Ensure all tools work with auto-installation system

---

## Files to Delete

Already deleted (per user request):
- `TRULY_MISSING_TOOLS_2025-10-13.json` ❌
- `TRULY_MISSING_TOOLS_FIXED_2025-10-13.json` ❌
- `tool_overlap_analysis_FIXED_2025-10-13.json` ❌
- `NFCORE_MISSING_INDEX_*.json` ❌
- `backend/tools/nfcore_missing/*.xml` (1,616 files) ❌

Should keep:
- `CORRECTED_MISSING_TOOLS_SUMMARY_2025-10-13.md` ✓
- `tool_overlap_analysis_corrected_2025-10-12.json` (for nf-core data) ✓
- `biomni_galaxy_overlap_corrected.json` (for BioMni package list) ✓

---

## Key Insights

1. **Granularity Mismatch:**
   - nf-core modules = tool-function level ✓ (matches Galaxy)
   - BioMni functions = workflow level ❌ (need to extract actual tools used)

2. **Data Source Priority:**
   - galaxy_tools folder has better BioMni analysis
   - backend folder has better nf-core summary
   - Need to combine both sources

3. **Tool Counts:**
   - nf-core: 568 missing (CONFIRMED)
   - BioMni: Need code parsing to determine actual missing tools
   - Total: 602+ tools (per summary doc)

---

## Conclusion

The overlap analysis corruption stemmed from three main issues:
1. Using outdated Galaxy crawler data
2. Counting BioMni Python functions instead of actual tools
3. Truncating output lists to 20 items

The fix requires:
1. Parse BioMni code to extract actual tool usage
2. Rebuild overlap analysis with correct data sources
3. Generate only the truly missing tools (568 nf-core + BioMni TBD)

**Critical Next Task:** Parse BioMni code to extract tool calls from the 258 workflow functions.
