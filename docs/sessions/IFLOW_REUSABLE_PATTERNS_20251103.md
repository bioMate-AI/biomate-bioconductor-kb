# iFlow Code Patterns - Reusable for BioMate Phase B
**Date**: November 3, 2025
**Purpose**: Extract reusable architecture patterns from iFlow CLI for BioMate's autonomous LLM system

---

## Executive Summary

iFlow CLI provides proven patterns for:
1. **Context compression** - AI-driven conversation summarization
2. **Checkpoint system** - State snapshots before changes
3. **Agent system** - Specialized sub-agents with tool permissions
4. **Memory management** - Multi-tier content storage
5. **File references** - Automatic file detection and inclusion

**Key Insight**: iFlow is CLI-based for developers, BioMate is GUI-based for biologists. We must **adapt the concepts, not copy the UX**.

---

## 1. Context Compression System

### iFlow Implementation

**Command**: `/compress`
- Uses AI to compress conversation history into summary
- Manual trigger, but can be automated via hooks
- Configuration: `compressionTokenThreshold` setting
- Hook trigger: SessionStart hook fires after compression

**Key Architecture Pattern**:
```
Long Conversation → AI Summarization → Compressed Summary → Continue with Summary
```

**What We Can Reuse**:
```typescript
// Core concept: Use LLM to compress context
interface ContextCompressionService {
  async compressConversation(
    messages: Message[],
    keepLastN: number = 3
  ): Promise<CompressedContext> {

    // 1. Separate recent messages from old history
    const recentMessages = messages.slice(-keepLastN);
    const oldMessages = messages.slice(0, -keepLastN);

    // 2. Use LLM to summarize old messages
    const summary = await llm.summarize({
      messages: oldMessages,
      prompt: `Summarize this conversation history, preserving:
        - User's research goals and context
        - Tool selections and reasons
        - Data types and files discussed
        - Workflow decisions made
        - Any inferred user preferences

        Format as structured facts, not narrative.`
    });

    // 3. Return compressed context
    return {
      summary: summary,
      recentMessages: recentMessages,
      originalMessageCount: messages.length,
      compressionRatio: summary.length / totalLength(oldMessages)
    };
  }

  // Monitor token usage
  shouldCompress(currentTokens: number): boolean {
    const threshold = config.compressionTokenThreshold || 160000;
    return currentTokens > threshold;
  }

  // User choice when threshold reached
  async handleContextOverflow(sessionId: string): Promise<UserChoice> {
    return await ui.askUser({
      title: "Context Limit Approaching",
      message: "We're approaching the conversation limit. What would you like to do?",
      options: [
        {
          id: "compress",
          label: "🗜️ Compress Context",
          description: "Summarize older messages, keep recent conversation"
        },
        {
          id: "new_session",
          label: "🆕 Start New Session",
          description: "Start fresh (previous work will be saved)"
        },
        {
          id: "continue",
          label: "▶️ Continue Anyway",
          description: "Risk hitting hard limit"
        }
      ],
      autoSelectAfter: 60000, // Auto-compress after 60s
      defaultOption: "compress"
    });
  }
}
```

**BioMate Adaptation**:
- **Trigger**: Auto-monitor token count, offer compression at 160k tokens
- **User Experience**: Show dialog in GUI (not slash command)
- **Preserve**: Scientific context, tool preferences, workflow state
- **Storage**: Save compressed summaries in `context_compressions` table

---

## 2. Checkpoint System

### iFlow Implementation

**Command**: `/restore`
- Automatic checkpoints before AI tool execution
- Stores: Git snapshots + conversation history + tool calls
- Location: `~/.iflow/snapshots/<project_hash>` + `~/.iflow/cache/<project_hash>/checkpoints`
- Permission model: User approves before checkpoint + tool execution

**Architecture**:
```
Tool Call Request → User Approval → Create Checkpoint → Execute Tool → Mark Success/Failure
```

**Storage Structure**:
```
~/.iflow/
  ├── snapshots/<project_hash>/     # Shadow Git repo
  └── cache/<project_hash>/
      └── checkpoints/
          ├── checkpoint_20231215_143022.json
          │   ├── conversation: [...messages]
          │   ├── toolCalls: [{tool, args, context}]
          │   └── metadata: {timestamp, project, branch}
          └── checkpoint_20231215_150130.json
```

**What We Can Reuse**:

