# Galaxy Interactive Tools Inventory

**Date**: January 9, 2026, 20:30
**Author**: Claude Code Assistant

---

## Summary

Galaxy Interactive Tools (GxIT) are containerized applications that run within Galaxy and have direct access to Galaxy history data. They enable interactive exploration, visualization, and analysis of workflow outputs.

**Total Available: 36 interactive tools**

---

## Tools by Category

### 1. Notebooks & IDEs (8 tools)

| Tool ID | Name | Description | Docker Image |
|---------|------|-------------|--------------|
| `interactive_tool_jupyter_notebook` | Jupyter Notebook | Python/R notebook with Galaxy data access | `quay.io/bgruening/docker-jupyter-notebook` |
| `interactive_tool_jupyter_notebook_1.0.0` | Jupyter Notebook 1.0.0 | Legacy version | - |
| `interactive_tool_jupyter_notebook_1.0.1` | Jupyter Notebook 1.0.1 | Legacy version | - |
| `interactive_tool_ml_jupyter_notebook` | ML Jupyter Notebook | Machine learning focused (TensorFlow, PyTorch) | - |
| `interactive_tool_pangeo_notebook` | Pangeo Notebook | Geoscience/climate data analysis (xarray, dask) | - |
| `interactive_tool_climate_notebook` | Climate Notebook | Climate science specific | - |
| `interactive_tool_rstudio` | RStudio | R statistical environment | - |
| `interactive_tool_rstudio_bioc_3.20` | RStudio Bioconductor | RStudio with Bioconductor 3.20 pre-installed | - |

### 2. Single-Cell & Genomics Visualization (4 tools)

| Tool ID | Name | Description | Input Format |
|---------|------|-------------|--------------|
| `interactive_tool_cellxgene` | CellxGene 1.1.1 | Single-cell RNA-seq UMAP/cluster explorer | h5ad (AnnData) |
| `interactive_tool_cellxgene_0.16.2` | CellxGene 0.16.2 | Legacy version | h5ad |
| `interactive_tool_higlass` | HiGlass | Hi-C chromatin interaction multi-scale viewer | cooler, mcool |
| `interactive_tool_isee` | iSEE | Interactive SummarizedExperiment Explorer | RDS |

### 3. Variant & Alignment Viewers (2 tools)

| Tool ID | Name | Description | Input Format |
|---------|------|-------------|--------------|
| `interactive_tool_bam_iobio` | BAM iobio | Real-time BAM file QC and visualization | BAM |
| `interactive_tool_vcf_iobio` | VCF iobio | Variant visualization and filtering | VCF |

### 4. Metagenomics & Taxonomy (4 tools)

| Tool ID | Name | Description | Input Format |
|---------|------|-------------|--------------|
| `interactive_tool_pavian` | Pavian | Metagenomics classification results viewer | Kraken/Centrifuge |
| `interactive_tool_phinch` | Phinch | Microbiome data visualization | BIOM |
| `interactive_tool_blobtoolkit` | BlobToolKit | Genome contamination detection | FASTA + coverage |
| `interactive_tool_metashark` | MetaShark | Metabolomics network analysis | - |

### 5. Image & 3D Visualization (4 tools)

| Tool ID | Name | Description | Input Format |
|---------|------|-------------|--------------|
| `interactive_tool_ilastik` | ilastik | ML-based image segmentation | TIFF, HDF5 |
| `interactive_tool_paraview` | ParaView | 3D scientific visualization | VTK, VTI |
| `interactive_tool_panoply` | Panoply | NetCDF/HDF climate data viz | NetCDF, HDF |
| `interactive_tool_vrm_editor` | VRM Editor | 3D avatar/model editing | VRM |

### 6. Data Wrangling & Spreadsheets (2 tools)

| Tool ID | Name | Description | Input Format |
|---------|------|-------------|--------------|
| `interactive_tool_openrefine` | OpenRefine | Data cleaning and transformation | CSV, TSV, JSON |
| `interactive_tool_ethercalc` | EtherCalc | Collaborative spreadsheet | CSV |

### 7. Graph & Knowledge Bases (2 tools)

| Tool ID | Name | Description | Input Format |
|---------|------|-------------|--------------|
| `interactive_tool_neo4j` | Neo4j | Graph database explorer | CSV, JSON |
| `interactive_tool_askomics` | AskOmics | RDF/SPARQL knowledge graph | RDF, TTL |

### 8. Specialized Domain Tools (10 tools)

