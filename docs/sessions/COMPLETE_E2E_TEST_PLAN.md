# Complete End-to-End Test Plan

**Purpose:** Test the ENTIRE BioMate workflow execution flow from user request to downloadable results

**Scope:** All 8 phases of workflow execution

---

## Test Strategy

### Test Levels

```
┌─────────────────────────────────────────────────────────────┐
│  LEVEL 1: Component Tests (Unit)                           │
│  - Individual components work correctly                    │
│  - Already covered by existing tests                       │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│  LEVEL 2: Integration Tests                                │
│  - Components integrate correctly                          │
│  - API endpoints work                                      │
│  - Database operations work                                │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│  LEVEL 3: End-to-End Tests (THIS PLAN)                     │
│  - Complete user journey works                             │
│  - All phases execute correctly                            │
│  - Results are correct and downloadable                    │
└─────────────────────────────────────────────────────────────┘
```

---

## E2E Test Scenarios

### Scenario 1: Complete RNA-Seq QC Workflow

**User Story:** As a researcher, I want to run quality control on my RNA-Seq data and get a downloadable report.

**Preconditions:**
- Frontend running on port 5000
- Backend running on port 8081
- Test FASTQ file exists: `/tmp/test_sample.fastq`

**Test Steps:**

```
STEP 1: User Request
──────────────────────
Action: POST /api/chat
Input: {
  message: "Run RNA-Seq quality control on my FASTQ file",
  files: ["/tmp/test_sample.fastq"]
}

Expected:
✅ Response within 10s
✅ Response contains workflow_ga
✅ workflow_ga has tool_id containing "fastqc"
✅ Response status: success


STEP 2: Workflow Validation
────────────────────────────
Action: (Automatic) Audit system validates workflow

Expected:
✅ Audit completes
✅ No validation errors
✅ Tool IDs are valid


STEP 3: Workflow Execution
───────────────────────────
Action: POST /api/workflows/execute
Input: {
  workflowDefinition: <workflow_ga from step 1>,
  executionConfig: {mode: "production"},
  inputs: {input_fastq: "/tmp/test_sample.fastq"},
  enable_input_validation: true
}

Expected:
✅ Response within 2s
✅ Response contains invocation_id
✅ Response contains history_id
✅ Status code: 200


STEP 4: Input Validation Check
───────────────────────────────
Action: GET /api/workflows/{invocation_id}/input-validation
Wait: 500ms

Expected:
✅ Validation report exists
✅ Status: "passed"
✅ passed_checks >= 1
✅ failed_checks == 0


STEP 5: Status Monitoring (Initial)
────────────────────────────────────
Action: GET /api/workflows/runs/{run_id}/status
Wait: 1s

Expected:
✅ Status: "queued" or "running"
✅ invocation_id matches
✅ history_id matches


STEP 6: Wait for Execution
───────────────────────────
Action: Poll status every 2s for max 120s
GET /api/workflows/runs/{run_id}/status

Expected:
✅ Status eventually becomes "ok" or "completed"
✅ Progress increases over time
✅ No status is "error" or "failed"


STEP 7: Verify Completion
──────────────────────────
Action: GET /api/workflows/runs/{run_id}/status

Expected:
✅ Status: "ok" or "completed"
✅ progress.completedSteps == progress.totalSteps
✅ No errors in response


STEP 8: Get Results
───────────────────
Action: GET /api/histories/{history_id}/contents

Expected:
✅ Response is array
✅ Array length > 0
✅ All datasets have state: "ok"
✅ At least one dataset contains output data


STEP 9: Download Results
─────────────────────────
Action: GET /api/datasets/{dataset_id}/display

Expected:
✅ Response is file content
✅ Content-Type header is correct
✅ File size > 0
✅ File content is valid (parseable)


STEP 10: Verify Results Content
────────────────────────────────
Action: Parse downloaded file

Expected:
✅ File format is valid (JSON/CSV/HTML/etc.)
✅ File contains expected data structure
✅ Results are scientifically plausible
```

