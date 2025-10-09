# Galaxy Workflow Execution: LLM Orchestration Architecture Analysis

**Analysis Date:** October 4, 2025
**Focus:** LLM usage patterns, orchestration architecture, and optimization opportunities

---

## Executive Summary

The current Galaxy workflow execution system **significantly underutilizes LLM for orchestration**. While LLM is used effectively for user intent analysis and dataset validation, critical orchestration decisions like workflow sequencing, parameter selection, error recovery, and tool chain building are either **hard-coded or not implemented at all**.

**Key Findings:**
- ✅ **Good:** LLM used for NLU, tool ranking, dataset validation
- ⚠️ **Underutilized:** LLM could orchestrate entire workflow execution
- ❌ **Missing:** Error recovery, dynamic tool chains, resource optimization
- ❌ **Critical Gap:** No domain knowledge base for bioinformatics best practices

---

## 1. Current LLM Usage Analysis

### 1.1 Where LLM is Currently Used ✅

#### A. **Intent Analysis** (`galaxy-assistant.ts` lines 180-236)
```typescript
async analyzeIntent(message: string, context: ChatContext): Promise<{
  type: 'workflow_generation' | 'tool_inquiry' | 'dataset_inquiry' | ...
  keywords: string[];
  needsToolSearch: boolean;
  needsDatasets: boolean;
  confidence: number;
}>
```
**Decision Made by LLM:**
- Classify user intent (5 categories)
- Extract keywords for search
- Determine if tool/dataset search needed
- Confidence scoring

**Effectiveness:** ✅ Excellent - This is well-designed NLU

---

#### B. **Tool Ranking** (`galaxy-assistant.ts` lines 271-338)
```typescript
async rankToolsByRelevance(
  userMessage: string,
  tools: GalaxyTool[]
): Promise<ToolRecommendation[]>
```
**Decision Made by LLM:**
- Rank tools by relevance (0-1 score)
- Provide reasoning for each tool
- Filter out low-relevance tools (<0.3)

**Effectiveness:** ✅ Good - Leverages LLM's knowledge of bioinformatics tools

---

#### C. **Dataset Validation** (`dataset-validator.ts` lines 46-117)
```typescript
async validateDatasets(
  datasets: Dataset[],
  workflowSteps: WorkflowStep[],
  workflowName: string
): Promise<DatasetValidationResult>
```
**Decision Made by LLM:**
- Validate dataset compatibility with workflow
- Identify issues, warnings, suggestions
- Propose dataset-to-step mappings
- Confidence levels for mappings

**Effectiveness:** ✅ Excellent - Context-aware validation with educational feedback

---

### 1.2 What Decisions are Hard-Coded ❌

#### A. **Workflow Step Sequencing** (`routes.ts` lines 859-1009)
```typescript
function generateStepsForType(type: string, datasets?: any) {
  switch (type) {
    case 'rna-seq':
      return [
        { id: 'step1', title: 'Quality Control', tool: 'FastQC', ... },
        { id: 'step2', title: 'Read Alignment', tool: 'HISAT2', ... },
        { id: 'step3', title: 'Gene Expression', tool: 'featureCounts', ... },
        { id: 'step4', title: 'Diff Expression', tool: 'DESeq2', ... }
      ];
  }
}
```
**Problem:**
- Only 5 predefined workflows (RNA-seq, variant-calling, QC, chip-seq, general)
- Fixed tool sequences - no adaptation to data characteristics
- No consideration of data quality or sample type

**Should LLM Do This?** ✅ YES - LLM could:
- Analyze dataset characteristics (e.g., read length, quality scores)
- Select optimal tool chain dynamically
- Adjust workflow based on sample type (human vs. mouse vs. bacteria)

---

#### B. **Parameter Selection** (`parameter-repository.ts` - Template-Based)
```typescript
// Current: Templates selected by exact matching
async searchTemplates(request: ParameterTemplateSearchRequest) {
  // Filter by: tool_id, use_case_category, analysis_type, sample_type
  // Returns: Pre-saved parameter configurations
}
```
**Problem:**
- Limited to pre-saved templates
- No parameter optimization for specific data
- No adaptation to available computational resources

**Should LLM Do This?** ✅ YES - LLM could:
- Analyze dataset size → adjust memory parameters
- Check quality metrics → tune filtering thresholds
- Consider downstream goals → optimize for speed vs. accuracy

---

#### C. **Workflow Trigger Logic** (`galaxy-assistant.ts` lines 389-421)
```typescript
async analyzeWorkflowNeed(...): Promise<WorkflowSuggestion> {
  const triggerWords = [
    'workflow', 'pipeline', 'analysis', 'process', 'steps',
    'rna-seq', 'variant calling', 'genome assembly'
  ];

  const hasWorkflowIntent = triggerWords.some(word =>
    message.toLowerCase().includes(word)
  );

  return {
    shouldGenerate: hasWorkflowIntent && hasEnoughTools,
    confidence: hasWorkflowIntent && hasEnoughTools ? 0.9 : 0.3,
    reasoning: // ...
  };
}
```
**Problem:**
- Keyword-based heuristics
- Doesn't understand implicit workflow needs
- Example: "I have ChIP-seq BAM files and want to find peaks" → Should trigger workflow but might not

**Should LLM Do This?** ✅ YES - Already using LLM for intent analysis, should leverage it fully

