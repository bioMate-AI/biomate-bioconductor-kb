# ACE Learning System Integration for BioMate
**Date**: October 30, 2025
**Purpose**: Integrate Agentic Context Engineering (ACE) framework into BioMate's codeless chat interface to enable self-improving workflow generation

---

## Executive Summary

This document outlines how to integrate the ACE (Agentic Context Engineering) framework into BioMate's existing chat-based workflow generation system. The integration happens **entirely in the backend**, preserving the codeless user interface while enabling the system to learn from execution feedback and improve tool selection accuracy over time.

**Key Benefits**:
- **Self-Improvement**: System learns from workflow execution failures to prevent repeated mistakes
- **No UI Changes**: All learning happens transparently in the backend
- **Backward Compatible**: Existing workflows continue to work unchanged
- **Measurable Impact**: Expected +4-10% improvement in tool selection accuracy (based on ACE paper results)

---

## Current BioMate Architecture (Chat-Based)

### User Interaction Flow
```
┌─────────────────────────────────────────────────────────────┐
│                     User Types Message                       │
│              "Analyze my DIA proteomics data"                │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              ChatInterface Component (Frontend)              │
│  File: frontend/client/src/components/chat-interface.tsx    │
│  Line 467-498: handleSendMessage()                          │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼ POST /api/ai_assistant/generate_workflow
┌─────────────────────────────────────────────────────────────┐
│              GalaxyAssistant (Backend Service)               │
│  File: frontend/server/galaxy-assistant.ts                  │
│                                                              │
│  processMessage() Pipeline:                                 │
│  1. analyzeIntent() - Extract keywords via Claude           │
│  2. searchRelevantTools() - Search 2,177 Galaxy tools       │
│  3. rankToolsByRelevance() ← 🎯 ACE INTEGRATION POINT #1    │
│  4. searchRelevantDatasets() - BioMNI dataset RAG           │
│  5. generateWorkflow() - Call unified Galaxy API            │
│  6. generateResponse() - Natural language response          │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              Workflow Execution & Monitoring                 │
│  Files: workflow-sse.ts, galaxy-state-poller.ts             │
│                                                              │
│  GalaxyStatePoller:                                         │
│  - Polls Galaxy API every 2s for invocation state           │
│  - Detects step state changes (running → ok/error)          │
│  - Fetches job logs when steps complete                     │
│  - Emits events: workflow_state, step_state, error          │
│                                                              │
│  WorkflowSSEManager:                                        │
│  - Broadcasts real-time updates to frontend via SSE         │
│  - Streams: workflow progress, step status, logs, errors    │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼ Execution Results
┌─────────────────────────────────────────────────────────────┐
│              WorkflowRepository (Storage)                    │
│  File: frontend/server/workflow-repository.ts               │
│  Line 185-206: recordUsage(templateId, success)             │
│                ← 🎯 ACE INTEGRATION POINT #2                 │
│                                                              │
│  Tracks: usage_count, success_rate, average_runtime         │
└─────────────────────────────────────────────────────────────┘
```

### Key Characteristics
1. **Chat-Based UI**: Users interact through natural language, not commands
2. **Codeless**: No slash commands, no file paths, no coding required
3. **Hybrid Intelligence**: Claude NLU + Galaxy Tool Search + BioMNI Dataset RAG
4. **Real-Time Feedback**: SSE streams workflow execution progress to frontend
5. **Template-Based**: Reuses validated workflow templates when possible

---

## ACE Framework Overview

### Three-Agent Architecture
```
┌────────────────────────────────────────────────────────────┐
│                      ACE Framework                          │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │  Generator   │  │  Reflector   │  │   Curator    │    │
│  │              │  │              │  │              │    │
│  │ Executes     │  │ Analyzes     │  │ Updates      │    │
│  │ tasks using  │  │ failures and │  │ playbook with│    │
│  │ playbook     │  │ extracts     │  │ learned      │    │
│  │ rules        │  │ insights     │  │ rules        │    │
│  └──────┬───────┘  └──────▲───────┘  └──────┬───────┘    │
│         │                  │                  │            │
│         │ Execution        │ Failure          │ Updated    │
│         │ Attempt          │ Logs             │ Playbook   │
│         │                  │                  │            │
│         ▼                  │                  ▼            │
│  ┌──────────────────────────────────────────────────────┐ │
│  │              Playbook (Knowledge Base)               │ │
│  │                                                      │ │
│  │  Rules: "For DIA data, never use MaxQuant (DDA)"   │ │
│  │  Counters: Helpful: 15, Harmful: 2                 │ │
│  │  Confidence: 0.88                                   │ │
│  └──────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────┘
```

### Core Concepts
1. **Playbook**: Structured knowledge base with itemized rules
2. **Incremental Delta Updates**: Small, deterministic changes to prevent context collapse
3. **Helpful/Harmful Counters**: Track rule effectiveness over time
4. **Execution Feedback Learning**: No labels needed, learns from natural signals (success/failure)
5. **Grow-and-Refine**: Balance knowledge growth with deduplication

---

## Integration Architecture

### Where ACE Fits in BioMate

