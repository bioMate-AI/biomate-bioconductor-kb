# iFlow Agent Task Management Architecture - Lessons for BioMate

**Date**: 2026-01-13
**Purpose**: Deep analysis of how iFlow creates, executes, and manages agent tasks - architectural patterns to adopt

---

## Executive Summary

This document focuses on the **how** of iFlow's agent task management, not just feature comparison. The key learnings are:

1. **Agent Communication Protocol (ACP)** - Standardized message types for agent orchestration
2. **Hierarchical Agent Specialization** - Domain experts with tool permission inheritance
3. **Task Lifecycle Management** - Creation → Execution → Plan → Finish with state tracking
4. **Workflow Composition** - Agents + Commands + Context as composable units

---

## Part 1: Agent Task Creation Architecture

### 1.1 iFlow's Task Analysis Pipeline

```
User Request → Task Analysis → Agent Matching → Tool Authorization → Task Execution
      ↓              ↓              ↓                  ↓                  ↓
[Description] → [Domain        → [Best Agent]  → [Tool Set      → [Professional
                Recognition]                     Selection]        Processing]
```

**Key Insight**: iFlow separates **what agent to use** from **what tools that agent can use**. This is different from BioMate's current approach where tools are selected first, then routed.

### 1.2 Agent Configuration Structure

```markdown
---
agentType: "domain-expert"           # Unique identifier
systemPrompt: "You are an expert..." # Domain specialization
whenToUse: "Use when handling..."    # Selection criteria
model: "claude-3-5-sonnet"           # Preferred model
allowedTools: ["Read", "Write"]      # Tool whitelist
allowedMcps: ["filesystem", "git"]   # MCP access control
isInheritTools: true                 # Permission inheritance
isInheritMcps: true                  # MCP inheritance
proactive: false                     # Auto-trigger behavior
---
```

