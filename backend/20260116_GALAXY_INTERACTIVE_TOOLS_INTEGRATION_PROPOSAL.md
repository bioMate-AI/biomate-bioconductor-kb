# Galaxy Interactive Tools Integration Proposal

**Date**: 2026-01-16
**Status**: Draft for Review

---

## Executive Summary

Galaxy has **36 interactive tools** and **100+ visualization tools** that are currently underutilized in BioMate's workflow generation. This proposal outlines how to integrate these resources to provide automated visualization and guided post-analysis.

**Key Principle**: Automate what can be automated; guide what needs user input through UI.

---

## Part 1: Current Code Review - Issues Found

### Issue 1: No Visualization Tools in Tool Search

**Problem**: The workflow generator searches for analysis tools but doesn't prioritize visualization tools for the post-processing phase.

**Location**: `galaxy_workflow_generator.py:_retrieve_tools_from_index()`

```python
# Current: Generic search, no visualization awareness
results = self.tool_index.search(user_intent, limit=limit)
```

**Fix**: Add explicit visualization tool search for post-processing:
```python
# Proposed: Domain-aware search including visualization
analysis_tools = self.tool_index.search(user_intent, limit=limit-10)
viz_tools = self.tool_index.search(f"{domain} visualization plot", limit=10)
results = analysis_tools + viz_tools
```

### Issue 2: Domain Patterns Missing Concrete Tool Mappings

**Problem**: `domain_workflow_patterns.py` lists "typical tools" as names (FastQC, DESeq2) but these don't match actual tool IDs in the database.

**Location**: `domain_workflow_patterns.py:55-408`

```python
# Current: Human-readable names
typical_tools=["DESeq2", "edgeR", "limma"]

# Reality in database:
# - aurora_deseq2 (ID: 1533)
# - bioconductor-edger (ID varies)
```

**Fix**: Add tool ID mapping:
```python
TOOL_ID_ALIASES = {
    "DESeq2": ["aurora_deseq2", "deseq2", "bioconductor-deseq2"],
    "FastQC": ["fastqc", "FastQC"],
    "STAR": ["rna_star", "star"],
    # ...
}
```

### Issue 3: No Interactive Tool Awareness

**Problem**: The workflow generator has NO knowledge of Galaxy's 36 interactive tools that can provide rich post-analysis capabilities.

**Impact**: Users miss opportunities for:
- CellxGene exploration of single-cell data
- Jupyter notebooks for custom analysis
- BAM/VCF iobio for QC inspection

### Issue 4: Output Format Not Tracked

**Problem**: Generated workflows don't track output file formats, making it impossible to suggest appropriate interactive tools.

**Location**: `galaxy_workflow_generator.py` - JSON output format

```python
# Current: No output format specification
"expected_output": "What output this step produces"

# Needed:
"expected_output": {
    "description": "Aligned reads",
    "format": "bam",
    "suggested_interactive_tool": "bam_iobio"
}
```

### Issue 5: Visualization Phase is Generic

**Problem**: The "Visualization" phase in domain patterns lists generic tools like "ggplot2" which isn't a Galaxy tool.

**Location**: `domain_workflow_patterns.py:98-104`

```python
WorkflowPhase(
    name="Visualization",
    typical_tools=["ggplot2", "Plotly", "heatmap"],  # NOT Galaxy tool IDs!
)
```

---

## Part 2: Galaxy Interactive Tools - Automation Strategy

### 2.1 Tools That CAN Be Automated (Batch Mode)

These tools support `run_it: true` for automated execution:

| Tool | Input Format | Automation Strategy |
|------|--------------|---------------------|
| **Jupyter Notebook** | Any | Pre-built template notebooks executed automatically |
| **RStudio** | R data | Pre-built R scripts for standard analyses |

**Implementation**: Create template notebook library:
```
templates/
├── transcriptomics/
│   ├── deseq2_visualization.ipynb    # Volcano, MA, heatmap
│   ├── pca_analysis.ipynb            # PCA plots
│   └── pathway_enrichment.ipynb      # GO/KEGG plots
├── single_cell/
│   ├── scanpy_qc.ipynb               # QC metrics
│   └── clustering_analysis.ipynb     # UMAP, markers
├── genomics/
│   ├── variant_summary.ipynb         # VCF statistics
│   └── coverage_analysis.ipynb       # Coverage plots
└── metagenomics/
    └── diversity_analysis.ipynb      # Alpha/beta diversity
```

### 2.2 Tools That Require User Interaction (Guided via UI)

