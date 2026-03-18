# Phase B: Autonomous LLM-Driven iFlow Features
**Created**: 2025-11-03 13:15:32
**Purpose**: Use iFlow's powerful features transparently - LLM takes initiative, not user

---

## 🎯 The Vision

**NOT this (manual commands):**
```bash
User types: /workflow dia-proteomics @data/experiment.mzML
User types: $tool-selector "What tools for DIA?"
User types: /validate
```

**YES this (autonomous intelligence):**
```
User: "I want to analyze my proteomics data for differential expression"

[Behind the scenes - LLM autonomously:]
1. Detects files in workspace: experiment.mzML
2. Analyzes file metadata → Identifies as DIA data
3. Invokes tool-selector agent internally
4. Composes workflow automatically
5. Validates tool compatibility
6. Presents ready-to-run workflow

User sees: "I've prepared a DIA proteomics workflow with MSstats. Ready to run?"
```

**User never types commands - LLM does everything!**

---

## 🧠 Core Concept: LLM as Power User

**Traditional iFlow**: Human expert types commands
**BioMate**: LLM is the expert, uses commands on behalf of user

```
User Input (Natural Language)
    ↓
┌─────────────────────────────────────┐
│   LLM Decision Engine                │
│   - Parse user intent                │
│   - Detect available files           │
│   - Decide which agents to invoke    │
│   - Compose workflow steps           │
│   - Validate compatibility           │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│   Autonomous Feature Usage           │
│   [File Detection] → @data/file.mzML │
│   [Agent Invocation] → $tool-selector│
│   [Workflow Composition] → Steps 1-5 │
│   [Validation] → Check compatibility │
└─────────────────────────────────────┘
    ↓
User Output (Simple Results)
```

---

## 🔧 Three Autonomous Features

### 1. **Autonomous File Detection & Reference**

**iFlow Manual:**
```bash
User: @data/experiment.mzML @data/library.tsv
```

**BioMate Autonomous:**
```python
# LLM System Prompt:
"""
When user mentions data/files:
1. Check user's workspace for relevant files
2. Automatically reference files in context
3. Extract metadata from files
4. Use metadata to inform tool selection
"""

# Example:
User: "Analyze my proteomics data"

LLM thinks:
- Scans workspace: /user/data/experiment.mzML exists
- Reads metadata: CV param MS:1003114 → DIA data
- Auto-references: @/user/data/experiment.mzML
- Uses metadata: "DIA data detected, selecting DIA-compatible tools"

User sees: "Found DIA proteomics data (experiment.mzML). Analyzing..."
```

**Implementation:**
```typescript
// System automatically scans workspace
const workspaceFiles = await scanUserWorkspace(userId);
// Returns: [
//   {path: "/user/data/experiment.mzML", type: "mzML", metadata: {...}},
//   {path: "/user/data/library.tsv", type: "spectral_library"}
// ]

// LLM context includes:
const systemContext = `
Available files in workspace:
- experiment.mzML (DIA mass spec data, 2.3 GB)
- library.tsv (spectral library, 45 MB)

When user requests analysis, automatically use these files.
`;

// LLM decides:
// "User wants proteomics analysis, I should use experiment.mzML"
// Internally uses: @/user/data/experiment.mzML
```

---

### 2. **Autonomous Agent Invocation**

**iFlow Manual:**
```bash
User: $tool-selector "What tools for DIA differential expression?"
User: $parameter-expert "Configure DIA-NN parameters"
```

