# BioMate Self-Learning System

**Document ID**: 20260113_SELF_LEARNING_SYSTEM
**Created**: January 13, 2026
**Purpose**: Comprehensive documentation of BioMate's self-learning and personalization capabilities

---

## Executive Summary

BioMate implements a **sophisticated multi-layer self-learning system** that enables the platform to:
1. Learn from user corrections and feedback
2. Personalize responses based on user expertise and preferences
3. Consolidate successful interaction patterns into reusable procedures
4. Adapt tool recommendations based on domain context

---

## 1. Architecture Overview

### 1.1 Learning System Components

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    BioMate Self-Learning Architecture                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐     │
│  │  User Context   │    │  Project Memory │    │ Global Patterns │     │
│  │    Adapter      │    │    Service      │    │   (Backend)     │     │
│  └────────┬────────┘    └────────┬────────┘    └────────┬────────┘     │
│           │                      │                      │               │
│           ▼                      ▼                      ▼               │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    Memory Integration Layer                       │  │
│  │  • Load user preferences    • Find similar episodes               │  │
│  │  • Get applicable procedures • Build enhanced context             │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                  │                                      │
│                                  ▼                                      │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    10-Table LTM Database                          │  │
│  │  ┌─────────┐ ┌────────────┐ ┌──────────────┐ ┌───────────────┐   │  │
│  │  │ltm_users│ │preferences │ │ corrections  │ │   episodes    │   │  │
│  │  └─────────┘ └────────────┘ └──────────────┘ └───────────────┘   │  │
│  │  ┌─────────┐ ┌────────────┐ ┌──────────────┐ ┌───────────────┐   │  │
│  │  │sessions │ │  messages  │ │  workflows   │ │  procedures   │   │  │
│  │  └─────────┘ └────────────┘ └──────────────┘ └───────────────┘   │  │
│  │  ┌─────────┐ ┌────────────┐                                      │  │
│  │  │projects │ │ knowledge  │                                      │  │
│  │  └─────────┘ └────────────┘                                      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Learning Flow

```
                    User Interaction
                          │
                          ▼
         ┌────────────────────────────────────┐
         │   1. Load Context (Memory Layer)   │
         │   • User preferences (confidence>0.5)│
         │   • Recent corrections (avoid)      │
         │   • Similar past episodes           │
         │   • Applicable procedures           │
         └────────────────┬───────────────────┘
                          │
                          ▼
         ┌────────────────────────────────────┐
         │   2. Process with Galaxy Assistant  │
         │   • Intent analysis with context    │
         │   • Tool search (ranked by prefs)   │
         │   • Workflow generation             │
         └────────────────┬───────────────────┘
                          │
                          ▼
         ┌────────────────────────────────────┐
         │   3. Record Episode                 │
         │   • User query + assistant response │
         │   • Tools used + parameters         │
         │   • Context snapshot                │
         └────────────────┬───────────────────┘
                          │
                          ▼
         ┌────────────────────────────────────┐
         │   4. User Feedback / Correction     │
         │   ┌──────────────────────────────┐ │
         │   │ If user corrects suggestion: │ │
         │   │ • Record in correction_log   │ │
         │   │ • Update domain preference   │ │
         │   │ • Extract keywords           │ │
         │   │ • Update router weights      │ │
         │   └──────────────────────────────┘ │
         └────────────────┬───────────────────┘
                          │
                          ▼
         ┌────────────────────────────────────┐
         │   5. Outcome Recording              │
         │   • Success/failure status          │
         │   • What worked / what failed       │
         │   • Lessons learned (AI-generated)  │
         └────────────────┬───────────────────┘
                          │
                          ▼
         ┌────────────────────────────────────┐
         │   6. Memory Consolidation           │
         │   (If 3+ similar successful episodes)│
         │   • Create procedural memory        │
         │   • Update success rates            │
         │   • Promote to reusable workflow    │
         └────────────────────────────────────┘
```

---

## 2. Database Schema (10 Tables)

### 2.1 Core User Learning Tables

| Table | Purpose | Key Fields |
|-------|---------|------------|
| **ltm_users** | User profiles & statistics | expertiseLevel, researchDomain, totalWorkflows, successRate |
| **user_preferences** | Learned tool/parameter preferences | preferenceType, confidence (0-1), usageCount, learnedFrom |
| **correction_log** | Learning from mistakes | suggestedApproach, correctedApproach, userExplanation |

