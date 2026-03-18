# BioMate V2.0 Integration Plan
**Date**: October 31, 2025
**Status**: Implementation Planning

## Executive Summary

This document outlines the integration plan for enhancing BioMate with V2.0 features while preserving and building upon the existing codebase. The current system has a solid foundation with comprehensive tool metadata and basic chat functionality. V2.0 will add proactive orchestration, user profiles, session memory, and enhanced scientific context utilization.

---

## Current System Analysis

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Frontend (TypeScript)                    │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ galaxy-assistant.ts (19KB)                             │ │
│  │ - Claude Sonnet 4.5 with prompt caching               │ │
│  │ - Intent analysis → Tool search → Workflow generation  │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                      Backend (Python)                        │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ search_index.py - Thread-safe FTS5 search             │ │
│  │ galaxy_tool_rag.py - RAG system for tools             │ │
│  │ tool_discovery.py - Multi-strategy tool discovery     │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                  Database (SQLite)                           │
│  galaxy_ai_tools.db (163 MB)                                │
│  - 9,212 tools with comprehensive metadata                  │
│  - scientific_context, function_info, examples, citations   │
│  - FTS5 index for full-text search                          │
└─────────────────────────────────────────────────────────────┘
```

### Current Database Schema

**Tools Table** (backend/lib/galaxy/tools/search_index.py:292-466):
```sql
CREATE TABLE tools (
    id INTEGER PRIMARY KEY,
    tool_id TEXT UNIQUE,
    name TEXT,
    version TEXT,
    category TEXT,
    description TEXT,

    -- Rich JSON metadata (already exists!)
    parameters TEXT,           -- JSON: Tool parameters
    inputs TEXT,              -- JSON: Input specifications
    outputs TEXT,             -- JSON: Output specifications
    help_text TEXT,           -- JSON: Documentation
    scientific_context TEXT,  -- JSON: Omics applicability, use cases
    function_info TEXT,       -- JSON: Underlying software, wrapper info
    examples TEXT,            -- JSON: Usage examples
    citations TEXT,           -- JSON: References
    edam_operations TEXT,     -- JSON: EDAM ontology
    requirements TEXT,        -- JSON: Software dependencies
    tags TEXT,               -- JSON: Searchable tags

    -- Repository info
    repo_owner TEXT,
    repo_name TEXT,
    url TEXT,

    -- Searchable
    rawText TEXT
);
```

**Key Discovery**: All 9,212 tools already have `scientific_context` populated! This includes:
- `omics_applicability`: primary_omics, suitable_designs, not_suitable
- `tool_selection`: best_for, not_recommended_for, alternatives
- `scientific_guidance`: common_pitfalls, key_parameters, result_interpretation
- `scientific_assumptions`
- `information_sources`

### Current Tool Search Flow

**Frontend** (galaxy-assistant.ts:90-175):
```typescript
async processMessage(message: string, context: ChatContext) {
  // Step 1: Analyze intent
  const intent = await this.analyzeIntent(message, context);

  // Step 2: Search tools
  const tools = await this.searchRelevantTools(message, intent.keywords);

  // Step 3: Search datasets
  const datasets = await this.searchRelevantDatasets(message, intent.keywords);

  // Step 4: Decide if workflow needed
  const workflowSuggestion = await this.analyzeWorkflowNeed(message, intent, tools);

  // Step 5: Generate workflow if needed
  if (workflowSuggestion.shouldGenerate) {
    generatedWorkflow = await this.generateWorkflow(userIntent, datasets);
  }

  // Step 6: Generate response
  const response = await this.generateResponse(...);

  return { message, recommendedTools, generatedWorkflow, suggestions };
}
```

**Backend** (galaxy_tool_rag.py:223-302):
```python
def search_tools(self, query: str, limit: int = 10) -> List[Dict]:
    # Simple LIKE query - NOT using scientific_context!
    sql = """
        SELECT tool_id, name, version, category, rawText
        FROM tools
        WHERE LOWER(name) LIKE ? OR LOWER(rawText) LIKE ?
        LIMIT ?
    """
    cursor.execute(sql, (f'%{query}%', f'%{query}%', limit))
