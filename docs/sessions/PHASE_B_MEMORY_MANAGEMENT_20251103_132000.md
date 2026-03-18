# Phase B: Autonomous Memory Management
**Created**: 2025-11-03 13:20:00
**Purpose**: Leverage iFlow's memory management - save context, compress when needed

---

## 🎯 The Problem

**Long workflow sessions hit token limits:**
```
User starts: "Analyze my proteomics data"
[50 messages later]
User: "Now add pathway analysis"

Context accumulated:
- File metadata (5,000 tokens)
- Tool selection discussions (10,000 tokens)
- Parameter configurations (8,000 tokens)
- Validation results (7,000 tokens)
- User clarifications (15,000 tokens)
TOTAL: 45,000 tokens → Near Claude's limit!

Next message might fail or lose early context!
```

---

## ✅ Solution: Autonomous Memory Management (iFlow-inspired)

### Three-Tier Memory System

```
┌────────────────────────────────────────┐
│   Tier 1: Working Memory               │
│   Current conversation (recent 10-20)  │
│   Always in context                    │
└────────────────────────────────────────┘
            ↓ auto-save
┌────────────────────────────────────────┐
│   Tier 2: Key Facts Memory             │
│   Extracted key decisions/facts        │
│   Compressed summaries                 │
│   Loaded when relevant                 │
└────────────────────────────────────────┘
            ↓ periodic compress
┌────────────────────────────────────────┐
│   Tier 3: Session Archive              │
│   Full conversation history            │
│   Retrieved on-demand                  │
│   Used for analysis/learning           │
└────────────────────────────────────────┘
```

---

## 🔧 Feature 1: Auto-Save Key Context

**What iFlow does manually:**
```bash
/memory add "User prefers MSstats for DIA data"
/memory add "FDR threshold: 0.01 for high confidence"
```

**What BioMate does autonomously:**
```python
# LLM automatically extracts and saves key facts
class AutonomousMemoryManager:

    async def monitor_conversation(self, conversation_history):
        """Monitor conversation and auto-extract key facts"""

        # After every N messages, extract key facts
        if len(conversation_history) % 5 == 0:
            key_facts = await self.extract_key_facts(conversation_history[-5:])
            await self.save_to_memory(key_facts)

    async def extract_key_facts(self, recent_messages):
        """LLM extracts important facts from conversation"""

        extraction_prompt = f"""
        Analyze this conversation and extract KEY FACTS to remember:

        {recent_messages}

        Extract:
        1. User preferences (tools, parameters, settings)
        2. Data characteristics (type, size, organism)
        3. Decisions made (which tool, which parameters)
        4. Constraints (time limits, resource limits)
        5. Context that affects future decisions

        Format as JSON:
        {{
          "data_context": {{}},
          "user_preferences": {{}},
          "decisions_made": [],
          "constraints": []
        }}
        """

        facts = await llm.extract(extraction_prompt)
        return facts
```

**Example Auto-Extraction:**
```
Conversation:
User: "I uploaded experiment.mzML, it's DIA data from Orbitrap"
LLM: "Great! DIA data detected. Recommended tools: MSstats, DEqMS"
User: "I prefer MSstats, I've used it before"
LLM: "Configuring MSstats with FDR=0.01..."
User: "Can you make FDR 0.05? I want more sensitivity"

Auto-extracted key facts:
{
  "data_context": {
    "file": "experiment.mzML",
    "type": "DIA",
    "instrument": "Orbitrap"
  },
  "user_preferences": {
    "preferred_tool": "MSstats",
    "reason": "previous experience"
  },
  "decisions_made": [
    "Selected MSstats for differential expression",
    "FDR adjusted to 0.05 for higher sensitivity"
  ],
  "constraints": {
    "sensitivity_priority": "high"
  }
}

Saved to memory → Can be recalled later without re-reading full conversation!
```

---

## 🔧 Feature 2: Context Compression

**What iFlow does manually:**
```bash
/compress   # User triggers compression
```

**What BioMate does autonomously:**

