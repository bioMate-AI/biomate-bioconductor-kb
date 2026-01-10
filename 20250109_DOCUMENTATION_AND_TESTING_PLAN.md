# Biomate Documentation & Testing Comprehensive Plan

**Date**: January 9, 2026
**Purpose**: Prepare Biomate for new team member onboarding
**Status**: Planning Phase

---

## Executive Summary

This document outlines a comprehensive plan for:
1. **Documentation**: Create structured documentation from high-level architecture to function-level details
2. **Testing**: Establish unit, module, and e2e testing frameworks to ensure system reliability

### Current State Assessment

| Category | Current State | Gap |
|----------|---------------|-----|
| **Documentation** | 100+ scattered .md files, some outdated | No unified structure, missing API docs, no onboarding guide |
| **Frontend Tests** | 1 test file (encryption.test.ts) | Missing component tests, hook tests, integration tests |
| **Backend Tests** | ~16 test_*.py files (mostly integration) | Missing unit tests, no pytest fixtures, low coverage |
| **E2E Tests** | Manual testing guide exists | No automated e2e framework |

---

# PART 1: DOCUMENTATION PLAN

## 1.1 Documentation Structure

Create a unified documentation structure under `/docs`:

```
/docs
├── 00-START-HERE.md                    # Quick navigation guide
├── 01-architecture/
│   ├── SYSTEM_OVERVIEW.md              # High-level architecture
│   ├── INFORMATION_FLOW.md             # Request/response flows
│   ├── DATA_ARCHITECTURE.md            # Database schemas, storage
│   └── SECURITY_ARCHITECTURE.md        # Auth, encryption, compliance
├── 02-frontend/
│   ├── FRONTEND_OVERVIEW.md            # Tech stack, structure
│   ├── COMPONENTS.md                   # Component library reference
│   ├── HOOKS.md                        # Custom hooks documentation
│   ├── STATE_MANAGEMENT.md             # React Query, context usage
│   ├── API_CLIENT.md                   # API client services
│   └── STYLING_GUIDE.md                # Tailwind, design system
├── 03-backend/
│   ├── BACKEND_OVERVIEW.md             # Tech stack, structure
│   ├── AI_ASSISTANT.md                 # AI orchestration system
│   ├── LLM_CLIENT.md                   # Multi-provider LLM integration
│   ├── WORKFLOW_GENERATOR.md           # Workflow generation pipeline
│   ├── TOOL_SEARCH.md                  # Tool discovery & RAG
│   ├── DATASET_RAG.md                  # Dataset search & selection
│   └── GALAXY_INTEGRATION.md           # Galaxy platform integration
├── 04-api/
│   ├── API_OVERVIEW.md                 # API design principles
│   ├── REST_API_REFERENCE.md           # Complete endpoint reference
│   ├── SSE_EVENTS.md                   # Server-Sent Events
│   └── ERROR_CODES.md                  # Error handling reference
├── 05-workflows/
│   ├── BIOMNI_TOOLS.md                 # 397 Biomni tool catalog
│   ├── WORKFLOW_TEMPLATES.md           # Pre-built workflow templates
│   └── TOOL_CATEGORIES.md              # 30+ biological domain tools
├── 06-operations/
│   ├── DEPLOYMENT.md                   # Deployment procedures
│   ├── CONFIGURATION.md                # Environment variables
│   ├── MONITORING.md                   # Logging, metrics, alerts
│   └── TROUBLESHOOTING.md              # Common issues & solutions
└── 07-onboarding/
    ├── NEW_DEVELOPER_GUIDE.md          # Step-by-step onboarding
    ├── DEVELOPMENT_SETUP.md            # Local development setup
    ├── CODE_CONVENTIONS.md             # Coding standards
    └── CONTRIBUTION_GUIDE.md           # How to contribute
```

---

## 1.2 Document Specifications

### 1.2.1 System Overview (01-architecture/SYSTEM_OVERVIEW.md)

**Content Requirements**:
- Platform mission and goals
- High-level component diagram
- Technology stack summary
- Key integrations (Galaxy, LLMs, databases)