```
┌─────────────────────────────────────────────────────────────┐
│                   User Chat Message                          │
│          "Analyze my DIA proteomics data"                    │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              GalaxyAssistant.processMessage()                │
│                                                              │
│  1. analyzeIntent() → "DIA proteomics, quantification"      │
│  2. searchRelevantTools() → 30 candidate tools              │
│  3. rankToolsByRelevance() ← 🔥 ACE PLAYBOOK INJECTION      │
│     ┌─────────────────────────────────────────────────┐    │
│     │  BEFORE (Current):                              │    │
│     │  - Uses Claude with general bioinformatics      │    │
│     │    knowledge only                               │    │
│     │  - No memory of past mistakes                   │    │
│     │                                                  │    │
│     │  AFTER (With ACE):                              │    │
│     │  - Injects learned rules into system prompt     │    │
│     │  - "For DIA data, NEVER use MaxQuant (DDA)"    │    │
│     │  - "For DIA quantification, prefer DIA-NN"     │    │
│     │  - Sorted by helpful/harmful ratio             │    │
│     └─────────────────────────────────────────────────┘    │
│  4. generateWorkflow() → Complete workflow with steps       │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼ Workflow Execution
┌─────────────────────────────────────────────────────────────┐
│              Workflow Execution Monitoring                   │
│  GalaxyStatePoller.fetchJobLogs()                           │
│                                                              │
│  Captures Errors: ← 🔥 ACE REFLECTOR INPUT                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ STDERR from Step 2 (MaxQuant):                      │   │
│  │ "Error: Input file is DIA-MS data. MaxQuant only   │   │
│  │  supports DDA acquisition. Please use DIA-NN or    │   │
│  │  Spectronaut instead."                              │   │
│  │                                                      │   │
│  │ Job State: error                                     │   │
│  │ Step: 2/5                                           │   │
│  │ Tool: MaxQuant                                      │   │
│  │ User Intent: "DIA proteomics analysis"              │   │
│  └─────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────┘
                           │ Error Event
                           ▼
┌─────────────────────────────────────────────────────────────┐
│         🔥 ACE REFLECTOR SERVICE (NEW)                       │
│  File: frontend/server/ace-reflector.ts                     │
│                                                              │
│  analyzeFailure(errorLog, stepInfo, userIntent):            │
│  1. Extract failure pattern using Claude:                   │
│     - Tool: MaxQuant                                        │
│     - Data Type: DIA                                        │
│     - Reason: Incompatible (DDA-only tool)                 │
│     - Alternative: DIA-NN, Spectronaut                     │
│                                                              │
│  2. Generate delta update:                                  │
│     {                                                        │
│       "rule": "For DIA proteomics data, never use          │
│                MaxQuant (DDA-only tool)",                  │
│       "trigger": "DIA data analysis",                       │
│       "harmful_tool": "MaxQuant",                          │
│       "recommended_tool": "DIA-NN",                        │
│       "evidence": "Job stderr: MaxQuant only supports DDA" │
│     }                                                        │
└──────────────────────────┬──────────────────────────────────┘
                           │ Delta Update
                           ▼
┌─────────────────────────────────────────────────────────────┐
│         🔥 ACE CURATOR SERVICE (NEW)                         │
│  File: frontend/server/ace-curator.ts                       │
│                                                              │
│  processUpdate(deltaUpdate):                                │
│  1. Check if rule already exists in playbook                │
│  2. If exists: increment harmful counter for MaxQuant       │
│  3. If new: add rule with initial counters (h:0, h:1)      │
│  4. Update playbook database                                │
│  5. Prune low-confidence rules (h/(h+h) < 0.3)             │
│                                                              │
│  Result:                                                     │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Playbook Entry:                                      │   │
│  │ - Rule: "For DIA data, never use MaxQuant"          │   │
│  │ - Helpful: 0, Harmful: 1                            │   │
│  │ - Confidence: 0.0 (needs more evidence)             │   │
│  │ - Created: 2025-10-30 14:32:15                      │   │
│  │                                                      │   │
│  │ After 5 more DIA failures with MaxQuant:            │   │
│  │ - Helpful: 0, Harmful: 6                            │   │
│  │ - Confidence: 0.0 (strong negative evidence)        │   │
│  │                                                      │   │
│  │ After 10 DIA successes with DIA-NN:                 │   │
│  │ - DIA-NN Rule: Helpful: 10, Harmful: 0              │   │
│  │ - Confidence: 1.0 (strong positive evidence)        │   │
│  └─────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│         🔥 PLAYBOOK DATABASE (NEW)                           │
│  File: frontend/server/playbook-database.ts                 │
│  Storage: PostgreSQL table: ace_playbook_rules              │
│                                                              │
│  Schema:                                                     │
│  - id: UUID                                                  │
│  - rule_text: TEXT                                          │
│  - trigger_keywords: TEXT[]                                 │
│  - harmful_tools: TEXT[]                                    │
│  - recommended_tools: TEXT[]                                │
│  - helpful_count: INTEGER                                   │
│  - harmful_count: INTEGER                                   │
│  - confidence: FLOAT (computed)                             │
│  - evidence: JSONB (execution logs)                         │
│  - created_at: TIMESTAMP                                    │
│  - updated_at: TIMESTAMP                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Details

### 1. Playbook Database Schema

**File**: `frontend/server/playbook-database.ts`

```typescript
import { pgTable, uuid, text, integer, real, jsonb, timestamp } from 'drizzle-orm/pg-core';
import { db } from './db';
import { eq, and, desc, sql } from 'drizzle-orm';

// Database schema
export const acePlaybookRules = pgTable('ace_playbook_rules', {
  id: uuid('id').primaryKey().defaultRandom(),

  // Rule content
  ruleText: text('rule_text').notNull(),
  triggerKeywords: text('trigger_keywords').array().notNull(), // e.g., ['DIA', 'proteomics']

  // Tool recommendations
  harmfulTools: text('harmful_tools').array().notNull(), // Tools to avoid
  recommendedTools: text('recommended_tools').array().notNull(), // Tools to prefer

  // Counters (ACE framework)
  helpfulCount: integer('helpful_count').default(0).notNull(),
  harmfulCount: integer('harmful_count').default(0).notNull(),

  // Computed confidence = helpful / (helpful + harmful)
  confidence: real('confidence').default(0).notNull(),

  // Evidence
  evidence: jsonb('evidence').$type<{
    successes: Array<{ workflowId: string; timestamp: string }>;
    failures: Array<{ workflowId: string; errorLog: string; timestamp: string }>;
  }>().notNull(),

  // Metadata
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});

export type PlaybookRule = typeof acePlaybookRules.$inferSelect;
export type NewPlaybookRule = typeof acePlaybookRules.$inferInsert;

/**
 * Playbook Database Manager
 */