---

### 1.3 What Decisions are NOT IMPLEMENTED ❌

#### A. **Error Recovery and Retries** (MISSING)
```typescript
// No error recovery system exists
// When a step fails:
// - No automatic retry with adjusted parameters
// - No fallback to alternative tools
// - No intelligent error diagnosis
```

**Current Behavior:** (`galaxy-state-poller.ts` lines 240-242)
```typescript
if (newStep.state === 'ok' || newStep.state === 'error') {
  this.fetchJobLogs(newState.id, newStep.id, newStep.job_id);
}
// ❌ Just logs the error, no recovery action
```

**What's Needed:**
```typescript
async handleStepFailure(step: WorkflowStep, error: string): Promise<RecoveryAction> {
  // Use LLM to analyze error message
  const analysis = await llm.analyzeError({
    step: step,
    error_log: error,
    dataset_info: datasets
  });

  // LLM suggests recovery actions:
  return {
    action: 'retry_with_adjusted_params' | 'use_alternative_tool' | 'fail',
    adjustments: {
      'memory': '16GB',  // Increase memory if OOM
      'threads': 4       // Reduce threads if resource error
    },
    alternative_tool: 'BWA-ALN',  // If BWA-MEM fails
    reasoning: 'Error suggests memory limit exceeded'
  };
}
```

---

#### B. **Dynamic Tool Chain Building** (MISSING)
```typescript
// Current: Only 5 predefined workflows
// Missing: Dynamic tool chain based on:
// - Data characteristics (paired-end vs single-end)
// - Quality metrics (raw vs. pre-processed)
// - Analysis goals (quick QC vs. publication-ready)
```

**What's Needed:**
```typescript
async buildToolChain(
  userGoal: string,
  datasets: Dataset[],
  constraints: { time?: string, quality?: 'fast' | 'accurate' }
): Promise<WorkflowStep[]> {
  // LLM analyzes:
  // 1. Dataset type → Required preprocessing
  // 2. User goal → Analysis depth
  // 3. Constraints → Tool selection strategy

  const prompt = `
    User wants: ${userGoal}
    Datasets: ${JSON.stringify(datasets)}
    Constraints: ${JSON.stringify(constraints)}

    Build optimal tool chain from 2,177 available Galaxy tools.
    Consider:
    - Data type compatibility
    - Tool dependencies (output of step N → input of step N+1)
    - Best practices for this analysis type
    - Performance characteristics
  `;

  return await llm.generateToolChain(prompt);
}
```

---

#### C. **Resource Allocation** (NOT IMPLEMENTED)
```typescript
// No resource management system
// Missing:
// - CPU/memory allocation per step
// - Parallel execution planning
// - Cost optimization (cloud environments)
```

**What's Needed:**
```typescript
async optimizeResourceAllocation(
  workflow: Workflow,
  datasets: Dataset[]
): Promise<ResourcePlan> {
  // LLM considers:
  // - Dataset size → memory requirements
  // - Tool complexity → CPU needs
  // - Step dependencies → parallelization opportunities

  return {
    steps: [
      {
        step_id: 'step1',
        resources: { cpu: 4, memory: '8GB', runtime: '~10min' },
        parallelizable: true  // Can run in parallel with step2
      },
      {
        step_id: 'step2',
        resources: { cpu: 8, memory: '16GB', runtime: '~30min' },
        dependencies: []  // No dependencies, can start immediately
      }
    ],
    total_cost: '$2.50',
    total_runtime: '~35min'  // Accounting for parallelization
  };
}
```

---

## 2. Orchestration Complexity Analysis

### 2.1 Current Orchestration Approach

**Architecture Pattern:** Template-Based with Manual Sequencing

```
User Input → Intent Analysis (LLM) → Template Lookup (Database) →
Static Workflow → Manual Execution → Polling (No Recovery)
```

**Problems:**
1. **No adaptability** - Same workflow regardless of data characteristics
2. **No error handling** - Failures just stop execution
3. **No optimization** - One-size-fits-all parameters
4. **Limited workflows** - Only 5 predefined types

---

### 2.2 Workflow Step Sequencing - Currently Manual

**Current Implementation:** (`workflow-repository.ts`)
```typescript
const steps = Object.entries(workflow_ga.steps).map(([stepId, stepData]) => ({
  step_id: stepId,
  tool_id: stepData.tool_id,
  tool_name: stepData.name,
  parameter_template_id: parameter_template_ids?.[stepId],
  custom_parameters: stepData.tool_state,
}));
```
**Analysis:**
- ❌ Steps defined in `.ga` file (Galaxy workflow format)
- ❌ Fixed sequence, no dynamic ordering
- ❌ No consideration of data-driven dependencies

---

### 2.3 Parameter Selection - Currently Template-Based

**Current Implementation:** (`parameter-repository.ts`)
```typescript
const template: ParameterTemplate = {
  tool_id: 'xcms',
  parameters: {
    method: 'centWave',
    ppm: 15,
    peakwidth_min: 5,
    peakwidth_max: 20
  },
  rationale: 'CentWave method with 15 ppm tolerance for high-resolution MS'
};
```
**Analysis:**
- ✅ Good: Captures expert knowledge
- ❌ Limited: Only ~3 example templates
- ❌ Static: No adaptation to dataset characteristics
- ❌ No reasoning: Just applies template blindly

