# iFlow CLI Integration Update - January 2026

**Date**: 2026-01-13
**Purpose**: Update iFlow analysis with latest features and map integration opportunities to BioMate's current architecture

---

## Executive Summary

This document updates the iFlow integration analysis from October 2025 with:
1. New iFlow features released since the last analysis
2. Mapping against BioMate's current self-learning and auditing capabilities
3. Concrete integration proposals for immediate implementation
4. Prioritized feature adoption based on current BioMate gaps

### Key Findings

| Capability | iFlow Status | BioMate Status | Integration Priority |
|------------|--------------|----------------|---------------------|
| **Self-Learning** | Manual curation only | **10-table LTM** with auto-learning | BioMate AHEAD |
| **Auditing** | Hooks + Telemetry | **Full AuditService** | BioMate AHEAD |
| **Checkpointing** | Shadow Git snapshots | Not implemented | HIGH - Adopt |
| **Workflow System** | Composable agents+commands | Galaxy workflows only | HIGH - Adopt patterns |
| **SDK/API** | Python SDK + ACP | API exists, no SDK | MEDIUM - Create SDK |
| **Hooks System** | 9 hook types | Basic server hooks | MEDIUM - Enhance |
| **SubAgents** | $agent-name syntax | LTM-based routing | LOW - Already have |
| **MCP Integration** | Full MCP marketplace | Not implemented | LOW - Future |

---

## Part 1: New iFlow Features Since October 2025

### 1.1 Checkpointing System (NEW)

**What It Does**: Automatically saves project state snapshots before AI tools modify files.

```
Tool Call → Permission Confirmation → State Snapshot → Tool Execution → Checkpoint Complete
```

**Key Components**:
- Shadow Git repository at `~/.iflow/snapshots/<project_hash>`
- Conversation history backup
- Tool call information storage
- `/restore` command for rollback

**BioMate Opportunity**:
- We have `workflow_executions` tracking but NO pre-execution snapshots
- Could add checkpoint-like system for workflow rollback
- Useful for long-running bioinformatics workflows where errors occur mid-execution

### 1.2 Python SDK with ACP (Agent Communication Protocol)

**What It Does**: Programmatic access to iFlow CLI for building custom agents.

```python
from iflow_sdk import IFlowClient, AssistantMessage, TaskFinishMessage

async with IFlowClient() as client:
    await client.send_message("Your question")
    async for message in client.receive_messages():
        if isinstance(message, AssistantMessage):
            print(message.chunk.text)
        elif isinstance(message, TaskFinishMessage):
            break
```

**Key Features**:
- Auto-process management (starts iFlow if not running)
- Message types: AssistantMessage, ToolCallMessage, PlanMessage, TaskFinishMessage
- AgentInfo tracking with task_id, agent_index, timestamp
- Streaming response support

**BioMate Opportunity**:
- Create `biomate-sdk` for programmatic workflow generation
- Enable third-party integrations with BioMate
- Support headless automation in CI/CD pipelines

### 1.3 Enhanced Hooks System (9 Hook Types)

**iFlow Hook Types**:

| Hook | Trigger | BioMate Equivalent |
|------|---------|-------------------|
| PreToolUse | Before tool execution | Not implemented |
| PostToolUse | After tool execution | Not implemented |
| SetUpEnvironment | Session start | Galaxy connection init |
| Stop | Session ends | Not implemented |
| SubagentStop | Subagent ends | Not implemented |
| SessionStart | Session begins | Conversation start |
| SessionEnd | Session ends normally | Not implemented |
| UserPromptSubmit | Before prompt processed | Not implemented |
| Notification | When notifications sent | SSE events only |

**BioMate Opportunity**:
- Add PreToolUse/PostToolUse hooks for workflow step validation
- UserPromptSubmit hook for content filtering (PII protection)
- SessionEnd hook for automatic learning trigger

### 1.4 Thinking Capability

**What It Does**: Triggers AI deep thinking through keywords with 5 reasoning levels.

- **none**: No thinking (0 tokens)
- **normal**: Basic thinking (2,000 tokens) - "think"
- **hard**: Intermediate (4,000 tokens) - "think harder"
- **mega**: Advanced (10,000 tokens) - "think really hard"
- **ultra**: Super (32,000 tokens) - "ultrathink"

**BioMate Opportunity**:
- Add thinking levels to workflow generation
- Use higher thinking for complex multi-tool workflows
- Default to "hard" for bioinformatics domain complexity

