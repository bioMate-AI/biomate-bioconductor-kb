# Frontend-Backend Connection Issues Audit

**Document ID**: 20260113_FRONTEND_BACKEND_CONNECTION_ISSUES
**Created**: January 13, 2026
**Priority**: CRITICAL - Must fix for production

---

## Executive Summary

After auditing the frontend-backend connections, I found **multiple critical issues** that prevent the system from working as expected:

1. **Inconsistent API endpoints** - Chat interface bypasses main chat logic
2. **Hardcoded localhost URLs** - Will fail in production
3. **Missing error handling** - Silent failures confuse users
4. **Disconnected features** - Galaxy Assistant logic unused

---

## Issue 1: Chat Interface Uses Wrong API Endpoint

**Severity**: CRITICAL
**Location**: `frontend/client/src/components/chat-interface.tsx:141`

### Problem

The chat interface calls `/api/ai_assistant/generate_workflow` directly:

```typescript
// chat-interface.tsx line 141
const chatMutation = useMutation({
  mutationFn: async (content: string) => {
    const response = await fetch('/api/ai_assistant/generate_workflow', {  // WRONG!
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ request_text: content })
    })
    // ...
  }
})
```

### Expected Behavior

Should call `/api/chat` which provides full hybrid intelligence:

```typescript
// routes.ts line 1547 - THIS IS WHAT SHOULD BE CALLED
app.post("/api/chat", async (req, res) => {
  // Uses galaxyAssistant.processMessage() which:
  // 1. Analyzes intent with Claude
  // 2. Searches tools (2,177 indexed)
  // 3. Searches datasets (BioMNI RAG)
  // 4. Generates workflow if needed
  // 5. Generates natural language response
  // 6. Returns suggestions
})
```

### Impact

When using `/api/ai_assistant/generate_workflow` directly:
- Intent analysis is **SKIPPED**
- Tool search is **SKIPPED**
- Dataset RAG is **SKIPPED**
- User patterns/personalization is **SKIPPED**
- Response is only workflow JSON, no natural language

### Fix Required

```typescript
// chat-interface.tsx - Change line 141
const chatMutation = useMutation({
  mutationFn: async (content: string) => {
    const response = await fetch('/api/chat', {  // CORRECT
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: content,
        context: {
          previousMessages: displayMessages.slice(-10),
          // userId: currentUser?.id  // For personalization
        }
      })
    })
    // ...
  }
})
```

---

## Issue 2: Hardcoded Localhost URLs

**Severity**: HIGH
**Location**: `frontend/client/src/components/chat-interface.tsx:798`

### Problem

```typescript
// chat-interface.tsx line 798
await fetch(`http://localhost:8081/api/sessions/${chatSession.id}/compress`, {
  method: 'POST',
  headers: {
    'x-api-key': 'a7e9f73a7c25300e222d27c84efb10f6',  // HARDCODED API KEY!
    'Content-Type': 'application/json'
  },
  // ...
})
```

### Issues

1. **Hardcoded `localhost:8081`** - Will fail in any environment except local dev
2. **Hardcoded API key** - Security risk, exposed in client code
3. **Port mismatch** - Frontend runs on different port than backend

### Fix Required

```typescript
// Use relative URL (handled by Vite proxy) or environment variable
await fetch(`/api/sessions/${chatSession.id}/compress`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json'
    // API key should be handled by backend session, not passed from client
  },
  // ...
})
```

---

## Issue 3: Two Parallel Chat Architectures

**Severity**: MEDIUM
**Location**: `routes.ts`, `galaxy-assistant.ts`, `chat-interface.tsx`

### Problem

There are TWO chat paths that do different things:

**Path A (Full)**: `/api/chat` → `galaxy-assistant.ts` → Full hybrid intelligence
```
User Message → Intent Analysis → Tool Search → Dataset RAG → Workflow Gen → Response
```

**Path B (Partial)**: `/api/ai_assistant/generate_workflow` → Galaxy backend only
```
User Message → Direct Workflow Generation (no intent, no tools, no datasets)
```

The frontend uses **Path B**, missing all the intelligence from **Path A**.

### Fix Required

1. Frontend should use `/api/chat` for all messages
2. `/api/ai_assistant/generate_workflow` should be internal only
3. Consolidate to single chat flow

---

## Issue 4: Response Structure Mismatch

**Severity**: HIGH
**Location**: `chat-interface.tsx:153-227`

### Problem

The chat interface expects response from `/api/ai_assistant/generate_workflow`:

```typescript
// Expected from direct workflow endpoint
{
  success: boolean;
  workflow_ga: object;
  message: string;
  confidence: number;
}
```

But `/api/chat` returns different structure:

```typescript
// From /api/chat endpoint
{
  response: string;
  suggestions: string[];
  workflow: object;
  thinking_content?: string;
  metadata: {
    recommendedTools: [];
    recommendedDatasets: [];
    sources: {};
  }
}
```

### Fix Required

Update chat-interface.tsx to handle `/api/chat` response structure:

```typescript
onSuccess: (data) => {
  // Handle /api/chat response format
  const workflowData = data.workflow?.workflow_ga || data.workflow;
  const workflowSuccess = !!data.workflow;

  const aiMessage: Message = {
    id: (Date.now() + 1).toString(),
    content: data.response,  // Use natural language response
    role: "assistant",
    timestamp: new Date(),
    suggestions: data.suggestions || [],
    metadata: {
      type: workflowSuccess ? 'workflow' : 'text',
      workflow: workflowData,
      recommendedTools: data.metadata?.recommendedTools,
      recommendedDatasets: data.metadata?.recommendedDatasets,
      thinking_content: data.thinking_content,
    }
  }
}
```

---

## Issue 5: Missing Authentication Context

**Severity**: MEDIUM
**Location**: `chat-interface.tsx`

### Problem

Chat requests don't include user authentication:

```typescript
// No auth token passed
const response = await fetch('/api/ai_assistant/generate_workflow', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  // Missing: Authorization header
  body: JSON.stringify({ request_text: content })
})
```

### Impact

- Memory integration won't work (requires userId)
- User patterns/preferences not loaded
- Workflow history not associated with user
- Rate limiting may not work correctly

### Fix Required

```typescript
// Include auth token from context
const { token } = useAuth();  // or however auth is managed

