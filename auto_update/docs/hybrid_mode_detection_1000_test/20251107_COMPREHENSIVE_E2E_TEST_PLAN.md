# Comprehensive E2E Test Plan for Biomate

**Date:** 2025-11-07
**Purpose:** End-to-End Testing of All Key Features
**Status:** Planning Complete, Implementation Pending
**Branch:** `new_framework_platform`

---

## Overview

This is the first comprehensive end-to-end test suite for the `new_framework_platform` branch, covering all major system features including:
- Task Management (Pause/Resume, Milestones, Priority)
- Workflow Execution & Monitoring
- Galaxy Assistant (AI-powered chat)
- Data Management
- Security Features
- UI Components

---

## Test Categories

### 1. Task Management Features (NEW - Option A)

#### 1.1 Pause/Resume Job Tests
**Files:** `test_pause_resume_jobs.py`

**Test Cases:**
1. **test_pause_running_job**
   - Submit workflow
   - Wait for job to start running
   - Call pause API
   - Verify job state = 'paused'

2. **test_pause_queued_job**
   - Submit workflow
   - Immediately pause before it starts
   - Verify job state = 'paused'

3. **test_resume_paused_job**
   - Pause a running job
   - Call resume API
   - Verify job state returns to 'queued' or 'running'

4. **test_pause_resume_cycle**
   - Pause → Resume → Pause → Resume
   - Verify workflow eventually completes

5. **test_pause_invalid_state** (Error Case)
   - Try to pause completed job
   - Expect 400 error

6. **test_pause_nonexistent_job** (Error Case)
   - Try to pause invalid job ID
   - Expect 404 error

**API Endpoints Tested:**
- `PUT /api/galaxy/jobs/:jobId/pause`
- `PUT /api/galaxy/jobs/:jobId/resume`

---

#### 1.2 Progress Milestone Tests
**Files:** `test_progress_milestones.py`

**Test Cases:**
1. **test_milestone_25_percent**
   - Submit 8-step workflow
   - Monitor SSE stream
   - Verify 25% milestone emitted after 2 steps

2. **test_milestone_50_percent**
   - Verify 50% milestone after 4 steps

3. **test_milestone_75_percent**
   - Verify 75% milestone after 6 steps

4. **test_milestone_100_percent**
   - Verify 100% milestone at completion

5. **test_milestone_eta_calculation**
   - Verify ETA is calculated and decreases over time
   - Verify format: "~Xm Ys remaining"

6. **test_milestone_uniqueness**
   - Verify each milestone only reported once
   - Even if polling happens multiple times at same percentage

7. **test_milestone_event_format**
   - Verify SSE event structure:
     ```json
     {
       "type": "progress_milestone",
       "data": {
         "progress": 0.50,
         "completedSteps": 4,
         "totalSteps": 8,
         "eta": "~2m 30s remaining",
         "message": "...",
         "milestone": 50
       }
     }
     ```

**SSE Events Tested:**
- `progress_milestone` event type

---

#### 1.3 Job Priority Tests
**Files:** `test_job_priorities.py`

**Test Cases:**
1. **test_submit_high_priority_workflow**
   - Submit workflow with `__priority: "high"`
   - Verify parameter passed to Galaxy

2. **test_submit_low_priority_workflow**
   - Submit workflow with `__priority: "low"`
   - Verify parameter passed to Galaxy

3. **test_priority_queue_ordering** (If resources limited)
   - Submit low priority workflow
   - Submit high priority workflow after
   - Verify high priority executes first (if queued)

4. **test_default_priority**
   - Submit workflow without priority parameter
   - Verify defaults to normal priority

5. **test_invalid_priority** (Error Case)
   - Try to submit with invalid priority value
   - Verify graceful handling

**API Parameters Tested:**
- `parameters.__priority` in workflow invocation

---

### 2. Workflow Execution & Monitoring

#### 2.1 Workflow Lifecycle Tests
**Files:** `test_workflow_lifecycle.py`

**Test Cases:**
1. **test_create_workflow**
   - POST new workflow definition
   - Verify workflow created in Galaxy

2. **test_get_workflow**
   - Retrieve workflow by ID
   - Verify structure matches

3. **test_invoke_workflow**
   - Submit workflow for execution
   - Verify invocation ID returned

4. **test_monitor_invocation_status**
   - Poll invocation endpoint
   - Verify state transitions: new → queued → running → ok

