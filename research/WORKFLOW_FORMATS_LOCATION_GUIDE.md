# Workflow Formats Location Guide
**Date**: 2025-11-19
**Purpose**: Reference guide for finding Galaxy, Nextflow, and BUWF workflow files

---

## Three Workflow Formats

BioMate supports three workflow formats:

1. **Galaxy .ga** - Original Galaxy workflow JSON format
2. **Nextflow .nf** - Nextflow DSL2 workflow scripts
3. **BUWF .json** - BioMate Unified Workflow Format (intermediate format)

---

## Example Workflow: Quantify Pseudo Alignment

### 1. Galaxy Format (.ga)

**Location**:
```
/home/yzhang/biomate/backend/galaxy_workflows_reformatted/quantify_pseudo_alignment.ga
```

**Size**: 22KB (JSON)

**Structure**:
```json
{
  "a_galaxy_workflow": "true",
  "annotation": "Quantify with kallisto or Salmon",
  "format-version": "0.1",
  "name": "Quantify Pseudo Alignment",
  "steps": {
    "0": {
      "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/kallisto_quant/kallisto_quant/...",
      "tool_state": "{...}",
      "type": "tool",
      "uuid": "..."
    },
    "1": {...},
    ...
  }
}
```

**Characteristics**:
- Tool IDs from Galaxy ToolShed
- Complex tool_state parameters
- Position-based workflow layout
- Galaxy-specific UUIDs

---

### 2. Nextflow Format (.nf)

**Original nf-core Workflow**:
```
/home/yzhang/biomate/backend/nf-core-workflows/rnaseq/subworkflows/nf-core/quantify_pseudo_alignment/main.nf
```

**Generated from Galaxy .ga**:
```
/home/yzhang/biomate/backend/nf-core-workflows/rnaseq/subworkflows/nf-core/quantify_pseudo_alignment/main_generated/main.nf
```

**Size**: 347 bytes (Groovy script)

**Structure**:
```groovy
workflow QUANTIFY_PSEUDO_ALIGNMENT {
    take:
    ch_index
    ch_reads
    ch_fasta

    main:
    // Kallisto quantification
    KALLISTO_QUANT (
        ch_reads,
        ch_index
    )

    // Salmon quantification
    SALMON_QUANT (
        ch_reads,
        ch_index,
        ch_fasta
    )

    emit:
    kallisto_results = KALLISTO_QUANT.out.abundance
    salmon_results   = SALMON_QUANT.out.results
}
```

**Characteristics**:
- Nextflow DSL2 syntax
- Channel-based data flow
- Named inputs/outputs
- Module imports

**Additional Files**:
```
main_generated/
├── main.nf                     # Main workflow
├── nextflow.config             # Configuration
├── workflow.buwf.json          # BUWF format
└── modules/
    └── nfcore_empty.nf         # Placeholder modules
```

---

### 3. BUWF Format (.json)

**Location**:
```
/home/yzhang/biomate/backend/nf-core-workflows/rnaseq/subworkflows/nf-core/quantify_pseudo_alignment/main_generated/workflow.buwf.json
```

**Size**: 4.7KB (JSON)

**Structure**:
```json
{
  "workflow_id": "quantify_pseudo_alignment_20251119",
  "name": "Quantify Pseudo Alignment",
  "description": "Quantify with kallisto or Salmon",
  "source_format": "galaxy",
  "execution_engine": "nextflow",
  "creator": "IUC",
  "license": "MIT",
  "tags": ["rna-seq", "quantification", "kallisto", "salmon"],
  "high_level_steps": [
    {
      "step_id": "quantification",
      "name": "Quantification",
      "description": "RNA-seq quantification with pseudo-alignment",
      "category": "quantification",
      "icon": "📊",
      "color": "#f39c12",
      "order": 0,
      "detailed_steps": [
        {
          "step_id": "0",
          "tool_id": "kallisto_quant",
          "tool_name": "Kallisto Quant",
          "tool_version": "0.46.2",
          "inputs": [
            {
              "name": "index",
              "data_type": "kallisto_index",
              "format": "kallisto.idx",
              "optional": false
            },
            {
              "name": "reads",
              "data_type": "fastq",
              "format": "fastqsanger",
              "optional": false
            }
          ],
          "outputs": [
            {
              "name": "abundance",
              "data_type": "tsv",
              "format": "tabular",
              "description": "Gene abundance estimates"
            }
          ],
          "parameters": {
            "bootstrap_samples": {
              "name": "bootstrap_samples",
              "type": "integer",
              "value": 100,
              "required": false,
              "default": 100
            }
          }
        }
      ],
      "inputs": [...],
      "outputs": [...]
    }
  ]
}
```

