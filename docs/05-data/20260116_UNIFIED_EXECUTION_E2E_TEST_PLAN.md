# Unified Execution System - End-to-End Test Plan

**Date**: 2026-01-16
**Author**: Claude Code
**Status**: Ready for Testing

---

## Overview

This document outlines comprehensive end-to-end tests for the Unified Workflow Execution system, covering:
- Frontend components (DataScopeConfig, ExecutionControlPanel)
- Frontend API endpoints (routes.ts)
- Backend API endpoints (ai_assistant.py)
- Data scope sampling strategies
- Execution lifecycle management

---

## Test Environment Setup

### Prerequisites
1. Galaxy backend running with AI Assistant enabled
2. Frontend dev server running
3. Test user authenticated in Galaxy
4. Simple test workflow available

### Simple Test Workflow (for all tests)

Use a minimal workflow for testing:
```json
{
  "a_galaxy_workflow": "true",
  "format-version": "0.1",
  "name": "E2E Test Workflow - Data Echo",
  "steps": {
    "0": {
      "annotation": "Input dataset",
      "content_id": null,
      "id": 0,
      "input_connections": {},
      "inputs": [
        {"name": "Input Dataset", "description": "Test input file"}
      ],
      "label": "Input Dataset",
      "name": "Input dataset",
      "outputs": [],
      "type": "data_input"
    },
    "1": {
      "annotation": "Simple text manipulation",
      "content_id": "toolshed.g2.bx.psu.edu/repos/bgruening/text_processing/tp_head_tool/1.1.0",
      "id": 1,
      "input_connections": {
        "infile": {"id": 0, "output_name": "output"}
      },
      "label": "Head Tool",
      "name": "Select first",
      "outputs": [{"name": "outfile", "type": "txt"}],
      "tool_state": "{\"infile\": {\"__class__\": \"RuntimeValue\"}, \"n\": \"10\"}",
      "type": "tool"
    }
  },
  "tags": ["e2e-test"],
  "uuid": "e2e-test-workflow-001"
}
```

### Test Data

Create 100 small test files for sampling tests:
```bash
for i in {1..100}; do
  echo "Test sample $i - $(date)" > /tmp/test_sample_$i.txt
done
```

---

## Test Scenarios

### Scenario 1: Basic Sandbox Execution (10% Data Scope)

**Purpose**: Verify basic unified execution with reduced data scope

**Steps**:
1. POST `/api/workflows/execute` with:
   ```json
   {
     "workflow_definition": { /* test workflow */ },
     "execution_config": {
       "mode": "sandbox",
       "data_scope": {
         "fraction": 0.1,
         "sampling_strategy": "random"
       }
     },
     "inputs": [ /* 100 test inputs */ ],
     "workflow_name": "E2E Test - Basic Sandbox"
   }
   ```

**Expected Results**:
- [ ] Response contains `run_id`, `galaxy_invocation_id`, `galaxy_history_id`
- [ ] `status` is "running"
- [ ] `mode` is "sandbox"
- [ ] `data_scope_applied.fraction` is 0.1
- [ ] `data_scope_applied.absolute_count` is 10 (10% of 100)
- [ ] Galaxy history name starts with "[Sandbox]"

**Verification Commands**:
```bash
# Test execution
curl -X POST http://localhost:8080/api/ai_assistant/execute \
  -H "Content-Type: application/json" \
  -H "x-api-key: $GALAXY_API_KEY" \
  -d '{"workflow_definition": {...}, "execution_config": {"mode": "sandbox", "data_scope": {"fraction": 0.1}}, "inputs": [...], "workflow_name": "E2E Test"}'

# Verify response
# Check run_id, galaxy_invocation_id, status == "running", mode == "sandbox"
```

---

### Scenario 2: Production Execution (100% Data Scope)

**Purpose**: Verify production mode execution uses all data

