# Parameter Inference API Documentation

## Overview

The Parameter Inference API provides intelligent parameter inference for Galaxy tools through:
- **Pilot data analysis** - Quick characterization of user data
- **Progressive context gathering** - Systematic dialogue to collect required information
- **Full parameter inference** - Combined pipeline for complete parameter inference

**Base URL**: `http://localhost:8081/api` (Galaxy backend)

---

## Endpoints

### 1. List Available Pilot Analyzers

**GET** `/pilot_analysis/analyzers`

Get list of available pilot analyzers with optional filtering.

**Query Parameters**:
- `domain` (optional): Filter by domain (genomics, cryo_em, single_cell, etc.)
- `input_type` (optional): Filter by input type (bam, fastq, h5ad, etc.)
- `quick_only` (optional, boolean): Only return quick analyzers (<30s)

**Response**:
```json
{
  "total_analyzers": 20,
  "analyzers_by_domain": {
    "genomics": 6,
    "single_cell": 3,
    "cryo_em": 3,
    ...
  },
  "quick_analyzers_count": 12,
  "analyzers": [
    {
      "name": "estimate_fragment_size",
      "domain": "genomics",
      "description": "Estimate DNA fragment size from BAM file",
      "input_type": "bam",
      "runtime_estimate": "~30s per 10M reads",
      "max_runtime_seconds": 300,
      "output_type": "integer"
    },
    ...
  ]
}
```

**Example**:
```bash
# Get all genomics analyzers
curl http://localhost:8081/api/pilot_analysis/analyzers?domain=genomics

# Get quick analyzers only
curl http://localhost:8081/api/pilot_analysis/analyzers?quick_only=true

# Get analyzers for BAM files
curl http://localhost:8081/api/pilot_analysis/analyzers?input_type=bam
```

---

### 2. Run Pilot Analyzer

**POST** `/pilot_analysis/run`

Execute a specific pilot analyzer on user data.

**Request Body**:
```json
{
  "analyzer_name": "estimate_fragment_size",
  "input_file_path": "/path/to/chipseq.bam",
  "params": {
    "optional_param": "value"
  }
}
```

**Response**:
```json
{
  "analyzer_name": "estimate_fragment_size",
  "status": "success",
  "extracted_data": {
    "insert_size_average": 247
  },
  "execution_time_seconds": 12.3,
  "used_fallback": false,
  "error_message": null,
  "metadata": {
    "command": "samtools stats ...",
    "stdout_lines": 45,
    "stderr_lines": 2
  }
}
```

**Status Values**:
- `success`: Analyzer executed successfully
- `fallback`: Execution failed, fallback value used
- `timeout`: Analyzer timed out
- `failed`: Execution failed with no fallback

**Example**:
```bash
curl -X POST http://localhost:8081/api/pilot_analysis/run \
  -H "Content-Type: application/json" \
  -d '{
    "analyzer_name": "estimate_fragment_size",
    "input_file_path": "/galaxy/database/files/001/dataset_123.dat"
  }'
```

---

### 3. Run Multiple Pilot Analyzers

**POST** `/pilot_analysis/batch`

Run multiple analyzers on the same input file.

**Request Body**:
```json
{
  "analyzer_names": [
    "estimate_fragment_size",
    "detect_sequencing_protocol",
    "count_reads_and_depth"
  ],
  "input_file_path": "/path/to/chipseq.bam"
}
```

**Response**:
```json
{
  "estimate_fragment_size": {
    "status": "success",
    "extracted_data": {"insert_size_average": 247},
    ...
  },
  "detect_sequencing_protocol": {
    "status": "success",
    "extracted_data": {"sequencing_protocol": "paired_end"},
    ...
  },
  "count_reads_and_depth": {
    "status": "success",
    "extracted_data": {
      "total_reads": 1000000,
      "mapped_reads": 950000
    },
    ...
  }
}
```

**Example**:
```bash
curl -X POST http://localhost:8081/api/pilot_analysis/batch \
  -H "Content-Type: application/json" \
  -d '{
    "analyzer_names": ["estimate_fragment_size", "detect_sequencing_protocol"],
    "input_file_path": "/galaxy/database/files/001/dataset_123.dat"
  }'
```

---

### 4. Progressive Context Gathering

**POST** `/context_gathering/chat`

Progressive dialogue for gathering context needed for parameter inference.

**Request Body (Initial)**:
```json
{
  "tool_id": "biomni/genomics/perform_chipseq_peak_calling_with_macs2",
  "initial_query": "Call peaks from H3K27me3 ChIP-seq in mouse brain",
  "user_answers": null,
  "input_files": null
}
```

