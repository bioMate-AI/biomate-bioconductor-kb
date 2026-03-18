# BioMate Complete Workflow Execution Architecture

**Purpose:** Document the ENTIRE workflow execution process from user request to downloadable results

**Date:** 2026-02-12

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Complete Architecture](#complete-architecture)
3. [End-to-End Flow](#end-to-end-flow)
4. [All System Components](#all-system-components)
5. [Integration Points](#integration-points)
6. [Data Flow Diagrams](#data-flow-diagrams)
7. [State Transitions](#state-transitions)
8. [Error Handling](#error-handling)

---

## System Overview

BioMate executes scientific workflows through a multi-layered architecture combining:
- **Frontend** (Node/Express on port 5000)
- **Backend** (Galaxy Python on port 8081)
- **Workflow Engine** (Nextflow)
- **Multiple validation/monitoring systems**

### High-Level Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER INTERFACE                          │
│  Browser → React App → Express Server (Port 5000)              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    FRONTEND LAYER (Node.js)                     │
│  - GalaxyAssistant (AI orchestration)                          │
│  - GalaxyAPIProxy (HTTP bridge)                                │
│  - GalaxyStatePoller (status polling)                          │
│  - WorkflowSSEManager (real-time updates)                      │
└────────────────────────┬────────────────────────────────────────┘
                         │ HTTP/REST
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                   BACKEND LAYER (Galaxy Python)                 │
│                                                                 │
│  AI & Workflow Generation:                                      │
│  ├─ AIAssistant (unified workflow generation)                  │
│  ├─ GalaxyWorkflowGenerator (create from scratch)              │
│  ├─ UnifiedWorkflowSearch (search 951+ templates)              │
│  └─ LLMParameterGenerator (infer parameters)                   │
│                                                                 │
│  Validation Systems:                                            │
│  ├─ Audit System (workflow structure)                          │
│  ├─ Parameter Validator (parameters)                           │
│  └─ Input Validator (input files) ← NEW                        │
│                                                                 │
│  Execution:                                                     │
│  ├─ NextflowExecutorV2 (workflow execution)                    │
│  ├─ NextflowWorkflowJobRunner (Nextflow runner)                │
│  └─ Galaxy Workflow Manager (import/invoke)                    │
│                                                                 │
│  Runtime Monitoring:                                            │
│  ├─ QC Gates (quality checks)                                  │
│  ├─ Autofix (error recovery)                                   │
│  └─ Progressive Tuning (pilot runs)                            │
│                                                                 │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              WORKFLOW EXECUTION LAYER (Nextflow)                │
│  - Nextflow Runtime                                             │
│  - Process Execution                                            │
│  - File Management                                              │
│  - Docker/Singularity Containers                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Complete Architecture

### Full System Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER JOURNEY                                   │
│  1. User Request → 2. Workflow Generation → 3. Validation →                │
│  4. Execution → 5. Monitoring → 6. Results                                 │
└─────────────────────────────────────────────────────────────────────────────┘

                                    ↓

┌─────────────────────────────────────────────────────────────────────────────┐
│                         PHASE 1: REQUEST HANDLING                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  User Browser                                                               │
│       ↓                                                                     │
│  POST /api/chat  (Frontend:5000)                                           │
│  {                                                                          │
│    message: "Run RNA-Seq QC on my FASTQ files",                           │
│    files: ["/data/sample_R1.fastq"]                                        │
│  }                                                                          │
│       ↓                                                                     │
│  GalaxyAssistant.handleMessage()                                           │
│       ├─ Intent Analysis (LLM)                                             │
│       ├─ Tool Ranking                                                      │
│       └─ Workflow Selection                                                │
│       ↓                                                                     │
│  GalaxyAPIProxy.generateWorkflow()                                         │
│       ↓ POST /api/ai_assistant/generate_workflow                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

                                    ↓

┌─────────────────────────────────────────────────────────────────────────────┐
│                    PHASE 2: WORKFLOW GENERATION (Backend:8081)              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  AIAssistant.generate_workflow()                                           │
│       ├─ Parse user request                                                │
│       ├─ UnifiedWorkflowSearch (search 951+ templates)                     │
│       │     ├─ Match by keywords                                           │
│       │     ├─ Match by domain (genomics/cryo_em/etc)                      │
│       │     └─ Rank by relevance                                           │
│       │                                                                     │
│       ├─ IF found template:                                                │
│       │     └─ Use template, fill parameters                               │
│       │                                                                     │
│       └─ IF no template:                                                   │
│             └─ GalaxyWorkflowGenerator.generate()                          │
│                   ├─ Call LLM (Claude/GPT-4)                               │
│                   ├─ Generate workflow JSON                                │
│                   └─ LLMParameterGenerator (infer params)                  │
│                                                                             │
│  Returns: workflow_ga (Galaxy format JSON)                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

                                    ↓

┌─────────────────────────────────────────────────────────────────────────────┐
│                      PHASE 3: VALIDATION STAGE                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Step 3.1: AUDIT (Workflow Structure Validation)                           │
│  ────────────────────────────────────────────────────                      │
│  File: lib/galaxy/ai/dual_llm_converter_system_part2.py                   │
│                                                                             │
│  audit_and_merge(workflow_ga)                                              │
│       ├─ Validate tool IDs exist                                           │
│       ├─ Check parameter connections                                       │
│       ├─ Verify workflow structure                                         │
│       └─ Create audit log                                                  │
│                                                                             │
│  IF audit fails:                                                           │
│       └─ Return error to user                                              │
│                                                                             │
│  ────────────────────────────────────────────────────                      │
│                                                                             │
│  Step 3.2: PARAMETER VALIDATION (Optional)                                 │
│  ────────────────────────────────────────────────────                      │
│  File: lib/galaxy/ai/workflow_ops/parameter_validator.py                  │
│                                                                             │
│  WorkflowParameterValidator.validate()                                     │
│       ├─ Check parameter types                                             │
│       ├─ Check parameter ranges                                            │
│       ├─ Check file path formats                                           │
│       └─ Warn if files missing (WARNING only)                              │
│                                                                             │
│  Note: This is OPTIONAL, user-initiated via API                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

                                    ↓

┌─────────────────────────────────────────────────────────────────────────────┐
│                    PHASE 4: WORKFLOW EXECUTION START                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Frontend calls:                                                            │
│  POST /api/workflows/execute                                               │
│  {                                                                          │
│    workflowDefinition: workflow_ga,                                        │
│    executionConfig: {mode: "production"},                                  │
│    inputs: {...},                                                          │
│    enable_input_validation: true                                           │
│  }                                                                          │
│       ↓                                                                     │
│  Backend: NextflowExecutorV2.execute_nextflow_workflow()                   │
│       ↓                                                                     │
│  ┌───────────────────────────────────────────────────────┐                 │
│  │  PARALLEL EXECUTION (2 threads)                       │                 │
│  ├───────────────────────────────────────────────────────┤                 │
│  │                                                       │                 │
│  │  THREAD 1: Workflow Execution (Main)                 │                 │
│  │  ────────────────────────────────                    │                 │
│  │  1. Create Galaxy History                            │                 │
│  │  2. Import Workflow to Galaxy                        │                 │
│  │  3. Create Workflow Invocation                       │                 │
│  │  4. Start Nextflow Execution                         │                 │
│  │  5. Return invocation_id to user                     │                 │
│  │                                                       │                 │
│  │  THREAD 2: Input Validation (Background)             │                 │
│  │  ────────────────────────────────                    │                 │
│  │  1. Get InputValidator instance                      │                 │
│  │  2. Register validators (first time)                 │                 │
│  │  3. Detect workflow domain                           │                 │
│  │  4. Load appropriate validator                       │                 │
│  │  5. Validate input files                             │                 │
│  │  6. Store validation report                          │                 │
│  │  7. Emit SSE event                                   │                 │
│  │                                                       │                 │
│  └───────────────────────────────────────────────────────┘                 │
│                                                                             │
│  Returns to Frontend:                                                       │
│  {                                                                          │
│    success: true,                                                          │
│    invocation_id: "inv_12345",                                             │
│    galaxy_history_id: "hist_67890",                                        │
│    workflow_id: "wf_abcdef"                                                │
│  }                                                                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

                                    ↓

┌─────────────────────────────────────────────────────────────────────────────┐
│                    PHASE 5: NEXTFLOW EXECUTION                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  NextflowWorkflowJobRunner.run()                                           │
│       ↓                                                                     │
│  Nextflow Runtime                                                           │
│       ├─ Parse workflow.nf                                                 │
│       ├─ Resolve dependencies                                              │
│       ├─ Create work directory                                             │
│       └─ Execute processes                                                 │
│             ↓                                                               │
│  ┌────────────────────────────────────────────┐                            │
│  │  Process Execution (per process)           │                            │
│  ├────────────────────────────────────────────┤                            │
│  │                                            │                            │
│  │  1. Stage input files                     │                            │
│  │  2. Pull Docker/Singularity container      │                            │
│  │  3. Run process script                     │                            │
│  │  4. Write outputs                          │                            │
│  │  5. Write trace metrics                    │                            │
│  │  6. Update status                          │                            │
│  │                                            │                            │
│  └────────────────────────────────────────────┘                            │
│                                                                             │
│  Generates:                                                                 │
│  - trace.txt (execution metrics)                                           │
│  - .command.log (process logs)                                             │
│  - Output files (results)                                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

                                    ↓

┌─────────────────────────────────────────────────────────────────────────────┐
│                    PHASE 6: RUNTIME MONITORING                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌────────────────────────────────────────────────────────┐                │
│  │  QC GATES (Quality Control Monitoring)                 │                │
│  ├────────────────────────────────────────────────────────┤                │
│  │  File: lib/galaxy/jobs/qc_trace_monitor.py            │                │
│  │                                                        │                │
│  │  QCTraceMonitor.monitor_workflow(invocation_id)       │                │
│  │       ↓                                                │                │
│  │  1. Watch trace.txt for updates                       │                │
│  │  2. Parse process completion events                   │                │
│  │  3. Extract metrics (runtime, memory, etc.)           │                │
│  │  4. Compare to QC thresholds                          │                │
│  │       ↓                                                │                │
│  │  IF metrics fail threshold:                           │                │
│  │       ├─ Trigger QC Gate                              │                │
│  │       ├─ Emit SSE event to user                       │                │
│  │       ├─ Show suggestions                             │                │
│  │       └─ Wait for user decision:                      │                │
│  │             ├─ Proceed anyway                         │                │
│  │             ├─ Retry with different params            │                │
│  │             └─ Cancel workflow                        │                │
│  │                                                        │                │
│  │  Config: backend/config/qc_metrics/*.json             │                │
│  └────────────────────────────────────────────────────────┘                │
│                                                                             │
│  ┌────────────────────────────────────────────────────────┐                │
│  │  AUTOFIX (Error Recovery)                              │                │
│  ├────────────────────────────────────────────────────────┤                │
│  │  File: lib/galaxy/ai/workflow_ops/autofix/            │                │
│  │                                                        │                │
│  │  IF workflow fails:                                   │                │
│  │       ↓                                                │                │
│  │  orchestrator.run_autofix(invocation_id)              │                │
│  │       ├─ Analyze error logs                           │                │
│  │       ├─ Identify error type                          │                │
│  │       ├─ Generate fix suggestions                     │                │
│  │       ├─ Apply fixes (if auto-approved)               │                │
│  │       └─ Retry workflow                               │                │
│  │                                                        │                │
│  │  Error types handled:                                 │                │
│  │  - Parameter mismatches                               │                │
│  │  - Tool failures                                      │                │
│  │  - Resource limits                                    │                │
│  │  - Dependency issues                                  │                │
│  └────────────────────────────────────────────────────────┘                │
│                                                                             │
│  ┌────────────────────────────────────────────────────────┐                │
│  │  PROGRESSIVE TUNING (Pilot Runs)                       │                │
│  ├────────────────────────────────────────────────────────┤                │
│  │  File: lib/galaxy/ai/progressive_tuning.py            │                │
│  │                                                        │                │
│  │  IF user requests pilot run:                          │                │
│  │       ↓                                                │                │
│  │  ProgressiveTuningController.start_pilot()            │                │
│  │       ├─ Run on 10% of data                           │                │
│  │       ├─ Collect metrics                              │                │
│  │       ├─ Estimate full run cost/time                  │                │
│  │       └─ Suggest parameter optimizations              │                │
│  │                                                        │                │
│  │  User decides: Proceed with full run or adjust params │                │
│  └────────────────────────────────────────────────────────┘                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

                                    ↓

┌─────────────────────────────────────────────────────────────────────────────┐
│                   PHASE 7: STATUS POLLING & UPDATES                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌────────────────────────────────────────────────────────┐                │
│  │  Frontend: GalaxyStatePoller                           │                │
│  ├────────────────────────────────────────────────────────┤                │
│  │                                                        │                │
│  │  Poll every 2 seconds:                                │                │
│  │  GET /api/workflows/runs/:id/status                   │                │
│  │       ↓                                                │                │
│  │  Backend checks:                                      │                │
│  │  1. Galaxy invocation state                           │                │
│  │  2. Nextflow execution status                         │                │
│  │  3. Job states                                        │                │
│  │  4. Output dataset states                             │                │
│  │       ↓                                                │                │
│  │  Returns:                                             │                │
│  │  {                                                    │                │
│  │    status: "running",                                 │                │
│  │    progress: {                                        │                │
│  │      completedSteps: 3,                               │                │
│  │      totalSteps: 10                                   │                │
│  │    },                                                 │                │
│  │    currentStep: "FASTQC analysis"                     │                │
│  │  }                                                    │                │
│  │                                                        │                │
│  └────────────────────────────────────────────────────────┘                │
│                                                                             │
│  ┌────────────────────────────────────────────────────────┐                │
│  │  WorkflowSSEManager (Real-time Updates)               │                │
│  ├────────────────────────────────────────────────────────┤                │
│  │                                                        │                │
│  │  SSE Connection: /api/workflows/:id/sse               │                │
│  │       ↓                                                │                │
│  │  Stream events:                                       │                │
│  │  - workflow_started                                   │                │
│  │  - step_completed                                     │                │
│  │  - qc_gate_triggered                                  │                │
│  │  - input_validation_completed                         │                │
│  │  - workflow_completed                                 │                │
│  │  - workflow_failed                                    │                │
│  │                                                        │                │
│  └────────────────────────────────────────────────────────┘                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

                                    ↓

┌─────────────────────────────────────────────────────────────────────────────┐
│                    PHASE 8: COMPLETION & RESULTS                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Workflow Completion:                                                       │
│       ├─ All processes complete                                            │
│       ├─ Outputs written to Galaxy history                                 │
│       ├─ Invocation state → "scheduled" (completed)                        │
│       └─ Jobs state → "ok"                                                 │
│             ↓                                                               │
│  Frontend detects completion (via polling or SSE)                           │
│       ↓                                                                     │
│  User sees: "✅ Workflow completed successfully!"                          │
│                                                                             │
│  ┌────────────────────────────────────────────────────────┐                │
│  │  Results Retrieval                                     │                │
│  ├────────────────────────────────────────────────────────┤                │
│  │                                                        │                │
│  │  1. Get history contents:                             │                │
│  │     GET /api/histories/:id/contents                   │                │
│  │       ↓                                                │                │
│  │     Returns: List of datasets with states             │                │
│  │                                                        │                │
│  │  2. Download output files:                            │                │
│  │     GET /api/datasets/:id/display                     │                │
│  │       ↓                                                │                │
│  │     Returns: File content (JSON/CSV/etc.)             │                │
│  │                                                        │                │
│  │  3. Visualize results (if applicable):                │                │
│  │     - Render charts                                   │                │
│  │     - Display tables                                  │                │
│  │     - Generate reports                                │                │
│  │                                                        │                │
│  └────────────────────────────────────────────────────────┘                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## End-to-End Flow

### Complete User Journey

**Scenario:** User runs RNA-Seq QC workflow on FASTQ files

```
TIME    | USER ACTION              | SYSTEM COMPONENT           | STATE
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=0s    | User types request       | Frontend UI                | -
        | "Run RNA-Seq QC"         |                            |
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=1s    | Submit request           | GalaxyAssistant            | Analyzing
        |                          | - Intent analysis (LLM)    |
        |                          | - Tool ranking             |
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=3s    | -                        | UnifiedWorkflowSearch      | Searching
        |                          | - Search 951+ workflows    |
        |                          | - Find "rnaseq_qc"         |
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=5s    | User sees workflow       | Frontend                   | Review
        | preview, clicks "Run"    |                            |
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=6s    | Submit execution         | Backend API                | Queuing
        |                          | POST /api/workflows/execute|
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=6.1s  | -                        | Audit System               | Validating
        |                          | - Check workflow structure |
        |                          | Result: PASS ✅            |
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=6.2s  | -                        | Input Validator (Thread 2) | Validating
        |                          | - Check FASTQ exists       |
        |                          | - Check genome exists      |
        |                          | Result: PASS ✅            |
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=6.5s  | -                        | Galaxy (Thread 1)          | Importing
        |                          | - Create history           |
        |                          | - Import workflow          |
        |                          | - Create invocation        |
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=7s    | User sees                | Frontend                   | Running
        | "Workflow running..."    | - Polls status every 2s    |
        |                          | - SSE receives events      |
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=8s    | -                        | Nextflow                   | Executing
        |                          | - Stage inputs             |
        |                          | - Pull containers          |
        |                          | - Run FASTQC               |
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=30s   | -                        | FASTQC completes           | Running
        |                          | QC Monitor checks metrics  |
        |                          | Result: Quality OK ✅      |
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=45s   | -                        | Nextflow                   | Executing
        |                          | - Run MultiQC              |
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=60s   | User sees                | All processes complete     | Completed
        | "Workflow completed!"    | Invocation state: scheduled|
        |                          | Jobs state: ok             |
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=61s   | Click "View Results"     | Frontend                   | Retrieving
        |                          | GET /api/histories/...     |
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=62s   | See results table        | Frontend displays          | Displaying
        | Click "Download"         | - MultiQC report           |
        |                          | - FASTQC results           |
────────┼──────────────────────────┼───────────────────────────┼──────────────
t=63s   | File downloads           | GET /api/datasets/.../     | Complete ✅
        |                          | display                    |
```

---

## All System Components

### Component Reference

| Component | File | Purpose | When Runs |
|-----------|------|---------|-----------|
| **GalaxyAssistant** | `frontend/server/services/GalaxyAssistant.ts` | Orchestrate AI workflow generation | User submits request |
| **GalaxyAPIProxy** | `frontend/server/services/GalaxyAPIProxy.ts` | HTTP bridge to Galaxy backend | All API calls |
| **GalaxyStatePoller** | `frontend/server/services/GalaxyStatePoller.ts` | Poll workflow status | During execution (every 2s) |
| **WorkflowSSEManager** | `frontend/server/services/WorkflowSSEManager.ts` | Real-time event streaming | During execution |
| **AIAssistant** | `backend/lib/galaxy/ai/ai_assistant.py` | Unified workflow generation | Workflow generation |
| **UnifiedWorkflowSearch** | `backend/lib/galaxy/ai/unified_workflow_search.py` | Search workflow templates | Workflow generation |
| **GalaxyWorkflowGenerator** | `backend/lib/galaxy/ai/galaxy_workflow_generator.py` | Generate from scratch via LLM | No template found |
| **LLMParameterGenerator** | `backend/lib/galaxy/ai/llm_parameter_generator.py` | Infer parameters | Parameter generation |
| **Audit System** | `backend/lib/galaxy/ai/dual_llm_converter_system_part2.py` | Validate workflow structure | After generation |
| **Parameter Validator** | `backend/lib/galaxy/ai/workflow_ops/parameter_validator.py` | Validate parameters | User-initiated (optional) |
| **Input Validator** | `backend/lib/galaxy/jobs/runtime_input_validator.py` | Validate input files | Before execution |
| **NextflowExecutorV2** | `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor_v2.py` | Workflow execution API | User triggers execution |
| **NextflowWorkflowJobRunner** | `backend/lib/galaxy/jobs/runners/nextflow_workflow_runner.py` | Nextflow runner | Execute Nextflow |
| **QCTraceMonitor** | `backend/lib/galaxy/jobs/qc_trace_monitor.py` | Runtime QC monitoring | During execution |
| **Autofix** | `backend/lib/galaxy/ai/workflow_ops/autofix/` | Error recovery | On workflow failure |
| **Progressive Tuning** | `backend/lib/galaxy/ai/progressive_tuning.py` | Pilot run management | User requests pilot |

---

## Integration Points

### Frontend ↔ Backend API Calls

```typescript
// Frontend calls Backend

// 1. Generate Workflow
POST /api/ai_assistant/generate_workflow
Request: { user_request: "Run RNA-Seq QC", context: {...} }
Response: { workflow_ga: {...}, parameters: {...} }

// 2. Validate Parameters (optional)
POST /api/workflows/{id}/validate-parameters
Request: { parameters: {...} }
Response: { valid: true, warnings: [...] }

// 3. Execute Workflow
POST /api/nextflow/execute
Request: {
  workflow_name: "genomics/rnaseq_qc/main.nf",
  parameters: {...},
  enable_input_validation: true
}
Response: { invocation_id: "inv_123", history_id: "hist_456" }

// 4. Poll Status
GET /api/workflows/runs/{id}/status
Response: { status: "running", progress: {...} }

// 5. Get Input Validation Results
GET /api/workflows/{invocation_id}/input-validation
Response: { status: "passed", validation_results: [...] }

// 6. SSE Connection
GET /api/workflows/{id}/sse
Stream: Server-Sent Events

// 7. Get Results
GET /api/histories/{id}/contents
Response: [ { id: "dataset_789", state: "ok", ... } ]

// 8. Download File
GET /api/datasets/{id}/display
Response: File content
```

### Backend Internal Calls

```python
# Backend component interactions

# 1. Workflow Generation Flow
AIAssistant.generate_workflow()
    ↓
UnifiedWorkflowSearch.search()
    ↓ (if no template)
GalaxyWorkflowGenerator.generate()
    ↓
LLMParameterGenerator.generate_parameters()

# 2. Validation Flow
audit_and_merge(workflow_ga)  # Audit
    ↓
WorkflowParameterValidator.validate()  # Optional
    ↓
InputValidator.validate_inputs()  # Before execution

# 3. Execution Flow
NextflowExecutorV2.execute_nextflow_workflow()
    ↓
Galaxy.workflows.import_workflow()
    ↓
Galaxy.workflows.invoke()
    ↓
NextflowWorkflowJobRunner.run()

# 4. Monitoring Flow
QCTraceMonitor.monitor_workflow()  # Parallel
    ↓ (if QC fails)
QCTraceMonitor.trigger_gate()
    ↓ (wait for user decision)

# 5. Error Recovery
IF workflow fails:
    AutofixOrchestrator.run_autofix()
        ↓
    Retry with fixes
```

---

## Data Flow Diagrams

### Request Data Flow

```
User Input
    ↓
{
  message: "Run RNA-Seq QC on sample.fastq",
  files: ["/data/sample.fastq"]
}
    ↓
GalaxyAssistant (Frontend)
    ↓
Intent Analysis (LLM)
    ↓
{
  intent: "workflow_execution",
  domain: "genomics",
  workflow_type: "rnaseq_qc",
  input_files: ["/data/sample.fastq"]
}
    ↓
AIAssistant (Backend)
    ↓
Workflow Search
    ↓
{
  workflow_ga: {
    name: "RNA-Seq QC",
    steps: {
      "0": { tool_id: "fastqc", inputs: {...} },
      "1": { tool_id: "multiqc", inputs: {...} }
    }
  },
  parameters: {
    input_fastq: "/data/sample.fastq"
  }
}
    ↓
Audit & Validation
    ↓
Galaxy Execution
    ↓
{
  invocation_id: "inv_12345",
  history_id: "hist_67890",
  workflow_id: "wf_abcdef"
}
    ↓
User sees execution status
```

### Status Data Flow

```
Nextflow Execution
    ↓
Writes trace.txt
    ↓
{
  process: "FASTQC",
  status: "COMPLETED",
  exit: 0,
  duration: 25000,
  memory: "512 MB"
}
    ↓
QCTraceMonitor reads trace.txt
    ↓
Checks QC thresholds
    ↓
{
  process: "FASTQC",
  metrics: {
    duration: 25s,
    memory: 512MB
  },
  thresholds: {
    max_duration: 60s,
    max_memory: 1GB
  },
  passed: true
}
    ↓
Updates Galaxy job state
    ↓
{
  job_id: "job_123",
  state: "ok"
}
    ↓
GalaxyStatePoller polls
    ↓
{
  status: "running",
  progress: {
    completedSteps: 1,
    totalSteps: 2
  },
  currentStep: "MultiQC"
}
    ↓
Frontend updates UI
    ↓
User sees: "Step 1/2 complete: FASTQC ✅"
```

---

## State Transitions

### Workflow Execution States

```
┌─────────────┐
│   PENDING   │  Workflow generation in progress
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  VALIDATING │  Audit + Parameter + Input validation
└──────┬──────┘
       │
       ├─── FAILED ──→ Return error to user
       │
       ▼
┌─────────────┐
│   QUEUED    │  Workflow queued for execution
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   RUNNING   │  Nextflow executing processes
└──────┬──────┘
       │
       ├─── QC_GATE ──→ User decision required
       │                      │
       │                      ├─ PROCEED ──→ Continue
       │                      ├─ RETRY ────→ Retry with changes
       │                      └─ CANCEL ───→ CANCELLED
       │
       ├─── ERROR ────→ Autofix attempts recovery
       │                      │
       │                      ├─ SUCCESS ──→ Continue
       │                      └─ FAIL ─────→ FAILED
       │
       ▼
┌─────────────┐
│  COMPLETED  │  All processes done, outputs ready
└─────────────┘
```

### Job States (Galaxy)

```
new → queued → running → ok
                    │
                    ├→ error
                    └→ paused
```

### Invocation States (Galaxy)

```
new → ready → scheduled (actually means completed)
           │
           └→ failed
           └→ cancelled
```

---

## Error Handling

### Error Types & Recovery

| Error Type | Detection | Recovery Strategy |
|------------|-----------|-------------------|
| **Missing Input File** | Input Validator | Immediate error before execution |
| **Invalid Parameters** | Parameter Validator | Return error, suggest fixes |
| **Tool Not Found** | Audit System | Return error, workflow invalid |
| **QC Threshold Failed** | QC Gates | User decision: proceed/retry/cancel |
| **Process Failed** | Nextflow exit code | Autofix attempts recovery |
| **Resource Limit** | Nextflow error | Autofix increases resources |
| **Dependency Missing** | Container pull fail | Autofix retries with alternatives |
| **Network Error** | API timeout | Retry with exponential backoff |

### Error Flow Example

```
Workflow Running
    ↓
Process "FASTQC" fails (exit code 1)
    ↓
Nextflow marks job as ERROR
    ↓
AutofixOrchestrator triggered
    ↓
Analyze error logs:
    "Error: Insufficient memory"
    ↓
Generate fix:
    Increase memory: 512MB → 2GB
    ↓
Apply fix to workflow
    ↓
Retry process
    ↓
Process succeeds ✅
    ↓
Workflow continues
```

---

## Performance Characteristics

### Timing Benchmarks

| Phase | Typical Time | Bottleneck |
|-------|--------------|------------|
| Request Handling | <100ms | LLM intent analysis |
| Workflow Search | <500ms | Database query |
| Workflow Generation | 2-5s | LLM generation |
| Audit | <100ms | Tool ID validation |
| Input Validation | <100ms | File existence checks |
| Galaxy Import | <500ms | Database writes |
| Nextflow Start | 1-2s | Container pull |
| Process Execution | Varies | Computation |
| Status Poll | <50ms | Database query |
| Results Retrieval | <200ms | File I/O |

### Resource Usage

| Component | Memory | CPU | Network |
|-----------|--------|-----|---------|
| Frontend | ~100MB | Low | Medium (API calls) |
| Backend | ~500MB | Medium | Low |
| Nextflow | ~200MB | Low (orchestration) | Medium (containers) |
| Processes | Varies | High (computation) | Low |

---

## Summary

The complete BioMate workflow execution involves:

1. **8 phases** from request to results
2. **15+ components** across frontend and backend
3. **5 validation systems** (Intent, Search, Audit, Parameters, Input Files)
4. **3 monitoring systems** (QC Gates, Autofix, Progressive Tuning)
5. **Multiple integration points** (Frontend↔Backend, Backend↔Galaxy, Galaxy↔Nextflow)
6. **Complex state management** (Workflow, Invocation, Job states)
7. **Comprehensive error handling** (Detection, Recovery, User notification)

**Total system complexity:** High, but well-architected with clear separation of concerns.

---

**Next:** See E2E test suite that validates this entire flow.