```

**Problem**: Current search ignores the rich `scientific_context` data!

---

## What's Missing (Gap Analysis)

### 1. Scientific Context Not Utilized ❌
**Current State**: Database has rich scientific_context JSON, but search only uses name/rawText
**V2.0 Need**: Search should understand:
- Which omics domains each tool applies to
- When tool is/isn't suitable
- Data requirements (min samples, replicates)
- Common pitfalls and key parameters

### 2. No User Profiles ❌
**Current State**: Every session starts fresh, no memory of user
**V2.0 Need**:
- Track user's research domain (genomics, proteomics, etc.)
- Remember expertise level (beginner, intermediate, expert)
- Store correction logs to learn from user feedback
- Maintain project context across sessions

### 3. No Session Persistence ❌
**Current State**: Each message is independent, no conversation history storage
**V2.0 Need**:
- Store full conversation transcripts
- Enable session resumption days/weeks later
- Compress context when approaching token limits
- Build project knowledge bases

### 4. Reactive Only, Not Proactive ❌
**Current State**: Assistant responds to queries but doesn't ask clarifying questions
**V2.0 Need**:
- Iterative generation: Ask 2-3 clarifying questions before generating
- Auto-infer from dataset metadata (file type, organism, format)
- Only ask what can't be inferred

### 5. No Multi-Layer Validation ❌
**Current State**: Workflow generated in one shot
**V2.0 Need**:
- Layer 1: Tool compatibility validation
- Layer 2: Scientific validity check
- Layer 3: Parameter constraint verification
- Layer 4: Data requirement validation
- Layer 5: Computational feasibility check

### 6. No ACE Learning System ❌
**Current State**: No learning from failures or user corrections
**V2.0 Need**:
- Reflector: Analyze what went wrong
- Curator: Update playbook with learned rules
- Playbook DB: Persistent knowledge base

### 7. System Prompt Too Generic ❌
**Current State** (galaxy-assistant.ts:527-543):
```typescript
const systemPrompt = `You are BioMate, an expert bioinformatics AI assistant powered by Galaxy.

Your capabilities:
- Access to 2,177 Galaxy tools (real-time search)
- Access to 100+ GB BioMNI dataset catalog
- Workflow generation with automatic tool/dataset selection

Style guide:
- Be concise and practical
- Recommend specific tools and datasets
- Explain workflow steps clearly
- Highlight key parameters and considerations
```

**V2.0 Need**: Comprehensive 2000-line system prompt with:
- Instructions for ALL life science domains
- Iterative generation workflow
- Multi-layer validation protocol
- Context management instructions
- Tool usage guidelines (when to use each of 6 tools)

---

## Integration Strategy

### Phase 0: Foundation (Weeks 1-3)
**Goal**: Add infrastructure without breaking existing features

#### Week 1: Database Extensions
- **Add user tables** (PostgreSQL):
  ```sql
  CREATE TABLE users (
    id UUID PRIMARY KEY,
    email VARCHAR(255) UNIQUE,
    expertise_level VARCHAR(20) DEFAULT 'intermediate',
    research_domain VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
  );

  CREATE TABLE sessions (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    project_id UUID REFERENCES projects(id),
    summary TEXT,
    transcript_path TEXT,
    created_at TIMESTAMP DEFAULT NOW()
  );

  CREATE TABLE user_preferences (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    preference_type VARCHAR(50),
    preference_key VARCHAR(255),
    preference_value JSONB,
    confidence FLOAT DEFAULT 1.0,
    updated_at TIMESTAMP DEFAULT NOW()
  );
  ```

- **Keep existing SQLite for tools**: galaxy_ai_tools.db stays as-is
- **Why separate?**: PostgreSQL for user data (ACID, concurrent writes), SQLite for tool catalog (read-heavy)

#### Week 2: Enhanced Tool Search
**File**: `backend/lib/galaxy/tools/enhanced_search.py` (new)