These tools are inherently interactive - suggest them after workflow completion:

| Tool | Input Format | When to Suggest |
|------|--------------|-----------------|
| **CellxGene** | h5ad | After single-cell workflow produces AnnData |
| **HiGlass** | mcool | After Hi-C workflow produces contact matrix |
| **BAM iobio** | BAM | After alignment step for QC inspection |
| **VCF iobio** | VCF | After variant calling for filtering |
| **Pavian** | Kraken report | After taxonomic classification |
| **Phinch** | BIOM | After microbiome profiling |
| **OpenRefine** | CSV/TSV | When data cleaning is needed |

**Implementation**: Output-based suggestion system:
```python
INTERACTIVE_TOOL_SUGGESTIONS = {
    "h5ad": {
        "tool": "interactive_tool_cellxgene",
        "purpose": "Explore cell clusters, gene expression, and annotations",
        "auto_possible": False
    },
    "bam": {
        "tool": "interactive_tool_bam_iobio",
        "purpose": "Inspect alignment quality and coverage",
        "auto_possible": False
    },
    "vcf": {
        "tool": "interactive_tool_vcf_iobio",
        "purpose": "Filter variants and inspect quality metrics",
        "auto_possible": False
    },
    # ...
}
```

---

## Part 3: Specific Integration Plan by Domain

### 3.1 Transcriptomics (RNA-seq)

| Workflow Output | File Format | Automated Visualization | Interactive Option |
|-----------------|-------------|------------------------|-------------------|
| Raw reads QC | HTML | FastQC + MultiQC (already automated) | - |
| Aligned reads | BAM | Coverage plot tool | BAM iobio |
| Count matrix | TSV | PCA plot, sample correlation | Jupyter notebook |
| DE results | TSV | **volcano_plot**, **heatmap_plot** | RStudio |
| Enrichment | TSV | GO bar plot | Jupyter notebook |

**Specific Tools to Add to Workflow Generator**:
```python
TRANSCRIPTOMICS_VISUALIZATION_TOOLS = {
    "count_matrix": [
        {"id": "plotPCA", "purpose": "Sample PCA visualization"},
        {"id": "plotCorrelation", "purpose": "Sample correlation heatmap"},
    ],
    "de_results": [
        {"id": "volcanoplot", "purpose": "Volcano plot of DE genes"},
        {"id": "heatmap2", "purpose": "Expression heatmap"},
    ],
}
```

### 3.2 Single-Cell RNA-seq

| Workflow Output | File Format | Automated Visualization | Interactive Option |
|-----------------|-------------|------------------------|-------------------|
| Filtered counts | h5ad | UMAP plot (Scanpy) | **CellxGene** (P1) |
| Clustered data | h5ad | Marker gene dotplot | **iSEE** |
| Trajectory | h5ad | Pseudotime plot | CellxGene |

**Key Integration**: After any workflow producing `.h5ad`:
```json
{
  "post_workflow_suggestion": {
    "tool": "interactive_tool_cellxgene",
    "message": "Your single-cell data is ready. Launch CellxGene to explore clusters and gene expression interactively.",
    "auto_launch": false,
    "one_click_action": true
  }
}
```

### 3.3 Genomics (Variant Calling)

| Workflow Output | File Format | Automated Visualization | Interactive Option |
|-----------------|-------------|------------------------|-------------------|
| Aligned reads | BAM | Coverage stats | **BAM iobio** |
| Raw variants | VCF | Variant stats summary | **VCF iobio** (P1) |
| Annotated VCF | VCF | Mutation spectrum plot | VCF iobio |
| SnpEff report | HTML | Already visual | - |

**Key Integration**: After variant calling:
```json
{
  "post_workflow_suggestion": {
    "tool": "interactive_tool_vcf_iobio",
    "message": "Variants ready. Use VCF iobio to filter by quality, frequency, and impact.",
    "auto_launch": false
  }
}
```

### 3.4 Metagenomics

| Workflow Output | File Format | Automated Visualization | Interactive Option |
|-----------------|-------------|------------------------|-------------------|
| Kraken report | TSV | **Krona chart** | **Pavian** (P1) |
| BIOM table | BIOM | Alpha diversity plot | **Phinch** |
| Assembly | FASTA | Assembly stats | **BlobToolKit** |

**Key Integration**:
```python
METAGENOMICS_POST_TOOLS = {
    "kraken_report": {
        "automated": "krona_pie_chart",  # Runs automatically
        "interactive": "interactive_tool_pavian"  # Suggested to user
    },
    "biom": {
        "automated": "alpha_diversity_plot",
        "interactive": "interactive_tool_phinch"
    }
}
```

