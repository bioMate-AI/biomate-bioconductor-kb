# BioMate Analysis Notebook

Multi-purpose Jupyter container for automated and interactive bioinformatics visualization.

## Features

- **Galaxy Integration**: `get()` and `put()` functions for seamless data exchange
- **Pre-installed Packages**: scanpy, DESeq2, ggplot2, pandas, seaborn
- **Template Notebooks**: Ready-to-run analysis for common workflows
- **Batch Execution**: Run notebooks automatically via papermill

## Quick Start

### Build

```bash
./build.sh
```

### Interactive Mode

```bash
docker run -p 8888:8888 \
    -v /path/to/data:/import \
    -v /path/to/output:/export \
    biomate/analysis-notebook:latest
```

Open http://localhost:8888 in browser.

### Batch Mode (Automated)

```bash
# Run DESeq2 visualization on results
docker run \
    -v /path/to/de_results.tsv:/import/de_results.tsv \
    -v /path/to/output:/export \
    biomate/analysis-notebook:latest \
    papermill templates/transcriptomics/deseq2_visualization.ipynb \
             /export/executed_notebook.ipynb \
             -p PVALUE_THRESHOLD 0.01 \
             -p LOG2FC_THRESHOLD 1.5
```

## Template Notebooks

| Notebook | Domain | Inputs | Outputs |
|----------|--------|--------|---------|
| `transcriptomics/deseq2_visualization.ipynb` | RNA-seq | DE results (.tsv) | Volcano, MA, heatmap |
| `single_cell/scanpy_qc.ipynb` | scRNA-seq | AnnData (.h5ad) | QC plots, UMAP |
| `genomics/variant_summary.ipynb` | Variants | VCF stats | Summary plots |
| `metagenomics/diversity_analysis.ipynb` | Microbiome | BIOM/TSV | Alpha/beta diversity |

## Galaxy Integration

Inside notebooks, use the `galaxy_notebook` module:

```python
from galaxy_notebook import get, put, list_inputs

# List available input files
for f in list_inputs():
    print(f"{f['index']}: {f['name']}")

# Load input data
df = get(0)  # By index
df = get("counts.tsv")  # By name
path = get(0, format='path')  # Get path only

# Save outputs (auto-uploaded to Galaxy)
put(df, "results.tsv")
put(fig, "plot.png")  # matplotlib figure
put("report.md", "Analysis Report")
```

## Environment Variables

| Variable | Description | Set By |
|----------|-------------|--------|
| `GALAXY_URL` | Galaxy server URL | Galaxy |
| `GALAXY_API_KEY` | User's API key | Galaxy (injected) |
| `HISTORY_ID` | Current history ID | Galaxy |
| `INPUT_PATHS` | Comma-separated input paths | BioMate |

## Directory Structure

```
/import/          # Input files (read-only, mounted by Galaxy)
/export/          # Output files (written by notebook)
/home/jovyan/     # Working directory
  templates/      # Pre-built analysis notebooks
    transcriptomics/
    single_cell/
    genomics/
    metagenomics/
```

## Extending

To add new template notebooks:

1. Create notebook in `templates/<domain>/`
2. Use `galaxy_notebook` for I/O
3. Add `parameters` cell tag for papermill support
4. Rebuild image
