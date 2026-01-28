# Clawdbot Survey and Biomate Integration Plan

**Date:** 2026-01-27
**Repository:** https://github.com/clawdbot/clawdbot (now rebranded to moltbot)
**Stars:** 60,000+ (one of fastest-growing open-source projects in GitHub history)
**License:** MIT

---

## Executive Summary

Clawdbot (recently rebranded to Moltbot) is a personal AI assistant that runs on the user's own devices and connects to multiple messaging channels. It provides a unified control plane for managing AI conversations across WhatsApp, Telegram, Slack, Discord, Signal, iMessage, Microsoft Teams, and more.

For Biomate, integrating with Clawdbot offers a compelling opportunity to extend user interaction channels beyond the current web-only interface, enabling bioinformatics workflow generation through familiar messaging platforms.

---

## Part 1: Clawdbot Survey

### 1.1 Core Architecture

```
Messaging Channels (WhatsApp, Telegram, Slack, Discord, Signal, iMessage, Teams, etc.)
                    │
                    ▼
┌───────────────────────────────────────────────────────────────┐
│                     Gateway (Control Plane)                    │
│                    ws://127.0.0.1:18789                        │
│  ┌─────────────┬──────────────┬───────────────┬─────────────┐ │
│  │  Sessions   │   Routing    │    Tools      │   Events    │ │
│  │  Management │   Engine     │    Registry   │   System    │ │
│  └─────────────┴──────────────┴───────────────┴─────────────┘ │
└────────────────────────┬──────────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
    Pi Agent        CLI/macOS        iOS/Android
    (RPC mode)        Apps             Nodes
```

### 1.2 Key Features

| Feature | Description | Relevance to Biomate |
|---------|-------------|---------------------|
| **Multi-Channel Support** | 12+ messaging platforms including WhatsApp, Telegram, Slack, Discord, Signal, iMessage, Teams, Matrix, Zalo | **High** - Enables workflow queries from any platform |
| **Local-First Gateway** | Single control plane for all sessions, runs on user's hardware | **Medium** - Can be deployed alongside Biomate |
| **Multi-Agent Routing** | Route channels/accounts to isolated agents with separate workspaces | **High** - Different users can have isolated workflow sessions |
| **Skills System** | Bundled, managed, and workspace skills for extending functionality | **Critical** - Biomate can be a skill plugin |
| **Voice Wake + Talk** | Always-on speech for macOS/iOS/Android with ElevenLabs | **Medium** - Voice-based workflow queries |
| **Live Canvas** | Agent-driven visual workspace with A2UI | **Medium** - Could display workflow visualizations |
| **Session Persistence** | Memory across conversations with session isolation | **High** - Track workflow history per user |
| **Webhook System** | Cron jobs and webhook triggers for automation | **High** - Async workflow completion notifications |
| **Security Model** | DM pairing, allowlists, sandbox for non-main sessions | **High** - Control who can trigger workflows |

### 1.3 Technical Stack

- **Runtime:** Node.js 22+
- **Language:** TypeScript (ESM)
- **Package Manager:** pnpm (also supports npm, bun)
- **Testing:** Vitest with 70% coverage threshold
- **Linting:** Oxlint + Oxfmt
- **Messaging Libraries:**
  - WhatsApp: Baileys
  - Telegram: grammY
  - Slack: Bolt
  - Discord: discord.js
  - Signal: signal-cli

### 1.4 Gateway WebSocket Protocol

```typescript
// Request format
{ type: "req", id: string, method: string, params: object }

// Response format
{ type: "res", id: string, ok: boolean, payload?: object, error?: object }

// Event format
{ type: "event", event: string, payload: object, seq?: number }
```

**Key Methods:**
- `connect` - Handshake with auth token
- `agent` - Run agent with message
- `send` - Send message to channel
- `health` - Get gateway health
- `status` - Get session status

### 1.5 Skills System Architecture

Skills are the primary extension mechanism:

```
~/clawd/skills/
├── biomate/               # Biomate skill directory
│   ├── SKILL.md           # Skill definition and prompts
│   ├── tools.json         # Tool definitions (optional)
│   └── index.ts           # Skill entry point (optional)
```

**SKILL.md Format:**
```markdown
# Biomate Workflow Generator

## Description
Generate and execute bioinformatics workflows from natural language.

## Tools
- `biomate_generate_workflow` - Generate workflow from description
- `biomate_execute_workflow` - Execute a workflow
- `biomate_status` - Check execution status

## Usage
Use this skill when users want to:
- Analyze genomic/proteomic data
- Run bioinformatics pipelines
- Generate scientific workflows
```

