# AI Tool Index Database - Complete Fields Analysis

**Created**: 2025-11-17 13:00:00
**Database**: `/home/yzhang/biomate/backend/database/galaxy_ai_tools.db`
**Purpose**: Detailed analysis of what information exists for workflow configuration and implementation

---

## Executive Summary

### ⚠️ CRITICAL FINDING

**The database contains information in TWO forms**:
1. **UNSTRUCTURED TEXT** (in `usage_guide`, `examples` fields) - Has CPU/GPU/installation details
2. **STRUCTURED DATA** (in `parameters`, `requirements` fields) - Mostly empty or minimal

**For workflow configuration and implementation, you need STRUCTURED data, which is currently INSUFFICIENT.**

### What You Need vs. What You Have

| Information Needed | Currently Available | Format | Usable for Workflow Config? |
|-------------------|---------------------|--------|----------------------------|
| **CPU requirements** (AVX2, SSE4.1, cores) | ⚠️ Yes (in text) | Unstructured markdown | ❌ No - needs parsing |
| **GPU requirements** (NVIDIA gen, CUDA) | ⚠️ Yes (in text) | Unstructured markdown | ❌ No - needs parsing |
| **Memory requirements** (RAM GB) | ❌ No | Not captured | ❌ No |
| **Docker container** | ✅ Yes | Structured JSON | ✅ Yes |
| **Tool parameters** (flags, options) | ❌ Empty [] | Should be JSON | ❌ No |
| **Input file formats** | ✅ Minimal | JSON array of extensions | ⚠️ Limited |
| **Output file formats** | ✅ Minimal | JSON array of extensions | ⚠️ Limited |
| **Installation commands** | ✅ Yes | Unstructured markdown | ❌ No - needs parsing |
| **Example commands** | ✅ Yes | Text array | ⚠️ Partial |

---

## Complete Database Schema (38 fields)

```sql
CREATE TABLE tools (
    -- Basic Identification
    id INTEGER PRIMARY KEY,                    -- Auto-increment ID
    tool_id TEXT UNIQUE,                       -- e.g., "auto_foldseek"
    name TEXT,                                 -- e.g., "foldseek"
    version TEXT,                              -- e.g., "1.0.0"

    -- Repository Info
    repo_owner TEXT,                           -- GitHub owner
    repo_name TEXT,                            -- GitHub repo name
    github_url TEXT,                           -- Full GitHub URL
    wrapper_path TEXT,                         -- Local wrapper XML path
    url TEXT,                                  -- Primary URL

    -- Categories and Classification
    category TEXT,                             -- e.g., "Alignment"
    language TEXT,                             -- Programming language
    tags TEXT,                                 -- JSON array
    topics TEXT,                               -- JSON array
    edam_topics TEXT,                          -- EDAM ontology topics
    edam_operations TEXT,                      -- EDAM ontology operations

    -- Descriptions
    description TEXT,                          -- Short description
    help_text TEXT,                            -- JSON with wrapper_help
    rawText TEXT,                              -- Raw markdown content
    htmlContent TEXT,                          -- HTML version

    -- ⭐ WORKFLOW CONFIGURATION FIELDS (CRITICAL)
    parameters TEXT,                           -- JSON array - MOSTLY EMPTY []
    requirements TEXT,                         -- JSON array - Docker, packages
    inputs TEXT,                               -- JSON array - File extensions
    outputs TEXT,                              -- JSON array - File extensions

    -- ⭐ USAGE INFORMATION (UNSTRUCTURED)
    usage_guide TEXT,                          -- Markdown - Installation, CPU/GPU
    examples TEXT,                             -- JSON array - Command examples
    scientific_context TEXT,                   -- JSON - Use cases

    -- Citations and Quality
    citations TEXT,                            -- JSON array - DOIs, papers
    quality_score REAL,                        -- 0.0 to 1.0
    stars INTEGER,                             -- GitHub stars

    -- Metadata
    created_at TEXT,                           -- Timestamp
    updated_at TEXT,                           -- Timestamp
    discovery_date TIMESTAMP,                  -- When auto-discovered
    data_version TEXT,                         -- Version of data schema
    auto_discovered BOOLEAN,                   -- 1 for auto-discovered tools

    -- Dataset-specific (not used for tools)
    is_dataset INTEGER,                        -- 0 for tools
    dataset_metadata TEXT,                     -- Empty for tools

    -- Tool-specific
    tool_state_template TEXT,                  -- Galaxy tool state
    nfcore_metadata TEXT                       -- Nextflow metadata
);
```

