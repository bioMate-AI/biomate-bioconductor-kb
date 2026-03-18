# Pre-Execution Validation & Conversational Preparation Design

**Created**: 2026-01-16 16:10
**Status**: Design Document
**Author**: BioMate Development

---

## Executive Summary

Design a **LLM-powered pre-execution validation system** that intelligently validates workflow prerequisites before Galaxy submission. Rather than hardcoding validation rules, the system leverages:

1. **Tool Database** - Rich metadata about tools, parameters, input/output formats
2. **LLM Intelligence** - Context-aware matching, recommendations, and conversational responses
3. **Galaxy APIs** - Real-time information about user's datasets and histories

---

## Design Philosophy

### What NOT to Do (Hardcoded Approach)
```typescript
// BAD: Hardcoded format lists
const FASTQ_FORMATS = ['fastq', 'fastqsanger', ...];
const COMMON_GENOMES = [{ value: 'hg38', label: 'Human' }, ...];

// BAD: Rigid format matching
if (FASTQ_FORMATS.includes(dataset.extension)) {
  return 'compatible';
}
```

**Problems:**
- Only works for known formats
- Doesn't understand biological context
- Can't adapt to new tools or domains
- No reasoning about compatibility

### What TO Do (LLM + Database Approach)
```typescript
// GOOD: Query tool database for dynamic schema
const toolSchema = await toolDatabase.getToolSchema(toolId);
const inputRequirements = toolSchema.inputs;

// GOOD: Use LLM to understand compatibility
const compatibility = await llm.analyze({
  prompt: `Given workflow input requirement: ${inputRequirement}
           And available dataset: ${datasetInfo}
           Are they compatible? Consider:
           - File format compatibility
           - Biological data type match
           - Any preprocessing needed`,
  context: { toolDocumentation, datasetMetadata }
});

// GOOD: LLM generates contextual response
const response = await llm.generate({
  prompt: `Generate a helpful message asking user to select
           input data for this ${workflowType} workflow.
           Available datasets: ${datasets}
           Required inputs: ${requirements}`
});
```

**Benefits:**
- Works across all life science domains
- Understands biological context
- Adapts to new tools automatically
- Provides intelligent recommendations

---

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                   PRE-EXECUTION VALIDATION SYSTEM                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────┐     ┌─────────────────┐     ┌──────────────┐  │
│  │  TOOL DATABASE  │     │    LLM ENGINE   │     │  GALAXY API  │  │
│  │                 │     │                 │     │              │  │
│  │ • Tool schemas  │     │ • Compatibility │     │ • Histories  │  │
│  │ • Parameters    │     │   analysis      │     │ • Datasets   │  │
│  │ • Input/output  │     │ • Contextual    │     │ • Metadata   │  │
│  │   formats       │     │   suggestions   │     │              │  │
│  │ • Documentation │     │ • Conversational│     │              │  │
│  │ • Scientific    │     │   responses     │     │              │  │
│  │   context       │     │                 │     │              │  │
│  └────────┬────────┘     └────────┬────────┘     └──────┬───────┘  │
│           │                       │                      │          │
│           └───────────────────────┼──────────────────────┘          │
│                                   │                                  │
│                                   ▼                                  │
│                    ┌──────────────────────────────┐                 │
│                    │   PREREQUISITES VALIDATOR    │                 │
│                    │                              │                 │
│                    │  1. Parse workflow inputs    │                 │
│                    │  2. Query available data     │                 │
│                    │  3. LLM compatibility check  │                 │
│                    │  4. Generate suggestions     │                 │
│                    │  5. Build conversational     │                 │
│                    │     response                 │                 │
│                    └──────────────────────────────┘                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Validation Flow