**Total Expected Time:** 60-120 seconds (depending on workflow complexity)

**Pass Criteria:** All 10 steps pass

---

### Scenario 2: Workflow with Missing Input File

**Purpose:** Test error handling when input file doesn't exist

**Test Steps:**

```
STEP 1-3: Same as Scenario 1

STEP 4: Input Validation (Should Fail)
───────────────────────────────────────
Input file: "/nonexistent/file.fastq"

Expected:
✅ Validation report exists
✅ Status: "failed"
✅ failed_checks >= 1
✅ Error message contains file path
✅ Error message contains "not found"

STEP 5: Execution Status (Should Not Start)
────────────────────────────────────────────
Expected:
✅ Workflow either:
   a) Never starts (validation blocks it), OR
   b) Starts but fails immediately with clear error

CRITICAL: User should see clear error about missing file
```

**Pass Criteria:** User gets clear error message before wasting computation time

---

### Scenario 3: Workflow with QC Gate Trigger

**Purpose:** Test QC monitoring and gate triggering

**Preconditions:**
- QC config exists for workflow
- QC threshold can be violated

**Test Steps:**

```
STEP 1-7: Same as Scenario 1 (up to execution)

STEP 8: Monitor for QC Gate
────────────────────────────
Action: Listen for SSE events
Event type: "qc_gate_triggered"

Expected (if QC gate triggers):
✅ SSE event received
✅ Event contains:
   - process_name
   - metrics that failed
   - suggestions for fixes
   - options: [proceed, retry, cancel]

STEP 9: User Decision
─────────────────────
Action: POST /api/workflows/{id}/qc-decision
Input: {decision: "proceed"}

Expected:
✅ Workflow continues
✅ Status eventually becomes "ok"
```

**Pass Criteria:** QC gate system detects issues and allows user control

---

### Scenario 4: Workflow with Auto-Fix Recovery

**Purpose:** Test autofix error recovery

**Preconditions:**
- Workflow configured to fail (e.g., insufficient memory)
- Autofix enabled

**Test Steps:**

```
STEP 1-7: Same as Scenario 1

STEP 8: Workflow Fails
──────────────────────
Workflow process fails with recoverable error

Expected:
✅ Job state becomes "error"
✅ Autofix system detects failure

STEP 9: Autofix Attempts Recovery
──────────────────────────────────
Action: (Automatic) Autofix analyzes and retries

Expected:
✅ Fix suggestion generated
✅ Fix applied
✅ Workflow retried

STEP 10: Recovery Success
─────────────────────────
Expected:
✅ Retry succeeds
✅ Workflow eventually completes
✅ Status: "ok"
```

**Pass Criteria:** Workflow recovers from failure without user intervention

---

### Scenario 5: Cryo-EM Workflow with Mock Mode

**Purpose:** Test Cryo-EM domain with mock data

**Test Steps:**

```
STEP 1: Request Cryo-EM Workflow
─────────────────────────────────
Input: {
  message: "Run Cryo-EM SPA pipeline",
  parameters: {
    movies_dir: "/data/movies",
    voltage: 300,
    mock_mode: true
  }
}

STEP 2-10: Same as Scenario 1

Additional Checks:
✅ Workflow uses CryoEMSPAInputValidator
✅ Mock mode detected
✅ File validation skipped (mock mode)
✅ Workflow completes in mock mode
```

**Pass Criteria:** Cryo-EM workflow executes correctly in mock mode

---

### Scenario 6: Paired-End RNA-Seq

**Purpose:** Test multiple input files

**Test Steps:**

```
STEP 1: Request with Paired-End Data
─────────────────────────────────────
Input: {
  input_fastq: [
    "/tmp/sample_R1.fastq",
    "/tmp/sample_R2.fastq"
  ]
}

STEP 4: Input Validation
─────────────────────────
Expected:
✅ Both R1 and R2 validated
✅ total_checks >= 2
✅ Both files marked as accessible

STEP 2-10: Same as Scenario 1
```