| Tool ID | Name | Description | Domain |
|---------|------|-------------|--------|
| `interactive_tool_guacamole_desktop` | Guacamole Desktop | Full Linux desktop in browser | General |
| `interactive_tool_radiant` | Radiant | Shiny-based business analytics | Statistics |
| `interactive_tool_wallace` | Wallace | Species distribution modeling | Ecology |
| `interactive_tool_wilson` | WIlson | Multi-omics data explorer | Omics |
| `interactive_tool_simtext_app` | SimText | Literature text mining | NLP |
| `interactive_tool_pyiron` | pyiron | Materials science workflows | Materials |
| `interactive_tool_geoexplorer` | GeoExplorer | Geographic data explorer | GIS |
| `interactive_tool_hicbrowser` | HiC Browser | Hi-C data browser | Genomics |
| `interactive_tool_mgnify_notebook` | MGnify Notebook | Metagenomics analysis | Microbiome |
| `interactive_tool_qiskit_jupyter_notebook` | Qiskit Notebook | Quantum computing | Quantum |

---

## How Interactive Tools Connect with Workflows

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          GALAXY WORKFLOW                                 │
├─────────────────────────────────────────────────────────────────────────┤
│  Step 1: FastQC    →  Step 2: STAR    →  Step 3: FeatureCounts         │
│                                                │                        │
│                                                ▼                        │
│                                    ┌─────────────────────┐              │
│                                    │ counts_matrix.tsv   │              │
│                                    └─────────────────────┘              │
│                                                │                        │
│                                                ▼                        │
│                           ┌────────────────────────────────────┐        │
│                           │  Step 4: Interactive Jupyter       │        │
│                           │  ┌──────────────────────────────┐  │        │
│                           │  │  mode: "previous"            │  │        │
│                           │  │  ipynb: analysis_template.ipynb │        │
│                           │  │  run_it: true (batch) / false (interactive)│
│                           │  │  input: [counts_matrix.tsv]  │  │        │
│                           │  └──────────────────────────────┘  │        │
│                           └────────────────────────────────────┘        │
│                                                │                        │
│                                                ▼                        │
│                                    ┌─────────────────────┐              │
│                                    │ executed_notebook.ipynb │          │
│                                    │ + generated figures     │          │
│                                    └─────────────────────┘              │
└─────────────────────────────────────────────────────────────────────────┘
```

### Two Execution Modes

#### 1. Interactive Mode (User Exploration)
```
Workflow pauses → User opens browser session → Explores data → Saves outputs → Workflow continues
```
- Used when: Ad-hoc exploration, unknown analysis needs
- User action required: Yes

#### 2. Batch Mode (Automated Execution)
```
Workflow runs notebook automatically → Captures outputs → Continues to next step
```
- Used when: Reproducible analysis with predefined notebook
- User action required: No
- Enabled by: `run_it: true` parameter in Jupyter

### Data Access Mechanisms

Interactive tools receive these environment variables:
```bash
HISTORY_ID=$__history_id__      # Current Galaxy history
GALAXY_URL=$__galaxy_url__      # Galaxy server URL
API_KEY=<injected>              # User's API key for programmatic access
```

This allows tools to:
1. Read any dataset from the history
2. Write results back to Galaxy
3. Access Galaxy APIs for metadata

### Input/Output Flow

```python
# Inside Jupyter notebook (Galaxy integration)
from galaxy import get, put

# Read workflow output
counts = get(1)  # Get first input dataset

# Do analysis
import pandas as pd
df = pd.read_csv(counts)
# ... analysis ...