```typescript
class ContextCompressor {
  private readonly MAX_CONTEXT_TOKENS = 180000;  // Claude's limit
  private readonly WARNING_THRESHOLD = 150000;    // Start warning
  private readonly COMPRESS_THRESHOLD = 160000;   // Auto-compress

  async monitorContextSize(sessionId: string) {
    const currentContext = await this.getCurrentContext(sessionId);
    const tokenCount = this.countTokens(currentContext);

    console.log(`Context size: ${tokenCount} / ${this.MAX_CONTEXT_TOKENS} tokens`);

    if (tokenCount >= this.COMPRESS_THRESHOLD) {
      // Critical: Auto-compress OR offer choice
      return await this.handleContextOverflow(sessionId);

    } else if (tokenCount >= this.WARNING_THRESHOLD) {
      // Warning: Inform user
      return {
        status: 'warning',
        message: `Context getting large (${tokenCount} tokens). Will compress soon.`,
        action: 'continue'
      };
    }

    return { status: 'ok', tokenCount };
  }

  async handleContextOverflow(sessionId: string) {
    // Option 1: Ask user what to do
    return {
      status: 'overflow',
      message: `Context limit approaching (160k tokens). Choose action:`,
      options: [
        {
          id: 'compress',
          label: '🗜️ Compress Context',
          description: 'Keep conversation going, summarize old messages'
        },
        {
          id: 'new_session',
          label: '🆕 New Session',
          description: 'Start fresh, archive this conversation'
        },
        {
          id: 'continue',
          label: '▶️ Continue Anyway',
          description: 'Risk losing early context (not recommended)'
        }
      ]
    };
  }

  async compressContext(sessionId: string) {
    """
    Compress conversation while preserving critical information
    """

    const fullContext = await this.getFullContext(sessionId);

    // 1. Identify what to keep vs compress
    const analysis = await this.analyzeContext(fullContext);

    // 2. Extract key facts from old messages
    const keyFacts = await this.extractKeyFacts(
      analysis.messages_to_compress
    );

    // 3. Create compressed summary
    const summary = await this.createSummary(
      analysis.messages_to_compress,
      keyFacts
    );

    // 4. Build new context
    const compressedContext = {
      summary: summary,              // Compressed old messages
      key_facts: keyFacts,            // Extracted decisions
      recent_messages: analysis.messages_to_keep,  // Keep recent 10-20
      metadata: {
        original_messages: fullContext.length,
        compressed_messages: analysis.messages_to_compress.length,
        compression_ratio: summary.length / analysis.messages_to_compress.length
      }
    };

    // 5. Save and replace
    await this.saveCompressedContext(sessionId, compressedContext);

    return {
      success: true,
      tokens_saved: this.calculateTokensSaved(fullContext, compressedContext),
      message: `Compressed ${analysis.messages_to_compress.length} messages into summary`
    };
  }
}
```

**Example Compression:**

**Before (45,000 tokens):**
```
[Message 1] User: Upload file...
[Message 2] LLM: Detected DIA data...
[Message 3] User: What tools available?
[Message 4] LLM: MSstats, DEqMS, DIA-NN...
[Message 5] User: Tell me about MSstats...
[Message 6] LLM: MSstats is a tool for...
...
[Message 50] User: Actually can we try different normalization?
[Message 51] LLM: Sure, here are normalization options...
```

**After Compression (15,000 tokens):**
```
[Compressed Summary]
Session started with DIA proteomics data (experiment.mzML, Orbitrap, 6 samples).
User selected MSstats after reviewing options.
Configured: FDR=0.05, normalization=quantile, min_peptides=2.
Workflow validated and executed successfully.
Results showed 342 differentially expressed proteins.

Key Facts:
- Data: DIA, Orbitrap, 6 samples
- Tool: MSstats (user's preference)
- Parameters: FDR=0.05, quantile normalization
- Status: Workflow completed
- Results: 342 proteins detected

[Recent Messages - Keep Full Detail]
[Message 50] User: Actually can we try different normalization?
[Message 51] LLM: Sure, here are normalization options...
```

**Result:** 45,000 → 15,000 tokens (saved 67%)

---

## 🔧 Feature 3: Smart Session Management

### Auto-Checkpoint System