### 2.2 Episodic & Procedural Memory

| Table | Purpose | Key Fields |
|-------|---------|------------|
| **project_episodes** | Interaction outcomes | userQuery, toolsUsed, outcomeSuccess, whatWorked, lessonsLearned |
| **project_procedures** | Consolidated workflows | triggerPattern, steps, successRate, timesUsed |
| **project_knowledge** | Domain knowledge base | knowledgeType, content, confidence |

### 2.3 Session & Conversation

| Table | Purpose | Key Fields |
|-------|---------|------------|
| **sessions** | Interaction sessions | summary, keyDecisions, messageCount, totalTokens |
| **conversation_messages** | Message history | role, content, toolsUsed, thinkingContent |
| **workflows** | Workflow executions | domain, dataType, analysisGoal, executionStatus |
| **projects** | Project context | primaryDomain, organisms, researchGoal |

---

## 3. Learning Mechanisms

### 3.1 Correction Learning (3-Layer)

```
User Corrects Suggestion
         │
         ├──────────────────────────────────────────────────┐
         │                                                  │
         ▼                                                  ▼
┌─────────────────────┐                      ┌─────────────────────┐
│  Layer 1: Direct    │                      │  Layer 2: Pattern   │
│  Pattern Update     │                      │  Extraction         │
│                     │                      │                     │
│  • confidence += 0.2│                      │  • Extract keywords │
│  • evidence_count++ │                      │  • Map to domain    │
│                     │                      │  • Add to router    │
└─────────────────────┘                      └─────────────────────┘
         │                                                  │
         └──────────────────────────┬───────────────────────┘
                                    │
                                    ▼
                       ┌─────────────────────┐
                       │  Layer 3: Router    │
                       │  Weight Update      │
                       │                     │
                       │  • EnhancedRouter   │
                       │  • Keyword → Domain │
                       │  • Faster routing   │
                       └─────────────────────┘
```

**Implementation:**
```typescript
// frontend/server/memory-integration.ts
async recordCorrection(data: {
  suggestedApproach: { tool: string; parameters: any };
  correctedApproach: { tool: string; parameters: any };
  userExplanation: string;
}) {
  // 1. Store correction
  await correctionRepository.insert(data);

  // 2. Update preference confidence
  await updateDomainPreference(correctedDomain, +0.2);

  // 3. Extract keywords and update router
  const keywords = extractKeywords(userQuery);
  await router.addLearnedKeywords(correctedDomain, keywords);
}
```

### 3.2 Preference Learning

```
┌─────────────────────────────────────────────────────────────────┐
│                    Preference Confidence Model                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Initial Confidence: 0.3 (new pattern)                          │
│                                                                  │
│  ┌───────────────┐    ┌───────────────┐    ┌───────────────┐    │
│  │ explicit_choice│    │repeated_usage │    │  correction   │    │
│  │   +0.3        │    │   +0.1        │    │   +0.2        │    │
│  │               │    │               │    │               │    │
│  │ User picks A  │    │ User uses A   │    │ User corrects │    │
│  │ over B        │    │ 5+ times      │    │ B → A         │    │
│  └───────────────┘    └───────────────┘    └───────────────┘    │
│                                                                  │
│  Maximum Confidence: 1.0                                         │
│  Usage Threshold: confidence > 0.5 to apply preference           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.3 Episodic to Procedural Consolidation

```
┌─────────────────────────────────────────────────────────────────┐
│                   Memory Consolidation Pipeline                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Step 1: Collect Successful Episodes                             │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ SELECT * FROM project_episodes                               ││
│  │ WHERE outcome_success = true                                 ││
│  │ ORDER BY created_at DESC LIMIT 50                            ││
│  └─────────────────────────────────────────────────────────────┘│
│                           │                                      │
│                           ▼                                      │
│  Step 2: Group by User Intent                                    │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Intent: "quantify proteins" → 5 episodes                     ││
│  │ Intent: "align sequences"  → 8 episodes                      ││
│  │ Intent: "variant calling"  → 3 episodes                      ││
│  └─────────────────────────────────────────────────────────────┘│
│                           │                                      │
│                           ▼                                      │
│  Step 3: Pattern Detection (threshold: 3+ occurrences)          │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ IF group.length >= 3:                                        ││
│  │   • Extract common tool sequence                             ││
│  │   • Identify shared parameters                               ││
│  │   • Create triggerPattern from intent                        ││
│  └─────────────────────────────────────────────────────────────┘│
│                           │                                      │
│                           ▼                                      │
│  Step 4: Create Procedural Memory                                │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ INSERT INTO project_procedures (                             ││
│  │   trigger_pattern: "quantify proteins",                      ││
│  │   steps: [{tool: "maxquant", params: {...}}, ...],           ││
│  │   success_rate: 0.85,                                        ││
│  │   learned_from: [episode_ids]                                ││
│  │ )                                                            ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Personalization System