---

### 2.4 Error Recovery - Currently None

**Current Implementation:** (`galaxy-state-poller.ts` lines 163-180)
```typescript
catch (error: any) {
  poller.failureCount++;
  console.error(`Failed to poll invocation ${invocationId}`);

  this.emit('polling_error', {
    invocation_id: invocationId,
    error: error.message,
  });

  if (poller.failureCount >= this.maxRetries) {
    this.emit('polling_failed', { invocation_id, error });
    this.stopPolling(invocationId);
  }
}
```
**Analysis:**
- ❌ Only retries API polling, not workflow execution
- ❌ No analysis of failure cause
- ❌ No alternative strategies
- ❌ Just stops and reports failure

---

### 2.5 Tool Chain Building - Currently Predefined

**Current Implementation:** (`routes.ts` lines 836-846)
```typescript
function detectWorkflowType(message: string): string {
  const msg = message.toLowerCase();

  if (msg.includes('rna-seq')) return 'rna-seq';
  if (msg.includes('variant')) return 'variant-calling';
  if (msg.includes('chip-seq')) return 'chip-seq';

  return 'general-analysis';
}
```
**Analysis:**
- ❌ Keyword matching only
- ❌ Fixed workflows per type
- ❌ No tool selection logic
- ❌ No dependency resolution

---

### 2.6 Resource Allocation - Not Implemented

**Current Implementation:** NONE
```typescript
// No resource management exists
// All jobs use default Galaxy allocation
```

---

## 3. Missing LLM Orchestration Opportunities

### 3.1 Should LLM Orchestrate the Entire Workflow Execution? ✅ YES

**Proposed Architecture:**

```typescript
class LLMWorkflowOrchestrator {
  /**
   * Master orchestration method
   * LLM makes ALL execution decisions
   */
  async orchestrateWorkflow(
    userGoal: string,
    datasets: Dataset[],
    constraints?: ExecutionConstraints
  ): Promise<WorkflowExecution> {

    // 1. LLM analyzes requirements
    const requirements = await this.analyzeRequirements(userGoal, datasets);

    // 2. LLM builds tool chain
    const toolChain = await this.buildToolChain(requirements);

    // 3. LLM selects parameters for each step
    const parameterizedSteps = await this.selectParameters(toolChain, datasets);

    // 4. LLM plans resource allocation
    const resourcePlan = await this.planResources(parameterizedSteps, datasets);

    // 5. Execute with LLM-driven error recovery
    return await this.executeWithRecovery(parameterizedSteps, resourcePlan);
  }

  /**
   * LLM-driven error recovery
   */
  async executeWithRecovery(
    steps: WorkflowStep[],
    resourcePlan: ResourcePlan
  ): Promise<WorkflowExecution> {
    for (const step of steps) {
      let retries = 0;
      while (retries < 3) {
        try {
          await this.executeStep(step, resourcePlan[step.id]);
          break;  // Success
        } catch (error) {
          // LLM analyzes error and suggests recovery
          const recovery = await this.llm.analyzeError({
            step: step,
            error: error.message,
            retry_count: retries
          });

          if (recovery.action === 'retry_with_adjustments') {
            step.parameters = { ...step.parameters, ...recovery.adjustments };
            retries++;
          } else if (recovery.action === 'use_alternative_tool') {
            step.tool_id = recovery.alternative_tool;
            retries++;
          } else {
            throw new WorkflowFailureError(recovery.reasoning);
          }
        }
      }
    }
  }
}
```

**Benefits:**
- ✅ Fully adaptive workflow execution
- ✅ Intelligent error recovery
- ✅ Resource optimization
- ✅ Captures bioinformatics expertise

---

### 3.2 Should LLM Handle Error Recovery and Retries? ✅ ABSOLUTELY YES

**Current Gap:** No error recovery exists

**LLM-Driven Error Recovery:**

```typescript
interface ErrorRecoveryStrategy {
  analyze_error(error: string, context: StepContext): ErrorAnalysis;
  suggest_recovery(analysis: ErrorAnalysis): RecoveryAction;
  apply_recovery(action: RecoveryAction): WorkflowStep;
}

// Example LLM prompt for error analysis:
const errorAnalysisPrompt = `
Workflow Step Failed:
- Step: ${step.title} (${step.tool})
- Error: ${error_message}
- Dataset: ${dataset.name} (${dataset.size})
- Parameters: ${JSON.stringify(step.parameters)}

Common failure modes for ${step.tool}:
1. Memory limit exceeded → Increase memory or reduce threads
2. File format mismatch → Check input type or use converter
3. Reference mismatch → Verify genome build
4. Quality threshold too strict → Relax filtering parameters

Analyze this error and suggest ONE recovery action:
{
  "error_type": "memory_limit" | "format_mismatch" | "reference_error" | "parameter_error",
  "root_cause": "string",
  "recovery_action": "retry_with_params" | "use_alternative_tool" | "convert_input" | "fail",
  "parameter_adjustments": { ... },
  "alternative_tool_id": "...",
  "reasoning": "..."
}
`;
```