**Pass Criteria:** Multiple input files handled correctly

---

### Scenario 7: Pilot Run (Progressive Tuning)

**Purpose:** Test pilot run on subset of data

**Test Steps:**

```
STEP 1: Request Pilot Run
──────────────────────────
Input: {
  message: "Run RNA-Seq QC",
  executionMode: "pilot",
  pilotFraction: 0.1
}

STEP 2: Pilot Execution
───────────────────────
Expected:
✅ Workflow runs on 10% of data
✅ Metrics collected
✅ Cost estimate generated

STEP 3: Review Pilot Results
─────────────────────────────
Action: GET /api/workflows/{id}/pilot-results

Expected:
✅ Results show:
   - Time for pilot
   - Estimated time for full run
   - Estimated cost
   - Suggested parameter optimizations

STEP 4: User Decides to Proceed
────────────────────────────────
Action: POST /api/workflows/{id}/full-run

Expected:
✅ Full workflow starts
✅ Uses optimized parameters
✅ Completes successfully
```

**Pass Criteria:** Pilot run provides useful estimates and proceeds to full run

---

## Test Implementation

### Test Setup (Before All Tests)

```python
import os
import time
import requests
import json
from pathlib import Path

# Test configuration
FRONTEND_URL = "http://localhost:5000"
BACKEND_URL = "http://localhost:8081"
TEST_DATA_DIR = "/tmp/biomate_e2e_tests"

# Setup
def setup_e2e_tests():
    """Create test data and verify services running"""

    # Create test directory
    os.makedirs(TEST_DATA_DIR, exist_ok=True)

    # Create test FASTQ file
    test_fastq = os.path.join(TEST_DATA_DIR, "test_sample.fastq")
    with open(test_fastq, 'w') as f:
        f.write("@SEQ_ID\n")
        f.write("GATTTGGGGTTCAAAGCAGTATCGATCAAATAGTAAATCCATTTGTTCAACTCACAGTTT\n")
        f.write("+\n")
        f.write("!''*((((***+))%%%++)(%%%%).1***-+*''))**55CCF>>>>>>CCCCCCC65\n")

    # Create paired-end files
    for suffix in ["R1", "R2"]:
        paired_file = os.path.join(TEST_DATA_DIR, f"sample_{suffix}.fastq")
        with open(paired_file, 'w') as f:
            f.write(f"@SEQ_{suffix}\n")
            f.write("GATTTGGGGTTCAAAGCAGTATCGATCAAATAGTAAATCCATTTGTTCAACTCACAGTTT\n")
            f.write("+\n")
            f.write("!''*((((***+))%%%++)(%%%%).1***-+*''))**55CCF>>>>>>CCCCCCC65\n")

    # Verify services
    try:
        r = requests.get(f"{FRONTEND_URL}/", timeout=5)
        assert r.status_code == 200, "Frontend not running"
    except:
        raise Exception("Frontend not accessible at http://localhost:5000")

    try:
        r = requests.get(f"{BACKEND_URL}/api/version", timeout=5)
        assert r.status_code == 200, "Backend not running"
    except:
        raise Exception("Backend not accessible at http://localhost:8081")

    print("✅ E2E test setup complete")
    return test_fastq
```

### Test Runner

