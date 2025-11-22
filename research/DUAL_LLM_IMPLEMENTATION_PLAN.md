# Dual-LLM Workflow Converter Implementation Plan

**Date**: 2025-11-20
**Status**: READY TO IMPLEMENT
**Approach**: Claude + Gemini with Iterative Nextflow Testing

---

## Executive Summary

This document outlines the complete implementation plan for a dual-LLM workflow converter that:
1. Uses both **Claude and Gemini** to convert Galaxy → Nextflow
2. **Tests with real Nextflow** execution
3. **Iteratively refines** until workflows run successfully
4. **Optimizes API costs** through parallel processing and caching

---

## System Architecture

```
                    Galaxy Workflow (.ga)
                            │
                ┌───────────┴────────────┐
                │ Extract Processes (N)  │
                └───────────┬────────────┘
                            │
        ┌───────────────────┼────────────────────┐
        │ PARALLEL CONVERSION (Both LLMs)        │
        │ • Same docs prefix (Gemini cache)      │
        │ • Quick succession (temporal locality) │
        └───────────────────┬────────────────────┘
                            │
                ┌───────────▼────────────┐
                │  Claude Auditor        │
                │  (Merge Best Parts)    │
                └───────────┬────────────┘
                            │
                ┌───────────▼────────────┐
                │  Nextflow Tester       │
                │  (Real Execution)      │
                └───────────┬────────────┘
                            │
                ┌───────────▼────────────┐
                │    Errors Found?       │
                └─┬─────────────────┬────┘
            YES   │                 │ NO
        ┌─────────┘                 └──────────┐
        │ Refinement Loop                      │
        │ (Only Broken Processes)              │
        └──────┐                         SUCCESS!
               │                         Runnable
               │                         Workflow
               │
         Max 3-5 iterations
```

---

## Components

### 1. DocumentationProvider
**File**: `dual_llm_converter_system.py`

**Purpose**: Load and cache all reference documentation

**Key Features**:
- Loads Galaxy format docs, Nextflow format docs, comparison analysis
- Loads real Galaxy workflows and nf-core examples
- Builds **stable prefix** for Gemini implicit caching
- Reuses prefix across all requests for maximum cache hits

**Gemini Caching Strategy**:
```python
# STABLE PREFIX (same for all requests)
prefix = """
# GALAXY TO NEXTFLOW CONVERSION REFERENCE
## Galaxy Format...
## Nextflow Format...
## Examples...
"""

# VARIABLE CONTENT (different per process)
process_content = """
## CONVERSION TASK
Convert this specific process...
"""

# COMPLETE PROMPT = prefix + process_content
# Result: Cache hit on prefix, only pay for process_content
```

**Optimization**: ~10,000 tokens cached, only ~500 tokens variable per request

### 2. GeminiClient
**File**: `dual_llm_converter_system.py`

**Purpose**: Handle Gemini API with optimal caching

**Key Features**:
- Parallel conversion of all processes
- Same prefix for all requests (cache optimization)
- Quick succession for temporal cache locality
- ThreadPoolExecutor for concurrency

**Performance**:
- 10 processes in parallel
- First request: ~2s (cache miss)
- Subsequent: ~0.3s each (cache hit)
- Total for 10 processes: ~4s (vs 20s sequential)

### 3. ProcessConverter
**File**: `dual_llm_converter_system.py`

**Purpose**: Orchestrate both LLMs

**Key Features**:
- Converts all processes with both Claude and Gemini in parallel
- Returns combined results for auditing
- Uses existing Claude converter when available

### 4. AssemblyAuditor
**File**: `dual_llm_converter_system_part2.py`

**Purpose**: Claude audits and merges outputs

**Scoring Criteria** (0-100 points):
- Real command (not echo): 30 points
- Correct tool usage: 20 points
- Proper inputs: 15 points
- Proper outputs: 15 points
- Has directives: 10 points
- Version tracking: 5 points
- Groovy syntax: 5 points

**Decision Logic**:
- If Claude >> Gemini (>20 points): Use Claude
- If Gemini >> Claude (>20 points): Use Gemini
- If close scores: Merge best components

### 5. NextflowTester
**File**: `dual_llm_converter_system_part2.py`

**Purpose**: Test with real Nextflow execution

**Test Modes**:
1. **stub-run** (fast): No real execution, just structure check
2. **preview**: Syntax check only
3. **real**: Full execution with test data

**Error Parsing**:
- Extracts errors by process
- Classifies error types (syntax, missing variable, type mismatch)
- Provides structured feedback for refinement

