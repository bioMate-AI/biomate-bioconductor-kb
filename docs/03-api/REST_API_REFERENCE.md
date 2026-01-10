# REST API Reference

Complete reference for the Biomate REST API.

**Base URL**: `http://localhost:3000/api`

---

## Table of Contents

1. [Authentication](#authentication)
2. [Health Check](#health-check)
3. [User Auth](#user-auth)
4. [File Storage (S3)](#file-storage-s3)
5. [Payments](#payments)
6. [Galaxy Tools](#galaxy-tools)
7. [Galaxy Datasets](#galaxy-datasets)
8. [Galaxy Workflows](#galaxy-workflows)
9. [Galaxy Jobs](#galaxy-jobs)
10. [AI Assistant](#ai-assistant)
11. [Chat](#chat)
12. [Parameter Templates](#parameter-templates)
13. [Workflow Templates](#workflow-templates)
14. [Long-Term Memory](#long-term-memory)
15. [Invocations](#invocations)
16. [Outputs](#outputs)

---

## Authentication

Most endpoints require authentication via JWT token.

### Authentication Methods

1. **Bearer Token** (Header)
   ```
   Authorization: Bearer <jwt_token>
   ```

2. **HTTP-Only Cookie**
   ```
   Cookie: biomate_token=<jwt_token>
   ```

### Response Codes

| Code | Description |
|------|-------------|
| 401 | Not authenticated |
| 403 | Forbidden / Trial expired |
| 429 | Rate limit exceeded |

---

## Health Check

### GET /api/health

Check server health status.

**Authentication**: None required

**Response**:
```json
{
  "status": "ok",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

---

## User Auth

### POST /api/auth/register

Register a new user account.

**Rate Limit**: 5 requests per hour

**Request Body**:
```json
{
  "email": "user@example.com",
  "password": "securePassword123",
  "fullName": "John Doe",
  "organization": "Research Lab",
  "phone": "+1234567890",
  "termsAccepted": true,
  "marketingEmailsOptIn": false
}
```

**Response** (201):
```json
{
  "success": true,
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "fullName": "John Doe",
    "organization": "Research Lab",
    "subscriptionStatus": "trialing",
    "subscriptionTier": "academic",
    "trialEndsAt": "2024-01-22T00:00:00.000Z"
  },
  "token": "jwt_token",
  "subscription": {
    "active": true,
    "trialing": true,
    "trialExpired": false,
    "daysRemaining": 7
  }
}
```

---

### POST /api/auth/login

Authenticate and receive JWT token.

**Rate Limit**: 10 requests per 15 minutes

**Request Body**:
```json
{
  "email": "user@example.com",
  "password": "securePassword123"
}
```

**Response** (200):
```json
{
  "success": true,
  "user": { ... },
  "token": "jwt_token",
  "subscription": { ... }
}
```

**Error Responses**:
- `401`: Invalid credentials
- `403`: Trial expired (error code: `TRIAL_EXPIRED`)

---

### POST /api/auth/logout

Log out and clear session cookie.

**Authentication**: None required

**Response** (200):
```json
{
  "success": true,
  "message": "Logged out successfully"
}
```

---

### GET /api/auth/me

Get current authenticated user info.

**Authentication**: Required

**Response** (200):
```json
{
  "success": true,
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "fullName": "John Doe",
    "emailVerified": true,
    ...
  },
  "subscription": {
    "active": true,
    "trialing": false,
    "subscriptionStatus": "active",
    "subscriptionTier": "pro"
  }
}
```

---

### POST /api/auth/resend-verification

Resend email verification link.

**Authentication**: Required
**Rate Limit**: 3 requests per hour

**Response** (200):
```json
{
  "success": true,
  "message": "Verification email sent"
}
```

---

### POST /api/auth/verify-email

Verify email address with token.

**Rate Limit**: 10 requests per hour

**Request Body**:
```json
{
  "token": "verification_token_from_email"
}
```

**Response** (200):
```json
{
  "success": true,
  "message": "Email verified successfully"
}
```

---

### POST /api/auth/request-password-reset

Request password reset email.

**Rate Limit**: 5 requests per hour

**Request Body**:
```json
{
  "email": "user@example.com"
}
```

**Response** (200):
```json
{
  "success": true,
  "message": "If an account exists, a reset email has been sent"
}
```

---

### POST /api/auth/reset-password

Reset password with token.

**Rate Limit**: 5 requests per hour

**Request Body**:
```json
{
  "token": "reset_token_from_email",
  "password": "newSecurePassword123"
}
```

**Response** (200):
```json
{
  "success": true,
  "message": "Password reset successfully"
}
```

---

### OAuth Endpoints

| Endpoint | Description |
|----------|-------------|
| GET /api/auth/google | Initiate Google OAuth |
| GET /api/auth/google/callback | Google OAuth callback |
| GET /api/auth/github | Initiate GitHub OAuth |
| GET /api/auth/github/callback | GitHub OAuth callback |
| GET /api/auth/oauth/status | Check OAuth configuration status |

---

## File Storage (S3)

### POST /api/s3/upload/init

Initialize a file upload and get presigned URL.

**Authentication**: Required
**Rate Limit**: 100 requests per 15 minutes

**Request Body**:
```json
{
  "fileName": "experiment_data.fastq",
  "fileType": "application/octet-stream",
  "fileSize": 1073741824
}
```

**Response** (200):
```json
{
  "success": true,
  "uploadUrl": "https://s3.amazonaws.com/...",
  "key": "uploads/uuid/experiment_data.fastq",
  "expiresIn": 3600
}
```

---

### POST /api/s3/download

Get presigned download URL.

**Authentication**: Required

**Request Body**:
```json
{
  "key": "uploads/uuid/experiment_data.fastq"
}
```

**Response** (200):
```json
{
  "success": true,
  "downloadUrl": "https://s3.amazonaws.com/...",
  "expiresIn": 3600
}
```

---

### DELETE /api/s3/files/:key

Delete a file from S3.

**Authentication**: Required

**Response** (200):
```json
{
  "success": true,
  "message": "File deleted successfully"
}
```

---

## Payments

### POST /api/payments/create-checkout-session

Create Stripe checkout session.

**Authentication**: Required

**Request Body**:
```json
{
  "priceId": "price_xxxxx",
  "successUrl": "https://biomate.com/success",
  "cancelUrl": "https://biomate.com/cancel"
}
```

**Response** (200):
```json
{
  "success": true,
  "sessionId": "cs_xxxxx",
  "url": "https://checkout.stripe.com/..."
}
```

---

### POST /api/payments/create-portal-session

Create Stripe customer portal session.

**Authentication**: Required

**Request Body**:
```json
{
  "returnUrl": "https://biomate.com/settings"
}
```

**Response** (200):
```json
{
  "success": true,
  "url": "https://billing.stripe.com/..."
}
```

---

### GET /api/payments/subscription

Get current subscription status.

**Authentication**: Required

**Response** (200):
```json
{
  "success": true,
  "subscription": {
    "status": "active",
    "tier": "pro",
    "currentPeriodEnd": "2024-02-15T00:00:00.000Z",
    "cancelAtPeriodEnd": false
  }
}
```

---

### POST /api/payments/cancel-subscription

Cancel subscription at period end.

**Authentication**: Required

**Response** (200):
```json
{
  "success": true,
  "message": "Subscription will cancel at period end"
}
```

---

### GET /api/payments/pricing

Get pricing information (public).

**Authentication**: None required

**Response** (200):
```json
{
  "plans": [
    {
      "id": "free",
      "name": "Free",
      "price": 0,
      "features": ["$5 credits", "Basic support"]
    },
    {
      "id": "pro",
      "name": "Pro",
      "price": 20,
      "features": ["$30 credits", "Priority compute"]
    }
  ]
}
```

---

## Galaxy Tools

### GET /api/galaxy/tools/search

Search available Galaxy tools.

**Query Parameters**:
| Parameter | Type | Description |
|-----------|------|-------------|
| q | string | Search query |
| category | string | Filter by category |
| limit | number | Max results (default: 20) |
| offset | number | Pagination offset |

**Response** (200):
```json
{
  "query": "fastqc",
  "category": null,
  "count": 5,
  "tools": [
    {
      "id": 1,
      "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73",
      "name": "FastQC",
      "description": "Read quality reports",
      "version": "0.73",
      "category": "Quality Control",
      "is_installed": true
    }
  ]
}
```

---

### GET /api/galaxy/tools/categories

Get all tool categories.

**Response** (200):
```json
{
  "categories": [
    { "name": "Quality Control", "count": 15 },
    { "name": "Mapping", "count": 28 },
    { "name": "Assembly", "count": 12 }
  ]
}
```

---

### GET /api/galaxy/tools/:toolId

Get tool details by ID.

**Response** (200):
```json
{
  "tool": {
    "tool_id": "fastqc",
    "name": "FastQC",
    "description": "...",
    "version": "0.73",
    "inputs": [...],
    "outputs": [...]
  }
}
```

---

### GET /api/galaxy/tools/:toolId/schema

Get tool input schema for parameter forms.

**Response** (200):
```json
{
  "schema": {
    "inputs": [
      {
        "name": "input_file",
        "type": "data",
        "format": ["fastq", "fastqsanger"],
        "required": true
      },
      {
        "name": "contaminants",
        "type": "data",
        "optional": true
      }
    ]
  }
}
```

---

### GET /api/galaxy/tools/installed/list

List all installed tools.

**Response** (200):
```json
{
  "count": 2177,
  "tools": [...]
}
```

---

## Galaxy Datasets

### POST /api/galaxy/datasets/search

Search BioMNI dataset repository.

**Request Body**:
```json
{
  "query": "human proteome",
  "category": "proteomics",
  "limit": 10
}
```

**Response** (200):
```json
{
  "query": "human proteome",
  "count": 5,
  "datasets": [
    {
      "id": "ds1",
      "name": "Human Proteome Reference",
      "description": "...",
      "category": "proteomics",
      "format": "fasta",
      "size_mb": 150,
      "relevance_score": 0.95
    }
  ]
}
```

---

### GET /api/galaxy/datasets/category/:category

Get datasets by category.

**Response** (200):
```json
{
  "category": "proteomics",
  "datasets": [...]
}
```

---

### GET /api/galaxy/datasets/:datasetId

Get dataset details.

**Response** (200):
```json
{
  "dataset": {
    "id": "ds1",
    "name": "Human Proteome Reference",
    "description": "Complete human proteome",
    "fields": {...},
    "path": "/data/proteomes/human.fasta"
  }
}
```

---

### POST /api/datasets/upload

Upload a dataset file.

**Content-Type**: `multipart/form-data`

**Form Fields**:
| Field | Type | Description |
|-------|------|-------------|
| file | File | The file to upload |
| name | string | Dataset name |
| description | string | Optional description |

**Response** (200):
```json
{
  "success": true,
  "dataset": {
    "id": "uuid",
    "name": "my_data.fastq",
    "size": 1073741824,
    "format": "fastq"
  }
}
```

---

### POST /api/datasets/validate

Validate dataset format.

**Request Body**:
```json
{
  "datasetId": "uuid",
  "expectedFormat": "fastq"
}
```

**Response** (200):
```json
{
  "valid": true,
  "format": "fastq",
  "records": 1000000,
  "warnings": []
}
```

---

## Galaxy Workflows

### POST /api/galaxy/workflows

Create a new workflow.

**Request Body**:
```json
{
  "name": "RNA-Seq Pipeline",
  "description": "Complete RNA-Seq analysis",
  "steps": [...]
}
```

**Response** (201):
```json
{
  "success": true,
  "workflow": {
    "id": "wf_uuid",
    "galaxyId": "galaxy_wf_id",
    "name": "RNA-Seq Pipeline"
  }
}
```

---

### POST /api/galaxy/workflows/invoke

Execute a workflow.

**Request Body**:
```json
{
  "workflowId": "galaxy_wf_id",
  "inputs": {
    "0": { "id": "dataset_id", "src": "hda" }
  },
  "parameters": {
    "step_1": { "threads": 8 }
  }
}
```

**Response** (200):
```json
{
  "success": true,
  "invocation": {
    "id": "inv_id",
    "state": "scheduled",
    "steps": [...]
  }
}
```

---

### GET /api/galaxy/workflows/:workflowId/invocations/:invocationId

Get workflow invocation status.

**Response** (200):
```json
{
  "invocation": {
    "id": "inv_id",
    "state": "running",
    "steps": [
      { "id": "step_1", "state": "ok", "job_id": "job_1" },
      { "id": "step_2", "state": "running", "job_id": "job_2" }
    ]
  }
}
```

---

### GET /api/galaxy/workflows/sse/:workflowId/:invocationId

Server-Sent Events stream for real-time workflow updates.

**Response**: SSE stream

```
event: step_update
data: {"step_id": "step_1", "state": "ok", "elapsed_ms": 5000}

event: workflow_complete
data: {"state": "ok", "outputs": [...]}
```

---

## Galaxy Jobs

### GET /api/galaxy/jobs/:jobId

Get job details.

**Response** (200):
```json
{
  "job": {
    "id": "job_id",
    "tool_id": "fastqc",
    "state": "ok",
    "create_time": "2024-01-15T10:00:00.000Z",
    "update_time": "2024-01-15T10:05:00.000Z"
  }
}
```

---

### GET /api/galaxy/jobs/:jobId/stdout

Get job standard output.

**Response** (200):
```json
{
  "stdout": "Processing file...\nComplete."
}
```

---

### GET /api/galaxy/jobs/:jobId/stderr

Get job error output.

**Response** (200):
```json
{
  "stderr": ""
}
```

---

### PUT /api/galaxy/jobs/:jobId/pause

Pause a running job.

**Response** (200):
```json
{
  "success": true,
  "state": "paused"
}
```

---

### PUT /api/galaxy/jobs/:jobId/resume

Resume a paused job.

**Response** (200):
```json
{
  "success": true,
  "state": "running"
}
```

---

## AI Assistant

### POST /api/chat

Send a message to the AI assistant.

**Request Body**:
```json
{
  "message": "I need to analyze RNA-seq data from mouse samples",
  "sessionId": "session_uuid",
  "context": {
    "datasets": ["ds1", "ds2"],
    "previousWorkflow": "wf_uuid"
  }
}
```

**Response** (200):
```json
{
  "response": {
    "message": "I can help you set up an RNA-seq analysis pipeline...",
    "tool_suggestions": [...],
    "dataset_suggestions": [...],
    "workflow_suggestion": {...}
  },
  "thinking": "Analyzing user intent...",
  "sessionId": "session_uuid"
}
```

---

### POST /api/ai_assistant/generate_workflow

Generate a workflow from natural language.

**Request Body**:
```json
{
  "user_intent": "Analyze differential gene expression between control and treatment groups",
  "datasets": [
    { "id": "ds1", "name": "control.fastq", "type": "fastq" },
    { "id": "ds2", "name": "treatment.fastq", "type": "fastq" }
  ]
}
```

**Response** (200):
```json
{
  "success": true,
  "workflow_ga": {...},
  "source": "template_adapt",
  "confidence": 0.92,
  "tool_selections": [...],
  "dataset_assignments": {...}
}
```

---

### POST /api/ai_assistant/citations/export

Export citations for tools used in a workflow.

**Request Body**:
```json
{
  "toolIds": ["fastqc", "bowtie2", "deseq2"],
  "format": "bibtex"
}
```

**Response** (200):
```json
{
  "success": true,
  "citations": "@article{fastqc2010,...}",
  "format": "bibtex"
}
```

---

### POST /api/ai_assistant/citations/methods

Generate methods section for publication.

**Request Body**:
```json
{
  "workflowId": "wf_uuid",
  "style": "nature"
}
```

**Response** (200):
```json
{
  "success": true,
  "methods": "Raw sequencing reads were quality-checked using FastQC v0.73...",
  "citations": [...]
}
```

---

### GET /api/ai_assistant/benchmarks/:scenario

Get benchmark results for a scenario.

**Response** (200):
```json
{
  "scenario": "rna_seq_de",
  "benchmarks": [
    {
      "tool": "deseq2",
      "performance": {...},
      "recommended_for": ["small_samples"]
    }
  ]
}
```

---

### POST /api/ai_assistant/research_query

Query research knowledge base.

**Request Body**:
```json
{
  "query": "Best practices for single-cell RNA-seq normalization",
  "includeEvidence": true
}
```

**Response** (200):
```json
{
  "answer": "Current best practices recommend...",
  "evidence": [...],
  "sources": [...]
}
```

---

## Parameter Templates

### GET /api/parameter-templates/search

Search parameter templates.

**Query Parameters**:
| Parameter | Type | Description |
|-----------|------|-------------|
| q | string | Search query |
| toolId | string | Filter by tool |
| category | string | Filter by use case |

**Response** (200):
```json
{
  "templates": [
    {
      "id": "pt1",
      "name": "FastQC Default",
      "toolId": "fastqc",
      "parameters": {...},
      "usageCount": 150
    }
  ]
}
```

---

### GET /api/parameter-templates/tool/:toolId

Get templates for a specific tool.

**Response** (200):
```json
{
  "templates": [...]
}
```

---

### POST /api/parameter-templates

Create a new parameter template.

**Request Body**:
```json
{
  "name": "BWA High Sensitivity",
  "toolId": "bwa_mem",
  "description": "Optimized for high sensitivity alignment",
  "parameters": {
    "threads": 8,
    "scoring": "pacbio"
  },
  "useCase": "long_reads"
}
```

**Response** (201):
```json
{
  "success": true,
  "template": {...}
}
```

---

## Workflow Templates

### GET /api/workflow-templates/search

Search workflow templates.

**Query Parameters**:
| Parameter | Type | Description |
|-----------|------|-------------|
| q | string | Search query |
| category | string | Filter by category |
| validated | boolean | Only validated templates |

**Response** (200):
```json
{
  "templates": [
    {
      "id": "wt1",
      "name": "RNA-Seq DE Analysis",
      "description": "Differential expression pipeline",
      "category": "genomics",
      "validated": true,
      "usageCount": 500
    }
  ]
}
```

---

## Long-Term Memory

### GET /api/memory/user

Get user's long-term memory profile.

**Authentication**: Required

**Response** (200):
```json
{
  "preferences": {...},
  "corrections": [...],
  "expertise_level": "intermediate"
}
```

---

### POST /api/memory/projects

Create a new project context.

**Authentication**: Required

**Request Body**:
```json
{
  "name": "Mouse Liver Study",
  "description": "RNA-seq analysis of mouse liver samples",
  "metadata": {
    "organism": "mouse",
    "tissue": "liver"
  }
}
```

**Response** (201):
```json
{
  "success": true,
  "project": {
    "id": "proj_uuid",
    "name": "Mouse Liver Study"
  }
}
```

---

### GET /api/memory/projects/:projectId/episodes

Get episodic memories for a project.

**Authentication**: Required

**Response** (200):
```json
{
  "episodes": [
    {
      "id": "ep1",
      "summary": "User ran FastQC on 6 samples",
      "outcome": "success",
      "timestamp": "2024-01-15T10:00:00.000Z"
    }
  ]
}
```

---

## Invocations

### POST /api/invocations

Create a workflow invocation record.

**Request Body**:
```json
{
  "workflowId": "wf_uuid",
  "workflowName": "RNA-Seq Pipeline",
  "galaxyInvocationId": "galaxy_inv_id",
  "galaxyHistoryId": "history_id",
  "totalSteps": 5
}
```

**Response** (201):
```json
{
  "success": true,
  "invocation": {
    "id": "inv_uuid",
    "status": "new"
  }
}
```

---

### GET /api/invocations

List all invocations.

**Query Parameters**:
| Parameter | Type | Description |
|-----------|------|-------------|
| status | string | Filter by status |
| limit | number | Max results |

**Response** (200):
```json
{
  "invocations": [...]
}
```

---

### GET /api/invocations/:id

Get invocation details.

**Response** (200):
```json
{
  "invocation": {
    "id": "inv_uuid",
    "status": "running",
    "completedSteps": 3,
    "totalSteps": 5,
    "currentStepName": "DESeq2"
  }
}
```

---

### PATCH /api/invocations/:id

Update invocation status.

**Request Body**:
```json
{
  "status": "ok",
  "completedSteps": 5
}
```

**Response** (200):
```json
{
  "success": true,
  "invocation": {...}
}
```

---

## Outputs

### GET /api/outputs/:id

Get output dataset details.

**Response** (200):
```json
{
  "output": {
    "id": "out_uuid",
    "name": "deseq2_results.csv",
    "format": "csv",
    "size": 1024000
  }
}
```

---

### GET /api/outputs/:id/download

Download output file.

**Response**: File download or redirect to S3 presigned URL

---

### GET /api/outputs/:id/preview

Get preview of output contents.

**Query Parameters**:
| Parameter | Type | Description |
|-----------|------|-------------|
| lines | number | Number of lines to preview |

**Response** (200):
```json
{
  "preview": "gene_id,log2FC,padj\nGENE1,2.5,0.001\n...",
  "totalLines": 5000,
  "truncated": true
}
```

---

## Error Responses

All endpoints return errors in this format:

```json
{
  "success": false,
  "error": "ErrorCode",
  "message": "Human-readable error message"
}
```

### Common Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `NOT_AUTHENTICATED` | 401 | Missing or invalid token |
| `FORBIDDEN` | 403 | Insufficient permissions |
| `TRIAL_EXPIRED` | 403 | Free trial has ended |
| `NOT_FOUND` | 404 | Resource not found |
| `VALIDATION_ERROR` | 400 | Invalid request body |
| `RATE_LIMITED` | 429 | Too many requests |
| `INTERNAL_ERROR` | 500 | Server error |

---

## Rate Limits

| Endpoint Category | Limit |
|-------------------|-------|
| Auth (login) | 10 / 15 min |
| Auth (register) | 5 / hour |
| Auth (password reset) | 5 / hour |
| File upload | 100 / 15 min |
| Chat | 60 / min |
| General | 1000 / 15 min |

---

**Last Updated**: January 9, 2026
