# Biomni Galaxy Integration - Comprehensive Architecture

**Date**: December 1, 2025, 21:30 UTC
**Status**: Complete

---

## 1. Architecture Overview

### Component Hierarchy

```
┌─────────────────────────────────────────────────────────────────────┐
│                         BIOMNI GALAXY                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────┐    ┌─────────────────────────────────────┐│
│  │  ATOMIC TOOLS (241) │    │      WORKFLOWS                      ││
│  │  (XML wrappers)     │    │                                     ││
│  │                     │    │  ┌──────────────────┐               ││
│  │  ┌───────────────┐  │    │  │ Main Workflows   │               ││
│  │  │ Python (109)  │  │    │  │ (122 .ga files)  │               ││
│  │  │ - Biopython   │  │    │  │ in workflows/    │               ││
│  │  │ - Scanpy      │  │    │  └────────┬─────────┘               ││
│  │  │ - OpenCV      │  │    │           │ may include             ││
│  │  │ - RDKit       │  │    │           ▼                         ││
│  │  └───────────────┘  │    │  ┌──────────────────┐               ││
│  │                     │    │  │ Subworkflows     │               ││
│  │  ┌───────────────┐  │    │  │ (275 .ga files)  │               ││
│  │  │ R (58)        │  │◄───┼──│ in subworkflows/ │               ││
│  │  │ - DESeq2      │  │    │  └──────────────────┘               ││
│  │  │ - Seurat      │  │    │                                     ││
│  │  │ - ggplot2     │  │    └─────────────────────────────────────┘│
│  │  └───────────────┘  │                                           │
│  │                     │                                           │
│  │  ┌───────────────┐  │                                           │
│  │  │ CLI (74)      │  │                                           │
│  │  │ - samtools    │  │                                           │
│  │  │ - bwa         │  │                                           │
│  │  │ - blast       │  │                                           │
│  │  └───────────────┘  │                                           │
│  │                     │                                           │
│  └─────────────────────┘                                           │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Key Definitions

### 2.1 Tool-Function (Atomic Tool)

A **tool-function** is the smallest executable unit - a single call to an external library or CLI.

| Aspect | Description |
|--------|-------------|
| Definition | Single library function or CLI command |
| Examples | `SeqIO.read()`, `samtools view`, `DESeq()` |
| Galaxy Format | XML wrapper (`.xml`) |
| Location | `biomni_galaxy/tools/` |
| Total Count | **241** |

### 2.2 Biomni Function (Workflow)

A **Biomni function** is a Python function that orchestrates tool-functions.

| Aspect | Description |
|--------|-------------|
| Definition | Python function calling 1+ tool-functions |
| Examples | `annotate_celltype_scRNA()`, `interspecies_gene_conversion()` |
| Galaxy Format | Workflow file (`.ga`) |
| Location | `biomni_galaxy/workflows/` |
| Total Count | **295** functions (122 with workflows) |

### 2.3 Subworkflow

A **subworkflow** is a reusable workflow component that can be embedded in other workflows.

| Aspect | Description |
|--------|-------------|
| Definition | Standalone workflow designed for reuse |
| Galaxy Format | Workflow file (`.ga`) with `"subworkflow"` tag |
| Location | `biomni_galaxy/subworkflows/` |
| Total Count | **275** |

---

## 3. Updated Statistics

### 3.1 Component Counts

| Component | Count | Description |
|-----------|-------|-------------|
| Atomic Tools (XML) | 241 | Direct tool wrappers |
| - Python functions | 109 | Library function wrappers |
| - R functions | 58 | R package wrappers |
| - CLI tools | 74 | Command-line wrappers |
| Main Workflows (.ga) | 122 | Biomni function workflows |
| - Multi-step | 82 | Call 2+ tool-functions |
| - Single-step | 40 | Call 0-1 tool-functions |
| Subworkflows (.ga) | 275 | Reusable components |
| **Total .ga files** | **397** | 122 + 275 |

### 3.2 Documentation Quality

| Metric | Count | Percentage |
|--------|-------|------------|
| Total Biomni functions | 295 | 100% |
| With docstrings | 241 | 81.7% |
| With parameters documented | 285 | 96.6% |
| Missing documentation | 54 | 18.3% |

---

## 4. Single-Step Workflows Clarification

### Why 40 single-step workflows exist:

The 40 "single-step" workflows are Biomni functions that:
1. Call only 0-1 external tool-functions
2. BUT still provide value as named workflows because they:
   - Encapsulate domain-specific logic
   - Set default parameters appropriate for the domain
   - Provide a user-friendly interface name

### Examples:

```
biomni/biochemistry/one_site_model
  → Calls: np_zeros_like (1 tool)
  → Value: Encapsulates binding model formula with domain defaults

biomni/bioengineering/exp_decay
  → Calls: np_exp (1 tool)
  → Value: Drug release kinetics model with appropriate constants