```python
class EnhancedToolSearch:
    """Enhanced search that uses scientific_context JSON"""

    def __init__(self, search_index: ToolSearchIndex):
        self.search_index = search_index

    def search_with_context(
        self,
        query: str,
        user_context: Optional[Dict] = None,
        filters: Optional[Dict] = None
    ) -> List[Dict]:
        """
        Enhanced search using scientific_context

        Args:
            query: User's natural language query
            user_context: {
                'research_domain': 'proteomics',
                'data_type': 'DIA-LCMS',
                'organism': 'human',
                'expertise_level': 'intermediate'
            }
            filters: {
                'omics_type': 'proteomics',
                'min_samples': 3,
                'suitable_for': 'differential expression'
            }
        """
        # Step 1: FTS5 search (existing)
        initial_results = self.search_index.search(query, limit=100)

        # Step 2: Parse scientific_context for each tool
        enhanced_results = []
        for tool in initial_results:
            context = json.loads(tool.get('scientific_context', '{}'))

            # Calculate relevance based on scientific context
            relevance_score = self._calculate_scientific_relevance(
                tool, context, user_context, filters
            )

            if relevance_score > 0.3:  # Threshold
                tool['scientific_relevance_score'] = relevance_score
                tool['parsed_context'] = context
                enhanced_results.append(tool)

        # Step 3: Sort by combined score
        enhanced_results.sort(
            key=lambda x: (
                x.get('scientific_relevance_score', 0) * 0.6 +
                x.get('rank', 0) * 0.4  # FTS5 BM25 rank
            ),
            reverse=True
        )

        return enhanced_results[:20]

    def _calculate_scientific_relevance(
        self, tool: Dict, context: Dict,
        user_context: Optional[Dict],
        filters: Optional[Dict]
    ) -> float:
        """Calculate relevance based on scientific_context"""
        score = 0.0

        # 1. Omics applicability (30% weight)
        if user_context and 'research_domain' in user_context:
            omics_app = context.get('omics_applicability', {})
            primary_omics = omics_app.get('primary_omics', [])

            user_domain = user_context['research_domain']
            if user_domain in primary_omics:
                score += 0.3
            elif user_domain in omics_app.get('secondary_omics', []):
                score += 0.15

        # 2. Suitable designs (25% weight)
        if filters and 'suitable_for' in filters:
            tool_sel = context.get('tool_selection', {})
            best_for = tool_sel.get('best_for', [])
            not_recommended = tool_sel.get('not_recommended_for', [])

            task = filters['suitable_for'].lower()
            if any(task in str(use).lower() for use in best_for):
                score += 0.25
            elif any(task in str(use).lower() for use in not_recommended):
                score -= 0.3  # Penalty for unsuitable tools

        # 3. Data requirements (20% weight)
        if filters and 'min_samples' in filters:
            data_req = context.get('omics_applicability', {}).get('data_requirements', {})
            min_samples = data_req.get('min_samples')

            if min_samples and filters['min_samples'] >= min_samples:
                score += 0.2
            elif min_samples and filters['min_samples'] < min_samples:
                score -= 0.2  # User doesn't have enough samples

        # 4. User expertise level (15% weight)
        if user_context and 'expertise_level' in user_context:
            guidance = context.get('scientific_guidance', {})
            pitfalls = guidance.get('common_pitfalls', [])

            # More pitfalls = more complex tool
            complexity = len(pitfalls) / 5  # Normalized
            user_level = user_context['expertise_level']

            if user_level == 'expert':
                score += 0.15  # Experts can handle complex tools
            elif user_level == 'beginner' and complexity > 0.6:
                score -= 0.1  # Beginners should avoid complex tools
            else:
                score += 0.1  # Intermediate users

        # 5. Information quality (10% weight)
        info_sources = context.get('information_sources', {})
        if info_sources:
            # Has citations, manual, well-documented
            score += 0.1

        return max(0.0, min(1.0, score))  # Clamp to [0, 1]
```

**Integration Point**: Update `galaxy-assistant.ts:searchRelevantTools()` to call enhanced search

#### Week 3: User Context Management
**File**: `frontend/server/user-context-manager.ts` (new)