**Key Insight**: Agents are defined with **explicit boundaries** (tools, MCPs) and **inheritance rules**. This enables:
- Security isolation (agents can't exceed their permissions)
- Specialization (each agent optimized for its domain)
- Composability (agents can delegate to sub-agents)

### 1.3 BioMate Current Architecture vs iFlow

| Aspect | BioMate Current | iFlow Pattern | Gap |
|--------|-----------------|---------------|-----|
| Task Analysis | Intent parsing in `ai_assistant.py` | Explicit agent matching | BioMate lacks agent specialization |
| Tool Selection | Tool search (2,177 tools) → ranking | Agent defines allowed tools | BioMate tools are global, not scoped |
| Permission | Galaxy API key controls all | Per-agent tool permissions | BioMate lacks fine-grained control |
| Specialization | LTM preferences per user | Agent types per domain | BioMate learns per-user, not per-domain |

---

## Part 2: Agent Task Execution Architecture

### 2.1 iFlow's Agent Communication Protocol (ACP)

iFlow defines a **standardized message protocol** for agent communication:

```python
# Message Types in ACP
AssistantMessage    # AI text response chunks
ToolCallMessage     # Tool execution requests/status
PlanMessage         # Structured task plans
TaskFinishMessage   # Task completion signals
```

Each message includes **AgentInfo**:
```python
class AgentInfo:
    agent_id: str           # Full agent identifier
    task_id: Optional[str]  # Task/instance ID
    agent_index: Optional[int]  # Agent index in task
    timestamp: Optional[int]    # Creation timestamp
```

**Key Insight**: Every message is tagged with **who sent it** (agent_id), **what task** (task_id), and **when** (timestamp). This enables:
- Multi-agent tracing
- Task state reconstruction
- Audit trail by agent

### 2.2 Task Lifecycle States

```
┌─────────┐     ┌─────────────┐     ┌──────────┐     ┌────────────┐
│ Created │ ──▶ │ In Progress │ ──▶ │ Planning │ ──▶ │ Executing  │
└─────────┘     └─────────────┘     └──────────┘     └────────────┘
                                          │                │
                                          ▼                ▼
                                    ┌──────────┐     ┌────────────┐
                                    │ Waiting  │     │ Completed  │
                                    │ for User │     │ (END_TURN) │
                                    └──────────┘     └────────────┘
                                          │
                                          ▼
                                    ┌──────────────┐
                                    │ Terminated   │
                                    │ (MAX_TOKENS) │
                                    └──────────────┘
```

**Stop Reasons**:
- `END_TURN` - Task completed successfully
- `MAX_TOKENS` - Token limit reached, task incomplete
- User interruption (suspend/resume)

### 2.3 Tool Call Status Flow

```
┌──────────┐     ┌──────────┐     ┌───────────┐     ┌───────────┐
│ Pending  │ ──▶ │ Running  │ ──▶ │ Completed │ or  │ Failed    │
└──────────┘     └──────────┘     └───────────┘     └───────────┘
                      │
                      ▼
               ┌──────────────┐
               │ Requires     │
               │ Permission   │
               └──────────────┘
```

**Key Insight**: Tool calls have explicit **permission gates** before execution. BioMate should add this for sensitive bioinformatics operations.

---

## Part 3: Agent Task Management (Orchestration)

### 3.1 Hierarchical Agent Delegation

iFlow supports **sub-agent** spawning with controlled scope:

```
Main Agent (Full permissions)
    │
    ├── SubAgent A (code-reviewer)
    │   └── Tools: [Read, Grep]  ← Reduced scope
    │
    ├── SubAgent B (doc-writer)
    │   └── Tools: [Read, Write]  ← Different scope
    │
    └── SubAgent C (data-scientist)
        └── Tools: [Read, Bash]  ← Analysis scope
```

**Permission Inheritance**:
```yaml
isInheritTools: true   # Inherit parent's tool permissions
isInheritMcps: false   # Don't inherit parent's MCP access
allowedTools: ["Read"] # Explicit whitelist
```

**Key Insight**: Sub-agents can be **more restricted** than parent, never more permissive. This is a security pattern BioMate should adopt.

### 3.2 Plan/Todo Integration

iFlow's `PlanMessage` is similar to BioMate's `TodoWrite` but integrated into the agent protocol:

```python
class PlanMessage:
    entries: List[PlanEntry]

class PlanEntry:
    content: str        # Task description
    priority: str       # Priority level
    status: str         # pending/completed/in_progress
```

**Key Insight**: Plans are **first-class messages** in the protocol, not a separate tool. This enables:
- Agents to communicate plans to each other
- External systems to track agent planning
- Audit trail of agent decisions

### 3.3 Workflow Composition Pattern

iFlow composes complex workflows from:

```
Workflow = Agents + Commands + IFLOW.md + MCP Tools
```

**Directory Structure**:
```
.iflow/
├── agents/           # Domain specialist definitions
│   ├── reviewer.md
│   └── developer.md
├── commands/         # Reusable command scripts
│   └── deploy.md
├── IFLOW.md          # Context documentation
└── settings.json     # MCP configuration
```

**Key Insight**: Workflows are **packages** that can be shared, installed, and versioned. This is a marketplace-ready pattern.

---

## Part 4: Architectural Recommendations for BioMate

### 4.1 Agent Communication Protocol for BioMate

**Current BioMate**: Ad-hoc message passing, no standardized protocol

**Proposed**: Implement Biomate Communication Protocol (BCP)

```typescript
// backend/lib/galaxy/ai/protocol/bcp.ts

type BCPMessageType =
  | 'assistant'      // AI text response
  | 'tool_call'      // Tool execution
  | 'workflow_plan'  // Workflow planning
  | 'task_finish'    // Task completion
  | 'learning'       // LTM update event

interface BCPMessage {
  type: BCPMessageType;
  agentInfo: {
    agentId: string;      // e.g., "workflow-generator-1736755200000"
    taskId?: string;      // e.g., "rna-seq-analysis-001"
    stepIndex?: number;   // e.g., 3 (for multi-step workflows)
    timestamp: number;
  };
  payload: any;
}

interface TaskFinishPayload {
  stopReason: 'end_turn' | 'max_tokens' | 'user_interrupt' | 'error';
  result?: any;
  error?: string;
}
```

**Benefits**:
- Standardized message format for all agent communication
- Full audit trail with agent attribution
- Multi-agent coordination support

### 4.2 Agent Specialization for Bioinformatics

**Current BioMate**: Single hybrid intelligence pipeline

**Proposed**: Domain-specialized agents with tool boundaries

```typescript
// backend/lib/galaxy/ai/agents/agent_registry.ts

interface BiomateAgent {
  agentType: string;
  domain: string;           // e.g., "genomics", "proteomics", "imaging"
  systemPrompt: string;
  allowedToolCategories: string[];  // e.g., ["genomics/*", "database/*"]
  preferredTools: string[];         // Tools this agent excels at
  model?: string;
  inheritToolsFromParent: boolean;
}

const BIOMATE_AGENTS: BiomateAgent[] = [
  {
    agentType: "genomics-analyst",
    domain: "genomics",
    systemPrompt: "You are a genomics analysis expert...",
    allowedToolCategories: ["genomics/*", "database/ensembl", "database/ucsc"],
    preferredTools: ["annotate_celltype_scRNA", "gene_set_enrichment_analysis"],
    inheritToolsFromParent: true
  },
  {
    agentType: "proteomics-analyst",
    domain: "proteomics",
    systemPrompt: "You are a proteomics analysis expert...",
    allowedToolCategories: ["pharmacology/*", "database/uniprot", "database/pdb"],
    preferredTools: ["docking_autodock_vina", "predict_binding_affinity"],
    inheritToolsFromParent: true
  },
  {
    agentType: "imaging-analyst",
    domain: "bioimaging",
    systemPrompt: "You are a biological imaging expert...",
    allowedToolCategories: ["bioimaging/*", "cell_biology/*"],
    preferredTools: ["segment_with_nn_unet", "register_images"],
    inheritToolsFromParent: true
  }
];
```

**Selection Logic**:
```typescript
// backend/lib/galaxy/ai/agents/agent_selector.ts

async function selectAgent(userRequest: string): Promise<BiomateAgent> {
  // 1. Analyze request domain
  const domain = await analyzeDomain(userRequest);

  // 2. Find matching agent
  const agent = BIOMATE_AGENTS.find(a => a.domain === domain);

  // 3. Fall back to general agent if no match
  return agent || GENERAL_PURPOSE_AGENT;
}
```

### 4.3 Tool Permission Scoping

**Current BioMate**: All tools accessible to all operations

**Proposed**: Tool scoping by agent and user role

```typescript
// backend/lib/galaxy/ai/permissions/tool_permissions.ts

interface ToolPermission {
  toolId: string;
  allowedAgents: string[];      // Which agents can use this
  requiredUserRole?: string;    // Minimum user role required
  requiresConfirmation: boolean; // Ask user before executing
  auditLevel: 'basic' | 'detailed' | 'full';
}

const TOOL_PERMISSIONS: ToolPermission[] = [
  {
    toolId: "delete_dataset",
    allowedAgents: ["admin-agent"],
    requiredUserRole: "admin",
    requiresConfirmation: true,
    auditLevel: "full"
  },
  {
    toolId: "run_diffdock_with_smiles",
    allowedAgents: ["proteomics-analyst", "pharmacology-analyst"],
    requiresConfirmation: false,
    auditLevel: "detailed"
  }
];

async function checkToolPermission(
  toolId: string,
  agentType: string,
  userRole: string
): Promise<{ allowed: boolean; reason?: string }> {
  const permission = TOOL_PERMISSIONS.find(p => p.toolId === toolId);

  if (!permission) return { allowed: true }; // Default allow

  if (!permission.allowedAgents.includes(agentType)) {
    return { allowed: false, reason: `Agent ${agentType} cannot use ${toolId}` };
  }

  if (permission.requiredUserRole && userRole !== permission.requiredUserRole) {
    return { allowed: false, reason: `Role ${permission.requiredUserRole} required` };
  }

  return { allowed: true };
}
```

### 4.4 Task Lifecycle Management

**Current BioMate**: Basic workflow execution tracking

**Proposed**: Full task lifecycle with state management

```typescript
// backend/lib/galaxy/ai/tasks/task_manager.ts

type TaskState =
  | 'created'
  | 'agent_selected'
  | 'planning'
  | 'executing'
  | 'waiting_user'
  | 'completed'
  | 'failed'
  | 'suspended';

interface BiomateTask {
  taskId: string;
  userId: string;
  projectId?: string;
  state: TaskState;

  // Agent info
  agentType: string;
  agentId: string;

  // Execution tracking
  steps: TaskStep[];
  currentStep: number;

  // State preservation (for checkpoint/restore)
  checkpoint?: TaskCheckpoint;

  // Lifecycle timestamps
  createdAt: Date;
  startedAt?: Date;
  completedAt?: Date;

  // Result
  stopReason?: 'end_turn' | 'max_tokens' | 'user_interrupt' | 'error';
  result?: any;
  error?: string;
}

interface TaskStep {
  stepIndex: number;
  toolId: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  input: any;
  output?: any;
  startedAt?: Date;
  completedAt?: Date;
}

class TaskManager {
  private tasks: Map<string, BiomateTask> = new Map();

  async createTask(userId: string, request: string): Promise<BiomateTask> {
    const taskId = `task-${Date.now()}-${randomId()}`;
    const agent = await selectAgent(request);

    const task: BiomateTask = {
      taskId,
      userId,
      state: 'created',
      agentType: agent.agentType,
      agentId: `${agent.agentType}-${taskId}`,
      steps: [],
      currentStep: 0,
      createdAt: new Date()
    };

    this.tasks.set(taskId, task);

    // Emit task created event for audit
    await this.emitBCPMessage({
      type: 'task_created',
      agentInfo: { agentId: task.agentId, taskId },
      payload: { userId, request, agentType: agent.agentType }
    });

    return task;
  }

  async transitionState(taskId: string, newState: TaskState): Promise<void> {
    const task = this.tasks.get(taskId);
    if (!task) throw new Error(`Task ${taskId} not found`);

    const oldState = task.state;
    task.state = newState;

    // Emit state transition for audit
    await this.emitBCPMessage({
      type: 'task_state_change',
      agentInfo: { agentId: task.agentId, taskId },
      payload: { oldState, newState }
    });
  }

  async createCheckpoint(taskId: string): Promise<TaskCheckpoint> {
    const task = this.tasks.get(taskId);
    if (!task) throw new Error(`Task ${taskId} not found`);

    const checkpoint: TaskCheckpoint = {
      checkpointId: `checkpoint-${taskId}-${Date.now()}`,
      taskId,
      state: task.state,
      currentStep: task.currentStep,
      steps: [...task.steps],
      createdAt: new Date()
    };

    task.checkpoint = checkpoint;

    // Persist checkpoint
    await this.persistCheckpoint(checkpoint);

    return checkpoint;
  }

  async restoreFromCheckpoint(checkpointId: string): Promise<BiomateTask> {
    const checkpoint = await this.loadCheckpoint(checkpointId);
    const task = this.tasks.get(checkpoint.taskId);

    if (!task) throw new Error(`Task ${checkpoint.taskId} not found`);

    task.state = checkpoint.state;
    task.currentStep = checkpoint.currentStep;
    task.steps = checkpoint.steps;

    return task;
  }
}
```

### 4.5 BIOMATE.md Project Context (Backend Integration)

**Current BioMate**: LTM preferences stored in database only

**Proposed**: Support project-level context files that feed into backend

```typescript
// backend/lib/galaxy/ai/context/project_context.ts

interface BiomateProjectContext {
  projectType: string;        // e.g., "DIA Proteomics"
  analysisGoal: string;       // e.g., "Quantitative proteomics"

  preferredTools: {
    primary: string[];        // First-choice tools
    alternative: string[];    // Fallback tools
    avoid: string[];          // Tools to never use
  };

  defaultParameters: Record<string, any>;  // Default tool params

  learningNotes?: {
    lastUpdated: Date;
    confidenceLevel: number;
    basedOn: number;          // Number of successful analyses
  };
}

async function loadProjectContext(projectPath: string): Promise<BiomateProjectContext | null> {
  const biomateFile = path.join(projectPath, 'BIOMATE.md');

  if (!fs.existsSync(biomateFile)) {
    return null;
  }

  const content = await fs.readFile(biomateFile, 'utf-8');
  return parseBiomateMarkdown(content);
}

function parseBiomateMarkdown(content: string): BiomateProjectContext {
  // Parse frontmatter and sections
  const sections = extractSections(content);

  return {
    projectType: sections['Project']?.type || 'Unknown',
    analysisGoal: sections['Analysis Type']?.goal || '',
    preferredTools: {
      primary: sections['Preferred Tools']?.primary || [],
      alternative: sections['Preferred Tools']?.alternative || [],
      avoid: sections['Preferred Tools']?.avoid || []
    },
    defaultParameters: sections['Parameters'] || {},
    learningNotes: sections['Learning Notes']
  };
}
```

---

## Part 5: Implementation Roadmap

### Phase 1: Core Protocol (Week 2)

| Task | Description | Files to Create/Modify |
|------|-------------|------------------------|
| Define BCP | Create message type definitions | `backend/lib/galaxy/ai/protocol/bcp.ts` |
| Message Router | Route BCP messages to handlers | `backend/lib/galaxy/ai/protocol/router.ts` |
| Audit Integration | Log all BCP messages to audit | `backend/lib/galaxy/ai/protocol/audit_logger.ts` |

### Phase 2: Agent Specialization (Week 2-3)

| Task | Description | Files to Create/Modify |
|------|-------------|------------------------|
| Agent Registry | Define domain-specific agents | `backend/lib/galaxy/ai/agents/registry.ts` |
| Agent Selector | Select agent based on request | `backend/lib/galaxy/ai/agents/selector.ts` |
| Tool Permissions | Scope tools by agent | `backend/lib/galaxy/ai/permissions/` |

### Phase 3: Task Lifecycle (Week 3)

| Task | Description | Files to Create/Modify |
|------|-------------|------------------------|
| Task Manager | Full task lifecycle management | `backend/lib/galaxy/ai/tasks/manager.ts` |
| Checkpoint System | State persistence/restore | `backend/lib/galaxy/ai/tasks/checkpoint.ts` |
| State Machine | Task state transitions | `backend/lib/galaxy/ai/tasks/state_machine.ts` |

### Phase 4: Project Context (Week 3-4)

| Task | Description | Files to Create/Modify |
|------|-------------|------------------------|
| BIOMATE.md Parser | Parse project context files | `backend/lib/galaxy/ai/context/parser.ts` |
| Context Loader | Load context into agent pipeline | `backend/lib/galaxy/ai/context/loader.ts` |
| LTM Integration | Sync with LTM preferences | `backend/lib/galaxy/ai/context/ltm_sync.ts` |

---

## Summary: What BioMate Should Learn from iFlow

### Architecture Patterns to Adopt

1. **Standardized Agent Protocol** - BCP for all agent communication
2. **Domain Agent Specialization** - Agents per bioinformatics domain
3. **Tool Permission Scoping** - Agents only access their allowed tools
4. **Task Lifecycle Management** - Full state machine for task execution
5. **Checkpoint/Restore** - State preservation for long-running tasks
6. **Project Context Files** - BIOMATE.md for project-specific settings

### What NOT to Copy from iFlow

1. **User-facing hooks** - Wrap all hooks in backend, users don't configure
2. **Agent marketplace** - BioMate's LTM learning is superior to manual curation
3. **MCP integration** - Limited bioinformatics MCPs available
4. **CLI-first design** - BioMate is web-first, different UX paradigm

### Key Differentiator to Maintain

BioMate's **automatic learning** (LTM) is superior to iFlow's manual agent curation. The goal is to combine:
- iFlow's **structured agent architecture** (for organization)
- BioMate's **automatic learning** (for personalization)

This creates a system that **starts organized** (domain agents) and **becomes personalized** (LTM preferences).