5. **test_cancel_invocation**
   - Start workflow
   - Cancel mid-execution
   - Verify state = 'cancelled'

6. **test_workflow_with_inputs**
   - Invoke workflow with dataset inputs
   - Verify inputs mapped correctly

7. **test_workflow_with_parameters**
   - Invoke workflow with step parameters
   - Verify parameters applied

---

#### 2.2 Real-Time Monitoring (SSE) Tests
**Files:** `test_sse_monitoring.py`

**Test Cases:**
1. **test_sse_connection**
   - Connect to SSE endpoint
   - Verify connection established
   - Verify initial state sent

2. **test_sse_workflow_state_events**
   - Monitor workflow execution via SSE
   - Verify 'workflow_state' events received

3. **test_sse_step_state_events**
   - Verify 'step_state' events for each workflow step

4. **test_sse_job_log_events**
   - Verify 'job_log' events with stdout/stderr

5. **test_sse_error_events**
   - Trigger workflow error
   - Verify 'error' event received

6. **test_sse_milestone_events**
   - Verify 'progress_milestone' events

7. **test_sse_multiple_clients**
   - Connect multiple clients to same invocation
   - Verify all receive events

8. **test_sse_client_disconnect**
   - Connect client
   - Disconnect
   - Verify polling stops when no clients

**SSE Endpoint Tested:**
- `GET /api/galaxy/workflows/sse/:invocationId`

---

### 3. Galaxy Assistant (AI Chat Interface)

#### 3.1 Mode Detection Tests
**Files:** `test_mode_detection.py` (Already created)

**Test Cases:**
1. **test_beginner_mode_detection**
   - Submit beginner-level query
   - Verify mode = 'Beginner'

2. **test_intermediate_mode_detection**
   - Submit intermediate-level query
   - Verify mode = 'Intermediate'

3. **test_expert_mode_detection**
   - Submit expert-level query
   - Verify mode = 'Expert'

4. **test_mode_detection_accuracy**
   - Run 1000 test scenarios
   - Verify >90% accuracy

**API Endpoint Tested:**
- Chat message processing with mode detection

---

#### 3.2 Chat Workflow Generation Tests
**Files:** `test_chat_workflow_generation.py`

**Test Cases:**
1. **test_generate_workflow_from_chat**
   - User: "Align FASTQ files to reference genome"
   - Verify workflow JSON generated
   - Verify contains alignment tool

2. **test_workflow_parameter_extraction**
   - User: "Run FastQC with quality threshold 30"
   - Verify parameter extracted: quality_threshold = 30

3. **test_dataset_selection_from_chat**
   - User: "Analyze my_data.fastq"
   - Verify correct dataset selected from history

4. **test_multi_step_workflow_generation**
   - User: "Quality control, then align, then call variants"
   - Verify 3-step workflow generated

5. **test_workflow_validation**
   - Generate workflow from chat
   - Verify workflow is valid Galaxy format
   - Verify can be executed

---

#### 3.3 Scientific Context Tests
**Files:** `test_scientific_context.py`

**Test Cases:**
1. **test_extract_domain_from_query**
   - User: "Analyze proteomics MS data"
   - Verify domain = 'proteomics'

2. **test_extract_technique_from_query**
   - User: "Run DIA-NN for mass spec"
   - Verify technique = 'DIA-MS'

3. **test_extract_organism_from_query**
   - User: "Align human genome reads"
   - Verify organism = 'human'

4. **test_context_aware_tool_selection**
   - User: "Analyze RNA-seq data"
   - Verify RNA-seq tools suggested (STAR, HISAT2)

---

### 4. Data Management

#### 4.1 Dataset Tests
**Files:** `test_dataset_management.py`

**Test Cases:**
1. **test_upload_dataset**
   - Upload file via API
   - Verify dataset created in history

2. **test_list_datasets**
   - GET datasets from history
   - Verify list contains uploaded files

3. **test_get_dataset_details**
   - GET dataset by ID
   - Verify metadata correct

4. **test_delete_dataset**
   - Delete dataset
   - Verify removed from history

5. **test_dataset_state_transitions**
   - Upload large file
   - Monitor state: queued → running → ok

---

#### 4.2 History Tests
**Files:** `test_history_management.py`

**Test Cases:**
1. **test_create_history**
   - POST new history
   - Verify history created

