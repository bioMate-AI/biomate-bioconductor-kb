# Backend Services Guide

This document describes the backend services in the Biomate Express server.

---

## Directory Structure

```
server/
├── index.ts              # Server entry point
├── routes.ts             # All API route handlers
├── db.ts                 # Database connection
├── storage.ts            # In-memory storage interface
├── auth-service.ts       # Authentication logic
├── auth-middleware.ts    # JWT authentication middleware
├── galaxy-assistant.ts   # AI assistant service
├── galaxy-api-proxy.ts   # Galaxy API integration
├── galaxy-state-poller.ts # SSE workflow updates
├── workflow-sse.ts       # SSE event management
├── encryption.ts         # Encryption utilities
├── email-service.ts      # Email sending
└── security-config.ts    # Security settings
```

---

## Core Services

### Galaxy Assistant

**File**: `server/galaxy-assistant.ts`

The main AI service that integrates Claude Sonnet 4.5 with Galaxy tools.

```typescript
import { GalaxyAssistant } from './galaxy-assistant';

const assistant = new GalaxyAssistant({
  anthropicApiKey: process.env.ANTHROPIC_API_KEY,
  galaxyAPIProxy: galaxyProxy
});
```

#### Key Methods

**processChat**: Handle user messages

```typescript
const response = await assistant.processChat({
  message: "Analyze RNA-seq data",
  sessionId: "uuid",
  history: previousMessages,
  context: {
    datasets: userDatasets,
    thinkingLevel: 'detailed'
  }
});

// Response structure:
{
  message: string,           // AI response text
  toolSuggestions: Tool[],   // Recommended tools
  datasetSuggestions: Dataset[], // Relevant datasets
  workflowSuggestion?: Workflow, // Generated workflow
  thinking?: string          // Reasoning (if enabled)
}
```

**generateWorkflow**: Create workflow from intent

```typescript
const workflow = await assistant.generateWorkflow({
  userIntent: "Differential expression analysis",
  datasets: inputDatasets,
  preferences: userPreferences
});
```

#### Architecture

```
User Message
    ↓
┌─────────────────────┐
│   Intent Analysis   │ ← Claude Sonnet 4.5
│   (NLU Layer)       │
└─────────────────────┘
    ↓
┌─────────────────────┐
│   Tool Search       │ ← BM25 Full-text Search
│   (2,177 tools)     │
└─────────────────────┘
    ↓
┌─────────────────────┐
│   Dataset RAG       │ ← BioMNI Dataset Index
│   (100+ GB)         │
└─────────────────────┘
    ↓
┌─────────────────────┐
│ Workflow Generation │ ← LLM + Validation
│   (.ga format)      │
└─────────────────────┘
```

---

### Galaxy API Proxy

**File**: `server/galaxy-api-proxy.ts`

Communicates with the Galaxy backend server.

```typescript
import { GalaxyAPIProxy } from './galaxy-api-proxy';

const proxy = new GalaxyAPIProxy(
  'http://localhost:8080',  // Galaxy URL
  'api_key'                 // Optional API key
);
```

#### Tool Operations

```typescript
// Search tools
const results = await proxy.searchTools({
  query: 'fastqc',
  category: 'Quality Control',
  limit: 20
});

// Get tool schema
const schema = await proxy.getToolSchema('fastqc');

// Get installed tools
const installed = await proxy.getInstalledTools();
```

#### Dataset Operations

```typescript
// Search datasets
const datasets = await proxy.searchDatasets({
  query: 'human proteome',
  category: 'proteomics'
});

// Get dataset details
const dataset = await proxy.getDataset('ds_id');
```

#### Workflow Operations

```typescript
// Create workflow
const workflow = await proxy.createWorkflow({
  name: 'My Pipeline',
  steps: workflowSteps
});

// Invoke workflow
const invocation = await proxy.invokeWorkflow(
  workflowId,
  historyId,
  inputs,
  parameters
);

// Get invocation status
const status = await proxy.getInvocationStatus(
  workflowId,
  invocationId
);
```

#### Job Operations

```typescript
// Get job details
const job = await proxy.getJob(jobId);

// Get job outputs
const stdout = await proxy.getJobStdout(jobId);
const stderr = await proxy.getJobStderr(jobId);

// Pause/Resume
await proxy.pauseJob(jobId);
await proxy.resumeJob(jobId);
```