**Diagram**: ASCII or Mermaid diagram showing:
```
┌─────────────────────────────────────────────────────────────────────┐
│                         BIOMATE PLATFORM                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────────┐     ┌──────────────────────────────────┐  │
│  │   FRONTEND          │     │   FRONTEND SERVER (Express)      │  │
│  │   (React + TS)      │────▶│   - routes.ts (API proxy)        │  │
│  │   Port: 5173        │     │   - galaxy-assistant.ts          │  │
│  │                     │     │   - workflow-sse.ts              │  │
│  │   - Chat Interface  │     │   - auth-service.ts              │  │
│  │   - Workflow UI     │     │   Port: 3000                     │  │
│  │   - Dataset Mgmt    │     │                                  │  │
│  └─────────────────────┘     └──────────────┬───────────────────┘  │
│                                              │                      │
│                                              ▼                      │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │   BACKEND (Galaxy + Python AI)                                 │ │
│  │                                                                │ │
│  │   ┌─────────────────────────────────────────────────────────┐ │ │
│  │   │  AI ASSISTANT (lib/galaxy/ai/)                          │ │ │
│  │   │  - ai_assistant.py (orchestrator)                       │ │ │
│  │   │  - llm_client.py (multi-provider)                       │ │ │
│  │   │  - galaxy_workflow_generator.py                         │ │ │
│  │   │  - biomni_dataset_rag.py                                │ │ │
│  │   │  - tool_search.py                                       │ │ │
│  │   └─────────────────────────────────────────────────────────┘ │ │
│  │                                                                │ │
│  │   ┌─────────────────────────────────────────────────────────┐ │ │
│  │   │  GALAXY PLATFORM                                        │ │ │
│  │   │  - 2,177+ Galaxy tools                                  │ │ │
│  │   │  - 397 Biomni workflows                                 │ │ │
│  │   │  - Workflow execution engine                            │ │ │
│  │   └─────────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │   EXTERNAL SERVICES                                            │ │
│  │   - Claude/OpenAI/Deepseek (LLM)                              │ │
│  │   - PostgreSQL (database)                                      │ │
│  │   - AWS S3 (file storage)                                      │ │
│  │   - Stripe (payments)                                          │ │
│  └───────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2.2 Information Flow (01-architecture/INFORMATION_FLOW.md)

**Critical Flows to Document**:

1. **Chat-to-Workflow Flow**:
   ```
   User Message → GalaxyAssistant.processMessage()
     → Intent Analysis (Claude)
     → Tool Search (FTS5 + RAG)
     → Workflow Generation
     → Dataset Assignment
     → Response with Workflow Artifact
   ```

2. **Workflow Execution Flow**:
   ```
   User clicks "Run" → POST /api/galaxy/workflows/invoke
     → Parameter validation
     → Galaxy API call
     → SSE connection established
     → Real-time status updates
     → Job completion → Output download
   ```

3. **Authentication Flow**:
   ```
   Login → JWT generation → HTTP-only cookie
     → Request middleware validation
     → Galaxy API key association
     → Session management
   ```

4. **Dataset Upload Flow**:
   ```
   File upload → S3 storage → Galaxy history creation
     → Dataset validation (AI-powered)
     → Workflow step mapping
   ```

### 1.2.3 Frontend Documentation (02-frontend/)

**Components to Document**:

| Component | File | Priority | Description |
|-----------|------|----------|-------------|
| ChatInterface | chat-interface.tsx | P0 | Main chat with AI assistant |
| WorkflowArtifact | workflow-artifact.tsx | P0 | Inline workflow display |
| WorkflowGraph | workflow-graph.tsx | P0 | Visual workflow editor |
| ParameterDialog | parameter-dialog.tsx | P0 | Step parameter configuration |
| ChatMessage | chat-message.tsx | P1 | Message rendering |
| DatasetValidation | dataset-validation-dialog.tsx | P1 | Dataset mapping UI |
| AuthContext | auth-context.tsx | P1 | Authentication provider |
| ProjectDetail | project-detail.tsx | P2 | Project management |

**Hooks to Document**:

| Hook | File | Description |
|------|------|-------------|
| useWorkflowExecution | useWorkflowExecution.ts | SSE-based workflow monitoring |
| useChat | (various) | Chat state management |
| useAuth | (auth-context) | Authentication state |

### 1.2.4 Backend Documentation (03-backend/)

**AI Modules to Document**:

| Module | File | Lines | Priority | Description |
|--------|------|-------|----------|-------------|
| AIAssistant | ai_assistant.py | ~530 | P0 | Main orchestrator |
| LLMClient | llm_client.py | ~435 | P0 | Multi-provider LLM |
| GalaxyWorkflowGenerator | galaxy_workflow_generator.py | ~494 | P0 | Constrained generation |
| BioMNIDatasetRAG | biomni_dataset_rag.py | ~486 | P1 | Dataset search |
| ToolSearchIndex | unified_tool_search.py | ~400 | P1 | FTS5 tool search |
| WorkflowDatasetSelector | workflow_dataset_selector.py | ~455 | P1 | Claude dataset assignment |
| IntentParser | intent_parser.py | ~150 | P2 | User intent analysis |
| TaskDecomposer | task_decomposer.py | ~160 | P2 | Task breakdown |

### 1.2.5 API Reference (04-api/)

**Endpoints to Document**:

| Category | Endpoint | Method | Description |
|----------|----------|--------|-------------|
| AI | /api/ai_assistant/generate_workflow | POST | Generate workflow from text |
| AI | /api/ai_assistant/citations/export | POST | Export citations as BibTeX |
| AI | /api/ai_assistant/pilot_run | POST | Execute pilot run |
| Workflow | /api/galaxy/workflows/invoke | POST | Execute workflow |
| Workflow | /api/galaxy/workflows/sse/:id | GET | SSE status stream |
| Tools | /api/galaxy/tools/search | GET | Search Galaxy tools |
| Datasets | /api/galaxy/datasets/search | GET | Search datasets |
| Auth | /api/auth/login | POST | User login |
| Auth | /api/auth/register | POST | User registration |
| Projects | /api/projects | GET/POST | Project management |

---

## 1.3 Documentation Priorities

### Phase 1: Critical (For Onboarding) - 5 documents
1. 00-START-HERE.md
2. 01-architecture/SYSTEM_OVERVIEW.md
3. 01-architecture/INFORMATION_FLOW.md
4. 07-onboarding/NEW_DEVELOPER_GUIDE.md
5. 07-onboarding/DEVELOPMENT_SETUP.md

### Phase 2: Core Reference - 8 documents
1. 02-frontend/FRONTEND_OVERVIEW.md
2. 02-frontend/COMPONENTS.md
3. 03-backend/BACKEND_OVERVIEW.md
4. 03-backend/AI_ASSISTANT.md
5. 04-api/REST_API_REFERENCE.md
6. 04-api/SSE_EVENTS.md
7. 03-backend/WORKFLOW_GENERATOR.md
8. 03-backend/LLM_CLIENT.md

### Phase 3: Complete Reference - Remaining documents

---

# PART 2: TESTING PLAN

## 2.1 Testing Strategy Overview

```
┌────────────────────────────────────────────────────────────────────┐
│                         TESTING PYRAMID                             │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│                          ┌─────────┐                                │
│                          │  E2E    │ ← 10-15 critical user journeys│
│                          │  Tests  │   (Playwright)                 │
│                          └────┬────┘                                │
│                      ┌────────┴────────┐                            │
│                      │   Integration   │ ← API, component integration│
│                      │      Tests      │   (Jest + Supertest)        │
│                      └────────┬────────┘                            │
│            ┌──────────────────┴──────────────────┐                  │
│            │           Unit Tests                │ ← Functions, utils│
│            │  (Jest/Vitest for TS, Pytest for Py)│   (80%+ coverage) │
│            └─────────────────────────────────────┘                  │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