export class PlaybookDatabase {
  /**
   * Add new rule or increment existing rule counters
   */
  async upsertRule(
    ruleText: string,
    triggerKeywords: string[],
    harmfulTools: string[],
    recommendedTools: string[],
    isSuccess: boolean,
    evidenceData: { workflowId: string; errorLog?: string }
  ): Promise<PlaybookRule> {
    // Check if similar rule exists
    const existing = await db.query.acePlaybookRules.findFirst({
      where: and(
        sql`${acePlaybookRules.harmfulTools} && ${harmfulTools}`,
        sql`${acePlaybookRules.triggerKeywords} && ${triggerKeywords}`
      ),
    });

    if (existing) {
      // Update existing rule
      const newHelpful = isSuccess ? existing.helpfulCount + 1 : existing.helpfulCount;
      const newHarmful = !isSuccess ? existing.harmfulCount + 1 : existing.harmfulCount;
      const newConfidence = newHelpful / (newHelpful + newHarmful);

      // Update evidence
      const newEvidence = { ...existing.evidence };
      if (isSuccess) {
        newEvidence.successes.push({ workflowId: evidenceData.workflowId, timestamp: new Date().toISOString() });
      } else {
        newEvidence.failures.push({
          workflowId: evidenceData.workflowId,
          errorLog: evidenceData.errorLog || '',
          timestamp: new Date().toISOString(),
        });
      }

      await db
        .update(acePlaybookRules)
        .set({
          helpfulCount: newHelpful,
          harmfulCount: newHarmful,
          confidence: newConfidence,
          evidence: newEvidence,
          updatedAt: new Date(),
        })
        .where(eq(acePlaybookRules.id, existing.id));

      return { ...existing, helpfulCount: newHelpful, harmfulCount: newHarmful, confidence: newConfidence };
    } else {
      // Insert new rule
      const [newRule] = await db
        .insert(acePlaybookRules)
        .values({
          ruleText,
          triggerKeywords,
          harmfulTools,
          recommendedTools,
          helpfulCount: isSuccess ? 1 : 0,
          harmfulCount: !isSuccess ? 1 : 0,
          confidence: isSuccess ? 1.0 : 0.0,
          evidence: {
            successes: isSuccess ? [{ workflowId: evidenceData.workflowId, timestamp: new Date().toISOString() }] : [],
            failures: !isSuccess ? [{ workflowId: evidenceData.workflowId, errorLog: evidenceData.errorLog || '', timestamp: new Date().toISOString() }] : [],
          },
        })
        .returning();

      return newRule;
    }
  }

  /**
   * Get relevant rules for a user query
   */
  async getRelevantRules(keywords: string[], minConfidence: number = 0.5): Promise<PlaybookRule[]> {
    const rules = await db.query.acePlaybookRules.findMany({
      where: and(
        sql`${acePlaybookRules.triggerKeywords} && ${keywords}`,
        sql`${acePlaybookRules.confidence} >= ${minConfidence}`
      ),
      orderBy: [desc(acePlaybookRules.confidence), desc(acePlaybookRules.helpfulCount)],
    });

    return rules;
  }

  /**
   * Prune low-confidence rules (garbage collection)
   */
  async pruneLowConfidenceRules(minConfidence: number = 0.3, minEvidence: number = 5): Promise<number> {
    const result = await db
      .delete(acePlaybookRules)
      .where(
        and(
          sql`${acePlaybookRules.confidence} < ${minConfidence}`,
          sql`${acePlaybookRules.helpfulCount} + ${acePlaybookRules.harmfulCount} >= ${minEvidence}`
        )
      );

    return result.rowCount || 0;
  }

  /**
   * Get all rules (for debugging/admin)
   */
  async getAllRules(): Promise<PlaybookRule[]> {
    return db.query.acePlaybookRules.findMany({
      orderBy: [desc(acePlaybookRules.confidence)],
    });
  }
}

export const playbookDatabase = new PlaybookDatabase();
```

### 2. ACE Reflector Service

**File**: `frontend/server/ace-reflector.ts`

```typescript
import Anthropic from '@anthropic-ai/sdk';
import type { WorkflowExecutionUpdate } from '../shared/galaxy-types';

export interface FailureAnalysis {
  failedTool: string;
  userIntent: string;
  dataType: string;
  errorReason: string;
  suggestedAlternatives: string[];
  ruleText: string;
  triggerKeywords: string[];
}

/**
 * ACE Reflector Service
 * Analyzes workflow execution failures and extracts learnable patterns
 */
export class ACEReflector {
  private claude: Anthropic;

  constructor(anthropicApiKey: string) {
    this.claude = new Anthropic({ apiKey: anthropicApiKey });
  }

  /**
   * Analyze a workflow execution failure
   * Extract tool incompatibility patterns for playbook update
   */
  async analyzeFailure(
    errorLog: string,
    stepInfo: { stepId: string; toolId: string; toolName: string },
    userIntent: string,
    workflowId: string
  ): Promise<FailureAnalysis | null> {
    const systemPrompt = `You are an expert in bioinformatics tool compatibility analysis.

Your task: Analyze workflow execution errors and extract learnable rules.

Focus on:
1. Tool incompatibilities (e.g., MaxQuant for DIA data when it only supports DDA)
2. Data format mismatches (e.g., FASTQ vs BAM, mzML vs mzXML)
3. Parameter constraints (e.g., FDR threshold too strict, missing required inputs)
4. Tool chain compatibility (e.g., tool A output incompatible with tool B input)

For EVERY analysis, extract:
- Failed tool name
- Data type/format involved
- Reason for failure (be specific)
- Alternative tools that would work
- A concise rule statement

Respond in JSON format ONLY. Example:
{
  "failedTool": "MaxQuant",
  "dataType": "DIA proteomics",
  "errorReason": "MaxQuant only supports DDA acquisition, not DIA",
  "suggestedAlternatives": ["DIA-NN", "Spectronaut"],
  "ruleText": "For DIA proteomics data, never use MaxQuant (DDA-only). Use DIA-NN or Spectronaut instead.",
  "triggerKeywords": ["DIA", "proteomics", "data-independent acquisition"]
}`;

    const userPrompt = `Workflow Execution Error:

**User Intent**: ${userIntent}

**Failed Step**: ${stepInfo.toolName} (${stepInfo.toolId})

**Error Log**:
${errorLog}

**Workflow ID**: ${workflowId}

Extract the learnable rule from this failure. If this is not a tool incompatibility issue (e.g., network error, resource exhaustion), return null.`;

    try {
      const completion = await this.claude.messages.create({
        model: 'claude-sonnet-4-5',
        max_tokens: 500,
        temperature: 0.3,
        system: systemPrompt,
        messages: [{ role: 'user', content: userPrompt }],
      });

      const content = completion.content[0];
      let resultText = content.type === 'text' ? content.text : '{}';

      // Strip markdown code blocks
      resultText = resultText.replace(/^```json\s*\n?/i, '').replace(/\n?```\s*$/i, '').trim();

      const analysis: FailureAnalysis = JSON.parse(resultText);

      // Validate analysis
      if (!analysis.failedTool || !analysis.ruleText) {
        console.log('[ACEReflector] Invalid analysis result, skipping');
        return null;
      }

      console.log('[ACEReflector] ✅ Extracted rule:', analysis.ruleText);
      return analysis;
    } catch (error) {
      console.error('[ACEReflector] Failed to analyze failure:', error);
      return null;
    }
  }