```
User: "Run differential expression analysis on my RNA-seq data"
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 1: Parse Workflow Requirements (from Tool Database)            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Query: Get tool schemas for all workflow steps                     │
│                                                                      │
│  Result: [                                                          │
│    { step: 0, type: 'data_input', label: 'RNA-seq reads' },        │
│    { step: 1, tool: 'STAR', inputs: { reads: 'fastq', genome: 'fasta' }}, │
│    { step: 2, tool: 'featureCounts', inputs: { bam: 'bam', gtf: 'gtf' }}, │
│    ...                                                              │
│  ]                                                                  │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 2: Get User's Available Data (from Galaxy API)                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Query: getHistoryDatasets(userHistoryId)                           │
│                                                                      │
│  Result: [                                                          │
│    { id: 'abc', name: 'sample1_R1.fastq.gz', ext: 'fastqsanger' }, │
│    { id: 'def', name: 'sample1_R2.fastq.gz', ext: 'fastqsanger' }, │
│    { id: 'ghi', name: 'reference.gtf', ext: 'gtf' },               │
│    ...                                                              │
│  ]                                                                  │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 3: LLM Compatibility Analysis                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Prompt to LLM:                                                     │
│  """                                                                │
│  You are validating prerequisites for a workflow execution.         │
│                                                                      │
│  WORKFLOW REQUIREMENTS:                                             │
│  {requirements_from_step_1}                                         │
│                                                                      │
│  AVAILABLE DATASETS:                                                │
│  {datasets_from_step_2}                                             │
│                                                                      │
│  TOOL DOCUMENTATION:                                                │
│  {relevant_tool_docs_from_database}                                 │
│                                                                      │
│  Please analyze:                                                    │
│  1. Which datasets can satisfy which workflow inputs?               │
│  2. Are there any missing required inputs?                          │
│  3. What parameters need user configuration?                        │
│  4. Any compatibility issues or recommendations?                    │
│                                                                      │
│  Return structured JSON with mappings and analysis.                 │
│  """                                                                │
│                                                                      │
│  LLM Response: {                                                    │
│    mappings: [...],                                                 │
│    missing: [...],                                                  │
│    recommendations: [...],                                          │
│    compatibilityNotes: [...]                                        │
│  }                                                                  │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 4: Generate Conversational Response (LLM)                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  If prerequisites not fulfilled:                                    │
│                                                                      │
│  Prompt to LLM:                                                     │
│  """                                                                │
│  Generate a helpful, conversational message to guide the user       │
│  through workflow preparation.                                      │
│                                                                      │
│  Analysis results: {analysis_from_step_3}                           │
│  Workflow type: Differential expression analysis                    │
│  User context: Has RNA-seq data, missing reference genome           │
│                                                                      │
│  Be specific, helpful, and offer clear options.                     │
│  """                                                                │
│                                                                      │
│  LLM Response:                                                      │
│  "I've prepared a differential expression workflow for your         │
│   RNA-seq analysis. I found your FASTQ files and can auto-pair     │
│   them. However, I need a few more details:                        │
│                                                                      │
│   📥 INPUT DATA: I found sample1_R1/R2.fastq.gz - use these?       │
│                                                                      │
│   🧬 REFERENCE GENOME: This workflow needs a reference.            │
│      What organism is your data from?                               │
│      - Human (I'll use GRCh38)                                     │
│      - Mouse (I'll use GRCm39)                                     │
│      - Other (please specify)                                       │
│                                                                      │
│   📋 ANNOTATION: I found reference.gtf - use this for gene         │
│      annotation?"                                                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Leveraging Existing Systems

### 1. Tool Database Integration

The BioMate tool database already contains rich information:

```typescript
// Query tool database for comprehensive info
const toolInfo = await toolDatabase.getToolInfo(toolId);

// Available data:
// - inputs: Array of input definitions with types, formats, optionality
// - outputs: Expected output types
// - parameters: All configurable parameters with types, defaults, constraints
// - help_text: Full documentation
// - scientific_context: Omics applicability, best practices, pitfalls
// - requirements: Software dependencies, resource needs
```

**Use cases:**
- Get exact input format requirements dynamically
- Understand parameter constraints and defaults
- Access scientific context for intelligent recommendations
- Reference documentation for user explanations

### 2. LLM for Intelligent Matching

Instead of rigid format matching, use LLM to understand:

```typescript
// Example: Is a .fastq.gz file compatible with a "FASTQ input" requirement?
const analysis = await llmClient.analyze({
  system: `You are a bioinformatics expert validating data compatibility.`,
  prompt: `
    Workflow input requirement:
    - Label: "Input FASTQ reads"
    - Accepted formats: fastq, fastqsanger
    - Tool: STAR aligner

    Available dataset:
    - Name: sample1_R1.fastq.gz
    - Extension: fastqsanger
    - Size: 2.4 GB

    Is this dataset compatible? Consider:
    1. Format compatibility (including compressed variants)
    2. Naming conventions (R1 suggests forward reads)
    3. Any preprocessing that might be needed
  `
});
```

### 3. Galaxy API for Real-Time Data

```typescript
// Get user's current data state
const datasets = await galaxyProxy.getHistoryDatasets(historyId);
const histories = await galaxyProxy.getHistories();

// Each dataset has:
// - id, name, extension, size, state
// - metadata (if available)
// - create_time, update_time
```

---

## Implementation Strategy

### Phase 1: Core Validator with LLM

```typescript
class WorkflowPrerequisitesValidator {
  constructor(
    private toolDatabase: ToolDatabase,
    private galaxyProxy: GalaxyAPIProxy,
    private llmClient: LLMClient
  ) {}

  async validate(request: ValidateRequest): Promise<ValidationResult> {
    // 1. Parse workflow to extract requirements
    const requirements = await this.extractRequirements(request.workflow);

    // 2. Get user's available datasets
    const datasets = await this.getUserDatasets(request.historyId);

    // 3. Get relevant tool documentation
    const toolDocs = await this.getToolDocumentation(requirements);

    // 4. LLM analysis for intelligent matching
    const analysis = await this.llmAnalyze({
      requirements,
      datasets,
      toolDocs,
      userContext: request.context
    });

    // 5. Generate conversational response
    const response = await this.generateResponse(analysis);

    return {
      fulfilled: analysis.allSatisfied,
      analysis,
      conversationalResponse: response,
      suggestions: analysis.suggestions
    };
  }