**Real-World Example:**
```
Step: BWA-MEM alignment fails
Error: "Memory limit exceeded (8GB used, 8GB limit)"

LLM Analysis:
{
  "error_type": "memory_limit",
  "root_cause": "Large FASTQ files (12GB) require more memory for indexing",
  "recovery_action": "retry_with_params",
  "parameter_adjustments": {
    "memory": "16GB",
    "threads": 4  // Reduce parallelism to save memory
  },
  "reasoning": "BWA-MEM typically requires 1.3x dataset size in memory. Increasing to 16GB should handle 12GB input."
}
```

---

### 3.3 Should LLM Select Optimal Tool Parameters? ✅ YES

**Current Gap:** Template-based only, no optimization

**LLM Parameter Optimization:**

```typescript
async selectOptimalParameters(
  tool: GalaxyTool,
  dataset: Dataset,
  context: AnalysisContext
): Promise<ToolParameters> {

  const prompt = `
Tool: ${tool.name}
Dataset: ${dataset.name}
- Type: ${dataset.file_type}
- Size: ${formatSize(dataset.file_size)}
- Quality: ${dataset.quality_metrics}

Analysis Context:
- Goal: ${context.analysis_goal}
- Sample Type: ${context.sample_type}
- Priority: ${context.priority}  // 'speed' vs 'accuracy'

Parameter Options for ${tool.name}:
${JSON.stringify(tool.schema.parameters)}

Best Practices Knowledge:
${await this.getBestPractices(tool.tool_id, context.sample_type)}

Select optimal parameters considering:
1. Dataset characteristics
2. Analysis goal
3. Best practices for ${context.sample_type}
4. Performance vs accuracy trade-off

Return:
{
  "parameters": { ... },
  "rationale": "Why these values are optimal",
  "estimated_runtime": "...",
  "quality_level": "production" | "exploratory"
}
  `;

  return await this.llm.selectParameters(prompt);
}
```

**Example:**
```
Tool: XCMS Peak Detection
Dataset: LC-MS mzML files (500MB each, 20 samples)
Context:
- Goal: Untargeted metabolomics
- Sample Type: Human plasma
- Priority: Accuracy (publication-quality)

LLM Response:
{
  "parameters": {
    "method": "centWave",
    "ppm": 10,              // Tighter tolerance for high-res MS
    "peakwidth_min": 8,     // Plasma metabolites have wider peaks
    "peakwidth_max": 30,
    "snthresh": 6,          // Stricter S/N for cleaner results
    "prefilter_k": 5,       // More stringent prefiltering
    "prefilter_i": 1000
  },
  "rationale": "Human plasma samples require stringent parameters due to complex matrix. centWave with 10ppm optimal for Orbitrap data. Peak width 8-30s typical for UPLC-MS of plasma metabolites.",
  "estimated_runtime": "~45 min for 20 samples",
  "quality_level": "production"
}
```

---

### 3.4 Should LLM Build Tool Chains Dynamically? ✅ YES

**Current Gap:** Only 5 predefined workflows

**LLM Dynamic Tool Chain Builder:**

```typescript
async buildDynamicToolChain(
  analysisGoal: string,
  datasets: Dataset[],
  availableTools: GalaxyTool[]  // 2,177 tools
): Promise<WorkflowStep[]> {

  // Step 1: Analyze data characteristics
  const dataAnalysis = await this.analyzeDatasets(datasets);

  // Step 2: LLM selects tools from 2,177 options
  const prompt = `
Analysis Goal: ${analysisGoal}

Dataset Characteristics:
${dataAnalysis.map(d => `
- ${d.name}: ${d.file_type}
  - Read type: ${d.read_type}  // paired-end, single-end
  - Quality: ${d.quality_score}
  - Size: ${d.size}
  - Preprocessing: ${d.preprocessing_status}
`).join('\n')}

Available Tools (subset of 2,177):
${this.getRelevantTools(availableTools, analysisGoal).map(t => `
- ${t.name} (${t.tool_id})
  - Category: ${t.category}
  - Inputs: ${t.inputs}
  - Outputs: ${t.outputs}
`).join('\n')}

Build optimal tool chain:
1. Identify required preprocessing steps based on data quality
2. Select main analysis tools appropriate for ${analysisGoal}
3. Include visualization/QC steps
4. Ensure output compatibility between steps

Return workflow as:
{
  "steps": [
    {
      "step_id": "step1",
      "tool_id": "...",
      "tool_name": "...",
      "reasoning": "Why this tool at this position",
      "input_from": "dataset" | "step_N",
      "estimated_time": "..."
    }
  ],
  "total_estimated_time": "...",
  "quality_score": 0-1
}
  `;

  return await this.llm.buildToolChain(prompt);
}
```

**Example - Adaptive Tool Selection:**
```
Scenario 1: High-quality paired-end RNA-seq
→ FastQC → HISAT2 → featureCounts → DESeq2

Scenario 2: Low-quality single-end RNA-seq (same goal)
→ FastQC → Trimmomatic → FastQC (post-trim) → STAR → HTSeq → edgeR
              ↑ LLM adds trimming step due to low quality
                     ↑ LLM switches to STAR for better sensitivity with short reads
```

---

### 3.5 Should LLM Optimize Resource Allocation? ✅ YES

**Current Gap:** No resource management

**LLM Resource Optimizer:**

```typescript
async optimizeResources(
  workflow: Workflow,
  datasets: Dataset[],
  infrastructure: InfrastructureConfig
): Promise<ResourcePlan> {

  const prompt = `
