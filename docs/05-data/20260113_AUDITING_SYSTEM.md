# BioMate Auditing and Logging System

**Document ID**: 20260113_AUDITING_SYSTEM
**Created**: January 13, 2026
**Purpose**: Comprehensive documentation of BioMate's auditing, logging, and analytics capabilities

---

## Executive Summary

BioMate implements a **comprehensive auditing system** for regulatory compliance, debugging, and analytics:
1. All API requests automatically logged with middleware
2. Workflow executions tracked step-by-step
3. User interactions stored in Long-Term Memory
4. Real-time monitoring via SSE
5. Structured logging with levels and components

---

## 1. Architecture Overview

### 1.1 Auditing System Components

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     BioMate Auditing Architecture                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────┐    ┌───────────────┐    ┌───────────────┐           │
│  │   Express     │    │   Workflow    │    │   Memory      │           │
│  │   Middleware  │    │   SSE Stream  │    │   Service     │           │
│  └───────┬───────┘    └───────┬───────┘    └───────┬───────┘           │
│          │                    │                    │                    │
│          ▼                    ▼                    ▼                    │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                      Audit Service Layer                          │  │
│  │  • logAuth()         • logWorkflowExecutionStart()                │  │
│  │  • logDatasetUpload() • logWorkflowExecutionComplete()            │  │
│  │  • logAccessDenied()  • logSSEConnection()                        │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                  │                                      │
│                                  ▼                                      │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                     Database Layer                                │  │
│  │  ┌─────────────┐  ┌───────────────────┐  ┌────────────────────┐  │  │
│  │  │ audit_logs  │  │workflow_executions│  │  LTM Tables (10)   │  │  │
│  │  │             │  │                   │  │  • sessions        │  │  │
│  │  │ • userId    │  │ • status          │  │  • messages        │  │  │
│  │  │ • action    │  │ • completedSteps  │  │  • episodes        │  │  │
│  │  │ • details   │  │ • errorMessage    │  │  • corrections     │  │  │
│  │  │ • timestamp │  │ • durationMs      │  │  • preferences     │  │  │
│  │  └─────────────┘  └───────────────────┘  └────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Audit Data Flow

```
                     User Action (API Request)
                              │
                              ▼
              ┌───────────────────────────────┐
              │    Express Middleware          │
              │    (auditMiddleware)           │
              │                                │
              │  Captures:                     │
              │  • User ID / Session ID        │
              │  • HTTP method + path          │
              │  • IP address + User Agent     │
              │  • Response status             │
              │  • Duration (ms)               │
              └───────────────┬───────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │    Route Handler               │
              │                                │
              │  Specific logging:             │
              │  • workflow.generate           │
              │  • workflow.execute.start      │
              │  • dataset.upload              │
              │  • auth.login                  │
              └───────────────┬───────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │    Audit Service               │
              │                                │
              │  Enriches and stores:          │
              │  • reasoning (AI decisions)    │
              │  • resourceType + resourceId   │
              │  • success/failure status      │
              │  • error messages              │
              └───────────────┬───────────────┘
                              │
              ┌───────────────┴───────────────┐
              │                               │
              ▼                               ▼
     ┌─────────────────┐           ┌─────────────────┐
     │   audit_logs    │           │  Console Log    │
     │   (PostgreSQL)  │           │  (Backup)       │
     └─────────────────┘           └─────────────────┘
```

---

## 2. Audit Log Schema

### 2.1 Main Audit Table

```typescript
// frontend/shared/schema.ts
export const auditLogs = pgTable("audit_logs", {
  id: varchar("id").primaryKey(),

  // WHO
  userId: text("user_id"),              // null for anonymous
  sessionId: text("session_id"),

  // WHAT
  action: text("action").notNull(),     // e.g., "workflow.execute"
  resourceType: text("resource_type"),  // e.g., "workflow"
  resourceId: text("resource_id"),      // e.g., "wf-12345"

  // DETAILS
  details: text("details"),             // JSON context
  reasoning: text("reasoning"),         // AI decision explanation

  // WHEN
  timestamp: timestamp("timestamp").defaultNow(),

  // WHERE
  ipAddress: text("ip_address"),
  userAgent: text("user_agent"),

  // RESULT
  status: text("status"),               // "success" | "failure" | "error"
  errorMessage: text("error_message"),
  durationMs: text("duration_ms"),
});
```

### 2.2 Workflow Executions Table

```typescript
export const workflowExecutions = pgTable("workflow_executions", {
  id: varchar("id").primaryKey(),

  // OWNERSHIP
  userId: text("user_id").notNull(),
  projectId: text("project_id"),

  // GALAXY REFERENCES
  galaxyInvocationId: text("galaxy_invocation_id").notNull(),
  galaxyWorkflowId: text("galaxy_workflow_id"),
  galaxyHistoryId: text("galaxy_history_id"),

  // WORKFLOW DETAILS
  workflowName: text("workflow_name"),
  workflowDefinition: text("workflow_definition"),  // Full JSON

  // STATUS
  status: text("status"),                 // new | queued | running | ok | error
  startedAt: timestamp("started_at"),
  completedAt: timestamp("completed_at"),

  // PROGRESS
  totalSteps: text("total_steps"),
  completedSteps: text("completed_steps"),

  // ERROR TRACKING
  errorMessage: text("error_message"),
});
```