**Steps**:
1. POST `/api/workflows/execute` with:
   ```json
   {
     "workflow_definition": { /* test workflow */ },
     "execution_config": {
       "mode": "production",
       "data_scope": {
         "fraction": 1.0,
         "sampling_strategy": "random"
       }
     },
     "inputs": [ /* 100 test inputs */ ],
     "workflow_name": "E2E Test - Production"
   }
   ```

**Expected Results**:
- [ ] `mode` is "production"
- [ ] `data_scope_applied.fraction` is 1.0
- [ ] `data_scope_applied.absolute_count` is 100
- [ ] Galaxy history name starts with "[Production]"

---

### Scenario 3: Data Sampling Strategies

#### 3.1: Random Sampling

```json
{
  "data_scope": {
    "fraction": 0.25,
    "sampling_strategy": "random"
  }
}
```

**Expected**:
- [ ] 25 random samples selected
- [ ] Different samples each time (non-deterministic)

#### 3.2: First N Sampling

```json
{
  "data_scope": {
    "fraction": 0.25,
    "sampling_strategy": "first_n"
  }
}
```

**Expected**:
- [ ] First 25 samples selected
- [ ] Same samples each time (deterministic)
- [ ] `sampled_ids` contains IDs from beginning of list

#### 3.3: Stratified Sampling

Prepare inputs with metadata:
```json
{
  "data_scope": {
    "fraction": 0.2,
    "sampling_strategy": "stratified",
    "strata_column": "sample_type"
  }
}
```

With sample metadata:
```json
[
  {"id": "1", "sample_type": "control"},
  {"id": "2", "sample_type": "treatment"},
  // 50 control, 50 treatment
]
```

**Expected**:
- [ ] `strata_distribution` shows proportional sampling
- [ ] ~10 control + ~10 treatment = 20 total
- [ ] Proportions maintained from original distribution

#### 3.4: Representative Sampling

```json
{
  "data_scope": {
    "fraction": 0.25,
    "sampling_strategy": "representative"
  }
}
```

**Expected**:
- [ ] Samples spread evenly across dataset
- [ ] Sample indices evenly spaced (e.g., 0, 4, 8, 12, ...)

---

### Scenario 4: Execution Lifecycle Management

#### 4.1: Status Polling

**Steps**:
1. Start execution
2. Poll status every 2 seconds

```bash
# Start run
RUN_ID=$(curl -X POST /api/ai_assistant/execute ... | jq -r '.run_id')

# Poll status
while true; do
  STATUS=$(curl /api/ai_assistant/execution/$RUN_ID/status | jq -r '.status')
  echo "Status: $STATUS"
  if [[ "$STATUS" == "completed" || "$STATUS" == "failed" ]]; then
    break
  fi
  sleep 2
done
```

**Expected**:
- [ ] Status transitions: running → completed (or failed)
- [ ] Progress percent increases over time
- [ ] `current_step` increments

#### 4.2: Pause/Resume

**Steps**:
1. Start execution
2. Pause while running
3. Verify paused state
4. Resume
5. Verify running again

```bash
# Pause
curl -X POST /api/ai_assistant/execution/$RUN_ID/pause?reason=Testing

# Verify paused
curl /api/ai_assistant/execution/$RUN_ID | jq '.status'  # Should be "paused"

# Resume
curl -X POST /api/ai_assistant/execution/$RUN_ID/resume

# Verify running
curl /api/ai_assistant/execution/$RUN_ID | jq '.status'  # Should be "running"
```

**Expected**:
- [ ] Pause succeeds when status is "running"
- [ ] Pause fails when status is not "running"
- [ ] Resume succeeds when status is "paused"
- [ ] Interactions array records pause/resume events

#### 4.3: Cancel

**Steps**:
1. Start execution
2. Cancel while running

```bash
curl -X POST /api/ai_assistant/execution/$RUN_ID/cancel
```

**Expected**:
- [ ] Status becomes "cancelled"
- [ ] Galaxy invocation cancellation attempted
- [ ] `completed_at` timestamp set

---

### Scenario 5: Iteration Linking

**Purpose**: Verify parent-child run linking for iteration tracking