Workflow Steps:
${workflow.steps.map(s => `
- ${s.tool_name}
  - Typical CPU: ${s.typical_cpu}
  - Typical Memory: ${s.typical_memory}
  - Parallelizable: ${s.parallelizable}
`).join('\n')}

Datasets:
${datasets.map(d => `- ${d.name}: ${formatSize(d.file_size)}`).join('\n')}

Infrastructure:
- Max CPU: ${infrastructure.max_cpu}
- Max Memory: ${infrastructure.max_memory}
- Cost per CPU-hour: ${infrastructure.cost_cpu}
- Cost per GB-hour: ${infrastructure.cost_memory}

Optimize for:
- Priority: ${infrastructure.priority}  // 'cost' vs 'speed'
- Budget: ${infrastructure.budget}

Consider:
1. Dataset size → memory requirements (rule of thumb: tool memory = 1.5x input size)
2. Tool parallelization → CPU allocation
3. Step dependencies → parallel execution opportunities
4. Cost constraints

Return:
{
  "resource_allocation": [
    {
      "step_id": "step1",
      "cpu": 4,
      "memory": "8GB",
      "estimated_runtime": "10min",
      "can_run_parallel_with": ["step2"]
    }
  ],
  "execution_plan": {
    "parallel_groups": [["step1", "step2"], ["step3"]],
    "total_runtime": "25min",
    "total_cost": "$1.50"
  },
  "reasoning": "..."
}
  `;

  return await this.llm.optimizeResources(prompt);
}
```

---

## 4. Architecture Gaps

### 4.1 Missing Domain Knowledge

**Current State:** Limited to hard-coded templates

**What's Needed:**

#### A. **Bioinformatics Best Practices Database**
```typescript
interface BestPracticesKB {
  tool_recommendations: {
    [analysis_type: string]: {
      [sample_type: string]: {
        preferred_tools: string[];
        parameter_ranges: Record<string, any>;
        quality_thresholds: Record<string, number>;
        references: string[];
      }
    }
  };

  common_failures: {
    [tool_id: string]: {
      error_pattern: string;
      root_cause: string;
      solution: string;
    }[]
  };

  tool_compatibility: {
    [tool_a: string]: {
      compatible_outputs: string[];
      incompatible_with: string[];
    }
  };
}

// Example:
const bestPractices = {
  tool_recommendations: {
    'rna_seq_alignment': {
      'human': {
        preferred_tools: ['HISAT2', 'STAR'],
        parameter_ranges: {
          'hisat2_threads': [4, 16],
          'star_genome_load': 'LoadAndKeep'
        },
        quality_thresholds: {
          'min_mapping_rate': 0.70,
          'max_duplication_rate': 0.30
        },
        references: [
          'Dobin et al. (2013) STAR: ultrafast universal RNA-seq aligner'
        ]
      }
    }
  }
};
```

---

#### B. **Tool Performance Profiles**
```typescript
interface ToolPerformanceProfile {
  tool_id: string;

  // Resource usage patterns
  resource_model: {
    cpu_scaling: 'linear' | 'sublinear' | 'none';
    memory_formula: string;  // e.g., "1.5 * input_size + 2GB"
    runtime_formula: string;  // e.g., "0.5 * (input_size / cpu_count)"
  };

  // Quality-speed tradeoffs
  presets: {
    'fast': { parameters: {...}, quality_score: 0.6 },
    'balanced': { parameters: {...}, quality_score: 0.8 },
    'sensitive': { parameters: {...}, quality_score: 0.95 }
  };

  // Known issues
  limitations: {
    max_input_size: string;
    incompatible_formats: string[];
    known_bugs: string[];
  };
}
```

---

#### C. **Sample Type Characteristics**
```typescript
interface SampleTypeProfile {
  sample_type: string;  // 'human_plasma', 'mouse_liver', etc.

  typical_characteristics: {
    complexity: 'low' | 'medium' | 'high';
    typical_features: number;
    background_level: 'low' | 'high';
    matrix_effects: string[];
  };

  preprocessing_requirements: {
    required_steps: string[];
    optional_steps: string[];
    parameters_to_adjust: Record<string, any>;
  };

  quality_benchmarks: {
    [metric: string]: {
      good: number;
      acceptable: number;
      poor: number;
    }
  };
}
```

---

### 4.2 Missing User Context Capture

**Current State:** Session stores only uploaded datasets

**What's Needed:**

```typescript
interface UserWorkflowContext {
  // User expertise level
  expertise: {
    level: 'beginner' | 'intermediate' | 'expert';
    familiar_tools: string[];
    previous_analyses: string[];
  };

  // Analysis context
  project: {
    type: 'exploratory' | 'validation' | 'publication';
    timeline: string;
    budget: number;
    quality_requirements: 'quick_check' | 'standard' | 'publication_grade';
  };

  // Historical performance
  history: {
    successful_workflows: WorkflowExecution[];
    failed_steps: { step: string; error: string; }[];
    preferred_tools: string[];
    typical_datasets: DatasetProfile[];
  };

  // Preferences
  preferences: {
    speed_vs_accuracy: number;  // 0 (speed) to 1 (accuracy)
    cost_sensitivity: number;   // 0 (unlimited) to 1 (minimal cost)
    explanation_detail: 'minimal' | 'moderate' | 'detailed';
  };
}
```

---

