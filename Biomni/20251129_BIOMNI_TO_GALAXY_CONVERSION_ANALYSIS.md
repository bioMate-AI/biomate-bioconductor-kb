# Biomni to Galaxy Workflow Conversion Analysis

**Date:** November 29, 2025
**Purpose:** Analyze Biomni's tool architecture for conversion to Galaxy workflows

---

## 1. Biomni Architecture Overview

### Core Components

```
biomni/
├── agent/          # ReAct agent for autonomous reasoning
│   ├── react.py    # Main agent with tool invocation
│   └── a1.py       # Extended agent capabilities
├── tool/           # Domain-specific tools (18 domains)
│   ├── genomics.py
│   ├── database.py
│   ├── molecular_biology.py
│   ├── biophysics.py
│   └── ... (18 total domain files)
├── tool/tool_description/  # Declarative tool metadata
│   └── {domain}.py         # Schema definitions
└── tool/schema_db/         # API schemas (pickle)
    └── uniprot.pkl, ensembl.pkl, etc.
```

### Tool Categories (18 Domains)

| Domain | Functions | Lines | Key Capabilities |
|--------|-----------|-------|------------------|
| **database.py** | ~50 | 4974 | UniProt, GWAS, ClinVar, Ensembl, GEO queries |
| **pharmacology.py** | ~30 | 3792 | Drug targets, ADMET, compound analysis |
| **genomics.py** | ~25 | 2759 | scRNA-seq, gene enrichment, ChIP-seq |
| **molecular_biology.py** | ~20 | 2222 | ORF finding, plasmid annotation, cloning |
| **immunology.py** | ~15 | 1972 | TCR/BCR analysis, cytokine prediction |
| **genetics.py** | ~15 | 1672 | GWAS, PRS, haplotype analysis |
| **microbiology.py** | ~12 | 1618 | Microbiome, AMR, metabolic modeling |
| **bioimaging.py** | ~10 | 1394 | Cell segmentation, fluorescence analysis |
| **bioengineering.py** | ~10 | 1387 | Strain design, pathway engineering |
| **physiology.py** | ~10 | 1359 | Cardiac models, neural simulation |
| **synthetic_biology.py** | ~10 | 1351 | Circuit design, CRISPR guide design |
| **cancer_biology.py** | ~10 | 1292 | Tumor analysis, driver prediction |
| **pathology.py** | ~8 | 1034 | Histology analysis, biomarker detection |
| **biochemistry.py** | ~8 | 1026 | Enzyme kinetics, metabolite analysis |
| **systems_biology.py** | ~8 | 926 | Network analysis, flux balance |
| **cell_biology.py** | ~6 | 742 | Cell cycle, organelle analysis |
| **biophysics.py** | ~4 | 513 | IDR prediction, cytoskeleton analysis |
| **glycoengineering.py** | ~2 | 146 | Glycan analysis |

---

## 2. Tool Calling Patterns

### Pattern 1: Pure Python Analysis Functions

Most Biomni tools are self-contained Python functions that:
- Take input files/parameters
- Process using Python libraries (pandas, numpy, Biopython, scanpy)
- Return result strings or save to files

**Example: `annotate_open_reading_frames`**
```python
def annotate_open_reading_frames(sequence, min_length, search_reverse=False):
    """Find all ORFs in a DNA sequence using Biopython."""
    from Bio.Seq import Seq
    # Pure Python processing
    return {"orfs": all_orfs, "summary_stats": stats}
```

**Galaxy Conversion:** Create Galaxy tool wrapper XML with Python script.

### Pattern 2: External API Calls (Database Queries)

Database functions query external REST APIs using LLM-generated queries:

**Example: `query_uniprot`**
```python
def query_uniprot(prompt=None, endpoint=None, max_results=5):
    # Load schema from pickle
    schema_path = os.path.join(os.path.dirname(__file__), "schema_db", "uniprot.pkl")
    with open(schema_path, "rb") as f:
        uniprot_schema = pickle.load(f)

    # Use LLM to generate API call from natural language
    result = _query_llm_for_api(prompt, schema, system_template)

    # Call REST API
    response = _query_rest_api(endpoint, method="GET", params=params)
```

