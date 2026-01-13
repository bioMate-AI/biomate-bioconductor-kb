# Database Schemas

This document provides comprehensive documentation of all database schemas in the Biomate platform.

---

## Overview

Biomate uses multiple databases organized in a 4-layer memory hierarchy:

| Layer | Database | Purpose | Schema File |
|-------|----------|---------|-------------|
| L1 | In-Memory | Hot session cache | `frontend/server/cache.ts` |
| L2 | Redis | Sessions, temp state | `frontend/server/redis-session.ts` |
| L3 | PostgreSQL | Main app + LTM | `frontend/shared/schema.ts`, `frontend/shared/ltm-schema.ts` |
| L4 | SQLite | Tool search index | `backend/lib/galaxy/tools/search_index.py` |

**Architecture Diagrams:** See `docs/architecture/19-24_*.drawio.xml` for visual representations.

---

## Main Application Schema (PostgreSQL)

### users

Primary user account table with authentication, subscription, and Galaxy integration.

```sql
CREATE TABLE users (
  id            SERIAL PRIMARY KEY,
  email         VARCHAR(255) UNIQUE NOT NULL,
  password      VARCHAR(255) NOT NULL,
  full_name     VARCHAR(255),

  -- Authentication
  email_verified BOOLEAN DEFAULT FALSE,
  verification_token VARCHAR(255),
  reset_token   VARCHAR(255),
  reset_token_expires TIMESTAMP,

  -- Subscription (Stripe integration)
  subscription_status VARCHAR(50) DEFAULT 'trialing',
  subscription_tier   VARCHAR(50) DEFAULT 'free',
  stripe_customer_id  VARCHAR(255),
  stripe_subscription_id VARCHAR(255),
  trial_ends_at TIMESTAMP,

  -- Galaxy Integration
  galaxy_user_id VARCHAR(255),
  galaxy_api_key VARCHAR(255),  -- Encrypted at rest

  -- AI Personalization
  workflow_preferences JSONB DEFAULT '{}',
  progressive_tuning   JSONB DEFAULT '{}',

  -- Timestamps
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_login TIMESTAMP
);

-- Indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_stripe_customer ON users(stripe_customer_id);
CREATE INDEX idx_users_galaxy_user ON users(galaxy_user_id);
```

**Key Fields:**
- `workflow_preferences`: User's preferred tools, parameters, output formats
- `progressive_tuning`: Learned AI behavior adjustments based on feedback

---

### audit_logs

SOC 2 / HIPAA compliant audit trail for all user actions.

```sql
CREATE TABLE audit_logs (
  id            SERIAL PRIMARY KEY,
  user_id       INTEGER REFERENCES users(id),

  -- Action Details
  action        VARCHAR(100) NOT NULL,  -- 'login', 'workflow_run', 'data_access'
  resource_type VARCHAR(100),           -- 'workflow', 'dataset', 'project'
  resource_id   VARCHAR(255),

  -- Request Context
  ip_address    VARCHAR(45),
  user_agent    TEXT,
  request_body  JSONB,    -- Sensitive fields redacted
  response_code INTEGER,

  -- Timestamps
  created_at    TIMESTAMP DEFAULT NOW()
);

-- Indexes for compliance queries
CREATE INDEX idx_audit_user ON audit_logs(user_id);
CREATE INDEX idx_audit_action ON audit_logs(action);
CREATE INDEX idx_audit_created ON audit_logs(created_at);
CREATE INDEX idx_audit_resource ON audit_logs(resource_type, resource_id);
```

---

### workflow_executions

Tracks Galaxy workflow invocations and their status.

```sql
CREATE TABLE workflow_executions (
  id                  SERIAL PRIMARY KEY,
  user_id             INTEGER REFERENCES users(id),
  ltm_workflow_id     INTEGER REFERENCES ltm_workflows(id),

  -- Galaxy References
  galaxy_workflow_id    VARCHAR(255) NOT NULL,
  galaxy_invocation_id  VARCHAR(255) NOT NULL,
  galaxy_history_id     VARCHAR(255) NOT NULL,

  -- Execution State
  status            VARCHAR(50) DEFAULT 'pending',  -- pending, running, ok, error
  input_parameters  JSONB,
  step_states       JSONB,      -- Per-step status tracking

  -- Timing
  started_at        TIMESTAMP,
  completed_at      TIMESTAMP,

  -- Timestamps
  created_at        TIMESTAMP DEFAULT NOW(),
  updated_at        TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_executions_user ON workflow_executions(user_id);
CREATE INDEX idx_executions_status ON workflow_executions(status);
CREATE INDEX idx_executions_galaxy ON workflow_executions(galaxy_invocation_id);
```

---

## Long-Term Memory Schema (PostgreSQL)