### 4.3 Missing Galaxy-Specific Knowledge

**Current State:** Basic API integration

**What's Needed:**

#### A. **Galaxy Tool Dependency Graph**
```typescript
interface GalaxyToolGraph {
  tools: {
    [tool_id: string]: {
      dependencies: string[];  // Required tools before this
      outputs_compatible_with: string[];
      typical_position: number;  // In workflow sequence
    }
  };

  // Common workflow patterns
  patterns: {
    [pattern_name: string]: {
      tools: string[];
      sequence: number[];
      success_rate: number;
      use_cases: string[];
    }
  };
}

// Example:
{
  "rna_seq_standard": {
    "tools": ["fastqc", "hisat2", "featurecounts", "deseq2"],
    "sequence": [0, 1, 2, 3],
    "success_rate": 0.92,
    "use_cases": ["differential_expression", "gene_discovery"]
  }
}
```

---

#### B. **Galaxy Dataset Type System**
```typescript
interface GalaxyDataTypeKnowledge {
  // Type compatibility rules
  conversions: {
    [from_type: string]: {
      [to_type: string]: {
        tool: string;
        parameters: Record<string, any>;
        quality_loss: number;  // 0-1
      }
    }
  };

  // Type inference from content
  type_detection: {
    [pattern: string]: {
      file_type: string;
      confidence: number;
      validation_regex: string;
    }
  };

  // Tool input requirements
  tool_requirements: {
    [tool_id: string]: {
      required_types: string[];
      optional_types: string[];
      format_strict: boolean;
    }
  };
}
```

---

## 5. Recommendations

### 5.1 Where Should LLM Be Used for Orchestration?

**Priority 1: Error Recovery (Immediate Impact)** 🔥
```typescript
// Implement LLM-driven error recovery FIRST
class LLMErrorRecovery {
  async handleFailure(
    step: WorkflowStep,
    error: string,
    context: ExecutionContext
  ): Promise<RecoveryAction> {
    // LLM analyzes error and suggests fix
    // Can be added to existing poller without major refactoring
  }
}
```
**Why First:** Existing workflows fail with no recovery - quick win

---

**Priority 2: Parameter Optimization (High Value)** ⭐
```typescript
// Enhance existing parameter system with LLM optimization
class LLMParameterOptimizer {
  async optimizeParameters(
    template: ParameterTemplate,
    dataset: Dataset
  ): Promise<OptimizedParameters> {
    // Takes existing template + dataset characteristics
    // Returns optimized parameters
  }
}
```
**Why Second:** Builds on existing template system, improves quality

---

**Priority 3: Dynamic Tool Chain (Most Powerful)** 🚀
```typescript
// Replace hard-coded workflows with LLM tool chain builder
class LLMToolChainBuilder {
  async buildChain(
    goal: string,
    datasets: Dataset[],
    constraints: Constraints
  ): Promise<WorkflowStep[]> {
    // Replaces generateStepsForType() with intelligent selection
  }
}
```
**Why Third:** Requires more infrastructure (knowledge base), biggest impact

---

**Priority 4: Resource Optimization (Production)** 💰
```typescript
// Add resource optimization for production deployments
class LLMResourceOptimizer {
  async planExecution(
    workflow: Workflow,
    infrastructure: InfrastructureConfig
  ): Promise<ExecutionPlan> {
    // Optimizes cost and performance
  }
}
```
**Why Last:** Only matters at scale, needs infrastructure monitoring

---

### 5.2 Information to Collect Offline

#### A. **Tool Performance Benchmarks** (High Priority)
```bash
# For each tool in Galaxy (2,177 tools):
# 1. Run with various input sizes
# 2. Measure: CPU, memory, runtime
# 3. Store in database

{
  "tool_id": "hisat2",
  "benchmarks": [
    {
      "input_size": "1GB",
      "cpu": 8,
      "memory_used": "4.2GB",
      "runtime": "8.5min"
    },
    {
      "input_size": "10GB",
      "cpu": 8,
      "memory_used": "12.1GB",
      "runtime": "85min"
    }
  ],
  "memory_model": "1.2 * input_size + 1GB",
  "cpu_scaling": "linear"
}
```

---

#### B. **Failure Mode Catalog** (Critical for Error Recovery)
```json
{
  "tool_id": "bwa_mem",
  "failure_modes": [
    {
      "error_pattern": ".*memory.*exceeded.*",
      "root_cause": "Insufficient memory for indexing",
      "solution": {
        "action": "increase_memory",
        "adjustment_factor": 1.5,
        "alternative_tool": "bwa_aln"
      }
    },
    {
      "error_pattern": ".*index.*not found.*",
      "root_cause": "Reference genome not indexed",
      "solution": {
        "action": "run_prerequisite",
        "prerequisite_tool": "bwa_index"
      }
    }
  ]
}
```

---

#### C. **Best Practices Corpus** (For LLM Context)
```markdown
# RNA-seq Best Practices (Human)

## Quality Control
- **Tool:** FastQC
- **Thresholds:**
  - Per-base quality: >28
  - Adapter content: <5%
  - Duplication: <30%

## Alignment
- **Preferred Tools:** HISAT2, STAR
- **HISAT2 Parameters (Illumina):**
  - `--threads 8-16`
  - `--dta` (downstream transcriptome assembly)
  - `--rna-strandness` (if stranded)
- **Expected Metrics:**
  - Mapping rate: >70%
  - Uniquely mapped: >60%

## Common Errors
- **Low mapping rate (<50%)**
  - Check: Reference genome version
  - Check: Adapter contamination
  - Solution: Re-trim adapters or use different reference
```

