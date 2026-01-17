# Unified Workflow Execution & Tuning Architecture

**Date**: 2026-01-16
**Author**: BioMate Architecture Team
**Status**: Approved for Implementation

## Overview

Design a unified workflow execution system where **sandbox (pilot) and production runs use the same code path**, with:
- Tunable data scope (any percentage, not just subset vs full)
- Rich user interaction during execution
- Explicit, structured tracking with visualization

---

## Problem Statement

Current issues:
1. Pilot runs have separate, simplified code paths
2. Data scope is binary (pilot subset vs full) instead of tunable
3. Tuning interactions only available in pilot mode
4. Limited structured tracking during execution
5. User interaction is passive (just watching progress)

---

## Design Principles

1. **One Execution Engine**: Sandbox and production are modes, not different systems
2. **Tunable Everything**: Data scope, parameters, resources - all adjustable
3. **Active Interaction**: Users can adjust parameters during/between runs
4. **Structured Visibility**: Every decision and metric is tracked and visualized

---

## Architecture

### Execution Modes (Same Engine)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    UNIFIED WORKFLOW EXECUTOR                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   execution_config = {                                              │
│     mode: 'sandbox' | 'production',                                 │
│     data_scope: {                                                   │
│       fraction: 0.1,          // Any value 0.01 - 1.0               │
│       sampling_strategy: 'stratified',                              │
│       explicit_samples: [...] // Or specific sample IDs             │
│     },                                                              │
│     environment: {                                                  │
│       history_prefix: '[Sandbox]' | '[Production]',                 │
│       allow_tuning: true,     // Always true in sandbox             │
│       allow_adjustment: true, // Mid-run parameter changes          │
│     },                                                              │
│     tracking: {                                                     │
│       collect_metrics: true,                                        │
│       log_level: 'detailed',                                        │
│       notify_milestones: true,                                      │
│     }                                                               │
│   }                                                                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Tuning Interaction Loop

```
┌──────────────────────────────────────────────────────────────────────┐
│                     TUNING INTERACTION CYCLE                         │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐            │
│  │  CONFIGURE  │ ──▶ │   EXECUTE   │ ──▶ │   REVIEW    │            │
│  │             │     │             │     │             │            │
│  │ • Data scope│     │ • Real-time │     │ • Metrics   │            │
│  │ • Parameters│     │   progress  │     │ • Quality   │            │
│  │ • Resources │     │ • Live logs │     │ • Compare   │            │
│  └─────────────┘     │ • Alerts    │     │ • Recommend │            │
│         ▲            └──────┬──────┘     └──────┬──────┘            │
│         │                   │                   │                    │
│         │         ┌─────────▼─────────┐         │                    │
│         │         │    MID-RUN        │         │                    │
│         │         │   ADJUSTMENTS     │         │                    │
│         │         │ • Pause/Resume    │         │                    │
│         │         │ • Parameter tweak │         │                    │
│         │         │ • Resource scale  │         │                    │
│         │         └───────────────────┘         │                    │
│         │                                       │                    │
│         └───────────────────────────────────────┘                    │
│                    (Iterate until satisfied)                         │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    PROMOTE TO PRODUCTION                       │  │
│  │  When satisfied: Apply same config to full data (100%)        │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Structured Tracking Schema

### Execution Run Record

```typescript
interface ExecutionRun {
  // Identity
  id: string;
  parentRunId?: string;        // Links iterations together
  runSequence: number;         // 1, 2, 3... within iteration cycle

  // Mode
  mode: 'sandbox' | 'production';

  // Data Scope (TUNABLE)
  dataScope: {
    fraction: number;          // 0.01 - 1.0 (1% to 100%)
    absoluteCount: number;     // Actual sample count used
    totalAvailable: number;    // Total samples available
    samplingStrategy: 'random' | 'stratified' | 'first_n' | 'representative';
    sampledIds: string[];      // Which samples were used
    strataDistribution?: Record<string, number>; // For stratified
  };