  private async llmAnalyze(context: AnalysisContext): Promise<Analysis> {
    const prompt = this.buildAnalysisPrompt(context);

    const result = await this.llmClient.chat({
      messages: [
        { role: 'system', content: VALIDATION_SYSTEM_PROMPT },
        { role: 'user', content: prompt }
      ],
      response_format: { type: 'json_object' }
    });

    return JSON.parse(result.content);
  }
}
```

### Phase 2: Integration Points

1. **Galaxy Assistant** - Call validator after workflow generation
2. **Routes** - Add `/api/workflows/validate` endpoint
3. **Chat UI** - Handle validation responses conversationally

### Phase 3: Continuous Improvement

- Track validation accuracy
- Learn from user corrections
- Expand tool database coverage

---

## Key Design Decisions

### 1. LLM-First, Not Rule-First

**Decision**: Use LLM as the primary intelligence for compatibility analysis.

**Rationale**:
- Life sciences has enormous diversity of data types, formats, domains
- Hardcoded rules can't cover all cases
- LLM can reason about biological context
- Graceful handling of edge cases

### 2. Tool Database as Source of Truth

**Decision**: All tool requirements come from the tool database, not hardcoded.

**Rationale**:
- Database is already maintained with 400+ tools
- Includes scientific context, best practices
- Can be updated without code changes
- Single source of truth

### 3. Conversational, Not Form-Based

**Decision**: Generate natural language responses, not rigid forms.

**Rationale**:
- More natural user experience
- Can explain WHY something is needed
- Adapts to context
- Matches BioMate's chat-first design

---

## Example Conversations

### Example 1: RNA-seq with Missing Genome

```
User: "Analyze my RNA-seq data for differential expression"

BioMate: "I've designed a differential expression pipeline for your RNA-seq data.

Looking at your current data, I found:
✓ sample1_R1.fastq.gz and sample1_R2.fastq.gz (paired-end reads)
✓ sample2_R1.fastq.gz and sample2_R2.fastq.gz (paired-end reads)

Before I can run the analysis, I need to know:

1. **Reference Genome**: What organism is your data from?
   I'll set up the appropriate reference genome and gene annotation.

2. **Comparison Groups**: Which samples are control vs treatment?
   This is needed for the differential expression comparison.

Just let me know these details and I'll configure everything."
```

### Example 2: Proteomics with Compatible Data

```
User: "Run protein identification on my mass spec data"

BioMate: "I've set up a protein identification workflow for your mass spectrometry data.

I found these files that match the workflow inputs:
✓ sample_fraction1.mzML → MS data input
✓ sample_fraction2.mzML → MS data input
✓ human_uniprot.fasta → Protein database

Everything looks ready! The workflow will:
1. Search spectra against the UniProt human database
2. Filter results at 1% FDR
3. Generate protein and peptide reports

Ready to run? Or would you like to adjust any parameters first?"
```

### Example 3: Unknown Domain

```
User: "Process my ATAC-seq data"

BioMate: "I'll help you process your ATAC-seq data for chromatin accessibility analysis.

Looking at your files:
✓ Found ATAC_sample1.fastq.gz (reads)
? No reference genome detected in your history

For ATAC-seq analysis, I need:
1. **Reference genome** - Which organism? (human, mouse, other)
2. **Blacklist regions** - Should I use standard ENCODE blacklists?

Also, I noticed your files aren't paired-end. ATAC-seq typically uses paired-end sequencing.
Are these single-end reads, or should I look for the R2 files?"
```

---

## Files to Create/Modify

### New Files

| File | Purpose |
|------|---------|
| `frontend/server/workflow-prerequisites-validator.ts` | Main validator class using LLM |
| `frontend/shared/prerequisites-types.ts` | TypeScript interfaces (minimal, not hardcoded) |

### Files to Modify

| File | Changes |
|------|---------|
| `frontend/server/galaxy-assistant.ts` | Integrate validation after workflow generation |
| `frontend/server/routes.ts` | Add `/api/workflows/validate` endpoint |
| `frontend/server/llm-client.ts` | Add validation-specific prompts |

### Files to Leverage (Read-Only)

| File | What to Use |
|------|-------------|
| `frontend/server/tool-database.ts` | Query tool schemas dynamically |
| `frontend/server/galaxy-api-proxy.ts` | Get user datasets, histories |
| `frontend/server/dataset-validator.ts` | Existing validation patterns |

---

## Success Metrics

1. **Validation Accuracy**: % of validations that correctly identify issues
2. **User Satisfaction**: Reduced confusion, fewer failed workflow runs
3. **Coverage**: Works across genomics, proteomics, imaging, etc.
4. **Adaptation**: Handles new tools without code changes

---

## Next Steps

1. [ ] Create minimal type definitions (interfaces only, no hardcoded data)
2. [ ] Implement WorkflowPrerequisitesValidator with LLM integration
3. [ ] Add validation prompts to LLM client
4. [ ] Create `/api/workflows/validate` endpoint
5. [ ] Integrate with galaxy-assistant.ts
6. [ ] E2E testing across different workflow types