const response = await fetch('/api/chat', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`  // Add auth
  },
  body: JSON.stringify({
    message: content,
    context: {
      memorySessionId: chatSession?.id,
      projectId: currentProject?.id,
    }
  })
})
```

---

## Issue 6: SSE Connection Not Used for Chat

**Severity**: LOW
**Location**: `useWorkflowExecution.ts`

### Current State

The SSE (Server-Sent Events) connection is well-implemented for workflow execution:
- `useWorkflowExecution.ts` connects to `/api/galaxy/workflows/sse/:workflowId/:invocationId`
- Handles `workflow_state`, `step_state`, `job_log`, `error` events
- Auto-reconnects on failure

### Missing

SSE is **not used for chat streaming**. All chat responses are synchronous.

### Recommendation

Consider adding streaming chat responses for better UX with long responses:

```typescript
// Optional enhancement for streaming
const eventSource = new EventSource('/api/chat/stream');
eventSource.onmessage = (event) => {
  appendToResponse(event.data);
};
```

---

## Issue 7: Demo Workflow Fallback Confusion

**Severity**: MEDIUM
**Location**: `chat-interface.tsx:162-181`

### Current Behavior

When workflow generation fails, a demo workflow is shown:

```typescript
if (!data.success || !data.workflow_ga) {
  workflowData = generateDemoWorkflow();  // Hardcoded RNA-seq workflow
  isDemo = true;
}
```

### Problem

Users might think the demo workflow is real and try to execute it, causing confusion when it fails or produces wrong results.

### Fix Required

1. Make demo workflows **clearly non-executable**
2. Disable "Run" button for demo workflows
3. Show prominent "DEMO - NOT EXECUTABLE" badge

---

## Issue 8: Galaxy URL Configuration

**Severity**: HIGH
**Location**: `galaxy-api-proxy.ts:32-33`

### Current State

```typescript
constructor(galaxyUrl?: string, apiKey?: string) {
  this.galaxyUrl = galaxyUrl || process.env.GALAXY_URL || 'http://localhost:8080';
  this.apiKey = apiKey || process.env.GALAXY_API_KEY;
}
```

### Potential Issues

1. **Default localhost** - If `GALAXY_URL` not set, defaults to localhost
2. **No validation** - Doesn't check if Galaxy is reachable
3. **API key exposure** - Key might not be set in production

### Fix Required

Add startup validation:

```typescript
constructor(galaxyUrl?: string, apiKey?: string) {
  this.galaxyUrl = galaxyUrl || process.env.GALAXY_URL;
  if (!this.galaxyUrl) {
    throw new Error('GALAXY_URL environment variable is required');
  }

  this.apiKey = apiKey || process.env.GALAXY_API_KEY;
  if (!this.apiKey) {
    console.warn('[GalaxyAPIProxy] No API key configured - some operations will fail');
  }

  // Validate connection on startup
  this.validateConnection();
}
```

---

## Quick Fix Priority List

### Must Fix Before Launch

| Priority | Issue | File | Effort |
|----------|-------|------|--------|
| 1 | Chat endpoint mismatch | `chat-interface.tsx:141` | Low |
| 2 | Hardcoded localhost URL | `chat-interface.tsx:798` | Low |
| 3 | Response structure handling | `chat-interface.tsx:153-227` | Medium |
| 4 | Add auth to chat requests | `chat-interface.tsx` | Low |
| 5 | Galaxy URL validation | `galaxy-api-proxy.ts` | Low |

### Should Fix

| Priority | Issue | File | Effort |
|----------|-------|------|--------|
| 6 | Demo workflow distinction | `chat-interface.tsx` | Low |
| 7 | Consolidate chat paths | `routes.ts` | Medium |

### Nice to Have

| Priority | Issue | File | Effort |
|----------|-------|------|--------|
| 8 | Streaming chat responses | Multiple | High |

---

## Next Steps

1. **Fix Issue 1 first** - This is blocking the main chat functionality
2. **Fix Issue 2** - Security and production deployment blocker
3. **Test the flow** - After fixes, run E2E test:
   ```
   User sends message → /api/chat → intent analysis → tool search → workflow gen → response displayed
   ```

---

**Document Version**: 1.0
**Status**: Ready for implementation
