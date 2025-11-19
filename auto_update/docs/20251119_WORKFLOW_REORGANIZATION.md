# Tool Addition Workflow Reorganization

**Date**: 2025-11-19

## Current Issues

1. **Quality Gate Too Late** - Tools added before quality validation
2. **Parameter Extraction After Integration** - Circular dependency
3. **No Feasibility Check** - Platforms/libraries waste processing time
4. **Redundant Extraction** - Multiple passes for same data

## Improved Workflow

```
STAGE 1: Detection
    ↓
STAGE 2: Feasibility Check (NEW) - Filter platforms/libraries
    ↓
STAGE 3: Documentation Fetching
    ↓
STAGE 4: Parameter Extraction (MOVED) - Before wrapper generation
    ↓
STAGE 5: Quality Pre-Check (NEW) - Gate integration
    ↓
STAGE 6: Wrapper Generation - With pre-extracted params
    ↓
STAGE 7: Validation
    ↓
STAGE 8: Integration
```

## Key Changes

### Feasibility Check (Stage 2)
- Filter out: web frameworks, workflow platforms, pure libraries
- Check for CLI indicators in README
- Skip unsuitable tools early

### Parameter Extraction (Stage 4)
- Extract parameters BEFORE wrapper generation
- Pass to wrapper generator for complete XML
- Single Claude API call per tool

### Quality Pre-Check (Stage 5)
- Score ≥ 0.70: Integrate
- Score 0.50-0.69: Flag for review
- Score < 0.50: Reject

## Benefits
- Faster processing (skip bad tools early)
- Better wrapper quality (params included)
- Cleaner database (quality gate)
