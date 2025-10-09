# AI-Powered Dataset Orchestration System

**Date:** October 4, 2025
**Status:** Backend Complete, UI Integration Pending

---

## Overview

Implemented an **intelligent dataset orchestration system** that uses LLM to automatically analyze and map uploaded datasets to workflow steps, with user confirmation only when issues are detected.

---

## ✅ Completed Backend Implementation

### 1. AI Dataset Validator (NEW)

**File:** `server/dataset-validator.ts` (150 lines)

**Features:**
- ✅ LLM-powered analysis using GPT-4
- ✅ Analyzes dataset characteristics (name, type, size, description)
- ✅ Validates against workflow requirements
- ✅ Auto-maps datasets to first workflow step
- ✅ Returns confidence levels (high/medium/low)
- ✅ Identifies issues and provides suggestions

**API Method:**
```typescript
async validateDatasets(
  datasets: Dataset[],
  workflowSteps: WorkflowStep[],
  workflowName: string
): Promise<DatasetValidationResult>
```

**Response Format:**
```typescript
{
  valid: boolean,
  issues: string[],           // Critical problems
  warnings: string[],          // Non-critical concerns
  suggestions: string[],       // Helpful tips
  mappings: [{
    dataset_id: string,
    step_id: string,
    input_name: string,        // e.g., "fastq_input", "bam_file"
    confidence: "high" | "medium" | "low",
    reasoning: string
  }]
}
```

---

### 2. Enhanced File Upload API

**Changes to `server/routes.ts`:**

✅ **Added description field** to upload endpoint:
```typescript
app.post("/api/datasets/upload", upload.single('file'), async (req, res) => {
  const description = req.body.description || '';

  // Store in session for validation
  req.session.uploadedDatasets.push({
    dataset_id, galaxy_dataset_id, name, description, file_type, file_size
  });

  // Return with description
  res.json({ ...dataset_info, description });
})
```

✅ **Session-based dataset tracking:**
- All uploaded datasets stored in `req.session.uploadedDatasets[]`
- Available for validation when workflow starts

---

### 3. Dataset Validation API (NEW)

**Endpoint:** `POST /api/datasets/validate`

**Request:**
```json
{
  "workflow_name": "RNA-seq Analysis Pipeline",
  "workflow_steps": [
    {
      "id": "step1",
      "title": "Quality Control",
      "tool": "FastQC",
      "parameters": { "..." }
    },
    ...
  ]
}
```

**Response:**
```json
{
  "valid": true,
  "issues": [],
  "warnings": ["File size unusually large (2.5GB)"],
  "suggestions": ["Consider adding paired-end reads for better results"],
  "mappings": [
    {
      "dataset_id": "abc123",
      "step_id": "step1",
      "input_name": "fastq_input",
      "confidence": "high",
      "reasoning": "FASTQ file format matches FastQC input requirements"
    }
  ]
}
```

---

## 🎯 How It Works

### User Flow:

1. **User uploads file(s)**
   - Optionally provides description: "Human RNA-seq reads from liver tissue"
   - File goes to local storage + Galaxy history
   - Metadata stored in session

2. **User starts workflow**
   - System calls `/api/datasets/validate`
   - Sends: uploaded datasets + workflow steps

3. **LLM Analysis** (GPT-4)
   - Analyzes dataset characteristics
   - Compares against workflow requirements
   - Checks file formats, naming patterns, descriptions
   - Identifies missing/incompatible datasets

4. **Auto-Mapping**
   - Datasets automatically assigned to **first workflow step**
   - Mapping includes confidence level + reasoning

5. **Conditional Confirmation**
   - **If valid** → Proceed automatically
   - **If issues detected** → Show confirmation dialog with:
     - Critical issues (e.g., "Missing FASTQ input")
     - Warnings (e.g., "File unusually large")
     - Suggestions (e.g., "Consider adding control samples")
     - Proposed mappings for user review

---

## 📊 LLM Validation Logic

### Analysis Criteria:

**File Format Compatibility:**
- FASTQ/FASTQ.GZ → QC tools (FastQC, Trimmomatic)
- BAM/SAM → Alignment tools (HISAT2, BWA)
- mzML/mzXML → LC-MS tools (XCMS, MSDIAL)

**Naming Patterns:**
- `sample1_R1.fastq` → Paired-end read 1
- `treatment_vs_control.bam` → ChIP-seq input
- `liver_tissue_pos.mzML` → LC-MS positive mode

**Description Analysis:**
- "RNA-seq from liver" → Matches RNA-seq workflow
- "ChIP-seq H3K27ac" → Matches peak calling workflow
- "Metabolomics LC-MS" → Matches XCMS workflow

**Missing Inputs:**
- RNA-seq needs paired FASTQ files
- ChIP-seq needs treatment + control BAM
- Metabolomics needs mzML/mzXML files

---

## 🔧 Tool-Specific Input Mapping

The validator knows expected inputs for common tools:

| Tool | Expected Input Name | File Types |
|------|---------------------|------------|
| FastQC | `fastq_input` | FASTQ, FASTQ.GZ |
| HISAT2/BWA | `fastq_reads` | FASTQ, FASTQ.GZ |
| MACS2 | `treatment_bam` | BAM |
| XCMS | `mzml_files` | mzML, mzXML |
| featureCounts | `bam_alignment` | BAM |

**Inference Logic:**
```typescript
if (tool.includes('fastqc')) return 'fastq_input'
if (tool.includes('hisat')) return 'fastq_reads'
if (tool.includes('macs')) return 'treatment_bam'
if (tool.includes('xcms')) return 'mzml_files'
```

---

## 🚀 Next Steps (UI Integration)

### Remaining UI Work:

#### 1. Add Description Field to FileUpload Component
```typescript
// file-upload.tsx - Add after file selection:
<Input
  placeholder="Optional: Describe this dataset (e.g., 'RNA-seq from liver tissue')"
  value={description}
  onChange={(e) => setDescription(e.target.value)}
/>

// Send description with upload:
formData.append('description', description)
```

#### 2. Add Validation Dialog Component
```typescript
// dataset-validation-dialog.tsx
<Dialog open={showValidation}>
  <DialogContent>
    <DialogTitle>
      {validation.valid ? "Datasets Ready" : "Issues Detected"}
    </DialogTitle>

    {validation.issues.length > 0 && (
      <Alert variant="destructive">
        <AlertTitle>Critical Issues</AlertTitle>
        <ul>{validation.issues.map(i => <li>{i}</li>)}</ul>
      </Alert>
    )}

    {validation.warnings.length > 0 && (
      <Alert>
        <AlertTitle>Warnings</AlertTitle>
        <ul>{validation.warnings.map(w => <li>{w}</li>)}</ul>
      </Alert>
    )}

    <div className="mt-4">
      <h4>Proposed Dataset Mappings:</h4>
      {validation.mappings.map(m => (
        <div className="flex items-center justify-between">
          <span>{m.dataset_id} → {m.input_name}</span>
          <Badge>{m.confidence}</Badge>
          <span className="text-sm text-muted">{m.reasoning}</span>
        </div>
      ))}
    </div>

    <DialogFooter>
      <Button onClick={handleConfirm}>Proceed</Button>
      <Button variant="outline" onClick={handleEdit}>Edit Mappings</Button>
    </DialogFooter>
  </DialogContent>
</Dialog>
```

#### 3. Integrate Validation Before Workflow Start
```typescript
// enhanced-workflow-builder.tsx
const handleWorkflowStart = async () => {
  // Call validation endpoint
  const validation = await fetch('/api/datasets/validate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      workflow_name: workflowName,
      workflow_steps: steps
    })
  }).then(r => r.json())

  // If valid → proceed automatically
  if (validation.valid && validation.issues.length === 0) {
    await invokeWorkflow(workflowId, buildInputsFromMappings(validation.mappings))
    return
  }

  // If issues → show confirmation dialog
  setValidationResult(validation)
  setShowValidationDialog(true)
}
```

---

## 💡 Example Scenarios

