# Galaxy AI Tools Database Schema Documentation

**Date:** October 30, 2025
**Database:** `database/galaxy_ai_tools.db`
**Size:** 162 MB
**Total Tools:** 9,212 tools

---

## Overview

The Galaxy AI Tools database contains comprehensive information about bioinformatics tools from multiple sources:
- **Galaxy ToolShed**: 8,981 tools (Galaxy tool wrappers)
- **nf-core Modules**: 231 modules (Nextflow wrappers, after merging 103 duplicates)

**Key Feature:** The database clearly distinguishes between wrappers/modules (Galaxy tools, nf-core modules) and the underlying software they wrap, with explicit function metadata for each wrapper.

---

## Database Schema

### Table: `tools`

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key (auto-increment) |
| `tool_id` | TEXT | Unique identifier (e.g., `toolshed.g2.bx.psu.edu/repos/devteam/fastqc/Repository_Actions_FastQC`) |
| `name` | TEXT | Wrapper name (e.g., "FastQC", "FastQC Summary") |
| `version` | TEXT | **Wrapper version** (e.g., "0.74+galaxy1") |
| `repo_owner` | TEXT | Repository owner (e.g., "devteam") |
| `repo_name` | TEXT | Repository name |
| `category` | TEXT | Tool category (e.g., "Sequence Analysis", "nf-core") |
| `rawText` | TEXT | Raw documentation text from source |
| `htmlContent` | TEXT | HTML documentation content |
| `url` | TEXT | Homepage/documentation URL |
| `created_at` | TEXT | Creation timestamp |
| `updated_at` | TEXT | Update timestamp |
| `data_version` | TEXT | Data version |
| `is_dataset` | INTEGER | Whether this is a dataset (0/1) |
| `dataset_metadata` | TEXT | JSON metadata for datasets |
| `parameters` | TEXT | **JSON array of parameter schemas** |
| `help_text` | TEXT | **JSON object with structured help** |
| `inputs` | TEXT | **JSON array of input specifications** |
| `outputs` | TEXT | **JSON array of output specifications** |
| `requirements` | TEXT | **JSON array of software requirements** |
| `tool_state_template` | TEXT | Default tool state template |
| `description` | TEXT | Tool description (text) |
| `citations` | TEXT | **JSON array of citations** |
| `edam_operations` | TEXT | **JSON array of EDAM ontology terms** |
| `edam_topics` | TEXT | JSON array of EDAM topics |
| `tags` | TEXT | **JSON array of tags/keywords** |
| `examples` | TEXT | **JSON array of usage examples** |
| `usage_guide` | TEXT | Tutorial/usage guide (text) |

---

## Critical Distinction: Wrapper vs Underlying Software

Each database entry represents a **wrapper/module** (Galaxy tool or nf-core module), NOT the underlying software itself.

### Example: FastQC

**8 different wrappers exist for FastQC software:**

#### Primary Analysis Wrappers (run FastQC):
1. **FastQC** (devteam)
   - `tool_id`: `toolshed.g2.bx.psu.edu/repos/devteam/fastqc/...`
   - `version`: `"0.74+galaxy1"` ← **Wrapper version**
   - `requirements`: `[{"name": "fastqc", "version": "0.12.1", "type": "package"}]` ← **Software version**
   - `help_text.function_info.wrapper_function`: `"Perform primary analysis"`
   - `help_text.function_info.is_primary_function`: `true`

2. **FastQC Sequence Analyzer** (duijker.d)
3. **aurora_fastqc** (mingchen0919) - RNA-specific
4. **sum_fastqc** (estrain)

#### Post-processing Wrapper (processes FastQC results):
5. **FastQC Summary** (nml)
   - `help_text.function_info.wrapper_function`: `"Summarize or aggregate results from the base tool"`
   - `help_text.function_info.operation_type`: `"post_processing"`
   - `help_text.function_info.is_primary_function`: `false`

#### Visualization Wrappers (display FastQC results):
6. **Fastqc Site** (mingchen0919)
   - `help_text.function_info.wrapper_function`: `"Generate website/portal with results"`
   - `help_text.function_info.operation_type`: `"visualization"`

7. **Fastqc report** (mingchen0919)
8. **aurora_fastqc_site** (mingchen0919)

---

## JSON Field Structures

### 1. `parameters` - Parameter Schema Array

```json
[
  {
    "name": "input_file",
    "label": "Input FASTQ file",
    "type": "data",
    "format": "fastq",
    "help": "Single or paired-end reads",
    "optional": false,
    "source": "rawText"
  },
  {
    "name": "contaminant_list",
    "label": "Contaminant sequences",
    "type": "data",
    "help": "Tab-delimited file with adapter sequences",
    "optional": true,
    "source": "rawText"
  }
]
```