**Galaxy Conversion:** Create Galaxy tool that either:
1. Wraps the API call directly (simpler)
2. Uses BioMate's AI assistant for natural language queries

### Pattern 3: CLI Tool Wrappers

Some functions wrap external CLI tools:

**Example: `perform_chipseq_peak_calling_with_macs2`**
```python
def perform_chipseq_peak_calling_with_macs2(chip_seq_file, control_file, ...):
    cmd = ["macs2", "callpeak", "-t", chip_seq_file, "-c", control_file, ...]
    subprocess.run(cmd, check=True)
```

**Galaxy Conversion:** Map to existing Galaxy MACS2 tool or create wrapper.

### Pattern 4: R Code Execution

Some functions execute R code via subprocess:

**Example from utils.py:**
```python
def run_r_code(code: str) -> str:
    with tempfile.NamedTemporaryFile(suffix=".R", mode="w", delete=False) as f:
        f.write(code)
    result = subprocess.run(["Rscript", temp_file], capture_output=True)
```

**Galaxy Conversion:** Use Galaxy's R integration or create R tool wrapper.

---

## 3. Data Flow Patterns

### Input Types
| Type | Example | Galaxy Data Type |
|------|---------|------------------|
| FASTA sequences | `sequence: str` | `fasta` |
| AnnData (h5ad) | `adata_path: str` | `h5ad` |
| BAM files | `chip_seq_file: str` | `bam` |
| VCF files | `vcf_file: str` | `vcf` |
| CSV/TSV data | `data_file: str` | `tabular` |
| PDB structures | `pdb_file: str` | `pdb` |
| Gene lists | `genes: list[str]` | `txt` |

### Output Types
| Type | Description | Galaxy Data Type |
|------|-------------|------------------|
| Result logs | Step-by-step analysis | `txt` |
| CSV reports | Tabular results | `tabular` |
| Plots | Visualization | `png/pdf` |
| Processed h5ad | scRNA-seq results | `h5ad` |
| JSON | Structured data | `json` |

---

## 4. Conversion Strategy for Galaxy

### Strategy A: Direct Tool Wrappers

For each Biomni function, create a Galaxy tool XML:

```xml
<tool id="biomni_annotate_orfs" name="Annotate ORFs" version="1.0">
    <description>Find Open Reading Frames in DNA sequence</description>
    <requirements>
        <requirement type="package" version="1.81">biopython</requirement>
    </requirements>
    <command><![CDATA[
        python '$__tool_directory__/annotate_orfs.py'
            --sequence '$input_sequence'
            --min_length $min_length
            $search_reverse
            --output '$output'
    ]]></command>
    <inputs>
        <param name="input_sequence" type="data" format="fasta"/>
        <param name="min_length" type="integer" value="100"/>
        <param name="search_reverse" type="boolean" truevalue="--search_reverse" falsevalue=""/>
    </inputs>
    <outputs>
        <data name="output" format="json"/>
    </outputs>
</tool>
```

### Strategy B: LLM-Assisted Orchestration (BioMate Approach)

Use BioMate's AI assistant to:
1. Understand user intent from natural language
2. Select appropriate Biomni tools
3. Generate Galaxy workflow dynamically
4. Execute and return results

This is BioMate's current approach - the AI assistant acts as orchestrator.

### Strategy C: Hybrid Workflows

Combine Galaxy tools with AI orchestration:
1. Database queries → AI-assisted (natural language)
2. Analysis functions → Galaxy tool wrappers
3. Multi-step pipelines → Galaxy workflows with conditional logic

---

## 5. Priority Tools for Conversion

### High Priority (Most Used, Clear I/O)

| Tool | Domain | Complexity | Galaxy Equivalent |
|------|--------|------------|-------------------|
| `gene_set_enrichment_analysis` | genomics | Low | gseapy wrapper |
| `annotate_open_reading_frames` | molecular_biology | Low | Custom tool |
| `get_gene_coding_sequence` | molecular_biology | Low | NCBI wrapper |
| `query_uniprot` | database | Medium | UniProt API tool |
| `perform_chipseq_peak_calling_with_macs2` | genomics | Low | Existing MACS2 |
| `interspecies_gene_conversion` | genomics | Medium | BioMart wrapper |

