# Biomate Documentation

Welcome to the Biomate platform documentation. This guide helps you navigate the codebase and understand the system architecture.

---

## Quick Navigation

| I want to... | Go to |
|--------------|-------|
| Understand the system architecture | [System Overview](01-architecture/SYSTEM_OVERVIEW.md) |
| See how data flows through the system | [Information Flow](01-architecture/INFORMATION_FLOW.md) |
| Set up my development environment | [Development Setup](07-onboarding/DEVELOPMENT_SETUP.md) |
| Start contributing code | [New Developer Guide](07-onboarding/NEW_DEVELOPER_GUIDE.md) |
| Understand frontend components | [Frontend Components](02-frontend/COMPONENTS.md) |
| Understand backend services | [Backend Services](04-backend/SERVICES.md) |
| Look up an API endpoint | [REST API Reference](03-api/REST_API_REFERENCE.md) |

---

## What is Biomate?

Biomate is an **AI-powered bioinformatics workflow platform** that enables researchers to:

1. **Describe analyses in natural language** - "Analyze my RNA-seq data for differential expression"
2. **Get AI-generated workflows** - Claude-powered workflow generation with 2,177+ Galaxy tools
3. **Execute workflows** - Run analysis pipelines on Galaxy with real-time monitoring
4. **Access domain knowledge** - 397 pre-built Biomni workflows across 30+ biological domains

---

## Technology Stack

### Frontend
| Technology | Purpose |
|------------|---------|
| React 18 + TypeScript | UI framework |
| Vite | Build tool |
| Express.js | API server (frontend/server/) |
| Tailwind CSS | Styling |
| Radix UI | Component library |
| React Query | Data fetching |
| Drizzle ORM | Database access |

### Backend
| Technology | Purpose |
|------------|---------|
| Galaxy Platform | Workflow execution engine |
| Python 3.11+ | Backend language |
| Claude Sonnet 4.5 | Primary LLM for NLU |
| PostgreSQL | Primary database |
| AWS S3 | File storage |
| Stripe | Payment processing |

---

## Repository Structure

```
biomate/
├── frontend/                 # React + Express application
│   ├── client/src/          # React components & pages
│   │   ├── components/      # UI components (40+)
│   │   ├── hooks/           # Custom React hooks
│   │   ├── lib/             # API clients & utilities
│   │   ├── pages/           # Route pages
│   │   └── contexts/        # React contexts
│   ├── server/              # Express backend
│   │   ├── routes.ts        # API endpoints (~2,800 lines)
│   │   ├── galaxy-assistant.ts  # Claude AI integration
│   │   ├── galaxy-api-proxy.ts  # Galaxy API wrapper
│   │   ├── auth-service.ts  # Authentication
│   │   └── ...              # 35+ service modules
│   └── shared/              # Shared types & schemas
│
├── backend/                  # Galaxy + Python AI
│   ├── lib/galaxy/ai/       # AI modules (50+ files)
│   │   ├── ai_assistant.py  # Main orchestrator
│   │   ├── llm_client.py    # Multi-provider LLM
│   │   ├── galaxy_workflow_generator.py
│   │   └── ...
│   ├── biomni_workflows/    # 397 pre-built workflows
│   │   ├── galaxy/tools/biomni/  # Galaxy XML tools
│   │   └── nextflow/        # Nextflow conversions
│   └── lib/galaxy/webapps/galaxy/api/  # REST API
│
├── docs/                     # This documentation
├── scripts/                  # Utility scripts
├── docker/                   # Docker configurations
└── research/                 # Research materials
```

---

## Key Concepts

### 1. Hybrid Intelligence Architecture
Biomate uses a "hybrid intelligence" approach:
- **Claude Sonnet 4.5** handles natural language understanding
- **Tool Search (FTS5)** finds relevant Galaxy tools from 2,177+ indexed tools
- **Dataset RAG** matches user data to appropriate analysis types
- **Galaxy Platform** executes the actual bioinformatics workflows

### 2. Workflow Generation Pipeline
```
User Query → Intent Analysis → Tool Search → Workflow Generation → Dataset Assignment → Execution
```

### 3. Real-time Execution Monitoring
Workflows are monitored via Server-Sent Events (SSE) for real-time status updates.

---

## Getting Help

- **Slack**: #biomate-dev
- **Issues**: GitHub Issues
- **Documentation Questions**: Create a PR to improve docs

---

## Document Status

| Document | Status | Last Updated |
|----------|--------|--------------|
| System Overview | Complete | Jan 2026 |
| Information Flow | Complete | Jan 2026 |
| Development Setup | Complete | Jan 2026 |
| New Developer Guide | Complete | Jan 2026 |
| Frontend Components | Complete | Jan 2026 |
| Backend Services | Complete | Jan 2026 |
| REST API Reference | Complete | Jan 2026 |

---

**Last Updated**: January 9, 2026
