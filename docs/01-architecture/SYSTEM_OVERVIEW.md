# System Architecture Overview

This document provides a high-level view of the Biomate platform architecture.

---

## Executive Summary

Biomate is a full-stack bioinformatics platform combining:
- **Modern web frontend** (React + Express)
- **AI-powered workflow generation** (Claude Sonnet 4.5)
- **Galaxy execution engine** (2,177+ tools, 397 Biomni workflows)
- **Enterprise features** (auth, payments, SOC 2/HIPAA compliance)

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              BIOMATE PLATFORM                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         FRONTEND LAYER                                  │ │
│  │                                                                         │ │
│  │  ┌─────────────────────┐      ┌──────────────────────────────────────┐ │ │
│  │  │   React Client      │      │   Express Server                     │ │ │
│  │  │   (Port 5173)       │─────▶│   (Port 3000)                        │ │ │
│  │  │                     │      │                                      │ │ │
│  │  │   - Chat Interface  │      │   - routes.ts (API routing)          │ │ │
│  │  │   - Workflow UI     │      │   - galaxy-assistant.ts (Claude AI)  │ │ │
│  │  │   - Auth UI         │      │   - galaxy-api-proxy.ts (Galaxy)     │ │ │
│  │  │   - Project Mgmt    │      │   - auth-service.ts                  │ │ │
│  │  │                     │      │   - workflow-sse.ts (real-time)      │ │ │
│  │  └─────────────────────┘      └──────────────────────────────────────┘ │ │
│  │                                                                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                      │                                       │
│                                      ▼                                       │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         BACKEND LAYER                                   │ │
│  │                                                                         │ │
│  │  ┌───────────────────────────────────────────────────────────────────┐ │ │
│  │  │   AI ASSISTANT MODULE (/backend/lib/galaxy/ai/)                   │ │ │
│  │  │                                                                    │ │ │
│  │  │   ┌─────────────┐  ┌─────────────┐  ┌───────────────────────────┐ │ │ │
│  │  │   │ ai_assistant│  │ llm_client  │  │ galaxy_workflow_generator │ │ │ │
│  │  │   │    .py      │  │    .py      │  │          .py              │ │ │ │
│  │  │   │ (Orchestr.) │  │ (Claude/    │  │ (Constrained generation)  │ │ │ │
│  │  │   │             │  │  OpenAI)    │  │                           │ │ │ │
│  │  │   └─────────────┘  └─────────────┘  └───────────────────────────┘ │ │ │
│  │  │                                                                    │ │ │
│  │  │   ┌─────────────┐  ┌─────────────┐  ┌───────────────────────────┐ │ │ │
│  │  │   │tool_search  │  │dataset_rag  │  │ benchmark_knowledge       │ │ │ │
│  │  │   │    .py      │  │    .py      │  │          .py              │ │ │ │
│  │  │   │ (FTS5 2177+)│  │ (100GB lake)│  │ (Performance metrics)     │ │ │ │
│  │  │   └─────────────┘  └─────────────┘  └───────────────────────────┘ │ │ │
│  │  └───────────────────────────────────────────────────────────────────┘ │ │
│  │                                                                         │ │
│  │  ┌───────────────────────────────────────────────────────────────────┐ │ │
│  │  │   GALAXY PLATFORM                                                  │ │ │
│  │  │   - 2,177+ Galaxy tools                                           │ │ │
│  │  │   - 397 Biomni workflows (30+ biological domains)                 │ │ │
│  │  │   - Workflow execution engine                                      │ │ │
│  │  │   - Job scheduling & resource management                           │ │ │
│  │  └───────────────────────────────────────────────────────────────────┘ │ │
│  │                                                                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                      │                                       │
│                                      ▼                                       │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                      EXTERNAL SERVICES                                  │ │
│  │                                                                         │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐  │ │
│  │  │ PostgreSQL  │  │  AWS S3     │  │   Stripe    │  │ Claude API   │  │ │
│  │  │ (Database)  │  │ (Files)     │  │ (Payments)  │  │ (LLM)        │  │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └──────────────┘  │ │
│  │                                                                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Details

### Frontend Layer

#### React Client (`frontend/client/`)
| Directory | Purpose | Key Files |
|-----------|---------|-----------|
| `components/` | UI components | `chat-interface.tsx`, `workflow-artifact.tsx`, `parameter-dialog.tsx` |
| `hooks/` | Custom hooks | `useWorkflowExecution.ts` |
| `lib/` | API clients | `api.ts`, `projects.ts`, `ai-assistant-api.ts` |
| `pages/` | Route pages | `home.tsx`, `project-detail.tsx` |
| `contexts/` | React contexts | `auth-context.tsx` |

#### Express Server (`frontend/server/`)
| File | Lines | Purpose |
|------|-------|---------|
| `routes.ts` | ~2,800 | API endpoint definitions |
| `galaxy-assistant.ts` | ~800 | Claude AI integration, NLU |
| `galaxy-api-proxy.ts` | ~400 | Galaxy API wrapper |
| `workflow-sse.ts` | ~200 | Real-time execution updates |
| `auth-service.ts` | ~500 | JWT authentication |
| `storage.ts` | ~600 | In-memory/persistent storage |

### Backend Layer

#### AI Assistant Module (`backend/lib/galaxy/ai/`)
| File | Lines | Purpose |
|------|-------|---------|
| `ai_assistant.py` | ~73K | Main AI orchestrator |
| `llm_client.py` | ~17K | Multi-provider LLM (Claude, OpenAI, Deepseek) |
| `galaxy_workflow_generator.py` | ~36K | Tool-constrained workflow generation |
| `enhanced_workflow_generator.py` | ~23K | Multi-strategy generation |
| `benchmark_knowledge.py` | ~195K | Tool performance metrics |
| `unified_tool_search.py` | ~21K | FTS5 tool indexing |
| `intent_parser.py` | ~10K | User intent analysis |
| `task_decomposer.py` | ~16K | Task breakdown |