  /**
   * Analyze a workflow execution success
   * Extract positive reinforcement for tool selection
   */
  async analyzeSuccess(
    stepInfo: { stepId: string; toolId: string; toolName: string },
    userIntent: string,
    workflowId: string
  ): Promise<{ tool: string; dataType: string; keywords: string[] } | null> {
    const systemPrompt = `Extract the data type and keywords from this successful workflow execution.

Respond in JSON format:
{
  "tool": "DIA-NN",
  "dataType": "DIA proteomics",
  "keywords": ["DIA", "proteomics", "quantification"]
}`;

    const userPrompt = `Successful Workflow:

**User Intent**: ${userIntent}
**Successful Tool**: ${stepInfo.toolName} (${stepInfo.toolId})
**Workflow ID**: ${workflowId}

Extract data type and keywords.`;

    try {
      const completion = await this.claude.messages.create({
        model: 'claude-sonnet-4-5',
        max_tokens: 300,
        temperature: 0.3,
        system: systemPrompt,
        messages: [{ role: 'user', content: userPrompt }],
      });

      const content = completion.content[0];
      let resultText = content.type === 'text' ? content.text : '{}';
      resultText = resultText.replace(/^```json\s*\n?/i, '').replace(/\n?```\s*$/i, '').trim();

      const analysis = JSON.parse(resultText);
      return analysis;
    } catch (error) {
      console.error('[ACEReflector] Failed to analyze success:', error);
      return null;
    }
  }
}
```

### 3. ACE Curator Service

**File**: `frontend/server/ace-curator.ts`

```typescript
import { playbookDatabase, type PlaybookRule } from './playbook-database';
import type { FailureAnalysis } from './ace-reflector';

/**
 * ACE Curator Service
 * Updates playbook with new rules from Reflector insights
 */
export class ACECurator {
  /**
   * Process a failure analysis and update playbook
   */
  async processFailure(analysis: FailureAnalysis, workflowId: string): Promise<void> {
    console.log('[ACECurator] Processing failure analysis:', analysis.ruleText);

    await playbookDatabase.upsertRule(
      analysis.ruleText,
      analysis.triggerKeywords,
      [analysis.failedTool], // Harmful tools
      analysis.suggestedAlternatives, // Recommended tools
      false, // isSuccess = false
      { workflowId, errorLog: analysis.errorReason }
    );

    console.log('[ACECurator] ✅ Updated playbook with failure rule');
  }

  /**
   * Process a success and update playbook
   */
  async processSuccess(
    successData: { tool: string; dataType: string; keywords: string[] },
    workflowId: string
  ): Promise<void> {
    console.log('[ACECurator] Processing success for tool:', successData.tool);

    const ruleText = `For ${successData.dataType}, ${successData.tool} is effective`;

    await playbookDatabase.upsertRule(
      ruleText,
      successData.keywords,
      [], // No harmful tools
      [successData.tool], // Recommended tool
      true, // isSuccess = true
      { workflowId }
    );

    console.log('[ACECurator] ✅ Updated playbook with success rule');
  }

  /**
   * Periodic maintenance: prune low-confidence rules
   */
  async performMaintenance(): Promise<void> {
    console.log('[ACECurator] Running playbook maintenance...');

    const pruned = await playbookDatabase.pruneLowConfidenceRules(0.3, 5);

    console.log(`[ACECurator] ✅ Pruned ${pruned} low-confidence rules`);
  }

  /**
   * Get playbook summary statistics
   */
  async getStatistics(): Promise<{
    totalRules: number;
    highConfidenceRules: number;
    recentUpdates: number;
  }> {
    const allRules = await playbookDatabase.getAllRules();

    const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);

    return {
      totalRules: allRules.length,
      highConfidenceRules: allRules.filter(r => r.confidence >= 0.8).length,
      recentUpdates: allRules.filter(r => new Date(r.updatedAt) > oneDayAgo).length,
    };
  }
}

export const aceCurator = new ACECurator();
```

### 4. Integrate ACE into GalaxyAssistant (Tool Ranking)

**File**: `frontend/server/galaxy-assistant.ts`

**Modifications to `rankToolsByRelevance()` method** (Line 306-382):

```typescript
/**
 * Rank tools by relevance using LLM + ACE Playbook
 */