# Write back to Galaxy
put(df.to_csv(), name="analyzed_counts.csv")
```

---

## Current Biomate Integration Status

### What's Implemented

| Component | Status | Location |
|-----------|--------|----------|
| Backend API: Launch interactive tool | Implemented | `galaxy-api-proxy.ts:951` |
| Backend API: Get active sessions | Implemented | `galaxy-api-proxy.ts:979` |
| API Endpoint: POST /api/interactive/launch | Implemented | `routes.ts:3239` |
| API Endpoint: GET /api/interactive/sessions | Implemented | `routes.ts:3277` |
| Frontend: Interactive Launcher Dialog | Implemented | `interactive-launcher.tsx` |

### What's NOT Implemented (Gaps)

| Gap | Description | Impact |
|-----|-------------|--------|
| **Workflow Generator Awareness** | AI workflow generator doesn't know about interactive tools | Cannot auto-suggest "add Jupyter for exploration" |
| **Workflow Integration** | No support for interactive tools as workflow steps | Cannot create workflows with embedded notebooks |
| **Template Notebooks** | No predefined analysis notebooks for common tasks | Users must create from scratch |
| **Batch Mode Support** | No UI for running notebooks in batch mode | Cannot use notebooks for reproducible outputs |
| **Output Type Detection** | No automatic suggestion based on output format | h5ad → CellxGene, BAM → bam_iobio not suggested |

### Recommended Integration Priorities

| Priority | Feature | Benefit |
|----------|---------|---------|
| **P1** | Output-based tool suggestions | After workflow: "Your h5ad file can be explored in CellxGene" |
| **P2** | Template notebooks per workflow type | RNA-seq → DESeq2 visualization notebook |
| **P2** | Workflow generator awareness | Include interactive steps in generated workflows |
| **P3** | Batch notebook execution | Run predefined analysis as workflow step |

---

## Use Cases by Workflow Type

### RNA-seq Analysis
| Output | Suggested Tool | Purpose |
|--------|---------------|---------|
| BAM files | bam_iobio | QC alignment |
| Count matrix | Jupyter/RStudio | Custom visualization |
| DE results | RStudio | Volcano plots, heatmaps |

### Single-Cell RNA-seq
| Output | Suggested Tool | Purpose |
|--------|---------------|---------|
| h5ad (AnnData) | CellxGene | UMAP exploration, cell type annotation |
| h5ad | iSEE | Statistical exploration |
| Scanpy notebook | Jupyter | Custom clustering |

### Metagenomics
| Output | Suggested Tool | Purpose |
|--------|---------------|---------|
| Kraken report | Pavian | Taxonomy visualization |
| BIOM file | Phinch | Microbiome diversity |
| Assembly | BlobToolKit | Contamination check |

### Hi-C / Chromatin
| Output | Suggested Tool | Purpose |
|--------|---------------|---------|
| .mcool file | HiGlass | Multi-resolution contact map |
| .cool file | HiC Browser | Interaction exploration |

### Variant Analysis
| Output | Suggested Tool | Purpose |
|--------|---------------|---------|
| VCF | vcf_iobio | Variant filtering, QC |
| BAM | bam_iobio | Read-level inspection |

---

## Technical Details

### Tool Definition Structure
```xml
<tool id="interactive_tool_jupyter_notebook"
      tool_type="interactive"           <!-- Marks as interactive -->
      name="Interactive Jupyter Notebook"
      version="0.3">

    <!-- Docker container requirement -->
    <requirements>
        <container type="docker">quay.io/bgruening/docker-jupyter-notebook</container>
    </requirements>

    <!-- Entry point for browser access -->
    <entry_points>
        <entry_point name="Jupyter" requires_domain="True">
            <port>8888</port>
            <url>ipython/lab</url>
        </entry_point>
    </entry_points>

    <!-- Galaxy integration variables -->
    <environment_variables>
        <environment_variable name="HISTORY_ID">$__history_id__</environment_variable>
        <environment_variable name="GALAXY_URL">$__galaxy_url__</environment_variable>
        <environment_variable name="API_KEY" inject="api_key" />
    </environment_variables>

    <!-- Inputs from workflow -->
    <inputs>
        <param name="input" multiple="true" type="data" optional="true"
               label="Include data into the environment"/>
    </inputs>

    <!-- Outputs back to Galaxy -->
    <outputs>
        <data name="jupyter_notebook" format="ipynb" label="Executed Notebook"/>
    </outputs>
</tool>
```

### Galaxy Entry Points API
```
GET  /api/entry_points              # List all entry points
GET  /api/entry_points?active=true  # Active sessions only
POST /api/entry_points/:id/access   # Get access URL
DELETE /api/entry_points/:id        # Stop session
```

---

## Files Reference

| File | Purpose |
|------|---------|
| `/backend/lib/galaxy/tools/bundled/interactive/` | Tool XML definitions |
| `/backend/lib/galaxy/webapps/galaxy/api/tool_entry_points.py` | Entry points API |
| `/frontend/server/galaxy-api-proxy.ts` | Biomate API wrapper |
| `/frontend/client/src/components/interactive-launcher.tsx` | Frontend launcher UI |

---

## Next Steps

1. **Implement output-based suggestions**: Detect output formats and suggest appropriate interactive tools
2. **Create template notebooks**: Pre-built analysis templates for common workflows
3. **Add to workflow generator**: Make AI aware of interactive tool capabilities
4. **Build notebook library**: Curated notebooks for RNA-seq, scRNA-seq, etc.