### 4.1 User Context Building

```typescript
// Built for every interaction
interface MemoryEnhancedContext {
  userMemory: {
    stats: {
      totalWorkflows: number;      // Experience indicator
      successRate: number;          // 0-1, quality indicator
    };
    preferences: Preference[];      // Ranked by confidence
    recentCorrections: Correction[]; // Avoid repeating mistakes
  };
  projectMemory: {
    project: Project;               // Domain, organisms, goal
    recentEpisodes: Episode[];      // What worked before
    procedures: Procedure[];        // Learned workflows
  };
}
```

### 4.2 Context Injection into LLM

```
┌─────────────────────────────────────────────────────────────────┐
│                    System Prompt Enhancement                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ## User Context                                                 │
│  - Experience Level: Expert (50+ workflows, 85% success)         │
│  - Primary Domain: Proteomics                                    │
│  - Preferred Tools: MaxQuant, DIA-NN, Perseus                    │
│                                                                  │
│  ## Recent Corrections (avoid these mistakes)                    │
│  - Suggested: MaxQuant for DIA → Corrected: DIA-NN               │
│  - Reason: "MaxQuant doesn't handle DIA data well"               │
│                                                                  │
│  ## Project Context                                              │
│  - Domain: Quantitative Proteomics                               │
│  - Organisms: Mouse, Human                                       │
│  - Goal: Identify differentially expressed proteins              │
│                                                                  │
│  ## Applicable Procedures (from past success)                    │
│  - "DIA Quantification" (85% success, used 12 times)             │
│    Steps: DIA-NN → Perseus → Volcano Plot                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.3 Expertise Level Inference

```
┌─────────────────────────────────────────────────────────────────┐
│                   Expertise Inference Methods                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Method 1: Complexity Preference Pattern                         │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ IF user consistently chooses complex tools → 'expert'        ││
│  │ IF user consistently chooses simple tools  → 'beginner'      ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  Method 2: Interaction Count Heuristic                           │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ interactions > 50  → 'expert'                                ││
│  │ interactions > 10  → 'intermediate'                          ││
│  │ interactions <= 10 → 'beginner'                              ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  Method 3: Success Rate Analysis                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ success_rate > 0.8 with 10+ workflows → likely expert        ││
│  │ success_rate < 0.5 with 5+ workflows  → needs guidance       ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  Combined Score: weighted average of all methods                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. API Endpoints

### 5.1 Preference Management

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/memory/user/preferences` | POST | Record new preference |
| `/api/memory/user/preferences` | GET | Get user preferences |
| `/api/memory/user/corrections` | POST | Record correction |

### 5.2 Episode Management

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/memory/interactions` | POST | Record interaction |
| `/api/memory/episodes/:id/outcome` | PUT | Update episode outcome |
| `/api/memory/projects/:id/consolidate` | POST | Trigger consolidation |

### 5.3 Procedure Management

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/memory/procedures` | GET | Get applicable procedures |
| `/api/memory/procedures/:id/usage` | POST | Record procedure usage |

---

## 6. File Locations

### Frontend (TypeScript)
- `frontend/server/memory-repository.ts` - Core memory service
- `frontend/server/memory-integration.ts` - LLM integration layer
- `frontend/server/user-patterns-service.ts` - Pattern caching
- `frontend/shared/ltm-schema.ts` - Database schema

### Backend (Python)
- `backend/lib/galaxy/ai/memory/agentic_memory.py` - Memory backend
- `backend/lib/galaxy/ai/agents/user_patterns_adapter.py` - Pattern DB access
- `backend/lib/galaxy/ai/agents/enhanced_domain_router.py` - Learned routing
- `backend/lib/galaxy/ai/services/workflow_learning_service.py` - Learning pipeline

---

## 7. Diagram Reference

See architecture diagram: `docs/architecture/26_self_learning_system.drawio.xml`

---

**Document Version**: 1.0
**Status**: Complete