### 6. IterativeRefiner
**File**: `dual_llm_converter_system_part2.py`

**Purpose**: Main orchestrator for refinement loop

**Process**:
1. **Iteration 1**: Convert ALL processes
2. Test with Nextflow
3. **Iteration 2+**: Refine ONLY broken processes (saves API costs)
4. Repeat until success or max iterations

**Optimization**: Only reconvert broken processes in refinement

---

## Workflow Phases

### Phase 1: Initial Conversion (Iteration 1)

**Input**: Galaxy workflow with N processes

**Steps**:
1. Extract processes from Galaxy .ga file
2. **Parallel LLM Conversion**:
   - Claude converts all N processes (using existing converter)
   - Gemini converts all N processes (parallel, cached prefix)
   - Both complete in ~5-10 seconds for 10 processes
3. **Audit**: Claude compares and merges (N comparisons)
4. **Assemble**: Build complete Nextflow workflow
5. **Test**: Run with Nextflow stub mode

**Output**:
- Merged workflow files
- Test results with errors (if any)

### Phase 2: Iterative Refinement (Iterations 2-5)

**Input**:
- Broken processes (subset of N)
- Error details from previous test

**Steps**:
1. **Targeted Refinement**:
   - Convert ONLY broken processes with both LLMs
   - Include error feedback in prompts
   - Gemini still uses cached prefix
2. **Re-audit**: Claude merges refined versions
3. **Re-test**: Run Nextflow again
4. **Check**: Success? → Done. Errors? → Next iteration

**Optimization**: If 2/10 processes failed, only reconvert those 2

### Phase 3: Success or Best Attempt

**Success Case**:
- Workflow runs without errors
- Return final workflow files
- Report: X iterations, Y API calls

**Failure Case** (max iterations reached):
- Return best attempt (fewest errors)
- Report remaining errors
- Suggest manual fixes

---

## Cost Optimization Strategies

### 1. Gemini Implicit Caching
**Savings**: ~80% on repeated context

**How it works**:
```
Request 1: 10,000 token prefix + 500 token content = 10,500 tokens
Request 2: 10,000 cached + 500 new = 500 tokens charged
Request 3: 10,000 cached + 500 new = 500 tokens charged
...
Total for 10 requests: 10,000 + (10 × 500) = 15,000 tokens
Without caching: 10 × 10,500 = 105,000 tokens
Savings: 85%
```

### 2. Parallel Processing
**Savings**: ~50% total time

**How it works**:
- Convert 10 processes in parallel: ~4 seconds
- Sequential would take: ~20 seconds
- Time saved: 16 seconds (80%)

### 3. Incremental Refinement
**Savings**: ~70% in iteration 2+

**How it works**:
- Iteration 1: Convert 10 processes (10 API calls × 2 LLMs = 20 calls)
- Iteration 2: Only 2 broken processes (2 calls × 2 = 4 calls)
- Savings: 80%

### 4. Component-Level Parallelism
**Savings**: Real-time execution, no waiting

**How it works**:
- Claude and Gemini convert in parallel
- Auditing happens when both finish
- No sequential blocking

---

## API Cost Estimate

### Small Workflow (5 processes)

**Iteration 1**:
- Gemini: 10k prefix + (5 × 500) = 12.5k tokens (~$0.02)
- Claude: 5 processes × 5k context = 25k tokens (~$0.05)
- **Total**: ~$0.07

**Iteration 2** (2 broken):
- Gemini: 10k cached + (2 × 500) = 1k tokens (~$0.002)
- Claude: 2 processes × 5k = 10k tokens (~$0.02)
- **Total**: ~$0.022

**Full refinement (3 iterations)**: ~$0.15

### Medium Workflow (20 processes)

**Iteration 1**:
- Gemini: 10k + (20 × 500) = 20k tokens (~$0.04)
- Claude: 20 × 5k = 100k tokens (~$0.20)
- **Total**: ~$0.24

**Iteration 2** (5 broken):
- Gemini: 10k cached + (5 × 500) = 2.5k tokens (~$0.005)
- Claude: 5 × 5k = 25k tokens (~$0.05)
- **Total**: ~$0.055

**Full refinement (3 iterations)**: ~$0.50

### Large Workflow (50 processes)

**Iteration 1**: ~$0.60
**Full refinement**: ~$1.20

---

## Test Data Strategy

### Phase 1: Small Test Workflows (Week 1)

**Start with**:
- FastQC → Trim → Align (3 tools)
- Simple RNA-seq (5 tools)

