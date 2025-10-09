# End-to-End Workflow Execution Testing Guide

**Date:** October 4, 2025
**Purpose:** Test complete Galaxy workflow execution with real API integration

---

## 🎯 Testing Objectives

Verify the complete workflow execution system works end-to-end:
1. ✅ Dataset upload to Galaxy
2. ✅ AI-powered dataset validation
3. ✅ Workflow execution (sequential & step-by-step)
4. ✅ Real-time status updates
5. ✅ Error handling

---

## 📋 Prerequisites

### 1. Galaxy Instance
- **Running Galaxy server** (local or remote)
- **Galaxy API key** configured
- **Tools installed**: FastQC, HISAT2, etc.

### 2. Environment Setup
```bash
# Server
export GALAXY_URL="http://localhost:8080"
export GALAXY_API_KEY="your_galaxy_api_key"
export OPENAI_API_KEY="your_openai_api_key"
export PORT=3000

# Start server
cd server
npm run dev

# Client (separate terminal)
cd client
npm run dev
```

### 3. Test Data
- Sample FASTQ file (for RNA-seq testing)
- Sample mzML file (for LC-MS testing)
- CSV file (for permissive validation testing)

---

## 🧪 Test Cases

### Test Case 1: Basic Dataset Upload ✅

**Steps:**
1. Open http://localhost:5173 (or client URL)
2. Navigate to file upload section
3. Drag-and-drop a FASTQ file
4. Add description: "Human RNA-seq reads from liver tissue"
5. Wait for upload completion

**Expected Results:**
- ✅ File uploads successfully
- ✅ Dataset ID displayed
- ✅ Galaxy dataset ID returned
- ✅ Galaxy history ID in session
- ✅ Description field shows input

**Verification:**
```bash
# Check server logs
[FileUpload] File uploaded successfully: sample.fastq -> <dataset_id>
[FileUpload] Galaxy dataset created: <galaxy_dataset_id>
```

---

### Test Case 2: AI Dataset Validation ✅

**Steps:**
1. Upload 2 files: `sample_R1.fastq` and `sample_R2.fastq`
2. Add description to R1: "RNA-seq paired-end read 1"
3. Add description to R2: "RNA-seq paired-end read 2"
4. Load "RNA-seq Analysis Pipeline" workflow
5. Click "Start Workflow"

**Expected Results:**
- ✅ Validation API called automatically
- ✅ GPT-4 analyzes dataset characteristics
- ✅ Datasets auto-mapped to first step
- ✅ High confidence mappings returned
- ✅ No confirmation dialog (valid datasets)
- ✅ Workflow starts immediately

**Verification:**
```bash
# Server logs
[DatasetValidation] Validating 2 datasets against workflow: RNA-seq Analysis Pipeline
[DatasetValidation] Validation result: {"valid":true,"issues":[],"mappings":[...]}
[Workflow] Invoking workflow: rna-seq-analysis-pipeline
```

---

### Test Case 3: Validation with Issues ⚠️

**Steps:**
1. Upload single file: `treatment.bam`
2. Description: "ChIP-seq treatment sample"
3. Load "MACS2 Peak Calling" workflow
4. Click "Start Workflow"

**Expected Results:**
- ✅ Validation detects missing control file
- ✅ Dialog shows: "Missing control BAM file"
- ✅ Suggestions provided
- ✅ User must confirm to proceed

**Verification:**
```bash
# Validation response
{
  "valid": false,
  "issues": ["Missing control BAM file for MACS2 peak calling"],
  "suggestions": ["Upload a control/input BAM file for better peak detection"]
}
```

---

### Test Case 4: Permissive CSV Validation ✅

**Steps:**
1. Upload `data.csv`
2. Description: "Pre-processed LC-MS peak list"
3. Load "LC-MS Statistical Analysis" workflow
4. Click "Start Workflow"

**Expected Results:**
- ✅ CSV file accepted (permissive validation)
- ✅ No format rejection
- ✅ Medium confidence mapping
- ✅ Workflow proceeds
- ✅ Tool will validate CSV format if needed

**Verification:**
```bash
# Validation result
{
  "valid": true,
  "warnings": [],
  "mappings": [{
    "dataset_id": "csv_id",
    "confidence": "medium",
    "reasoning": "CSV file with description indicating pre-processed data"
  }]
}
```

---

### Test Case 5: Sequential Workflow Execution ✅

**Steps:**
1. Upload valid dataset
2. Load workflow template
3. Select "Sequential" execution mode
4. Click "Start Workflow"

**Expected Results:**
- ✅ All steps execute automatically
- ✅ Real-time status updates via SSE
- ✅ Timeline shows step progression
- ✅ Logs display for running steps
- ✅ Workflow completes successfully

**Verification:**
```bash
# Watch SSE stream
[SSE] Step 1: running
[SSE] Step 1: completed
[SSE] Step 2: running
[SSE] Step 2: completed
...
```

---

### Test Case 6: Step-by-Step Execution ✅

**Steps:**
1. Upload valid dataset
2. Load workflow template
3. Select "Step-by-Step" execution mode
4. Click "Run" on Step 1 (Quality Control)
5. Wait for completion
6. Review outputs
7. Click "Run" on Step 2 (Alignment)

**Expected Results:**
- ✅ Step 1 submits to Galaxy
- ✅ Status polling every 2 seconds
- ✅ Step transitions: Pending → Running → Completed
- ✅ User can review outputs
- ✅ Step 2 waits for manual trigger
- ✅ Full granular control