**Characteristics**:
- Domain-agnostic format
- Hierarchical structure (high-level → detailed steps)
- Rich metadata (icons, colors, categories)
- Tool inputs/outputs/parameters explicitly defined
- Convertible to both Galaxy and Nextflow

---

## Directory Structure

### Galaxy Workflows

**Official IWC (Intergalactic Workflow Commission)**:
```
/home/yzhang/biomate/backend/galaxy_workflows_official_iwc/
├── assembly/
├── chipseq/
├── computational-chemistry/
├── epigenetics/
├── imaging/
├── microbiome/
├── proteomics/
├── scRNAseq/
├── transcriptomics/
└── virology/
```

**Reformatted Workflows** (cleaned up for testing):
```
/home/yzhang/biomate/backend/galaxy_workflows_reformatted/
├── quantify_pseudo_alignment.ga
├── fastq_align_dna.ga
├── fastq_preprocess.ga
├── bam_qc_picard.ga
└── ... (50+ workflows)
```

**Curated Workflows** (from research):
```
/home/yzhang/biomate/research/curated_workflows/
├── 165_chip-seq_analysis_single-end_read_processing_relea_5.ga
├── 155_amr_gene_detection_release_v11.ga
├── 150_scrna-seq_preprocessing_10x_v3_bun_release_v03_1.ga
└── ... (100+ workflows)
```

---

### Nextflow Workflows

**nf-core Workflows**:
```
/home/yzhang/biomate/backend/nf-core-workflows/
├── rnaseq/
│   ├── workflows/
│   │   └── rnaseq.nf
│   └── subworkflows/
│       └── nf-core/
│           ├── quantify_pseudo_alignment/
│           │   ├── main.nf                    # Original nf-core
│           │   └── main_generated/            # Generated from Galaxy
│           │       ├── main.nf
│           │       ├── workflow.buwf.json
│           │       └── modules/
│           ├── fastqc_trimgalore/
│           ├── align_star/
│           └── ...
├── chipseq/
│   └── subworkflows/
│       └── local/
│           └── bed_consensus_quantify_qc_bedtools_featurecounts_deseq2.nf
└── ...
```

---

### BUWF Workflows

**Generated Alongside Nextflow**:
```
/home/yzhang/biomate/backend/nf-core-workflows/rnaseq/subworkflows/nf-core/quantify_pseudo_alignment/main_generated/workflow.buwf.json
```

**In-Memory During API Calls** (not saved to disk):
- Generated dynamically during workflow generation
- Returned in API responses as `buwf_workflow` field
- Used for frontend display

---

## Converter Classes

### Location
```
/home/yzhang/biomate/backend/lib/galaxy/ai/workflow_converters/
```

### Files
1. **`galaxy_converter.py`** - Galaxy .ga ↔ BUWF
2. **`nextflow_converter.py`** - Nextflow .nf ↔ BUWF
3. **`workflow_grouper.py`** - BUWF intelligent step grouping
4. **`serialization.py`** - BUWF JSON serialization
5. **`workflow_abstraction.py`** - BUWF data models

### Conversion Flow

```
Galaxy .ga
    │
    ├─→ GalaxyToUnifiedConverter.convert()
    │       └─→ UnifiedWorkflow (BUWF in-memory)
    │               │
    │               ├─→ group_workflow_steps()
    │               │       └─→ Grouped BUWF
    │               │
    │               ├─→ UnifiedToGalaxyConverter.convert()
    │               │       └─→ Galaxy .ga (round-trip)
    │               │
    │               └─→ UnifiedToNextflowConverter.convert()
    │                       └─→ Nextflow .nf
    │
    └─→ serialize_buwf()
            └─→ workflow.buwf.json
```

---

## Test Scripts

### Testing Conversions

**Test API Integration** (all formats):
```bash
cd /home/yzhang/biomate
python3 research/scripts/test_api_integration.py
```

Tests:
- Galaxy → BUWF conversion
- BUWF grouping
- BUWF serialization
- Round-trip conversion (Galaxy → BUWF → Galaxy)

**Test Galaxy Conversion**:
```bash
python3 research/scripts/test_galaxy_conversion_quick.py
```

**Test Nextflow Conversion**:
```bash
python3 research/scripts/test_nextflow_conversion.py
```

**Test Workflow Grouping**:
```bash
python3 research/scripts/test_workflow_grouping.py
```

---

## Example Workflows by Category

### RNA-Seq

**Galaxy**:
- `backend/galaxy_workflows_reformatted/quantify_pseudo_alignment.ga`
- `backend/galaxy_workflows_official_iwc/transcriptomics/rnaseq-pe.ga`