## 2.2 Unit Testing Plan

### 2.2.1 Frontend Unit Tests (Vitest + React Testing Library)

**Target Coverage**: 80%

**Test Files to Create**:

```
frontend/client/src/
├── __tests__/
│   ├── components/
│   │   ├── chat-interface.test.tsx
│   │   ├── chat-message.test.tsx
│   │   ├── workflow-artifact.test.tsx
│   │   ├── workflow-graph.test.tsx
│   │   ├── parameter-dialog.test.tsx
│   │   ├── dataset-validation-dialog.test.tsx
│   │   └── auth-components.test.tsx
│   ├── hooks/
│   │   ├── useWorkflowExecution.test.ts
│   │   ├── useChat.test.ts
│   │   └── useAuth.test.ts
│   ├── lib/
│   │   ├── api.test.ts
│   │   ├── projects.test.ts
│   │   ├── chat-history.test.ts
│   │   └── ai-assistant-api.test.ts
│   └── utils/
│       ├── token-counter.test.ts
│       └── context-compressor.test.ts
│
frontend/server/
├── __tests__/
│   ├── encryption.test.ts           # ✅ EXISTS
│   ├── auth-service.test.ts         # NEW
│   ├── auth-middleware.test.ts      # NEW
│   ├── galaxy-api-proxy.test.ts     # NEW
│   ├── galaxy-assistant.test.ts     # NEW
│   ├── storage.test.ts              # NEW
│   ├── rate-limit.test.ts           # NEW
│   └── security-config.test.ts      # NEW
```