**Response (Need More Context)**:
```json
{
  "status": "need_more_context",
  "questions": [
    {
      "field": "organism",
      "question": "What organism is your sample from?",
      "type": "select",
      "parameter": "genome",
      "help_text": "Required for peak calling against reference genome",
      "options": [
        {
          "value": "mouse",
          "label": "Mouse (Mus musculus)",
          "description": "Laboratory mouse",
          "recommended_value": "mm10"
        },
        {
          "value": "human",
          "label": "Human (Homo sapiens)",
          "description": "Human genome",
          "recommended_value": "hg38"
        }
      ],
      "allow_custom": true
    }
  ],
  "gathered_so_far": {
    "antibody_target": "H3K27me3",
    "histone_mark_type": "broad",
    "tissue_type": "brain"
  },
  "progress": {
    "collected": 3,
    "remaining": 1,
    "total": 4
  }
}
```

**Request Body (With Answers)**:
```json
{
  "tool_id": "biomni/genomics/perform_chipseq_peak_calling_with_macs2",
  "initial_query": "",
  "user_answers": {
    "organism": "mouse"
  },
  "input_files": {
    "bam_file": "/path/to/chipseq.bam"
  }
}
```

**Response (Context Complete)**:
```json
{
  "status": "context_complete",
  "questions": null,
  "context": {
    "antibody_target": "H3K27me3",
    "histone_mark_type": "broad",
    "tissue_type": "brain",
    "organism": "mouse",
    "fragment_size": 247
  },
  "gathered_so_far": {...},
  "summary": "Context for MACS2 peak calling:\n  • antibody_target: H3K27me3\n  • organism: mouse\n  • fragment_size: 247",
  "pilot_analysis_results": {
    "insert_size_average": 247,
    "sequencing_protocol": "paired_end"
  }
}
```

**Example (Multi-round dialogue)**:
```bash
# Round 1: Initial query
curl -X POST http://localhost:8081/api/context_gathering/chat \
  -H "Content-Type: application/json" \
  -d '{
    "tool_id": "biomni/genomics/perform_chipseq_peak_calling_with_macs2",
    "initial_query": "Call peaks from H3K27me3 ChIP-seq"
  }'

# Response: status=need_more_context, questions=[{field: organism, ...}]

# Round 2: Answer questions
curl -X POST http://localhost:8081/api/context_gathering/chat \
  -H "Content-Type: application/json" \
  -d '{
    "tool_id": "biomni/genomics/perform_chipseq_peak_calling_with_macs2",
    "user_answers": {"organism": "mouse"},
    "input_files": {"bam_file": "/path/to/file.bam"}
  }'

# Response: status=context_complete, context={...}
```

---

### 5. Full Parameter Inference

**POST** `/parameter_inference/infer`

Complete parameter inference pipeline combining context gathering and pilot analysis.

**Request Body**:
```json
{
  "tool_id": "biomni/genomics/perform_chipseq_peak_calling_with_macs2",
  "user_query": "Call peaks from H3K27me3 ChIP-seq in mouse brain",
  "input_files": {
    "bam_file": "/path/to/chipseq.bam"
  },
  "user_context": {
    "organism": "mouse"
  },
  "enable_pilot_analysis": true
}
```

**Response**:
```json
{
  "tool_id": "biomni/genomics/perform_chipseq_peak_calling_with_macs2",
  "inferred_parameters": {
    "peak_type": "broad",
    "extsize": 200,
    "qvalue": 0.05,
    "genome": "mm10"
  },
  "context_used": {
    "antibody_target": "H3K27me3",
    "histone_mark_type": "broad",
    "organism": "mouse",
    "fragment_size": 247
  },
  "pilot_analysis_run": true,
  "pilot_analysis_results": {
    "insert_size_average": 247
  },
  "confidence": {
    "peak_type": "high",
    "extsize": "high",
    "qvalue": "medium",
    "genome": "high"
  },
  "recommendations": [
    "All required parameters inferred successfully",
    "Fragment size (247 bp) extracted from data"
  ],
  "warnings": []
}
```

**Confidence Levels**:
- `high`: User-provided or data-extracted value
- `medium`: Inferred from context or using fallback
- `low`: Using default value with limited context

**Example**:
```bash
curl -X POST http://localhost:8081/api/parameter_inference/infer \
  -H "Content-Type: application/json" \
  -d '{
    "tool_id": "biomni/genomics/perform_chipseq_peak_calling_with_macs2",
    "user_query": "Call peaks from H3K27me3 ChIP-seq",
    "input_files": {"bam_file": "/galaxy/files/dataset_123.dat"},
    "enable_pilot_analysis": true
  }'
```

---

### 6. Health Check

**GET** `/parameter_inference/health`

Check parameter inference system health.