  // Parameters (VERSIONED)
  parameters: {
    version: number;           // Increments on each adjustment
    toolParameters: Record<string, Record<string, any>>;
    changedFrom?: {            // What changed from previous run
      toolId: string;
      paramName: string;
      oldValue: any;
      newValue: any;
      reason: string;
    }[];
  };

  // Execution
  execution: {
    galaxyInvocationId: string;
    galaxyHistoryId: string;
    status: 'configuring' | 'queued' | 'running' | 'paused' | 'completed' | 'failed' | 'cancelled';
    startedAt?: Date;
    completedAt?: Date;
    pausedAt?: Date;
    pauseReason?: string;
  };

  // Step-Level Tracking
  steps: StepExecution[];

  // Metrics (DETAILED)
  metrics: {
    runtime: {
      totalSeconds: number;
      perStepSeconds: Record<string, number>;
      estimatedRemaining?: number;
    };
    resources: {
      peakMemoryGB: number;
      avgCpuPercent: number;
      diskUsedGB: number;
    };
    quality: Record<string, number>; // Domain-specific metrics
    outputs: {
      fileCount: number;
      totalSizeBytes: number;
      byType: Record<string, number>;
    };
  };

  // User Interactions
  interactions: UserInteraction[];

  // Recommendations
  recommendations: ParameterRecommendation[];

  // Comparison (if iterating)
  comparison?: {
    previousRunId: string;
    runtimeDelta: number;      // % change
    qualityDelta: Record<string, number>;
    improvementSummary: string;
  };
}

interface StepExecution {
  stepId: string;
  stepName: string;
  toolId: string;

  status: 'pending' | 'queued' | 'running' | 'completed' | 'failed' | 'skipped';

  timing: {
    queuedAt?: Date;
    startedAt?: Date;
    completedAt?: Date;
    durationMs?: number;
  };

  metrics: {
    memoryUsedGB?: number;
    cpuPercent?: number;
    inputSizeBytes?: number;
    outputSizeBytes?: number;
  };

  logs: {
    stdout: string[];
    stderr: string[];
    truncated: boolean;
  };

  outputs: {
    datasetId: string;
    name: string;
    extension: string;
    sizeBytes: number;
  }[];
}

interface UserInteraction {
  timestamp: Date;
  type: 'parameter_change' | 'pause' | 'resume' | 'cancel' | 'apply_recommendation' | 'adjust_data_scope';
  details: Record<string, any>;
  reason?: string;            // User's stated reason
}
```

---

## UI Components

### 1. Execution Control Panel (NEW)

Replaces separate pilot config + execution status:

```
┌─────────────────────────────────────────────────────────────────┐
│  WORKFLOW EXECUTION                                    [Sandbox] │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  DATA SCOPE ──────────────────────────────────────────────────  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  [====|==========]  25%  (250 of 1000 samples)           │   │
│  │                                                           │   │
│  │  Strategy: [Stratified ▼]   Group by: [sample_type ▼]    │   │
│  │                                                           │   │
│  │  Distribution:                                            │   │
│  │    control: 125 samples (50%)                            │   │
│  │    treatment: 125 samples (50%)                          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  PARAMETERS ──────────────────────────────────────────────────  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  ▸ STAR Aligner                                          │   │
│  │    threads: 8  [Adjust]                                  │   │
│  │    outSAMtype: BAM SortedByCoordinate                    │   │
│  │                                                           │   │
│  │  ▸ featureCounts                                         │   │
│  │    threads: 8  [Adjust]  ⚡ Recommendation available      │   │
│  │    minOverlap: 1                                         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌────────────────┐  ┌────────────────┐                        │
│  │  ▶ Run (25%)   │  │  ▶ Run (100%)  │    Run #3 of iteration │
│  └────────────────┘  └────────────────┘                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 2. Live Execution Dashboard (ENHANCED)