**BioMate Autonomous:**
```python
# LLM System Prompt:
"""
You have access to specialized agents. Invoke them autonomously when appropriate:

Agents available:
- tool-selector: Select appropriate tools for user's data type and task
- parameter-expert: Configure tool parameters based on experimental design
- workflow-validator: Check tool compatibility and data format matching
- results-interpreter: Explain analysis results to user

Invoke agents WITHOUT asking user permission. Present results naturally.
"""

# Example:
User: "I need to find differentially expressed proteins"

LLM thinks:
- Task: differential expression
- Data type: DIA (from file metadata)
- Required: Tool selection + parameter configuration

LLM autonomously invokes:
1. $tool-selector(task="differential_expression", data_type="DIA")
   → Returns: [MSstats, DEqMS, DIA-NN]

2. $parameter-expert(tool="MSstats", data_type="DIA", samples=6)
   → Returns: {FDR: 0.01, normalization: "quantile", ...}

3. $workflow-validator(tools=[MSstats], data=experiment.mzML)
   → Returns: {compatible: true, warnings: []}

User sees: "I recommend MSstats for your DIA differential expression analysis.
            Configured with FDR=0.01 for 6 samples. Ready to run?"
```

**Implementation:**
```typescript
// Agent registry
const agents = {
  'tool-selector': new ToolSelectorAgent(),
  'parameter-expert': new ParameterExpertAgent(),
  'workflow-validator': new WorkflowValidatorAgent()
};

// LLM prompt includes agent descriptions
const systemPrompt = `
You can invoke these agents by using their function:

tool_selector({task, data_type, user_history}) → Returns recommended tools
parameter_expert({tool, data_type, samples}) → Returns configured parameters
workflow_validator({tools, data}) → Returns validation results

Example:
User: "analyze my data"
You think: Need to select tools, so invoke:
  const tools = tool_selector({task: "differential_expression", data_type: "DIA"})
Then present to user naturally.
`;

// LLM has function calling capability
// When LLM decides to invoke agent, it calls:
const tools = await llm.callFunction('tool_selector', {
  task: 'differential_expression',
  data_type: 'DIA',
  user_history: userPatterns
});
```

---

### 3. **Autonomous Workflow Composition**

**iFlow Manual:**
```markdown
## Workflow Steps (user writes this)
1. Use tool-selector
2. Configure parameters
3. Run validation
4. Execute workflow
```

**BioMate Autonomous:**
```python
# LLM System Prompt:
"""
When user requests analysis, autonomously compose complete workflows:

Standard workflow pattern:
1. Detect data type from files
2. Select appropriate tools (invoke tool-selector agent)
3. Configure parameters (invoke parameter-expert agent)
4. Validate compatibility (invoke workflow-validator agent)
5. Present workflow to user for approval
6. Execute upon confirmation

Do this automatically - don't ask user to manage steps.
"""

# Example:
User: "Run differential expression analysis"

LLM autonomously composes:

Step 1: File Detection
- Scans workspace → finds experiment.mzML
- Extracts metadata → DIA data, 6 samples, 3 replicates

Step 2: Tool Selection
- Invokes: $tool-selector(task="diff_expr", data_type="DIA")
- Result: MSstats (score: 0.92), DEqMS (score: 0.85)
- Decision: Use MSstats (highest score + user preference pattern)

Step 3: Parameter Configuration
- Invokes: $parameter-expert(tool="MSstats", samples=6, replicates=3)
- Result: {FDR: 0.01, normalization: "quantile", min_peptides: 2}

Step 4: Validation
- Invokes: $workflow-validator(
    input: experiment.mzML,
    tool: MSstats,
    params: {...}
  )
- Result: {compatible: true, estimated_time: "15 min"}

Step 5: Present to User
"I've prepared a workflow:
 1. DIA data detected (experiment.mzML, 6 samples)
 2. MSstats selected for differential expression
 3. Configured: FDR=0.01, min 2 peptides per protein
 4. Estimated time: 15 minutes

 Start workflow? [Yes] [Modify parameters] [Choose different tool]"

User sees: Complete, ready workflow without managing any steps!
```

---

## 📐 System Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    User Interface (GUI/Chat)                │
│  User input: "Analyze my proteomics data"                  │
│  No commands, no syntax, pure natural language             │
└────────────────────────────────────────────────────────────┘
                            ↓