### 2. `help_text` - Structured Help Object

```json
{
  "what_it_does": "Description of tool purpose",
  "how_to_use": "Usage instructions",
  "input_description": "Input format details",
  "output_description": "Output format details",
  "examples": "Example usage",
  "keywords": ["qc", "quality control", "fastq"],
  "homepage": "https://www.bioinformatics.babraham.ac.uk/projects/fastqc/",
  "documentation": "https://www.bioinformatics.babraham.ac.uk/projects/fastqc/Help/",
  "function_info": {
    "underlying_software": "fastqc",
    "wrapper_name": "FastQC",
    "wrapper_function": "Perform primary analysis",
    "operation_type": "primary_analysis",
    "is_primary_function": true
  }
}
```

### 3. `inputs` - Input Specifications

**Galaxy Tools (simple list):**
```json
["bam", "sam", "fastq", "fastq.gz"]
```

**nf-core Modules (structured):**
```json
[
  {
    "name": "reads",
    "type": "file",
    "description": "List of input FastQ files for single-end or paired-end data",
    "pattern": "*.{fastq,fq,fastq.gz,fq.gz}",
    "ontologies": [],
    "formats": ["fastq", "fq", "fastq.gz", "fq.gz"]
  }
]
```

### 4. `outputs` - Output Specifications

**Galaxy Tools (simple list):**
```json
["html", "zip", "txt"]
```

**nf-core Modules (structured):**
```json
[
  {
    "name": "html",
    "type": "file",
    "description": "FastQC HTML report",
    "pattern": "*_fastqc.html",
    "ontologies": [{"edam": "http://edamontology.org/format_2331"}],
    "formats": ["html"]
  },
  {
    "name": "zip",
    "type": "file",
    "description": "FastQC report archive",
    "pattern": "*_fastqc.zip",
    "ontologies": [],
    "formats": ["zip"]
  }
]
```

### 5. `requirements` - Software Dependencies

```json
[
  {
    "name": "fastqc",
    "version": "0.12.1",
    "type": "package"
  },
  {
    "name": "bioconda::fastqc",
    "version": "0.12.1",
    "type": "conda"
  }
]
```

### 6. `citations` - References

```json
[
  {
    "type": "doi",
    "value": "10.1093/bioinformatics/btv351"
  },
  {
    "type": "pmid",
    "value": "26059717"
  }
]
```

### 7. `examples` - Usage Examples

```json
[
  "fastqc sample_R1.fastq sample_R2.fastq",
  "for file in *.fastq; do fastqc $file; done",
  "Usage condition: task.ext.when == null || task.ext.when"
]
```

### 8. `edam_operations` - EDAM Ontology Terms

```json
[
  "http://edamontology.org/operation_3218",
  "http://edamontology.org/format_3750"
]
```

---

## Operation Types

Tools are categorized by operation type to distinguish different functions:

| Operation Type | Count | Description | Examples |
|----------------|-------|-------------|----------|
| `primary_analysis` | 7,397 | Run the main software function | FastQC, BLAST, BWA |
| `data_manipulation` | 955 | Filter, select, extract data | Filter VCF, Select reads |
| `visualization` | 450 | Generate reports, plots, websites | FastQC Site, IGV Reports |
| `format_conversion` | 231 | Convert between formats | BAM to SAM, FASTQ to FASTA |
| `batch_processing` | 100 | Batch/parallel versions | Multi-sample FastQC |
| `post_processing` | 79 | Summarize, aggregate results | FastQC Summary, Aggregate stats |

---

## Data Coverage Statistics

| Field | Coverage | Description |
|-------|----------|-------------|
| Parameters | 8,903 (96.6%) | Full parameter schemas extracted |
| Descriptions | 9,192 (99.8%) | Tool purpose and functionality |
| Input formats | 6,516 (70.7%) | Accepted file formats |
| Output formats | 5,822 (63.2%) | Generated file formats |
| Requirements | 9,294 (100.9%) | Software dependencies |
| Examples | 1,165 (12.6%) | Usage examples and code |
| Function metadata | 9,212 (100%) | Wrapper vs software distinction |
| EDAM operations | 328 (3.6%) | Ontology terms |

---

## Extraction Sources

### Galaxy ToolShed Tools (8,981 tools)
**Extracted from:**
- Tool XML files (via API)
- rawText and htmlContent fields
- Galaxy Tool Shed metadata