---

#### D. **Tool Compatibility Matrix**
```json
{
  "compatibility": {
    "fastqc": {
      "outputs": ["html", "zip"],
      "compatible_downstream": ["trimmomatic", "hisat2", "bwa"]
    },
    "hisat2": {
      "outputs": ["bam", "sam"],
      "compatible_downstream": ["featurecounts", "htseq", "samtools"]
    }
  }
}
```

---

### 5.3 Knowledge Bases to Build

#### A. **Bioinformatics Workflow Knowledge Base** (SQL + Vector DB)
```sql
-- Tools table
CREATE TABLE tools (
  tool_id VARCHAR PRIMARY KEY,
  category VARCHAR,
  description TEXT,
  input_types JSON,
  output_types JSON,
  parameter_schema JSON,
  typical_use_cases TEXT[]
);

-- Tool performance table
CREATE TABLE tool_performance (
  tool_id VARCHAR REFERENCES tools(tool_id),
  input_size_gb FLOAT,
  cpu_count INT,
  memory_gb FLOAT,
  runtime_minutes FLOAT,
  dataset_type VARCHAR
);

-- Failure modes table
CREATE TABLE failure_modes (
  tool_id VARCHAR REFERENCES tools(tool_id),
  error_pattern TEXT,
  root_cause TEXT,
  solution JSON
);

-- Best practices (vector embeddings for semantic search)
CREATE TABLE best_practices (
  id SERIAL PRIMARY KEY,
  analysis_type VARCHAR,
  sample_type VARCHAR,
  content TEXT,
  embedding VECTOR(1536),  -- OpenAI ada-002 embeddings
  references TEXT[]
);
```

---

#### B. **Workflow Pattern Library** (Graph Database - Neo4j)
```cypher
// Store successful workflows as graphs
CREATE (w:Workflow {name: "RNA-seq Standard"})
CREATE (s1:Step {tool: "fastqc", position: 1})
CREATE (s2:Step {tool: "hisat2", position: 2})
CREATE (s3:Step {tool: "featurecounts", position: 3})
CREATE (s1)-[:OUTPUTS_TO]->(s2)
CREATE (s2)-[:OUTPUTS_TO]->(s3)
CREATE (w)-[:CONTAINS]->(s1)

// Query for similar workflows
MATCH (w:Workflow)-[:CONTAINS]->(s:Step)
WHERE s.tool IN ['fastqc', 'hisat2']
RETURN w
```

---

#### C. **Sample Type Profiles** (JSON Documents)
```json
{
  "sample_type": "human_plasma_lcms",
  "characteristics": {
    "complexity": "high",
    "typical_features": "5000-15000",
    "matrix_effects": ["ion_suppression", "phospholipid_interference"],
    "recommended_preprocessing": [
      "blank_subtraction",
      "batch_correction",
      "internal_standard_normalization"
    ]
  },
  "quality_benchmarks": {
    "cv_qc": {"good": "<15%", "acceptable": "<25%", "poor": ">25%"},
    "signal_to_noise": {"good": ">10", "acceptable": ">5", "poor": "<5"}
  },
  "tool_recommendations": {
    "peak_detection": {
      "tool": "xcms",
      "parameters": {
        "method": "centWave",
        "ppm": 10,
        "peakwidth": [8, 30]
      }
    }
  }
}
```

---

### 5.4 Ideal Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     LLM ORCHESTRATION LAYER                 │
│                                                             │
│  ┌──────────────┐  ┌───────────────┐  ┌─────────────────┐ │
│  │   Intent     │  │   Tool Chain  │  │   Parameter     │ │
│  │   Analysis   │→ │   Builder     │→ │   Optimizer     │ │
│  └──────────────┘  └───────────────┘  └─────────────────┘ │
│         ↓                  ↓                     ↓          │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           WORKFLOW EXECUTION ORCHESTRATOR            │  │
│  │                                                      │  │
│  │  • Dynamic tool selection from 2,177 tools          │  │
│  │  • Adaptive parameter tuning                        │  │
│  │  • Resource allocation optimization                 │  │
│  │  • Error recovery with retries                      │  │
│  └──────────────────────────────────────────────────────┘  │
│         ↓                  ↓                     ↓          │
│  ┌──────────────┐  ┌───────────────┐  ┌─────────────────┐ │
│  │   Dataset    │  │   Resource    │  │   Error         │ │
│  │   Validator  │  │   Manager     │  │   Recovery      │ │
│  └──────────────┘  └───────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    KNOWLEDGE BASE LAYER                      │
│                                                             │
│  ┌──────────────┐  ┌───────────────┐  ┌─────────────────┐ │
│  │   Tool       │  │   Best        │  │   Failure       │ │
│  │   Profiles   │  │   Practices   │  │   Modes         │ │
│  │   (SQL)      │  │   (Vector DB) │  │   (Catalog)     │ │
│  └──────────────┘  └───────────────┘  └─────────────────┘ │
│                                                             │
│  ┌──────────────┐  ┌───────────────┐  ┌─────────────────┐ │
│  │   Workflow   │  │   Sample      │  │   User          │ │
│  │   Patterns   │  │   Profiles    │  │   History       │ │
│  │   (Graph DB) │  │   (JSON)      │  │   (Session)     │ │
│  └──────────────┘  └───────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   GALAXY EXECUTION LAYER                     │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Galaxy API Proxy                        │  │
│  │  • Tool invocation                                   │  │
│  │  • Job monitoring (SSE)                             │  │
│  │  • Dataset management                                │  │
│  │  • History management                                │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