```typescript
interface SessionCheckpointService {
  // Checkpoint triggers
  checkpointMoments = [
    'before_workflow_execution',
    'after_tool_selection',
    'before_file_upload_processing',
    'every_10_messages',
    'manual_save'
  ];

  // Create checkpoint
  async createCheckpoint(
    sessionId: string,
    trigger: CheckpointTrigger
  ): Promise<Checkpoint> {

    const session = await getSession(sessionId);

    return {
      checkpoint_id: generateId(),
      session_id: sessionId,
      timestamp: new Date().toISOString(),
      trigger: trigger,

      // Save conversation state
      conversation_snapshot: {
        messages: session.messages,
        current_context: session.inferredContext,
        token_count: session.tokenCount
      },

      // Save workflow state
      workflow_snapshot: {
        selected_tools: session.selectedTools,
        workflow_graph: session.workflowGraph,
        parameters: session.parameters
      },

      // Save uploaded files metadata (not full files)
      files_snapshot: session.uploadedFiles.map(f => ({
        file_id: f.id,
        file_name: f.name,
        detected_type: f.detectedType,
        status: f.processingStatus
      })),

      // Save inferred user patterns
      user_patterns_snapshot: await getUserPatterns(session.userId)
    };
  }

  // Restore checkpoint
  async restoreCheckpoint(checkpointId: string): Promise<Session> {
    const checkpoint = await loadCheckpoint(checkpointId);

    return {
      ...checkpoint.conversation_snapshot,
      ...checkpoint.workflow_snapshot,
      restored_from: checkpointId,
      restored_at: new Date().toISOString()
    };
  }

  // List checkpoints for session
  async listCheckpoints(sessionId: string): Promise<Checkpoint[]> {
    return await db.query(
      'SELECT * FROM session_checkpoints WHERE session_id = ? ORDER BY timestamp DESC',
      [sessionId]
    );
  }
}
```

**BioMate Adaptation**:
- **Storage**: SQLite database table `session_checkpoints`
- **Trigger Points**:
  - Before executing workflow on Galaxy
  - After every 10 user interactions
  - When user uploads large datasets
  - Manual "Save Progress" button in GUI
- **Restore**: Show checkpoint list in sidebar, click to restore
- **No Git**: We don't need Git snapshots (no code files), just conversation + workflow state

**Database Schema**:
```sql
CREATE TABLE session_checkpoints (
    checkpoint_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    user_id TEXT NOT NULL,

    -- When and why
    created_at TEXT DEFAULT (datetime('now')),
    trigger_type TEXT NOT NULL, -- 'auto', 'manual', 'before_workflow', etc.

    -- Conversation state (JSON)
    conversation_snapshot TEXT NOT NULL,
    -- {messages: [...], context: {...}, token_count: N}

    -- Workflow state (JSON)
    workflow_snapshot TEXT NOT NULL,
    -- {selected_tools: [...], graph: {...}, parameters: {...}}

    -- Files metadata (JSON)
    files_snapshot TEXT,

    -- User patterns at this moment (JSON)
    patterns_snapshot TEXT,

    -- Human-readable label
    checkpoint_label TEXT, -- "Before RNA-seq workflow", "After data upload", etc.

    FOREIGN KEY (session_id) REFERENCES sessions(session_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE INDEX idx_checkpoints_session ON session_checkpoints(session_id);
CREATE INDEX idx_checkpoints_timestamp ON session_checkpoints(created_at);
```

---

## 3. Agent System (Sub-Agents)

### iFlow Implementation

**Core Concept**: Specialized agents for specific tasks
- **Agent Definition**: Markdown files with YAML frontmatter
- **Agent Selection**: LLM decides which agent to invoke based on task description
- **Tool Permissions**: Each agent has restricted tool access
- **Invocation**: Main agent uses `Task` tool to call sub-agent

**Agent File Structure** (`~/.iflow/agents/code-reviewer.md`):
```markdown
---
agentType: "code-reviewer"
systemPrompt: "You are an expert code reviewer..."
whenToUse: "Use when user asks for code review, quality checks, or best practices"
model: "claude-3-5-sonnet-20241022"
allowedTools: ["Read", "Grep", "Bash"]
allowedMcps: ["git"]
isInheritTools: false
isInheritMcps: false
proactive: true
color: "blue"
---

# Code Review Expert

You are a specialized agent for reviewing code quality...
```