---

## 3. Audit Service Methods

### 3.1 Authentication Auditing

```typescript
// frontend/server/audit-service.ts
await auditService.logAuth(
  action: 'login' | 'logout' | 'register' | 'password_reset',
  userId: string | null,
  ipAddress: string,
  userAgent: string,
  success: boolean,
  errorMessage?: string
);
```

**Logged Actions:**
- `auth.login` - User login attempts
- `auth.logout` - User logout
- `auth.register` - New user registration
- `auth.password_reset` - Password reset requests

### 3.2 Workflow Auditing

```typescript
// Workflow Generation
await auditService.logWorkflowGeneration(
  userId: string | null,
  workflowName: string,
  toolsUsed: string[],
  reasoning: string,        // AI decision explanation
  success: boolean,
  errorMessage?: string
);

// Execution Start
await auditService.logWorkflowExecutionStart(
  userId: string | null,
  invocationId: string,
  workflowName: string,
  galaxyHistoryId: string
);

// Execution Complete
await auditService.logWorkflowExecutionComplete(
  userId: string | null,
  invocationId: string,
  status: 'success' | 'failure' | 'error',
  durationMs: number,
  errorMessage?: string
);
```

### 3.3 Dataset Auditing

```typescript
await auditService.logDatasetUpload(
  userId: string | null,
  datasetId: string,
  fileName: string,
  fileSize: number
);
```

### 3.4 Access Control Auditing

```typescript
await auditService.logAccessDenied(
  userId: string | null,
  action: string,
  resourceType: string,
  resourceId: string,
  reason: string,
  ipAddress: string
);
```

### 3.5 SSE Connection Auditing

```typescript
await auditService.logSSEConnection(
  userId: string | null,
  invocationId: string,
  action: 'connect' | 'disconnect',
  ipAddress: string
);
```

---

## 4. Automatic Request Logging

### 4.1 Audit Middleware

```typescript
// frontend/server/audit-service.ts
export function auditMiddleware(options: {
  excludePaths?: string[];
  logBody?: boolean;
} = {}) {
  return async (req, res, next) => {
    const startTime = Date.now();

    // Skip excluded paths
    if (excludePaths.includes(req.path)) {
      return next();
    }

    // Capture response
    res.on('finish', async () => {
      const duration = Date.now() - startTime;

      await auditService.log({
        userId: req.user?.id,
        sessionId: req.sessionID,
        action: `api.${req.method.toLowerCase()}.${req.path}`,
        resourceType: 'api',
        resourceId: req.path,
        ipAddress: req.ip,
        userAgent: req.get('user-agent'),
        status: res.statusCode < 400 ? 'success' : 'failure',
        durationMs: duration,
      });
    });

    next();
  };
}
```

### 4.2 Applied Configuration

```typescript
// frontend/server/routes.ts
app.use('/api', auditMiddleware({
  excludePaths: ['/api/health', '/api/workflow/sse'],
  logBody: false,  // Privacy: don't log request bodies
}));
```

---

## 5. Workflow Execution Tracking

### 5.1 Execution Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Workflow Execution Audit Trail                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. Invocation Request                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  POST /api/galaxy/workflows/invoke                               │   │
│  │  • Log: workflow.execute.start                                   │   │
│  │  • Create: workflow_executions record (status: 'new')            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  2. SSE Connection                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  GET /api/galaxy/workflows/sse/:workflowId/:invocationId        │   │
│  │  • Log: sse.connect                                              │   │
│  │  • Start: GalaxyStatePoller                                      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  3. Real-Time Updates (every 2 seconds)                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Events streamed:                                                │   │
│  │  • workflow_state: State changes (queued → running → ok)        │   │
│  │  • step_state: Per-step progress                                │   │
│  │  • job_log: Execution logs                                      │   │
│  │  • error: Error messages                                        │   │
│  │                                                                  │   │
│  │  Update: workflow_executions.completedSteps                     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  4. Completion                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Log: workflow.execute.complete                                │   │
│  │  • Update: workflow_executions (status, completedAt, duration)   │   │
│  │  • Log: sse.disconnect                                           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Execution Status Tracking

```typescript
// Status values in workflow_executions
type WorkflowStatus =
  | 'new'       // Just created
  | 'queued'    // Waiting for resources
  | 'running'   // Actively executing
  | 'ok'        // Completed successfully
  | 'error'     // Failed with error
  | 'cancelled' // User cancelled
```

---

## 6. Interaction Auditing (LTM)

### 6.1 Session Tracking