### 1.6 Extension/Plugin System

Clawdbot supports workspace packages for channel extensions:

```
extensions/
├── msteams/          # Microsoft Teams extension
├── matrix/           # Matrix protocol
├── zalo/             # Zalo messaging
├── googlechat/       # Google Chat
├── voice-call/       # Voice calling
└── ...
```

**Plugin SDK exports:**
- `moltbot/plugin-sdk` - Core SDK for building plugins
- Tool definition helpers
- Channel abstraction interfaces

---

## Part 2: Biomate Current State

### 2.1 Architecture Summary

```
React Frontend (Vite)
        │
        ▼
Express Server (Proxy)
        │
        ▼
Galaxy Backend (Port 8080)
        │
        ├── AI Module (Claude LLM)
        ├── Tool Database (7000+ tools)
        ├── Workflow Generator
        └── Job Execution Engine
```

### 2.2 Current Capabilities

| Component | Status | Notes |
|-----------|--------|-------|
| Workflow Generation | Working | LLM-based with validation |
| Tool Database | Complete | 7000+ Galaxy tools indexed |
| Execution Engine | Working | Galaxy job queue |
| Web UI | Functional | React-based chat interface |
| SSE Monitoring | Working | Real-time updates |
| Multi-channel Support | **None** | Web-only |
| Mobile Support | **None** | Browser only |
| Voice Interface | **None** | Text only |

### 2.3 Key APIs to Expose

```typescript
// Workflow generation
POST /api/workflows/generate
Body: { query: string, parameters?: object }
Response: { workflowId: string, workflow: GalaxyWorkflow }

// Workflow execution
POST /api/galaxy/workflows/invoke
Body: { workflowId: string, inputs: object }
Response: { invocationId: string, status: string }

// Execution status
GET /api/galaxy/workflows/sse/:invocationId
Response: SSE stream with progress updates

// Quick query (for messaging)
POST /api/biomate/query
Body: { message: string, sessionId?: string }
Response: { response: string, workflowId?: string }
```

---

## Part 3: Integration Plan

### 3.1 Integration Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    User Messaging Channels                        │
│   WhatsApp │ Telegram │ Slack │ Discord │ Signal │ WebChat       │
└──────────────────────────┬───────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│                   Clawdbot Gateway                                │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                    Biomate Skill                            │  │
│  │  ┌────────────────┬────────────────┬─────────────────────┐ │  │
│  │  │ workflow_query │ workflow_exec  │  workflow_status    │ │  │
│  │  └────────────────┴────────────────┴─────────────────────┘ │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────┬───────────────────────────────────────┘
                           │ HTTP API
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Biomate Backend                                │
│  ┌────────────┬─────────────────┬──────────────────────────────┐ │
│  │ Express    │  Galaxy         │  Claude LLM                  │ │
│  │ Server     │  Backend        │  (Workflow Generation)       │ │
│  └────────────┴─────────────────┴──────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

### 3.2 Implementation Phases

#### Phase 1: Biomate API Adapter (Week 1-2)

**Goal:** Create a messaging-friendly API layer for Biomate

**Tasks:**
1. Create `/api/biomate/chat` endpoint for conversational queries
2. Add session management for multi-turn conversations
3. Implement webhook callbacks for async workflow completion
4. Add message formatting for different channel constraints
5. Create status polling endpoint for long-running workflows

**New Endpoints:**
```typescript
// Chat-style interface for messaging
POST /api/biomate/chat
{
  message: string,
  sessionId: string,
  channel: "whatsapp" | "telegram" | "slack" | "discord" | "web",
  userId: string
}

// Webhook callback registration
POST /api/biomate/webhooks
{
  workflowId: string,
  callbackUrl: string,
  events: ["completed", "failed", "progress"]
}

// Simplified status check
GET /api/biomate/status/:invocationId
```

#### Phase 2: Clawdbot Skill Development (Week 2-3)

**Goal:** Create Biomate skill for Clawdbot

**Directory Structure:**
```
skills/biomate/
├── SKILL.md              # Skill documentation and prompts
├── package.json          # Dependencies (if needed)
├── tools/
│   ├── workflow-query.ts    # Main query tool
│   ├── workflow-execute.ts  # Execution tool
│   ├── workflow-status.ts   # Status checking
│   └── dataset-upload.ts    # File handling
└── config.json           # Biomate server configuration
```