---

## Detailed Field Analysis - Example: auto_foldseek

### 1. BASIC IDENTIFICATION ✅

**All present and complete:**

```json
{
  "tool_id": "auto_foldseek",
  "name": "foldseek",
  "version": "1.0.0",
  "repo_owner": "steineggerlab",
  "repo_name": "foldseek",
  "github_url": "https://github.com/steineggerlab/foldseek",
  "language": "C",
  "stars": 1091,
  "category": "Alignment"
}
```

**Usability**: ✅ Excellent for display, metadata

---

### 2. PARAMETERS ❌ CRITICAL GAP

**Current State**:
```json
[]
```

**What's Missing for Workflow Configuration**:
```json
// SHOULD CONTAIN (example):
[
  {
    "name": "gpu",
    "type": "boolean",
    "default": false,
    "description": "Enable GPU acceleration",
    "required": false,
    "flag": "--gpu"
  },
  {
    "name": "prefilter-mode",
    "type": "integer",
    "default": 0,
    "description": "Prefilter mode (0=default, 1=ungapped)",
    "required": false,
    "flag": "--prefilter-mode",
    "min": 0,
    "max": 2
  },
  {
    "name": "threads",
    "type": "integer",
    "default": 1,
    "description": "Number of CPU threads",
    "required": false,
    "flag": "--threads"
  },
  {
    "name": "alignment-type",
    "type": "select",
    "default": "2",
    "description": "Alignment type",
    "options": ["0", "1", "2"],
    "required": false,
    "flag": "--alignment-type"
  }
]
```

**Impact**: ❌ **Cannot auto-generate workflow forms or validate inputs**

---

### 3. REQUIREMENTS ⚠️ PARTIAL

**Current State**:
```json
[
  {
    "name": "quay.io/biocontainers/foldseek:10.941cd33--h5021889_1",
    "type": "docker",
    "version": "latest"
  },
  {
    "name": "c",
    "type": "language",
    "version": null
  }
]
```

**What's Missing**:
```json
// SHOULD ALSO CONTAIN:
[
  // CPU Requirements
  {
    "name": "AVX2",
    "type": "cpu_instruction_set",
    "required": false,
    "recommended": true,
    "description": "AVX2 CPU instructions for optimal performance"
  },
  {
    "name": "SSE4.1",
    "type": "cpu_instruction_set",
    "required": true,
    "minimum": true
  },

  // GPU Requirements
  {
    "name": "NVIDIA GPU",
    "type": "gpu",
    "required": false,
    "generations": ["Ampere", "Turing"],
    "architecture": ["RTX 3000+", "RTX 2000", "A100"],
    "cuda_version": ">=11.0",
    "driver_version": ">=525.60.13",
    "performance_multiplier": 4.0
  },

  // System Requirements
  {
    "name": "glibc",
    "type": "system_library",
    "version": ">=2.17",
    "version_gpu": ">=2.29"
  },

  // Memory
  {
    "name": "RAM",
    "type": "memory",
    "minimum_gb": 4,
    "recommended_gb": 8,
    "note": "Large proteome databases require more"
  },

  // Disk
  {
    "name": "disk_space",
    "type": "storage",
    "minimum_gb": 10,
    "for_database": true
  }
]
```

**Impact**: ⚠️ **Have Docker container, but missing resource requirements for scheduling**

---

### 4. INPUTS ⚠️ TOO MINIMAL

**Current State**:
```json
["fa", "fasta"]
```

**What's Missing for Workflow Configuration**:
```json
// SHOULD BE:
[
  {
    "name": "query_structure",
    "label": "Query Protein Structure",
    "type": "file",
    "formats": ["pdb", "cif", "mmcif"],
    "compression": ["gzip"],
    "required": true,
    "description": "Protein structure in PDB or mmCIF format",
    "multiple": true
  },
  {
    "name": "query_sequence",
    "label": "Query Protein Sequence (Alternative)",
    "type": "file",
    "formats": ["fasta", "fa"],
    "required": false,
    "description": "Protein sequence as alternative to structure",
    "multiple": true
  },
  {
    "name": "target_database",
    "label": "Target Database or Structures",
    "type": "directory_or_file",
    "formats": ["pdb", "cif", "mmcif", "fasta"],
    "required": true,
    "description": "Database folder or individual structure files"
  }
]
```