```typescript
import { Pool } from 'pg';

export interface UserProfile {
  id: string;
  email: string;
  expertise_level: 'beginner' | 'intermediate' | 'expert';
  research_domain: string;
  preferred_communication_style: 'detailed' | 'concise' | 'balanced';
  active_projects: ProjectContext[];
}

export interface ProjectContext {
  id: string;
  name: string;
  description: string;
  research_goal: string;
  primary_domain: string;
  organisms: string[];
  tissue_types: string[];
  conditions: string[];
  knowledge_base: string;  // Path to knowledge_base.md
}

export interface SessionContext {
  session_id: string;
  user_id: string;
  project_id?: string;
  conversation_history: Message[];
  token_count: number;
  created_at: Date;
}

export class UserContextManager {
  private pgPool: Pool;

  constructor(connectionString: string) {
    this.pgPool = new Pool({ connectionString });
  }

  async loadUserContext(userId: string): Promise<UserProfile> {
    // Load user profile from PostgreSQL
    const userResult = await this.pgPool.query(
      'SELECT * FROM users WHERE id = $1',
      [userId]
    );

    if (userResult.rows.length === 0) {
      throw new Error(`User ${userId} not found`);
    }

    const user = userResult.rows[0];

    // Load active projects
    const projectsResult = await this.pgPool.query(
      `SELECT * FROM projects
       WHERE user_id = $1 AND status = 'active'
       ORDER BY updated_at DESC`,
      [userId]
    );

    const active_projects = projectsResult.rows.map(p => ({
      id: p.id,
      name: p.name,
      description: p.description,
      research_goal: p.research_goal,
      primary_domain: p.primary_domain,
      organisms: p.organisms,
      tissue_types: p.tissue_types,
      conditions: p.conditions,
      knowledge_base: p.storage_path + '/knowledge_base.md'
    }));

    return {
      id: user.id,
      email: user.email,
      expertise_level: user.expertise_level,
      research_domain: user.research_domain,
      preferred_communication_style: user.preferred_communication_style,
      active_projects
    };
  }

  async loadSession(sessionId: string): Promise<SessionContext> {
    const sessionResult = await this.pgPool.query(
      'SELECT * FROM sessions WHERE id = $1',
      [sessionId]
    );

    if (sessionResult.rows.length === 0) {
      throw new Error(`Session ${sessionId} not found`);
    }

    const session = sessionResult.rows[0];

    // Load conversation history from file
    const fs = require('fs').promises;
    const transcript = await fs.readFile(session.transcript_path, 'utf-8');
    const conversation_history = this.parseTranscript(transcript);

    return {
      session_id: session.id,
      user_id: session.user_id,
      project_id: session.project_id,
      conversation_history,
      token_count: this.estimateTokens(conversation_history),
      created_at: session.created_at
    };
  }

  async saveSession(context: SessionContext): Promise<void> {
    // Save conversation history to file
    const transcript = this.formatTranscript(context.conversation_history);
    const transcriptPath = `/storage/users/${context.user_id}/sessions/${context.session_id}/transcript.md`;

    const fs = require('fs').promises;
    await fs.writeFile(transcriptPath, transcript, 'utf-8');

    // Update session in PostgreSQL
    await this.pgPool.query(
      `UPDATE sessions
       SET transcript_path = $1, updated_at = NOW()
       WHERE id = $2`,
      [transcriptPath, context.session_id]
    );
  }

  async compressContext(context: SessionContext): Promise<SessionContext> {
    // When approaching 80% of 200K token limit (160K tokens)
    if (context.token_count > 160000) {
      // Keep last 10 messages, compress earlier ones
      const recentMessages = context.conversation_history.slice(-10);
      const oldMessages = context.conversation_history.slice(0, -10);

      // Use Claude Haiku to summarize
      const summary = await this.summarizeMessages(oldMessages);

      // Create new context with summary
      const compressedHistory = [
        {
          role: 'system',
          content: `Previous conversation summary:\n\n${summary}`
        },
        ...recentMessages
      ];

      return {
        ...context,
        conversation_history: compressedHistory,
        token_count: this.estimateTokens(compressedHistory)
      };
    }

    return context;
  }

  private estimateTokens(messages: Message[]): number {
    // Rough estimate: 1 token ≈ 4 characters
    const totalChars = messages.reduce((sum, msg) =>
      sum + (msg.content?.length || 0), 0
    );
    return Math.ceil(totalChars / 4);
  }

  // ... other helper methods
}
```

**Integration Point**: Update `galaxy-assistant.ts` to load user context before processing messages

---

### Phase 1: Enhanced Orchestration (Weeks 4-6)

#### Week 4-5: Enhanced System Prompt
**File**: `frontend/server/system-prompts/comprehensive.ts` (new)

Create a ~2000-line system prompt based on `BIOMATE_V2_FINAL_ARCHITECTURE_20251031.md` that includes:

1. **Life Science Domain Coverage** (500 lines)
   - Genomics, transcriptomics, proteomics, metabolomics
   - Single-cell, spatial, imaging, metagenomics
   - Clinical diagnostics, drug discovery
   - Agriculture, environmental science

2. **Workflow Generation Process** (400 lines)
   - Phase 1: Understand intent FIRST
   - Auto-infer from GetDatasetMetadata()
   - Only ask what can't be inferred
   - 2-3 clarifying questions maximum

3. **Tool Selection Guidelines** (300 lines)
   - Use SearchTools() with scientific filters
   - Check scientific_context for suitability
   - Prefer tools with high confidence scores
   - Consider user expertise level

4. **Multi-Layer Validation** (300 lines)
   - Layer 1: Tool compatibility
   - Layer 2: Scientific validity
   - Layer 3: Parameter constraints
   - Layer 4: Data requirements
   - Layer 5: Computational feasibility

5. **Context Management** (200 lines)
   - Use GetUserProfile() for personalization
   - Check project knowledge base
   - Compress when >80% token limit
   - Update project knowledge after successful workflows

6. **Tool Documentation** (300 lines)
   - SearchTools(): When and how to use
   - GetDatasetMetadata(): Auto-detect data properties
   - GetUserProfile(): Access user context
   - ValidateWorkflow(): Check before execution
   - GetScientificContext(): Understand tool appropriateness
   - CompressContext(): Manage token usage

**Integration**: Replace existing system prompt in `galaxy-assistant.ts`

#### Week 6: Iterative Generation
**File**: `frontend/server/iterative-generator.ts` (new)