### 1.5 GitHub Actions Integration

**What It Does**: Native GitHub Actions for CI/CD automation.

```yaml
- name: 'Run iFlow CLI'
  uses: vibe-ideas/iflow-cli-action@main
  with:
    api_key: ${{ secrets.IFLOW_API_KEY }}
    prompt: "Analyze and label this issue"
```

**BioMate Opportunity**:
- Create `biomate-action` for GitHub Actions
- Automate workflow generation in PR reviews
- CI/CD integration for bioinformatics pipelines

---

## Part 2: Comparison with BioMate Current Architecture

### 2.1 Self-Learning Comparison

**iFlow**: Manual curation through marketplace
- Expert creates workflow
- Users install and use
- Expert manually updates
- Community shares via platform

**BioMate (SUPERIOR)**: 10-table LTM with automatic learning
```
┌─────────────────────────────────────────────────────────────────┐
│                    LTM Database (10 Tables)                      │
├─────────────────────────────────────────────────────────────────┤
│ ltm_users          │ User profiles and capabilities             │
│ user_preferences   │ Tool/parameter preferences (0-1 confidence)│
│ correction_log     │ Learning from corrections                  │
│ project_episodes   │ Episodic memory per project               │
│ project_procedures │ Reusable patterns (3+ similar episodes)   │
│ project_knowledge  │ Consolidated domain knowledge             │
│ sessions           │ Conversation sessions                      │
│ conversation_msgs  │ Message history                           │
│ workflows          │ Generated workflows                       │
│ projects           │ Project metadata                          │
└─────────────────────────────────────────────────────────────────┘
```

**Key Differentiators**:
- BioMate has **automatic preference learning** (iFlow lacks this)
- BioMate has **episodic → procedural consolidation** (iFlow lacks this)
- BioMate tracks **confidence scores** (iFlow has helpful/harmful counters only in ACE proposal)
- BioMate learns from **corrections in real-time** (iFlow requires manual updates)

### 2.2 Auditing Comparison

**iFlow**: Hooks + Telemetry
- PreToolUse/PostToolUse hooks for logging
- Telemetry with OTLP endpoint support
- Session transcript files

**BioMate (SUPERIOR)**: Comprehensive AuditService
```typescript
// BioMate's AuditService methods
- logAuth(userId, action, success, metadata)
- logWorkflowGeneration(userId, workflowId, request, response)
- logWorkflowExecution(userId, workflowId, stepIndex, status)
- logDatasetUpload(userId, datasetId, size, format)
- logAccessDenied(userId, resource, reason)
- logSSEConnection(userId, connectionId, action)
```

**Key Differentiators**:
- BioMate has **structured audit logs** (iFlow has hook-based logging only)
- BioMate tracks **workflow execution step-by-step** (iFlow tracks tool calls only)
- BioMate has **built-in compliance fields** (WHO/WHAT/WHEN/WHERE/WHY/OUTCOME)
- BioMate has **SSE connection tracking** (iFlow lacks this)

### 2.3 Workflow System Comparison

**iFlow**: Composable Workflow System
```
.iflow/
├── agents/        # Domain specialists
├── commands/      # Custom commands
├── IFLOW.md       # Workflow documentation
└── settings.json  # MCP config
```

**BioMate**: Galaxy-Native Workflows
```
workflows/
├── ga4gh/         # Standard workflow formats
├── galaxy/        # Galaxy XML tools
└── generated/     # AI-generated workflows
```

**Gap Analysis**:
- BioMate lacks **IFLOW.md-style documentation** for AI workflows
- BioMate lacks **composable agent patterns** (has hybrid intelligence but less modular)
- BioMate lacks **local workflow packaging** (everything goes through Galaxy)

---

## Part 3: Integration Proposals

### Proposal 1: Workflow Checkpointing System (HIGH PRIORITY)

**Problem**: BioMate workflows can fail mid-execution with no rollback capability.

**Solution**: Adopt iFlow's checkpointing pattern for Galaxy workflows.

```typescript
// Proposed: frontend/server/lib/checkpointing.ts
export class WorkflowCheckpointer {
  private snapshotDir: string = '~/.biomate/snapshots';

  async createCheckpoint(workflowId: string): Promise<Checkpoint> {
    return {
      id: `checkpoint_${Date.now()}`,
      workflowId,
      timestamp: new Date(),
      state: {
        historyId: await this.getHistorySnapshot(),
        datasetStates: await this.getDatasetStates(),
        conversationContext: await this.getConversationContext()
      }
    };
  }

  async restore(checkpointId: string): Promise<void> {
    const checkpoint = await this.loadCheckpoint(checkpointId);
    await this.restoreHistoryState(checkpoint.state.historyId);
    await this.restoreConversation(checkpoint.state.conversationContext);
  }
}
```