```typescript
// frontend/shared/ltm-schema.ts
export const sessions = pgTable("sessions", {
  id: uuid("id").primaryKey(),
  userId: uuid("user_id"),
  projectId: uuid("project_id"),

  // SESSION METADATA
  title: text("title"),
  startedAt: timestamp("started_at"),
  endedAt: timestamp("ended_at"),
  durationSeconds: integer("duration_seconds"),

  // CONTENT SUMMARY
  summary: text("summary"),              // AI-generated summary
  keyDecisions: jsonb("key_decisions"),
  toolsDiscussed: text("tools_discussed").array(),

  // STATISTICS
  messageCount: integer("message_count"),
  totalTokens: integer("total_tokens"),
  transcriptPath: text("transcript_path"),
});
```

### 6.2 Message History

```typescript
export const conversationMessages = pgTable("conversation_messages", {
  id: serial("id").primaryKey(),
  sessionId: uuid("session_id"),

  // MESSAGE CONTENT
  role: varchar("role"),      // 'user' | 'assistant' | 'system'
  content: text("content"),

  // TOOL USAGE
  toolsUsed: jsonb("tools_used"),  // [{tool, input, output}]
  contextSnapshot: jsonb("context_snapshot"),

  // METADATA
  tokenCount: integer("token_count"),
  thinkingContent: text("thinking_content"),
  createdAt: timestamp("created_at"),
});
```

### 6.3 Episode Tracking

```typescript
export const projectEpisodes = pgTable("project_episodes", {
  id: serial("id").primaryKey(),
  projectId: uuid("project_id"),
  sessionId: uuid("session_id"),

  // INTERACTION DETAILS
  userQuery: text("user_query"),
  assistantResponse: text("assistant_response"),
  toolsUsed: jsonb("tools_used"),

  // OUTCOME TRACKING
  outcomeSuccess: boolean("outcome_success"),
  userFeedback: integer("user_feedback"),    // 1-5 rating

  // ERROR TRACKING
  errorOccurred: boolean("error_occurred"),
  errorType: varchar("error_type"),
  errorMessage: text("error_message"),

  // LEARNING DATA
  whatWorked: text("what_worked").array(),
  whatFailed: text("what_failed").array(),
  lessonsLearned: text("lessons_learned").array(),
});
```

---

## 7. Structured Logging

### 7.1 Logger Configuration

```typescript
// frontend/server/logger.ts
export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
}

interface LogEntry {
  level: string;
  timestamp: string;        // ISO format
  component: string;        // Source component
  message: string;
  data?: any;
  error?: any;
}

// Pre-configured component loggers
export const serverLogger = createLogger('Server');
export const chatLogger = createLogger('Chat');
export const galaxyLogger = createLogger('Galaxy');
export const cacheLogger = createLogger('Cache');
```

### 7.2 Logger Methods

```typescript
logger.debug(message, data?)    // Development only
logger.info(message, data?)     // Normal operations
logger.warn(message, data?)     // Potential issues
logger.error(message, error?, data?)  // Errors

// API helpers
logger.request(method, path, data?)
logger.response(method, path, status, duration)

// Timed operations
await logger.time<T>(label, asyncFn)
```

---

## 8. Compliance Support

### 8.1 Audit Trail Completeness

| Question | Answer |
|----------|--------|
| **WHO** performed the action? | userId, sessionId |
| **WHAT** action was performed? | action, resourceType, resourceId |
| **WHEN** was it performed? | timestamp, durationMs |
| **WHERE** did it originate? | ipAddress, userAgent |
| **WHY** was this decision made? | reasoning (AI decisions) |
| **OUTCOME** of the action? | status, errorMessage |

### 8.2 Regulatory Compliance Features

- **Complete Audit Trail**: All actions logged with timestamps
- **User Attribution**: Every action linked to user/session
- **Error Tracking**: Full error messages preserved
- **Duration Metrics**: Performance accountability
- **AI Decision Reasoning**: Transparency in automated decisions
- **Data Access Logging**: Dataset operations tracked
- **Session Transcripts**: Full conversation history

---

## 9. API Endpoints

### 9.1 Audit Query Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/audit/logs` | GET | Query audit logs |
| `/api/audit/logs/:id` | GET | Get specific log entry |
| `/api/audit/user/:userId` | GET | Get user's audit history |
| `/api/audit/workflow/:id` | GET | Get workflow audit trail |

### 9.2 Workflow Execution Query

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/workflow-executions` | GET | List all executions |
| `/api/workflow-executions/:id` | GET | Get execution details |
| `/api/workflow-executions/:id/logs` | GET | Get execution logs |

---

## 10. File Locations

### Frontend
- `frontend/server/audit-service.ts` - Main audit service
- `frontend/server/logger.ts` - Structured logging
- `frontend/server/routes.ts` - Middleware configuration
- `frontend/shared/schema.ts` - audit_logs, workflow_executions tables
- `frontend/shared/ltm-schema.ts` - LTM tables for interaction tracking

### Backend
- `backend/lib/galaxy/ai/ai_assistant.py` - AI decision logging

---

## 11. Diagram Reference

See architecture diagram: `docs/architecture/27_auditing_system.drawio.xml`

---

**Document Version**: 1.0
**Status**: Complete