---

### Auth Service

**File**: `server/auth-service.ts`

Handles user authentication, registration, and session management.

```typescript
import { authService } from './auth-service';
```

#### User Registration

```typescript
const result = await authService.register({
  email: 'user@example.com',
  password: 'securePassword',
  fullName: 'John Doe',
  termsAccepted: true
});

// Returns:
{
  user: SafeUser,    // User without password
  token: string,     // JWT token
  expiresIn: number  // Seconds until expiry
}
```

#### Login

```typescript
const result = await authService.login({
  email: 'user@example.com',
  password: 'securePassword'
});
```

#### Password Management

```typescript
// Request reset
await authService.sendPasswordResetEmail(email);

// Reset password
await authService.resetPassword(token, newPassword);
```

#### Email Verification

```typescript
// Send verification
await authService.sendVerificationEmail(userId);

// Verify email
await authService.verifyEmail(token);
```

#### Subscription Status

```typescript
const status = authService.checkSubscriptionStatus(user);

// Returns:
{
  active: boolean,
  trialing: boolean,
  trialExpired: boolean,
  daysRemaining: number,
  subscriptionStatus: string,
  subscriptionTier: string
}
```

---

### Auth Middleware

**File**: `server/auth-middleware.ts`

JWT authentication middleware for Express routes.

```typescript
import { authenticateToken, optionalAuth } from './auth-middleware';

// Required authentication
app.get('/api/protected', authenticateToken, (req, res) => {
  // req.user is available
  res.json({ userId: req.user.id });
});

// Optional authentication
app.get('/api/public', optionalAuth, (req, res) => {
  // req.user may be undefined
  res.json({ authenticated: !!req.user });
});
```

#### Token Sources

1. **Authorization Header**: `Bearer <token>`
2. **Cookie**: `biomate_token=<token>`

---

### Galaxy State Poller

**File**: `server/galaxy-state-poller.ts`

Monitors workflow execution and emits real-time updates.

```typescript
import { galaxyPoller } from './galaxy-state-poller';

// Start monitoring
galaxyPoller.startPolling(workflowId, invocationId);

// Listen for events
galaxyPoller.on('step_update', (data) => {
  console.log('Step updated:', data.stepId, data.state);
});

galaxyPoller.on('workflow_completed', (data) => {
  console.log('Workflow completed:', data.invocation_id);
});

galaxyPoller.on('error', (error) => {
  console.error('Polling error:', error);
});

// Stop monitoring
galaxyPoller.stopPolling(invocationId);
```

#### Events

| Event | Data | Description |
|-------|------|-------------|
| `step_update` | `{ stepId, state, jobId, elapsedMs }` | Step status changed |
| `workflow_completed` | `{ invocation_id, state }` | Workflow finished |
| `error` | `{ error, invocation_id }` | Error occurred |

---

### Workflow SSE

**File**: `server/workflow-sse.ts`

Server-Sent Events management for real-time updates.

```typescript
import { workflowSSE } from './workflow-sse';

// Add client connection
workflowSSE.addClient(workflowId, invocationId, res);

// Send event to all clients watching an invocation
workflowSSE.sendEvent(invocationId, 'step_update', {
  stepId: 'step_1',
  state: 'ok'
});

// Remove client
workflowSSE.removeClient(invocationId, clientId);
```

#### Client Connection (from routes.ts)

```typescript
app.get('/api/galaxy/workflows/sse/:workflowId/:invocationId', (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');

  workflowSSE.addClient(workflowId, invocationId, res);

  req.on('close', () => {
    workflowSSE.removeClient(invocationId, res);
  });
});
```

---

### Encryption Service

**File**: `server/encryption.ts`

AES-256-GCM encryption for sensitive data at rest.

```typescript
import { encrypt, decrypt, hash, verifyHash } from './encryption';

// Encrypt data
const encrypted = encrypt('sensitive data');
// { data: 'base64...', iv: 'base64...', authTag: 'base64...' }

// Decrypt data
const plaintext = decrypt(encrypted);

// Password-based encryption
const encrypted = encrypt('data', 'password123');
const decrypted = decrypt(encrypted, 'password123');

// Hashing
const hashed = hash('data');
const isMatch = verifyHash('data', hashed);
```