private async rankToolsByRelevance(
  userMessage: string,
  tools: GalaxyTool[],
  intent?: any // From analyzeIntent()
): Promise<ToolRecommendation[]> {
  // 🔥 NEW: Get relevant playbook rules
  const keywords = intent?.keywords || [];
  const playbookRules = await playbookDatabase.getRelevantRules(keywords, 0.5);

  // 🔥 NEW: Format playbook rules for system prompt
  const playbookGuidance = playbookRules.length > 0
    ? `\n\nLEARNED RULES (from previous workflow executions):\n${playbookRules
        .map(
          (rule, i) =>
            `${i + 1}. ${rule.ruleText} (confidence: ${(rule.confidence * 100).toFixed(1)}%, evidence: ${rule.helpfulCount + rule.harmfulCount} workflows)`
        )
        .join('\n')}\n\nIMPORTANT: Prioritize these learned rules when ranking tools.`
    : '';

  const systemPrompt = `You are a bioinformatics tool expert. Rank the provided tools by relevance to the user's request.
For each tool, provide:
1. Relevance score (0-1)
2. Brief reasoning
${playbookGuidance}

Respond in JSON format:
[
  {
    "tool_id": "tool_123",
    "relevanceScore": 0.95,
    "reasoning": "Perfect match for RNA-seq alignment"
  }
]`;

  const toolCatalog = tools
    .map(
      (t, i) =>
        `${i + 1}. ${t.name} (${t.tool_id})
   Category: ${t.category || 'N/A'}
   Keywords: ${t.keywords || 'N/A'}`
    )
    .join('\n\n');

  try {
    const completion = await this.claude.messages.create({
      model: 'claude-sonnet-4-5',
      max_tokens: 500,
      temperature: 0.3,
      system: [
        {
          type: 'text',
          text: systemPrompt,
          cache_control: { type: 'ephemeral' },
        },
      ],
      messages: [
        {
          role: 'user',
          content: `User request: ${userMessage}\n\nAvailable tools:\n${toolCatalog}`,
        },
      ],
    });

    const content = completion.content[0];
    let resultText = content.type === 'text' ? content.text : '{"rankings":[]}';

    // Strip markdown code blocks if present
    resultText = resultText.replace(/^```json\s*\n?/i, '').replace(/\n?```\s*$/i, '').trim();

    const rankings = JSON.parse(resultText);
    const rankingArray = rankings.rankings || rankings;

    // 🔥 NEW: Apply playbook penalties/bonuses
    const rankedTools = tools
      .map((tool) => {
        const ranking = rankingArray.find((r: any) => r.tool_id === tool.tool_id);
        let score = ranking?.relevanceScore || 0.5;

        // Check if tool is in harmful list
        for (const rule of playbookRules) {
          if (rule.harmfulTools.includes(tool.tool_id) || rule.harmfulTools.includes(tool.name)) {
            // Apply penalty based on confidence
            score *= (1 - rule.confidence * 0.5); // Max 50% penalty
            console.log(`[GalaxyAssistant] Applied playbook penalty to ${tool.name}: ${score.toFixed(2)} (rule: ${rule.ruleText})`);
          }
          if (rule.recommendedTools.includes(tool.tool_id) || rule.recommendedTools.includes(tool.name)) {
            // Apply bonus based on confidence
            score = Math.min(1.0, score + rule.confidence * 0.2); // Max 20% bonus
            console.log(`[GalaxyAssistant] Applied playbook bonus to ${tool.name}: ${score.toFixed(2)} (rule: ${rule.ruleText})`);
          }
        }

        return {
          tool,
          relevanceScore: score,
          reasoning: ranking?.reasoning || 'Potentially relevant',
        };
      })
      .filter((r) => r.relevanceScore > 0.3)
      .sort((a, b) => b.relevanceScore - a.relevanceScore)
      .slice(0, 5);

    console.log(`[GalaxyAssistant] Tool ranking with ${playbookRules.length} playbook rules applied`);
    return rankedTools;
  } catch (error) {
    console.error('[GalaxyAssistant] Tool ranking failed:', error);
    return tools.slice(0, 5).map((tool) => ({
      tool,
      relevanceScore: 0.5,
      reasoning: 'Retrieved from tool search',
    }));
  }
}
```

### 5. Integrate ACE into Workflow Execution Monitoring

**File**: `frontend/server/galaxy-state-poller.ts`

**Add ACE feedback collection** (after Line 288):

```typescript
import { ACEReflector } from './ace-reflector';
import { aceCurator } from './ace-curator';

export class GalaxyStatePoller extends EventEmitter {
  // ... existing code ...

  private aceReflector: ACEReflector | null = null;
  private workflowIntents: Map<string, string> = new Map(); // invocationId -> userIntent

  constructor(api: any, options: PollerOptions = {}) {
    super();
    this.api = api;
    this.pollInterval = options.pollInterval || 2000;
    this.maxRetries = options.maxRetries || 5;

    // 🔥 NEW: Initialize ACE Reflector if API key available
    if (process.env.ANTHROPIC_API_KEY) {
      this.aceReflector = new ACEReflector(process.env.ANTHROPIC_API_KEY);
    }
  }

  /**
   * 🔥 NEW: Set user intent for an invocation (for ACE learning)
   */
  setWorkflowIntent(invocationId: string, userIntent: string): void {
    this.workflowIntents.set(invocationId, userIntent);
  }

  /**
   * Fetch job logs and emit as events
   * 🔥 MODIFIED: Add ACE failure analysis
   */
  private async fetchJobLogs(invocationId: string, stepId: string, jobId?: string): Promise<void> {
    if (!jobId) return;

    try {
      const [stdout, stderr] = await Promise.all([
        this.api.getJobStdout(jobId),
        this.api.getJobStderr(jobId),
      ]);

      if (stdout) {
        this.emitUpdate({
          type: 'job_log',
          invocation_id: invocationId,
          timestamp: new Date().toISOString(),
          data: {
            step_id: stepId,
            job_id: jobId,
            log_message: `STDOUT:\n${stdout}`,
          },
        });
      }

      if (stderr) {
        const isError = stderr.includes('error') || stderr.includes('Error') || stderr.includes('failed');

        this.emitUpdate({
          type: isError ? 'error' : 'job_log',
          invocation_id: invocationId,
          timestamp: new Date().toISOString(),
          data: {
            step_id: stepId,
            job_id: jobId,
            log_message: `STDERR:\n${stderr}`,
            error: stderr,
          },
        });

        // 🔥 NEW: ACE Reflector analysis for errors
        if (isError && this.aceReflector) {
          const userIntent = this.workflowIntents.get(invocationId);
          if (userIntent) {
            console.log('[GalaxyStatePoller] 🧠 Analyzing failure with ACE Reflector...');

            // Get step info from poller state
            const invocation = this.pollers.get(invocationId)?.lastState;
            const step = invocation?.steps.find(s => s.id === stepId);

            if (step) {
              const analysis = await this.aceReflector.analyzeFailure(
                stderr,
                { stepId: step.id, toolId: step.tool_id || 'unknown', toolName: step.name || 'Unknown' },
                userIntent,
                invocationId
              );

              if (analysis) {
                console.log('[GalaxyStatePoller] ✅ ACE analysis complete, updating playbook...');
                await aceCurator.processFailure(analysis, invocationId);
              }
            }
          }
        }
      }
    } catch (error: any) {
      console.error(`Failed to fetch logs for job ${jobId}:`, error.message);
    }
  }

