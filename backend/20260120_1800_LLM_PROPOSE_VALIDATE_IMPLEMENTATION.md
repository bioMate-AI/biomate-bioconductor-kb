# LLM-Propose-Then-Validate Implementation

**Date:** 2026-01-20 18:00
**Status:** Complete

---

## Summary

Implemented the LLM-Propose-Then-Validate workflow generation architecture as discussed. This approach allows the LLM to use its full domain knowledge to propose workflows, then validates and refines them against the Galaxy tool index and benchmark knowledge.

---

## Components Implemented

### 1. ToolIndexValidator (`workflow_proposal_validator.py`)

Validates proposed tools against the Galaxy tool index.

**Features:**
- Exact match by tool name
- Alias matching (e.g., "STAR" -> "rna_star")
- Fuzzy string matching (Levenshtein distance)
- Category-based matching (e.g., "aligner" -> finds alignment tools)

**Tool Aliases Supported:**
```python
TOOL_ALIASES = {
    "star": ["rna_star", "star_aligner"],
    "hisat2": ["hisat", "hisat_2"],
    "salmon": ["salmon_quant"],
    "kallisto": ["kallisto_quant"],
    "fastqc": ["fastqc_quality"],
    "trimmomatic": ["trimmomatic_tool"],
    "cutadapt": ["cutadapt_tool"],
    "deseq2": ["deseq", "deseq_2"],
    "edger": ["edger_tool"],
    "bwa": ["bwa_mem", "bwa_tool"],
    "bowtie2": ["bowtie", "bowtie_2"],
    "samtools": ["samtools_tool"],
    "bcftools": ["bcftools_tool"],
    "gatk": ["gatk_tool", "gatk4"],
    "featurecounts": ["subread_featurecounts", "feature_counts"],
    ...
}
```

### 2. KnowledgeValidator (`workflow_proposal_validator.py`)

Validates tool choices against benchmark knowledge.

**Features:**
- Decision rule lookup from `benchmark_knowledge.db`
- Context-aware recommendations
- Warning generation for suboptimal choices
- Best practice retrieval

### 3. WorkflowProposalValidator (`workflow_proposal_validator.py`)

Orchestrates validation of entire workflows.

**Key Methods:**
- `validate_workflow()` - Validates all steps
- `generate_refinement_prompt()` - Creates LLM refinement prompts

### 4. ProposeValidateWorkflowGenerator (`propose_validate_workflow_generator.py`)

Main generator implementing the propose-validate-refine loop.

**Flow:**
```
User Intent → LLM Proposes Workflow → Validate Against Index → Validate Against Knowledge → Refine if Needed → Output
```

**Configuration:**
- `MAX_REFINEMENT_ITERATIONS = 2` - Maximum refinement attempts
- Automatic fallback to validated workflow after max iterations

---

## Integration into AI Assistant

Updated `ai_assistant.py` to use propose-validate generator for low confidence cases:

```python
# ai_assistant.py line 72
self.propose_validate_generator = ProposeValidateWorkflowGenerator(config=self.config)

# In generate_workflow_unified() for score < 0.5
if score < 0.5:
    result = self.propose_validate_generator.generate_workflow(
        user_intent=user_intent,
        data_characteristics=data_characteristics
    )
```

---

## API Response Structure

The propose-validate generator returns:

```python
{
    'success': True,
    'workflow': {...},           # Validated workflow structure
    'workflow_ga': {...},        # Galaxy .ga format
    'validation': {
        'all_tools_available': True,
        'all_tools_recommended': True,
        'confidence_score': 0.95,
        'steps': [...]
    },
    'refinement_history': [...], # All refinement iterations
    'confidence': 0.95,
    'domain': 'transcriptomics',
    'needs_manual_review': False
}
```

---

## Test Results

### Basic Generation Test
```
[PASS] Workflow generated successfully
  - Domain: transcriptomics
  - Confidence: 1.00
  - All tools available: True
  - All tools recommended: True
  - Iterations: 1
  - Steps: 4
  - LLM calls: 1

Workflow steps validation:
  ✓ Step 1: FastQC -> FOUND (ID: toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.74+galaxy1)
  ✓ Step 2: HISAT2 -> FOUND (ID: toolshed.g2.bx.psu.edu/repos/devteam/hisat/hisat/1.0.3)
  ✓ Step 3: featureCounts -> FOUND (ID: toolshed.g2.bx.psu.edu/repos/yhoogstrate/featurecounts/...)
  ✓ Step 4: DESeq2 -> FOUND (ID: toolshed.g2.bx.psu.edu/repos/iuc/deseq2/deseq2/2.11.40.8+galaxy0)
```

### Refinement Test
```
[INFO] Testing refinement with unavailable tools...

Success: True
LLM calls: 2
Iterations: 2

Refinement history:
  Iteration 0:
    - All available: False
    - Needs refinement: True
    - Confidence: 0.82
      ✓ FastQC: FOUND
      ✓ STAR: FOUND
      ~ SomeUnknownTool: SUBSTITUTE

  Iteration 1:
    - All available: True
    - Needs refinement: False
    - Confidence: 1.00
      ✓ fastqc: FOUND
      ✓ hisat2: FOUND
      ✓ gatk: FOUND
```

---

## Files Created/Modified

### New Files:
- `workflow_proposal_validator.py` - Core validation components
- `propose_validate_workflow_generator.py` - Main generator
- `tests/test_propose_validate_simple.py` - Test suite

### Modified Files:
- `ai_assistant.py` - Added propose-validate integration

---

## Benefits

1. **Leverages LLM Domain Knowledge** - LLM can propose any tool it knows, not just search results
2. **Ensures Tool Availability** - Every tool validated against Galaxy index
3. **Knowledge-Grounded** - Tool choices validated against benchmark knowledge
4. **Transparent** - Full validation trace and refinement history
5. **Self-Correcting** - Automatic refinement with validation feedback

---

## Next Steps (Optional)

1. Add more tool aliases as discovered
2. Expand benchmark knowledge rules
3. Add caching for repeated queries
4. Consider parallel validation for large workflows