**Test data**:
- Minimal FASTQ (100 reads, ~4KB)
- Small reference (single gene, ~10KB)

**Purpose**: Validate system without large costs

### Phase 2: Medium Workflows (Week 2)

**Scale to**:
- Full RNA-seq (10-15 tools)
- ChIP-seq (8-12 tools)

**Test data**:
- Small real dataset (1000 reads)
- Subset reference (one chromosome)

**Purpose**: Test realistic complexity

### Phase 3: Production Workflows (Week 3)

**Full scale**:
- Complete RNA-seq (20+ tools)
- Multi-omics (30+ tools)

**Test data**:
- From nf-core test datasets
- Or user-provided samples

**Purpose**: Production validation

---

## Implementation Steps

### Week 1: Build and Validate System

**Day 1-2: Core Implementation**
```bash
cd /home/yzhang/biomate/backend/lib/galaxy/ai

# 1. Review and test dual_llm_converter_system.py
python3 -m py_compile dual_llm_converter_system.py
python3 -m py_compile dual_llm_converter_system_part2.py

# 2. Create main execution script
# (see run_dual_llm_converter.py)

# 3. Test with minimal workflow
python3 run_dual_llm_converter.py \
    --galaxy-workflow test_minimal.ga \
    --output output/test1 \
    --max-iterations 3
```

**Day 3-4: Test with Small Workflows**
- Convert FastQC workflow
- Convert Trim-Galore workflow
- Measure success rate, costs, time

**Day 5: Optimization**
- Tune scoring thresholds
- Refine error parsing
- Improve merge logic

### Week 2: Scale to Medium Workflows

**Day 6-8: RNA-seq Workflow**
- Convert full RNA-seq (quantify_pseudo_alignment.ga)
- Test iterative refinement
- Document common errors and fixes

**Day 9-10: Additional Domains**
- ChIP-seq workflow
- Variant calling workflow
- Measure generalization

### Week 3: Production Ready

**Day 11-13: Full Production Workflows**
- Multi-omics workflows
- Complex conditional workflows
- Stress test the system

**Day 14-15: Documentation and Deployment**
- Create user guide
- Build error knowledge base
- Deploy to production

---

## Success Metrics

### Technical Metrics
- **Success Rate**: % of workflows that run without errors
  - Target: >80% after 3 iterations
- **Convergence Speed**: Average iterations to success
  - Target: <2.5 iterations
- **Error Reduction**: % error reduction per iteration
  - Target: >60% reduction

### Cost Metrics
- **API Cost per Workflow**: Total cost for conversion + refinement
  - Target: <$1 for large workflows
- **Cost per Process**: Average cost per tool conversion
  - Target: <$0.05

### Performance Metrics
- **Conversion Time**: Total time for conversion + testing
  - Target: <2 minutes for medium workflows
- **Parallel Efficiency**: Time saved vs sequential
  - Target: >50% time reduction

---

## Risk Mitigation

### Risk 1: Both LLMs produce broken code
**Mitigation**:
- Start with high-quality input (well-formed Galaxy workflows)
- Use extensive documentation in prompts
- Have fallback to existing single-LLM converter

### Risk 2: Nextflow testing takes too long
**Mitigation**:
- Use stub-run mode (fast, no execution)
- Only use real execution for final validation
- Parallel test execution if multiple workflows

### Risk 3: API costs exceed budget
**Mitigation**:
- Aggressive caching (Gemini implicit cache)
- Incremental refinement (only broken processes)
- Set hard cost limits per workflow

### Risk 4: Iterative refinement doesn't converge
**Mitigation**:
- Max 3-5 iterations hardcoded
- Return best attempt if not successful
- Log detailed iteration history for analysis

---

## Next Steps

1. ✅ **Review this plan** - Confirm approach with user
2. **Create main execution script** - `run_dual_llm_converter.py`
3. **Test Gemini API** - Verify credentials and model access
4. **Test Nextflow installation** - Ensure Nextflow is available
5. **Run first test** - Convert minimal 3-process workflow
6. **Iterate and refine** - Improve based on results

---

**Ready to implement!** The complete architecture is designed and coded.

Files created:
- `/backend/lib/galaxy/ai/dual_llm_converter_system.py` (Part 1)
- `/backend/lib/galaxy/ai/dual_llm_converter_system_part2.py` (Part 2)
- `/research/DUAL_LLM_IMPLEMENTATION_PLAN.md` (This document)

Next: Create execution script and begin testing.