  /**
   * 🔥 NEW: Record workflow success for ACE learning
   */
  private async recordWorkflowSuccess(invocationId: string): Promise<void> {
    if (!this.aceReflector) return;

    const userIntent = this.workflowIntents.get(invocationId);
    if (!userIntent) return;

    const invocation = this.pollers.get(invocationId)?.lastState;
    if (!invocation) return;

    console.log('[GalaxyStatePoller] 🧠 Recording successful workflow for ACE...');

    // Analyze successful tools
    for (const step of invocation.steps) {
      if (step.state === 'ok') {
        const successData = await this.aceReflector.analyzeSuccess(
          { stepId: step.id, toolId: step.tool_id || 'unknown', toolName: step.name || 'Unknown' },
          userIntent,
          invocationId
        );

        if (successData) {
          await aceCurator.processSuccess(successData, invocationId);
        }
      }
    }
  }

  /**
   * Check if workflow is complete
   * 🔥 MODIFIED: Add ACE success recording
   */
  private isWorkflowComplete(invocation: GalaxyWorkflowInvocation): boolean {
    // Terminal states
    if (this.isTerminalState(invocation.state)) {
      return true;
    }

    // Check if all steps are complete
    if (invocation.steps.length > 0) {
      const allStepsComplete = invocation.steps.every(
        step => step.state === 'ok' || step.state === 'error'
      );

      // 🔥 NEW: Record success for ACE if all steps OK
      if (allStepsComplete && invocation.steps.every(s => s.state === 'ok')) {
        this.recordWorkflowSuccess(invocation.id).catch(err =>
          console.error('[GalaxyStatePoller] Failed to record success:', err)
        );
      }

      return allStepsComplete;
    }

    return false;
  }
}
```

### 6. Wire Everything Together in Routes

**File**: `frontend/server/routes.ts`

**Add ACE initialization** (after line 50):

```typescript
import { playbookDatabase } from './playbook-database';
import { aceCurator } from './ace-curator';

// Initialize playbook database
await playbookDatabase.initialize().catch(err => {
  console.error('[Routes] Failed to initialize ACE playbook database:', err);
});

// Schedule periodic playbook maintenance (every 6 hours)
setInterval(() => {
  aceCurator.performMaintenance().catch(err => {
    console.error('[Routes] ACE maintenance failed:', err);
  });
}, 6 * 60 * 60 * 1000);