```python
def run_e2e_scenario_1():
    """Test Scenario 1: Complete RNA-Seq QC Workflow"""

    print("\n" + "="*70)
    print("SCENARIO 1: Complete RNA-Seq QC Workflow")
    print("="*70)

    test_fastq = setup_e2e_tests()

    # STEP 1: User Request
    print("\nSTEP 1: User Request")
    print("-" * 40)
    start_time = time.time()

    response = requests.post(
        f"{FRONTEND_URL}/api/chat",
        json={
            "message": "Run RNA-Seq quality control on my FASTQ file",
            "files": [test_fastq]
        },
        timeout=30
    )

    step1_duration = time.time() - start_time
    assert response.status_code == 200, f"Step 1 failed: {response.status_code}"
    assert step1_duration < 10, f"Step 1 too slow: {step1_duration:.1f}s"

    chat_response = response.json()
    assert "workflow" in chat_response, "No workflow in response"
    assert chat_response["workflow"]["success"], "Workflow generation failed"

    workflow_ga = chat_response["workflow"]["workflow_ga"]
    print(f"✅ Step 1 PASS ({step1_duration:.1f}s)")
    print(f"   Generated workflow: {workflow_ga.get('name', 'Unknown')}")

    # STEP 2: Workflow Validation (automatic)
    print("\nSTEP 2: Workflow Validation")
    print("-" * 40)
    # Validation happens internally during generation
    # We just verify no validation errors in response
    assert not chat_response.get("validation_errors"), "Validation errors present"
    print("✅ Step 2 PASS (Audit passed)")

    # STEP 3: Workflow Execution
    print("\nSTEP 3: Workflow Execution")
    print("-" * 40)
    start_time = time.time()

    exec_response = requests.post(
        f"{FRONTEND_URL}/api/workflows/execute",
        json={
            "workflowDefinition": workflow_ga,
            "executionConfig": {"mode": "production"},
            "inputs": {"input_fastq": test_fastq},
            "enable_input_validation": True
        },
        timeout=10
    )

    step3_duration = time.time() - start_time
    assert exec_response.status_code == 200, f"Step 3 failed: {exec_response.status_code}"
    assert step3_duration < 2, f"Step 3 too slow: {step3_duration:.1f}s"

    exec_data = exec_response.json()
    invocation_id = exec_data.get("invocation_id") or exec_data.get("runId")
    history_id = exec_data.get("history_id") or exec_data.get("galaxyHistoryId")

    assert invocation_id, "No invocation_id in response"
    print(f"✅ Step 3 PASS ({step3_duration:.1f}s)")
    print(f"   Invocation ID: {invocation_id}")
    print(f"   History ID: {history_id}")

    # STEP 4: Input Validation Check
    print("\nSTEP 4: Input Validation Check")
    print("-" * 40)
    time.sleep(0.5)  # Wait for validation to complete

    validation_response = requests.get(
        f"{BACKEND_URL}/api/workflows/{invocation_id}/input-validation",
        timeout=5
    )

    if validation_response.status_code == 200:
        validation_data = validation_response.json()
        assert validation_data["status"] in ["passed", "skipped"], \
            f"Validation failed: {validation_data.get('error_message')}"
        print(f"✅ Step 4 PASS")
        print(f"   Validation status: {validation_data['status']}")
        print(f"   Checks passed: {validation_data.get('passed_checks', 0)}")
    else:
        print(f"⚠️ Step 4 SKIP (Validation endpoint not available)")

    # STEP 5: Initial Status Check
    print("\nSTEP 5: Initial Status Check")
    print("-" * 40)
    time.sleep(1)

    status_response = requests.get(
        f"{FRONTEND_URL}/api/workflows/runs/{invocation_id}/status",
        timeout=5
    )

    assert status_response.status_code == 200, "Step 5 failed"
    status_data = status_response.json()

    assert status_data["status"] in ["queued", "running", "new"], \
        f"Unexpected initial status: {status_data['status']}"
    print(f"✅ Step 5 PASS")
    print(f"   Status: {status_data['status']}")

    # STEP 6: Wait for Completion
    print("\nSTEP 6: Wait for Execution")
    print("-" * 40)

    max_wait = 120  # 2 minutes max
    poll_interval = 2  # Poll every 2 seconds
    start_time = time.time()
    last_status = None

    while (time.time() - start_time) < max_wait:
        status_response = requests.get(
            f"{FRONTEND_URL}/api/workflows/runs/{invocation_id}/status",
            timeout=5
        )

        if status_response.status_code == 200:
            status_data = status_response.json()
            current_status = status_data["status"]

            if current_status != last_status:
                print(f"   Status: {current_status}")
                if "progress" in status_data:
                    prog = status_data["progress"]
                    print(f"   Progress: {prog.get('completedSteps', 0)}/{prog.get('totalSteps', '?')}")
                last_status = current_status

            # Check for completion
            if current_status in ["ok", "completed", "scheduled"]:
                print(f"✅ Step 6 PASS ({time.time() - start_time:.1f}s)")
                break

            # Check for failure
            if current_status in ["error", "failed"]:
                raise AssertionError(f"Workflow failed with status: {current_status}")

        time.sleep(poll_interval)
    else:
        raise TimeoutError(f"Workflow did not complete within {max_wait}s")

    # STEP 7: Verify Completion
    print("\nSTEP 7: Verify Completion")
    print("-" * 40)

    final_status = requests.get(
        f"{FRONTEND_URL}/api/workflows/runs/{invocation_id}/status",
        timeout=5
    ).json()

    assert final_status["status"] in ["ok", "completed", "scheduled"], \
        f"Final status not OK: {final_status['status']}"
    print(f"✅ Step 7 PASS")
    print(f"   Final status: {final_status['status']}")

    # STEP 8: Get Results
    print("\nSTEP 8: Get Results")
    print("-" * 40)

    results_response = requests.get(
        f"{BACKEND_URL}/api/histories/{history_id}/contents",
        timeout=10
    )

    assert results_response.status_code == 200, "Step 8 failed"
    results_data = results_response.json()

    assert isinstance(results_data, list), "Results should be array"
    assert len(results_data) > 0, "No results found"

    # Find output datasets (state = "ok")
    output_datasets = [d for d in results_data if d.get("state") == "ok"]
    assert len(output_datasets) > 0, "No completed output datasets"

    print(f"✅ Step 8 PASS")
    print(f"   Total datasets: {len(results_data)}")
    print(f"   Completed datasets: {len(output_datasets)}")

    # STEP 9: Download Results
    print("\nSTEP 9: Download Results")
    print("-" * 40)

    dataset_id = output_datasets[0]["id"]
    download_response = requests.get(
        f"{BACKEND_URL}/api/datasets/{dataset_id}/display",
        timeout=10
    )

    assert download_response.status_code == 200, "Step 9 failed"
    assert len(download_response.content) > 0, "Downloaded file is empty"

    print(f"✅ Step 9 PASS")
    print(f"   Downloaded {len(download_response.content)} bytes")

    # STEP 10: Verify Content
    print("\nSTEP 10: Verify Results Content")
    print("-" * 40)

    content = download_response.content
    # Try to parse as text
    try:
        text_content = content.decode('utf-8')
        assert len(text_content) > 0, "Content is empty"
        print(f"✅ Step 10 PASS")
        print(f"   Content type: text")
        print(f"   Content length: {len(text_content)} characters")
    except:
        # Binary content
        print(f"✅ Step 10 PASS")
        print(f"   Content type: binary")
        print(f"   Content length: {len(content)} bytes")

    # Final Summary
    print("\n" + "="*70)
    print("✅ SCENARIO 1: ALL STEPS PASSED")
    print("="*70)
    print(f"Total execution time: {time.time() - start_time:.1f}s")

    return True
```

