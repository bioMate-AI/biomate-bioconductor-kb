# Comprehensive E2E Test IDs - Complete Reference

**Date**: 2025-10-14
**Purpose**: Complete list of all test IDs for granular E2E testing including step-level operations, parameter editing, progress tracking, and dataset workflows

---

## Table of Contents

1. [Chat Interface Test IDs](#chat-interface-test-ids)
2. [Workflow Builder Test IDs](#workflow-builder-test-ids)
3. [Individual Step Test IDs](#individual-step-test-ids)
4. [Parameter Editing Test IDs](#parameter-editing-test-ids)
5. [Progress Tracking Test IDs](#progress-tracking-test-ids)
6. [Dataset Input Test IDs](#dataset-input-test-ids)
7. [Execution Output Test IDs](#execution-output-test-ids)
8. [Test Scenarios](#test-scenarios)

---

## Chat Interface Test IDs

### Basic Chat Operations
| Test ID | Element | Purpose | File |
|---------|---------|---------|------|
| `chat-input` | Textarea | Type user queries | chat-input.tsx:54 |
| `chat-send-button` | Button | Send chat messages | chat-input.tsx:68 |
| `chat-messages` | ScrollArea | View chat history | chat-interface.tsx:395 |
| `workflow-generated-message` | Div | Detect workflow generation | chat-message.tsx:44 |
| `button-view-workflow` | Button | Open workflow in builder | chat-message.tsx:102 |

### Progress Display
| Test ID | Element | Purpose | File |
|---------|---------|---------|------|
| `button-toggle-progress` | Button | Show/hide progress section | chat-interface.tsx:415 |
| `button-view-logs` | Button | View execution logs | chat-interface.tsx:496 |
| `button-workflow-settings` | Button | Open workflow settings | chat-interface.tsx:499 |

---

## Workflow Builder Test IDs

### Overall Workflow Controls
| Test ID | Element | Purpose | File |
|---------|---------|---------|------|
| `button-execute-workflow` | Button | Start entire workflow | enhanced-workflow-builder.tsx:581 |
| `button-workflow-pause` | Button | Pause workflow execution | enhanced-workflow-builder.tsx:591 |
| `button-workflow-resume` | Button | Resume paused workflow | enhanced-workflow-builder.tsx:602 |
| `button-workflow-stop` | Button | Stop workflow execution | enhanced-workflow-builder.tsx:613 |
| `button-workflow-restart` | Button | Restart workflow | enhanced-workflow-builder.tsx:622 |
| `button-save-workflow` | Button | Save workflow | enhanced-workflow-builder.tsx:634 |
| `button-export-workflow` | Button | Export workflow as .ga | enhanced-workflow-builder.tsx:642 |
| `button-add-step` | Button | Add new workflow step | enhanced-workflow-builder.tsx:653 |

### Workflow Status
| Test ID | Element | Purpose | File |
|---------|---------|---------|------|
| `workflow-status-idle` | Badge | Workflow not started | enhanced-workflow-builder.tsx:527 |
| `workflow-status-running` | Badge | Workflow executing | enhanced-workflow-builder.tsx:527 |
| `workflow-status-paused` | Badge | Workflow paused | enhanced-workflow-builder.tsx:527 |
| `workflow-status-completed` | Badge | Workflow finished | enhanced-workflow-builder.tsx:527 |
| `workflow-graph` | SVG | Visual workflow graph | workflow-graph.tsx:316 |
| `artifacts-panel` | Panel | Workflow builder panel | chat-with-artifacts.tsx:212 |
| `workflow-builder` | Div | Workflow builder container | chat-with-artifacts.tsx:230 |

---

## Individual Step Test IDs

### Step Identification
| Test ID Pattern | Element | Purpose | File |
|-----------------|---------|---------|------|
| `graph-node-{stepId}` | ForeignObject | Individual step node | workflow-graph.tsx:184 |
| `step-status-{stepId}` | Badge | Step status indicator | (needs to be added) |

### Step-Level Actions
| Test ID Pattern | Element | Purpose | File |
|-----------------|---------|---------|------|
| `button-graph-run-{stepId}` | Button | Run individual step | workflow-graph.tsx:233 |
| `button-graph-pause-{stepId}` | Button | Pause step execution | workflow-graph.tsx:246 |
| `button-graph-restart-{stepId}` | Button | Restart step | workflow-graph.tsx:259 |
| `button-graph-edit-{stepId}` | Button | Edit step parameters | workflow-graph.tsx:271 |
| `button-graph-delete-{stepId}` | Button | Delete step | workflow-graph.tsx:283 |

### Example Step IDs
```python
# For step with ID "step1":
page.locator('[data-testid="graph-node-step1"]').click()
page.locator('[data-testid="button-graph-run-step1"]').click()
page.locator('[data-testid="button-graph-edit-step1"]').click()

# For step with ID "step2":
page.locator('[data-testid="graph-node-step2"]').click()
page.locator('[data-testid="button-graph-run-step2"]').click()
```

---

## Parameter Editing Test IDs

### Parameter Dialog *(Needs to be added)*
| Test ID | Element | Purpose | Location |
|---------|---------|---------|----------|
| `parameter-dialog` | Dialog | Parameter editing dialog | parameter-dialog.tsx or parameter-editor.tsx |
| `parameter-input-{paramName}` | Input | Edit specific parameter | parameter-dialog.tsx |
| `button-save-parameters` | Button | Save parameter changes | parameter-dialog.tsx |
| `button-cancel-parameters` | Button | Cancel parameter editing | parameter-dialog.tsx |
| `parameter-validation-error` | Div | Show validation errors | parameter-dialog.tsx |

### Generated Parameter Preview *(Already exists)*
| Test ID | Element | Purpose | File |
|---------|---------|---------|------|
| `parameter-preview-dialog` | Dialog | Review LLM-generated params | parameter-preview-dialog.tsx |
| `param-confidence-badge-{stepId}` | Badge | Confidence score display | (needs to be added) |
| `button-edit-param-{stepId}-{paramName}` | Button | Edit individual param | (needs to be added) |

---

## Progress Tracking Test IDs

### Execution Timeline *(✅ Complete)*
| Test ID | Element | Purpose | File (Line) |
|---------|---------|---------|-------------|
| `execution-timeline` | Card | Show step-by-step progress | execution-timeline.tsx:140 |
| `timeline-event-{stepId}` | Div | Individual timeline event | execution-timeline.tsx:161 |
| `timeline-event-status-{state}` | Badge | Event status indicator (queued/running/ok/error) | execution-timeline.tsx:196 |
| `timeline-elapsed-{stepId}` | Div | Step elapsed time display | execution-timeline.tsx:211 |
| `timeline-job-{stepId}` | Div | Job ID display | execution-timeline.tsx:217 |

### Progress Indicators
| Test ID Pattern | Element | Purpose | Location |
|-----------------|---------|---------|----------|
| `step-progress-{stepId}` | ProgressBar | Individual step progress | (needs to be added) |
| `step-elapsed-{stepId}` | Span | Step elapsed time | (needs to be added) |
| `step-output-{stepId}` | Div | Step output preview | (needs to be added) |

---

## Dataset Input Test IDs

### Dataset Selection *(Needs to be added)*
| Test ID | Element | Purpose | Location |
|---------|---------|---------|----------|
| `dataset-input-dialog` | Dialog | Choose input datasets | dataset-dialog.tsx |
| `dataset-list` | ScrollArea | Available datasets | dataset-dialog.tsx |
| `dataset-item-{datasetId}` | Div | Individual dataset item | dataset-dialog.tsx |
| `button-select-dataset-{datasetId}` | Button | Select dataset | dataset-dialog.tsx |
| `dataset-preview-{datasetId}` | Div | Dataset metadata preview | dataset-dialog.tsx |

### Dataset Upload
| Test ID | Element | Purpose | Location |
|---------|---------|---------|----------|
| `button-upload-dataset` | Button | Upload new dataset | file-upload.tsx or dataset-dialog.tsx |
| `file-upload-input` | Input | File input element | file-upload.tsx |
| `upload-progress` | ProgressBar | Upload progress | (needs to be added) |

---

## Execution Output Test IDs

### Job Logs *(✅ Complete)*
| Test ID | Element | Purpose | File (Line) |
|---------|---------|---------|-------------|
| `job-log-viewer-{stepId}` | Card | Show real-time logs for step | job-log-viewer.tsx:204 |
| `log-search-{stepId}` | Input | Search log content | job-log-viewer.tsx:235 |
| `log-auto-scroll-{stepId}` | Button | Toggle auto-scroll | job-log-viewer.tsx:243 |
| `button-download-logs-{stepId}` | Button | Download logs | job-log-viewer.tsx:254 |
| `button-clear-logs-{stepId}` | Button | Clear log display | job-log-viewer.tsx:263 |
| `log-content-{stepId}` | Div | Log text container | job-log-viewer.tsx:287 |
| `log-entry-{stepId}-{index}` | Div | Individual log entry | job-log-viewer.tsx:303 |

### Output Files
| Test ID Pattern | Element | Purpose | Location |
|-----------------|---------|---------|----------|
| `output-file-{stepId}-{fileId}` | Div | Output file item | (needs to be added) |
| `button-download-output-{fileId}` | Button | Download output | (needs to be added) |
| `button-preview-output-{fileId}` | Button | Preview output | (needs to be added) |

### Error Display
| Test ID | Element | Purpose | Location |
|---------|---------|---------|----------|
| `execution-error` | Card | Error message display | enhanced-workflow-builder.tsx:724 |
| `error-details` | Pre | Full error stacktrace | (needs to be added) |
| `button-retry-step` | Button | Retry failed step | (needs to be added) |

---

## Test Scenarios

### Scenario 1: Full Workflow E2E Test
```python
# 1. Enter query
page.locator('[data-testid="chat-input"]').fill("Analyze DIA LC-MS data")
page.locator('[data-testid="chat-send-button"]').click()

# 2. Wait for workflow generation
page.wait_for_selector('[data-testid="workflow-generated-message"]')

# 3. Open workflow builder
page.locator('[data-testid="button-view-workflow"]').click()
page.wait_for_selector('[data-testid="workflow-builder"]')

# 4. Verify workflow structure
page.wait_for_selector('[data-testid="workflow-graph"]')
assert page.locator('[data-testid^="graph-node-"]').count() >= 1

# 5. Execute entire workflow
page.locator('[data-testid="button-execute-workflow"]').click()

# 6. Wait for completion
page.wait_for_selector('[data-testid="workflow-status-completed"]', timeout=600000)
```

### Scenario 2: Step-Level Execution Test
```python
# 1. Open workflow builder
page.goto("http://localhost:3000/workflow/123")

# 2. Select first step
page.locator('[data-testid="graph-node-step1"]').click()

# 3. Edit step parameters
page.locator('[data-testid="button-graph-edit-step1"]').click()
page.wait_for_selector('[data-testid="parameter-dialog"]')

# 4. Modify parameter
page.locator('[data-testid="parameter-input-organism"]').fill("mouse")
page.locator('[data-testid="button-save-parameters"]').click()

# 5. Execute just this step
page.locator('[data-testid="button-graph-run-step1"]').click()

# 6. Wait for step completion (not full workflow)
page.wait_for_selector('[data-testid="graph-node-step1"] .text-green-500')  # completed icon

# 7. Check step output
page.locator('[data-testid="output-file-step1-1"]').should_be_visible()
```

### Scenario 3: Dataset Input Test
```python
# 1. Open workflow requiring dataset
page.goto("http://localhost:3000/workflow/456")

# 2. Click on data input step
page.locator('[data-testid="graph-node-input1"]').click()

# 3. Select dataset
page.locator('[data-testid="button-graph-edit-input1"]').click()
page.wait_for_selector('[data-testid="dataset-input-dialog"]')

# 4. Browse available datasets
page.locator('[data-testid="dataset-list"]').scroll_into_view()

# 5. Select specific dataset
page.locator('[data-testid="dataset-item-ensembl-genes-mouse"]').click()
page.locator('[data-testid="button-select-dataset-ensembl-genes-mouse"]').click()

# 6. Execute workflow with dataset
page.locator('[data-testid="button-execute-workflow"]').click()
```

### Scenario 4: Progress Tracking Test
```python
# 1. Start workflow execution
page.locator('[data-testid="button-execute-workflow"]').click()

# 2. Verify status changes
page.wait_for_selector('[data-testid="workflow-status-running"]')

# 3. Check execution timeline appears
page.wait_for_selector('[data-testid="execution-timeline"]')

# 4. Monitor step progress
for step_id in ["step1", "step2", "step3"]:
    # Wait for step to start
    page.wait_for_selector(f'[data-testid="timeline-event-{step_id}"]')

    # Verify step is running
    step_node = page.locator(f'[data-testid="graph-node-{step_id}"]')
    assert "border-blue-500" in step_node.get_attribute("class")

    # Wait for step to complete
    page.wait_for_selector(f'[data-testid="graph-node-{step_id}"] .text-green-500')

# 5. Verify final status
page.wait_for_selector('[data-testid="workflow-status-completed"]')

# 6. Check all outputs
page.locator('[data-testid^="output-file-"]').count() >= 3
```

### Scenario 5: Error Handling Test
```python
# 1. Execute workflow that will fail
page.locator('[data-testid="button-execute-workflow"]').click()

# 2. Wait for error
page.wait_for_selector('[data-testid="execution-error"]', timeout=30000)

# 3. Check error details
error_text = page.locator('[data-testid="execution-error"]').text_content()
assert "Failed" in error_text or "Error" in error_text

# 4. Check which step failed
failed_step = page.locator('[data-testid^="graph-node-"] .text-red-500')
assert failed_step.count() == 1

# 5. Retry failed step
failed_step_id = failed_step.get_attribute("data-testid").replace("graph-node-", "")
page.locator(f'[data-testid="button-graph-restart-{failed_step_id}"]').click()
```

---

## Test IDs Status - Priority List

### High Priority (Required for basic E2E tests)
1. ✅ Individual step nodes - **DONE** (`graph-node-{stepId}`) - workflow-graph.tsx:184
2. ✅ Step-level execution buttons - **DONE** (`button-graph-run-{stepId}`) - workflow-graph.tsx:233
3. ✅ **Parameter dialog** - **DONE** (`parameter-dialog`, `parameter-input-*`, `button-save-parameters`) - parameter-dialog.tsx (Commit: a2f98b4)
4. ✅ **Execution timeline** - **DONE** (`execution-timeline`, `timeline-event-{stepId}`, `timeline-event-status-{state}`) - execution-timeline.tsx (Commit: 53e7ee6)
5. ✅ **Job log viewer** - **DONE** (`job-log-viewer-{stepId}`, `log-content-{stepId}`, `log-entry-{stepId}-{index}`) - job-log-viewer.tsx (Commit: 53e7ee6)

### Medium Priority (Enhanced testing)
6. ⏳ **Dataset input dialog** - `dataset-input-dialog`, `dataset-item-{id}` - (pending)
7. ⏳ **Step progress indicators** - `step-progress-{stepId}` - (pending)
8. ⏳ **Output file display** - `output-file-{stepId}-{fileId}` - (pending)
9. ⏳ **Error details** - `error-details`, `button-retry-step` - (pending)

### Low Priority (Nice to have)
10. ⏳ **Parameter confidence badges** - `param-confidence-badge-{stepId}` - (pending)
11. ✅ **Log auto-scroll** - **DONE** (`log-auto-scroll-{stepId}`) - job-log-viewer.tsx:243
12. ⏳ **Upload progress** - `upload-progress` - (pending)

---

## Next Steps

1. ✅ ~~Add test IDs to ParameterDialog/ParameterEditor component~~ - **DONE** (Commit: a2f98b4)
2. ✅ ~~Add test IDs to ExecutionTimeline component~~ - **DONE** (Commit: 53e7ee6)
3. ✅ ~~Add test IDs to JobLogViewer component~~ - **DONE** (Commit: 53e7ee6)
4. ⏳ Add test IDs to dataset-related dialogs (Medium Priority)
5. ⏳ Create first complete E2E test case with step-level validation
6. ⏳ Implement screenshot + log capture for each step

**All High Priority Test IDs Complete!** The frontend now has comprehensive test IDs for:
- Individual workflow step execution
- Parameter editing
- Progress tracking (timeline + logs)
- Step-level controls (run, pause, restart, edit, delete)

Ready to implement E2E test cases with Playwright.

---

## Benefits of Granular Test IDs

### Step-Level Testing
- Test individual step execution without running entire workflow
- Validate step outputs independently
- Test parameter editing for specific steps
- Verify step status transitions (pending → running → completed)

### Progress Tracking
- Monitor workflow execution in real-time
- Capture intermediate outputs
- Verify execution timeline accuracy
- Test pause/resume functionality

### Dataset Workflows
- Test dataset selection and validation
- Verify dataset upload process
- Test workflows with different input datasets
- Validate dataset compatibility with tools

### Output Validation
- Access step-specific outputs
- Verify output file generation
- Test output download functionality
- Validate intermediate results

---

**Status**: All High Priority test IDs complete! Ready for E2E test implementation.
**Branch**: `frontend_stronger`
**Commits**:
- `14593ba` - Initial test IDs (chat, workflow controls)
- `a2f98b4` - Parameter dialog test IDs
- `53e7ee6` - Progress tracking test IDs (timeline + logs)

**Summary**:
- ✅ 5/5 High Priority test IDs complete
- ⏳ 4/4 Medium Priority test IDs pending
- ✅ 1/3 Low Priority test IDs complete

**Test Coverage**:
- Individual step operations (run, pause, restart, edit, delete)
- Parameter editing with 3-tier UI (essential, common, advanced)
- Real-time progress tracking via ExecutionTimeline
- Real-time log monitoring via JobLogViewer
- Step-level state transitions and elapsed time tracking