**Extracted information:**
- Parameter schemas (from XML structure)
- Input/Output formats (from patterns and descriptions)
- Requirements (from XML requirements section)
- Descriptions and examples (from help text)
- Citations (DOI, PMID patterns)
- Version information

### nf-core Modules (231 tools after merging)
**Extracted from:**
- `meta.yml` - Module metadata
- `environment.yml` - Conda/pip dependencies
- `main.nf` - Nextflow script with command templates

**Extracted information:**
- Structured input/output specifications
- EDAM ontology terms
- Exact software versions from conda
- Command examples from Nextflow templates
- Authors and maintainers
- Homepage and documentation URLs

---

## Merging Strategy

When a tool exists in both Galaxy and nf-core (103 tools merged):

1. **Keep Galaxy tool as primary** (has full parameter schemas, Galaxy integration)
2. **Merge nf-core metadata:**
   - Better descriptions (if more detailed)
   - Examples (nf-core has better command examples)
   - Structured I/O details
   - EDAM ontology terms
   - Exact version info from conda
   - Homepage URLs
3. **Delete nf-core duplicate** after merge
4. **Result:** Best information from both sources in single entry

**Example merged tool:**
- Galaxy FastQC: ✓ Full parameters, ✓ Galaxy integration
- + nf-core FastQC: ✓ Exact version (0.12.1), ✓ EDAM ontology, ✓ Better examples
- = Complete tool entry with all information

---

## Usage Guidance

### Distinguishing Wrappers vs Software

**Always check `help_text.function_info`:**
```json
{
  "underlying_software": "fastqc",       // The actual software
  "wrapper_name": "FastQC Summary",      // This wrapper's name
  "wrapper_function": "Summarize...",    // What THIS wrapper does
  "operation_type": "post_processing",   // Type of operation
  "is_primary_function": false           // NOT the primary function
}
```

### Getting Software Version (not wrapper version)

**Don't use:** `version` field (this is wrapper version)

**Do use:** Extract from `requirements`:
```python
import json
requirements = json.loads(tool['requirements'])
for req in requirements:
    if req['type'] in ['package', 'conda']:
        software_version = req['version']  # e.g., "0.12.1"
        break
```

### Finding Primary Analysis Tools

Filter by `is_primary_function`:
```sql
SELECT * FROM tools
WHERE json_extract(help_text, '$.function_info.is_primary_function') = 'true'
  AND json_extract(help_text, '$.function_info.underlying_software') = 'fastqc';
```

### Searching Across Multiple Functions

To find all FastQC-related tools (primary + post-processing + visualization):
```sql
SELECT
  name,
  json_extract(help_text, '$.function_info.wrapper_function'),
  json_extract(help_text, '$.function_info.operation_type')
FROM tools
WHERE json_extract(help_text, '$.function_info.underlying_software') LIKE '%fastqc%'
ORDER BY json_extract(help_text, '$.function_info.operation_type');
```

---

## API Integration Notes

The database is accessed by:
1. **Backend API:** `/api/tool_search/schema?tool_id=...`
2. **Frontend:** Parameter dialog fetches schemas via API
3. **Galaxy Proxy:** Falls back to Galaxy's `/api/tools/{id}/build` if not in database

### Required API Changes

See "Code Modifications Required" section below.

---

## Maintenance

### Adding New Tools
Use extraction scripts:
- `scripts/extract_comprehensive_tool_info.py` - Extract from existing tools
- `scripts/extract_nfcore_modules_comprehensive.py` - Extract from nf-core modules
- `scripts/add_function_metadata.py` - Add function metadata

### Updating Tool Information
Re-run extraction scripts to update from latest sources.

### Merging Duplicates
Use `scripts/merge_galaxy_nfcore_tools.py` when new sources are added.

---

## Version History

- **2025-10-30:** Initial comprehensive extraction
  - Added 334 nf-core modules
  - Merged 103 duplicate tools (Galaxy + nf-core)
  - Added function metadata to all 9,212 tools
  - Added wrapper vs software distinction
  - Achieved 96.6% parameter coverage, 99.8% description coverage

- **Previous:** Basic parameter extraction from rawText
  - 8,903 tools with parameters
  - Simple input/output format lists

---

## Database File

**Location:** `/home/yzhang/biomate/backend/database/galaxy_ai_tools.db`
**Format:** SQLite 3
**Size:** 162 MB
**Schema Version:** 2025-10-30

---

## Contact

For questions about this database schema, see:
- Backend documentation: `/home/yzhang/biomate/backend/doc/`
- Extraction scripts: `/home/yzhang/biomate/backend/scripts/`
