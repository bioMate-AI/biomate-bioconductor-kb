# BioMate Multi-Agent System Upgrade Plan
**Date:** 2025-12-23 14:54
**Author:** Claude Code

## Overview
Upgrade BioMate's multi-agent system to add LLM-based routing, connect UserPatternsService, and implement auditing/learning capabilities.

## Problem Statement
1. **DomainRouter uses pure keywords** - No semantic understanding, misses nuanced intent
2. **UserPatternsService not connected** - Exists but not integrated with AgentOrchestrator
3. **No auditing** - Workflow generation attempts not recorded
4. **No learning** - System doesn't learn from user corrections or errors

---

## Architecture Summary

```
User Query
    │
    ▼
┌─────────────────────────────────────┐
│  EnhancedDomainRouter               │
│  ┌─────────────┐  ┌───────────────┐ │
│  │ Fast Path   │  │ LLM Semantic  │ │
│  │ (Keywords)  │──│ Analysis      │ │
│  │ <10ms       │  │ ~500ms        │ │
│  └─────────────┘  └───────────────┘ │
│         │                 │         │
│         ▼                 ▼         │
│  ┌─────────────────────────────────┐│
│  │ UserPatternsAdapter             ││
│  │ (Boost by user preferences)     ││
│  └─────────────────────────────────┘│
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│  WorkflowAuditService               │
│  (Record all generation attempts)   │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│  WorkflowLearningService            │
│  (Learn from corrections/outcomes)  │
└─────────────────────────────────────┘
```

---

## Phase 1: Database Schema (New Tables)

### File: `database/migrations/006_workflow_audit_and_learning.sql`

```sql
-- Workflow generation audit trail
CREATE TABLE IF NOT EXISTS workflow_generation_audit (
    audit_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    session_id TEXT,
    request_id TEXT UNIQUE NOT NULL,

    -- Input
    query_text TEXT NOT NULL,
    query_hash TEXT,
    user_context TEXT,  -- JSON

    -- Routing
    routing_decision TEXT,  -- JSON
    routing_method TEXT,  -- 'keyword', 'llm', 'hybrid'
    routing_latency_ms INTEGER,

    -- Result
    success INTEGER NOT NULL,
    workflow_id TEXT,
    confidence REAL,
    error_type TEXT,
    error_message TEXT,

    -- Performance
    total_latency_ms INTEGER,
    llm_calls_count INTEGER,

    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_audit_user ON workflow_generation_audit(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_success ON workflow_generation_audit(success);
CREATE INDEX IF NOT EXISTS idx_audit_created ON workflow_generation_audit(created_at);

-- User corrections for learning
CREATE TABLE IF NOT EXISTS workflow_user_corrections (
    correction_id INTEGER PRIMARY KEY AUTOINCREMENT,
    audit_id INTEGER NOT NULL,
    user_id TEXT NOT NULL,

    correction_type TEXT NOT NULL,  -- 'domain', 'tool_selection', 'parameters'
    original_value TEXT,  -- JSON
    corrected_value TEXT,  -- JSON
    correction_reason TEXT,

    timestamp TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (audit_id) REFERENCES workflow_generation_audit(audit_id)
);

CREATE INDEX IF NOT EXISTS idx_corrections_audit ON workflow_user_corrections(audit_id);
CREATE INDEX IF NOT EXISTS idx_corrections_type ON workflow_user_corrections(correction_type);

-- Learned keywords (from corrections)
CREATE TABLE IF NOT EXISTS learned_domain_keywords (
    keyword_id INTEGER PRIMARY KEY AUTOINCREMENT,
    domain TEXT NOT NULL,
    keyword TEXT NOT NULL,
    weight REAL DEFAULT 1.0,
    source TEXT,  -- 'user_correction', 'batch_learning'
    user_id TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(domain, keyword)
);

CREATE INDEX IF NOT EXISTS idx_learned_domain ON learned_domain_keywords(domain);
```

---

## Phase 2: New Services

### 2.1 UserPatternsAdapter
**File:** `lib/galaxy/ai/agents/user_patterns_adapter.py`

```python
class UserPatternsAdapter:
    """Adapter to make UserPatternsService usable by agents."""

    def get_routing_context(self, user_id: str) -> Dict:
        """Get minimal context for fast routing decisions."""
        # Returns: domain_preference, tool_preferences, expertise_level

    def record_workflow_attempt(self, user_id, query, routing, result, success):
        """Record a workflow generation attempt."""

    def update_domain_preference(self, user_id, domain, confidence_boost):
        """Update user's domain preference from feedback."""

    def record_tool_preference(self, user_id, preferred_tool, over_tool):
        """Record tool preference from user's correction."""
```

### 2.2 WorkflowAuditService
**File:** `lib/galaxy/ai/services/workflow_audit_service.py`