```
┌─────────────────────────────────────────────────────────────────┐
│  RUNNING: RNA-Seq Analysis                          [Sandbox 25%]│
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  PROGRESS ────────────────────────────────────────────────────  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  ████████████░░░░░░░░░░░░░░░░░░  Step 3/8 (37%)         │   │
│  │                                                           │   │
│  │  ETA: ~4 min 30 sec                                      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  STEP DETAILS ────────────────────────────────────────────────  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  ✓ 1. Input validation         (2.1s)                    │   │
│  │  ✓ 2. Quality control          (45.3s)  📊 Report ready  │   │
│  │  ⟳ 3. STAR alignment          [Running 2:15]             │   │
│  │       Memory: 12.4 GB | CPU: 85% | Progress: 67%         │   │
│  │       ┌─────────────────────────────────────────────┐    │   │
│  │       │  Processing: sample_042.fastq               │    │   │
│  │       │  Mapped: 45.2M reads (89.3%)                │    │   │
│  │       └─────────────────────────────────────────────┘    │   │
│  │  ○ 4. featureCounts            (pending)                 │   │
│  │  ○ 5. DESeq2                   (pending)                 │   │
│  │  ...                                                      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  LIVE METRICS ────────────────────────────────────────────────  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Peak Memory: 14.2 GB    Disk Used: 8.7 GB               │   │
│  │  Avg CPU: 72%            Est. Cost: $0.45                │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  [⏸ Pause]  [⏹ Cancel]  [📋 View Logs]  [⚙️ Adjust Parameters] │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3. Run Comparison Panel (NEW)

```
┌─────────────────────────────────────────────────────────────────┐
│  ITERATION COMPARISON                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Run 1 (10%)          Run 2 (10%)          Run 3 (25%)          │
│  ─────────────        ─────────────        ─────────────        │
│  threads=4            threads=8            threads=8            │
│                                                                  │
│  Runtime: 12m 30s     Runtime: 7m 45s      Runtime: 18m 20s     │
│                       ↓ 38% faster         (scaled correctly)    │
│                                                                  │
│  Memory: 8.2 GB       Memory: 14.1 GB      Memory: 14.8 GB      │
│                       ↑ Higher but OK      ↑ Stable              │
│                                                                  │
│  Quality:             Quality:             Quality:              │
│    Mapped: 87.2%        Mapped: 89.1%        Mapped: 89.3%       │
│    Unique: 72.4%        Unique: 74.8%        Unique: 75.1%       │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  📊 RECOMMENDATION:                                       │   │
│  │  Run 2 config (threads=8) shows best balance.            │   │
│  │  Quality improved 2.2% with acceptable memory increase.   │   │
│  │                                                           │   │
│  │  Full run estimate: ~73 min, 16 GB memory, $3.65 cost    │   │
│  │                                                           │   │
│  │  [Apply to Full Run]  [Try Another Config]  [View Details]│   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Plan

### Phase 1: Unified Execution Schema
**Files to modify:**
- `frontend/shared/schema.ts` - Add ExecutionRun, StepExecution, UserInteraction schemas
- `frontend/server/storage.ts` - Add execution run CRUD methods
- `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` - Unified invoke endpoint

### Phase 2: Tunable Data Scope
**Files to modify:**
- `backend/lib/galaxy/ai/progressive_tuning.py` - Enhance DataSampler for any fraction
- `frontend/client/src/components/data-scope-config.tsx` - NEW: Data scope slider/config UI
- Frontend API to pass dataScope config

### Phase 3: Execution Control Panel
**Files to modify:**
- `frontend/client/src/components/execution-control-panel.tsx` - NEW: Unified config + execution
- `frontend/client/src/components/workflow-artifact.tsx` - Integrate new panel
- Remove separate pilot-run-panel.tsx (merge into execution-control-panel)

### Phase 4: Live Dashboard Enhancement
**Files to modify:**
- `frontend/client/src/hooks/useWorkflowExecution.ts` - Enhanced step metrics
- `frontend/server/galaxy-state-poller.ts` - Collect detailed metrics
- `frontend/client/src/components/live-execution-dashboard.tsx` - NEW: Rich live view

### Phase 5: Run Comparison
**Files to modify:**
- `frontend/client/src/components/run-comparison-panel.tsx` - NEW: Compare iterations
- `frontend/server/routes.ts` - API endpoint to fetch run history for comparison
- Recommendation engine enhancement