2. **test_list_histories**
   - GET user histories
   - Verify list contains created history

3. **test_switch_history**
   - Switch to different history
   - Verify current history changed

4. **test_delete_history**
   - Delete history
   - Verify deleted (or marked deleted)

---

### 5. Security Features

#### 5.1 Tool Installation Security Tests
**Files:** `test_tool_security.py`

**Test Cases:**
1. **test_block_malicious_tool_install**
   - Attempt to install tool with suspicious code
   - Verify installation blocked

2. **test_validate_tool_source**
   - Install tool from untrusted source
   - Verify warning or block

3. **test_tool_permissions**
   - Verify tools run with limited permissions
   - Cannot access outside sandbox

4. **test_audit_log_tool_install**
   - Install tool
   - Verify logged in audit trail

---

#### 5.2 API Security Tests
**Files:** `test_api_security.py`

**Test Cases:**
1. **test_authentication_required**
   - Call protected endpoint without auth
   - Expect 401 Unauthorized

2. **test_invalid_token**
   - Call endpoint with invalid token
   - Expect 403 Forbidden

3. **test_sql_injection_prevention**
   - Send SQL injection payload
   - Verify sanitized/rejected

4. **test_xss_prevention**
   - Send XSS payload in chat
   - Verify sanitized

5. **test_rate_limiting** (If implemented)
   - Send many requests rapidly
   - Verify rate limited

---

### 6. UI Component Tests (Playwright)

#### 6.1 Enhanced Workflow Builder Tests
**Files:** `test_workflow_builder_ui.py`

**Test Cases:**
1. **test_render_workflow_builder**
   - Load workflow builder page
   - Verify UI elements present

2. **test_add_step_to_workflow**
   - Click "Add Step"
   - Select tool
   - Verify step added to canvas

3. **test_connect_workflow_steps**
   - Drag connection between steps
   - Verify connection created

4. **test_execute_workflow_from_ui**
   - Click "Run Workflow"
   - Verify execution starts

5. **test_pause_button_visibility**
   - Start workflow
   - Verify "Pause" button appears for running steps

6. **test_pause_workflow_from_ui**
   - Click "Pause" button
   - Verify job paused

7. **test_resume_workflow_from_ui**
   - Pause workflow
   - Click "Resume" button
   - Verify job resumed

---

#### 6.2 Execution Timeline Tests
**Files:** `test_execution_timeline_ui.py`

**Test Cases:**
1. **test_timeline_renders**
   - Start workflow
   - Verify timeline component visible

2. **test_timeline_shows_steps**
   - Verify all workflow steps shown

3. **test_timeline_state_icons**
   - Verify correct icons for each state:
     - Circle for 'new'
     - Clock for 'queued'
     - Loader for 'running'
     - CheckCircle for 'ok'
     - AlertCircle for 'error'

4. **test_timeline_elapsed_time**
   - Verify elapsed time shown for running steps

5. **test_timeline_milestone_display** (NEW)
   - Run workflow with 8+ steps
   - Verify milestone notifications appear in timeline

---

#### 6.3 Chat Interface Tests
**Files:** `test_chat_interface_ui.py`

**Test Cases:**
1. **test_send_chat_message**
   - Type message
   - Click send
   - Verify message appears in chat

2. **test_receive_assistant_response**
   - Send message
   - Verify assistant response received

3. **test_mode_badge_display**
   - Send expert query
   - Verify "Expert" badge shown

4. **test_workflow_artifact_render**
   - Generate workflow from chat
   - Verify workflow card rendered

5. **test_click_workflow_artifact**
   - Click workflow card
   - Verify opens in workflow builder

---

### 7. Integration Tests

#### 7.1 End-to-End User Workflows
**Files:** `test_e2e_user_workflows.py`

**Test Cases:**
1. **test_complete_analysis_workflow**
   - Upload dataset
   - Chat: "Run FastQC on this file"
   - Execute generated workflow
   - Monitor progress milestones
   - Verify completion

2. **test_task_interruption_scenario**
   - Start long workflow (low priority)
   - Pause it
   - Start urgent workflow (high priority)
   - Wait for urgent to complete
   - Resume original workflow
   - Verify both complete successfully

3. **test_multi_dataset_pipeline**
   - Upload 3 datasets
   - Chat: "Run quality control on all files, then align to hg38"
   - Execute workflow
   - Monitor via SSE
   - Verify all steps complete