#### Configuration

Environment variables:
- `ENCRYPTION_KEY`: 32-character encryption key
- Falls back to generated key if not set (development only)

---

### Email Service

**File**: `server/email-service.ts`

Sends transactional emails via SMTP.

```typescript
import { emailService } from './email-service';

// Send email
await emailService.sendEmail({
  to: 'user@example.com',
  subject: 'Welcome to Biomate',
  html: '<h1>Welcome!</h1>',
  text: 'Welcome!'
});

// Send verification email
await emailService.sendVerificationEmail(
  'user@example.com',
  'John Doe',
  'verification_token'
);

// Send password reset
await emailService.sendPasswordResetEmail(
  'user@example.com',
  'John Doe',
  'reset_token'
);
```

#### Configuration

Environment variables:
- `EMAIL_HOST`: SMTP server host
- `EMAIL_PORT`: SMTP port
- `EMAIL_USER`: SMTP username
- `EMAIL_PASS`: SMTP password
- `EMAIL_FROM`: From address

---

### Storage Interface

**File**: `server/storage.ts`

In-memory storage for workflow invocations and outputs.

```typescript
import { storage } from './storage';

// Invocations
const invocation = await storage.createInvocation({
  workflowId: 'wf_id',
  workflowName: 'My Pipeline',
  galaxyInvocationId: 'galaxy_inv_id',
  galaxyHistoryId: 'history_id',
  totalSteps: 5
});

await storage.updateInvocation(id, { status: 'running' });

const invocations = await storage.getAllInvocations();

// Outputs
const output = await storage.addOutput({
  invocationId: 'inv_id',
  name: 'results.csv',
  format: 'csv',
  size: 1024
});

const outputs = await storage.getInvocationOutputs(invocationId);
```

---

### Database

**File**: `server/db.ts`

PostgreSQL connection using Drizzle ORM.

```typescript
import { db } from './db';
import { users, eq } from '../shared/schema';

// Query example
const user = await db
  .select()
  .from(users)
  .where(eq(users.email, 'user@example.com'))
  .limit(1);

// Insert
await db.insert(users).values({
  email: 'new@example.com',
  password: hashedPassword,
  fullName: 'New User'
});

// Update
await db
  .update(users)
  .set({ emailVerified: true })
  .where(eq(users.id, userId));
```

---

### Security Config

**File**: `server/security-config.ts`

Security-related configurations and middleware.

```typescript
import {
  csrfProtection,
  sanitizeInput,
  securityHeaders
} from './security-config';

// Apply security headers
app.use(securityHeaders);

// CSRF protection
app.use(csrfProtection);

// Input sanitization
const clean = sanitizeInput(userInput);
```

---

## Rate Limiting

Rate limits are configured per endpoint category:

```typescript
import rateLimit from 'express-rate-limit';

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,
  message: { error: 'Too many login attempts' }
});

const registerLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 5
});

const uploadLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100
});
```

---

## Error Handling

Standard error response format:

```typescript
// In route handler
try {
  const result = await someOperation();
  res.json({ success: true, data: result });
} catch (error: any) {
  console.error('[ServiceName] Operation failed:', error);
  res.status(500).json({
    success: false,
    error: 'OPERATION_FAILED',
    message: error.message
  });
}
```

---

## Testing Services

### Unit Testing

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { authService } from './auth-service';

describe('AuthService', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should hash password on registration', async () => {
    const result = await authService.register({
      email: 'test@example.com',
      password: 'password123',
      fullName: 'Test User',
      termsAccepted: true
    });

    expect(result.user.email).toBe('test@example.com');
    expect(result.token).toBeDefined();
  });
});
```

### Integration Testing

```typescript
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { app } from './index';

describe('Auth API', () => {
  it('should register a new user', async () => {
    const res = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'new@example.com',
        password: 'password123',
        fullName: 'New User',
        termsAccepted: true
      });

    expect(res.status).toBe(201);
    expect(res.body.success).toBe(true);
  });
});
```

---

**Last Updated**: January 9, 2026