#### Galaxy Platform
- **2,177+ Galaxy tools** - Standard bioinformatics tools
- **397 Biomni workflows** - Pre-built domain-specific workflows
- **30+ biological domains** - Genomics, proteomics, pharmacology, etc.

### External Services

| Service | Purpose | Configuration |
|---------|---------|---------------|
| PostgreSQL | Primary database | `DATABASE_URL` |
| AWS S3 | File storage | `AWS_*` credentials |
| Claude API | Primary LLM | `ANTHROPIC_API_KEY` |
| OpenAI API | Fallback LLM | `OPENAI_API_KEY` |
| Stripe | Payments | `STRIPE_SECRET_KEY` |

---

## Data Flow Summary

### Chat → Workflow Generation
```
1. User sends message via React Chat Interface
2. Express routes.ts receives POST /api/chat
3. GalaxyAssistant.processMessage() called
4. Claude analyzes intent (NLU)
5. Parallel: Tool Search + Dataset RAG
6. Workflow generation with tool constraints
7. Response with workflow artifact
```

### Workflow Execution
```
1. User clicks "Run" on workflow artifact
2. POST /api/galaxy/workflows/invoke
3. Galaxy API receives workflow definition
4. Galaxy creates history & jobs
5. SSE connection streams status updates
6. Frontend updates UI in real-time
7. Completion → outputs available for download
```

---

## Memory & Learning Architecture

BioMate implements a sophisticated agentic memory system that enables the AI to learn from user interactions and improve over time.

### 4-Layer Memory Hierarchy

| Layer | Storage | TTL | Access Time | Purpose |
|-------|---------|-----|-------------|---------|
| L1 Volatile | In-Memory | 5 min | <1ms | Hot session data cache |
| L2 Transient | Redis | 24 hours | ~5ms | Sessions, temporary state |
| L3 Persistent | PostgreSQL LTM | Permanent | ~10-50ms | Long-term memory (10 tables) |
| L4 Searchable | SQLite + Vector | Permanent | ~20-100ms | FTS5 + 384-dim embeddings |

**Key Files:**
- `frontend/server/cache.ts` - L1 in-memory cache
- `frontend/server/redis-session.ts` - L2 Redis sessions
- `frontend/shared/ltm-schema.ts` - L3 LTM database schema
- `backend/lib/galaxy/tools/search_index.py` - L4 hybrid search

### Long-Term Memory Database (10 Tables)

| Domain | Tables | Purpose |
|--------|--------|---------|
| User | ltm_users, user_preferences, correction_log | User profiles, learned preferences, explicit corrections |
| Project | projects, project_knowledge, workflows | Project context, accumulated knowledge, saved workflows |
| Session | sessions, conversation_messages | Conversation history, message storage |
| Learning | project_episodes, project_procedures | Episodic memory, emergent procedural knowledge |

### 3 Learning Mechanisms

1. **Explicit Learning**: User corrections are stored with high importance (0.8) in `correction_log`
2. **Implicit Learning**: Repeated tool/workflow selections increase confidence (+0.1) in `user_preferences`
3. **Emergent Learning**: 3+ similar episodes trigger automatic procedure generation in `project_procedures`

### AI Tool Search (Hybrid)

```
Query → Parallel Search → Score Fusion → Top-K Results
         ├─ SQLite FTS5 (BM25 ranking)
         └─ Vector (all-MiniLM-L6-v2, 384-dim)

combined_score = 0.6 × bm25_score + 0.4 × cosine_similarity
```

**Architecture Diagrams:** See `docs/architecture/19-24_*.drawio.xml` for detailed visualizations.

---

## Security Architecture

### Authentication
- **JWT tokens** stored in HTTP-only cookies
- **Bcrypt** password hashing (12 rounds)
- **OAuth 2.0** support (Google, GitHub)
- **HIPAA** 15-minute session timeout

### Authorization
- Role-based access control (RBAC)
- Per-user Galaxy API keys
- Project-level permissions

### Data Protection
- **AES-256-GCM** encryption at rest
- **TLS 1.3** encryption in transit
- **SOC 2 Type II** compliance controls

---

## Scalability Considerations

### Current Architecture
- Single Express server
- PostgreSQL with connection pooling
- S3 for file storage (unlimited scale)

### Scaling Points
| Component | Scaling Strategy |
|-----------|-----------------|
| Express Server | Horizontal (load balancer) |
| PostgreSQL | Read replicas, connection pooling |
| Galaxy Jobs | Worker nodes, queue management |
| LLM Calls | Rate limiting, caching |

---

## Technology Versions

| Technology | Version | Notes |
|------------|---------|-------|
| Node.js | 20.x | LTS |
| React | 18.3.1 | Concurrent features |
| TypeScript | 5.6.3 | Strict mode |
| Python | 3.11+ | Backend AI |
| PostgreSQL | 14+ | Primary DB |
| Galaxy | Latest | Workflow engine |

---

## Related Documents

- [Information Flow](INFORMATION_FLOW.md) - Detailed request/response flows
- [Data Architecture](DATA_ARCHITECTURE.md) - Database schemas
- [Security Architecture](SECURITY_ARCHITECTURE.md) - Security controls
- [Frontend Overview](../02-frontend/FRONTEND_OVERVIEW.md) - Frontend details
- [Backend Overview](../03-backend/BACKEND_OVERVIEW.md) - Backend details

---

**Last Updated**: January 9, 2026