**Response**:
```json
{
  "parameter_inference_available": true,
  "pilot_analysis_available": true,
  "context_gathering_available": true,
  "status": "healthy"
}
```

**Example**:
```bash
curl http://localhost:8081/api/parameter_inference/health
```

---

## Integration Examples

### Frontend Integration (React/TypeScript)

```typescript
// 1. List available analyzers for a data file
async function getApplicableAnalyzers(fileType: string) {
  const response = await fetch(
    `/api/pilot_analysis/analyzers?input_type=${fileType}`
  );
  return await response.json();
}

// 2. Progressive context gathering
async function gatherContext(toolId: string, query: string) {
  let status = 'need_more_context';
  let context = null;

  // Initial query
  let response = await fetch('/api/context_gathering/chat', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
      tool_id: toolId,
      initial_query: query
    })
  });

  let result = await response.json();

  while (result.status === 'need_more_context') {
    // Show questions to user
    const answers = await askUserQuestions(result.questions);

    // Submit answers
    response = await fetch('/api/context_gathering/chat', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        tool_id: toolId,
        user_answers: answers
      })
    });

    result = await response.json();
  }

  return result.context;
}

// 3. Full parameter inference
async function inferParameters(toolId: string, query: string, files: Record<string, string>) {
  const response = await fetch('/api/parameter_inference/infer', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
      tool_id: toolId,
      user_query: query,
      input_files: files,
      enable_pilot_analysis: true
    })
  });

  return await response.json();
}
```

### Python Client

```python
import requests

BASE_URL = "http://localhost:8081/api"

def run_pilot_analysis(analyzer_name: str, input_file: str):
    """Run pilot analyzer on data."""
    response = requests.post(
        f"{BASE_URL}/pilot_analysis/run",
        json={
            "analyzer_name": analyzer_name,
            "input_file_path": input_file
        }
    )
    response.raise_for_status()
    return response.json()

def infer_parameters(tool_id: str, query: str, input_files: dict):
    """Get inferred parameters for a tool."""
    response = requests.post(
        f"{BASE_URL}/parameter_inference/infer",
        json={
            "tool_id": tool_id,
            "user_query": query,
            "input_files": input_files,
            "enable_pilot_analysis": True
        }
    )
    response.raise_for_status()
    return response.json()

# Example usage
if __name__ == "__main__":
    # Run pilot analysis
    result = run_pilot_analysis(
        "estimate_fragment_size",
        "/galaxy/files/chipseq.bam"
    )
    print(f"Fragment size: {result['extracted_data']['insert_size_average']} bp")

    # Infer parameters
    params = infer_parameters(
        "biomni/genomics/perform_chipseq_peak_calling_with_macs2",
        "Call peaks from H3K27me3 ChIP-seq",
        {"bam_file": "/galaxy/files/chipseq.bam"}
    )
    print(f"Inferred parameters: {params['inferred_parameters']}")
```

---

## Error Handling

All endpoints return proper HTTP status codes:

- `200 OK`: Request successful
- `400 Bad Request`: Invalid request parameters
- `404 Not Found`: Resource not found
- `500 Internal Server Error`: Server error
- `503 Service Unavailable`: Parameter inference system not available

**Error Response Format**:
```json
{
  "detail": "Error description"
}
```

**Example**:
```json
{
  "detail": "Parameter inference not available"
}
```

---

## OpenAPI Documentation

Once the Galaxy server is running, full OpenAPI (Swagger) documentation is available at:

- **Swagger UI**: `http://localhost:8081/docs`
- **ReDoc**: `http://localhost:8081/redoc`
- **OpenAPI JSON**: `http://localhost:8081/openapi.json`

The API documentation includes:
- All endpoints with descriptions
- Request/response schemas
- Example requests
- Try-it-out functionality

---

## Rate Limiting & Performance

**Pilot Analysis**:
- Quick analyzers (<30s): No rate limit
- Medium analyzers (<60s): Recommended max 10/minute
- Long analyzers (>60s): Recommended max 5/minute

**Context Gathering**:
- No rate limit (lightweight LLM calls)

**Full Inference**:
- Recommended max 20/minute (includes pilot analysis)

**Caching**:
- Pilot analysis results are cached per file
- Context gathering caches LLM extractions
- Cache duration: Session-based (cleared on logout)

---

## Authentication

All endpoints require Galaxy authentication:
- **Session cookie**: For web UI
- **API key**: For programmatic access

**Using API Key**:
```bash
curl -H "x-api-key: YOUR_API_KEY" \
  http://localhost:8081/api/pilot_analysis/analyzers
```

---

## Changelog

**Version 1.0 (2026-02-09)**:
- Initial release with 6 endpoints
- 20 pilot analyzers across 7 domains
- Progressive context gathering
- Full parameter inference pipeline