```typescript
export class IterativeWorkflowGenerator {
  private claude: Anthropic;
  private galaxyAPI: GalaxyAPIProxy;
  private userContext: UserContextManager;

  async generateIteratively(
    userIntent: string,
    userId: string,
    projectId?: string
  ): Promise<WorkflowGenerationResult> {
    // Step 1: Load user and project context
    const userProfile = await this.userContext.loadUserContext(userId);
    const projectContext = projectId
      ? userProfile.active_projects.find(p => p.id === projectId)
      : null;

    // Step 2: Auto-detect from uploaded datasets
    const datasets = await this.galaxyAPI.getUserDatasets(userId);
    const datasetMetadata = await Promise.all(
      datasets.map(ds => this.galaxyAPI.getDatasetMetadata(ds.id))
    );

    // Step 3: Determine what's known and what needs clarification
    const knownContext = {
      user_domain: userProfile.research_domain,
      expertise_level: userProfile.expertise_level,
      project_goal: projectContext?.research_goal,
      organisms: projectContext?.organisms,
      data_types: datasetMetadata.map(dm => dm.inferred_type),
      formats: datasetMetadata.map(dm => dm.format)
    };

    // Step 4: Ask Claude to identify what needs clarification
    const clarificationNeeded = await this.identifyClarifications(
      userIntent,
      knownContext
    );

    // Step 5: If clarifications needed, ask user
    if (clarificationNeeded.questions.length > 0) {
      return {
        status: 'needs_clarification',
        questions: clarificationNeeded.questions,
        partial_context: knownContext
      };
    }

    // Step 6: Generate workflow with full context
    return await this.generateWorkflowWithContext(
      userIntent,
      knownContext,
      clarificationNeeded.inferred_requirements
    );
  }

  async identifyClarifications(
    userIntent: string,
    knownContext: any
  ): Promise<{
    questions: ClarifyingQuestion[],
    inferred_requirements: any
  }> {
    const prompt = `
# Task: Identify Clarifications Needed

User intent: "${userIntent}"

Known context:
${JSON.stringify(knownContext, null, 2)}

Instructions:
1. Analyze what information is ALREADY KNOWN from the context
2. Infer what you can from the user intent and known context
3. Only ask about information that is:
   - Critical for workflow generation
   - Cannot be inferred from available context
   - Not already provided

Output format:
{
  "inferred_requirements": {
    "analysis_type": "differential expression",
    "statistical_method": "DESeq2 (standard for RNA-seq)",
    "quality_control": "required (always needed for raw data)"
  },
  "questions": [
    {
      "question": "What is your false discovery rate (FDR) threshold?",
      "default": "0.05",
      "why_needed": "Determines statistical significance cutoff",
      "options": ["0.01", "0.05", "0.1"]
    }
  ]
}

Respond with JSON only.
`;

    const response = await this.claude.messages.create({
      model: 'claude-sonnet-4-5',
      max_tokens: 800,
      temperature: 0.3,
      messages: [{ role: 'user', content: prompt }]
    });

    const result = JSON.parse(
      response.content[0].type === 'text'
        ? response.content[0].text
        : '{}'
    );

    return {
      questions: result.questions || [],
      inferred_requirements: result.inferred_requirements || {}
    };
  }

  // ... more methods
}
```

**Integration**: Use in `galaxy-assistant.ts` before calling `generateWorkflow()`

---

### Phase 2: Validation & Learning (Weeks 7-9)

#### Week 7-8: Multi-Layer Validation
**File**: `backend/lib/galaxy/ai/multi_layer_validator.py` (new)