┌────────────────────────────────────────────────────────────┐
│              LLM Decision Engine (Autonomous)               │
│                                                             │
│  System Prompt:                                            │
│  - You have access to workspace files                      │
│  - You can invoke specialized agents                       │
│  - You compose workflows automatically                     │
│  - You present results simply to user                      │
│                                                             │
│  Functions Available:                                      │
│  - scan_workspace() → List files                           │
│  - extract_metadata(file) → Get file details              │
│  - tool_selector(...) → Invoke agent                       │
│  - parameter_expert(...) → Invoke agent                    │
│  - workflow_validator(...) → Invoke agent                  │
│  - compose_workflow(...) → Build pipeline                  │
└────────────────────────────────────────────────────────────┘
                            ↓
┌────────────────────────────────────────────────────────────┐
│                    Backend Services                         │
│                                                             │
│  [File Manager] ← LLM calls scan_workspace()               │
│  [Agent Registry] ← LLM invokes agents                     │
│  [Workflow Composer] ← LLM builds pipelines                │
│  [Enhanced Search] ← Agents use for tool selection         │
│  [Behavioral Profile] ← Informs LLM decisions              │
└────────────────────────────────────────────────────────────┘
                            ↓
┌────────────────────────────────────────────────────────────┐
│                    Execution Layer                          │
│  - Galaxy API integration                                  │
│  - Workflow execution                                      │
│  - Result collection                                       │
│  - Feedback to behavioral learning                         │
└────────────────────────────────────────────────────────────┘
```

---

## 🎬 Complete Example: User Journey

### User Action 1: Upload File

```
User: [Uploads experiment.mzML via drag-drop]

LLM (autonomous):
1. Detects file upload event
2. Scans file metadata
3. Identifies: DIA-LCMS data, Orbitrap, 6 samples
4. Checks user patterns: 95% proteomics work
5. Prepares context for next interaction

User sees: "File uploaded: experiment.mzML (DIA proteomics data, 6 samples)"
```

### User Action 2: Request Analysis

```
User: "I want to find proteins that are differentially expressed"

LLM (autonomous decision-making):

[Step 1: Understand Request]
- Intent: Differential expression analysis
- Data: experiment.mzML (already uploaded)
- User expertise: Intermediate (from behavioral patterns)

[Step 2: Invoke Tool Selection Agent]
LLM calls: tool_selector({
  task: "differential_expression",
  data_type: "DIA",
  user_context: {
    domain: "proteomics",
    expertise: "intermediate",
    preferences: {preferred_tools: ["MSstats"]}
  }
})

Agent returns: {
  recommended: [
    {tool: "MSstats", score: 0.92, reason: "Best for DIA differential expression"},
    {tool: "DEqMS", score: 0.85, reason: "Alternative with robust statistics"}
  ]
}

[Step 3: Invoke Parameter Configuration Agent]
LLM calls: parameter_expert({
  tool: "MSstats",
  data_type: "DIA",
  sample_count: 6,
  replicate_count: 3,
  user_expertise: "intermediate"
})

Agent returns: {
  parameters: {
    FDR: 0.01,
    normalization: "quantile",
    min_peptides_per_protein: 2,
    remove_interfered_peptides: true
  },
  explanation: "Standard settings for high-confidence results"
}

[Step 4: Compose Workflow]
LLM calls: compose_workflow({
  input_file: "experiment.mzML",
  tool: "MSstats",
  parameters: {...},
  task: "differential_expression"
})

Returns: {
  workflow_id: "wf-20251103-001",
  steps: [
    {name: "DIA-NN Processing", tool: "DIA-NN", estimated_time: "10 min"},
    {name: "Statistical Analysis", tool: "MSstats", estimated_time: "5 min"}
  ],
  total_estimated_time: "15 min"
}

[Step 5: Validate]
LLM calls: workflow_validator({
  workflow_id: "wf-20251103-001",
  input_data: "experiment.mzML"
})

Returns: {
  compatible: true,
  warnings: [],
  ready_to_execute: true
}

User sees:
"I've prepared your differential expression workflow:

📊 Analysis Plan:
- Input: experiment.mzML (DIA data, 6 samples)
- Tool: MSstats (recommended for DIA differential expression)
- Settings: FDR=0.01, min 2 peptides per protein
- Estimated time: 15 minutes

🔧 Workflow Steps:
1. DIA-NN: Process raw data (~10 min)
2. MSstats: Statistical analysis (~5 min)

Ready to start? [▶️ Run Workflow] [⚙️ Modify Settings] [🔄 Try Different Tool]"
```

### User Action 3: Modify Settings (Optional)

```
User: "Can you make it more sensitive? I want to find subtle changes"

LLM (autonomous adjustment):

[Understand: User wants higher sensitivity]
LLM calls: parameter_expert({
  tool: "MSstats",
  adjustment: "increase_sensitivity",
  current_params: {FDR: 0.01, ...}
})

Agent returns: {
  updated_parameters: {
    FDR: 0.05,  // More lenient threshold
    normalization: "quantile",
    min_peptides_per_protein: 1,  // Allow single-peptide proteins
    remove_interfered_peptides: false  // Keep more data
  },
  trade_off: "Higher sensitivity but more potential false positives"
}

User sees:
"Adjusted for higher sensitivity:
- FDR: 0.05 (was 0.01) → More proteins detected
- Min peptides: 1 (was 2) → Include single-peptide proteins
- Keep all peptides → Maximize data

⚠️ Trade-off: May include more false positives

Proceed with these settings? [Yes] [No, keep original]"
```

---

## 💻 Implementation Strategy

### 1. **LLM System Prompt Template**

```typescript
const AUTONOMOUS_BIOMATE_SYSTEM_PROMPT = `
You are BioMate AI, an autonomous proteomics workflow assistant.

CAPABILITIES:
You can autonomously:
1. Detect and analyze files in user's workspace
2. Invoke specialized agents for tool selection and configuration
3. Compose complete workflows without user managing steps
4. Validate compatibility and estimate execution time
5. Learn from user behavior to improve suggestions

WORKSPACE ACCESS:
Current workspace files: {{workspace_files}}
Recent user activity: {{user_patterns}}

AVAILABLE AGENTS (invoke autonomously when needed):
- tool_selector(task, data_type, user_context) → Recommends tools
- parameter_expert(tool, data_type, samples, expertise) → Configures parameters
- workflow_validator(workflow, data) → Validates compatibility
- results_interpreter(results, task) → Explains results

BEHAVIORAL CONTEXT:
User's typical domain: {{primary_domain}} (confidence: {{domain_confidence}})
Preferred tools: {{preferred_tools}}
Inferred expertise: {{expertise_level}}

GUIDELINES:
1. When user uploads file → Automatically analyze metadata
2. When user requests analysis → Autonomously:
   a. Select appropriate tools (invoke tool_selector)
   b. Configure parameters (invoke parameter_expert)
   c. Compose workflow steps
   d. Validate compatibility
   e. Present complete workflow
3. Never ask user to manage technical details
4. Present options clearly with trade-offs
5. Always allow user to modify/override

RESPONSE FORMAT:
- Simple, natural language
- Show what you decided and why
- Provide [Action Buttons] for user choices
- Explain technical concepts simply

Example:
User: "Analyze my data"
You: [Autonomous actions: scan workspace → detect DIA data → invoke tool_selector → invoke parameter_expert → compose workflow]
Present: "I've prepared a DIA proteomics workflow with MSstats (15 min). [Run] [Modify] [Details]"
`;
```

### 2. **Function Calling Interface**

```typescript
// LLM has access to these functions
const LLM_FUNCTIONS = [
  {
    name: "scan_workspace",
    description: "Scan user's workspace for files and data",
    parameters: {
      user_id: "string"
    }
  },
  {
    name: "extract_file_metadata",
    description: "Extract metadata from uploaded file",
    parameters: {
      file_path: "string"
    }
  },
  {
    name: "invoke_tool_selector",
    description: "Invoke tool selection agent",
    parameters: {
      task: "string",
      data_type: "string",
      user_context: "object"
    }
  },
  {
    name: "invoke_parameter_expert",
    description: "Invoke parameter configuration agent",
    parameters: {
      tool: "string",
      data_type: "string",
      samples: "number",
      expertise_level: "string"
    }
  },
  {
    name: "compose_workflow",
    description: "Compose complete workflow from selected tools",
    parameters: {
      tools: "array",
      parameters: "object",
      input_data: "string"
    }
  },
  {
    name: "validate_workflow",
    description: "Validate workflow compatibility",
    parameters: {
      workflow_id: "string"
    }
  }
];

