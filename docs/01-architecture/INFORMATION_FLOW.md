# Information Flow Documentation

This document details how data flows through the Biomate system for key operations.

---

## Table of Contents
1. [Chat → Workflow Generation Flow](#1-chat--workflow-generation-flow)
2. [Workflow Execution Flow](#2-workflow-execution-flow)
3. [Authentication Flow](#3-authentication-flow)
4. [Dataset Upload Flow](#4-dataset-upload-flow)
5. [SSE Real-Time Updates](#5-sse-real-time-updates)

---

## 1. Chat → Workflow Generation Flow

The most important flow: user asks a question and receives an AI-generated workflow.

### Sequence Diagram

```
┌──────────┐     ┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│  React   │     │   Express   │     │  GalaxyAssistant │     │  Claude AI  │
│  Client  │     │   Server    │     │    (TS class)    │     │    (API)    │
└────┬─────┘     └──────┬──────┘     └────────┬─────────┘     └──────┬──────┘
     │                  │                     │                      │
     │  POST /api/chat  │                     │                      │
     │  {message: "..."}│                     │                      │
     │─────────────────▶│                     │                      │
     │                  │                     │                      │
     │                  │  processMessage()   │                      │
     │                  │────────────────────▶│                      │
     │                  │                     │                      │
     │                  │                     │   analyzeIntent()    │
     │                  │                     │─────────────────────▶│
     │                  │                     │                      │
     │                  │                     │   Intent + Keywords  │
     │                  │                     │◀─────────────────────│
     │                  │                     │                      │
     │                  │                     │  ┌─────────────────┐ │
     │                  │                     │  │ PARALLEL SEARCH │ │
     │                  │                     │  └─────────────────┘ │
     │                  │                     │                      │
     │                  │                     │   searchTools()      │
     │                  │                     │──────────┐           │
     │                  │                     │          │ FTS5 Query│
     │                  │                     │◀─────────┘           │
     │                  │                     │                      │
     │                  │                     │   searchDatasets()   │
     │                  │                     │──────────┐           │
     │                  │                     │          │ RAG Search│
     │                  │                     │◀─────────┘           │
     │                  │                     │                      │
     │                  │                     │  analyzeWorkflowNeed │
     │                  │                     │─────────────────────▶│
     │                  │                     │                      │
     │                  │                     │  Yes, generate       │
     │                  │                     │◀─────────────────────│
     │                  │                     │                      │
     │                  │                     │  generateWorkflow()  │
     │                  │                     │─────────────────────▶│
     │                  │                     │                      │
     │                  │                     │  Galaxy .ga JSON     │
     │                  │                     │◀─────────────────────│
     │                  │                     │                      │
     │                  │  GalaxyAssistantResponse                   │
     │                  │◀────────────────────│                      │
     │                  │                     │                      │
     │  JSON Response   │                     │                      │
     │  {message, workflow, tools, ...}       │                      │
     │◀─────────────────│                     │                      │
     │                  │                     │                      │
```

### Code Locations

| Step | File | Line | Function |
|------|------|------|----------|
| API Endpoint | `frontend/server/routes.ts` | 1193 | `POST /api/chat` |
| Process Message | `frontend/server/galaxy-assistant.ts` | 100 | `processMessage()` |
| Intent Analysis | `frontend/server/galaxy-assistant.ts` | 200+ | `analyzeIntent()` |
| Tool Search | `frontend/server/galaxy-assistant.ts` | 300+ | `searchRelevantTools()` |
| Workflow Generation | `frontend/server/galaxy-assistant.ts` | 400+ | `generateWorkflow()` |

### Request/Response Format

**Request:**
```typescript
POST /api/chat
Content-Type: application/json

{
  "message": "Analyze RNA-seq data for differential expression",
  "context": {
    "previousMessages": [...],
    "currentWorkflow": null,
    "selectedDatasets": ["dataset_123"],
    "userId": 1,
    "memorySessionId": "session_abc",  // Optional: for LTM
    "projectId": 5                      // Optional: for project context
  }
}
```

**Response:**
```typescript
{
  "message": "I've created an RNA-seq differential expression workflow...",
  "recommendedTools": [
    {
      "tool": { "id": "fastqc", "name": "FastQC", ... },
      "relevanceScore": 0.95,
      "reasoning": "Quality control for raw reads"
    }
  ],
  "recommendedDatasets": [...],
  "workflowSuggestion": {
    "shouldGenerate": true,
    "userIntent": "differential_expression",
    "confidence": 0.92,
    "reasoning": "User requested DE analysis"
  },
  "generatedWorkflow": {
    "name": "RNA-seq DE Analysis",
    "steps": {
      "0": { "tool_id": "fastqc", ... },
      "1": { "tool_id": "hisat2", ... },
      "2": { "tool_id": "featurecounts", ... },
      "3": { "tool_id": "deseq2", ... }
    }
  },
  "suggestions": [
    "Would you like to configure the reference genome?",
    "Do you want to add quality trimming before alignment?"
  ],
  "sources": {
    "toolSearchUsed": true,
    "datasetRAGUsed": true,
    "workflowGenerated": true,
    "thinkingUsed": false
  }
}
```

---

## 2. Workflow Execution Flow

How a generated workflow is executed on Galaxy.

### Sequence Diagram

```
┌──────────┐     ┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  React   │     │   Express   │     │ GalaxyAPIProxy│    │   Galaxy    │
│  Client  │     │   Server    │     │              │     │   Server    │
└────┬─────┘     └──────┬──────┘     └──────┬───────┘     └──────┬──────┘
     │                  │                   │                    │
     │ POST /api/galaxy/workflows/invoke    │                    │
     │ {workflow_id, inputs, parameters}    │                    │
     │─────────────────▶│                   │                    │
     │                  │                   │                    │
     │                  │ invokeWorkflow()  │                    │
     │                  │──────────────────▶│                    │
     │                  │                   │                    │
     │                  │                   │ POST /api/workflows│
     │                  │                   │───────────────────▶│
     │                  │                   │                    │
     │                  │                   │ Invocation Created │
     │                  │                   │◀───────────────────│
     │                  │                   │                    │
     │                  │ {id, state, ...}  │                    │
     │                  │◀──────────────────│                    │
     │                  │                   │                    │
     │ {invocation_id}  │                   │                    │
     │◀─────────────────│                   │                    │
     │                  │                   │                    │
     │ EventSource      │                   │                    │
     │ /api/galaxy/workflows/sse/{wf}/{inv} │                    │
     │─────────────────▶│                   │                    │
     │                  │                   │                    │
     │                  │ poller.startPolling(invocationId)      │
     │                  │──────────────────▶│                    │
     │                  │                   │                    │
     │                  │                   │ GET /invocations   │
     │                  │                   │───────────────────▶│
     │                  │                   │  (every 2 seconds) │
     │                  │                   │                    │
     │                  │                   │ State Update       │
     │                  │                   │◀───────────────────│
     │                  │                   │                    │
     │ SSE: step_state  │                   │                    │
     │◀─────────────────│                   │                    │
     │                  │                   │                    │
     │    ... (repeat until complete) ...   │                    │
     │                  │                   │                    │
     │ SSE: workflow_completed              │                    │
     │◀─────────────────│                   │                    │
     │                  │                   │                    │
```

### Code Locations

| Step | File | Line | Function |
|------|------|------|----------|
| Invoke Endpoint | `frontend/server/routes.ts` | 1071 | `POST /api/galaxy/workflows/invoke` |
| Galaxy API Call | `frontend/server/galaxy-api-proxy.ts` | - | `invokeWorkflow()` |
| SSE Endpoint | `frontend/server/routes.ts` | - | `GET /api/galaxy/workflows/sse/:id/:invId` |
| State Poller | `frontend/server/galaxy-state-poller.ts` | - | `startPolling()` |
| SSE Manager | `frontend/server/workflow-sse.ts` | 20 | `WorkflowSSEManager` |
| Client Hook | `frontend/client/src/hooks/useWorkflowExecution.ts` | 35 | `useWorkflowExecution()` |

### SSE Event Types

```typescript
interface WorkflowExecutionUpdate {
  type: 'workflow_state' | 'step_state' | 'job_log' | 'error' | 'progress_milestone';
  invocation_id: string;
  timestamp: string;
  data: {
    workflow_state?: 'new' | 'ready' | 'scheduled' | 'cancelled' | 'failed';
    step_id?: string;
    step_state?: 'new' | 'queued' | 'running' | 'ok' | 'error';
    job_id?: string;
    log?: string;
    error?: string;
    completed_steps?: number;
    total_steps?: number;
  };
}
```

---

## 3. Authentication Flow

JWT-based authentication with HTTP-only cookies.

### Login Sequence

```
┌──────────┐     ┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  React   │     │   Express   │     │  AuthService │     │ PostgreSQL  │
│  Client  │     │   Server    │     │              │     │             │
└────┬─────┘     └──────┬──────┘     └──────┬───────┘     └──────┬──────┘
     │                  │                   │                    │
     │ POST /api/auth/login                 │                    │
     │ {email, password}                    │                    │
     │─────────────────▶│                   │                    │
     │                  │                   │                    │
     │                  │ login()           │                    │
     │                  │──────────────────▶│                    │
     │                  │                   │                    │
     │                  │                   │ SELECT user        │
     │                  │                   │───────────────────▶│
     │                  │                   │                    │
     │                  │                   │ User record        │
     │                  │                   │◀───────────────────│
     │                  │                   │                    │
     │                  │                   │ bcrypt.compare()   │
     │                  │                   │──────────┐         │
     │                  │                   │          │         │
     │                  │                   │◀─────────┘         │
     │                  │                   │                    │
     │                  │                   │ jwt.sign()         │
     │                  │                   │──────────┐         │
     │                  │                   │          │         │
     │                  │                   │◀─────────┘         │
     │                  │                   │                    │
     │                  │ {user, token}     │                    │
     │                  │◀──────────────────│                    │
     │                  │                   │                    │
     │ Set-Cookie: biomate_token=<JWT>      │                    │
     │ {success, user, subscription}        │                    │
     │◀─────────────────│                   │                    │
     │                  │                   │                    │
```

### Token Verification (Middleware)

```
┌──────────┐     ┌─────────────────┐     ┌────────────────────┐
│  React   │     │ authenticateToken│    │     JWT Library    │
│  Client  │     │   (middleware)  │     │                    │
└────┬─────┘     └────────┬────────┘     └─────────┬──────────┘
     │                    │                        │
     │ GET /api/protected │                        │
     │ Cookie: biomate_token=<JWT>                 │
     │───────────────────▶│                        │
     │                    │                        │
     │                    │ jwt.verify()           │
     │                    │───────────────────────▶│
     │                    │                        │
     │                    │ {userId, email, ...}   │
     │                    │◀───────────────────────│
     │                    │                        │
     │                    │ req.user = payload     │
     │                    │──────────┐             │
     │                    │          │             │
     │                    │◀─────────┘             │
     │                    │                        │
     │                    │ next()                 │
     │                    │───────▶ Route Handler  │
     │                    │                        │
```

### Code Locations

| Step | File | Function |
|------|------|----------|
| Login Endpoint | `frontend/server/routes.ts:163` | `POST /api/auth/login` |
| Register Endpoint | `frontend/server/routes.ts:125` | `POST /api/auth/register` |
| Auth Service | `frontend/server/auth-service.ts` | `login()`, `register()` |
| Auth Middleware | `frontend/server/auth-middleware.ts` | `authenticateToken` |
| Password Hashing | `frontend/server/auth-service.ts` | bcrypt, 12 rounds |

---

## 4. Dataset Upload Flow

File upload to S3 with Galaxy integration.

### Upload Sequence

```
┌──────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  React   │     │   Express   │     │  S3 Service │     │   AWS S3    │
│  Client  │     │   Server    │     │             │     │             │
└────┬─────┘     └──────┬──────┘     └──────┬──────┘     └──────┬──────┘
     │                  │                   │                   │
     │ POST /api/s3/upload/init             │                   │
     │ {filename, fileSize, contentType}    │                   │
     │─────────────────▶│                   │                   │
     │                  │                   │                   │
     │                  │ generatePresignedUploadUrl()          │
     │                  │──────────────────▶│                   │
     │                  │                   │                   │
     │                  │                   │ Create presigned  │
     │                  │                   │ PUT URL           │
     │                  │                   │──────────────────▶│
     │                  │                   │                   │
     │                  │                   │ Presigned URL     │
     │                  │                   │◀──────────────────│
     │                  │                   │                   │
     │                  │ {uploadUrl, key}  │                   │
     │                  │◀──────────────────│                   │
     │                  │                   │                   │
     │ {uploadUrl, key} │                   │                   │
     │◀─────────────────│                   │                   │
     │                  │                   │                   │
     │ PUT to presigned │                   │                   │
     │ URL (direct)     │                   │                   │
     │───────────────────────────────────────────────────────▶ │
     │                  │                   │                   │
     │ 200 OK           │                   │                   │
     │◀──────────────────────────────────────────────────────── │
     │                  │                   │                   │
```

### Code Locations

| Step | File | Function |
|------|------|----------|
| Init Upload | `frontend/server/routes.ts:437` | `POST /api/s3/upload/init` |
| S3 Service | `frontend/server/s3-client.ts` | `generatePresignedUploadUrl()` |
| Multipart Upload | `frontend/server/s3-client.ts` | `generateMultipartUploadUrls()` |

---

## 5. SSE Real-Time Updates

How real-time workflow updates are streamed to the client.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         SSE ARCHITECTURE                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────┐                                                     │
│  │  React Client  │                                                     │
│  │                │                                                     │
│  │  useWorkflow   │◀───── EventSource ──────┐                          │
│  │  Execution()   │                          │                          │
│  └────────────────┘                          │                          │
│                                              │                          │
│                                    ┌─────────┴──────────┐               │
│                                    │  WorkflowSSEManager │               │
│                                    │                     │               │
│                                    │  - clients Map      │               │
│                                    │  - broadcastToClients()             │
│                                    └─────────┬──────────┘               │
│                                              │                          │
│                                    ┌─────────┴──────────┐               │
│                                    │ GalaxyStatePoller  │               │
│                                    │                     │               │
│                                    │  - pollInterval: 2s │               │
│                                    │  - emit('step_state')               │
│                                    │  - emit('workflow_completed')       │
│                                    └─────────┬──────────┘               │
│                                              │                          │
│                                    ┌─────────┴──────────┐               │
│                                    │  GalaxyAPIProxy    │               │
│                                    │                     │               │
│                                    │  - getInvocation() │               │
│                                    │  - getJobState()   │               │
│                                    └─────────┬──────────┘               │
│                                              │                          │
│                                    ┌─────────┴──────────┐               │
│                                    │   Galaxy Server    │               │
│                                    │                     │               │
│                                    │  /api/invocations  │               │
│                                    │  /api/jobs         │               │
│                                    └────────────────────┘               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Event Flow

1. **Client connects** to SSE endpoint: `GET /api/galaxy/workflows/sse/{workflowId}/{invocationId}`
2. **SSEManager** registers client and starts polling (if not already running)
3. **Poller** queries Galaxy API every 2 seconds
4. **State changes** detected → emit event
5. **SSEManager** broadcasts to all connected clients for that invocation
6. **Client** receives event and updates UI state

### Client-Side Hook

```typescript
// frontend/client/src/hooks/useWorkflowExecution.ts

export function useWorkflowExecution() {
  const [state, setState] = useState<WorkflowExecutionState>({...});
  const eventSourceRef = useRef<EventSource | null>(null);

  const connectToSSE = (workflowId: string, invocationId: string) => {
    const eventSource = new EventSource(
      `/api/galaxy/workflows/sse/${workflowId}/${invocationId}`
    );

    eventSource.onmessage = (event) => {
      const update: WorkflowExecutionUpdate = JSON.parse(event.data);

      switch (update.type) {
        case 'step_state':
          // Update step in state.steps Map
          break;
        case 'workflow_state':
          // Update workflow state
          break;
        case 'workflow_completed':
          // Close connection, mark complete
          break;
      }
    };
  };

  return { state, invokeWorkflow, isConnected };
}
```

---

## Key Design Decisions

### 1. Why Hybrid Intelligence?
- **Claude** excels at natural language understanding
- **FTS5** provides fast, accurate tool search (2,177+ tools)
- **RAG** enables semantic dataset matching
- **Galaxy** provides proven workflow execution

### 2. Why SSE over WebSockets?
- Simpler implementation for one-way updates
- Automatic reconnection in browsers
- Works through proxies/load balancers
- Sufficient for status streaming

### 3. Why JWT in HTTP-only Cookies?
- XSS protection (JavaScript can't access token)
- CSRF protection with SameSite=strict
- Automatic inclusion in requests
- HIPAA compliance for session management

### 4. Why Presigned URLs for S3?
- Large file uploads bypass server
- Reduces server memory/bandwidth
- Client uploads directly to S3
- Server only manages authentication

---

## Related Documents

- [System Overview](SYSTEM_OVERVIEW.md) - Architecture overview
- [Frontend Overview](../02-frontend/FRONTEND_OVERVIEW.md) - Frontend details
- [Backend Overview](../03-backend/BACKEND_OVERVIEW.md) - Backend details
- [API Reference](../04-api/REST_API_REFERENCE.md) - Endpoint details

---

**Last Updated**: January 9, 2026