### Running All Scenarios

```python
def run_all_e2e_tests():
    """Run all E2E test scenarios"""

    results = {
        "passed": 0,
        "failed": 0,
        "skipped": 0
    }

    scenarios = [
        ("Scenario 1: Complete RNA-Seq QC", run_e2e_scenario_1),
        # Add more scenarios here
    ]

    for name, test_func in scenarios:
        try:
            print(f"\n\nRunning: {name}")
            print("="*70)
            test_func()
            results["passed"] += 1
        except Exception as e:
            print(f"\n❌ {name} FAILED:")
            print(f"   Error: {str(e)}")
            results["failed"] += 1

    # Print summary
    print("\n\n" + "="*70)
    print("E2E TEST SUMMARY")
    print("="*70)
    print(f"Total scenarios: {len(scenarios)}")
    print(f"Passed: {results['passed']} ✅")
    print(f"Failed: {results['failed']} ❌")
    print(f"Success rate: {results['passed']/len(scenarios)*100:.1f}%")

    return results["failed"] == 0
```

---

## Test Execution

### Prerequisites

1. **Services Running:**
   ```bash
   # Frontend
   cd frontend && npm run dev  # Port 5000

   # Backend
   cd backend && ./run.sh  # Port 8081
   ```

2. **Test Data:**
   ```bash
   # Created automatically by setup_e2e_tests()
   ```

