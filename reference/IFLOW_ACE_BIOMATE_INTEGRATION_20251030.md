# iFlow CLI + ACE Framework: Comparative Analysis & Integration Guide for BioMate
**Date**: October 30, 2025
**Purpose**: Synthesize insights from iFlow CLI and ACE framework to enhance BioMate workflow generation

---

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Side-by-Side Comparison](#side-by-side-comparison)
3. [Complementary Strengths](#complementary-strengths)
4. [Recommended Integration Architecture](#recommended-integration-architecture)
5. [Resource Links](#resource-links)
6. [Implementation Roadmap](#implementation-roadmap)
7. [Concrete Code Examples](#concrete-code-examples)

---

## Executive Summary

### What Each Framework Solves

**iFlow CLI** (GitHub: https://github.com/iflow-ai/iflow-cli)
- **Problem**: Claude Code is powerful but operates at terminal level; users need domain-specific workflows
- **Solution**: Meta-level abstractions (slash commands, workflows, agents) for specialized tasks
- **Target**: Software developers, DevOps, data analysts needing repeatable patterns
- **Key Innovation**: Workflow composition (agents + commands + tools + IFLOW.md)

**ACE** (Paper: https://arxiv.org/abs/2510.04618)
- **Problem**: Context adaptation suffers from brevity bias and context collapse
- **Solution**: Three-agent system with incremental delta updates and evolving playbooks
- **Target**: Any LLM application needing self-improvement without fine-tuning
- **Key Innovation**: Automated learning from execution feedback with structured context

**BioMate** (Current State)
- **Problem**: Proteomics workflow generation produces redundant/incompatible tool chains
- **Solution In Progress**: Enhanced tool metadata + Claude-based workflow generation
- **Target**: Bioinformaticians needing domain-specific proteomics/genomics workflows
- **Opportunity**: Combine iFlow's UX patterns + ACE's learning system

### Why Integrate Both?

| Capability | iFlow Provides | ACE Provides | BioMate Gains |
|------------|----------------|--------------|---------------|
| **User Interface** | Slash commands, @ file refs, $ agent calls | Natural language + structured feedback | Intuitive proteomics workflow commands |
| **Context Building** | `/init` progressive discovery | Incremental delta updates | Prevent metadata loss during iterations |
| **Specialized Agents** | Marketplace with permission control | Automated specialization through learning | Tool-selector, parameter-expert, validator agents |
| **Workflow Patterns** | IFLOW.md composition | Playbook evolution | Domain-specific proteomics workflow library |
| **Learning** | Manual curation | Automated from feedback | Self-improving without constant expert input |
| **Memory Management** | `/compress` manual control | Grow-and-refine automatic | Scale to long workflow histories |

**Integration Thesis**:
- Use **iFlow's UX patterns** for user-facing interface (commands, workflows, file references)
- Use **ACE's learning system** for backend intelligence (playbook evolution, automated improvement)
- Result: **Self-improving proteomics workflow platform with intuitive UX**

---

## Side-by-Side Comparison

### 1. Architecture Philosophy

#### iFlow CLI Architecture
```
User Input (Natural Language or /command)
     ↓
┌─────────────────────────────────────┐
│     Meta-Layer (iFlow Runtime)      │
│  - Slash Commands (/init, /clear)   │
│  - @ File References                │
│  - $ Agent Calls                    │
│  - ! Shell Execution                │
└─────────────────────────────────────┘
     ↓
┌─────────────────────────────────────┐
│         Claude Code (Base)          │
│  - Tool use (Read, Write, Bash)     │
│  - Context window management        │
│  - Model capabilities               │
└─────────────────────────────────────┘
```

**Key Insight**: iFlow is a **meta-framework on top of Claude Code**, adding domain-specific abstractions.

**Resource**:
- iFlow Architecture Overview: https://github.com/iflow-ai/iflow-cli/blob/main/README.md
- iFlow vs Claude Code comparison: https://docs.iflow.cn/en/docs/comparison

#### ACE Framework Architecture
```
User Query + Current Playbook
     ↓
┌─────────────────────────────────────┐
│          Generator Agent            │
│  - Executes task using playbook     │
│  - Tracks bullet usage (helpful/    │
│    harmful)                          │
└─────────────────────────────────────┘
     ↓ (trajectory + execution result)
┌─────────────────────────────────────┐
│         Reflector Agent             │
│  - Analyzes failures                │
│  - Identifies root causes           │
│  - Proposes corrections             │
└─────────────────────────────────────┘
     ↓ (insights)
┌─────────────────────────────────────┐
│          Curator Agent              │
│  - Generates delta updates          │
│  - Deterministic merge (non-LLM)    │
│  - Deduplication                    │
└─────────────────────────────────────┘
     ↓
   Updated Playbook
```

**Key Insight**: ACE is a **learning framework**, separating execution from reflection and curation.

**Resource**:
- ACE Paper: https://arxiv.org/abs/2510.04618
- ACE Implementation: https://github.com/sci-m-wang/ACE-open
- Dynamic Cheatsheet (precursor): https://github.com/suzgunmirac/dynamic-cheatsheet

#### BioMate Integration Opportunity
```
User: "Analyze my DIA proteomics data"
     ↓
┌─────────────────────────────────────┐
│    iFlow-style Interface Layer      │
│  /workflow dia-proteomics           │  ← Slash command
│  @data/experiment.raw               │  ← File reference
│  $tool-selector                     │  ← Agent call
└─────────────────────────────────────┘
     ↓
┌─────────────────────────────────────┐
│   ACE-powered Learning Backend      │
│  Generator: Claude + Playbook       │
│  Reflector: Analyze tool choices    │
│  Curator: Update tool rules         │
└─────────────────────────────────────┘
     ↓
Generated Workflow (self-improving)
```

### 2. Context Management Strategies

#### iFlow Approach: Manual Control with Clear Commands

**Commands**:
```bash
/init          # Analyze project, build context
/clear         # Clear context, start fresh
/memory add    # Add persistent instruction
/compress      # Summarize long conversations
```

**Example Flow**:
```
> cd proteomics-project
> iflow
> /init
  [iFlow analyzes directory structure]
  [Builds context: "This is a DIA proteomics project with..."]

> I want to add differential expression analysis
  [Claude generates workflow using established context]

> /compress
  [Summarizes conversation, keeps key facts]
```

**Strengths**:
- ✅ User has explicit control
- ✅ Clear when context resets
- ✅ `/init` pattern prevents repetitive explanations

**Limitations**:
- ❌ Manual compression decisions
- ❌ No automated learning from past workflows
- ❌ Context lost between sessions unless explicitly saved

**Resource**: https://docs.iflow.cn/en/docs/features/slash-commands

#### ACE Approach: Automated Incremental Updates

**Mechanism**:
```python
# Step 1: Generate with current playbook
workflow = generator.generate(query, playbook)

# Step 2: Execute and get feedback
result = execute(workflow)

# Step 3: Reflect on what went wrong/right
insights = reflector.analyze(workflow, result)

# Step 4: Generate small delta (not full rewrite!)
delta = curator.create_delta(insights)

# Step 5: Deterministic merge (preserves old knowledge)
playbook = merge(playbook, delta)
```

**Example Evolution**:
```
Iteration 1:
  User: "Analyze DIA data"
  Generated: [Uses MaxQuant] ❌
  Reflection: "MaxQuant is DDA-only"
  Delta: ADD "Never use MaxQuant for DIA data"

Iteration 2:
  User: "Analyze DIA data"
  Generated: [Uses DIA-NN] ✅
  Reflection: "Correct tool, but FDR too lenient"
  Delta: ADD "Default FDR 0.01 for DIA-NN"

Iteration 3:
  User: "Analyze DIA data"
  Generated: [Uses DIA-NN with FDR 0.01] ✅
  Reflection: "Correct!"
  Delta: INCREMENT helpful counter for DIA-NN rule
```

**Strengths**:
- ✅ Automatic improvement over time
- ✅ No context collapse (incremental updates)
- ✅ Learns from execution feedback

**Limitations**:
- ❌ Requires training data or feedback loop
- ❌ Less transparent to user (happens in background)
- ❌ Need to prevent learning from bad examples

**Resource**: https://arxiv.org/abs/2510.04618 (Section 3.1: Incremental Delta Updates)

#### BioMate Integration Strategy

**Combine Both Approaches**:

**User-Facing (iFlow-style)**:
```bash
# Explicit context control
/workflow init proteomics     # Like /init, but domain-specific
/workflow history             # Show past workflows learned from
/workflow compress            # Manual compression if needed
```

**Background (ACE-style)**:
```typescript
// Automated learning (invisible to user)
class WorkflowMemory {
  async learnFromExecution(workflow: Workflow, result: ExecutionResult) {
    // ACE's three-agent loop runs in background
    const insights = await reflector.analyze(workflow, result);
    const delta = await curator.generateDelta(insights);
    this.playbook = this.mergeDelta(this.playbook, delta);
  }
}
```

**Best of Both Worlds**:
- User gets iFlow's clarity (explicit commands)
- System gets ACE's intelligence (automated improvement)
- User can inspect playbook: `/playbook show tool-selection-rules`

### 3. Specialized Agents

#### iFlow Agent System

**Marketplace Structure**:
- **Online Repository**: https://platform.iflow.cn/agents
- **Local Installation**: `.iflow/agents/*.md` files
- **Permission Control**: `allowedTools`, `allowedMcps` arrays

**Agent Configuration Example**:
```markdown
---
agentType: "proteomics-expert"
systemPrompt: "You are a proteomics workflow specialist..."
whenToUse: "Use when user mentions DIA, DDA, proteomics, or mass spectrometry"
model: "claude-3-5-sonnet-20241022"
allowedTools: ["Read", "Write", "Grep", "Bash"]
allowedMcps: ["tool-database", "galaxy-api"]
proactive: false
color: "#4A90E2"
---

# Proteomics Expert Agent

This agent specializes in proteomics data analysis workflows.

## Capabilities
- Tool selection for DIA vs DDA data
- Parameter configuration for MS tools
- Workflow validation for proteomics pipelines
```

**Invocation**:
```bash
$proteomics-expert Help me analyze DIA data from Orbitrap
```

**Strengths**:
- ✅ Explicit permission boundaries (security)
- ✅ Reusable across projects (install once)
- ✅ Community marketplace for sharing
- ✅ Clear separation of concerns

**Limitations**:
- ❌ Manual creation (no automated learning)
- ❌ Static prompts (don't evolve)
- ❌ Requires upfront domain expertise

**Resources**:
- Agent Configuration: https://docs.iflow.cn/en/docs/examples/subagent
- Agent Marketplace: https://platform.iflow.cn/agents?type=agents
- Installation Guide: https://docs.iflow.cn/en/docs/examples/subagent#agent-installation-management

#### ACE Agent System

**Specialized Roles** (from paper):
1. **Generator**: General-purpose, uses playbook
2. **Reflector**: Specialized in error analysis
3. **Curator**: Specialized in knowledge synthesis

**Key Difference**: ACE agents are **functional roles**, not domain specialists.

**Strengths**:
- ✅ Automated specialization through reflection
- ✅ Learns domain knowledge over time
- ✅ No manual prompt engineering needed

**Limitations**:
- ❌ Less explicit than iFlow's domain agents
- ❌ All roles need same context window
- ❌ Harder to share/reuse across projects

**Resource**: https://arxiv.org/abs/2510.04618 (Section 3: ACE Framework)

#### BioMate Integration: Hybrid Agent System

**Proposal: iFlow-style agents + ACE-style learning**

```markdown
# .iflow/agents/tool-selector.md
---
agentType: "tool-selector"
systemPrompt: "You select appropriate proteomics tools based on data type"
whenToUse: "Use when generating workflows or validating tool choices"
allowedTools: ["Read"]
allowedMcps: ["tool-database"]

# ACE integration: Reference evolving playbook
playbookSections: ["tool_selection_rules", "data_type_compatibility"]
---

# Tool Selector Agent

You are an expert at selecting proteomics analysis tools.

## Evolving Knowledge Base

{{playbook.tool_selection_rules}}  <!-- Populated by ACE Curator -->

## Your Task
1. Analyze user's data type (DIA/DDA/etc)
2. Consult playbook rules above
3. Select compatible tools
4. Explain reasoning
```

**Workflow**:
```bash
# User invokes agent
$tool-selector What tools for DIA Orbitrap data?

# Agent uses current playbook (ACE-maintained)
# After execution, ACE updates playbook in background
```

**Benefits**:
- iFlow's explicit agent boundaries
- ACE's evolving knowledge
- User sees transparent tool selection
- System learns from corrections automatically

### 4. Workflow Composition

#### iFlow Workflow System

**Structure**:
```
Project/
├── .iflow/
│   ├── agents/           # Domain specialists
│   │   ├── tool-selector.md
│   │   └── parameter-expert.md
│   ├── commands/         # Reusable commands
│   │   ├── validate-workflow.md
│   │   └── execute-step.md
│   ├── IFLOW.md          # Main workflow doc
│   └── settings.json     # MCP + other config
└── data/                 # User's data
```

**IFLOW.md Example**:
```markdown
# DIA Proteomics Analysis Workflow

## Overview
This workflow analyzes DIA mass spectrometry data.

## Prerequisites
- Raw data in mzML format
- Spectral library (optional)

## Steps
1. Use `$tool-selector` to choose analysis tool
2. Run `/validate-workflow` to check compatibility
3. Configure parameters with `$parameter-expert`
4. Execute workflow

## Configuration
- Tools: DIA-NN, MSstats, DESeq2
- MCP Servers: tool-database, galaxy-api
```

**Strengths**:
- ✅ Self-documenting (IFLOW.md serves as README)
- ✅ Composable (agents + commands + tools)
- ✅ Shareable (zip entire .iflow folder)
- ✅ Version controlled (agents are markdown files)

**Limitations**:
- ❌ No automatic optimization of workflows
- ❌ Manual updates when best practices change
- ❌ Requires upfront workflow design

**Resources**:
- Workflow Documentation: https://docs.iflow.cn/en/docs/examples/workflow
- Packaging Guide: https://docs.iflow.cn/en/docs/examples/workflow#package-workflow
- Marketplace: https://platform.iflow.cn/agents?type=workflows

#### ACE Playbook System

**Structure**:
```json
{
  "version": "1.0",
  "sections": {
    "tool_selection_rules": {
      "bullets": [
        {
          "id": "tool-00001",
          "content": "For DIA data, use DIA-NN or Spectronaut (never MaxQuant)",
          "helpful": 15,
          "harmful": 0
        }
      ]
    },
    "parameter_guidelines": {
      "bullets": [
        {
          "id": "param-00001",
          "content": "DIA-NN default FDR: 0.01 for high confidence",
          "helpful": 8,
          "harmful": 1
        }
      ]
    }
  }
}
```

**Strengths**:
- ✅ Self-improving (bullets added automatically)
- ✅ Empirically validated (helpful/harmful counters)
- ✅ Structured (JSON, easy to query)
- ✅ Scales (incremental updates)

**Limitations**:
- ❌ Less human-readable than markdown
- ❌ Requires training period to build up
- ❌ Harder to manually curate

**Resource**: https://arxiv.org/abs/2510.04618 (Section 3.1: Incremental Delta Updates)

#### BioMate Integration: Workflow + Playbook Hybrid

**Proposal**:

```
Project/
├── .iflow/
│   ├── agents/
│   │   └── proteomics-agents.md     # iFlow-style agents
│   ├── commands/
│   │   └── proteomics-commands.md   # iFlow-style commands
│   ├── IFLOW.md                     # Human-readable workflow doc
│   └── playbook.json                # ACE-style evolving knowledge
└── data/
```

**IFLOW.md** (iFlow-style, user-facing):
```markdown
# DIA Proteomics Analysis Workflow

## Steps
1. **Data Upload**: Use `@data/experiment.raw` to reference file
2. **Tool Selection**: Run `$tool-selector` to pick analysis tools
3. **Workflow Generation**: System generates step-by-step workflow
4. **Validation**: Automatic format compatibility checks
5. **Execution**: Run workflow or export to Galaxy

## Learn More
- See `playbook.json` for accumulated best practices
- Run `/playbook show tool-selection` to see learned rules
```

**playbook.json** (ACE-style, machine-maintained):
```json
{
  "tool_selection_rules": [
    {
      "id": "dia-tool-001",
      "content": "DIA data from Orbitrap → DIA-NN (fastest) or Spectronaut (most accurate)",
      "helpful": 23,
      "harmful": 0,
      "source": "learned",
      "created": "2025-01-15"
    }
  ]
}
```

**User Flow**:
```bash
# User reads IFLOW.md (human-friendly)
> cat .iflow/IFLOW.md

# User invokes workflow (iFlow syntax)
> /workflow dia-analysis @data/experiment.raw

# Behind scenes: ACE system uses playbook.json
# After execution: ACE updates playbook.json automatically

# User can inspect what was learned
> /playbook show tool-selection-rules
  [Shows bullets from playbook.json in human-readable format]
```

**Benefits**:
- iFlow's documentation clarity (IFLOW.md)
- ACE's learning capability (playbook.json)
- Best of both worlds

### 5. Learning & Evolution

#### iFlow Learning Model: Manual Curation

**Process**:
1. Expert creates workflow in `.iflow/`
2. Users install and use workflow
3. If workflow needs updates, expert manually edits files
4. Users pull updates from marketplace

**Strengths**:
- ✅ High quality (expert-curated)
- ✅ Explicit versioning (git-based)
- ✅ Community-driven (marketplace)

**Limitations**:
- ❌ Slow to adapt (requires expert intervention)
- ❌ Doesn't learn from user feedback
- ❌ Static workflows don't improve automatically

**Resource**: https://docs.iflow.cn/en/docs/examples/workflow#best-practices-for-workflow-sharing

#### ACE Learning Model: Automated Evolution

**Process**:
1. System generates workflow using playbook
2. Execution provides feedback (success/failure)
3. Reflector analyzes what went wrong
4. Curator updates playbook automatically
5. Next workflow uses improved playbook

**Multi-Epoch Training** (from paper):
```python
# Offline training
for epoch in range(5):
    for workflow_example in training_set:
        # Generate using current playbook
        generated = generator.generate(workflow_example.query, playbook)

        # Compare with ground truth
        result = evaluate(generated, workflow_example.ground_truth)

        # Learn from mistakes
        reflection = reflector.analyze(generated, result)
        delta = curator.create_delta(reflection)
        playbook = merge(playbook, delta)
```

**Results from Paper**:
- Epoch 1 → Epoch 5: +4.3% accuracy improvement
- 86.9% reduction in adaptation latency
- Works without labels (execution feedback sufficient)

**Strengths**:
- ✅ Continuous improvement
- ✅ Learns from all users (aggregated knowledge)
- ✅ Fast adaptation to new patterns

**Limitations**:
- ❌ Needs feedback loop (execution or validation)
- ❌ Can learn wrong lessons from bad examples
- ❌ Less interpretable (automated updates)

**Resource**:
- ACE Paper Section 4.5: https://arxiv.org/abs/2510.04618
- ACE Ablation Study (multi-epoch importance)

#### BioMate Integration: Hybrid Learning

**Expert-Seeded + Auto-Evolved**:

```typescript
class BiomatePlaybook {
  // Phase 1: Expert seed (iFlow-style)
  initializeFromExperts() {
    this.playbook = loadExpertCuratedRules();
    // 50-100 bullets from proteomics experts
  }

  // Phase 2: Automated learning (ACE-style)
  async learnFromWorkflow(workflow: Workflow, result: ExecutionResult) {
    const reflection = await this.reflector.analyze(workflow, result);
    const delta = await this.curator.generateDelta(reflection);

    // Auto-update playbook
    this.playbook = this.merge(this.playbook, delta);

    // But: Flag for expert review if high-impact change
    if (delta.affectsToolSelection) {
      await this.requestExpertReview(delta);
    }
  }

  // Human-in-the-loop
  async requestExpertReview(delta: Delta) {
    // Email domain expert: "ACE wants to add this rule, approve?"
    const approved = await emailExpert(delta);
    if (approved) {
      this.applyDelta(delta);
    }
  }
}
```

**Governance Model**:
- **Low-risk changes**: Auto-apply (e.g., parameter tweaks)
- **Medium-risk changes**: Apply with notification (e.g., new tool suggestions)
- **High-risk changes**: Require approval (e.g., "never use Tool X")

**Benefits**:
- Expert quality (seeded knowledge)
- Continuous improvement (ACE learning)
- Safety (human oversight for critical changes)

---

## Complementary Strengths

### What iFlow Does Better

1. **User Experience**
   - Clear slash commands (`/init`, `/clear`, `/memory`)
   - Intuitive file references (`@data/file.csv`)
   - Explicit agent calls (`$agent-name`)
   - Visual workflow composition

2. **Documentation & Sharing**
   - IFLOW.md serves as self-documenting workflow
   - Easy to share (zip entire `.iflow/` folder)
   - Marketplace for discovering workflows
   - Version control friendly (markdown + JSON)

3. **Permission & Security**
   - Explicit tool permissions per agent
   - MCP server access control
   - User can inspect what each agent can do
   - Sandboxed execution

4. **Community Ecosystem**
   - Active marketplace: https://platform.iflow.cn/agents
   - Pre-built workflows for common tasks
   - Expert-curated agents
   - Established patterns and best practices

**BioMate Should Adopt**:
- Slash command syntax for proteomics workflows
- File reference system for dataset handling
- Agent marketplace model (proteomics tool selector, parameter expert, etc.)
- IFLOW.md for documenting workflow patterns

### What ACE Does Better

1. **Automated Learning**
   - Learns from execution feedback (no labels needed)
   - Multi-epoch refinement (5 iterations → +4.3% accuracy)
   - Incremental updates (prevents context collapse)
   - Scales to large knowledge bases

2. **Context Management**
   - Structured bullets with metadata (helpful/harmful counters)
   - Deterministic merge (no LLM hallucination during updates)
   - Semantic deduplication (removes redundancy)
   - Grow-and-refine mechanism (automatic pruning)

3. **Efficiency**
   - 86.9% latency reduction vs. monolithic rewrites
   - 75.1% fewer rollouts needed
   - 83.6% lower token costs
   - Parallel delta generation

4. **Empirical Validation**
   - +10.6% improvement on agent benchmarks
   - +8.6% on domain-specific tasks
   - Matches GPT-4 agent with smaller open-source model
   - Works without ground truth labels

**BioMate Should Adopt**:
- Three-agent architecture (Generator, Reflector, Curator)
- Incremental delta updates (prevent knowledge loss)
- Helpful/harmful bullet tracking
- Multi-epoch training on validation workflows

### Where They Complement Each Other

| Aspect | iFlow Contribution | ACE Contribution | BioMate Result |
|--------|-------------------|------------------|----------------|
| **Initial Setup** | Expert-curated workflows | Automated seed from examples | Hybrid: 50 expert rules + learn from data |
| **User Interaction** | `/workflow dia-analysis` | Playbook-guided generation | Clear commands + intelligent execution |
| **Knowledge Growth** | Manual marketplace updates | Automated delta learning | Community curation + self-improvement |
| **Context Handling** | `/compress` manual control | Grow-and-refine automatic | User control + background optimization |
| **Agent System** | Explicit domain specialists | Functional role separation | Proteomics agents + learning roles |
| **Sharing** | Zip workflow, upload marketplace | Export playbook JSON | Both: workflow templates + learned knowledge |

**Synthesis**: iFlow provides the **UX layer** (commands, files, agents), ACE provides the **intelligence layer** (learning, optimization, evolution).

---

## Recommended Integration Architecture

### Overall System Design

```
┌─────────────────────────────────────────────────────────────┐
│                    User Interface Layer                     │
│                   (iFlow-inspired syntax)                    │
│                                                              │
│  /workflow <type>          Slash commands                   │
│  @data/file.mzML           File references                  │
│  $tool-selector            Agent invocation                 │
│  !galaxy-execute           Shell execution                  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                 Workflow Orchestration Layer                │
│                  (BioMate custom logic)                      │
│                                                              │
│  - Parse user intent                                        │
│  - Route to appropriate agent                               │
│  - Manage conversation context                             │
│  - Format results for UI                                    │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────┬──────────────────────┬──────────────┐
│  iFlow-Style Agents  │  ACE Learning System │ Tool Database│
│  (Domain Specialists)│  (Intelligence)      │ (Metadata)   │
│                      │                      │              │
│  • tool-selector.md  │  • Generator Agent   │ • Galaxy     │
│  • param-expert.md   │  • Reflector Agent   │   Tools      │
│  • validator.md      │  • Curator Agent     │ • Input/     │
│  • explainer.md      │  • Playbook (JSON)   │   Output     │
│                      │  • Delta Updates     │ • Scientific │
│                      │                      │   Context    │
└──────────────────────┴──────────────────────┴──────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    Execution & Feedback Layer                │
│                                                              │
│  - Galaxy API integration                                   │
│  - Workflow execution monitoring                            │
│  - Format validation                                        │
│  - Feedback collection                                      │
└─────────────────────────────────────────────────────────────┘
```

### Component Details

#### 1. iFlow-Style Interface Components

**Slash Commands for BioMate**:

```typescript
// frontend/server/lib/commands/index.ts
export const BIOMATE_COMMANDS = {
  // Workflow management
  '/workflow': {
    subcommands: {
      'dia-proteomics': 'Generate DIA proteomics analysis workflow',
      'dda-proteomics': 'Generate DDA proteomics analysis workflow',
      'rna-seq': 'Generate RNA-seq analysis workflow',
      'init': 'Initialize workflow from project context'
    }
  },

  // Playbook inspection (ACE integration)
  '/playbook': {
    subcommands: {
      'show': 'Display playbook section',
      'stats': 'Show playbook statistics',
      'export': 'Export playbook for sharing'
    }
  },

  // Memory management
  '/memory': {
    subcommands: {
      'add': 'Add persistent instruction',
      'clear': 'Clear conversation memory',
      'compress': 'Summarize long conversation'
    }
  },

  // Context building (iFlow /init pattern)
  '/init': 'Analyze project and build context'
};
```

**File Reference Syntax**:

```typescript
// frontend/server/lib/parsers/fileReference.ts
function parseFileReferences(input: string): FileReference[] {
  // @data/experiment.raw → Include file in context
  // @folder/project/ → Include directory structure
  const regex = /@([\w\-\/\.]+)/g;
  return [...input.matchAll(regex)].map(match => ({
    path: match[1],
    type: inferType(match[1])  // file vs directory
  }));
}
```

**Agent Call Syntax**:

```typescript
// frontend/server/lib/parsers/agentCall.ts
function parseAgentCalls(input: string): AgentCall[] {
  // $tool-selector What tools for DIA data?
  const regex = /\$(\w+)\s+(.+)/g;
  return [...input.matchAll(regex)].map(match => ({
    agentType: match[1],
    query: match[2]
  }));
}
```

#### 2. ACE-Powered Learning Backend

**Three-Agent Implementation**:

```typescript
// frontend/server/lib/ace/index.ts
export class ACESystem {
  private generator: GeneratorAgent;
  private reflector: ReflectorAgent;
  private curator: CuratorAgent;
  private playbook: Playbook;

  constructor() {
    this.generator = new GeneratorAgent();
    this.reflector = new ReflectorAgent();
    this.curator = new CuratorAgent();
    this.playbook = this.loadPlaybook();
  }

  // Main workflow generation (uses ACE Generator)
  async generateWorkflow(userQuery: string): Promise<WorkflowResult> {
    const { workflow, bulletFeedback } = await this.generator.generate(
      userQuery,
      this.playbook
    );

    return {
      workflow,
      bulletFeedback,
      playbookVersion: this.playbook.version
    };
  }

  // Learning loop (ACE Reflector + Curator)
  async learnFromExecution(
    workflow: Workflow,
    executionResult: ExecutionResult
  ): Promise<void> {
    // Step 1: Reflect on what happened
    const reflection = await this.reflector.analyze(
      workflow,
      executionResult,
      this.playbook
    );

    // Step 2: Generate delta update
    const delta = await this.curator.generateDelta(
      reflection,
      this.playbook
    );

    // Step 3: Merge deterministically
    this.playbook = this.mergeDelta(this.playbook, delta);

    // Step 4: Save updated playbook
    await this.savePlaybook(this.playbook);
  }

  // Non-LLM merge (fast, deterministic)
  private mergeDelta(playbook: Playbook, delta: Delta): Playbook {
    const updated = { ...playbook };

    for (const op of delta.operations) {
      if (op.type === 'ADD') {
        updated.sections[op.section].bullets.push({
          id: this.generateBulletId(),
          content: op.content,
          helpful: 0,
          harmful: 0,
          createdAt: new Date()
        });
      }
      // Handle UPDATE, REMOVE similarly
    }

    return updated;
  }
}
```

#### 3. Hybrid Agent System

**iFlow-Style Agent Configuration**:

```markdown
<!-- .iflow/agents/tool-selector.md -->
---
agentType: "tool-selector"
systemPrompt: |
  You are a proteomics tool selection expert.
  Your job is to recommend appropriate analysis tools based on:
  - Data type (DIA, DDA, DIA-PASEF, etc.)
  - Instrument (Orbitrap, QTOF, TripleTOF, timsTOF)
  - Analysis goals (identification, quantification, PTMs, etc.)

whenToUse: "Use when selecting tools for proteomics workflow generation"
allowedTools: ["Read"]
allowedMcps: ["tool-database"]

# ACE integration
playbookSections: ["tool_selection_rules", "data_type_compatibility"]
---

# Tool Selector Agent

## Process
1. Analyze user's data characteristics
2. Consult evolving playbook (auto-maintained by ACE)
3. Select compatible tools
4. Explain selection rationale

## Evolving Knowledge (from ACE Playbook)

{{playbook.tool_selection_rules}}

## Tool Recommendations

Based on the playbook above and user's data type, recommend tools.
```

**Runtime Integration**:

```typescript
// frontend/server/lib/agents/toolSelector.ts
export class ToolSelectorAgent {
  private aceSystem: ACESystem;

  async select(userQuery: string): Promise<ToolSelection> {
    // Get current playbook from ACE
    const playbook = this.aceSystem.getPlaybook();

    // Render agent prompt with playbook content
    const prompt = this.renderPrompt({
      userQuery,
      playbookRules: playbook.sections.tool_selection_rules
    });

    // Call Claude
    const selection = await claude.generate(prompt);

    // Track which playbook bullets were helpful
    const bulletFeedback = this.trackBulletUsage(selection, playbook);

    return { selection, bulletFeedback };
  }
}
```

#### 4. Workflow Composition Pattern

**Directory Structure**:

```
biomate-project/
├── .iflow/
│   ├── agents/
│   │   ├── tool-selector.md           # iFlow agent
│   │   ├── parameter-expert.md        # iFlow agent
│   │   └── workflow-validator.md      # iFlow agent
│   ├── commands/
│   │   ├── validate-workflow.md       # Custom command
│   │   └── export-to-galaxy.md        # Custom command
│   ├── IFLOW.md                       # Human-readable workflow doc
│   ├── playbook.json                  # ACE-maintained knowledge
│   └── settings.json                  # MCP + config
└── data/
    ├── experiment.raw
    └── spectral-library.tsv
```

**IFLOW.md** (User-facing documentation):

```markdown
# BioMate DIA Proteomics Workflow

## Quick Start
```bash
# 1. Initialize project
/init

# 2. Reference your data
@data/experiment.raw

# 3. Generate workflow
/workflow dia-proteomics

# 4. Validate before execution
/validate

# 5. Execute or export
/execute
# or
/export galaxy
```

## Workflow Steps

1. **Tool Selection**
   - Agent: `$tool-selector`
   - Playbook section: `tool_selection_rules`
   - Input: Data type, instrument
   - Output: Recommended tools (DIA-NN, MSstats, etc.)

2. **Parameter Configuration**
   - Agent: `$parameter-expert`
   - Playbook section: `parameter_guidelines`
   - Input: Selected tools
   - Output: Configured parameters (FDR, charge states, etc.)

3. **Workflow Validation**
   - Agent: `$workflow-validator`
   - Playbook section: `format_compatibility`
   - Input: Generated workflow
   - Output: Validation report

4. **Execution**
   - Integration: Galaxy API
   - Monitoring: Real-time status
   - Feedback: Execution results → ACE learning

## Learned Knowledge

See `playbook.json` for accumulated best practices.
Run `/playbook show <section>` to inspect learned rules.

## Version History

- v1.0: Initial expert-seeded playbook (50 rules)
- v1.1: +15 rules learned from 100 workflow executions
- v1.2: +8 rules learned from user corrections
```

**playbook.json** (ACE-maintained):

```json
{
  "version": "1.2",
  "lastUpdated": "2025-10-30T10:30:00Z",
  "sections": {
    "tool_selection_rules": {
      "bullets": [
        {
          "id": "tool-dia-001",
          "content": "DIA data from Orbitrap instruments: Use DIA-NN for speed or Spectronaut for accuracy. Never use MaxQuant (DDA-only).",
          "helpful": 23,
          "harmful": 0,
          "source": "expert_seed",
          "createdAt": "2025-01-15T00:00:00Z"
        },
        {
          "id": "tool-dia-002",
          "content": "DIA-PASEF (timsTOF) data: DIA-NN has native support. Spectronaut also works but slower.",
          "helpful": 8,
          "harmful": 0,
          "source": "learned",
          "createdAt": "2025-02-03T14:23:00Z"
        }
      ]
    },
    "parameter_guidelines": {
      "bullets": [
        {
          "id": "param-fdr-001",
          "content": "DIA-NN default FDR: 0.01 for high-confidence identifications. For exploratory analysis, 0.05 acceptable.",
          "helpful": 15,
          "harmful": 1,
          "source": "expert_seed"
        }
      ]
    }
  }
}
```

---

## Resource Links

### iFlow CLI Resources

**Official Documentation**:
- Main Docs: https://docs.iflow.cn/en/docs/introduction
- Quick Start: https://docs.iflow.cn/en/docs/quickstart
- Use Cases: https://docs.iflow.cn/en/docs/scenarios (scenarios.md analyzed earlier)
- Best Practices: https://docs.iflow.cn/en/docs/examples/best-practices

**Key Features**:
- Slash Commands: https://docs.iflow.cn/en/docs/features/slash-commands
- Interactive Mode: https://docs.iflow.cn/en/docs/features/interactive
- Sub-Agents: https://docs.iflow.cn/en/docs/examples/subagent
- Workflows: https://docs.iflow.cn/en/docs/examples/workflow
- MCP Integration: https://docs.iflow.cn/en/docs/examples/mcp

**Code Repository**:
- GitHub: https://github.com/iflow-ai/iflow-cli
- Installation: `npm install -g @iflow/cli`

**Marketplace**:
- Agent Marketplace: https://platform.iflow.cn/agents
- Workflow Marketplace: https://platform.iflow.cn/agents?type=workflows

**Examples**:
- Basic Usage: https://docs.iflow.cn/en/docs/examples/basic-usage
- Advanced Configuration: https://docs.iflow.cn/en/docs/configuration/settings

**Comparison**:
- iFlow vs Claude Code: https://docs.iflow.cn/en/docs/comparison
- Feature Matrix: https://docs.iflow.cn/en/docs/introduction#key-features

### ACE Framework Resources

**Research Paper**:
- arXiv: https://arxiv.org/abs/2510.04618
- HTML Version: https://arxiv.org/html/2510.04618v1
- PDF: https://arxiv.org/pdf/2510.04618

**GitHub Implementations**:
1. **sci-m-wang/ACE-open** (Implementation Scaffold)
   - URL: https://github.com/sci-m-wang/ACE-open
   - Features: Core ACE loop, playbook management, LLM abstraction
   - Status: Open-source, community-maintained
   - Best for: Understanding architecture, rapid prototyping

2. **kayba-ai/agentic-context-engine** (Production-Ready)
   - URL: https://github.com/kayba-ai/agentic-context-engine
   - Features: Multi-LLM support (LiteLLM), production-grade
   - Status: Actively maintained
   - Best for: Production integration

3. **mmprotest/ace-playbook** (Educational)
   - URL: https://github.com/mmprotest/ace-playbook
   - Features: Three-role architecture focus
   - Best for: Learning the agent pattern

**Related Work**:
- Dynamic Cheatsheet (ACE Precursor): https://github.com/suzgunmirac/dynamic-cheatsheet
- Dynamic Cheatsheet Paper: https://arxiv.org/abs/2504.07952

**Benchmarks Used in Paper**:
- AppWorld: https://appworld.dev/
- AppWorld Leaderboard: https://appworld.dev/leaderboard
- FiNER (Financial NER): https://arxiv.org/abs/2203.06482

**Media Coverage**:
- MarkTechPost Article: https://www.marktechpost.com/2025/10/10/agentic-context-engineering-ace-self-improving-llms-via-evolving-contexts-not-fine-tuning/
- InfoQ News: https://www.infoq.com/news/2025/10/agentic-context-eng/

**Author Information**:
- Qizheng Zhang's Homepage: https://alex-q-z.github.io/
- Stanford Affiliations: https://cs.stanford.edu/

### BioMate-Specific Resources

**Current Documentation** (for reference):
- Tool Metadata Design: `/home/yzhang/biomate/reference/TOOL_METADATA_GAP_ANALYSIS_20251030.md`
- Claude Code Design: `/home/yzhang/biomate/reference/CLAUDE_CODE_INSPIRED_PLATFORM_DESIGN_20251030.md`
- Discussion Questions: `/home/yzhang/biomate/reference/DISCUSSION_QUESTIONS_WORKFLOW_GENERATION_20251030.md`
- iFlow Patterns: `/home/yzhang/biomate/reference/claude_prompts/IFLOW_PROMPT_PATTERNS_20251030.md`
- ACE Analysis: `/home/yzhang/biomate/reference/ACE_FRAMEWORK_ANALYSIS_20251030.md`

**Integration Resources** (this document):
- This Document: `/home/yzhang/biomate/reference/IFLOW_ACE_BIOMATE_INTEGRATION_20251030.md`

### Community & Support

**iFlow Community**:
- GitHub Discussions: https://github.com/iflow-ai/iflow-cli/discussions
- GitHub Issues: https://github.com/iflow-ai/iflow-cli/issues

**ACE Community**:
- Paper Discussion (Hugging Face): https://huggingface.co/papers/2510.04618
- AI Wiki Entry: https://aiwiki.ai/wiki/Agentic_Context_Engineering

**Related Frameworks**:
- Claude Code Docs: https://docs.claude.com/en/docs/claude-code
- MCP Protocol: https://modelcontextprotocol.io/
- DSPy (GEPA, MIPROv2): https://dspy.ai/

---

## Implementation Roadmap

### Phase 1: Foundation (Weeks 1-4)

**Goal**: Establish hybrid iFlow+ACE architecture

**Week 1: iFlow-Style Interface**
- [ ] Implement slash command parser
  - `/workflow <type>`
  - `/playbook <action>`
  - `/init`, `/clear`, `/memory`
- [ ] Implement file reference syntax (`@path/to/file`)
- [ ] Implement agent call syntax (`$agent-name query`)
- [ ] Create UI for command autocomplete

**Resources**:
- iFlow Slash Commands: https://docs.iflow.cn/en/docs/features/slash-commands
- Implementation reference: `iflow-cli/src/commands/`

**Week 2: Playbook Data Structure**
- [ ] Design PostgreSQL schema for playbook bullets
  ```sql
  CREATE TABLE playbook_bullets (
    id SERIAL PRIMARY KEY,
    bullet_id VARCHAR(50) UNIQUE,
    section VARCHAR(100),
    content TEXT,
    helpful_count INT DEFAULT 0,
    harmful_count INT DEFAULT 0,
    source VARCHAR(20),  -- 'expert_seed' or 'learned'
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    tags TEXT[]
  );
  ```
- [ ] Create TypeScript interfaces for Playbook, Bullet, Delta
- [ ] Implement playbook CRUD operations
- [ ] Create playbook initialization script (50 expert rules)

**Resources**:
- ACE Playbook Structure: https://arxiv.org/abs/2510.04618 (Section 3.1)
- Example implementation: `ACE-open/ace/playbook.py`

**Week 3: Enhanced Tool Metadata**
- [ ] Add missing columns to `tools` table
  ```sql
  ALTER TABLE tools ADD COLUMN data_types_supported TEXT[];
  ALTER TABLE tools ADD COLUMN data_types_not_supported TEXT[];
  ALTER TABLE tools ADD COLUMN common_mistakes TEXT;
  ALTER TABLE tools ADD COLUMN alternatives TEXT[];
  ```
- [ ] Populate metadata for 20 core proteomics tools
- [ ] Create migration script for existing tools
- [ ] Build metadata validation API

**Resources**:
- Tool Metadata Analysis: `/home/yzhang/biomate/reference/TOOL_METADATA_GAP_ANALYSIS_20251030.md`

**Week 4: iFlow Agent Configuration**
- [ ] Create `.iflow/agents/` directory structure
- [ ] Implement tool-selector agent (markdown config)
- [ ] Implement parameter-expert agent
- [ ] Implement workflow-validator agent
- [ ] Create agent invocation system

**Resources**:
- iFlow Sub-Agent Docs: https://docs.iflow.cn/en/docs/examples/subagent
- Agent Configuration Examples: https://platform.iflow.cn/agents

### Phase 2: ACE Integration (Weeks 5-8)

**Week 5: Generator Agent**
- [ ] Implement `GeneratorAgent` class
- [ ] Create prompt template with playbook injection
  ```typescript
  const prompt = `
  You are a proteomics workflow generator.

  EVOLVING PLAYBOOK:
  ${playbook.renderSection('tool_selection_rules')}
  ${playbook.renderSection('parameter_guidelines')}

  User Query: ${userQuery}
  `;
  ```
- [ ] Implement bullet usage tracking
- [ ] Test with existing tool database

**Resources**:
- ACE Generator: https://arxiv.org/abs/2510.04618 (Section 3)
- Prompt Examples: ACE paper Appendix D (Figures 6-9)

**Week 6: Reflector Agent**
- [ ] Implement `ReflectorAgent` class
- [ ] Create reflection prompt template
  ```typescript
  const prompt = `
  Analyze this workflow execution:

  Generated Workflow: ${JSON.stringify(workflow)}
  Execution Result: ${JSON.stringify(result)}
  Ground Truth (if available): ${groundTruth}

  Identify:
  1. What went wrong (error_identification)
  2. Why it happened (root_cause_analysis)
  3. How to fix (correct_approach)
  4. Principle to remember (key_insight)
  `;
  ```
- [ ] Implement bullet tagging (helpful/harmful/neutral)
- [ ] Create unit tests with known failure cases

**Resources**:
- ACE Reflector: https://arxiv.org/abs/2510.04618 (Section 3)
- Reflector Prompts: ACE paper Figures 10, 13

**Week 7: Curator Agent**
- [ ] Implement `CuratorAgent` class
- [ ] Create delta generation prompt
  ```typescript
  const prompt = `
  Based on this reflection, generate playbook updates:

  Reflection: ${JSON.stringify(reflection)}
  Current Playbook: ${JSON.stringify(playbook)}

  Output JSON:
  {
    "operations": [
      {"type": "ADD", "section": "...", "content": "..."}
    ]
  }
  `;
  ```
- [ ] Implement deterministic merge (non-LLM)
- [ ] Add semantic deduplication (embedding-based)
- [ ] Create playbook versioning system

**Resources**:
- ACE Curator: https://arxiv.org/abs/2510.04618 (Section 3.1)
- Curator Prompts: ACE paper Figures 11, 14

**Week 8: ACE Loop Integration**
- [ ] Implement offline training loop
  ```typescript
  for (let epoch = 0; epoch < 5; epoch++) {
    for (const example of trainingSet) {
      const workflow = await generator.generate(example.query, playbook);
      const result = await execute(workflow);
      const reflection = await reflector.analyze(workflow, result);
      const delta = await curator.generateDelta(reflection);
      playbook = mergeDelta(playbook, delta);
    }
    await saveCheckpoint(playbook, epoch);
  }
  ```
- [ ] Create training dataset (50 validation workflows)
- [ ] Run first multi-epoch training
- [ ] Analyze playbook growth metrics

**Resources**:
- Multi-Epoch Training: https://arxiv.org/abs/2510.04618 (Section 4.3)
- Implementation: `ACE-open/ace/adaptation.py`

### Phase 3: Integration & Testing (Weeks 9-12)

**Week 9: UI Integration**
- [ ] Build slash command UI (autocomplete, help text)
- [ ] Create playbook inspection interface
  ```typescript
  // /playbook show tool-selection-rules
  // Displays bullets with helpful/harmful counters
  ```
- [ ] Add agent call UI ($ syntax support)
- [ ] Implement file reference picker (@data/...)

**Week 10: Feedback Loop**
- [ ] Implement workflow execution monitoring
- [ ] Create feedback collection system
  - Execution success/failure
  - User corrections
  - Format validation errors
- [ ] Connect feedback to ACE Reflector
- [ ] Set up background learning task queue

**Week 11: Online Adaptation**
- [ ] Deploy online learning (test-time)
- [ ] Implement lazy playbook refinement
  ```typescript
  if (playbook.size() > MAX_SIZE) {
    playbook = refinePlaybook(playbook);  // Deduplicate, prune
  }
  ```
- [ ] Create A/B testing framework
  - Group A: Current approach
  - Group B: ACE-powered
- [ ] Set up metrics dashboard

**Week 12: Validation & Tuning**
- [ ] Run ablation studies
  - ACE vs. current baseline
  - With/without Reflector
  - 1 epoch vs. 5 epochs
- [ ] Collect user feedback
- [ ] Tune parameters (delta threshold, deduplication threshold)
- [ ] Document learned best practices

### Phase 4: Production Deployment (Weeks 13-16)

**Week 13: Playbook Management UI**
- [ ] Build expert review interface
  - Review proposed deltas
  - Approve/reject/modify
- [ ] Create playbook export/import
- [ ] Implement playbook versioning UI
- [ ] Add playbook statistics dashboard

**Week 14: Community Features** (Optional)
- [ ] Create BioMate workflow marketplace
  - Upload/download workflows
  - Star/rating system
- [ ] Implement playbook sharing
  - Export as JSON
  - Import from colleagues
- [ ] Build workflow template library

**Week 15: Multi-Omics Extension**
- [ ] Extend to genomics workflows
  - RNA-seq playbook
  - Variant calling playbook
- [ ] Extend to metabolomics workflows
  - LC-MS metabolomics playbook
- [ ] Create domain-specific agents for each

**Week 16: Polish & Launch**
- [ ] Performance optimization
- [ ] Security audit (agent permissions, playbook updates)
- [ ] Documentation update
- [ ] User training materials
- [ ] Production deployment

---

## Concrete Code Examples

### Example 1: iFlow-Style Command Handler

```typescript
// frontend/server/lib/commands/workflowCommand.ts
import { ACESystem } from '../ace';
import { parseFileReferences } from '../parsers/fileReference';

export class WorkflowCommand {
  private aceSystem: ACESystem;

  constructor() {
    this.aceSystem = new ACESystem();
  }

  async execute(args: string, context: ConversationContext): Promise<CommandResult> {
    // Parse command: /workflow dia-proteomics @data/experiment.raw
    const [workflowType, ...rest] = args.split(' ');
    const query = rest.join(' ');

    // Extract file references
    const fileRefs = parseFileReferences(query);
    const fileContents = await this.loadFiles(fileRefs);

    // Build enriched query
    const enrichedQuery = `
      Workflow Type: ${workflowType}
      User Query: ${query}

      Referenced Files:
      ${fileContents.map(f => `${f.path}:\n${f.content}`).join('\n\n')}
    `;

    // Generate workflow using ACE
    const { workflow, bulletFeedback } = await this.aceSystem.generateWorkflow(
      enrichedQuery
    );

    // Update bullet counters
    await this.aceSystem.updateBulletCounters(bulletFeedback);

    return {
      success: true,
      workflow,
      message: `Generated ${workflowType} workflow using ${Object.keys(bulletFeedback).length} playbook rules`
    };
  }
}
```

**Resource**:
- iFlow Command Pattern: https://docs.iflow.cn/en/docs/examples/basic-usage#slash-command-execution
- ACE Generator: https://github.com/sci-m-wang/ACE-open/blob/main/ace/generator.py

### Example 2: ACE Three-Agent Workflow

```typescript
// frontend/server/lib/ace/workflow.ts
export class ACEWorkflow {
  async processWorkflowExecution(
    workflow: Workflow,
    executionResult: ExecutionResult
  ): Promise<PlaybookUpdate> {

    // Step 1: Generator marks bullets as helpful/harmful
    const bulletFeedback = this.extractBulletFeedback(workflow);

    // Step 2: Reflector analyzes execution
    const reflection = await this.reflector.analyze({
      workflow,
      executionResult,
      playbook: this.playbook,
      bulletFeedback
    });

    // Example reflection output:
    // {
    //   errorIdentification: "MaxQuant was used for DIA data",
    //   rootCause: "Tool database lacks data_types_not_supported field",
    //   correctApproach: "Check data type before tool selection",
    //   keyInsight: "MaxQuant is DDA-only, incompatible with DIA"
    // }

    // Step 3: Curator generates delta
    const delta = await this.curator.generateDelta({
      reflection,
      playbook: this.playbook,
      bulletFeedback
    });

    // Example delta:
    // {
    //   operations: [
    //     {
    //       type: "ADD",
    //       section: "tool_selection_rules",
    //       content: "For DIA data, never use MaxQuant (DDA-only). Use DIA-NN or Spectronaut instead."
    //     },
    //     {
    //       type: "UPDATE",
    //       bulletId: "tool-00042",
    //       increment: "harmful"  // MaxQuant suggestion was harmful
    //     }
    //   ]
    // }

    // Step 4: Merge deterministically (no LLM call!)
    const updatedPlaybook = this.mergeDelta(this.playbook, delta);

    // Step 5: Save
    await this.savePlaybook(updatedPlaybook);

    return {
      playbookVersion: updatedPlaybook.version,
      bulletsAdded: delta.operations.filter(op => op.type === 'ADD').length,
      bulletsUpdated: delta.operations.filter(op => op.type === 'UPDATE').length
    };
  }

  // Deterministic merge (fast, no hallucination risk)
  private mergeDelta(playbook: Playbook, delta: Delta): Playbook {
    const updated = _.cloneDeep(playbook);
    updated.version = this.incrementVersion(playbook.version);
    updated.lastUpdated = new Date();

    for (const op of delta.operations) {
      switch (op.type) {
        case 'ADD':
          updated.sections[op.section].bullets.push({
            id: this.generateBulletId(op.section),
            content: op.content,
            helpful: 0,
            harmful: 0,
            source: 'learned',
            createdAt: new Date()
          });
          break;

        case 'UPDATE':
          const bullet = updated.findBullet(op.bulletId);
          if (op.increment === 'helpful') bullet.helpful++;
          if (op.increment === 'harmful') bullet.harmful++;
          bullet.updatedAt = new Date();
          break;

        case 'REMOVE':
          updated.removeBullet(op.bulletId);
          break;
      }
    }

    return updated;
  }
}
```

**Resource**:
- ACE Workflow: https://arxiv.org/abs/2510.04618 (Figure 4)
- Delta Updates: https://github.com/sci-m-wang/ACE-open/blob/main/ace/curator.py

### Example 3: iFlow Agent with ACE Playbook

```markdown
<!-- .iflow/agents/tool-selector.md -->
---
agentType: "tool-selector"
systemPrompt: |
  You are a proteomics tool selection expert.
  Use the evolving playbook below to make informed decisions.

whenToUse: "Use when selecting analysis tools for workflows"
model: "claude-3-5-sonnet-20241022"
allowedTools: ["Read"]
allowedMcps: ["tool-database"]
playbookSections: ["tool_selection_rules", "data_type_compatibility"]
proactive: false
---

# Tool Selector Agent

## Your Process

1. **Understand User's Data**
   - Data type: DIA, DDA, DIA-PASEF, etc.
   - Instrument: Orbitrap, QTOF, TripleTOF, timsTOF
   - Analysis goals: Identification, quantification, PTMs, etc.

2. **Consult Evolving Playbook**

{{playbook.tool_selection_rules}}

The rules above are automatically maintained by our learning system.
Rules with high `helpful` counts are proven patterns.
Rules with `harmful` counts should be avoided.

3. **Query Tool Database**

Use the `tool-database` MCP to check:
- Available tools
- Tool capabilities (data_types_supported)
- Tool limitations (data_types_not_supported)

4. **Make Recommendation**

Recommend 2-3 tools with rationale:
- Why each tool is appropriate
- Trade-offs between options
- Expected workflow sequence

## Example

User: "I have DIA data from an Orbitrap instrument"

Your Response:
```
Based on your DIA Orbitrap data, I recommend:

1. **DIA-NN** (Primary)
   - Playbook rule [tool-dia-001]: "DIA-NN for speed"
   - Helpful: 23, Harmful: 0
   - Best for: Fast analysis, large datasets

2. **Spectronaut** (Alternative)
   - Playbook rule [tool-dia-001]: "Spectronaut for accuracy"
   - Best for: Maximum sensitivity, small datasets

3. ❌ **MaxQuant** (Avoid)
   - Playbook rule [tool-dia-001]: "Never use MaxQuant for DIA"
   - Reason: DDA-only tool, incompatible with DIA
```
```

**TypeScript Integration**:

```typescript
// frontend/server/lib/agents/toolSelectorAgent.ts
export class ToolSelectorAgent {
  private playbook: Playbook;

  async select(userQuery: string): Promise<ToolSelection> {
    // Load agent configuration
    const agentConfig = await this.loadAgentConfig('tool-selector');

    // Render playbook sections into agent prompt
    const playbookContent = agentConfig.playbookSections
      .map(section => this.playbook.renderSection(section))
      .join('\n\n');

    // Build prompt
    const prompt = agentConfig.systemPrompt.replace(
      '{{playbook.tool_selection_rules}}',
      playbookContent
    );

    // Call Claude
    const response = await claude.generate(`${prompt}\n\nUser Query: ${userQuery}`);

    // Track bullet usage
    const bulletFeedback = this.trackBulletUsage(response, playbookContent);

    return {
      recommendation: response,
      bulletFeedback,
      playbookVersion: this.playbook.version
    };
  }

  private trackBulletUsage(
    response: string,
    playbookContent: string
  ): Record<string, 'helpful' | 'harmful'> {
    // Parse response for bullet references
    // e.g., "Playbook rule [tool-dia-001]" → mark as helpful
    const regex = /\[(\w+-\w+-\d+)\]/g;
    const matches = [...response.matchAll(regex)];

    const feedback: Record<string, 'helpful' | 'harmful'> = {};
    for (const match of matches) {
      const bulletId = match[1];

      // Check if bullet was used positively or negatively
      const context = response.substring(
        Math.max(0, match.index! - 50),
        Math.min(response.length, match.index! + 100)
      );

      if (context.includes('❌') || context.includes('Avoid') || context.includes('Never')) {
        feedback[bulletId] = 'harmful';
      } else {
        feedback[bulletId] = 'helpful';
      }
    }

    return feedback;
  }
}
```

**Resources**:
- iFlow Agent Config: https://docs.iflow.cn/en/docs/examples/subagent#custom-agent-configuration
- ACE Playbook Rendering: https://github.com/sci-m-wang/ACE-open/blob/main/ace/playbook.py

### Example 4: Slash Command for Playbook Inspection

```typescript
// frontend/server/lib/commands/playbookCommand.ts
export class PlaybookCommand {
  async execute(args: string): Promise<CommandResult> {
    const [subcommand, ...rest] = args.split(' ');

    switch (subcommand) {
      case 'show':
        return this.show(rest.join(' '));

      case 'stats':
        return this.stats();

      case 'export':
        return this.export();

      default:
        return {
          success: false,
          message: `Unknown subcommand: ${subcommand}\n\nAvailable: show, stats, export`
        };
    }
  }

  private async show(section: string): Promise<CommandResult> {
    const playbook = await this.loadPlaybook();

    if (!playbook.sections[section]) {
      return {
        success: false,
        message: `Section "${section}" not found.\n\nAvailable sections:\n${Object.keys(playbook.sections).join('\n')}`
      };
    }

    const bullets = playbook.sections[section].bullets;

    // Render in human-readable format
    const output = bullets
      .sort((a, b) => b.helpful - a.helpful)  // Sort by usefulness
      .map(bullet => `
[${bullet.id}] ${bullet.source === 'expert_seed' ? '👤' : '🤖'} ${bullet.helpful}✓ ${bullet.harmful}✗
${bullet.content}

Created: ${bullet.createdAt.toLocaleDateString()}
      `.trim())
      .join('\n\n---\n\n');

    return {
      success: true,
      message: `
# ${section} (${bullets.length} rules)

${output}

Legend:
👤 = Expert-seeded
🤖 = Learned from data
✓ = Times marked helpful
✗ = Times marked harmful
      `.trim()
    };
  }

  private async stats(): Promise<CommandResult> {
    const playbook = await this.loadPlaybook();

    const totalBullets = Object.values(playbook.sections)
      .reduce((sum, section) => sum + section.bullets.length, 0);

    const expertSeeded = Object.values(playbook.sections)
      .flatMap(section => section.bullets)
      .filter(b => b.source === 'expert_seed')
      .length;

    const learned = totalBullets - expertSeeded;

    const avgHelpful = Object.values(playbook.sections)
      .flatMap(section => section.bullets)
      .reduce((sum, b) => sum + b.helpful, 0) / totalBullets;

    return {
      success: true,
      message: `
# Playbook Statistics

Version: ${playbook.version}
Last Updated: ${playbook.lastUpdated.toLocaleString()}

Total Rules: ${totalBullets}
├─ Expert-Seeded: ${expertSeeded}
└─ Learned: ${learned}

Average Helpful Score: ${avgHelpful.toFixed(2)}

Section Breakdown:
${Object.entries(playbook.sections).map(([name, section]) =>
  `  ${name}: ${section.bullets.length} rules`
).join('\n')}
      `.trim()
    };
  }

  private async export(): Promise<CommandResult> {
    const playbook = await this.loadPlaybook();
    const filename = `playbook_${playbook.version}_${Date.now()}.json`;
    const filepath = `/tmp/${filename}`;

    await fs.writeFile(filepath, JSON.stringify(playbook, null, 2));

    return {
      success: true,
      message: `Playbook exported to: ${filepath}\n\nYou can share this file with colleagues or import it into another BioMate instance.`,
      data: { filepath }
    };
  }
}
```

**Usage Example**:
```bash
# Show tool selection rules
> /playbook show tool_selection_rules

# View playbook statistics
> /playbook stats

# Export playbook for sharing
> /playbook export
```

**Resource**:
- iFlow Command System: https://docs.iflow.cn/en/docs/features/slash-commands

---

## Conclusion

By integrating **iFlow CLI's UX patterns** with **ACE's learning system**, BioMate can achieve:

1. **Intuitive Interface** (iFlow)
   - Slash commands for workflow management
   - File references for dataset handling
   - Agent calls for specialized tasks
   - Clear, documented workflows

2. **Intelligent Backend** (ACE)
   - Self-improving playbooks
   - Automated learning from feedback
   - Incremental knowledge updates
   - Prevention of context collapse

3. **Best of Both Worlds**
   - User-facing: Clear commands and documentation (iFlow)
   - Backend: Automated learning and optimization (ACE)
   - Integration: iFlow agents powered by ACE playbooks

**Next Steps**:
1. Review this integration architecture
2. Prioritize which components to implement first
3. Start with Phase 1 (Foundation) if approved
4. Iterate based on user feedback and performance metrics

**Resources Summary**:
- iFlow CLI: https://github.com/iflow-ai/iflow-cli
- iFlow Docs: https://docs.iflow.cn/en/docs/introduction
- ACE Paper: https://arxiv.org/abs/2510.04618
- ACE Implementation: https://github.com/sci-m-wang/ACE-open
- This Document: `/home/yzhang/biomate/reference/IFLOW_ACE_BIOMATE_INTEGRATION_20251030.md`