```python
class MultiLayerValidator:
    """5-layer validation system for workflows"""

    def __init__(self, tool_search: EnhancedToolSearch):
        self.tool_search = tool_search

    def validate(self, workflow: Dict, context: Dict) -> ValidationResult:
        """Run all 5 validation layers"""

        results = {
            'layer1_compatibility': self.validate_tool_compatibility(workflow),
            'layer2_scientific': self.validate_scientific_validity(workflow, context),
            'layer3_parameters': self.validate_parameter_constraints(workflow),
            'layer4_data': self.validate_data_requirements(workflow, context),
            'layer5_computational': self.validate_computational_feasibility(workflow)
        }

        # Calculate overall confidence
        passed = sum(1 for r in results.values() if r['passed'])
        confidence = passed / 5

        # Aggregate issues
        all_issues = []
        for layer_name, result in results.items():
            all_issues.extend(result.get('issues', []))

        return ValidationResult(
            passed=confidence >= 0.8,  # Need 80% to pass
            confidence=confidence,
            layer_results=results,
            issues=all_issues,
            recommendations=self._generate_recommendations(results)
        )

    def validate_tool_compatibility(self, workflow: Dict) -> Dict:
        """Layer 1: Check if tools can connect (output → input)"""
        issues = []

        steps = workflow.get('steps', [])
        for i, step in enumerate(steps):
            if i == 0:
                continue  # First step has no input from previous

            prev_step = steps[i-1]

            # Get output format of previous step
            prev_tool = self.tool_search.search_index.get_by_id(
                prev_step['tool_id']
            )
            prev_outputs = json.loads(prev_tool.get('outputs', '[]'))

            # Get input format of current step
            curr_tool = self.tool_search.search_index.get_by_id(
                step['tool_id']
            )
            curr_inputs = json.loads(curr_tool.get('inputs', '[]'))

            # Check compatibility
            compatible = self._check_format_compatibility(
                prev_outputs, curr_inputs
            )

            if not compatible:
                issues.append({
                    'severity': 'error',
                    'step': i,
                    'message': f"Step {i} ({step['tool_id']}) cannot accept output from step {i-1} ({prev_step['tool_id']})",
                    'prev_outputs': [o.get('format') for o in prev_outputs],
                    'curr_inputs': [inp.get('format') for inp in curr_inputs]
                })

        return {
            'passed': len(issues) == 0,
            'issues': issues
        }

    def validate_scientific_validity(self, workflow: Dict, context: Dict) -> Dict:
        """Layer 2: Check if workflow makes scientific sense"""
        issues = []

        steps = workflow.get('steps', [])
        user_domain = context.get('research_domain', '')
        data_type = context.get('data_type', '')

        for i, step in enumerate(steps):
            tool = self.tool_search.search_index.get_by_id(step['tool_id'])
            scientific_context = json.loads(tool.get('scientific_context', '{}'))

            # Check 1: Is tool suitable for this omics domain?
            omics_app = scientific_context.get('omics_applicability', {})
            primary_omics = omics_app.get('primary_omics', [])
            not_suitable = omics_app.get('not_suitable', [])

            if user_domain not in primary_omics and user_domain:
                issues.append({
                    'severity': 'warning',
                    'step': i,
                    'message': f"Tool {tool['name']} is not primarily designed for {user_domain}",
                    'primary_omics': primary_omics,
                    'suggestion': f"Consider tools optimized for {user_domain}"
                })

            if any(user_domain.lower() in str(ns).lower() for ns in not_suitable):
                issues.append({
                    'severity': 'error',
                    'step': i,
                    'message': f"Tool {tool['name']} is explicitly NOT suitable for {user_domain}",
                    'not_suitable_for': not_suitable
                })

            # Check 2: Is tool appropriate for this specific use case?
            tool_selection = scientific_context.get('tool_selection', {})
            not_recommended = tool_selection.get('not_recommended_for', [])

            analysis_type = context.get('analysis_type', '')
            if any(analysis_type.lower() in str(nr).lower() for nr in not_recommended):
                issues.append({
                    'severity': 'error',
                    'step': i,
                    'message': f"Tool {tool['name']} is not recommended for {analysis_type}",
                    'alternatives': tool_selection.get('alternatives', [])
                })

        return {
            'passed': not any(issue['severity'] == 'error' for issue in issues),
            'issues': issues
        }

    def validate_parameter_constraints(self, workflow: Dict) -> Dict:
        """Layer 3: Check parameter ranges and dependencies"""
        issues = []

        for i, step in enumerate(workflow.get('steps', [])):
            tool = self.tool_search.search_index.get_by_id(step['tool_id'])
            parameters = json.loads(tool.get('parameters', '[]'))

            step_params = step.get('parameters', {})

            for param_def in parameters:
                param_name = param_def.get('name')
                param_value = step_params.get(param_name)

                if param_value is None:
                    if not param_def.get('optional', True):
                        issues.append({
                            'severity': 'error',
                            'step': i,
                            'parameter': param_name,
                            'message': f"Required parameter '{param_name}' is missing"
                        })
                    continue

                # Check range constraints
                if param_def.get('type') in ['integer', 'float']:
                    min_val = param_def.get('min')
                    max_val = param_def.get('max')

                    if min_val is not None and param_value < min_val:
                        issues.append({
                            'severity': 'error',
                            'step': i,
                            'parameter': param_name,
                            'message': f"Value {param_value} is below minimum {min_val}"
                        })

                    if max_val is not None and param_value > max_val:
                        issues.append({
                            'severity': 'error',
                            'step': i,
                            'parameter': param_name,
                            'message': f"Value {param_value} exceeds maximum {max_val}"
                        })

        return {
            'passed': not any(issue['severity'] == 'error' for issue in issues),
            'issues': issues
        }

    def validate_data_requirements(self, workflow: Dict, context: Dict) -> Dict:
        """Layer 4: Check if user has required data"""
        issues = []

        available_samples = context.get('num_samples', 0)
        available_replicates = context.get('num_replicates', 0)

        for i, step in enumerate(workflow.get('steps', [])):
            tool = self.tool_search.search_index.get_by_id(step['tool_id'])
            scientific_context = json.loads(tool.get('scientific_context', '{}'))

            data_req = scientific_context.get('omics_applicability', {}).get('data_requirements', {})
            min_samples = data_req.get('min_samples')
            min_replicates = data_req.get('min_replicates')

            if min_samples and available_samples < min_samples:
                issues.append({
                    'severity': 'error',
                    'step': i,
                    'message': f"Tool {tool['name']} requires at least {min_samples} samples, but only {available_samples} available"
                })

            if min_replicates and available_replicates < min_replicates:
                issues.append({
                    'severity': 'warning',
                    'step': i,
                    'message': f"Tool {tool['name']} recommends at least {min_replicates} replicates for statistical power"
                })

        return {
            'passed': not any(issue['severity'] == 'error' for issue in issues),
            'issues': issues
        }

    def validate_computational_feasibility(self, workflow: Dict) -> Dict:
        """Layer 5: Estimate if workflow can run in reasonable time/resources"""
        issues = []

        total_estimated_time = 0
        total_estimated_memory = 0

        for i, step in enumerate(workflow.get('steps', [])):
            tool = self.tool_search.search_index.get_by_id(step['tool_id'])
            requirements = json.loads(tool.get('requirements', '[]'))

            # Estimate based on requirements
            # (This is simplified - real implementation would use historical data)
            for req in requirements:
                if isinstance(req, dict):
                    if 'memory' in req.get('name', '').lower():
                        memory = req.get('version', '8GB')
                        # Parse memory string
                        total_estimated_memory += self._parse_memory(memory)

        # Check against limits
        if total_estimated_memory > 128 * 1024:  # 128 GB limit
            issues.append({
                'severity': 'warning',
                'message': f"Workflow may require {total_estimated_memory // 1024} GB memory, which exceeds typical limits",
                'suggestion': "Consider using downsampled data or cloud resources"
            })

        return {
            'passed': not any(issue['severity'] == 'error' for issue in issues),
            'issues': issues,
            'estimated_memory_mb': total_estimated_memory,
            'estimated_time_minutes': total_estimated_time
        }

    # ... helper methods
```