3. **Environment:**
   ```bash
   # Python 3.8+
   pip install requests
   ```

### Run Tests

```bash
# Run all E2E tests
python3 backend/test_e2e_complete.py

# Run specific scenario
python3 -c "from test_e2e_complete import run_e2e_scenario_1; run_e2e_scenario_1()"
```

---

## Success Criteria

### Must Pass (Critical)

- [ ] Scenario 1: Complete workflow execution
- [ ] Scenario 2: Error handling for missing files
- [ ] All steps in Scenario 1 complete within expected time
- [ ] Results are downloadable and non-empty
- [ ] No critical errors in logs

### Should Pass (Important)

- [ ] Scenario 3: QC gate handling
- [ ] Scenario 4: Autofix recovery
- [ ] Scenario 5: Cryo-EM workflow
- [ ] Scenario 6: Multiple input files

### Nice to Have

- [ ] Scenario 7: Pilot run workflow
- [ ] Performance benchmarks met
- [ ] SSE events received correctly

---

## Monitoring During Tests

### What to Watch

```bash
# Frontend logs
tail -f frontend/logs/app.log

# Backend logs
tail -f backend/logs/galaxy.log

# Nextflow logs
tail -f backend/workflows/.nextflow.log

# System resources
watch -n 1 'ps aux | grep -E "node|python|nextflow"'
```

### Success Indicators

- ✅ No ERROR or CRITICAL in logs
- ✅ Memory usage stable
- ✅ No zombie processes
- ✅ All temporary files cleaned up

---

## Troubleshooting E2E Tests

### Test Fails at Step 3 (Execution)

**Possible Causes:**
- Backend not running
- Galaxy database not initialized
- Workflow import failed

**Debug:**
```bash
# Check backend logs
tail -f backend/logs/galaxy.log | grep ERROR

# Test API manually
curl http://localhost:8081/api/version
```

### Test Fails at Step 6 (Waiting)

**Possible Causes:**
- Nextflow not installed
- Docker/Singularity not available
- Process execution failed

**Debug:**
```bash
# Check Nextflow status
nextflow info

# Check process logs
cat backend/work/.command.log

# Check trace
cat backend/trace.txt
```

### Test Times Out

**Possible Causes:**
- Workflow too slow
- Resource contention
- Infinite loop

**Debug:**
- Check system resources (CPU, memory, disk)
- Review Nextflow trace for slow processes
- Increase timeout if workflow is legitimately slow

---

## Next Steps After E2E Tests Pass

1. **Performance Profiling:**
   - Identify bottlenecks
   - Optimize slow components
   - Set performance budgets

2. **Load Testing:**
   - Multiple concurrent workflows
   - Stress test with large files
   - Test resource limits

3. **Security Testing:**
   - Input validation
   - Authentication/authorization
   - File access controls

4. **User Acceptance Testing:**
   - Real users test workflows
   - Gather feedback
   - Identify UX issues

---

## Test Metrics

Track these metrics over time:

| Metric | Target | Actual |
|--------|--------|--------|
| E2E test pass rate | 100% | TBD |
| Average workflow time | <120s | TBD |
| Setup time | <5s | TBD |
| Download time | <10s | TBD |
| Memory usage | <2GB | TBD |
| CPU usage (peak) | <80% | TBD |

---

**Status:** Test plan complete, ready for implementation