**Implementation Steps**:
1. Add `workflow_checkpoints` table to database
2. Create checkpoint before each workflow execution step
3. Add `/restore` API endpoint
4. Integrate with existing `workflow_executions` tracking

### Proposal 2: BioMate Python SDK (MEDIUM PRIORITY)

**Problem**: No programmatic access to BioMate for automation.

**Solution**: Create SDK similar to iFlow's pattern.

```python
# Proposed: biomate-sdk
from biomate_sdk import BiomateClient, WorkflowMessage

async with BiomateClient() as client:
    # Generate workflow
    workflow = await client.generate_workflow(
        "Analyze DIA proteomics data",
        data_type="DIA",
        instrument="Orbitrap"
    )

    # Execute workflow
    async for status in client.execute_workflow(workflow.id):
        if status.type == "step_complete":
            print(f"Step {status.step}: {status.result}")
        elif status.type == "workflow_complete":
            print(f"Workflow finished: {status.outputs}")
```

**Implementation Steps**:
1. Define BioMate Communication Protocol (BCP)
2. Create Python package `biomate-sdk`
3. Implement WebSocket-based message streaming
4. Add authentication via API keys

### Proposal 3: Pre/Post Tool Hooks (MEDIUM PRIORITY)

**Problem**: No way to validate workflow steps before/after execution.

**Solution**: Adopt iFlow's hook pattern.

```typescript
// Proposed: frontend/server/lib/hooks.ts
export class WorkflowHooks {
  private hooks: Map<HookType, HookHandler[]> = new Map();

  async executePreToolHook(tool: Tool, params: ToolParams): Promise<HookResult> {
    // Validate tool compatibility
    // Check data type requirements
    // Log audit event
    return { proceed: true };
  }

  async executePostToolHook(tool: Tool, result: ToolResult): Promise<void> {
    // Update learning database
    // Trigger ACE reflection if error
    // Update audit log
  }
}
```

**Hook Types to Implement**:
1. `PreWorkflowExecution` - Validate entire workflow before start
2. `PreToolExecution` - Validate individual tool step
3. `PostToolExecution` - Learn from tool results
4. `WorkflowComplete` - Trigger episodic memory consolidation

### Proposal 4: BIOMATE.md Context Files (LOW PRIORITY)

**Problem**: No standardized way to document AI workflow patterns.

**Solution**: Adopt IFLOW.md pattern for bioinformatics contexts.

```markdown
# BIOMATE.md

## Project: DIA Proteomics Analysis

## Analysis Type
- Data: DIA mass spectrometry
- Instrument: Orbitrap Exploris 480
- Goal: Quantitative proteomics

## Preferred Tools
- Primary: DIA-NN (fast, accurate)
- Alternative: Spectronaut (maximum sensitivity)
- Avoid: MaxQuant (DDA-only)

## Parameters
- FDR: 0.01 (high confidence)
- Charge states: 2-4
- Precursor mass tolerance: 10 ppm

## Learning Notes
- Last updated: 2026-01-13
- Confidence level: 0.85
- Based on: 15 successful analyses
```

**Implementation Steps**:
1. Add `BIOMATE.md` parser to project context loader
2. Integrate with LTM `project_knowledge` table
3. Auto-generate BIOMATE.md from learned preferences
4. Support hierarchical context (user-level + project-level)

---