**Integration**: Call before executing workflow

#### Week 9: ACE Learning System (Basic)
**File**: `backend/lib/galaxy/ai/ace_learning.py` (new)

```python
class ACELearningSystem:
    """Adaptive Context Engineering - Learn from failures and corrections"""

    def __init__(self, db_connection):
        self.db = db_connection
        self.init_playbook_db()

    def init_playbook_db(self):
        """Create playbook tables"""
        self.db.execute("""
            CREATE TABLE IF NOT EXISTS ace_playbook_rules (
                id SERIAL PRIMARY KEY,
                rule_type VARCHAR(50),
                condition JSONB,
                action JSONB,
                confidence FLOAT DEFAULT 0.5,
                success_count INTEGER DEFAULT 0,
                failure_count INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT NOW(),
                last_used TIMESTAMP
            )
        """)

        self.db.execute("""
            CREATE TABLE IF NOT EXISTS correction_log (
                id SERIAL PRIMARY KEY,
                user_id UUID,
                workflow_id UUID,
                suggested_approach JSONB,
                corrected_approach JSONB,
                workflow_context JSONB,
                user_explanation TEXT,
                learned_rule_id INTEGER REFERENCES ace_playbook_rules(id),
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)

    def log_correction(
        self,
        user_id: str,
        workflow_id: str,
        suggested: Dict,
        corrected: Dict,
        context: Dict,
        explanation: Optional[str] = None
    ) -> int:
        """Log when user corrects our suggestion"""

        result = self.db.execute("""
            INSERT INTO correction_log (
                user_id, workflow_id, suggested_approach, corrected_approach,
                workflow_context, user_explanation
            ) VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING id
        """, (
            user_id, workflow_id,
            json.dumps(suggested), json.dumps(corrected),
            json.dumps(context), explanation
        ))

        correction_id = result.fetchone()[0]

        # Analyze correction and potentially create rule
        rule_id = self._analyze_and_learn(suggested, corrected, context)

        if rule_id:
            self.db.execute("""
                UPDATE correction_log
                SET learned_rule_id = $1
                WHERE id = $2
            """, (rule_id, correction_id))

        return correction_id

    def _analyze_and_learn(
        self, suggested: Dict, corrected: Dict, context: Dict
    ) -> Optional[int]:
        """Analyze correction and create/update playbook rule"""

        # Identify what changed
        changes = self._identify_changes(suggested, corrected)

        if not changes:
            return None

        # Extract pattern
        pattern = self._extract_pattern(changes, context)

        if not pattern:
            return None

        # Check if similar rule exists
        existing = self._find_similar_rule(pattern)

        if existing:
            # Update existing rule confidence
            self.db.execute("""
                UPDATE ace_playbook_rules
                SET success_count = success_count + 1,
                    confidence = LEAST(0.95, confidence + 0.05),
                    last_used = NOW()
                WHERE id = $1
            """, (existing['id'],))
            return existing['id']
        else:
            # Create new rule
            result = self.db.execute("""
                INSERT INTO ace_playbook_rules (
                    rule_type, condition, action, confidence
                ) VALUES ($1, $2, $3, $4)
                RETURNING id
            """, (
                pattern['type'],
                json.dumps(pattern['condition']),
                json.dumps(pattern['action']),
                0.3  # Start with low confidence
            ))
            return result.fetchone()[0]

    def get_applicable_rules(self, context: Dict) -> List[Dict]:
        """Get playbook rules that apply to current context"""

        result = self.db.execute("""
            SELECT * FROM ace_playbook_rules
            WHERE confidence > 0.5
            ORDER BY confidence DESC, success_count DESC
            LIMIT 20
        """)

        all_rules = [dict(row) for row in result.fetchall()]

        # Filter by context
        applicable = []
        for rule in all_rules:
            if self._matches_condition(rule['condition'], context):
                applicable.append(rule)

        return applicable

    # ... more methods
```

