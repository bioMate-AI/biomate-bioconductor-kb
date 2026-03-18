# Dual-LLM Workflow Converter Implementation

**Date**: 2025-12-04
**Status**: Completed
**Files**: `backend/lib/galaxy/ai/llm_workflow_converter.py`

---

## Overview

Implemented a bidirectional Galaxy ↔ Nextflow workflow converter using dual-LLM (Gemini + Claude) for enhanced accuracy.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  LLMBidirectionalConverter                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐      ┌─────────────────────────────────┐  │
│  │  LLMConverter  │◄────│  Dual-LLM Consensus Engine      │  │
│  │  (Gemini+Claude)│    │  - Parallel query both LLMs     │  │
│  └─────────────┘      │  - Union subworkflows            │  │
│         │             │  - Union conditionals            │  │
│         ▼             │  - Claude tiebreaker             │  │
│  ┌─────────────┐      └─────────────────────────────────┘  │
│  │  Galaxy→NF  │                                            │
│  │  Converter  │◄──── Rule-based syntax generation          │
│  └─────────────┘                                            │
│         │                                                   │
│         ▼                                                   │
│  ┌─────────────┐                                            │
│  │  NF→Galaxy  │◄──── LLM parsing + rule validation         │
│  │  Converter  │                                            │
│  └─────────────┘                                            │
│                                                             │
│  Docker: biomate/biotools:latest (all tools)                │
└─────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

### 1. Dual-LLM Strategy

Both Gemini and Claude are queried in parallel for workflow analysis:

```python
def call_dual_llm(self, prompt: str) -> Dict[str, str]:
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = {}
        if 'gemini' in self.providers:
            futures[executor.submit(self._call_gemini, prompt)] = 'gemini'
        if 'anthropic' in self.providers:
            futures[executor.submit(self._call_anthropic, prompt)] = 'anthropic'
        # Collect results...
```

### 2. Consensus Merging

Results from both LLMs are merged with union strategy:

- **Subworkflows**: Union of all detected (more is better)
- **Conditionals**: Union of all detected
- **Execution Order**: Prefer Claude's (more reliable)
- **Parallel Groups**: Use Claude's detection

### 3. No Tool ID Matching

All tools run in unified Docker container (`biomate/biotools:latest`):
- No need to map Galaxy ToolShed IDs to Nextflow process names
- Same binaries available on both platforms
- Simplifies conversion significantly

### 4. Parameter Type Preservation

Properly handles Galaxy input types:
- `data_input` → `Channel.fromPath(params.xxx)`
- `parameter_input` → `Channel.value(params.xxx)`

## Test Results

### Dual-LLM Conversion (5 workflows)

| Workflow | Steps | Subworkflows | Conditionals | Status |
|----------|-------|--------------|--------------|--------|
| quantify_pseudo_alignment.ga | 29 | 10 | 3 | ✅ |
| fastq_ngscheckmate.ga | 12 | 3 | 0 | ✅ |
| fastq_align_dna.ga | 15 | 4 | 6 | ✅ |
| fastq_align_bamcmp_bwa.ga | 9 | 5 | 0 | ✅ |
| fastq_taxonomic_profile_metaphlan.ga | 5 | 4 | 0 | ✅ |

### Round-Trip Fidelity (93 workflows)

With rule-based fallback (no LLM):
- **100% fidelity** on all 93 Galaxy workflows
- Proper step count preservation
- Correct input/output type mapping

## API Keys Required

```bash
export GEMINI_API_KEY='AIzaSy...'        # Google Gemini
export ANTHROPIC_API_KEY='sk-ant-...'    # Anthropic Claude
```

## Usage

```python
from llm_workflow_converter import LLMBidirectionalConverter

# Initialize with dual-LLM
converter = LLMBidirectionalConverter()

# Check providers
print(f"Dual-LLM available: {converter.llm.is_dual_available()}")

# Convert Galaxy → Nextflow
result = converter.galaxy_to_nextflow(Path("workflow.ga"))
print(result.workflow['code'])

# Convert Nextflow → Galaxy
result = converter.nextflow_to_galaxy(Path("workflow.nf"))
print(json.dumps(result.workflow, indent=2))

# Round-trip test
result = converter.test_roundtrip(Path("workflow.ga"), 'galaxy')
print(f"Fidelity: {result['fidelity']*100:.0f}%")
```

## Files

- `llm_workflow_converter.py` - Main dual-LLM converter (~700 lines)
- `enhanced_bidirectional_converter.py` - Rule-based converter with tool index
- `dual_llm_converter_system.py` - Original dual-LLM architecture (reference)

## What's Detected

The dual-LLM analysis detects:

1. **Subworkflows**: Logical groupings of steps (alignment, QC, quantification)
2. **Conditionals**: When expressions, alternative tool branches
3. **Execution Order**: Proper step sequencing
4. **Parallel Groups**: Steps that can run concurrently

## Limitations

1. **Actual Commands**: Process scripts contain placeholder commands (not real tool invocations)
2. **Subworkflow Deduplication**: Dual-LLM may produce overlapping subworkflows
3. **When Clause Generation**: Conditionals detected but not yet converted to Nextflow `when:` syntax

## Next Steps

1. Add actual tool command generation (from tool index database)
2. Improve subworkflow deduplication in dual-LLM merge
3. Generate proper `when:` clauses for conditional steps
4. Test with nf-core workflows (Nextflow → Galaxy direction)