**Nextflow**:
- `backend/nf-core-workflows/rnaseq/workflows/rnaseq.nf`
- `backend/nf-core-workflows/rnaseq/subworkflows/nf-core/quantify_pseudo_alignment/main.nf`

### ChIP-Seq

**Galaxy**:
- `backend/galaxy_workflows_official_iwc/epigenetics/chipseq-pe/chipseq-pe.ga`

**Nextflow**:
- `backend/nf-core-workflows/chipseq/workflows/chipseq.nf`

### Variant Calling

**Galaxy**:
- `backend/galaxy_workflows_reformatted/bam_tumor_normal_somatic_variant_calling_gatk.ga`

### Preprocessing

**Galaxy**:
- `backend/galaxy_workflows_reformatted/fastq_preprocess.ga`
- `backend/galaxy_workflows_reformatted/fastq_align_dna.ga`

---

## Quick Access Commands

### View Galaxy Workflow
```bash
cat /home/yzhang/biomate/backend/galaxy_workflows_reformatted/quantify_pseudo_alignment.ga | jq '.' | less
```

### View Nextflow Workflow
```bash
cat /home/yzhang/biomate/backend/nf-core-workflows/rnaseq/subworkflows/nf-core/quantify_pseudo_alignment/main.nf
```

### View BUWF Workflow
```bash
cat /home/yzhang/biomate/backend/nf-core-workflows/rnaseq/subworkflows/nf-core/quantify_pseudo_alignment/main_generated/workflow.buwf.json | jq '.' | less
```

### Count Workflows
```bash
# Galaxy workflows
find /home/yzhang/biomate/backend/galaxy_workflows_reformatted -name "*.ga" | wc -l

# Nextflow workflows
find /home/yzhang/biomate/backend/nf-core-workflows -name "*.nf" -type f | wc -l

# BUWF workflows
find /home/yzhang/biomate/backend/nf-core-workflows -name "*.buwf.json" | wc -l
```

### Convert Galaxy to BUWF (Python)
```python
import sys
import json
from pathlib import Path

sys.path.insert(0, '/home/yzhang/biomate/backend')

from lib.galaxy.ai.workflow_converters import (
    GalaxyToUnifiedConverter,
    group_workflow_steps,
    serialize_buwf
)

# Load Galaxy workflow
with open('/home/yzhang/biomate/backend/galaxy_workflows_reformatted/quantify_pseudo_alignment.ga') as f:
    galaxy_wf = json.load(f)

# Convert to BUWF
converter = GalaxyToUnifiedConverter()
unified_wf = converter.convert(galaxy_wf)

# Apply grouping
grouped_wf = group_workflow_steps(unified_wf)

# Serialize to JSON
buwf_json = serialize_buwf(grouped_wf)

# Save
with open('/tmp/workflow.buwf.json', 'w') as f:
    json.dump(buwf_json, f, indent=2)

print(f"✅ Converted: {len(grouped_wf.high_level_steps)} high-level steps")
```

---

## Format Comparison

| Feature | Galaxy .ga | Nextflow .nf | BUWF .json |
|---------|-----------|--------------|------------|
| **Size** | 22KB | 347 bytes | 4.7KB |
| **Format** | JSON | Groovy | JSON |
| **Execution** | Galaxy | Nextflow | Both (via conversion) |
| **Tools** | Galaxy ToolShed IDs | nf-core modules | Generic tool names |
| **Parameters** | tool_state blob | Config file | Structured dict |
| **Layout** | Position-based | Flow-based | Hierarchical |
| **Metadata** | Minimal | Minimal | Rich (icons, colors, categories) |
| **Grouping** | No | No | Yes (intelligent) |
| **Human-readable** | Medium | High | Very High |

---

## Summary

**For Galaxy → BUWF → Nextflow conversions**:
1. Start with: `backend/galaxy_workflows_reformatted/quantify_pseudo_alignment.ga`
2. Convert with: `GalaxyToUnifiedConverter().convert()`
3. Group with: `group_workflow_steps()`
4. To Nextflow: `UnifiedToNextflowConverter().convert()`
5. Output: `main_generated/main.nf` + `workflow.buwf.json`

**For viewing examples**:
- Galaxy: `backend/galaxy_workflows_reformatted/` (50+ workflows)
- Nextflow: `backend/nf-core-workflows/` (subworkflows)
- BUWF: `main_generated/workflow.buwf.json` (generated)

**For testing**:
- Run: `research/scripts/test_api_integration.py`
- Checks all conversion paths

---

**Last Updated**: 2025-11-19
