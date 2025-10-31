# iFlow CLI Prompt Patterns and Best Practices

**Date:** 2025-10-30
**Source:** iFlow CLI Documentation (https://github.com/iflow-ai/iflow-cli)
**Purpose:** Extract key prompt patterns, command structures, and best practices for applying to BioMate workflow generation platform

---

## Executive Summary

iFlow CLI demonstrates sophisticated patterns for:
1. **Iterative Project Understanding** - `/init` command for context building
2. **Specialized Sub-Agents** - Domain-specific AI assistants with tool permissions
3. **Workflow Composition** - Combining agents, commands, and tools
4. **Context Management** - Memory compression, checkpointing, session recovery
5. **Progressive Disclosure** - From simple queries to complex multi-step workflows

**Key Takeaway:** Success comes from **building context progressively** rather than expecting perfect one-shot generation.

---

## Table of Contents

1. [Core Command Patterns](#core-command-patterns)
2. [Project Initialization & Context Building](#project-initialization--context-building)
3. [Sub-Agent System Patterns](#sub-agent-system-patterns)
4. [Workflow Composition](#workflow-composition)
5. [Questioning Techniques](#questioning-techniques)
6. [Development Workflow Patterns](#development-workflow-patterns)
7. [Error Handling & Recovery](#error-handling--recovery)
8. [Application to BioMate Platform](#application-to-biomate-platform)

---

## Core Command Patterns

### Slash Commands (Meta-Level Control)

iFlow uses `/` prefix for system-level commands that control the CLI itself:

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `/init` | Analyze project & build context | Start of every new project or conversation |
| `/clear` | Clear context & reset | When switching topics or context is cluttered |
| `/memory` | Manage persistent instructions | Add project-specific rules/preferences |
| `/compress` | Compress chat history to summary | When context is getting too long |
| `/chat save <name>` | Save conversation checkpoint | Before major changes or at milestones |
| `/chat restore <name>` | Restore previous conversation | Return to earlier state |
| `/tools` | List available tools | See what capabilities are available |
| `/stats` | Show usage statistics | Monitor token usage and performance |

### @ Symbol (File/Directory Reference)

```bash
@<path> - Include file or directory content in prompt

Examples:
@src/auth.js Review this authentication code for security issues
@data/sales_2024.csv Analyze this sales data and identify trends
@components/ What components are available in this directory?
```

### $ Symbol (Quick Agent Call)

```bash
$<agent-type> <task> - Quickly invoke specialized sub-agent

Examples:
$code-reviewer Perform security audit on current project
$frontend-developer Create responsive navigation component
$data-scientist Analyze trends in @data/sales.csv
```

### ! Symbol (Shell Command Execution)

```bash
!<command> - Execute shell command directly

Examples:
!git status
!npm test
!ls -la
```

---

## Project Initialization & Context Building

### The `/init` Pattern

**Purpose:** Establish comprehensive project context before AI attempts any work

**What it Does:**
1. Scans codebase structure
2. Identifies technology stack
3. Analyzes dependencies
4. Reads README/documentation
5. Creates `IFLOW.md` with project summary

**When to Use:**
- **Start of new conversation** in existing project
- **After major changes** to project structure
- **When AI responses** seem to lack context

**Workflow:**
```bash
cd my-project/
iflow
> /init
> [AI analyzes project, creates IFLOW.md]
> Now help me [specific task with full context]
```

**IFLOW.md Structure:**

```markdown
# IFLOW.md

## Project Overview
[High-level description of what this project does]

## Key Features
1. Feature A
2. Feature B
3. Feature C

## Repository Structure
- src/ - Source code
- tests/ - Test files
- docs/ - Documentation

## Development Commands
### Build
\```bash
npm run build
\```

### Test
\```bash
npm test
\```

## Architecture Overview
[Description of system architecture, key components, design patterns]

## Development Guidelines
[Project-specific conventions, coding standards, etc.]
```

**Application to BioMate:**

Create equivalent for workflow generation:

```markdown
# WORKFLOW_CONTEXT.md

## User Profile
- Research domain: Proteomics
- Preferred methods: DIA acquisition, label-free quantification
- Organism: Mouse
- Tissue types: Liver, brain
- Expertise level: Intermediate

## Tool Preferences (Learned)
- Database search: DIA-NN (not MaxQuant)
- Normalization: Median normalization
- Statistics: limma

## Recent Workflows
1. DIA-NN → Normalization → limma (Successful)
2. MaxQuant → Failed (Wrong tool for DIA data)

## Common Mistakes to Avoid
- Don't use MaxQuant for DIA data
- Always include normalization before statistics
- Check instrument type for mass tolerance

## Current Project Context
[Dataset information, experimental design, goals]
```

---

## Sub-Agent System Patterns

### What are Sub-Agents?

**Concept:** Specialized AI assistants with:
- **Domain expertise** (coding, data analysis, security, etc.)
- **Tool permissions** (what they can/cannot do)
- **Custom system prompts** (tailored instructions)
- **Specific focus** (narrower scope = better results)

### Sub-Agent Architecture

```
User Request
  ↓
Task Analysis (Main Agent)
  ↓
Domain Recognition
  ↓
Select Best Sub-Agent
  ↓
Grant Tool Permissions
  ↓
Sub-Agent Executes Task
  ↓
Return Results to User
```

### Built-in Sub-Agents (Examples)

| Agent Type | Domain | Tool Access | Use Cases |
|------------|--------|-------------|-----------|
| `code-reviewer` | Code quality & security | Read, Bash | Review PRs, find vulnerabilities |
| `frontend-developer` | UI/UX development | Read, Write, Bash | Create components, responsive design |
| `backend-developer` | API & database | Read, Write, Bash, DB | Design APIs, optimize queries |
| `data-scientist` | Data analysis | Read, Write, Bash, Python | Analyze datasets, create visualizations |
| `devops-engineer` | Deployment & ops | Read, Write, Bash, Docker | CI/CD, monitoring, infrastructure |

### Sub-Agent Configuration Format

**File:** `~/.iflow/agents/my-agent.md`

```markdown
---
name: Proteomics Workflow Expert
type: workflow-generator
description: Expert in proteomics workflow generation with focus on mass spec data
tools: [Read, Write, Bash]
mcp_servers: [tool-database, galaxy-api]
color: blue
---

# System Prompt

You are a proteomics workflow generation expert specializing in mass spectrometry data analysis using Galaxy tools.

## Your Expertise
- Mass spectrometry (DDA, DIA, targeted)
- Proteomics search engines (MaxQuant, DIA-NN, MSFragger, MSGF+)
- Quantification methods (label-free, TMT, iTRAQ, SILAC)
- Statistical analysis (limma, DEqMS, MSstats)
- Data formats (RAW, mzML, mzXML, MGF)

## Your Responsibilities
1. Understand user's data type and experimental design
2. Suggest appropriate tools based on scientific context
3. Validate tool compatibility and workflow logic
4. Prevent common mistakes (e.g., MaxQuant on DIA data)
5. Explain your reasoning clearly

## Tool Selection Rules

### DIA Data
- ✅ Use: DIA-NN, Spectronaut, OpenSWATH
- ❌ Avoid: MaxQuant (designed for DDA)

### DDA Data
- ✅ Use: MaxQuant, MSFragger, MSGF+, Mascot
- ❌ Avoid: DIA-NN (designed for DIA)

### TMT/iTRAQ Data
- Must include reporter ion quantification step
- Compatible with MaxQuant, MSFragger, Proteome Discoverer

## Workflow Validation Checks

Before suggesting a workflow, verify:
1. ✓ Tool matches data type (DDA/DIA)
2. ✓ Output formats compatible with next tool
3. ✓ No redundant steps (e.g., two search engines)
4. ✓ Proper ordering (conversion → search → quant → stats)
5. ✓ Parameters match instrument specifications

## Common Mistakes to Prevent

1. **Using wrong search engine for data type**
   - Example: MaxQuant on DIA data
   - Fix: Ask about data type first, then suggest appropriate tool

2. **Missing format conversion**
   - Example: RAW → DIA-NN without mzML conversion
   - Fix: Insert MSConvert step

3. **Skipping normalization**
   - Example: Going directly from quantification to statistics
   - Fix: Add median/quantile normalization step

4. **Incompatible tool chains**
   - Example: Tool A outputs .txt but Tool B needs .tsv
   - Fix: Find conversion tool or alternative

## Interaction Style

Always:
- Ask clarifying questions about data type and goals
- Explain why you're suggesting specific tools
- Validate each step before adding to workflow
- Warn about potential issues
- Provide alternatives when applicable

Example:
"I see you have DIA data. For DIA analysis, I recommend DIA-NN instead of MaxQuant because:
1. DIA-NN is specifically designed for DIA acquisition patterns
2. It has higher sensitivity for DIA data
3. MaxQuant is optimized for DDA and won't perform well on DIA

Would you like me to proceed with DIA-NN, or do you have a preference for another DIA-specific tool like Spectronaut or OpenSWATH?"
```

### Application to BioMate

Create specialized sub-agents for:

**1. Workflow Generation Agent**
```markdown
---
name: workflow-generator
type: proteomics-workflow
tools: [Read, Grep, Glob]
mcp_servers: [tool-database, workflow-validator]
---

Specialized in generating proteomics workflows with validation.
[Include tool selection rules, common mistakes, validation logic]
```

**2. Parameter Configuration Agent**
```markdown
---
name: parameter-configurator
type: tool-parameters
tools: [Read]
mcp_servers: [tool-database]
---

Expert in setting scientifically valid parameters for proteomics tools.
[Include instrument-specific defaults, validation rules]
```

**3. Workflow Validator Agent**
```markdown
---
name: workflow-validator
type: validation
tools: [Read]
mcp_servers: [tool-database, workflow-history]
---

Reviews workflows for errors before execution.
[Include validation rules, common error patterns]
```

---

## Workflow Composition

### Workflow Structure

**File:** `IFLOW.md` (project-level workflow definition)

```markdown
# Workflow Name

## Overview
[Description of what this workflow does]

## Components

### Agents
- agent1: Purpose and role
- agent2: Purpose and role

### Commands
- /command1: What it does
- /command2: What it does

### MCP Tools
- tool1: Functionality
- tool2: Functionality

## Workflow Steps

1. **Step 1:** Description
   - Agent: agent1
   - Tools: tool1, tool2
   - Output: What this produces

2. **Step 2:** Description
   - Agent: agent2
   - Tools: tool3
   - Input: Output from step 1
   - Output: Final result

## Usage

\```bash
/command-name [arguments]
\```

Or natural language:
\```
I want to [describe goal]
\```
```

### Workflow Execution Pattern

```
User Input
  ↓
Workflow Engine Parses Request
  ↓
Step Orchestration:
  Step 1: Call Agent A with Tool X → Output A
  Step 2: Call Agent B with Output A and Tool Y → Output B
  Step 3: Call Agent C with Output B → Final Result
  ↓
Result Aggregation
  ↓
Present to User
```

### Application to BioMate: Workflow Generation Workflow

```markdown
# Proteomics Workflow Generation

## Components

### Agents
- clarification-agent: Asks questions to understand user needs
- tool-selector-agent: Chooses appropriate tools
- parameter-agent: Configures tool parameters
- validator-agent: Checks workflow before execution

### Tools
- tool-database (MCP): Query available Galaxy tools
- workflow-validator (MCP): Validate tool chains
- parameter-suggester (MCP): Suggest parameter values

## Workflow Steps

### Step 1: Clarification
**Agent:** clarification-agent
**Goal:** Understand user's data and experimental design

Questions to ask:
1. What type of mass spec data? (DDA/DIA/Targeted)
2. What organism?
3. Analysis goal? (Identification/Quantification/PTMs)
4. What instrument?

**Output:** User context object
```json
{
  "data_type": "DIA",
  "organism": "mouse",
  "goal": "quantification",
  "instrument": "Orbitrap Exploris"
}
```

### Step 2: Tool Selection
**Agent:** tool-selector-agent
**Input:** User context from Step 1
**Tools:** tool-database MCP

Process:
1. Query tool database for compatible tools
2. Filter by data type compatibility
3. Check user preferences from history
4. Select optimal tool chain

**Output:** Tool sequence
```json
{
  "steps": [
    {"tool": "msconvert", "purpose": "Convert RAW to mzML"},
    {"tool": "dia_nn", "purpose": "Database search for DIA data"},
    {"tool": "median_normalization", "purpose": "Normalize intensities"},
    {"tool": "limma", "purpose": "Statistical analysis"}
  ]
}
```

### Step 3: Parameter Configuration
**Agent:** parameter-agent
**Input:** Tool sequence from Step 2, User context from Step 1
**Tools:** parameter-suggester MCP

For each tool:
1. Get parameter schema from tool database
2. Set defaults based on user context (instrument, etc.)
3. Ask user for confirmation/customization

**Output:** Configured workflow
```json
{
  "workflow": [
    {
      "tool": "dia_nn",
      "parameters": {
        "mass_accuracy_ms1": 10.0,  // Orbitrap default
        "mass_accuracy_ms2": 20.0,
        "fdr": 0.01
      }
    }
  ]
}
```

### Step 4: Validation
**Agent:** validator-agent
**Input:** Configured workflow from Step 3
**Tools:** workflow-validator MCP

Checks:
1. ✓ Tool chain compatibility (formats match)
2. ✓ No redundant steps
3. ✓ Scientific validity (DIA tools for DIA data)
4. ✓ Parameter ranges valid

**Output:** Validation report + executable workflow

## Usage

Natural language:
\```
I have DIA data from mouse liver samples acquired on Orbitrap Exploris.
I want to quantify proteins across 3 conditions with 4 replicates each.
\```

Or slash command:
\```bash
/generate-workflow
# Triggers interactive workflow generation process
\```
```

---

## Questioning Techniques

### Effective Questions (from iFlow Best Practices)

**❌ Poor Question:**
```
Code doesn't work, please fix it
```

**✅ Good Question:**
```
I encountered an issue while implementing user authentication. Here's my code:
[paste relevant code]

When running tests, I get the following error:
[paste complete error message]

I'm using Node.js + Express + JWT. I've tried:
1. Checking JWT secret configuration
2. Verifying token expiration settings

Please help me analyze the problem and provide solutions.
```

### Context Provision Checklist

When asking Claude for help, always provide:

1. ✅ **Relevant code snippets** (not entire files, just relevant parts)
2. ✅ **Complete error messages** (not just "it failed")
3. ✅ **Tech stack and environment** (versions, OS, etc.)
4. ✅ **Expected behavior vs actual behavior**
5. ✅ **Already attempted solutions** (what you've tried)

### Application to BioMate: Workflow Generation Questions

**Initial Query Pattern:**
```
User: "I want to analyze my proteomics data"
```

**Claude's Response Should Include:**

```
I'll help you create a proteomics workflow. First, let me understand your data:

📊 Data Type Questions:
1. What type of mass spectrometry data do you have?
   ○ DDA (Data-Dependent Acquisition) - traditional shotgun
   ○ DIA (Data-Independent Acquisition) - SWATH
   ○ Targeted (SRM/MRM/PRM)
   ○ I'm not sure

2. What's your analysis goal?
   ☐ Protein identification only
   ☐ Protein quantification (compare conditions)
   ☐ Post-translational modifications (phospho, acetyl, etc.)
   ☐ All of the above

3. What organism are your samples from?
   [Text input: ____________]

4. What mass spectrometer did you use?
   ○ Orbitrap (Thermo)
     └─ Which model? [Dropdown: Exploris, Fusion, Q Exactive]
   ○ QTOF (Waters/Agilent/Bruker)
   ○ Other

5. How many conditions and replicates?
   - Conditions: ___
   - Replicates per condition: ___
```

**Progressive Question Pattern:**

Don't ask all questions at once. Ask in stages:

**Stage 1: Critical Info (Always Ask)**
- Data type (DDA/DIA/Targeted)
- Organism
- Analysis goal

**Stage 2: Contextual (Ask Based on Stage 1 Answers)**
- If DDA: "Do you have isobaric labels (TMT/iTRAQ)?"
- If DIA: "Do you have a spectral library, or should we build one?"
- If quantification: "How many conditions and replicates?"

**Stage 3: Parameter Tuning (Ask When Configuring)**
- Instrument model (for mass tolerance)
- Specific modifications to search
- Statistical analysis preferences

---

## Development Workflow Patterns

### Pattern 1: Feature Development Workflow

**iFlow Pattern:**
```bash
# 1. Clear context
/clear

# 2. Initialize project understanding
/init

# 3. Describe feature
I need to implement [specific feature],
please help me analyze which files need modification

# 4. Create feature branch
!git checkout -b feature/new-feature

# 5. Develop based on suggestions
[Development work]

# 6. Test
!npm test

# 7. Code review
$code-reviewer Please review the changes

# 8. Commit
!git add . && git commit -m "Add new feature"
```

**Application to BioMate:**
```bash
# 1. Clear previous workflow context
[Clear button in UI / /clear command]

# 2. Initialize analysis context
User selects dataset + experimental design

# 3. Describe analysis goal
"I want to compare protein expression between conditions A, B, C"

# 4. Generate workflow draft
Claude generates 5-step workflow structure

# 5. Review step-by-step
For each step:
  - Show tool + purpose
  - Get user confirmation
  - Configure parameters

# 6. Validate workflow
Run validation checks

# 7. Present final workflow
Show complete workflow with all steps + parameters

# 8. Execute or save
User can execute immediately or save for later
```

### Pattern 2: Debugging Workflow

**iFlow Pattern:**
```bash
# 1. Reproduce issue
!npm test

# 2. Provide error context
Here's the error message: [paste complete error]

# 3. Get analysis
Please help me analyze the problem cause and provide solutions

# 4. Apply fix
[Implementation]

# 5. Verify
!npm test
```

**Application to BioMate:**
```bash
# 1. Workflow fails during execution
Step 3 (DIA-NN search) failed with error

# 2. Show error to Claude
"Step 3 failed: Tool 'dia_nn' expected input format 'mzML' but received 'raw'"

# 3. Claude analyzes
"The issue is that Step 2 (file upload) is outputting RAW files,
but DIA-NN requires mzML format. We need to add a conversion step."

# 4. Claude proposes fix
"I'll insert MSConvert between Steps 2 and 3 to convert RAW → mzML"

# 5. User approves fix
Workflow updated automatically

# 6. Re-execute
Workflow runs successfully
```

### Pattern 3: Code Review Workflow

**iFlow Pattern:**
```bash
# 1. Review after development
$code-reviewer Please review my just-completed user login functionality

# 2. For specific files
$code-reviewer Please focus on reviewing the security of src/auth.js

# 3. For specific commits
!git show HEAD
$code-reviewer Please review the changes in this commit
```

**Application to BioMate:**
```bash
# 1. After workflow generation
$workflow-validator Please review this DIA workflow for common mistakes

# 2. Before execution
$workflow-validator Check for:
  - Tool compatibility
  - Missing normalization
  - Wrong tool for data type

# 3. After user corrections
$workflow-validator Verify this updated workflow is scientifically valid
```

---

## Error Handling & Recovery

### Context Management Strategies

**Problem:** AI responses become inaccurate over time

**Solutions:**

1. **Clear when switching topics**
   ```bash
   /clear  # Remove irrelevant context
   ```

2. **Re-establish context periodically**
   ```bash
   /init   # Re-analyze project
   ```

3. **Compress long conversations**
   ```bash
   /compress  # Summarize history to save tokens
   ```

**Application to BioMate:**

```python
class WorkflowConversationManager:
    def __init__(self, user_id, session_id):
        self.max_messages = 20
        self.compression_threshold = 15

    def add_message(self, role, content):
        self.messages.append({"role": role, "content": content})

        # Auto-compress when approaching limit
        if len(self.messages) >= self.compression_threshold:
            self.compress_history()

    def compress_history(self):
        """Compress old messages into summary"""
        summary = self.generate_summary(self.messages[:-5])

        # Replace old messages with summary
        self.messages = [
            {"role": "system", "content": f"Previous conversation: {summary}"}
        ] + self.messages[-5:]  # Keep recent 5 messages

    def generate_summary(self, messages):
        """Use Claude to summarize conversation"""
        return f"""
        User is creating a DIA proteomics workflow.
        Key decisions made:
        - Data type: DIA
        - Organism: Mouse
        - Search engine: DIA-NN (user corrected from MaxQuant)
        - Current step: Configuring statistical analysis parameters
        """
```

### Checkpointing & Session Recovery

**iFlow Pattern:**
```bash
# Save important state
/chat save before-refactor

# Work on changes
[Development]

# If things go wrong
/chat restore before-refactor

# Or list checkpoints
/chat list
```

**Application to BioMate:**

```typescript
interface WorkflowCheckpoint {
  id: string;
  timestamp: Date;
  workflow: Workflow;
  conversation: Message[];
  user_feedback: string;
}

class WorkflowCheckpointer {
  async saveCheckpoint(name: string, workflow: Workflow) {
    const checkpoint: WorkflowCheckpoint = {
      id: generateId(),
      timestamp: new Date(),
      workflow: workflow,
      conversation: this.conversationHistory,
      user_feedback: ""
    };

    await db.saveCheckpoint(checkpoint);
    return checkpoint.id;
  }

  async restoreCheckpoint(checkpointId: string) {
    const checkpoint = await db.getCheckpoint(checkpointId);

    this.workflow = checkpoint.workflow;
    this.conversationHistory = checkpoint.conversation;

    return checkpoint;
  }

  // Auto-save at key points
  async autoSave() {
    // Save after each major step
    if (this.workflow.steps.length % 3 === 0) {
      await this.saveCheckpoint(`auto-${Date.now()}`, this.workflow);
    }
  }
}
```

---

## Application to BioMate Platform

### 1. Project Initialization Equivalent

**iFlow:** `/init` → analyzes codebase → creates IFLOW.md

**BioMate:** `/understand-data` → analyzes datasets → creates WORKFLOW_CONTEXT.md

**Implementation:**
```python
class DatasetAnalyzer:
    async def initialize_context(self, dataset_id):
        """
        Equivalent to iFlow's /init command
        Analyzes dataset and builds context for workflow generation
        """
        dataset = await self.fetch_dataset(dataset_id)

        # Analyze dataset metadata
        analysis = {
            "data_type": self.detect_data_type(dataset),  # DDA/DIA/Targeted
            "file_format": dataset.format,  # raw, mzML, etc.
            "organism": dataset.metadata.get("organism"),
            "instrument": self.infer_instrument(dataset),
            "num_samples": len(dataset.files),
            "acquisition_method": self.detect_acquisition_method(dataset)
        }

        # Create context document
        context_md = self.generate_context_markdown(analysis)

        # Save for Claude to reference
        await self.save_context(dataset_id, context_md)

        return analysis
```

### 2. Sub-Agent System

**Create specialized agents for workflow tasks:**

```python
# File: .biomate/agents/workflow-generator.md

WORKFLOW_GENERATOR_PROMPT = """
You are a proteomics workflow generation expert.

## Your Role
Generate scientifically valid Galaxy workflows for mass spectrometry data analysis.

## Critical Rules
1. ALWAYS ask about data type first (DDA/DIA/Targeted)
2. Match tools to data type:
   - DIA → DIA-NN, Spectronaut, OpenSWATH
   - DDA → MaxQuant, MSFragger, MSGF+
3. Validate each step before adding to workflow
4. Explain your reasoning

## Workflow Generation Process

### Step 1: Clarification
Ask user:
1. Data type?
2. Organism?
3. Analysis goal?
4. Instrument?

### Step 2: Draft Structure
Create high-level workflow:
Step 1: File conversion
Step 2: Database search
Step 3: Quantification
Step 4: Statistical analysis

Get user approval before detailing.

### Step 3: Configure Each Step
For each step:
1. Select appropriate tool
2. Explain why this tool
3. Set parameters
4. Validate compatibility

### Step 4: Final Validation
Check:
- Tool chain compatibility
- No redundant steps
- Scientific validity
- Parameter ranges

## Available Tools
{{tools_catalog}}

## User Context
{{user_context}}

## Conversation History
{{conversation_summary}}
"""
```

### 3. Workflow Composition Framework

**Directory Structure:**
```
.biomate/
├── agents/
│   ├── workflow-generator.md
│   ├── parameter-configurator.md
│   └── workflow-validator.md
├── commands/
│   ├── generate-workflow.md
│   └── validate-workflow.md
├── workflows/
│   ├── dia-standard.json
│   └── dda-tmt.json
└── CONTEXT.md
```

**Command Definition:**
```markdown
# File: .biomate/commands/generate-workflow.md

---
name: generate-workflow
description: Generate a proteomics workflow interactively
agents: [workflow-generator, parameter-configurator, workflow-validator]
---

# Generate Workflow Command

## Process

1. **Clarification Phase**
   Agent: workflow-generator
   Goal: Understand user needs

2. **Tool Selection Phase**
   Agent: workflow-generator
   Goal: Select appropriate tools

3. **Parameter Configuration Phase**
   Agent: parameter-configurator
   Goal: Set scientifically valid parameters

4. **Validation Phase**
   Agent: workflow-validator
   Goal: Check workflow before execution

## Usage

\```bash
/generate-workflow
\```

Or natural language:
\```
Create workflow for my DIA mouse proteomics data
\```
```

### 4. Context Management

**Implement conversation compression:**

```python
class WorkflowConversationManager:
    MAX_CONTEXT_TOKENS = 8000
    COMPRESSION_TRIGGER = 6000

    def should_compress(self):
        """Check if context needs compression"""
        estimated_tokens = self.estimate_tokens(self.messages)
        return estimated_tokens > self.COMPRESSION_TRIGGER

    async def compress_context(self):
        """Compress conversation history"""
        summary_prompt = f"""
        Summarize this workflow generation conversation into key decisions:

        {self.messages[:-5]}  # All but last 5 messages

        Extract:
        1. User's data type and experimental design
        2. Tool preferences (and corrections)
        3. Current workflow state
        4. Open questions or next steps

        Format as concise bullet points.
        """

        summary = await claude.generate(summary_prompt)

        # Replace old messages with summary
        self.messages = [
            {"role": "system", "content": f"Previous conversation summary:\n{summary}"}
        ] + self.messages[-5:]  # Keep recent messages
```

### 5. Progressive Disclosure UI

**Implement step-by-step workflow building:**

```typescript
// Workflow Builder Component

interface WorkflowBuilderState {
  phase: 'clarification' | 'draft' | 'configuration' | 'validation';
  workflow: Workflow;
  currentStep: number;
}

const WorkflowBuilder = () => {
  const [state, setState] = useState<WorkflowBuilderState>({
    phase: 'clarification',
    workflow: null,
    currentStep: 0
  });

  // Phase 1: Clarification
  if (state.phase === 'clarification') {
    return <QuestionnaireForm
      questions={clarificationQuestions}
      onComplete={answers => {
        setState({...state, phase: 'draft'});
        generateWorkflowDraft(answers);
      }}
    />;
  }

  // Phase 2: Draft Review
  if (state.phase === 'draft') {
    return <WorkflowDraftView
      workflow={state.workflow}
      onApprove={() => setState({...state, phase: 'configuration'})}
      onEdit={(step) => editStep(step)}
    />;
  }

  // Phase 3: Step-by-Step Configuration
  if (state.phase === 'configuration') {
    const currentStep = state.workflow.steps[state.currentStep];

    return <StepConfigurator
      step={currentStep}
      onConfirm={params => {
        updateStepParameters(state.currentStep, params);

        if (state.currentStep < state.workflow.steps.length - 1) {
          setState({...state, currentStep: state.currentStep + 1});
        } else {
          setState({...state, phase: 'validation'});
        }
      }}
    />;
  }

  // Phase 4: Validation
  if (state.phase === 'validation') {
    return <WorkflowValidationView
      workflow={state.workflow}
      validationResults={validationResults}
      onExecute={() => executeWorkflow(state.workflow)}
      onEdit={() => setState({...state, phase: 'configuration', currentStep: 0})}
    />;
  }
};
```

### 6. Learning from Corrections

**Implement feedback loop:**

```python
class WorkflowLearningSystem:
    def record_correction(self, workflow_id, correction):
        """
        When user corrects Claude's suggestion, learn from it
        """
        correction_record = {
            "timestamp": datetime.now(),
            "workflow_id": workflow_id,
            "original_suggestion": correction["original"],
            "user_correction": correction["corrected"],
            "context": self.get_workflow_context(workflow_id),
            "reason": correction.get("reason", "")
        }

        # Store correction
        self.db.save_correction(correction_record)

        # Extract learning rule
        rule = self.extract_rule(correction_record)
        if rule:
            self.db.save_rule(rule)

    def extract_rule(self, correction):
        """
        Extract reusable rule from correction

        Example:
        User corrected MaxQuant → DIA-NN for DIA data

        Rule: IF data_type == "DIA" AND task == "database_search"
              THEN avoid MaxQuant, prefer DIA-NN
        """
        if "maxquant" in correction["original"].lower() and \
           "dia" in correction["context"]["data_type"].lower():
            return {
                "rule_type": "tool_substitution",
                "condition": {
                    "data_type": "DIA",
                    "task": "database_search"
                },
                "avoid": ["maxquant"],
                "prefer": ["dia_nn", "spectronaut"],
                "reason": "MaxQuant is designed for DDA, not DIA data",
                "confidence": 0.95
            }

        return None
```

---

## Key Takeaways for BioMate

### 1. Progressive Context Building
**Don't expect one-shot perfection.** Build context progressively:
- Start with clarification questions
- Draft high-level workflow
- Detail step-by-step
- Validate before execution

### 2. Specialized Agents
**One agent can't do everything well.** Create domain-specific agents:
- Workflow generator
- Parameter configurator
- Workflow validator
- Data analyzer

### 3. Memory Management
**Long conversations lose context.** Implement:
- Auto-compression when context grows
- Checkpointing at key milestones
- Session recovery

### 4. Learning System
**Mistakes are learning opportunities.** When users correct Claude:
- Record the correction
- Extract reusable rules
- Apply rules to future workflows

### 5. Progressive Disclosure UI
**Don't overwhelm users.** Show:
- Questions first (clarification)
- Draft next (high-level)
- Details incrementally (step-by-step)
- Validation last (before execution)

### 6. Tool Permissions
**Control what agents can access:**
- Workflow generator: Read tool database, no execution
- Validator: Read only, no modifications
- Parameter configurator: Read tool schemas, no workflow changes

---

## Next Steps

### Week 1: Foundation
1. Create `WORKFLOW_CONTEXT.md` pattern equivalent to `IFLOW.md`
2. Implement `/understand-data` command
3. Build conversation compression system

### Week 2: Sub-Agents
1. Create workflow-generator agent
2. Create parameter-configurator agent
3. Create workflow-validator agent

### Week 3: Workflow System
1. Implement progressive workflow building UI
2. Add checkpointing and session recovery
3. Build learning system for corrections

### Week 4: Integration
1. Connect agents to tool database
2. Implement validation framework
3. Test end-to-end workflow generation

---

## Conclusion

iFlow CLI's success comes from:
1. ✅ Building context before attempting generation
2. ✅ Specialized agents for specific tasks
3. ✅ Progressive disclosure of complexity
4. ✅ Memory management and compression
5. ✅ Learning from mistakes

**For BioMate:** Apply these patterns to workflow generation, replacing code development with scientific workflow creation. The principles are the same - build context, specialize agents, validate progressively, and learn continuously.