**Agent Invocation Flow**:
```
User: "Review this code for security issues"
  ↓
Main LLM: Analyzes task → Matches "code review" → Selects code-reviewer agent
  ↓
Main LLM: Calls Task(agent="code-reviewer", task="Review for security")
  ↓
Code-Reviewer Agent: Executes with restricted tools (Read, Grep, Bash only)
  ↓
Returns result to Main LLM
  ↓
Main LLM: Incorporates result into response to user
```

**Permission Model**:
```typescript
interface AgentPermissions {
  // Tool access
  allowedTools: string[];           // ["Read", "Grep", "Bash"]
  isInheritTools: boolean;          // false = no inheritance from main agent

  // MCP server access
  allowedMcps: string[];            // ["git", "filesystem"]
  isInheritMcps: boolean;           // false = no inheritance

  // Proactive suggestion
  proactive: boolean;               // true = suggest usage automatically
}
```

**What We Can Reuse**:

```typescript
interface BiomateAgentSystem {
  // Built-in agents for BioMate
  agents = {
    'proteomics-expert': {
      whenToUse: "User working with proteomics data (DIA, DDA, TMT)",
      systemPrompt: `You are a proteomics workflow specialist.
        You understand:
        - DIA vs DDA data differences
        - MSstats vs other quant tools
        - Protein identification workflows
        - Quality control for mass spec data`,
      allowedTools: ['enhanced_tool_search', 'file_metadata_extraction'],
      contextRequired: ['data_type', 'experiment_goal']
    },

    'workflow-builder': {
      whenToUse: "User needs to compose multi-step analysis workflow",
      systemPrompt: `You are a workflow composition expert.
        You understand:
        - Tool dependencies and compatibility
        - Parameter optimization
        - Data flow between tools
        - Best practice workflows`,
      allowedTools: ['enhanced_tool_search', 'workflow_validation'],
      contextRequired: ['selected_tools', 'data_files']
    },

    'data-interpreter': {
      whenToUse: "User uploads file or describes data without clear type",
      systemPrompt: `You are a bioinformatics data type expert.
        You can identify:
        - File formats (mzML, FASTQ, BAM, etc.)
        - Data types (proteomics, genomics, transcriptomics)
        - Experiment types (DIA, RNA-seq, ChIP-seq, etc.)`,
      allowedTools: ['file_metadata_extraction', 'cv_param_lookup'],
      contextRequired: ['file_metadata']
    },

    'parameter-assistant': {
      whenToUse: "User needs help setting tool parameters",
      systemPrompt: `You are a parameter optimization expert.
        You understand:
        - Default vs optimal parameters
        - Parameter impact on results
        - Common parameter mistakes
        - Data-specific parameter choices`,
      allowedTools: ['tool_parameter_schema', 'scientific_context_lookup'],
      contextRequired: ['selected_tool', 'data_type']
    }
  };

  // Main LLM decides when to invoke agent
  async shouldInvokeAgent(
    userQuery: string,
    currentContext: Context
  ): Promise<AgentInvocation | null> {

    // LLM analyzes: Does this need specialized expertise?
    const analysis = await llm.analyze({
      query: userQuery,
      context: currentContext,
      prompt: `Analyze if this task needs a specialized agent.

        Available agents:
        - proteomics-expert: For proteomics-specific workflows
        - workflow-builder: For multi-step workflow composition
        - data-interpreter: For identifying unknown data types
        - parameter-assistant: For parameter optimization

        Return:
        - agent: <agent_name> or null
        - confidence: 0.0-1.0
        - reason: Why this agent is appropriate`
    });

    if (analysis.confidence > 0.7) {
      return {
        agent: analysis.agent,
        reason: analysis.reason,
        context: extractRequiredContext(currentContext, this.agents[analysis.agent].contextRequired)
      };
    }

    return null;
  }

  // Invoke agent
  async invokeAgent(
    agentName: string,
    task: string,
    context: Context
  ): Promise<AgentResult> {

    const agent = this.agents[agentName];

    // Create specialized prompt
    const agentPrompt = `
${agent.systemPrompt}

Context:
${JSON.stringify(context, null, 2)}

Task:
${task}