### Phase 6: User Interaction Tracking
**Files to modify:**
- `frontend/server/storage.ts` - Track all user interactions
- `frontend/client/src/hooks/useExecutionInteractions.ts` - NEW: Interaction hook
- Audit log integration

---

## Key API Changes

### New Unified Invoke Endpoint

```
POST /api/workflows/execute
{
  workflow_definition: {...},    // .ga format

  execution_config: {
    mode: 'sandbox' | 'production',

    data_scope: {
      fraction: 0.25,            // 25% of data
      sampling_strategy: 'stratified',
      strata_column: 'sample_type',
      explicit_samples?: string[], // Override: use these specific samples
    },

    parameters: {
      'star': { threads: 8 },
      'featurecounts': { minOverlap: 10 },
    },

    tracking: {
      collect_detailed_metrics: true,
      notify_milestones: true,
      log_level: 'verbose',
    },

    parent_run_id?: string,      // Links to previous iteration
  },

  inputs: [...]
}

Response:
{
  run_id: string,
  galaxy_invocation_id: string,
  galaxy_history_id: string,
  status: 'queued',
  data_scope_applied: {
    fraction: 0.25,
    absolute_count: 250,
    sampled_ids: [...],
  }
}
```

### Run Status with Detailed Metrics

```
GET /api/workflows/runs/{run_id}
{
  ...full ExecutionRun object...
}
```

### Compare Runs

```
GET /api/workflows/runs/{run_id}/compare?with={other_run_id}
{
  runs: [run1, run2],
  comparison: {
    runtime_delta: -38,         // % change
    memory_delta: +72,
    quality_delta: { mapped: +1.9, unique: +2.4 },
  },
  recommendation: {
    preferred_run: 'run2',
    reason: 'Better quality with acceptable resource increase',
    full_run_estimate: {...},
  }
}
```

---

## Verification Plan

1. **Unit Tests**: Schema validation, data sampling accuracy
2. **Integration Tests**: Full invoke → track → compare cycle
3. **E2E Tests**:
   - Start sandbox run at 10%
   - Adjust parameters mid-run (pause/resume)
   - Compare with previous run
   - Promote to production at 100%
4. **UI Tests**: Visual regression for new panels

---

## Design Decisions (Confirmed)

1. **Mid-run parameter changes**: Require pause first. User must pause workflow before changing parameters - safer and predictable.

2. **Comparison depth**: Last 2 runs (A/B comparison). Simple, clean UI that shows current vs previous iteration.

3. **Production tuning**: Same interactions as sandbox. Production and sandbox have identical capabilities. Only difference is data scope and history naming.

---

## File Change Summary

### New Files to Create:
| File | Purpose |
|------|---------|
| `frontend/shared/schema.ts` | Add ExecutionRun, StepExecution, UserInteraction types |
| `frontend/client/src/components/execution-control-panel.tsx` | Unified config + execution UI |
| `frontend/client/src/components/data-scope-config.tsx` | Tunable data scope slider |
| `frontend/client/src/components/live-execution-dashboard.tsx` | Rich real-time execution view |
| `frontend/client/src/components/run-comparison-panel.tsx` | A/B comparison of runs |
| `frontend/client/src/hooks/useExecutionRun.ts` | Hook for execution run state |

### Files to Modify:
| File | Changes |
|------|---------|
| `frontend/server/routes.ts` | Add unified `/api/workflows/execute` endpoint |
| `frontend/server/storage.ts` | Add ExecutionRun CRUD methods |
| `frontend/server/galaxy-state-poller.ts` | Collect detailed step metrics |
| `backend/lib/galaxy/ai/progressive_tuning.py` | Enhance DataSampler for any fraction |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | Unified execution endpoint |
| `frontend/client/src/components/workflow-artifact.tsx` | Integrate ExecutionControlPanel |

### Files to Deprecate:
| File | Reason |
|------|--------|
| `frontend/client/src/components/pilot-run-panel.tsx` | Merged into ExecutionControlPanel |