**Sample Test Cases (chat-interface.test.tsx)**:
```typescript
describe('ChatInterface', () => {
  it('renders message input field');
  it('sends message on submit');
  it('displays loading state during API call');
  it('renders workflow artifact when received');
  it('handles API errors gracefully');
  it('compresses context when token limit approached');
  it('maintains chat history across sessions');
});
```

### 2.2.2 Backend Unit Tests (Pytest)

**Target Coverage**: 80%

**Test Files to Create**:

```
backend/lib/galaxy/ai/
├── tests/
│   ├── __init__.py
│   ├── conftest.py                    # Shared fixtures
│   ├── test_ai_assistant.py           # Main orchestrator
│   ├── test_llm_client.py             # LLM integration
│   ├── test_intent_parser.py          # Intent analysis
│   ├── test_task_decomposer.py        # Task breakdown
│   ├── test_tool_recommender.py       # Tool suggestions
│   ├── test_galaxy_workflow_generator.py  # Workflow generation
│   ├── test_workflow_dataset_selector.py  # Dataset assignment
│   ├── test_biomni_dataset_rag.py     # Dataset search
│   ├── test_unified_tool_search.py    # Tool search
│   ├── test_workflow_search_rag.py    # Workflow templates
│   └── test_citation_enricher.py      # Citation management
```

**Sample Test Cases (test_llm_client.py)**:
```python
class TestLLMClient:
    def test_anthropic_provider_initialization(self):
        """Test Claude API client initialization."""

    def test_openai_provider_initialization(self):
        """Test OpenAI API client initialization."""

    def test_fallback_on_primary_failure(self):
        """Test automatic fallback when primary LLM fails."""

    def test_response_parsing(self):
        """Test correct parsing of LLM responses."""

    def test_token_counting(self):
        """Test accurate token counting for context management."""

    def test_rate_limiting_handling(self):
        """Test graceful handling of rate limit errors."""
```

**Fixtures (conftest.py)**:
```python
import pytest
from unittest.mock import Mock, AsyncMock

@pytest.fixture
def mock_llm_client():
    """Mock LLM client for testing without API calls."""
    client = Mock()
    client.generate_response = AsyncMock(return_value={
        "content": "Test response",
        "tokens_used": 100
    })
    return client

@pytest.fixture
def sample_workflow():
    """Sample Galaxy workflow for testing."""
    return {
        "name": "Test Workflow",
        "steps": {
            "0": {"tool_id": "fastqc", "inputs": {}},
            "1": {"tool_id": "hisat2", "inputs": {}}
        }
    }

@pytest.fixture
def mock_tool_index():
    """Mock tool search index."""
    return [
        {"id": "fastqc", "name": "FastQC", "description": "Quality control"},
        {"id": "hisat2", "name": "HISAT2", "description": "Alignment"}
    ]
```

---

## 2.3 Module/Integration Testing Plan

### 2.3.1 Frontend Integration Tests