```typescript
class SessionManager {

  async createCheckpoint(sessionId: string, reason: string) {
    """
    Auto-save session state at key moments
    """

    const checkpoint = {
      checkpoint_id: `cp-${Date.now()}`,
      session_id: sessionId,
      timestamp: new Date(),
      reason: reason,  // 'workflow_completed', 'tool_changed', 'manual'

      state: {
        current_workflow: await this.getCurrentWorkflow(sessionId),
        selected_tools: await this.getSelectedTools(sessionId),
        configured_parameters: await this.getParameters(sessionId),
        uploaded_files: await this.getUploadedFiles(sessionId),
        key_decisions: await this.getKeyDecisions(sessionId)
      },

      context_snapshot: await this.compressCurrentContext(sessionId)
    };

    await db.saveCheckpoint(checkpoint);

    return checkpoint;
  }

  async autoCheckpointTriggers(sessionId: string, event: string) {
    """
    Automatically create checkpoints at important moments
    """

    const triggers = {
      'workflow_completed': true,      // After workflow runs
      'tool_selection_final': true,    // After tool selected
      'parameter_config_done': true,   // After parameters set
      'every_10_messages': true,       // Regular intervals
      'before_compression': true       // Before compressing context
    };

    if (triggers[event]) {
      await this.createCheckpoint(sessionId, event);
    }
  }

  async offerNewSessionOrCompress(sessionId: string) {
    """
    When context is full, offer user choice with context
    """

    const stats = await this.getSessionStats(sessionId);

    return {
      title: "Context Limit Approaching",
      message: `
        This conversation has grown large (${stats.message_count} messages, ${stats.token_count} tokens).

        📊 Session Summary:
        - Workflows created: ${stats.workflows_created}
        - Tools configured: ${stats.tools_configured}
        - Analyses completed: ${stats.analyses_completed}

        Choose how to continue:
      `,
      options: [
        {
          id: 'compress_continue',
          icon: '🗜️',
          title: 'Compress & Continue',
          description: 'Summarize old messages, keep this conversation going',
          recommended: stats.workflows_created < 3,  // Recommend if not too many workflows
          details: 'Preserves key decisions, compresses old details'
        },
        {
          id: 'new_session',
          icon: '🆕',
          title: 'Start New Session',
          description: 'Archive this conversation, start fresh',
          recommended: stats.workflows_created >= 3,  // Recommend if many workflows
          details: 'Current work saved, cleaner context for new analysis'
        },
        {
          id: 'checkpoint_continue',
          icon: '💾',
          title: 'Checkpoint & Force Continue',
          description: 'Save current state, risk context overflow',
          recommended: false,
          warning: 'May lose early context if limit exceeded'
        }
      ],
      auto_action_in: 60  // Auto-compress if no choice in 60 seconds
    };
  }
}
```

---

## 🎬 User Experience Examples

### Example 1: Warning Phase

```
[After 40 messages in workflow discussion]

System (autonomous):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️ Context Status: 152,000 / 180,000 tokens (84%)

Your conversation is getting long. I'm tracking:
• 3 workflows created
• 8 tool configurations
• 2 completed analyses

I'll let you know when compression is needed.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[Continues normally]
```

### Example 2: Compression Choice

```
[Context reaches 160,000 tokens]

System (autonomous):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️ Context Limit Approaching

This conversation has 67 messages (160k tokens).

📊 What we've accomplished:
• Analyzed experiment.mzML (DIA proteomics)
• Created MSstats workflow
• Configured parameters (FDR=0.05)
• Completed differential expression analysis
• Found 342 differentially expressed proteins

How would you like to continue?

[🗜️ Compress Context]
Keep conversation going, summarize older messages
→ Recommended: Good for continuing this analysis

[🆕 New Session]
Start fresh, archive this conversation
→ Recommended if starting different analysis

[▶️ Continue Anyway]
Force continue (not recommended)

Auto-compressing in 60 seconds...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Example 3: After Compression

```
User chooses: [🗜️ Compress Context]

System (autonomous):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Context Compressed

📊 Results:
• Compressed 50 messages → Summary
• Saved 30,000 tokens (67% reduction)
• Preserved all key decisions and configurations
• Recent 10 messages kept in full detail

💾 Checkpoint saved: cp-20251103-132045

You can now continue without context issues!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