**Integration**: Use in workflow generation to apply learned rules

---

## Success Metrics

### Phase 0 (Weeks 1-3)
- [ ] PostgreSQL user tables created and tested
- [ ] Enhanced tool search returns 20% more relevant results
- [ ] User context loads in <100ms
- [ ] Session persistence working across days

### Phase 1 (Weeks 4-6)
- [ ] Comprehensive system prompt deployed (2000 lines)
- [ ] Iterative generation asks 2-3 clarifying questions before generating
- [ ] 50% of questions auto-answered by dataset metadata inference
- [ ] User feedback: workflows feel more tailored to their needs

### Phase 2 (Weeks 7-9)
- [ ] Multi-layer validation catches 80% of incompatibilities
- [ ] ACE system logs corrections and creates initial rules
- [ ] Workflow generation confidence score >0.85
- [ ] User corrections decrease by 30%

---

## Risk Mitigation

### Risk 1: Breaking Existing Features
**Mitigation**:
- Keep existing APIs unchanged
- Add new endpoints with `/v2/` prefix
- Run parallel A/B test with 10% of users
- Maintain rollback capability

### Risk 2: Performance Degradation
**Mitigation**:
- Enhanced search uses indexes (FTS5 + JSONB in PostgreSQL)
- User context caching with Redis
- Async loading of non-critical data
- Load testing before each phase deployment

### Risk 3: Token Limit Issues
**Mitigation**:
- Context compression at 80% threshold (160K tokens)
- Use Claude Haiku for summarization (cheap)
- Store summaries in PostgreSQL for quick reload
- Monitor token usage per session

### Risk 4: Database Migration Complexity
**Mitigation**:
- Use Alembic for PostgreSQL migrations
- SQLite (tools) remains read-only, no migration needed
- Test migrations on staging environment first
- Backup before each migration

---

## Next Steps

1. **Review this plan** with stakeholders
2. **Set up PostgreSQL** instance for user/project data
3. **Create Week 1 tasks** in detail
4. **Begin implementation** of Phase 0

---

## Appendix: File Structure

```
biomate/
├── backend/
│   ├── lib/galaxy/
│   │   ├── ai/
│   │   │   ├── enhanced_tool_search.py      [NEW - Week 2]
│   │   │   ├── multi_layer_validator.py     [NEW - Week 7]
│   │   │   ├── ace_learning.py              [NEW - Week 9]
│   │   │   ├── tool_discovery.py            [KEEP - Enhance]
│   │   │   ├── galaxy_tool_rag.py           [KEEP - Use less]
│   │   │   └── workflow_generator.py        [KEEP - Integrate]
│   │   └── tools/
│   │       └── search_index.py              [KEEP - Use more]
│   └── database/
│       └── galaxy_ai_tools.db               [KEEP - Read-only]
├── frontend/
│   └── server/
│       ├── user-context-manager.ts          [NEW - Week 3]
│       ├── iterative-generator.ts           [NEW - Week 6]
│       ├── system-prompts/
│       │   └── comprehensive.ts             [NEW - Week 4]
│       ├── galaxy-assistant.ts              [ENHANCE - All phases]
│       └── routes.ts                        [ENHANCE - Add v2 endpoints]
└── migrations/
    └── postgresql/                          [NEW - Week 1]
        ├── 001_create_users.sql
        ├── 002_create_projects.sql
        ├── 003_create_sessions.sql
        └── 004_create_ace_playbook.sql
```

---

**End of Integration Plan**