**Test Files**:
```
frontend/
├── __integration_tests__/
│   ├── api-routes.test.ts           # Test all API routes
│   ├── auth-flow.test.ts            # Full auth flow
│   ├── chat-to-workflow.test.ts     # Chat → workflow generation
│   ├── workflow-execution.test.ts   # Workflow run flow
│   ├── dataset-upload.test.ts       # File upload → Galaxy
│   └── project-management.test.ts   # CRUD operations
```

**Sample Integration Test (chat-to-workflow.test.ts)**:
```typescript
describe('Chat to Workflow Integration', () => {
  it('generates workflow from natural language request', async () => {
    // 1. Send chat message
    const response = await request(app)
      .post('/api/chat')
      .send({ message: 'Analyze RNA-seq differential expression' });

    // 2. Verify workflow artifact in response
    expect(response.body.generatedWorkflow).toBeDefined();
    expect(response.body.generatedWorkflow.steps).toHaveLength(5);

    // 3. Verify tool IDs are valid
    const toolIds = Object.values(response.body.generatedWorkflow.steps)
      .map(step => step.tool_id);
    expect(toolIds).toContain('fastqc');
  });

  it('suggests follow-up questions after workflow generation');
  it('handles dataset attachment to generated workflow');
  it('supports workflow modification through chat');
});
```

### 2.3.2 Backend Integration Tests

**Test Files**:
```
backend/
├── integration_tests/
│   ├── test_workflow_generation_pipeline.py
│   ├── test_tool_search_integration.py
│   ├── test_dataset_rag_integration.py
│   ├── test_llm_workflow_generation.py
│   ├── test_galaxy_api_integration.py
│   └── test_api_endpoints.py
```

**Sample Integration Test**:
```python
class TestWorkflowGenerationPipeline:
    """Test the full workflow generation pipeline."""

    async def test_full_workflow_generation(self, mock_llm_client):
        """Test end-to-end workflow generation from user query."""
        assistant = AIAssistant(config, mock_llm_client)

        result = await assistant.generate_workflow_unified(
            user_query="Analyze RNA-seq data with DESeq2",
            context={}
        )

        assert result['success'] is True
        assert 'workflow' in result
        assert len(result['workflow']['steps']) > 0

        # Verify no hallucinated tools
        for step in result['workflow']['steps'].values():
            assert step['tool_id'] in VALID_TOOL_IDS

    async def test_template_matching_priority(self):
        """Verify template search runs before generation."""

    async def test_dataset_assignment(self):
        """Verify datasets are correctly assigned to workflow steps."""
```

---

## 2.4 End-to-End Testing Plan (Playwright)

### 2.4.1 E2E Test Structure

```
e2e/
├── playwright.config.ts
├── fixtures/
│   ├── test-data/
│   │   ├── sample.fastq
│   │   ├── sample.mzML
│   │   └── sample.csv
│   └── auth-fixtures.ts
├── tests/
│   ├── auth/
│   │   ├── login.spec.ts
│   │   ├── registration.spec.ts
│   │   └── password-reset.spec.ts
│   ├── chat/
│   │   ├── basic-conversation.spec.ts
│   │   ├── workflow-generation.spec.ts
│   │   └── context-compression.spec.ts
│   ├── workflows/
│   │   ├── create-workflow.spec.ts
│   │   ├── execute-workflow.spec.ts
│   │   ├── parameter-configuration.spec.ts
│   │   └── step-by-step-execution.spec.ts
│   ├── datasets/
│   │   ├── file-upload.spec.ts
│   │   ├── dataset-validation.spec.ts
│   │   └── dataset-attachment.spec.ts
│   ├── projects/
│   │   ├── project-crud.spec.ts
│   │   └── project-workflow-association.spec.ts
│   └── critical-paths/
│       ├── new-user-journey.spec.ts
│       ├── rna-seq-analysis.spec.ts
│       └── workflow-export.spec.ts
└── utils/
    ├── api-helpers.ts
    └── test-utils.ts
```

### 2.4.2 Critical User Journeys