**Verification:**
```bash
# Server logs
[StepExecution] Executing step step1 with tool FastQC
[StepExecution] Job submitted: {"id":"job123","state":"queued"}
[StepStatus] Step step1 status: running
[StepStatus] Step step1 status: ok
```

---

### Test Case 7: Error Handling ❌

**Steps:**
1. Upload incompatible dataset
2. Load workflow with strict requirements
3. Start execution
4. Tool encounters error

**Expected Results:**
- ✅ Error state detected
- ✅ Step marked as "error" ❌
- ✅ Error message displayed
- ✅ User can edit parameters
- ✅ User can retry step

**Verification:**
```bash
# Error handling
[StepStatus] Step step1 status: error
[Frontend] Step execution failed: <error_message>
```

---

### Test Case 8: Session Persistence 🔐

**Steps:**
1. Upload dataset (creates Galaxy history)
2. Start workflow execution
3. Refresh page
4. Check session data

**Expected Results:**
- ✅ Galaxy history ID persists
- ✅ Uploaded datasets available
- ✅ Workflow jobs tracked
- ✅ Can resume from last state

**Verification:**
```bash
# Session data
req.session.galaxyHistoryId = "hist123"
req.session.uploadedDatasets = [...]
req.session.workflowJobs = {
  "step1": {"job_id":"job123","state":"ok"}
}
```

---

### Test Case 9: Workflow Template Management 📚

**Steps:**
1. Create custom workflow
2. Save as template
3. Load template in new session
4. Verify all parameters restored

**Expected Results:**
- ✅ Template saved with parameters
- ✅ Template listed in repository
- ✅ Template loads correctly
- ✅ Parameters pre-filled

---

### Test Case 10: Real-time Logs & Timeline 📊

**Steps:**
1. Start workflow execution
2. Monitor execution timeline
3. View logs for running step

**Expected Results:**
- ✅ Timeline shows step progression
- ✅ Running step highlighted
- ✅ Logs stream in real-time
- ✅ Completed steps marked with ✅
- ✅ Error steps marked with ❌

---

## 🔍 Manual Testing Checklist

### Backend API Testing:

```bash
# 1. Upload dataset
curl -X POST http://localhost:3000/api/datasets/upload \
  -F "file=@sample.fastq" \
  -F "description=Test RNA-seq sample"

# Expected: {"dataset_id":"...","galaxy_dataset_id":"..."}

# 2. Validate datasets
curl -X POST http://localhost:3000/api/datasets/validate \
  -H "Content-Type: application/json" \
  -d '{
    "workflow_name": "RNA-seq Analysis",
    "workflow_steps": [
      {"id":"step1","tool":"FastQC","parameters":{}}
    ]
  }'

# Expected: {"valid":true,"mappings":[...]}

# 3. Execute step
curl -X POST http://localhost:3000/api/workflow/step/execute \
  -H "Content-Type: application/json" \
  -d '{
    "step_id": "step1",
    "tool_id": "FastQC",
    "parameters": {}
  }'

# Expected: {"step_id":"step1","job_id":"...","state":"queued"}

# 4. Check status
curl http://localhost:3000/api/workflow/step/step1/status

# Expected: {"step_id":"step1","state":"ok","outputs":[...]}
```

---

## 🐛 Known Issues & Workarounds

### Issue 1: Galaxy Connection
**Problem:** Galaxy API unreachable
**Workaround:** Verify GALAXY_URL and API key
```bash
curl -H "x-api-key: $GALAXY_API_KEY" $GALAXY_URL/api/version
```

### Issue 2: Status Polling Timeout
**Problem:** Step runs longer than 5 minutes
**Workaround:** Increase timeout in handleStepAction:
```typescript
setTimeout(() => clearInterval(pollInterval), 600000) // 10 minutes
```

### Issue 3: Session Expiry
**Problem:** Session expires during long workflows
**Workaround:** Increase session timeout in server/index.ts:
```typescript
cookie: { maxAge: 3600000 } // 1 hour
```

---

## 📈 Performance Metrics

### Expected Performance:
- **File Upload:** < 5 seconds (50MB file)
- **AI Validation:** < 3 seconds (GPT-4 call)
- **Step Execution:** Depends on tool (FastQC ~2-3 min)
- **Status Polling:** 2-second intervals
- **SSE Updates:** < 100ms latency

---

## ✅ Success Criteria

All tests pass with:
- ✅ 100% dataset upload success
- ✅ Accurate AI validation results
- ✅ Successful Galaxy job submission
- ✅ Real-time status updates working
- ✅ Both execution modes functional
- ✅ Error handling graceful
- ✅ Session persistence working
- ✅ No memory leaks (polling cleanup)

---

## 📝 Test Report Template

```markdown
## Test Execution Report

**Date:** [Date]
**Tester:** [Name]
**Environment:** [Local/Staging/Production]

### Results Summary:
- Total Test Cases: 10
- Passed: [X]
- Failed: [Y]
- Blocked: [Z]

### Failed Tests:
1. [Test Case Name]
   - **Error:** [Description]
   - **Logs:** [Relevant logs]
   - **Workaround:** [If available]

### Performance Observations:
- Upload Speed: [X] MB/s
- Validation Latency: [X] ms
- Step Execution: [X] seconds

### Recommendations:
- [List any improvements needed]
```

---

**Last Updated:** October 4, 2025, 7:00 PM