How would you like to proceed with your analysis?
```

### Example 4: Auto-Recovery

```
[User doesn't respond to choice prompt]

System (after 60 seconds, autonomous):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🗜️ Auto-Compressing Context

No response received, automatically compressing to prevent context overflow.

✅ Compressed 50 messages (saved 30k tokens)
💾 Full conversation archived
📋 Key facts preserved

Ready to continue!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 💾 Database Schema for Memory Management

```sql
-- Session Checkpoints
CREATE TABLE IF NOT EXISTS session_checkpoints (
    checkpoint_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    user_id TEXT NOT NULL,

    -- Checkpoint metadata
    created_at TEXT DEFAULT (datetime('now')),
    trigger_reason TEXT,  -- 'workflow_completed', 'manual', 'before_compression'

    -- Saved state
    workflow_state TEXT,      -- JSON: current workflow
    tool_configurations TEXT, -- JSON: tool parameters
    uploaded_files TEXT,      -- JSON: file metadata
    key_decisions TEXT,       -- JSON: important decisions made

    -- Compressed context
    compressed_context TEXT,  -- Summarized conversation
    context_token_count INTEGER,

    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Compressed Summaries
CREATE TABLE IF NOT EXISTS context_compressions (
    compression_id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    user_id TEXT NOT NULL,

    -- Compression details
    compressed_at TEXT DEFAULT (datetime('now')),
    messages_compressed INTEGER,     -- How many messages compressed
    original_tokens INTEGER,          -- Original token count
    compressed_tokens INTEGER,        -- After compression
    compression_ratio REAL,           -- Percentage saved

    -- Compressed content
    summary TEXT,                     -- Compressed summary
    extracted_key_facts TEXT,         -- JSON: key facts extracted

    -- What was kept
    retained_messages TEXT,           -- JSON: messages kept in full

    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Session Statistics
CREATE TABLE IF NOT EXISTS session_stats (
    session_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,

    -- Counts
    message_count INTEGER DEFAULT 0,
    current_tokens INTEGER DEFAULT 0,
    workflows_created INTEGER DEFAULT 0,
    tools_configured INTEGER DEFAULT 0,
    files_uploaded INTEGER DEFAULT 0,

    -- Status
    is_active INTEGER DEFAULT 1,
    last_compression_at TEXT,
    compression_count INTEGER DEFAULT 0,

    -- Timestamps
    started_at TEXT DEFAULT (datetime('now')),
    last_activity TEXT DEFAULT (datetime('now')),

    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE INDEX idx_checkpoints_session ON session_checkpoints(session_id);
CREATE INDEX idx_compressions_session ON context_compressions(session_id);
```

---

## 🔄 Integration with Phase A & C

### Phase A Integration (Behavioral Patterns)

```python
# Compressed context includes behavioral patterns
compression_summary = f"""
Session Summary (Compressed):
- User's typical work: {user_patterns.primary_domain}
- Preferred tools: {user_patterns.preferred_tools}
- Data type: {detected_data_type}
- Workflows created: {workflows_created}

This session's specific context:
- Working with DIA proteomics data
- Selected MSstats (aligns with user preference)
- Configured for high sensitivity (FDR=0.05)
- Completed differential expression analysis
"""
```

### Phase C Integration (ACE Learning)

```python
# When compressing, save what worked for ACE
ace_learning_from_session = {
  "successful_patterns": [
    "MSstats selected for DIA differential expression",
    "FDR=0.05 provided good sensitivity/specificity balance",
    "Quantile normalization worked well for this dataset"
  ],
  "failed_attempts": [
    "Initial FDR=0.01 was too stringent, user changed to 0.05"
  ],
  "user_preferences_reinforced": [
    "User consistently prefers MSstats over alternatives"
  ]
}

# Feed into ACE for future improvement
ace.learn_from_compressed_session(ace_learning_from_session)
```

---

## 📋 Implementation Checklist

### Week 1: Core Memory System
- [ ] Implement token counting for context
- [ ] Build auto-extraction of key facts
- [ ] Create checkpoint system
- [ ] Test compression algorithms

### Week 2: User Experience
- [ ] Design compression choice UI
- [ ] Implement auto-compression with warning
- [ ] Build session statistics dashboard
- [ ] Test with long conversations

### Week 3: Integration
- [ ] Connect to Phase A behavioral patterns
- [ ] Feed compressed learnings to Phase C (ACE)
- [ ] Implement checkpoint recovery
- [ ] Performance testing

---

## ✅ Summary

**Memory Management Features:**

1. **Auto-Save Key Context**
   - LLM extracts important facts every N messages
   - Saved to memory for later retrieval
   - No user action needed

2. **Smart Compression**
   - Monitors context size automatically
   - Warns at 150k tokens
   - Offers choice at 160k tokens
   - Auto-compresses if no response

3. **Session Checkpoints**
   - Auto-saves at key moments
   - Preserves workflow state
   - Enables recovery/resume

4. **User Choice**
   - Clear options when context full
   - Recommendations based on session
   - Graceful handling of long sessions

**Result:** Users can have long, complex workflow sessions without context management worries!

---

**This completes Phase B design. Ready to implement?**