```python
class WorkflowAuditService:
    """Records all workflow generation attempts."""

    def start_audit(self, user_id, query, session_id) -> str:
        """Start auditing. Returns request_id."""

    def record_routing(self, request_id, routing_decision, method, latency_ms):
        """Record routing decision."""

    def complete_audit(self, request_id, success, workflow_id, error_type, error_msg):
        """Complete audit record."""

    def record_correction(self, audit_id, user_id, correction_type, original, corrected):
        """Record user correction for learning."""

    def get_failure_patterns(self, limit=100) -> List[Dict]:
        """Analyze common failure patterns."""
```

### 2.3 WorkflowLearningService
**File:** `lib/galaxy/ai/services/workflow_learning_service.py`

```python
class WorkflowLearningService:
    """Learns from user corrections and outcomes."""

    def learn_from_correction(self, user_id, audit_id, correction_type, original, corrected):
        """Learn from user correction."""
        # - Update user patterns
        # - Add learned keywords to router

    def learn_from_workflow_outcome(self, user_id, audit_id, success, user_kept, rating):
        """Learn from workflow execution outcome."""

    def batch_learn(self, lookback_days=7):
        """Periodic batch learning from interactions."""
```

---

## Phase 3: EnhancedDomainRouter

### File: `lib/galaxy/ai/agents/enhanced_domain_router.py`

**Hybrid Approach:**
1. **Fast Path (Keywords)**: If confidence > 0.7, return immediately (<10ms)
2. **LLM Path**: If confidence < 0.7, use LLM for semantic analysis (~500ms)
3. **User Pattern Boost**: Always apply user preferences to final scores

**LLM Routing Prompt:**
```
You are a bioinformatics domain classifier.

Available Domains: genomics, transcriptomics, proteomics, metabolomics,
single-cell, metagenomics, structural_biology, pharmacology, immunology,
cancer_biology, bioimaging, molecular_biology, biochemistry, database, literature

User Query: {query}
User Expertise: {expertise_level}
Recent Domains: {recent_domains}

Respond in JSON:
{
    "primary_domain": "domain_name",
    "secondary_domains": ["domain1", "domain2"],
    "confidence": 0.0-1.0,
    "complexity": "simple|standard|complex",
    "reasoning": "brief explanation"
}
```

---

## Phase 4: Integration Points

### 4.1 Modify AgentOrchestrator
**File:** `lib/galaxy/ai/agents/agent_orchestrator.py`

- Inject UserPatternsAdapter, WorkflowAuditService, WorkflowLearningService
- Replace DomainRouter with EnhancedDomainRouter
- Add audit calls at start/end of generate_workflow()

### 4.2 Modify AIAssistant
**File:** `lib/galaxy/ai/ai_assistant.py`

- Initialize all new services in agent_orchestrator property
- Pass services to AgentOrchestrator

### 4.3 Add API Endpoints
**File:** `lib/galaxy/webapps/galaxy/api/ai_assistant.py`

- `POST /api/ai/workflow/{request_id}/correction` - Submit correction
- `GET /api/ai/audit/history` - Get audit history

---

## Files to Create

| File | Purpose |
|------|---------|
| `database/migrations/006_workflow_audit_and_learning.sql` | Database schema |
| `lib/galaxy/ai/agents/user_patterns_adapter.py` | UserPatterns adapter |
| `lib/galaxy/ai/agents/enhanced_domain_router.py` | LLM-enhanced router |
| `lib/galaxy/ai/services/__init__.py` | Services package |
| `lib/galaxy/ai/services/workflow_audit_service.py` | Audit service |
| `lib/galaxy/ai/services/workflow_learning_service.py` | Learning service |

## Files to Modify

| File | Changes |
|------|---------|
| `lib/galaxy/ai/agents/agent_orchestrator.py` | Inject new services, use EnhancedDomainRouter |
| `lib/galaxy/ai/agents/__init__.py` | Export new classes |
| `lib/galaxy/ai/ai_assistant.py` | Initialize and inject services |
| `lib/galaxy/webapps/galaxy/api/ai_assistant.py` | Add correction/audit endpoints |

---

## Implementation Order

1. **Create database migration** - New tables for audit and learning
2. **Create UserPatternsAdapter** - Bridge to existing UserPatternsService
3. **Create WorkflowAuditService** - Record generation attempts
4. **Create EnhancedDomainRouter** - Hybrid keyword + LLM routing
5. **Create WorkflowLearningService** - Learn from corrections
6. **Modify AgentOrchestrator** - Inject and use new services
7. **Modify AIAssistant** - Initialize services
8. **Add API endpoints** - Correction and audit endpoints
9. **Test end-to-end** - Verify audit trail and learning

---

## Performance Targets

| Operation | Target Latency |
|-----------|----------------|
| Keyword routing (high confidence) | <10ms |
| LLM routing (low confidence) | <600ms |
| User patterns lookup | <20ms |
| Audit recording | <5ms (async) |
| Full workflow generation | <5s |

## Graceful Degradation

- If LLM fails → Fall back to keyword routing
- If UserPatternsAdapter fails → Route without personalization
- If AuditService fails → Log error, continue generation
- If LearningService fails → Log error, patterns not updated