```

### Decision Tree:

```
Is it a Biomni function?
├── YES → Create .ga workflow
│   ├── Multi-step (2+ tools) → Full workflow orchestration
│   └── Single-step (0-1 tools) → Named workflow with defaults
└── NO → Just use XML tool directly
```

---

## 5. Galaxy Nested Workflows (Subworkflows)

### How Galaxy Handles Subworkflows

Based on [Galaxy Documentation](https://training.galaxyproject.org/training-material/topics/galaxy-interface/tutorials/workflow-editor/workflows/subworkflow.html):

1. **Step Type**: A subworkflow is a step type in Galaxy workflows
2. **Embedding**: Workflows can include other workflows as steps
3. **Labeled Outputs**: Subworkflow outputs must have labels for connection
4. **Runtime Parameters**: Can expose parameters from nested workflows

### Subworkflow Step Definition:

```json
{
  "type": "subworkflow",
  "subworkflow": {
    "a_galaxy_workflow": "true",
    "name": "nested_workflow_name",
    "steps": { ... }
  },
  "input_connections": { ... },
  "label": "Step N: Run nested workflow"
}
```

### Current Biomni Subworkflow Structure:

```
subworkflows/
├── biochemistry/         (12 subworkflows)
├── bioengineering/       (15 subworkflows)
├── bioimaging/           (4 subworkflows)
├── biophysics/           (8 subworkflows)
├── cancer_biology/       (18 subworkflows)
├── cell_biology/         (25 subworkflows)
├── genetics/             (22 subworkflows)
├── genomics/             (35 subworkflows)
├── immunology/           (18 subworkflows)
├── microbiology/         (28 subworkflows)
├── molecular_biology/    (42 subworkflows)
├── pathology/            (15 subworkflows)
├── pharmacology/         (12 subworkflows)
├── physiology/           (8 subworkflows)
└── ... (more domains)
```

---

## 6. Documentation Sources in Biomni Code

### 6.1 Function Docstrings (Primary Source)

Biomni functions use numpy/sphinx style docstrings:

```python
def interspecies_gene_conversion(
    gene_list: list[str],
    source_species: str,
    target_species: str,
) -> str:
    """Convert ENSEMBL gene IDs between different species using BioMart.

    This function converts a list of ENSEMBL gene IDs from one species to their
    homologous counterparts in another species using the Ensembl BioMart database.

    Parameters
    ----------
    gene_list : list[str]
        List of ENSEMBL gene IDs to convert
    source_species : str
        Source species name. Supported: human, mouse, rat, zebrafish...
    target_species : str
        Target species name.

    Returns
    -------
    str
        Multi-line string containing the steps performed and file paths.

    Examples
    --------
    >>> gene_ids = ["ENSG00000007372", "ENSG00000181449"]
    >>> result = interspecies_gene_conversion(gene_ids, "human", "mouse")
    """
```

### 6.2 Type Annotations (Secondary Source)

Function signatures provide type information:

```python
def generate_gene_embeddings_with_ESM_models(
    ensembl_gene_ids: list[str],        # Required list of gene IDs
    model_name: str = "esm2_t6_8M_UR50D", # ESM model variant
    layer: int = 6,                       # Layer to extract embeddings from
    save_path: str | None = None,         # Optional output path
    batch_size: int = 1,                  # Processing batch size
    max_sequence_length: int = 1024,      # Max sequence length
) -> str:
```

### 6.3 Inline Comments (Tertiary Source)

Important logic is documented inline:

```python
# this is required for scvi/scanvi based classifier
ref_adata.layers["counts"] = ref_adata.X.copy()