// LLM autonomously calls these as needed
```

### 3. **Agent Implementation**

```typescript
// Tool Selector Agent (invoked by LLM)
class ToolSelectorAgent {
  async select(params: {
    task: string;
    data_type: string;
    user_context: UserContext;
  }): Promise<ToolRecommendation[]> {

    // Use enhanced search with user context
    const results = await enhancedSearch.search_with_context(
      query: params.task,
      user_context: {
        research_domain: params.user_context.domain,
        data_type: params.data_type,
        expertise_level: params.user_context.expertise
      }
    );

    // Use behavioral patterns to boost preferred tools
    const rankedResults = this.applyUserPreferences(
      results,
      params.user_context.preferred_tools
    );

    return rankedResults.slice(0, 3).map(tool => ({
      tool_id: tool.tool_id,
      name: tool.name,
      score: tool.combined_score,
      reason: tool.relevance_explanation,
      nfcore_validated: tool.had_nfcore_badge
    }));
  }
}

// Parameter Expert Agent (invoked by LLM)
class ParameterExpertAgent {
  async configure(params: {
    tool: string;
    data_type: string;
    samples: number;
    expertise_level: string;
  }): Promise<ParameterConfig> {

    // Get parameter schema for tool
    const schema = await this.getToolParameterSchema(params.tool);

    // Apply scientific context from database
    const scientificGuidance = await this.getScientificGuidance(
      params.tool,
      params.data_type
    );

    // Configure based on expertise level
    if (params.expertise_level === 'beginner') {
      return this.getSimpleConfiguration(schema, scientificGuidance);
    } else {
      return this.getAdvancedConfiguration(schema, scientificGuidance, params);
    }
  }
}
```

---

## 🎯 Benefits of This Approach

### ✅ User Experience
- **Natural interaction**: Chat/GUI, no commands to learn
- **Autonomous intelligence**: LLM handles complexity
- **Smart defaults**: Uses behavioral patterns automatically
- **Always explainable**: LLM explains what it decided and why

### ✅ Technical Power
- **iFlow's features**: File detection, agents, workflow composition
- **Used transparently**: LLM uses them, user doesn't manage them
- **Extensible**: Add new agents, LLM learns to use them

### ✅ Learning System
- **Behavioral adaptation**: LLM decisions informed by user patterns
- **Continuous improvement**: ACE learns what works
- **Context-aware**: LLM has full context of workspace, history, preferences

---

## 📋 Implementation Plan

### Week 1: Foundation
1. Create file workspace scanning API
2. Build LLM function calling interface
3. Implement specialized agents (tool-selector, parameter-expert)

### Week 2: Integration
1. Design LLM system prompts with agent access
2. Implement autonomous workflow composition
3. Connect to enhanced search and behavioral profiles

### Week 3: Testing
1. Test LLM autonomous decision-making
2. Validate agent invocation logic
3. User testing with real proteomics scenarios

### Week 4: ACE Integration
1. Feed LLM decisions into ACE learning
2. Update behavioral patterns from successes/failures
3. Continuous improvement loop

---

## ✅ Summary

**Phase B is NOT about user typing commands.**

**Phase B IS about:**
- LLM autonomously uses iFlow's powerful features
- User interacts naturally through chat/GUI
- System intelligently manages all technical complexity
- iFlow features work invisibly in the background

**Result:** User gets power of iFlow without complexity of commands!

Would you like me to implement this autonomous LLM-driven system?