The LTM schema stores the agentic memory system data. It's defined in `frontend/shared/ltm-schema.ts` using Drizzle ORM.

### ltm_users

Extends main users table with LTM-specific metadata.

```sql
CREATE TABLE ltm_users (
  id            SERIAL PRIMARY KEY,
  user_id       INTEGER REFERENCES users(id) UNIQUE,

  -- Memory Configuration
  memory_enabled BOOLEAN DEFAULT TRUE,
  memory_retention_days INTEGER DEFAULT 365,

  -- Learning Settings
  explicit_learning_enabled BOOLEAN DEFAULT TRUE,
  implicit_learning_enabled BOOLEAN DEFAULT TRUE,
  emergent_learning_enabled BOOLEAN DEFAULT TRUE,

  -- Timestamps
  created_at    TIMESTAMP DEFAULT NOW(),
  updated_at    TIMESTAMP DEFAULT NOW()
);
```

---

### user_preferences

Stores learned user preferences (implicit learning).

```sql
CREATE TABLE user_preferences (
  id            SERIAL PRIMARY KEY,
  ltm_user_id   INTEGER REFERENCES ltm_users(id),

  -- Preference Details
  category      VARCHAR(100) NOT NULL,  -- 'tool_preference', 'parameter_default', 'output_format'
  key           VARCHAR(255) NOT NULL,
  value         TEXT NOT NULL,

  -- Learning Metrics
  confidence    DECIMAL(3,2) DEFAULT 0.50,  -- 0.00 to 1.00
  frequency     INTEGER DEFAULT 1,           -- Selection count

  -- Timestamps
  created_at    TIMESTAMP DEFAULT NOW(),
  updated_at    TIMESTAMP DEFAULT NOW(),

  UNIQUE(ltm_user_id, category, key)
);

-- Indexes
CREATE INDEX idx_prefs_user ON user_preferences(ltm_user_id);
CREATE INDEX idx_prefs_category ON user_preferences(category);
CREATE INDEX idx_prefs_confidence ON user_preferences(confidence DESC);
```

**Confidence Scoring:**
- Initial: 0.50
- Each repeated selection: +0.10
- User correction away: -0.20
- Maximum: 1.00

---

### correction_log

Stores explicit user corrections (explicit learning).

```sql
CREATE TABLE correction_log (
  id                  SERIAL PRIMARY KEY,
  ltm_user_id         INTEGER REFERENCES ltm_users(id),

  -- Correction Details
  context             TEXT NOT NULL,           -- What was the user trying to do
  original_suggestion TEXT NOT NULL,           -- What AI suggested
  corrected_value     TEXT NOT NULL,           -- What user corrected to
  correction_type     VARCHAR(100),            -- 'tool_selection', 'parameter', 'workflow_step'

  -- Learning Weight
  importance_score    DECIMAL(3,2) DEFAULT 0.80,  -- Explicit corrections weighted highly

  -- Metadata
  metadata            JSONB DEFAULT '{}',

  -- Timestamps
  created_at          TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_corrections_user ON correction_log(ltm_user_id);
CREATE INDEX idx_corrections_type ON correction_log(correction_type);
CREATE INDEX idx_corrections_created ON correction_log(created_at DESC);
```

---

### projects

User projects with associated context and knowledge.

```sql
CREATE TABLE projects (
  id            SERIAL PRIMARY KEY,
  ltm_user_id   INTEGER REFERENCES ltm_users(id),

  -- Project Info
  name          VARCHAR(255) NOT NULL,
  description   TEXT,
  domain        VARCHAR(100),  -- 'genomics', 'proteomics', 'pharmacology', etc.

  -- Status
  status        VARCHAR(50) DEFAULT 'active',

  -- Timestamps
  created_at    TIMESTAMP DEFAULT NOW(),
  updated_at    TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_projects_user ON projects(ltm_user_id);
CREATE INDEX idx_projects_domain ON projects(domain);
CREATE INDEX idx_projects_status ON projects(status);
```

---

### project_knowledge

Accumulated knowledge about a project (datasets, organisms, parameters).

```sql
CREATE TABLE project_knowledge (
  id            SERIAL PRIMARY KEY,
  project_id    INTEGER REFERENCES projects(id),

  -- Knowledge Entry
  knowledge_type VARCHAR(100) NOT NULL,  -- 'dataset_info', 'organism', 'parameter_set'
  key           VARCHAR(255) NOT NULL,
  content       JSONB NOT NULL,

  -- Confidence
  confidence    DECIMAL(3,2) DEFAULT 0.70,
  source        VARCHAR(100),  -- 'user_stated', 'inferred', 'file_metadata'

  -- Timestamps
  created_at    TIMESTAMP DEFAULT NOW(),
  updated_at    TIMESTAMP DEFAULT NOW(),

  UNIQUE(project_id, knowledge_type, key)
);

-- Indexes
CREATE INDEX idx_knowledge_project ON project_knowledge(project_id);
CREATE INDEX idx_knowledge_type ON project_knowledge(knowledge_type);
```