console.log('[Routes] ✅ ACE learning system initialized');
```

**Add workflow intent tracking** (when workflow is generated):

```typescript
// When workflow is generated and executed
app.post('/api/workflows/:workflowId/execute', async (req, res) => {
  const { workflowId } = req.params;
  const { invocationId, userIntent } = req.body;

  // Track user intent for ACE learning
  if (userIntent && galaxyStatePoller) {
    galaxyStatePoller.setWorkflowIntent(invocationId, userIntent);
  }

  // ... rest of execution logic ...
});
```

---

## Testing & Validation

### Phase 1: Unit Tests (Week 1-2)

```typescript
// tests/ace-playbook.test.ts
describe('ACE Playbook Database', () => {
  it('should upsert new rule on first failure', async () => {
    const rule = await playbookDatabase.upsertRule(
      'For DIA data, never use MaxQuant',
      ['DIA', 'proteomics'],
      ['MaxQuant'],
      ['DIA-NN'],
      false,
      { workflowId: 'test-1', errorLog: 'MaxQuant only supports DDA' }
    );

    expect(rule.harmfulCount).toBe(1);
    expect(rule.confidence).toBe(0.0);
  });

  it('should increment harmful counter on repeated failure', async () => {
    // Second failure with MaxQuant on DIA data
    const rule = await playbookDatabase.upsertRule(
      'For DIA data, never use MaxQuant',
      ['DIA', 'proteomics'],
      ['MaxQuant'],
      ['DIA-NN'],
      false,
      { workflowId: 'test-2', errorLog: 'MaxQuant only supports DDA' }
    );

    expect(rule.harmfulCount).toBe(2);
    expect(rule.confidence).toBe(0.0);
  });

  it('should retrieve relevant rules by keywords', async () => {
    const rules = await playbookDatabase.getRelevantRules(['DIA', 'proteomics'], 0.0);

    expect(rules.length).toBeGreaterThan(0);
    expect(rules[0].ruleText).toContain('MaxQuant');
  });
});
```

### Phase 2: Integration Tests (Week 3-4)

```typescript
// tests/ace-integration.test.ts
describe('ACE Reflector + Curator Integration', () => {
  it('should analyze workflow failure and update playbook', async () => {
    const reflector = new ACEReflector(process.env.ANTHROPIC_API_KEY!);
    const curator = new ACECurator();

    // Simulate workflow failure
    const analysis = await reflector.analyzeFailure(
      'Error: MaxQuant cannot process DIA-MS data. Only DDA is supported.',
      { stepId: '2', toolId: 'maxquant', toolName: 'MaxQuant' },
      'Analyze my DIA proteomics data',
      'workflow-123'
    );

    expect(analysis).not.toBeNull();
    expect(analysis!.failedTool).toBe('MaxQuant');

    // Update playbook
    await curator.processFailure(analysis!, 'workflow-123');

    // Verify rule was added
    const rules = await playbookDatabase.getRelevantRules(['DIA', 'proteomics']);
    expect(rules.length).toBeGreaterThan(0);
  });
});
```

### Phase 3: End-to-End Tests (Week 5-6)

**Test Scenario 1: DIA Proteomics Workflow**

```typescript
// tests/e2e/dia-workflow.test.ts
describe('DIA Proteomics Workflow with ACE Learning', () => {
  it('should recommend DIA-NN after learning from MaxQuant failures', async () => {
    // Step 1: Simulate 5 workflow failures with MaxQuant on DIA data
    for (let i = 0; i < 5; i++) {
      await simulateWorkflowFailure({
        userIntent: 'Analyze DIA proteomics data',
        failedTool: 'MaxQuant',
        errorLog: 'Error: MaxQuant only supports DDA acquisition',
      });
    }

    // Step 2: Query tool recommendations for DIA data
    const galaxyAssistant = new GalaxyAssistant({
      anthropicApiKey: process.env.ANTHROPIC_API_KEY!,
      galaxyAPIProxy,
    });

    const response = await galaxyAssistant.processMessage('Analyze my DIA proteomics data');

    // Step 3: Verify DIA-NN is recommended and MaxQuant is penalized
    const toolIds = response.recommendedTools?.map(t => t.tool.tool_id) || [];
    expect(toolIds).toContain('diann'); // DIA-NN recommended
    expect(toolIds).not.toContain('maxquant'); // MaxQuant filtered out
  });
});
```

### Phase 4: Production Validation (Week 7-8)

**Metrics to Track**:

1. **Tool Selection Accuracy**:
   - Baseline (without ACE): Measure % of workflows that succeed on first attempt
   - With ACE (after 100 workflows): Compare improvement
   - Target: +5-10% improvement

2. **Playbook Growth**:
   - Number of rules added per week
   - Average confidence score
   - Rule distribution by data type (DIA, DDA, RNA-seq, etc.)

3. **User Feedback**:
   - Workflow success rate
   - Time to successful workflow (iterations needed)
   - User satisfaction surveys

**Monitoring Dashboard** (Admin UI):

```typescript
// New endpoint: GET /api/ace/statistics
app.get('/api/ace/statistics', async (req, res) => {
  const stats = await aceCurator.getStatistics();
  const allRules = await playbookDatabase.getAllRules();

  res.json({
    totalRules: stats.totalRules,
    highConfidenceRules: stats.highConfidenceRules,
    recentUpdates: stats.recentUpdates,
    topRules: allRules.slice(0, 10).map(r => ({
      rule: r.ruleText,
      confidence: r.confidence,
      evidence: r.helpfulCount + r.harmfulCount,
    })),
  });
});
```

---

## Rollout Plan (16 Weeks)

### Phase 1: Foundation (Weeks 1-4)

**Week 1-2: Database & Schema**
- [ ] Create PostgreSQL migration for `ace_playbook_rules` table
- [ ] Implement `PlaybookDatabase` class with CRUD operations
- [ ] Write unit tests for playbook database
- [ ] Seed initial rules from domain experts (optional)

**Week 3-4: ACE Reflector Service**
- [ ] Implement `ACEReflector` class with failure analysis
- [ ] Implement success analysis for positive reinforcement
- [ ] Test with historical workflow execution logs
- [ ] Validate Claude prompt effectiveness (>80% extraction accuracy)

### Phase 2: Core Services (Weeks 5-8)

**Week 5-6: ACE Curator Service**
- [ ] Implement `ACECurator` class with playbook updates
- [ ] Implement incremental delta update logic
- [ ] Implement rule pruning/garbage collection
- [ ] Write integration tests (Reflector → Curator → Database)

**Week 7-8: GalaxyAssistant Integration**
- [ ] Modify `rankToolsByRelevance()` to inject playbook rules
- [ ] Implement playbook penalty/bonus scoring
- [ ] Add logging for playbook rule applications
- [ ] Test with synthetic workflows (controlled scenarios)

### Phase 3: Execution Monitoring (Weeks 9-12)

**Week 9-10: State Poller Integration**
- [ ] Add ACE feedback collection to `GalaxyStatePoller`
- [ ] Implement workflow intent tracking
- [ ] Connect error events to ACE Reflector
- [ ] Test with real Galaxy workflow executions

**Week 11-12: E2E Testing**
- [ ] Run 50 validation workflows across different data types
- [ ] Measure baseline vs. ACE-enhanced accuracy
- [ ] Fix bugs and edge cases
- [ ] Performance optimization (query caching, batch updates)

### Phase 4: Production Deployment (Weeks 13-16)

**Week 13-14: Staging Deployment**
- [ ] Deploy to staging environment
- [ ] Run canary tests (10% of workflows)
- [ ] Monitor playbook growth and rule quality
- [ ] Implement admin dashboard for monitoring

**Week 15-16: Production Rollout**
- [ ] Gradual rollout (20% → 50% → 100%)
- [ ] Monitor key metrics (success rate, latency, rule count)
- [ ] Collect user feedback
- [ ] Post-deployment report and lessons learned

---

## Success Metrics

### Key Performance Indicators (KPIs)

| Metric | Baseline (No ACE) | Target (With ACE) | Measurement |
|--------|-------------------|-------------------|-------------|
| Workflow Success Rate | 70% | 80-85% | % of workflows that complete without errors |
| Tool Selection Accuracy | 65% | 75-80% | % of first-attempt correct tool selection |
| Playbook Coverage | 0 rules | 50-100 rules | Number of high-confidence rules (>0.7) |
| Rule Confidence | N/A | >0.8 average | Average confidence across all rules |
| Learning Speed | N/A | <100 workflows | Workflows needed to learn a stable rule |

### Expected ACE Framework Impact (from paper)

Based on ACE paper results (arXiv:2510.04618):
- **+10.6% improvement** on agent tasks (GPT-4o)
- **+8.6% improvement** on domain tasks
- **86.9% latency reduction** vs. iterative prompt rewriting
- **+4.3% improvement** with 5-epoch multi-epoch training

**BioMate-Specific Targets**:
- Reduce "tool incompatibility" errors by **60-80%**
- Reduce workflow iterations (user corrections) by **40-50%**
- Increase user-reported satisfaction by **15-20%**

---

## Risk Mitigation

### Risk 1: Incorrect Rules Learned

**Problem**: ACE might learn wrong lessons from failures (e.g., "never use FastQC" from a network error)

**Mitigation**:
1. **Confidence Thresholds**: Only apply rules with confidence >0.5
2. **Evidence Requirements**: Require ≥3 instances before trusting a rule
3. **Human Review**: Admin dashboard to review and veto low-quality rules
4. **Automatic Pruning**: Remove rules with confidence <0.3 after ≥5 data points

### Risk 2: Playbook Drift

**Problem**: Playbook grows unbounded, becomes stale or contradictory

**Mitigation**:
1. **Periodic Pruning**: Run `pruneLowConfidenceRules()` every 6 hours
2. **Max Rules Cap**: Limit to 500 rules, remove lowest-confidence when exceeded
3. **Freshness Decay**: Reduce confidence for rules not used in 30 days
4. **Version Control**: Track playbook changes in Git for rollback

### Risk 3: Cold Start Problem

**Problem**: No playbook rules initially, system starts with no advantage

**Mitigation**:
1. **Expert Seeding**: Seed initial rules from domain experts (optional)
2. **Public Repository**: Create community playbook repository
3. **Import from Literature**: Extract rules from bioinformatics protocols
4. **Gradual Improvement**: Clearly communicate that system improves over time

### Risk 4: Performance Impact

**Problem**: Playbook lookups slow down tool ranking

**Mitigation**:
1. **Database Indexing**: Index `trigger_keywords` column with GIN index
2. **Query Caching**: Cache playbook rules for 5 minutes
3. **Async Updates**: Update playbook asynchronously (don't block workflow execution)
4. **Batch Processing**: Process multiple failure analyses in batches

---

## Future Enhancements

### V2: Parameter Learning (Weeks 17-24)

Extend ACE to learn optimal parameter values, not just tool selection:

```
Rule: "For DIA-NN on Orbitrap data, use FDR 0.01 (not 0.001)"
Evidence: 20 successful workflows with FDR 0.01, 5 failures with FDR 0.001
Confidence: 0.80
```

### V3: Workflow Template Learning (Weeks 25-32)

Learn complete workflow templates from successful executions:

```
Template: "DIA Proteomics → Differential Expression"
Steps: [DIA-NN, MSstats, DESeq2]
Success Rate: 95% (20/21 workflows)
Avg Runtime: 45 minutes
```

### V4: Multi-User Playbooks (Weeks 33-40)

Enable playbook sharing across organizations:

```
- Organization-level playbook (shared within BioMate instance)
- Public community playbook (opt-in sharing)
- Expert-curated playbook (validated by domain experts)
```

---

## Resources & References

### ACE Framework
- **Paper**: Wang et al. (2024) "Agentic Context Engineering: Evolving Contexts for Self-Improving LLM Systems" [arXiv:2510.04618](https://arxiv.org/abs/2510.04618)
- **GitHub**: [sci-m-wang/ACE-open](https://github.com/sci-m-wang/ACE-open)
- **Implementation**: [kayba-ai/agentic-context-engine](https://github.com/kayba-ai/agentic-context-engine)

### iFlow CLI (UX Patterns)
- **Scenarios**: [iFlow Use Cases](https://github.com/iflow-ai/iflow-cli/blob/main/docs_en/scenarios.md)
- **Sub-Agents**: [Agent Configuration](https://github.com/iflow-ai/iflow-cli/blob/main/docs_en/examples/subagent.md)

### BioMate Documentation
- **Workflow Generation**: `frontend/server/galaxy-assistant.ts`
- **Execution Monitoring**: `frontend/server/galaxy-state-poller.ts`
- **Tool Database**: Galaxy API with 2,177 indexed tools

---

## Appendix: Example Playbook Rules

### Proteomics

```json
{
  "ruleText": "For DIA proteomics data, never use MaxQuant (DDA-only). Use DIA-NN or Spectronaut instead.",
  "triggerKeywords": ["DIA", "proteomics", "data-independent"],
  "harmfulTools": ["MaxQuant"],
  "recommendedTools": ["DIA-NN", "Spectronaut"],
  "helpfulCount": 0,
  "harmfulCount": 8,
  "confidence": 0.0
}
```

```json
{
  "ruleText": "For DIA-NN quantification, use FDR threshold 0.01 for standard analysis",
  "triggerKeywords": ["DIA", "quantification", "DIA-NN"],
  "harmfulTools": [],
  "recommendedTools": ["DIA-NN"],
  "helpfulCount": 15,
  "harmfulCount": 2,
  "confidence": 0.88
}
```

### Genomics

```json
{
  "ruleText": "For RNA-seq differential expression, use DESeq2 over edgeR for small sample sizes (<10)",
  "triggerKeywords": ["RNA-seq", "differential expression", "small sample"],
  "harmfulTools": ["edgeR"],
  "recommendedTools": ["DESeq2"],
  "helpfulCount": 12,
  "harmfulCount": 3,
  "confidence": 0.80
}
```

### Data Formats

```json
{
  "ruleText": "For Orbitrap instruments, use mzML format (not mzXML) for better metadata preservation",
  "triggerKeywords": ["Orbitrap", "mass spec", "file format"],
  "harmfulTools": [],
  "recommendedTools": [],
  "helpfulCount": 20,
  "harmfulCount": 5,
  "confidence": 0.80
}
```

---

## Contact & Support

**Implementation Lead**: BioMate Development Team
**ACE Research**: sci-m-wang (GitHub)
**Questions**: Open GitHub issue in BioMate repository

---

**Document Version**: 1.0
**Last Updated**: October 30, 2025
**Status**: Ready for Implementation