## Part 4: Integration Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BioMate + iFlow Integration                          │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                           USER INTERFACE LAYER                               │
│                      (Adopt iFlow UX Patterns)                               │
│                                                                              │
│  /workflow <type>        Slash commands (iFlow pattern)                     │
│  @data/file.mzML         File references (iFlow pattern)                    │
│  $tool-selector          Agent calls (map to LTM routing)                   │
│  BIOMATE.md              Context files (new)                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ORCHESTRATION LAYER                                  │
│                   (BioMate Hybrid Intelligence)                              │
│                                                                              │
│  ┌───────────────┐   ┌───────────────┐   ┌───────────────┐                 │
│  │ Intent        │   │ Tool Search   │   │ Dataset RAG   │                 │
│  │ Analysis      │──▶│ (2,177 tools) │──▶│ (ChromaDB)    │                 │
│  └───────────────┘   └───────────────┘   └───────────────┘                 │
│                              │                                              │
│                              ▼                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    HOOKS SYSTEM (NEW)                                │   │
│  │  PreWorkflow → PreTool → [Execute] → PostTool → WorkflowComplete    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌───────────────────────────┬─────────────────────────┬───────────────────────┐
│   LEARNING LAYER          │   EXECUTION LAYER       │   AUDITING LAYER      │
│   (BioMate LTM)           │   (Galaxy Backend)      │   (BioMate Audit)     │
│                           │                         │                       │
│  ┌───────────────────┐    │  ┌─────────────────┐    │  ┌─────────────────┐  │
│  │ 10-Table LTM      │    │  │ Galaxy API      │    │  │ AuditService    │  │
│  │ • Preferences     │    │  │ • Workflows     │    │  │ • Auth logs     │  │
│  │ • Corrections     │    │  │ • Datasets      │    │  │ • Workflow logs │  │
│  │ • Episodes        │    │  │ • Jobs          │    │  │ • Execution logs│  │
│  │ • Procedures      │    │  │ • Histories     │    │  │ • SSE logs      │  │
│  └───────────────────┘    │  └─────────────────┘    │  └─────────────────┘  │
│                           │                         │                       │
│  ┌───────────────────┐    │  ┌─────────────────┐    │  ┌─────────────────┐  │
│  │ CHECKPOINTS (NEW) │    │  │ Workflow        │    │  │ Telemetry       │  │
│  │ • Pre-execution   │    │  │ Executions      │    │  │ (Future: OTLP)  │  │
│  │ • State snapshots │    │  │ Step tracking   │    │  │                 │  │
│  │ • Rollback        │    │  │                 │    │  │                 │  │
│  └───────────────────┘    │  └─────────────────┘    │  └─────────────────┘  │
└───────────────────────────┴─────────────────────────┴───────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SDK/API LAYER (NEW)                                │
│                                                                              │
│  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐           │
│  │ REST API        │   │ BioMate SDK     │   │ GitHub Action   │           │
│  │ (Current)       │   │ (Python)        │   │ biomate-action  │           │
│  │                 │   │ (Proposed)      │   │ (Proposed)      │           │
│  └─────────────────┘   └─────────────────┘   └─────────────────┘           │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 5: Implementation Priority Matrix

| Feature | Effort | Impact | Priority | Blocker? |
|---------|--------|--------|----------|----------|
| Workflow Checkpointing | Medium | High | **1** | No |
| Pre/Post Tool Hooks | Medium | High | **2** | No |
| BIOMATE.md Context | Low | Medium | **3** | No |
| Python SDK | High | Medium | **4** | No |
| GitHub Action | Medium | Low | **5** | Needs SDK |
| Thinking Levels | Low | Low | **6** | No |
| MCP Integration | High | Low | **7** | External dep |

---

## Part 6: Conclusion

### What BioMate Already Has (Superior to iFlow)

1. **Self-Learning**: 10-table LTM with automatic preference learning, correction tracking, and episodic consolidation
2. **Auditing**: Comprehensive AuditService with structured compliance-ready logs
3. **Hybrid Intelligence**: Intent analysis + tool search + dataset RAG pipeline

### What to Adopt from iFlow

1. **Checkpointing**: Pre-execution snapshots for workflow rollback
2. **Hook System**: Pre/Post tool execution hooks for validation
3. **SDK Pattern**: Python SDK for programmatic access
4. **Context Files**: BIOMATE.md for project-specific AI context

### Immediate Next Steps

1. Implement workflow checkpointing (builds on existing workflow_executions)
2. Add PreToolExecution and PostToolExecution hooks
3. Create BIOMATE.md parser and integrate with LTM

### Deferred Items

- MCP integration (external dependency, limited bioinformatics MCPs available)
- Full iFlow workflow syntax (Galaxy workflows serve current needs)
- Agent marketplace (focus on built-in agents first)

---

## References

- iFlow CLI Repository: https://github.com/iflow-ai/iflow-cli
- Previous Integration Analysis: `/home/yzhang/biomate/reference/IFLOW_ACE_BIOMATE_INTEGRATION_20251030.md`
- BioMate Self-Learning Documentation: `/home/yzhang/biomate/docs/05-data/20260113_SELF_LEARNING_SYSTEM.md`
- BioMate Auditing Documentation: `/home/yzhang/biomate/docs/05-data/20260113_AUDITING_SYSTEM.md`
