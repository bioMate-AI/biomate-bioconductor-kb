# Tool Quality Improvement Plan

**Date**: 2025-11-18
**Current Status**: 3/14 tools workflow-ready (21%)
**Target**: 80% workflow-ready

---

## Progress Summary

### Phase 1: Quality Enhancement System (COMPLETED)
- Built unified metadata extractor
- Created quality validator with 6-category scoring
- Integrated into pipeline post-processing
- Fixed parameter type mapping (string -> text)

### Phase 2: Quick Wins (COMPLETED)
- Fixed auto_rush parameter types -> 0.92 (A) Workflow Ready
- Enhanced auto_colabfold I/O and GPU info -> 0.98 (A+) Workflow Ready

### Current Workflow-Ready Tools
1. **auto_foldseek** - 1.00 (A+) - Structure search
2. **auto_colabfold** - 0.98 (A+) - Protein folding
3. **auto_rush** - 0.92 (A) - Parallel execution

---

## Remaining 11 Tools Analysis

### Category 1: CLI Tools (HIGH PRIORITY)
These are real CLI tools that SHOULD have parameters but extraction failed due to insufficient documentation.

| Tool | Score | Issue | Fix Approach |
|------|-------|-------|--------------|
| **mmseqs2** | 0.61 (C) | No params | Fetch from wiki, add easy-search params |
| **seqkit** | 0.55 (D) | No params | Fetch from bioinf.shenwei.me, add subcommands |
| **htslib** | 0.55 (D) | No params | Add samtools/bcftools params |

**Expected Impact**: +3 workflow-ready tools (43% total)

### Category 2: Python Libraries (MEDIUM PRIORITY)
These are Python APIs without CLI interfaces. Need different scoring or alternative parameter definition.

| Tool | Score | Issue | Fix Approach |
|------|-------|-------|--------------|
| **biopython** | 0.47 (F) | No CLI | Add function signatures as pseudo-params |
| **biotite** | 0.55 (D) | No CLI | Extract from API docs |
| **scanpy** | 0.55 (D) | No CLI | Define key functions |
| **graphein** | 0.56 (D) | No CLI | Define core methods |
| **omicverse** | 0.52 (D) | No CLI | Extract API methods |

**Options**:
1. Create "library" tool type with different scoring weights
2. Define API methods as "parameters" for workflow forms
3. Reduce parameter weight for libraries (35% -> 10%)

### Category 3: Platforms/Frameworks (LOW PRIORITY)
These are platforms, not tools - may need reclassification.

| Tool | Score | Issue | Fix Approach |
|------|-------|-------|--------------|
| **nextflow** | 0.49 (F) | Workflow DSL | May not be appropriate as "tool" |
| **dash** | 0.46 (F) | Web framework | Not a bioinformatics tool |
| **galaxy** | 0.46 (F) | Platform | Recursive - Galaxy in Galaxy |

**Recommendation**: Consider excluding these from auto-discovery or creating "platform" category.

---

## Recommended Actions

### Immediate (This Session)
1. [x] Fix parameter type extraction
2. [x] Enhance auto_colabfold
3. [ ] Add mmseqs2 parameters from documentation

### Short-term (Week 1)
4. Improve documentation fetching for CLI tools
5. Enhance seqkit and htslib parameters
6. **Target: 6/14 tools (43%)**

### Medium-term (Week 2)
7. Create "library" tool type classification
8. Adjust scoring weights for Python libraries
9. Extract function signatures for Python tools
10. **Target: 10/14 tools (71%)**

### Long-term (Week 3)
11. Reclassify platforms (nextflow, dash, galaxy)
12. Manual review for complex tools
13. **Target: 11-12/14 tools (80%+)**

---

## Technical Improvements Needed

### 1. Enhanced Documentation Fetching
- Fetch from external docs (not just README)
- Parse --help output if available
- Follow documentation links

### 2. Tool Type Classification
```python
TOOL_TYPES = {
    'cli': {'param_weight': 0.35},  # Current
    'library': {'param_weight': 0.10, 'api_weight': 0.25},
    'platform': {'param_weight': 0.05}
}
```

### 3. Alternative Parameter Extraction
For Python libraries, extract from:
- Function signatures
- Type hints
- Docstrings
- API reference

---

## Metrics

| Metric | Start | Current | Target |
|--------|-------|---------|--------|
| Workflow Ready | 1 (7%) | 3 (21%) | 11 (80%) |
| Average Score | 0.55 | 0.65 | 0.85 |
| CLI Tools Ready | 1/4 | 3/4 | 4/4 |
| Libraries Ready | 0/5 | 0/5 | 4/5 |
| Platforms Ready | 0/3 | 0/3 | 1/3 |

---

## Conclusion

We've made significant progress from 7% to 21% workflow-ready with the quality enhancement system. The main blocker is parameter extraction:

1. **CLI tools** need better documentation fetching
2. **Python libraries** need alternative scoring or parameter definition
3. **Platforms** may need reclassification

With the proposed improvements, we can reach the 80% target within 2-3 weeks.