**Steps**:
1. Start sandbox run (Run 1)
2. Wait for completion
3. Start another run with `parent_run_id` = Run 1 (Run 2)
4. Get iterations for Run 1

```bash
# Run 1
RUN_1=$(curl -X POST /api/ai_assistant/execute \
  -d '{"execution_config": {"mode": "sandbox", "data_scope": {"fraction": 0.1}}, ...}' \
  | jq -r '.run_id')

# Wait for completion
# ...

# Run 2 (child of Run 1)
RUN_2=$(curl -X POST /api/ai_assistant/execute \
  -d '{"execution_config": {"mode": "sandbox", "parent_run_id": "'$RUN_1'", "data_scope": {"fraction": 0.2}}, ...}' \
  | jq -r '.run_id')

# Get iterations
curl /api/ai_assistant/execution/$RUN_1/iterations
```

**Expected**:
- [ ] Run 2 has `parent_run_id` = Run 1
- [ ] Run 2 has `run_sequence` = 2
- [ ] Iterations endpoint returns both runs
- [ ] Runs sorted by `run_sequence`

---

### Scenario 6: Run Comparison

**Purpose**: Verify comparison between two runs

**Steps**:
1. Complete Run 1 with params: `{"star": {"threads": 4}}`
2. Complete Run 2 with params: `{"star": {"threads": 8}}`
3. Compare runs

```bash
curl "/api/ai_assistant/execution/$RUN_1/compare?compare_with=$RUN_2"
```

**Expected**:
- [ ] `comparison.data_scope_delta` shows fraction differences
- [ ] `comparison.parameter_differences` lists changed params
- [ ] Parameter difference shows threads 4 vs 8

---

### Scenario 7: Promote Sandbox to Production

**Purpose**: Verify promotion flow

**Steps**:
1. Complete sandbox run at 10%
2. Promote to production

```bash
# Complete sandbox run
RUN_1=$(curl -X POST /api/ai_assistant/execute \
  -d '{"execution_config": {"mode": "sandbox", "data_scope": {"fraction": 0.1}}, ...}' \
  | jq -r '.run_id')

# Wait for completion
# ...

# Promote
curl -X POST /api/ai_assistant/execution/$RUN_1/promote
```

**Expected**:
- [ ] New production run created
- [ ] Production run has `mode` = "production"
- [ ] Production run has `fraction` = 1.0
- [ ] Production run has `parent_run_id` = sandbox run ID
- [ ] Same parameters as sandbox run

---

### Scenario 8: Frontend Components

#### 8.1: DataScopeConfig Component

**Test file**: `data-scope-config.test.tsx`

```typescript
describe('DataScopeConfig', () => {
  it('renders fraction slider', () => {
    render(<DataScopeConfig totalSamples={100} onChange={jest.fn()} />);
    expect(screen.getByText('Sample Fraction')).toBeInTheDocument();
  });

  it('updates fraction on slider change', () => {
    const onChange = jest.fn();
    render(<DataScopeConfig totalSamples={100} onChange={onChange} />);
    // Simulate slider change to 25%
    fireEvent.change(slider, { target: { value: 0.25 } });
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({
      fraction: 0.25,
      absoluteCount: 25
    }));
  });

  it('shows preset buttons', () => {
    render(<DataScopeConfig totalSamples={100} onChange={jest.fn()} />);
    expect(screen.getByText('5%')).toBeInTheDocument();
    expect(screen.getByText('10%')).toBeInTheDocument();
    expect(screen.getByText('25%')).toBeInTheDocument();
    expect(screen.getByText('50%')).toBeInTheDocument();
    expect(screen.getByText('100%')).toBeInTheDocument();
  });

  it('shows strata options when stratified sampling selected', () => {
    render(<DataScopeConfig
      totalSamples={100}
      strataColumns={['sample_type', 'batch']}
      onChange={jest.fn()}
    />);
    // Select stratified
    fireEvent.click(screen.getByText('Stratified'));
    expect(screen.getByText('Group By')).toBeInTheDocument();
  });

  it('calculates strata distribution preview', () => {
    const sampleMetadata = [
      { id: '1', sample_type: 'control' },
      { id: '2', sample_type: 'treatment' },
      // ... 50/50 split
    ];
    render(<DataScopeConfig
      totalSamples={100}
      strataColumns={['sample_type']}
      sampleMetadata={sampleMetadata}
      initialConfig={{ samplingStrategy: 'stratified', strataColumn: 'sample_type', fraction: 0.2 }}
      onChange={jest.fn()}
    />);
    expect(screen.getByText('control')).toBeInTheDocument();
    expect(screen.getByText('treatment')).toBeInTheDocument();
  });
});
```