---

### workflows (LTM)

Saved workflow definitions with success tracking.

```sql
CREATE TABLE ltm_workflows (
  id            SERIAL PRIMARY KEY,
  project_id    INTEGER REFERENCES projects(id),

  -- Workflow Definition
  name          VARCHAR(255) NOT NULL,
  description   TEXT,
  definition    JSONB NOT NULL,         -- Galaxy .ga format
  tags          TEXT[],

  -- Success Tracking
  run_count     INTEGER DEFAULT 0,
  success_count INTEGER DEFAULT 0,
  success_rate  DECIMAL(5,2) DEFAULT 0.00,

  -- Source
  source        VARCHAR(100) DEFAULT 'ai_generated',  -- 'ai_generated', 'user_created', 'biomni'

  -- Timestamps
  created_at    TIMESTAMP DEFAULT NOW(),
  updated_at    TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_ltm_workflows_project ON ltm_workflows(project_id);
CREATE INDEX idx_ltm_workflows_success ON ltm_workflows(success_rate DESC);
CREATE INDEX idx_ltm_workflows_tags ON ltm_workflows USING GIN(tags);
```

---

### sessions

Conversation sessions for context management.

```sql
CREATE TABLE sessions (
  id            SERIAL PRIMARY KEY,
  ltm_user_id   INTEGER REFERENCES ltm_users(id),
  project_id    INTEGER REFERENCES projects(id),

  -- Session State
  status        VARCHAR(50) DEFAULT 'active',

  -- Context Summary
  summary       TEXT,                    -- LLM-generated session summary
  key_entities  JSONB DEFAULT '[]',      -- Extracted entities (genes, tools, datasets)

  -- Timestamps
  created_at    TIMESTAMP DEFAULT NOW(),
  updated_at    TIMESTAMP DEFAULT NOW(),
  ended_at      TIMESTAMP
);

-- Indexes
CREATE INDEX idx_sessions_user ON sessions(ltm_user_id);
CREATE INDEX idx_sessions_project ON sessions(project_id);
CREATE INDEX idx_sessions_status ON sessions(status);
```

---

### conversation_messages

Individual messages within sessions.

```sql
CREATE TABLE conversation_messages (
  id            SERIAL PRIMARY KEY,
  session_id    INTEGER REFERENCES sessions(id),

  -- Message Content
  role          VARCHAR(50) NOT NULL,    -- 'user', 'assistant', 'system'
  content       TEXT NOT NULL,

  -- Metadata
  metadata      JSONB DEFAULT '{}',      -- tool_calls, tokens, thinking_content

  -- Timestamps
  created_at    TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_messages_session ON conversation_messages(session_id);
CREATE INDEX idx_messages_role ON conversation_messages(role);
CREATE INDEX idx_messages_created ON conversation_messages(created_at);
```

---

### project_episodes

Episodic memory - specific interaction instances for emergent learning.

```sql
CREATE TABLE project_episodes (
  id            SERIAL PRIMARY KEY,
  project_id    INTEGER REFERENCES projects(id),
  session_id    INTEGER REFERENCES sessions(id),

  -- Episode Content
  trigger       TEXT NOT NULL,           -- What triggered this episode
  action        TEXT NOT NULL,           -- What action was taken
  outcome       VARCHAR(50) NOT NULL,    -- 'success', 'failure', 'partial'

  -- Learning Metrics
  confidence    DECIMAL(3,2) DEFAULT 0.70,

  -- Metadata
  context       JSONB DEFAULT '{}',      -- Additional context

  -- Timestamps
  created_at    TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_episodes_project ON project_episodes(project_id);
CREATE INDEX idx_episodes_outcome ON project_episodes(outcome);
CREATE INDEX idx_episodes_trigger ON project_episodes USING GIN(to_tsvector('english', trigger));
```

---

### project_procedures

Emergent procedural knowledge - automatically generated from repeated episodes.

```sql
CREATE TABLE project_procedures (
  id            SERIAL PRIMARY KEY,
  project_id    INTEGER REFERENCES projects(id),

  -- Procedure Definition
  name          VARCHAR(255) NOT NULL,
  description   TEXT,
  trigger_pattern TEXT NOT NULL,          -- Pattern that triggers this procedure
  steps         JSONB NOT NULL,           -- Ordered list of steps

  -- Source Episodes
  source_episode_ids INTEGER[],           -- Episodes that generated this

  -- Metrics
  success_rate  DECIMAL(5,2) DEFAULT 0.00,
  usage_count   INTEGER DEFAULT 0,

  -- Timestamps
  created_at    TIMESTAMP DEFAULT NOW(),
  updated_at    TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_procedures_project ON project_procedures(project_id);
CREATE INDEX idx_procedures_trigger ON project_procedures USING GIN(to_tsvector('english', trigger_pattern));
CREATE INDEX idx_procedures_success ON project_procedures(success_rate DESC);
```