### Scenario 1: Perfect Match ✅
**User uploads:** `sample_R1.fastq.gz`, `sample_R2.fastq.gz`
**Description:** "Human RNA-seq paired-end reads"
**Workflow:** RNA-seq QC → Alignment → DESeq2

**LLM Response:**
```json
{
  "valid": true,
  "issues": [],
  "warnings": [],
  "suggestions": ["Ensure reference genome is hg38 for human samples"],
  "mappings": [
    {
      "dataset_id": "R1_id",
      "step_id": "step1",
      "input_name": "fastq_r1",
      "confidence": "high",
      "reasoning": "FASTQ format with R1 suffix indicates paired-end read 1"
    },
    {
      "dataset_id": "R2_id",
      "step_id": "step1",
      "input_name": "fastq_r2",
      "confidence": "high",
      "reasoning": "FASTQ format with R2 suffix indicates paired-end read 2"
    }
  ]
}
```
**Action:** Proceed automatically, no confirmation needed

---

### Scenario 2: Missing Dataset ❌
**User uploads:** `treatment.bam`
**Description:** "ChIP-seq treatment sample"
**Workflow:** MACS2 Peak Calling

**LLM Response:**
```json
{
  "valid": false,
  "issues": ["Missing control BAM file for MACS2 peak calling"],
  "warnings": [],
  "suggestions": ["Upload a control/input BAM file for better peak detection"],
  "mappings": [
    {
      "dataset_id": "treatment_id",
      "step_id": "step1",
      "input_name": "treatment_bam",
      "confidence": "high",
      "reasoning": "BAM file matches MACS2 treatment input"
    }
  ]
}
```
**Action:** Show dialog with issue, suggest uploading control file

---

### Scenario 3: Ambiguous Mapping ⚠️
**User uploads:** `data.csv`
**Description:** (none provided)
**Workflow:** LC-MS Peak Detection (XCMS)

**LLM Response:**
```json
{
  "valid": false,
  "issues": ["Wrong file format: XCMS requires mzML or mzXML files"],
  "warnings": ["CSV file provided, but LC-MS workflows need raw spectral data"],
  "suggestions": ["Convert raw LC-MS data to mzML format using MSConvert"],
  "mappings": []
}
```
**Action:** Show dialog explaining issue, prevent execution

---

## 🔒 Fallback Behavior

If LLM validation fails (API error, timeout):
```typescript
return {
  valid: true,
  issues: [],
  warnings: ["Could not validate datasets. Proceeding with auto-assignment."],
  suggestions: [],
  mappings: datasets.map(d => ({
    dataset_id: d.dataset_id,
    step_id: firstStep.id,
    input_name: inferInputName(firstStep.tool),
    confidence: 'low',
    reasoning: 'Validation service unavailable, auto-assigned to first step'
  }))
}
```

**Ensures system continues working even if AI validation is unavailable.**

---

## 📈 Benefits

1. **Intelligent Auto-Mapping** - LLM understands dataset context and workflow requirements
2. **Proactive Issue Detection** - Catches problems before execution starts
3. **User-Friendly** - Confirmation only when necessary, not for every upload
4. **Context-Aware** - Considers descriptions, file names, types together
5. **Confidence Scoring** - Users see how certain the system is about mappings
6. **Educational** - Suggestions help users understand workflow requirements

---

## 🛠️ Technical Stack

- **LLM:** GPT-4 (OpenAI)
- **Backend:** Node.js + Express
- **Session Storage:** Express session
- **Type Safety:** TypeScript interfaces
- **Error Handling:** Graceful fallbacks

---

## 📝 Summary

**Backend: 100% Complete ✅**
- Dataset validator service with GPT-4 integration
- File upload enhanced with description field
- Validation API endpoint
- Session-based dataset tracking
- Auto-mapping to first workflow step

**UI Integration: Pending** (3 components needed)
1. Description field in FileUpload
2. Validation dialog component
3. Integration in workflow builder

**Estimated UI Work:** 2-3 hours

---

**Last Updated:** October 4, 2025, 3:30 PM