### 5.5 Implementation Roadmap

#### **Phase 1: Error Recovery (Weeks 1-2)** 🔥
```typescript
// Add to existing galaxy-state-poller.ts
class LLMErrorRecovery {
  async analyzeStepFailure(
    step: WorkflowStep,
    error: string
  ): Promise<RecoveryAction> {
    const prompt = `
      Step: ${step.tool_name}
      Error: ${error}
      Suggest recovery action
    `;
    return await llm.complete(prompt);
  }
}

// Integrate with poller
if (newStep.state === 'error') {
  const recovery = await errorRecovery.analyzeStepFailure(newStep, errorLog);
  if (recovery.action === 'retry_with_params') {
    await retryStep(newStep, recovery.adjustments);
  }
}
```

---

#### **Phase 2: Build Knowledge Bases (Weeks 3-6)** 📚
1. **Week 3-4:** Collect tool performance benchmarks
   - Run automated benchmark suite on Galaxy tools
   - Store in PostgreSQL

2. **Week 5:** Build failure mode catalog
   - Analyze Galaxy job logs
   - Extract common error patterns
   - Document solutions

3. **Week 6:** Create best practices corpus
   - Scrape protocols from papers
   - Extract from Galaxy training materials
   - Store in vector database (Pinecone/Weaviate)

---

#### **Phase 3: Parameter Optimization (Weeks 7-8)** ⭐
```typescript
class LLMParameterOptimizer {
  async optimizeForDataset(
    tool: GalaxyTool,
    dataset: Dataset
  ): Promise<OptimizedParameters> {
    // Retrieve best practices from vector DB
    const practices = await vectorDB.search({
      query: `${tool.name} parameters for ${dataset.type}`,
      k: 5
    });

    // LLM optimizes based on dataset + best practices
    const optimized = await llm.optimize({
      tool: tool,
      dataset: dataset,
      best_practices: practices
    });

    return optimized;
  }
}
```

---

#### **Phase 4: Dynamic Tool Chains (Weeks 9-12)** 🚀
```typescript
class LLMToolChainBuilder {
  async buildChain(
    goal: string,
    datasets: Dataset[]
  ): Promise<WorkflowStep[]> {
    // Query workflow pattern library (Neo4j)
    const similarWorkflows = await graphDB.findSimilar(goal);

    // Retrieve relevant tools
    const tools = await db.searchTools({
      analysis_type: goal,
      input_types: datasets.map(d => d.type)
    });

    // LLM builds chain
    const chain = await llm.buildToolChain({
      goal: goal,
      datasets: datasets,
      available_tools: tools,
      similar_workflows: similarWorkflows
    });

    return chain;
  }
}
```

---

#### **Phase 5: Production Deployment (Weeks 13-16)** 💰
1. Add resource optimization
2. Implement A/B testing (LLM vs template-based)
3. Monitor and refine prompts
4. Scale knowledge bases

---

## 6. Critical Conclusions

### ✅ What's Working Well
1. **LLM for NLU:** Intent analysis is well-designed
2. **Tool ranking:** Leverages LLM's domain knowledge
3. **Dataset validation:** Context-aware, educational

### ❌ Critical Gaps
1. **No error recovery:** Workflows fail permanently
2. **Template-only parameters:** Not adaptive
3. **Fixed workflows:** Only 5 types, no customization
4. **No resource optimization:** Wastes compute/money
5. **Knowledge silos:** Best practices in developer's head, not in system

### 🎯 Biggest Opportunity
**Replace hard-coded orchestration with LLM-driven workflow execution**

The system is currently using LLM as a "smart search engine" when it should be using it as a **"workflow conductor"**.

---

## 7. Final Recommendations

### Immediate Actions (This Sprint) 🔥
1. **Add LLM error recovery to galaxy-state-poller.ts**
   - Analyze error messages
   - Suggest retry strategies
   - Quick win with minimal refactoring

2. **Create failure mode catalog**
   - Document common Galaxy tool failures
   - Build prompt templates for recovery

### Short-Term (Next 2 Sprints) ⭐
3. **Enhance parameter selection with LLM optimization**
   - Keep templates as fallback
   - Add LLM optimization on top
   - Compare quality metrics

4. **Build knowledge bases**
   - Tool performance benchmarks
   - Best practices corpus
   - Sample type profiles

### Long-Term (Next Quarter) 🚀
5. **Replace workflow generation with LLM orchestration**
   - Dynamic tool chain building
   - Adaptive parameter tuning
   - Resource optimization

6. **Production monitoring and refinement**
   - A/B test LLM vs. template-based
   - Collect user feedback
   - Continuously improve prompts

---

**The current system is like having a PhD bioinformatician write the protocol but then having a robot blindly execute it. We should let the PhD orchestrate the entire execution, adapting in real-time to what they observe.**