**Emergent Learning Rule:** When 3+ similar episodes share a trigger pattern, automatically generate a procedure.

---

## AI Tool Database (SQLite)

### tools

Main tool metadata table.

```sql
CREATE TABLE tools (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  description   TEXT,

  -- Classification
  section       TEXT,                     -- Tool section in Galaxy
  panel_section TEXT,                     -- Panel section path

  -- Tool Details
  version       TEXT,
  repository    TEXT,                     -- ToolShed repository

  -- Search Optimization
  keywords      TEXT,                     -- Extracted keywords

  -- Timestamps
  indexed_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### tools_fts

Full-text search virtual table using FTS5.

```sql
CREATE VIRTUAL TABLE tools_fts USING fts5(
  id,
  name,
  description,
  keywords,
  content='tools',
  content_rowid='rowid',
  tokenize='porter unicode61'
);
```

**BM25 Ranking:** SQLite FTS5 provides built-in BM25 ranking for relevance scoring.

### Vector Embeddings

Tool embeddings are stored separately in NPZ format for semantic search.

| Component | Details |
|-----------|---------|
| Model | all-MiniLM-L6-v2 (sentence-transformers) |
| Dimensions | 384 |
| Storage | `tools_embeddings.npz` |
| Index | Approximate nearest neighbor (optional FAISS) |

**Hybrid Search Formula:**
```
combined_score = 0.6 * bm25_score + 0.4 * cosine_similarity
```

---

## Schema Relationships

```
┌─────────────────────────────────────────────────────────────────────┐
│                        MAIN APPLICATION                             │
├─────────────────────────────────────────────────────────────────────┤
│  users ─────────────────────────────────────────────────────────┐   │
│    │                                                            │   │
│    ├──→ audit_logs                                              │   │
│    │                                                            │   │
│    └──→ workflow_executions ──→ ltm_workflows                   │   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     LONG-TERM MEMORY (LTM)                          │
├─────────────────────────────────────────────────────────────────────┤
│  users ──→ ltm_users ──┬──→ user_preferences                        │
│                        │                                            │
│                        ├──→ correction_log                          │
│                        │                                            │
│                        └──→ projects ──┬──→ project_knowledge        │
│                                        │                            │
│                                        ├──→ ltm_workflows            │
│                                        │                            │
│                                        ├──→ sessions ──→ messages    │
│                                        │                            │
│                                        ├──→ project_episodes         │
│                                        │                            │
│                                        └──→ project_procedures       │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     AI TOOL DATABASE (SQLite)                       │
├─────────────────────────────────────────────────────────────────────┤
│  tools ──→ tools_fts (virtual)                                     │
│    │                                                               │
│    └──→ embeddings (NPZ file)                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## ORM Usage (Drizzle)

BioMate uses Drizzle ORM for type-safe database access.

### Schema Definition

```typescript
// frontend/shared/ltm-schema.ts
import { pgTable, serial, varchar, decimal, jsonb, timestamp, integer, boolean, text } from 'drizzle-orm/pg-core';

export const userPreferences = pgTable('user_preferences', {
  id: serial('id').primaryKey(),
  ltmUserId: integer('ltm_user_id').references(() => ltmUsers.id),
  category: varchar('category', { length: 100 }).notNull(),
  key: varchar('key', { length: 255 }).notNull(),
  value: text('value').notNull(),
  confidence: decimal('confidence', { precision: 3, scale: 2 }).default('0.50'),
  frequency: integer('frequency').default(1),
  createdAt: timestamp('created_at').defaultNow(),
  updatedAt: timestamp('updated_at').defaultNow()
});
```

### Query Example

```typescript
import { db } from './db';
import { userPreferences, eq, desc } from './ltm-schema';

// Get high-confidence preferences
const prefs = await db
  .select()
  .from(userPreferences)
  .where(eq(userPreferences.ltmUserId, userId))
  .orderBy(desc(userPreferences.confidence))
  .limit(10);
```

---

## Migrations

Database migrations are managed with Drizzle Kit.

```bash
# Generate migration
npx drizzle-kit generate:pg

# Run migrations
npx drizzle-kit push:pg

# View migrations
npx drizzle-kit studio
```

---

## Related Documentation

- [System Overview](../01-architecture/SYSTEM_OVERVIEW.md) - High-level architecture
- [Backend Services](../04-backend/SERVICES.md) - Memory repository layer
- [Architecture Diagrams](../architecture/) - Visual schemas (19-24_*.drawio.xml)

---

**Last Updated**: January 12, 2026