# passing arguments this way decreases chance of LLM generation errors
flags = {
    "CELLTYPIST": CELLTYPIST,
    "KNN_BBKNN": KNN_BBKNN,
    ...
}
```

---

## 7. Database Schema (Updated)

### 7.1 Tool Functions Table

```sql
CREATE TABLE tool_functions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id TEXT UNIQUE NOT NULL,        -- "python/bio/SeqIO.read"
    name TEXT NOT NULL,                   -- Human-readable name
    tool_type TEXT NOT NULL,              -- 'python', 'r', 'cli'
    library TEXT NOT NULL,                -- 'biopython', 'deseq2'
    function TEXT NOT NULL,               -- 'SeqIO.read', 'DESeq'
    description TEXT,                     -- From library docs
    implementation TEXT,                  -- JSON call template
    xml_path TEXT,                        -- Path to XML wrapper
    created_at TIMESTAMP
);
```

### 7.2 Biomni Workflows Table (Enhanced)

```sql
CREATE TABLE biomni_workflows (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workflow_id TEXT UNIQUE NOT NULL,     -- "biomni/genomics/func_name"
    name TEXT NOT NULL,
    domain TEXT NOT NULL,
    description TEXT,                     -- Summary from docstring
    docstring TEXT,                       -- Full docstring
    parameters TEXT,                      -- JSON array of parameters
    returns TEXT,                         -- Return description
    tool_calls TEXT,                      -- JSON list of tool IDs
    is_multi_step BOOLEAN,
    ga_path TEXT,                         -- Path to .ga file
    created_at TIMESTAMP
);
```

---

## 8. Directory Structure (Final)

```
biomni_galaxy/
├── tools/                              # 241 XML wrappers
│   ├── python/                         # 109 Python tool-functions
│   │   ├── bio/                        # Biopython
│   │   ├── scanpy/                     # Scanpy
│   │   ├── cv2/                        # OpenCV
│   │   └── ...
│   ├── r/                              # 58 R tool-functions
│   │   ├── deseq2/                     # DESeq2
│   │   ├── seurat/                     # Seurat
│   │   └── ...
│   └── cli/                            # 74 CLI tool-functions
│       ├── samtools/
│       ├── bwa/
│       └── ...
│
├── workflows/                          # 122 main Biomni workflows
│   ├── genomics/
│   ├── bioimaging/
│   └── ...
│
├── subworkflows/                       # 275 reusable subworkflows
│   ├── genomics/
│   ├── bioimaging/
│   └── ...
│
├── biomni_tools_v2.db                  # SQLite database
├── biomni_function_docs.json           # Extracted documentation
├── BIOMNI_FUNCTION_DOCUMENTATION.md    # Documentation report
└── 20251201_2110_BIOMNI_GALAXY_TOOL_INDEX_COMPLETE.md
```

---

## 9. Galaxy vs Nextflow: Subworkflow Handling

### Critical Difference

| Aspect | Galaxy | Nextflow |
|--------|--------|----------|
| Storage | **Embedded inline** in parent workflow | **Separate files** with `include` |
| Reference | Full workflow JSON embedded in step | `include { workflow } from './path.nf'` |
| Reuse | Copy/paste or database `content_id` | File imports |
| File count | Single `.ga` with all embedded | Multiple `.nf` files |

### Galaxy Subworkflow Format (from IWC)

Real example from `research/official_iwc/workflows/transcriptomics/rnaseq-pe/rnaseq-pe.ga`:

```json
{
  "19": {
    "type": "subworkflow",
    "id": 19,
    "label": "Generate Unstranded Coverage",
    "name": "Get Uniquely mapped unstranded coverage",
    "input_connections": {
      "STAR BAM": {
        "id": 18,
        "input_subworkflow_step_id": 1,
        "output_name": "mapped_reads"
      }
    },
    "subworkflow": {
      "a_galaxy_workflow": "true",
      "format-version": "0.1",
      "name": "Get Uniquely mapped unstranded coverage",
      "steps": { ... }  // FULL workflow embedded here
    }
  }
}
```

### Biomni Strategy: Build-Time Embedding

Since Galaxy requires inline embedding but we want Nextflow-style reusability:

```
┌─────────────────────────────────────────────────────────────────┐
│  DEVELOPMENT TIME                                                │
│  ─────────────────                                               │
│  subworkflows/genomics/align_reads.ga    (separate, editable)   │
│  subworkflows/genomics/call_variants.ga  (separate, editable)   │
│  workflows/genomics/variant_pipeline.ga  (with references)      │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                    ┌───────────▼───────────┐
                    │  embed_subworkflows.py │
                    │  (build script)        │
                    └───────────┬───────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│  BUILD OUTPUT                                                    │
│  ────────────                                                    │
│  workflows/genomics/variant_pipeline.ga                          │
│    └── Contains full embedded subworkflows inline                │
└─────────────────────────────────────────────────────────────────┘
```

### Build Script Location

`scripts/embed_subworkflows.py` - Reads workflows with subworkflow references and embeds them inline.

### Subworkflow Reference Format (Development)

```json
{
  "1": {
    "type": "subworkflow_reference",
    "label": "Run Alignment",
    "subworkflow_path": "genomics/align_reads.ga",
    "input_connections": {
      "reads": {"id": 0, "output_name": "output"}
    }
  }
}
```

This gets converted to Galaxy's native `"type": "subworkflow"` with full embedding during build.

---

## 10. Sources

- [Galaxy Workflow Modules Documentation](https://docs.galaxyproject.org/en/master/_modules/galaxy/workflow/modules.html)
- [Galaxy Subworkflow Tutorial](https://training.galaxyproject.org/training-material/topics/galaxy-interface/tutorials/workflow-editor/workflows/subworkflow.html)
- [Galaxy Workflow Format 2](https://galaxyproject.github.io/gxformat2/v19_09.html)
- [Creating Workflows - Galaxy Hub](https://galaxyproject.org/learn/advanced-workflow/)

---

*Generated by Claude Code on December 1, 2025*