**SKILL.md Content:**
```markdown
# Biomate - Bioinformatics Workflow Assistant

## Overview
Biomate enables natural language generation and execution of bioinformatics
workflows through Galaxy's 7000+ scientific tools.

## Capabilities
- Generate workflows from natural language descriptions
- Execute workflows on genomic, proteomic, metabolomic data
- Track workflow execution status
- Handle file uploads for analysis

## Tools

### biomate_query
Query the biomate system for workflow suggestions or execute tasks.
- `message`: The user's request (required)
- `action`: "suggest" | "execute" | "status" (default: "suggest")

### biomate_upload
Upload a file for analysis.
- `file_path`: Local file path
- `data_type`: "fastq" | "fasta" | "vcf" | "bam" | "csv" | "auto"

### biomate_status
Check the status of a running workflow.
- `invocation_id`: The workflow invocation ID

## Example Interactions

User: "I need to align my RNA-seq reads to the human genome"
Response: Suggests HISAT2 or STAR alignment workflow

User: "Run a variant calling pipeline on my VCF file"
Response: Generates and optionally executes variant annotation workflow

## Configuration
Set BIOMATE_API_URL in your clawdbot config to point to your Biomate server.
```

#### Phase 3: Channel-Specific Optimizations (Week 3-4)

**Goal:** Optimize responses for each messaging channel

**WhatsApp/iMessage Constraints:**
- Max message length: 4096 characters
- Format: Plain text with limited markdown
- Media: Support image attachments for workflow diagrams

**Slack/Discord:**
- Rich formatting: Blocks, embeds, code snippets
- Interactive: Buttons for workflow actions
- Threads: Use threads for workflow progress updates

**Telegram:**
- Inline keyboards for workflow selection
- Long messages: Use telegraph for detailed outputs

**Implementation:**
```typescript
// Channel-aware response formatter
function formatResponse(result: WorkflowResult, channel: string): ChannelMessage {
  switch (channel) {
    case 'slack':
      return formatSlackBlocks(result);
    case 'discord':
      return formatDiscordEmbed(result);
    case 'whatsapp':
    case 'telegram':
      return formatPlainText(result, { maxLength: 4096 });
    default:
      return formatMarkdown(result);
  }
}
```

#### Phase 4: Advanced Features (Week 4-6)

**4a. Multi-Agent Support:**
- Different Biomate instances for different research groups
- Agent routing based on domain (genomics, proteomics, etc.)
- Shared workflow templates across agents

**4b. Voice Interface:**
- Integrate with Clawdbot's Voice Wake for hands-free queries
- Text-to-speech for workflow status updates
- "Hey Biomate, run the variant calling pipeline"

**4c. Canvas Integration:**
- Display workflow DAG on Clawdbot's Live Canvas
- Interactive workflow editing through Canvas A2UI
- Real-time execution visualization

**4d. Proactive Notifications:**
- Cron-based workflow monitoring
- Notify users when long workflows complete
- Daily digest of completed analyses

### 3.3 Configuration

**Biomate Server Config:**
```json
// ~/.clawdbot/moltbot.json
{
  "skills": {
    "biomate": {
      "enabled": true,
      "apiUrl": "http://localhost:5173",
      "apiKey": "${BIOMATE_API_KEY}",
      "webhookSecret": "${BIOMATE_WEBHOOK_SECRET}",
      "defaultAgent": "galaxy-default"
    }
  }
}
```

**Environment Variables:**
```bash
BIOMATE_API_URL=http://localhost:5173
BIOMATE_API_KEY=your-api-key
BIOMATE_WEBHOOK_SECRET=webhook-secret
CLAWDBOT_BIOMATE_ENABLED=1
```

### 3.4 Security Considerations

1. **Authentication:**
   - API key authentication between Clawdbot and Biomate
   - JWT tokens for user identification
   - Per-channel allowlists for Biomate access

2. **Authorization:**
   - Define who can execute workflows (not just query)
   - Rate limiting per user/channel
   - Sandbox execution for untrusted inputs

3. **Data Privacy:**
   - No sensitive data in logs
   - Encrypted webhook payloads
   - Session data isolation

### 3.5 Testing Strategy

**Unit Tests:**
- Biomate skill tool functions
- Response formatting for each channel
- Webhook handling

**Integration Tests:**
- End-to-end message flow
- Workflow generation through Clawdbot
- Multi-channel message delivery

**E2E Tests:**
- Real WhatsApp/Telegram message test
- Voice query test
- Canvas visualization test

---

## Part 4: Implementation Roadmap

### Milestones