---

## Test Infrastructure

### Test Utilities Created

1. **mode_validator.py** (Already exists)
   - Mode detection validation
   - Accuracy calculation

2. **workflow_executor.py** (To create)
   - Helper for workflow submission
   - Polling utilities
   - State verification

3. **sse_client.py** (To create)
   - SSE connection manager
   - Event listener
   - Event filtering

4. **dataset_helper.py** (To create)
   - Dataset upload
   - History management
   - Cleanup utilities

5. **ui_helpers.py** (To create)
   - Playwright page utilities
   - Element locators
   - Wait conditions

---

## Test Data

### Required Test Datasets

1. **Small FASTQ file** (1MB)
   - For quick execution tests
   - Verify basic workflow flow

2. **Medium FASTQ file** (50MB)
   - For progress milestone tests
   - Verify ETA calculation

3. **Test genome reference** (minimal)
   - For alignment workflows
   - Verify multi-step workflows

4. **Proteomics MS data** (sample)
   - For domain-specific tests
   - Verify scientific context extraction

---

## Test Execution Plan

### Phase 1: Core Functionality (Priority 1)
**Estimated Time:** 4 hours

1. Workflow Lifecycle Tests
2. SSE Monitoring Tests
3. Dataset Management Tests

### Phase 2: Task Management (Priority 1)
**Estimated Time:** 3 hours

1. Pause/Resume Tests
2. Progress Milestone Tests
3. Job Priority Tests

### Phase 3: AI Features (Priority 2)
**Estimated Time:** 4 hours

1. Mode Detection Tests (use existing)
2. Chat Workflow Generation Tests
3. Scientific Context Tests

### Phase 4: Security (Priority 2)
**Estimated Time:** 2 hours

1. Tool Security Tests
2. API Security Tests

### Phase 5: UI Components (Priority 3)
**Estimated Time:** 4 hours

1. Workflow Builder Tests
2. Execution Timeline Tests
3. Chat Interface Tests

### Phase 6: Integration (Priority 1)
**Estimated Time:** 3 hours

1. End-to-End User Workflows
2. Task Interruption Scenarios

**Total Estimated Time:** 20 hours

---

## Success Criteria

### Coverage Goals
- ✅ API Endpoints: 100% of critical paths
- ✅ SSE Events: All event types tested
- ✅ Task Management: All 3 features fully tested
- ✅ Workflow Execution: All states covered
- ✅ UI Components: All interactive elements tested

### Quality Gates
- ✅ All tests pass on clean environment
- ✅ No flaky tests (>95% pass rate)
- ✅ Test execution time <30 minutes total
- ✅ Code coverage >80% for tested modules

### Documentation
- ✅ All tests have docstrings
- ✅ Test data documented
- ✅ Known issues documented
- ✅ CI/CD integration guide

---

## Test Report Format

### Automated Report Generation
Generate JSON report with:
```json
{
  "timestamp": "2025-11-07T20:00:00Z",
  "branch": "new_framework_platform",
  "total_tests": 150,
  "passed": 147,
  "failed": 3,
  "skipped": 0,
  "duration_seconds": 1245,
  "categories": {
    "task_management": {"passed": 18, "failed": 0},
    "workflow_execution": {"passed": 23, "failed": 1},
    "ai_features": {"passed": 35, "failed": 2},
    "security": {"passed": 12, "failed": 0},
    "ui_components": {"passed": 28, "failed": 0},
    "integration": {"passed": 31, "failed": 0}
  },
  "failures": [
    {
      "test": "test_workflow_with_invalid_input",
      "category": "workflow_execution",
      "error": "Expected 400, got 500",
      "traceback": "..."
    }
  ]
}
```

---

## Next Steps

1. ✅ Create test infrastructure utilities
2. ✅ Implement Phase 1 tests (Core Functionality)
3. ✅ Implement Phase 2 tests (Task Management)
4. ✅ Implement Phase 3 tests (AI Features)
5. ✅ Implement Phase 4 tests (Security)
6. ✅ Implement Phase 5 tests (UI Components)
7. ✅ Implement Phase 6 tests (Integration)
8. ✅ Generate comprehensive test report
9. ✅ Document known issues
10. ✅ Setup CI/CD integration

---

**Document Version:** 1.0
**Last Updated:** 2025-11-07 20:00
**Status:** Test plan complete, ready for implementation