### 3.5 Epigenomics (ChIP-seq/ATAC-seq)

| Workflow Output | File Format | Automated Visualization | Interactive Option |
|-----------------|-------------|------------------------|-------------------|
| Peaks | BED/narrowPeak | Peak annotation pie chart | - |
| Signal tracks | bigWig | Profile plot (plotProfile) | **HiGlass** |
| Differential peaks | BED | Volcano plot | Jupyter |

---

## Part 4: Implementation Plan

### Phase 1: Output Format Tracking (Week 1)

**Goal**: Track output formats in workflow generation

**Changes**:
1. Update `domain_workflow_patterns.py` to include output formats per phase
2. Update workflow JSON output to include `output_format` field
3. Add `INTERACTIVE_TOOL_SUGGESTIONS` mapping

```python
# domain_workflow_patterns.py
WorkflowPhase(
    name="Differential Expression",
    typical_tools=["DESeq2", "edgeR"],
    output_formats=["tsv", "csv"],  # NEW
    visualization_tools=["volcanoplot", "heatmap2"],  # NEW
    interactive_tools=["interactive_tool_rstudio"],  # NEW
)
```

### Phase 2: Visualization Tool Search (Week 2)

**Goal**: Include visualization tools in workflow generation

**Changes**:
1. Add visualization tool category to tool search
2. Create `VISUALIZATION_TOOL_MAPPING` for each domain
3. Update LLM prompt to include visualization phase tools

```python
# galaxy_workflow_generator.py
def _retrieve_tools_with_visualization(self, user_intent, domain, limit=30):
    # Get analysis tools
    analysis_tools = self.tool_index.search(user_intent, limit=limit-10)

    # Get domain-specific visualization tools
    viz_keywords = DOMAIN_VISUALIZATION_KEYWORDS.get(domain, [])
    viz_tools = self.tool_index.search(' '.join(viz_keywords), limit=10)

    return analysis_tools + viz_tools
```

### Phase 3: Post-Workflow Suggestions (Week 3)

**Goal**: Suggest interactive tools after workflow completion

**Changes**:
1. Add `post_workflow_suggestions` to workflow result
2. Implement output format detection
3. Create suggestion UI component

```python
# In workflow result:
{
    "success": True,
    "workflow_ga": {...},
    "post_workflow_suggestions": [
        {
            "output_file": "results.h5ad",
            "format": "h5ad",
            "suggested_tool": "interactive_tool_cellxgene",
            "purpose": "Explore single-cell clusters interactively",
            "launch_url": "/api/interactive/launch?tool=cellxgene&input=..."
        }
    ]
}
```

### Phase 4: Template Notebook Library (Week 4)

**Goal**: Create pre-built notebooks for automated visualization

**Deliverables**:
1. DESeq2 visualization notebook (volcano, MA, heatmap)
2. Single-cell QC notebook
3. Variant summary notebook
4. Metagenomics diversity notebook

**Notebook Structure**:
```python
# templates/transcriptomics/deseq2_visualization.ipynb
# Cell 1: Load data from Galaxy
from galaxy import get
de_results = get(1)  # First input

# Cell 2: Volcano plot
import pandas as pd
import matplotlib.pyplot as plt
df = pd.read_csv(de_results, sep='\t')
plt.scatter(df['log2FoldChange'], -np.log10(df['padj']))
plt.savefig('volcano_plot.png')

# Cell 3: Heatmap
# ... automated heatmap generation

# Cell 4: Save outputs
from galaxy import put
put('volcano_plot.png', name='Volcano Plot')
put('heatmap.png', name='Expression Heatmap')
```

---

## Part 5: Specific Tool Mappings

### Galaxy Visualization Tools in Database

| Tool ID | Name | Best For |
|---------|------|----------|
| `plotPCA` | PCA plot | Sample relationships |
| `plotCorrelation` | Correlation plot | Sample QC |
| `plotHeatmap` | Heatmap | Expression/ChIP signal |
| `plotProfile` | Profile plot | ChIP-seq signal |
| `plotFingerprint` | Fingerprint plot | ChIP-seq QC |
| `volcanoplot` | Volcano plot | DE results |
| `krona_pie_chart` | Krona | Taxonomic composition |
| `Fasta Statistics` | FASTA stats | Assembly QC |

### Galaxy Interactive Tools Available