**Journey 1: New User Onboarding**
```typescript
test('new user complete onboarding', async ({ page }) => {
  // 1. Register account
  await page.goto('/register');
  await page.fill('[name="email"]', 'test@example.com');
  await page.fill('[name="password"]', 'SecurePass123!');
  await page.click('button[type="submit"]');

  // 2. Verify email (mock)
  await verifyEmail('test@example.com');

  // 3. First login
  await page.goto('/login');
  await page.fill('[name="email"]', 'test@example.com');
  await page.fill('[name="password"]', 'SecurePass123!');
  await page.click('button[type="submit"]');

  // 4. Complete first chat
  await expect(page.locator('.chat-interface')).toBeVisible();
  await page.fill('.message-input', 'Hello, what can you help me with?');
  await page.click('.send-button');

  // 5. Verify AI response
  await expect(page.locator('.assistant-message')).toBeVisible();
});
```

**Journey 2: RNA-seq Analysis Workflow**
```typescript
test('complete RNA-seq analysis workflow', async ({ page }) => {
  // 1. Login
  await login(page, credentials);

  // 2. Upload dataset
  await page.setInputFiles('input[type="file"]', 'fixtures/sample.fastq');
  await expect(page.locator('.upload-success')).toBeVisible();

  // 3. Request workflow
  await page.fill('.message-input', 'Analyze this RNA-seq data for differential expression');
  await page.click('.send-button');

  // 4. Verify workflow artifact
  await expect(page.locator('.workflow-artifact')).toBeVisible();

  // 5. Configure parameters
  await page.click('.configure-parameters-button');
  await page.fill('[name="reference_genome"]', 'hg38');
  await page.click('.save-parameters');

  // 6. Execute workflow
  await page.click('.run-workflow-button');

  // 7. Monitor execution
  await expect(page.locator('.execution-status')).toContainText('Running');

  // 8. Verify completion (with timeout)
  await expect(page.locator('.execution-status')).toContainText('Completed', { timeout: 300000 });
});
```

---

## 2.5 Test Configuration

### 2.5.1 Frontend Test Config (vitest.config.ts)
```typescript
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test-setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'lcov'],
      exclude: ['node_modules/', 'dist/', '**/*.d.ts'],
      thresholds: {
        statements: 80,
        branches: 75,
        functions: 80,
        lines: 80,
      },
    },
  },
});
```

### 2.5.2 Backend Test Config (pytest.ini)
```ini
[pytest]
testpaths = tests lib/galaxy/ai/tests
python_files = test_*.py
python_functions = test_*
addopts = -v --cov=lib/galaxy/ai --cov-report=html --cov-report=term-missing
asyncio_mode = auto
filterwarnings = ignore::DeprecationWarning

[coverage:run]
branch = True
source = lib/galaxy/ai

[coverage:report]
fail_under = 80
exclude_lines =
    pragma: no cover
    def __repr__
    raise NotImplementedError
```

### 2.5.3 Playwright Config
```typescript
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e/tests',
  fullyParallel: false,  // Sequential for workflow tests
  retries: 2,
  timeout: 60000,
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'on-first-retry',
    video: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
    { name: 'firefox', use: { browserName: 'firefox' } },
  ],
  webServer: {
    command: 'npm run dev',
    port: 5173,
    reuseExistingServer: true,
  },
});
```

---

## 2.6 Test Priorities

### Phase 1: Foundation (Week 1-2)
| Test Type | Files | Priority |
|-----------|-------|----------|
| Backend Unit | test_llm_client.py | P0 |
| Backend Unit | test_ai_assistant.py | P0 |
| Backend Unit | test_galaxy_workflow_generator.py | P0 |
| Frontend Unit | encryption.test.ts (exists) | P0 |
| Frontend Unit | auth-service.test.ts | P0 |
| E2E | login.spec.ts | P0 |

### Phase 2: Core Flows (Week 3-4)
| Test Type | Files | Priority |
|-----------|-------|----------|
| Integration | chat-to-workflow.test.ts | P0 |
| Integration | workflow-execution.test.ts | P0 |
| E2E | workflow-generation.spec.ts | P0 |
| E2E | execute-workflow.spec.ts | P0 |
| Backend Unit | test_unified_tool_search.py | P1 |
| Backend Unit | test_biomni_dataset_rag.py | P1 |

### Phase 3: Comprehensive (Week 5-6)
- Remaining unit tests
- All integration tests
- Complete E2E coverage
- Performance tests