Respond with structured recommendations.`;

    // Call LLM with agent's system prompt
    const result = await llm.complete({
      systemPrompt: agent.systemPrompt,
      messages: [{ role: 'user', content: task }],
      context: context,
      tools: agent.allowedTools.map(t => getToolDefinition(t))
    });

    return {
      agent: agentName,
      result: result,
      toolsUsed: result.toolCalls,
      confidence: result.confidence
    };
  }
}
```

**BioMate Adaptation**:
- **NOT** slash commands - LLM automatically invokes agents
- **NOT** markdown files - agents defined in code or database
- **YES** specialized prompts for different bioinformatics domains
- **YES** tool permission restrictions
- **YES** automatic agent selection based on task analysis

**User Experience**:
```
User: "I have proteomics data, what tools should I use?"
  ↓
[Background: Main LLM detects "proteomics" → invokes proteomics-expert agent]
  ↓
GUI shows: 🧬 Analyzing proteomics workflow options...
  ↓
Agent searches for proteomics tools, applies domain knowledge
  ↓
GUI shows: "For proteomics analysis, I recommend..."
  (User never sees "agent invoked" - seamless experience)
```

---

## 4. Memory Management (Multi-Tier)

### iFlow Implementation

**Command**: `/memory`
- Persistent instructions across sessions
- Modular content import via `@file.md`
- Memory levels: Session memory vs Global memory

**Memory Import System**:
```markdown
# Main IFLOW.md

Project uses React and TypeScript.

@./memory/coding-standards.md
@./memory/project-architecture.md
```

**What We Can Reuse**:

```typescript
interface MemoryTierSystem {
  // Three-tier memory architecture
  tiers = {
    // Tier 1: Working Memory (current session)
    working: {
      scope: 'session',
      maxTokens: 20000,
      contains: [
        'current_conversation',
        'recent_user_actions',
        'active_workflow_state'
      ]
    },

    // Tier 2: Key Facts (extracted important info)
    keyFacts: {
      scope: 'session',
      maxTokens: 10000,
      contains: [
        'inferred_research_goal',
        'detected_data_types',
        'tool_preferences_this_session',
        'important_decisions'
      ],
      updateFrequency: 'every_10_messages'
    },

    // Tier 3: Long-term Patterns (cross-session)
    longTerm: {
      scope: 'user',
      maxTokens: 5000,
      contains: [
        'domain_preference',
        'tool_preferences',
        'complexity_level',
        'common_workflows'
      ],
      source: 'user_patterns table (Phase A)'
    }
  };

  // Extract key facts from conversation
  async extractKeyFacts(
    messages: Message[],
    lastExtractedIndex: number
  ): Promise<KeyFacts> {

    const newMessages = messages.slice(lastExtractedIndex);

    const facts = await llm.extract({
      messages: newMessages,
      prompt: `Extract key facts from this conversation segment:

        Focus on:
        1. Research Goal: What is the user trying to achieve?
        2. Data Context: What type of data? What format?
        3. Tool Preferences: Which tools did they select and why?
        4. Important Decisions: Any critical choices made?
        5. Problems Encountered: Any issues or errors?

        Format as structured JSON:
        {
          "research_goal": "...",
          "data_type": "...",
          "tools_selected": [...],
          "decisions": [...],
          "problems": [...]
        }`
    });

    return facts;
  }

  // Build context injection for next LLM call
  async buildContextInjection(
    sessionId: string,
    userId: string
  ): Promise<string> {

    // Tier 1: Recent messages (already in conversation)
    // (No need to inject)

    // Tier 2: Key facts from this session
    const keyFacts = await getSessionKeyFacts(sessionId);

    // Tier 3: Long-term user patterns
    const userPatterns = await getUserPatterns(userId);

    return `
[Context]

Session Key Facts:
${JSON.stringify(keyFacts, null, 2)}

User Patterns (from past behavior):
- Research Domain: ${userPatterns.domain} (confidence: ${userPatterns.domain_confidence})
- Preferred Tools: ${userPatterns.preferred_tools.join(', ')}
- Complexity Level: ${userPatterns.complexity_level}

[End Context]`;
  }

  // Auto-save key facts periodically
  async autoSaveKeyFacts(sessionId: string, messageCount: number) {
    if (messageCount % 10 === 0) {
      const facts = await this.extractKeyFacts(
        getSessionMessages(sessionId),
        getLastExtractedIndex(sessionId)
      );

      await saveKeyFacts(sessionId, facts);
      updateLastExtractedIndex(sessionId, messageCount);
    }
  }
}
```