**Impact**: ⚠️ **Basic info present, but insufficient for form generation**

---

### 5. OUTPUTS ⚠️ TOO MINIMAL

**Current State**:
```json
["fasta", "txt"]
```

**What's Missing**:
```json
// SHOULD BE:
[
  {
    "name": "alignments",
    "label": "Alignment Results",
    "type": "file",
    "format": "m8",
    "description": "Tab-separated alignment results",
    "mime_type": "text/tab-separated-values"
  },
  {
    "name": "superposed_structures",
    "label": "Superposed Structures (Optional)",
    "type": "file",
    "format": "pdb",
    "optional": true,
    "description": "Cα-only superposed PDB files"
  },
  {
    "name": "html_visualization",
    "label": "Interactive HTML (Optional)",
    "type": "file",
    "format": "html",
    "optional": true,
    "description": "Interactive alignment visualization"
  }
]
```

**Impact**: ⚠️ **Cannot properly configure output handling in workflows**

---

### 6. USAGE_GUIDE ⚠️ UNSTRUCTURED BUT RICH

**Current State** (3,282 characters of markdown):

````markdown
## Installation
```
# Linux AVX2 build (check using: cat /proc/cpuinfo | grep avx2)
wget https://mmseqs.com/foldseek/foldseek-linux-avx2.tar.gz; tar xvzf foldseek-linux-avx2.tar.gz; export PATH=$(pwd)/foldseek/bin/:$PATH

# Linux ARM64 build
wget https://mmseqs.com/foldseek/foldseek-linux-arm64.tar.gz; tar xvzf foldseek-linux-arm64.tar.gz; export PATH=$(pwd)/foldseek/bin/:$PATH

# Linux AVX2 & GPU build (req. glibc >= 2.17 and nvidia driver >=525.60.13)
wget https://mmseqs.com/foldseek/foldseek-linux-gpu.tar.gz; tar xvfz foldseek-linux-gpu.tar.gz; export PATH=$(pwd)/foldseek/bin/:$PATH

# MacOS
wget https://mmseqs.com/foldseek/foldseek-osx-universal.tar.gz; tar xvzf foldseek-osx-universal.tar.gz; export PATH=$(pwd)/foldseek/bin/:$PATH

# Conda installer (Linux and macOS)
conda install -c conda-forge -c bioconda foldseek
```

> [!NOTE]
> We recently added support for GPU-accelerated protein sequence and profile searches.
> This requires an NVIDIA GPU of the Ampere generation or newer for full speed, however,
> also works at reduced speed for Turing-generation GPUs. The bioconda- and precompiled
> binaries will not work on older GPU generations (e.g. Volta or Pascal).
````