---

## 2.7 CI/CD Integration

### GitHub Actions Workflow (.github/workflows/tests.yml)
```yaml
name: Biomate Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  frontend-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Install dependencies
        run: cd frontend && npm ci
      - name: Run unit tests
        run: cd frontend && npm test -- --coverage
      - name: Run integration tests
        run: cd frontend && npm run test:integration
      - name: Upload coverage
        uses: codecov/codecov-action@v3

  backend-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: |
          cd backend
          pip install -r requirements.txt
          pip install pytest pytest-cov pytest-asyncio
      - name: Run tests
        run: cd backend && pytest --cov --cov-report=xml
      - name: Upload coverage
        uses: codecov/codecov-action@v3

  e2e-tests:
    runs-on: ubuntu-latest
    needs: [frontend-tests, backend-tests]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
      - name: Install Playwright
        run: npx playwright install --with-deps
      - name: Run E2E tests
        run: cd e2e && npx playwright test
      - name: Upload test artifacts
        uses: actions/upload-artifact@v3
        with:
          name: playwright-report
          path: e2e/playwright-report/
```

---

# PART 3: IMPLEMENTATION TIMELINE

## Week 1: Foundation
- [ ] Create /docs directory structure
- [ ] Write 00-START-HERE.md
- [ ] Write SYSTEM_OVERVIEW.md
- [ ] Write NEW_DEVELOPER_GUIDE.md
- [ ] Set up Vitest for frontend
- [ ] Set up Pytest for backend
- [ ] Write auth-service.test.ts
- [ ] Write test_llm_client.py

## Week 2: Core Documentation
- [ ] Write INFORMATION_FLOW.md
- [ ] Write FRONTEND_OVERVIEW.md
- [ ] Write BACKEND_OVERVIEW.md
- [ ] Write DEVELOPMENT_SETUP.md
- [ ] Write test_ai_assistant.py
- [ ] Write test_galaxy_workflow_generator.py

## Week 3: API & Integration
- [ ] Write REST_API_REFERENCE.md
- [ ] Write AI_ASSISTANT.md
- [ ] Write WORKFLOW_GENERATOR.md
- [ ] Implement chat-to-workflow.test.ts
- [ ] Implement workflow-execution.test.ts
- [ ] Set up Playwright

## Week 4: E2E & Completion
- [ ] Write SSE_EVENTS.md
- [ ] Complete remaining backend tests
- [ ] Implement login.spec.ts
- [ ] Implement workflow-generation.spec.ts
- [ ] Set up CI/CD pipeline
- [ ] Code coverage reports

## Week 5-6: Polish & Complete
- [ ] Complete all remaining documentation
- [ ] Achieve 80% test coverage
- [ ] Full E2E test suite
- [ ] Performance benchmarks
- [ ] Documentation review

---

# PART 4: SUCCESS METRICS

| Metric | Target | Measurement |
|--------|--------|-------------|
| Documentation Coverage | 100% of critical systems | All P0 docs complete |
| Unit Test Coverage (Frontend) | 80% | Jest/Vitest coverage report |
| Unit Test Coverage (Backend) | 80% | Pytest coverage report |
| Integration Test Coverage | 100% of critical flows | Flow checklist |
| E2E Test Coverage | 15 critical journeys | Playwright tests |
| New Developer Onboarding Time | < 2 days | Time to first PR |
| Documentation Freshness | Updated with code | Git commit tracking |

---

# PART 5: DELIVERABLES CHECKLIST

## Documentation Deliverables
- [ ] /docs directory with 25+ organized documents
- [ ] System architecture diagrams (ASCII/Mermaid)
- [ ] API reference with all endpoints
- [ ] Component documentation
- [ ] Onboarding guide for new developers

## Testing Deliverables
- [ ] Frontend unit test suite (80%+ coverage)
- [ ] Backend unit test suite (80%+ coverage)
- [ ] Integration test suite
- [ ] E2E test suite (15+ critical journeys)
- [ ] CI/CD pipeline configuration
- [ ] Coverage reports and dashboards

---

**Document Author**: Claude Code
**Last Updated**: January 9, 2026
**Status**: Ready for Review