**BioMate Adaptation**:
- **Tier 1 (Working)**: Current conversation in session
- **Tier 2 (Key Facts)**: Extracted and stored in `session_key_facts` table
- **Tier 3 (Long-term)**: User patterns from Phase A (`user_patterns` table)

**Database Schema**:
```sql
CREATE TABLE session_key_facts (
    fact_id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,

    -- When extracted
    extracted_at TEXT DEFAULT (datetime('now')),
    message_range TEXT, -- "messages 10-20"

    -- Extracted facts (JSON)
    research_goal TEXT,
    data_context TEXT,
    tool_selections TEXT,
    decisions_made TEXT,
    problems_encountered TEXT,

    FOREIGN KEY (session_id) REFERENCES sessions(session_id)
);

CREATE INDEX idx_key_facts_session ON session_key_facts(session_id);
```

---

## 5. File Reference System

### iFlow Implementation

**Syntax**: `@<file_path>` or `@<directory>`
- Automatically detects files in workspace
- Injects file content into prompt
- Supports relative and absolute paths
- Security: Circular import detection, path validation

**What We Can Reuse**:

```typescript
interface AutoFileReferenceService {
  // LLM autonomously detects files to reference
  async detectRelevantFiles(
    userQuery: string,
    workspaceFiles: File[]
  ): Promise<File[]> {

    // Analyze query for file-related keywords
    const analysis = await llm.analyze({
      query: userQuery,
      files: workspaceFiles.map(f => ({ name: f.name, size: f.size, type: f.type })),
      prompt: `User query: "${userQuery}"

        Available files:
        ${workspaceFiles.map(f => `- ${f.name} (${f.type}, ${f.size} bytes)`).join('\n')}

        Which files are relevant to this query?
        Return JSON: {
          "relevant_files": ["file1.mzML", "file2.csv"],
          "reason": "Why these files are relevant",
          "confidence": 0.0-1.0
        }`
    });

    if (analysis.confidence > 0.7) {
      return workspaceFiles.filter(f => analysis.relevant_files.includes(f.name));
    }

    return [];
  }

  // Auto-inject file metadata
  async injectFileContext(
    files: File[]
  ): Promise<string> {

    const metadataPromises = files.map(async f => {
      const metadata = await extractFileMetadata(f);
      return {
        name: f.name,
        type: f.type,
        size: f.size,
        detected_data_type: metadata.dataType,
        key_properties: metadata.keyProperties
      };
    });

    const metadata = await Promise.all(metadataPromises);

    return `
[Uploaded Files Context]

${metadata.map(m => `
File: ${m.name}
Type: ${m.detected_data_type}
Properties: ${JSON.stringify(m.key_properties)}
`).join('\n')}

[End Files Context]`;
  }
}
```

**BioMate Adaptation**:
- **User Uploads**: Files uploaded via GUI file picker
- **Auto-Detection**: When user mentions "my file" or "the data", LLM checks uploaded files
- **Metadata Extraction**: Automatically extract and include file metadata in context
- **No Path Syntax**: GUI-based, not file path strings

---

## 6. Architecture Integration: Complete Flow

### How It All Works Together