#### 8.2: ExecutionControlPanel Component

**Test file**: `execution-control-panel.test.tsx`

```typescript
describe('ExecutionControlPanel', () => {
  it('renders mode toggle', () => {
    render(<ExecutionControlPanel workflow={mockWorkflow} />);
    expect(screen.getByText('Sandbox')).toBeInTheDocument();
    expect(screen.getByText('Production')).toBeInTheDocument();
  });

  it('switches mode on toggle click', () => {
    render(<ExecutionControlPanel workflow={mockWorkflow} />);
    fireEvent.click(screen.getByText('Production'));
    // Verify production mode is selected (amber → green styling)
    expect(screen.getByText('Production')).toHaveClass('bg-green-500');
  });

  it('shows run button with data scope', () => {
    render(<ExecutionControlPanel workflow={mockWorkflow} totalSamples={100} />);
    // Default 10%
    expect(screen.getByText('Run (10%)')).toBeInTheDocument();
  });

  it('shows progress when running', () => {
    render(<ExecutionControlPanel
      workflow={mockWorkflow}
      executionRun={{ status: 'running', progress: { percent: 50 } }}
    />);
    expect(screen.getByText('50%')).toBeInTheDocument();
    expect(screen.getByText('Pause')).toBeInTheDocument();
    expect(screen.getByText('Cancel')).toBeInTheDocument();
  });

  it('shows promote button when sandbox completed', () => {
    render(<ExecutionControlPanel
      workflow={mockWorkflow}
      executionRun={{ mode: 'sandbox', status: 'completed' }}
    />);
    expect(screen.getByText('Promote to Production')).toBeInTheDocument();
  });

  it('applies recommendation on click', () => {
    const onApplyRecommendation = jest.fn();
    render(<ExecutionControlPanel
      workflow={mockWorkflow}
      recommendations={[{
        toolId: 'star',
        paramName: 'threads',
        recommendedValue: 8,
        reason: 'Optimal for this dataset size'
      }]}
      onApplyRecommendation={onApplyRecommendation}
    />);
    fireEvent.click(screen.getByText('Apply'));
    expect(onApplyRecommendation).toHaveBeenCalled();
  });
});
```

---

### Scenario 9: API Error Handling

#### 9.1: Invalid Data Scope

```bash
# Fraction out of range
curl -X POST /api/ai_assistant/execute \
  -d '{"execution_config": {"data_scope": {"fraction": 2.0}}, ...}'
# Expected: 422 Validation Error
```

#### 9.2: Missing Workflow

```bash
# No workflow_id or workflow_definition
curl -X POST /api/ai_assistant/execute \
  -d '{"execution_config": {}, "inputs": []}'
# Expected: 400 "Either workflow_id or workflow_definition is required"
```

#### 9.3: Run Not Found

```bash
curl /api/ai_assistant/execution/nonexistent_run_id
# Expected: 404 "Execution run nonexistent_run_id not found"
```

#### 9.4: Invalid State Transition

```bash
# Pause a completed run
curl -X POST /api/ai_assistant/execution/$COMPLETED_RUN/pause
# Expected: 400 "Cannot pause run with status: completed"
```

---

## Integration Test Script

Full automated test script:

```bash
#!/bin/bash
# e2e_unified_execution_test.sh

set -e

BASE_URL="http://localhost:8080"
API_KEY="${GALAXY_API_KEY}"

echo "=== Unified Execution E2E Tests ==="

# Test 1: Basic Sandbox Execution
echo "Test 1: Basic Sandbox Execution"
RESPONSE=$(curl -s -X POST "$BASE_URL/api/ai_assistant/execute" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{
    "workflow_definition": {
      "a_galaxy_workflow": "true",
      "format-version": "0.1",
      "name": "E2E Test",
      "steps": {}
    },
    "execution_config": {
      "mode": "sandbox",
      "data_scope": {"fraction": 0.1, "sampling_strategy": "random"}
    },
    "inputs": [],
    "workflow_name": "E2E Test"
  }')

RUN_ID=$(echo $RESPONSE | jq -r '.run_id')
MODE=$(echo $RESPONSE | jq -r '.mode')
FRACTION=$(echo $RESPONSE | jq -r '.data_scope_applied.fraction')

if [[ "$MODE" == "sandbox" && "$FRACTION" == "0.1" ]]; then
  echo "  PASS: Sandbox run created with 10% data scope"
else
  echo "  FAIL: Expected sandbox mode with 0.1 fraction"
  exit 1
fi

# Test 2: Status Polling
echo "Test 2: Status Polling"
STATUS=$(curl -s "$BASE_URL/api/ai_assistant/execution/$RUN_ID/status" | jq -r '.status')
if [[ "$STATUS" == "running" || "$STATUS" == "completed" ]]; then
  echo "  PASS: Status endpoint working"
else
  echo "  FAIL: Unexpected status: $STATUS"
  exit 1
fi

# Test 3: Pause/Resume
echo "Test 3: Pause/Resume"
if [[ "$STATUS" == "running" ]]; then
  curl -s -X POST "$BASE_URL/api/ai_assistant/execution/$RUN_ID/pause?reason=E2E%20test"
  PAUSED_STATUS=$(curl -s "$BASE_URL/api/ai_assistant/execution/$RUN_ID" | jq -r '.status')
  if [[ "$PAUSED_STATUS" == "paused" ]]; then
    echo "  PASS: Run paused successfully"
    curl -s -X POST "$BASE_URL/api/ai_assistant/execution/$RUN_ID/resume"
    RESUMED_STATUS=$(curl -s "$BASE_URL/api/ai_assistant/execution/$RUN_ID" | jq -r '.status')
    if [[ "$RESUMED_STATUS" == "running" ]]; then
      echo "  PASS: Run resumed successfully"
    fi
  fi
else
  echo "  SKIP: Run already completed"
fi

# Test 4: Iterations
echo "Test 4: Iterations"
ITERATIONS=$(curl -s "$BASE_URL/api/ai_assistant/execution/$RUN_ID/iterations" | jq -r '.total_iterations')
if [[ "$ITERATIONS" -ge 1 ]]; then
  echo "  PASS: Iterations endpoint working"
else
  echo "  FAIL: Expected at least 1 iteration"
  exit 1
fi

echo ""
echo "=== All E2E Tests Passed ==="
```

---

## Test Coverage Summary

| Component | Test Coverage |
|-----------|---------------|
| Backend `/api/ai_assistant/execute` | Full lifecycle |
| Backend `/api/ai_assistant/execution/{id}` | CRUD operations |
| Backend Sampling Strategies | All 4 strategies |
| Frontend DataScopeConfig | All props and interactions |
| Frontend ExecutionControlPanel | All states and actions |
| Error Handling | Validation, 404, state transitions |

---

## Known Limitations

1. **Galaxy Pause**: Galaxy doesn't support true invocation pausing. Our pause/resume is tracked at the application layer.

2. **In-Memory Storage**: Current implementation uses in-memory storage. Production should use persistent database.

3. **Stratified Sampling**: Requires sample metadata to be passed with inputs.

---

## Next Steps After Testing

1. Integrate ExecutionControlPanel into workflow-artifact.tsx
2. Connect frontend to new backend endpoints
3. Add persistent storage for execution runs
4. Implement real metrics collection from Galaxy jobs