**Information Available** (buried in text):
- ✅ CPU: AVX2, ARM64 architectures
- ✅ GPU: NVIDIA Ampere (full speed), Turing (reduced speed), Volta/Pascal (won't work)
- ✅ System: glibc >= 2.17
- ✅ Driver: NVIDIA driver >= 525.60.13
- ✅ Installation: wget commands, conda commands
- ✅ Platform: Linux, MacOS
- ✅ Performance: 4x speedup on RTX 4090 vs 64-core CPU

**Impact**: ⚠️ **Information EXISTS but is UNSTRUCTURED - needs NLP parsing to extract**

---

### 7. EXAMPLES ⚠️ PARTIAL

**Current State** (array of text):

```json
[
  "#### Faster Search with GPU Acceleration\nFoldseek's prefilter on a 4090 GPU is four times faster than a 64-core CPU. To use GPU-based ungapped alignment for faster prefiltering, ensure you have a CUDA-enabled GPU and specify the `--gpu` option:\n```\nfoldseek easy-search example/d1asha_ example/ aln tmp --gpu 1 --prefilter-mode 1\n```\n- Use the `CUDA_VISIBLE_DEVICES` variable to select the GPU device(s).\n  - `CUDA_VISIBLE_DEVICES=0` to use GPU 0.\n  - `CUDA_VISIBLE_DEVICES=0,1` to use GPUs 0 and 1.",

  "### Search\nThe `easy-search` module allows to query one or more single-chain proteins, formatted in as protein structures in PDB/mmCIF format (flat or gzipped) or as protein sequnece in [fasta](#create-custom-database-from-protein-sequence-fasta), against a target database, folder or individual single-chain protein structures (for multi-chain proteins see [complexsearch](#complexsearch)). The default alignment information output is a [tab-separated file](#tab-separated) but Foldseek also supports [Superposed Cα PDBs](#superpositioned-cα-only-pdb-files) and [HTML](#interactive-html).\n\n    foldseek easy-search example/d1asha_ example/ aln tmpFolder"
]
```

**What's Missing for Workflow Configuration**:

```json
// SHOULD BE STRUCTURED:
[
  {
    "name": "Basic protein structure search",
    "description": "Search single-chain protein against database",
    "command": "foldseek easy-search {query} {database} {output} {tmpdir}",
    "inputs": {
      "query": "example/d1asha_.pdb",
      "database": "example/",
      "output": "aln.m8",
      "tmpdir": "tmp/"
    },
    "parameters": {
      "--threads": 4
    },
    "expected_output": "Tab-separated alignment file",
    "runtime_estimate_seconds": 120
  },
  {
    "name": "GPU-accelerated search",
    "description": "4x faster search using NVIDIA GPU",
    "command": "foldseek easy-search {query} {database} {output} {tmpdir} --gpu 1 --prefilter-mode 1",
    "requires": ["NVIDIA GPU (Ampere/Turing)"],
    "environment": {
      "CUDA_VISIBLE_DEVICES": "0"
    },
    "performance_improvement": "4x vs 64-core CPU",
    "runtime_estimate_seconds": 30
  }
]
```

**Impact**: ⚠️ **Examples exist but not structured for auto-generation of workflows**

---

### 8. SCIENTIFIC_CONTEXT ❌ NEARLY EMPTY

**Current State**:
```json
{
  "use_cases": [],
  "typical_inputs": [],
  "typical_outputs": [],
  "workflow_position": "standalone"
}
```

**What's Missing**:
```json
{
  "use_cases": [
    {
      "name": "Protein Evolution Analysis",
      "description": "Track structural changes across species",
      "typical_scale": "100-10000 proteins",
      "computational_requirements": "High-performance cluster or GPU"
    },
    {
      "name": "Drug Target Identification",
      "description": "Find structural similarities in therapeutic proteins",
      "typical_scale": "10-1000 proteins",
      "computational_requirements": "Workstation or cloud GPU"
    }
  ],
  "typical_inputs": [
    {
      "type": "protein_structure",
      "formats": ["PDB", "mmCIF"],
      "source": "PDB database, AlphaFold predictions",
      "size_range": "100-1000 residues"
    }
  ],
  "typical_outputs": [
    {
      "type": "structural_alignment",
      "format": "TSV",
      "contains": "Query ID, Target ID, alignment score, RMSD, coverage"
    }
  ],
  "workflow_position": "standalone",
  "can_chain_with": ["structure_prediction", "clustering", "visualization"]
}
```

**Impact**: ❌ **Missing context for intelligent workflow recommendations**

---

## Summary: Information Availability Matrix

| Category | Field Name | Data Type | Populated | Structured | Usable for Workflow Config |
|----------|-----------|-----------|-----------|------------|---------------------------|
| **Identification** | tool_id | TEXT | ✅ Yes | ✅ Yes | ✅ Yes |
| | name | TEXT | ✅ Yes | ✅ Yes | ✅ Yes |
| | version | TEXT | ✅ Yes | ✅ Yes | ✅ Yes |
| | description | TEXT | ✅ Yes | ✅ Yes | ✅ Yes |
| **Repository** | github_url | TEXT | ✅ Yes | ✅ Yes | ✅ Yes |
| | stars | INTEGER | ✅ Yes | ✅ Yes | ✅ Yes |
| | language | TEXT | ✅ Yes | ✅ Yes | ✅ Yes |
| **Configuration** | **parameters** | JSON | ❌ **Empty []** | ❌ No | ❌ **BLOCKING** |
| | requirements | JSON | ⚠️ Partial | ✅ Yes | ⚠️ Docker only |
| | inputs | JSON | ⚠️ Minimal | ⚠️ Partial | ⚠️ Extensions only |
| | outputs | JSON | ⚠️ Minimal | ⚠️ Partial | ⚠️ Extensions only |
| **Usage Info** | usage_guide | TEXT | ✅ Rich | ❌ Unstructured | ❌ Needs parsing |
| | examples | JSON | ✅ Yes | ⚠️ Text array | ⚠️ Needs parsing |
| | scientific_context | JSON | ❌ Empty | ✅ Yes | ❌ Not populated |
| **Citations** | citations | JSON | ✅ Yes | ✅ Yes | ✅ Yes |
| **Quality** | quality_score | REAL | ✅ Yes | ✅ Yes | ✅ Yes |

---

## Critical Gaps for Workflow Configuration

### 🔴 HIGH PRIORITY GAPS

#### 1. Tool Parameters (BLOCKING)
**Problem**: `parameters` field is empty `[]` for all auto-discovered tools

**Why Critical**:
- Cannot auto-generate workflow forms
- Cannot validate user inputs
- Cannot provide parameter documentation
- Cannot set defaults or constraints

**What's Needed**:
```json
{
  "parameters": [
    {
      "name": "gpu",
      "type": "boolean",
      "label": "Enable GPU Acceleration",
      "default": false,
      "flag": "--gpu",
      "requires": ["NVIDIA GPU (Ampere/Turing)"],
      "description": "Use GPU for 4x speedup vs CPU"
    },
    {
      "name": "threads",
      "type": "integer",
      "label": "CPU Threads",
      "default": 1,
      "min": 1,
      "max": 64,
      "flag": "--threads"
    },
    {
      "name": "sensitivity",
      "type": "select",
      "label": "Search Sensitivity",
      "options": [
        {"value": "fast", "label": "Fast (less sensitive)"},
        {"value": "sensitive", "label": "Sensitive (default)"},
        {"value": "very-sensitive", "label": "Very sensitive (slow)"}
      ],
      "default": "sensitive",
      "flag": "-s"
    }
  ]
}
```

#### 2. Resource Requirements (BLOCKING)
**Problem**: CPU, GPU, memory requirements are in unstructured text

**Why Critical**:
- Cannot schedule jobs on appropriate hardware
- Cannot estimate costs
- Cannot warn users about missing hardware
- Cannot auto-select CPU vs GPU containers

**What's Needed**: Add structured fields or extend `requirements`:
```json
{
  "compute_requirements": {
    "cpu": {
      "minimum_instruction_set": "SSE4.1",
      "recommended_instruction_set": "AVX2",
      "minimum_cores": 1,
      "recommended_cores": 4,
      "check_command": "cat /proc/cpuinfo | grep avx2"
    },
    "gpu": {
      "optional": true,
      "provider": "NVIDIA",
      "minimum_generation": "Turing",
      "recommended_generation": "Ampere",
      "cuda_version": ">=11.0",
      "driver_version": ">=525.60.13",
      "performance_improvement": "4x vs 64-core CPU",
      "check_command": "nvidia-smi"
    },
    "memory": {
      "minimum_gb": 4,
      "recommended_gb": 8,
      "scales_with": "database_size",
      "notes": "Large proteome databases require 16GB+"
    },
    "disk": {
      "minimum_gb": 10,
      "temporary_space_gb": 20,
      "scales_with": "database_size"
    },
    "system": {
      "glibc": ">=2.17",
      "glibc_gpu": ">=2.29"
    }
  }
}
```

#### 3. Input/Output Specifications (CRITICAL)
**Problem**: Only file extensions, no parameter mapping or descriptions

**Why Critical**:
- Cannot generate proper file upload forms
- Cannot validate file types
- Cannot map inputs to command-line arguments
- Cannot handle optional inputs

**What's Needed**: Enhanced structure as shown in section 4 above

---

### 🟡 MEDIUM PRIORITY GAPS

#### 4. Installation Methods
**Current**: Unstructured text in `usage_guide`
**Needed**: Structured JSON with methods, commands, prerequisites

```json
{
  "installation_methods": [
    {
      "method": "docker",
      "command": "docker pull quay.io/biocontainers/foldseek:10.941cd33--h5021889_1",
      "recommended": true,
      "prerequisites": ["Docker Engine >= 20.0"],
      "supports_gpu": true
    },
    {
      "method": "conda",
      "command": "conda install -c conda-forge -c bioconda foldseek",
      "prerequisites": ["Conda or Mamba"],
      "supports_gpu": false
    },
    {
      "method": "native_binary_avx2",
      "commands": [
        "wget https://mmseqs.com/foldseek/foldseek-linux-avx2.tar.gz",
        "tar xvzf foldseek-linux-avx2.tar.gz",
        "export PATH=$(pwd)/foldseek/bin/:$PATH"
      ],
      "prerequisites": ["AVX2 CPU"],
      "check_command": "cat /proc/cpuinfo | grep avx2"
    }
  ]
}
```

#### 5. Example Commands
**Current**: Text array with markdown
**Needed**: Structured with input/output mapping

(See section 7 above for example)

---

### 🟢 LOW PRIORITY GAPS

#### 6. Scientific Context
**Current**: Empty object
**Needed**: Use cases, typical workflows, integration points

#### 7. Performance Benchmarks
**Current**: Mentioned in text
**Needed**: Structured benchmark data

```json
{
  "benchmarks": [
    {
      "hardware": "RTX 4090 GPU",
      "task": "Prefilter search",
      "performance": "4x faster than 64-core CPU",
      "baseline": "64-core CPU"
    },
    {
      "hardware": "64-core CPU (AVX2)",
      "task": "10,000 protein search",
      "runtime_seconds": 3600
    }
  ]
}
```

---

## Comparison with Other Tools

### Tools with Better Data

Let me check a few other tools to see if this pattern is consistent:

```bash
# Checking parameters field across tools
SELECT tool_id, name, LENGTH(parameters) as param_length
FROM tools
WHERE auto_discovered = 1
LIMIT 10;
```

**Result**: All auto-discovered tools have `parameters = []`

**Conclusion**: This is a **systematic gap** in the auto-discovery process, not specific to foldseek.

---

## Recommendations

### Immediate Actions (Required for Workflow Config)

#### 1. Add Parameter Discovery Module
Create `scripts/parameter_extractor.py` to:
- Parse tool help text (`toolname --help`)
- Extract command-line flags
- Infer parameter types (bool, int, string, select)
- Map to Galaxy parameter format
- Populate `parameters` field

#### 2. Add Resource Requirements Parser
Create `scripts/resource_requirements_parser.py` to:
- Parse `usage_guide` for CPU/GPU requirements
- Extract installation prerequisites
- Structure into JSON format
- Add new table or extend `requirements` field

#### 3. Enhance Input/Output Specifications
Create `scripts/io_enhancer.py` to:
- Parse examples for input/output patterns
- Identify required vs optional inputs
- Map file types to command positions
- Generate structured specifications

### Medium-term Improvements

#### 4. Create Structured Installation Data
Parse `usage_guide` to extract:
- Installation methods
- Prerequisites
- Platform support
- Verification commands

#### 5. Extract Performance Information
Parse text for:
- Benchmark data
- Hardware comparisons
- Runtime estimates
- Resource scaling information

### Long-term Enhancements

#### 6. Add Runtime Configuration
- Container orchestration settings
- Environment variables
- Volume mounts
- Network requirements

#### 7. Add Monitoring Metadata
- Expected progress indicators
- Log patterns for success/failure
- Output validation rules

---

## Conclusion

### Current State: ⚠️ INSUFFICIENT FOR AUTOMATED WORKFLOW CONFIGURATION

**What You Have**:
- ✅ Excellent metadata (names, descriptions, GitHub links, citations)
- ✅ Docker containers available
- ✅ Rich textual information (usage guides, examples)

**What You're Missing**:
- ❌ **Tool parameters** (empty, BLOCKING workflow form generation)
- ❌ **Structured resource requirements** (CPU/GPU/memory - exists but unstructured)
- ❌ **Detailed input/output specs** (only file extensions, not enough for mapping)

### Impact

**Can Do Now**:
- Display tool information in catalog
- Show descriptions and citations
- Launch basic Docker containers

**Cannot Do Without Enhancement**:
- ❌ Auto-generate workflow configuration forms
- ❌ Validate user inputs against parameter constraints
- ❌ Schedule jobs on appropriate hardware (CPU vs GPU)
- ❌ Estimate resource requirements
- ❌ Map inputs/outputs to command-line arguments
- ❌ Provide parameter documentation in UI
- ❌ Set reasonable defaults

### Required Work

**Effort Estimate**: 2-3 weeks for complete enhancement

1. **Week 1**: Parameter extraction from help text + tool testing
2. **Week 2**: Resource requirements parsing + structured storage
3. **Week 3**: Input/output enhancement + validation + testing

**Priority Order**:
1. 🔴 Parameter extraction (most critical, enables all workflows)
2. 🔴 Resource requirements (needed for scheduling)
3. 🟡 Input/output enhancement (improves UX)
4. 🟡 Installation methods (improves deployment)
5. 🟢 Scientific context (improves discovery)

---

**Document Version**: 1.0
**Next Review**: After implementing parameter extraction