```
User Interaction
  ↓
┌─────────────────────────────────────────────────────────┐
│ 1. INCOMING MESSAGE                                      │
│    - User query                                          │
│    - Uploaded files                                      │
│    - Session history                                     │
└─────────────────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────────────────┐
│ 2. CONTEXT BUILDING                                      │
│    ┌────────────────────────────────────┐               │
│    │ Tier 1: Working Memory (recent)     │               │
│    │ Tier 2: Key Facts (extracted)       │               │
│    │ Tier 3: User Patterns (Phase A)     │               │
│    └────────────────────────────────────┘               │
│    ┌────────────────────────────────────┐               │
│    │ File Context (if files present)     │               │
│    └────────────────────────────────────┘               │
└─────────────────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────────────────┐
│ 3. AGENT SELECTION                                       │
│    Main LLM: Should I invoke specialized agent?         │
│    ┌────────────────────────────────────┐               │
│    │ YES → Invoke proteomics-expert      │               │
│    │ NO  → Handle directly                │               │
│    └────────────────────────────────────┘               │
└─────────────────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────────────────┐
│ 4. TASK EXECUTION                                        │
│    - Search tools (enhanced_tool_search)                 │
│    - Extract metadata                                    │
│    - Compose workflow                                    │
└─────────────────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────────────────┐
│ 5. CHECKPOINT (if needed)                                │
│    Before executing workflow:                            │
│    - Save conversation state                             │
│    - Save workflow state                                 │
│    - Save file metadata                                  │
└─────────────────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────────────────┐
│ 6. RESPONSE TO USER                                      │
│    - Tool recommendations                                │
│    - Workflow suggestions                                │
│    - Next steps guidance                                 │
└─────────────────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────────────────┐
│ 7. MEMORY UPDATE                                         │
│    Every 10 messages:                                    │
│    - Extract key facts                                   │
│    - Store in session_key_facts                          │
│                                                          │
│    Every interaction:                                    │
│    - Log to user_interactions (Phase A)                  │
│    - Update user_patterns (Phase A)                      │
└─────────────────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────────────────┐
│ 8. CONTEXT OVERFLOW CHECK                                │
│    Token count > 160k?                                   │
│    ┌────────────────────────────────────┐               │
│    │ YES → Offer compression             │               │
│    │ NO  → Continue                      │               │
│    └────────────────────────────────────┘               │
└─────────────────────────────────────────────────────────┘
```

---

## 7. Implementation Priority

### Phase B.1: Foundation (Week 1)
1. ✅ **Context Building Service** - Inject Tier 2 + Tier 3 into prompts
2. ✅ **Token Monitoring** - Track context size
3. ✅ **Checkpoint System** - Database schema + basic save/restore

### Phase B.2: Memory Management (Week 1)
4. **Key Facts Extraction** - Auto-extract every 10 messages
5. **Context Compression** - Implement AI-based summarization
6. **User Choice UI** - Dialog for compress vs new session

### Phase B.3: Agent System (Week 2)
7. **Agent Definitions** - Define 4 core agents (proteomics, workflow, data, parameter)
8. **Agent Invocation Logic** - Main LLM decides when to invoke
9. **Tool Permissions** - Restrict agent tool access

### Phase B.4: File Intelligence (Week 2)
10. **Auto File Detection** - LLM detects relevant files from workspace
11. **Metadata Injection** - Include file context automatically

---

## 8. Key Differences: iFlow vs BioMate

| Aspect | iFlow (CLI for Developers) | BioMate (GUI for Biologists) |
|--------|---------------------------|------------------------------|
| **User Interface** | Terminal, slash commands | Web GUI, chat interface |
| **User Expertise** | Developers familiar with CLI | Biologists, varying technical levels |
| **Agent Invocation** | User types `$agent-name` | LLM automatically invokes agents |
| **File Reference** | User types `@file.md` | LLM auto-detects uploaded files |
| **Compression Trigger** | User types `/compress` | Auto-prompt at token threshold |
| **Checkpoints** | Before tool execution | Before workflow execution + auto-save |
| **Agent Types** | Code review, frontend dev, etc. | Proteomics expert, workflow builder, etc. |
| **Context** | Code repositories | Scientific data and workflows |

**Core Principle**: We're adapting **iFlow's autonomous LLM patterns**, not its CLI user experience!

---

## 9. Code to NOT Reuse

**DO NOT REUSE**:
- ❌ Shell script installation (`install.sh`) - we have web deployment
- ❌ Terminal UI rendering - we have React frontend
- ❌ Slash command parser - we have chat interface
- ❌ Git integration - not needed for scientific workflows
- ❌ Shell job control (suspend/resume) - not applicable
- ❌ MCP server protocol - we use Galaxy API

**DO REUSE**:
- ✅ **Concepts**: Agents, compression, checkpoints, memory tiers
- ✅ **Patterns**: Context building, agent selection logic, permission models
- ✅ **Architectures**: Multi-tier memory, checkpoint structures

---

## Summary

iFlow provides proven patterns for autonomous LLM systems:
1. **Context Compression**: AI-driven summarization when approaching token limits
2. **Checkpointing**: State snapshots before critical actions
3. **Agent System**: Specialized sub-agents with automatic invocation
4. **Memory Management**: Three-tier architecture (working, key facts, long-term)
5. **File Intelligence**: Automatic file detection and metadata injection

**Next Step**: Implement these patterns in BioMate with bioinformatics-specific adaptations! 🚀