| Tool ID | Best For | Input Format |
|---------|----------|--------------|
| `interactive_tool_jupyter_notebook` | Custom analysis | Any |
| `interactive_tool_rstudio` | R-based viz | R data, TSV |
| `interactive_tool_cellxgene` | Single-cell exploration | h5ad |
| `interactive_tool_bam_iobio` | Alignment QC | BAM |
| `interactive_tool_vcf_iobio` | Variant filtering | VCF |
| `interactive_tool_pavian` | Metagenomics | Kraken report |
| `interactive_tool_phinch` | Microbiome | BIOM |
| `interactive_tool_higlass` | Hi-C data | mcool |

---

## Part 6: UI Integration

### Post-Workflow Suggestion Card

After workflow completion, show:

```
┌────────────────────────────────────────────────────────────┐
│  Workflow Complete: RNA-seq Differential Expression        │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  Output Files:                                             │
│  ├── counts_matrix.tsv                                     │
│  ├── de_results.tsv                                        │
│  └── volcano_plot.png (auto-generated)                     │
│                                                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Suggested Next Steps:                               │   │
│  │                                                     │   │
│  │ [Launch Jupyter] Customize visualization            │   │
│  │   → Pre-loaded with your DE results                 │   │
│  │   → Template: deseq2_visualization.ipynb            │   │
│  │                                                     │   │
│  │ [Launch RStudio] Advanced R analysis                │   │
│  │   → Bioconductor packages pre-installed             │   │
│  │                                                     │   │
│  │ [Download Report] Get workflow summary              │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### One-Click Interactive Launch

```typescript
// Frontend: Single click to launch with data pre-loaded
async function launchInteractiveTool(toolId: string, outputs: string[]) {
  const response = await fetch('/api/interactive/launch', {
    method: 'POST',
    body: JSON.stringify({
      tool_id: toolId,
      inputs: outputs,
      template: getTemplateForTool(toolId),
      run_batch: false  // Interactive mode
    })
  });
  const { entry_point_url } = await response.json();
  window.open(entry_point_url, '_blank');
}
```

---

## Summary: Actionable Items

### Immediate (This Week)
1. Add `output_format` tracking to workflow steps
2. Create `INTERACTIVE_TOOL_SUGGESTIONS` mapping
3. Add visualization tools to tool search

### Short-term (Next 2 Weeks)
4. Create 4 template notebooks (transcriptomics, single-cell, variants, metagenomics)
5. Implement post-workflow suggestion UI
6. Add one-click interactive tool launch

### Medium-term (Month)
7. Build comprehensive notebook template library
8. Add batch notebook execution to workflows
9. Implement output format auto-detection

---

## Appendix: Full Output Format to Tool Mapping

```python
OUTPUT_FORMAT_TOOL_MAP = {
    # Alignment outputs
    "bam": {
        "visualization": ["plotCoverage", "bamCoverage"],
        "interactive": ["interactive_tool_bam_iobio"],
        "qc": ["samtools_flagstat", "samtools_stats"]
    },

    # Variant outputs
    "vcf": {
        "visualization": ["bcftools_stats", "variant_annotator"],
        "interactive": ["interactive_tool_vcf_iobio"],
    },

    # Single-cell
    "h5ad": {
        "visualization": ["scanpy_plot_umap", "scanpy_plot_dotplot"],
        "interactive": ["interactive_tool_cellxgene", "interactive_tool_isee"],
    },

    # Expression
    "count_matrix": {
        "visualization": ["plotPCA", "plotCorrelation", "heatmap2"],
        "interactive": ["interactive_tool_jupyter_notebook", "interactive_tool_rstudio"],
    },

    # DE results
    "de_table": {
        "visualization": ["volcanoplot", "ma_plot", "heatmap2"],
        "interactive": ["interactive_tool_rstudio"],
    },

    # Metagenomics
    "kraken_report": {
        "visualization": ["krona_pie_chart"],
        "interactive": ["interactive_tool_pavian"],
    },
    "biom": {
        "visualization": ["alpha_diversity", "beta_diversity_plot"],
        "interactive": ["interactive_tool_phinch"],
    },

    # ChIP-seq
    "narrowPeak": {
        "visualization": ["plotProfile", "computeMatrix"],
        "interactive": ["interactive_tool_higlass"],
    },
    "bigwig": {
        "visualization": ["plotHeatmap", "plotProfile"],
        "interactive": ["interactive_tool_higlass"],
    },

    # Hi-C
    "mcool": {
        "visualization": [],
        "interactive": ["interactive_tool_higlass"],
    },
}
```