### Medium Priority (Specialized Analysis)

| Tool | Domain | Complexity | Notes |
|------|--------|------------|-------|
| `annotate_celltype_scRNA` | genomics | High | LLM-dependent |
| `predict_protein_disorder_regions` | biophysics | Medium | IUPred2A API |
| `analyze_chromatin_interactions` | genomics | High | Hi-C analysis |
| `generate_gene_embeddings_with_ESM_models` | genomics | High | GPU needed |

### Low Priority (Complex/Niche)

| Tool | Domain | Reason |
|------|--------|--------|
| `unsupervised_celltype_transfer_between_scRNA_datasets` | genomics | Complex dependencies |
| LLM-dependent annotation tools | various | Requires AI orchestration |

---

## 6. Schema Mapping

### Biomni Tool Description → Galaxy Tool XML

**Biomni format:**
```python
{
    "name": "gene_set_enrichment_analysis",
    "description": "Perform enrichment analysis for a list of genes",
    "required_parameters": [
        {"name": "genes", "type": "list", "description": "List of gene symbols"}
    ],
    "optional_parameters": [
        {"name": "top_k", "type": "int", "default": 10, "description": "Number of top pathways"}
    ]
}
```

**Galaxy XML equivalent:**
```xml
<tool id="gene_set_enrichment_analysis" name="Gene Set Enrichment Analysis">
    <inputs>
        <param name="genes" type="data" format="txt" label="Gene list"/>
        <param name="top_k" type="integer" value="10" label="Top pathways"/>
    </inputs>
</tool>
```

### Automated Conversion Possible

The structured Biomni tool descriptions in `tool_description/*.py` can be automatically converted to Galaxy XML using a script.

---

## 7. Implementation Recommendations

### Phase 1: Core Tools (Immediate)
1. Convert 10-15 most-used Biomni functions to Galaxy tools
2. Focus on clear input/output patterns
3. Reuse existing Galaxy tools where possible (MACS2, samtools, etc.)

### Phase 2: Database Integration
1. Create Galaxy tools for database queries (UniProt, GWAS, etc.)
2. Option A: Direct API wrappers
3. Option B: Use BioMate AI for natural language queries

### Phase 3: Workflow Templates
1. Create multi-step Galaxy workflows from common Biomni patterns
2. Examples:
   - scRNA-seq analysis pipeline
   - ChIP-seq peak calling + motif analysis
   - Gene set enrichment workflow

### Phase 4: AI Orchestration
1. Integrate BioMate AI assistant for dynamic tool selection
2. Use Galaxy workflow generator for automated pipeline creation

---

## 8. Key Differences: Biomni vs Galaxy

| Aspect | Biomni | Galaxy |
|--------|--------|--------|
| **Orchestration** | LLM-driven (ReAct agent) | User-defined workflows |
| **Tool Discovery** | Semantic retrieval | Browse/search catalog |
| **Execution** | Python subprocess | Job runner (Pulsar, etc.) |
| **Data Management** | File paths | History datasets |
| **Reproducibility** | Code logs | Workflow history |
| **Scalability** | Single machine | Cluster/cloud |

### Synergy Opportunity

BioMate can bridge both approaches:
- Use Biomni's semantic tool understanding for suggestions
- Execute via Galaxy infrastructure for scalability
- Combine LLM intelligence with reproducible workflows

---

## 9. Next Steps

1. **Tool Inventory**: Create complete list of Biomni functions with I/O signatures
2. **Mapping Table**: Match Biomni tools to existing Galaxy tools
3. **Wrapper Generation**: Script to auto-generate Galaxy XML from Biomni schemas
4. **Integration Testing**: Test converted tools in BioMate's Galaxy instance
5. **Documentation**: Create user guide for Biomni-style workflows in Galaxy

---

## Summary

Biomni provides ~150+ biomedical analysis functions across 18 domains. Most can be converted to Galaxy tools with:
- **70%** direct Python wrapper conversion
- **20%** mapping to existing Galaxy tools
- **10%** requiring AI orchestration for natural language interfaces

The structured tool descriptions in Biomni enable automated conversion to Galaxy XML format.