| Milestone | Description | Duration | Dependencies |
|-----------|-------------|----------|--------------|
| M1 | Biomate Chat API | 1 week | None |
| M2 | Basic Clawdbot Skill | 1 week | M1 |
| M3 | WhatsApp/Telegram Integration | 1 week | M2 |
| M4 | Slack/Discord Rich Formatting | 1 week | M2 |
| M5 | Webhook Notifications | 3 days | M1 |
| M6 | File Upload Support | 3 days | M2 |
| M7 | Voice Interface | 1 week | M4 |
| M8 | Canvas Visualization | 1 week | M4 |
| M9 | Multi-Agent Routing | 1 week | M4 |

### Quick Start (Minimum Viable Integration)

For a quick proof-of-concept, focus on:

1. **Create simple chat endpoint** (2-3 days)
   ```typescript
   // frontend/server/biomate-chat.ts
   app.post('/api/biomate/chat', async (req, res) => {
     const { message, sessionId } = req.body;
     const result = await galaxyAssistant.chat(message, sessionId);
     res.json({ response: result.text, workflowId: result.workflowId });
   });
   ```

2. **Create minimal skill** (1 day)
   ```markdown
   # skills/biomate/SKILL.md
   # Biomate Workflow Generator

   Use biomate_query tool to interact with the bioinformatics system.
   ```

3. **Test via Clawdbot WebChat** (1 day)
   - Connect Clawdbot Gateway
   - Enable Biomate skill
   - Send test queries through WebChat

---

## Part 5: Benefits Summary

### For Users

| Benefit | Description |
|---------|-------------|
| **Accessibility** | Query workflows from WhatsApp, Telegram, Slack - no browser needed |
| **Mobile-First** | Generate workflows from phone while in the lab |
| **Voice Support** | Hands-free workflow queries during experiments |
| **Notifications** | Get notified when long workflows complete |
| **Collaboration** | Share workflows directly in team Slack/Discord channels |

### For Biomate Platform

| Benefit | Description |
|---------|-------------|
| **Wider Reach** | Access through 12+ messaging platforms |
| **Lower Friction** | Users don't need to remember URLs or login |
| **Session Continuity** | Conversations persist across devices |
| **Platform Agnostic** | One integration, many channels |
| **Community Growth** | Leverage Clawdbot's 60k+ star community |

### Technical Benefits

| Benefit | Description |
|---------|-------------|
| **Mature Infrastructure** | Battle-tested messaging adapters |
| **Security Built-in** | Pairing, allowlists, sandboxing |
| **Extensible** | Add new channels without code changes |
| **Observable** | Unified logging and monitoring |
| **Maintainable** | Separation of concerns (messaging vs. science) |

---

## References

- Clawdbot Repository: https://github.com/clawdbot/clawdbot
- Clawdbot Docs: https://docs.molt.bot
- Galaxy Project: https://galaxyproject.org
- Biomate Backend: `/home/yzhang/biomate/backend/`
- Biomate Frontend: `/home/yzhang/biomate/frontend/`

---

## Appendix A: Clawdbot CLI Quick Reference

```bash
# Install Clawdbot
npm install -g moltbot@latest

# Run onboarding wizard
moltbot onboard --install-daemon

# Start gateway
moltbot gateway --port 18789 --verbose

# Check channel status
moltbot channels status --probe

# Send test message
moltbot message send --to +1234567890 --message "Test from Biomate"

# Run agent query
moltbot agent --message "Generate RNA-seq workflow"

# List skills
moltbot skills list

# Install skill
moltbot skills install biomate
```

## Appendix B: Sample Tool Implementation

```typescript
// skills/biomate/tools/workflow-query.ts
import { defineTool } from 'moltbot/plugin-sdk';

export const workflowQueryTool = defineTool({
  name: 'biomate_query',
  description: 'Query Biomate for bioinformatics workflow suggestions or execution',
  parameters: {
    type: 'object',
    properties: {
      message: {
        type: 'string',
        description: 'The user query about bioinformatics workflows'
      },
      action: {
        type: 'string',
        enum: ['suggest', 'execute', 'refine'],
        default: 'suggest',
        description: 'The action to perform'
      }
    },
    required: ['message']
  },
  async execute({ message, action }, context) {
    const apiUrl = context.config.get('skills.biomate.apiUrl');
    const response = await fetch(`${apiUrl}/api/biomate/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message,
        action,
        sessionId: context.session.id,
        channel: context.channel.type
      })
    });

    const result = await response.json();
    return {
      text: result.response,
      metadata: {
        workflowId: result.workflowId,
        toolsUsed: result.tools
      }
    };
  }
});
```
