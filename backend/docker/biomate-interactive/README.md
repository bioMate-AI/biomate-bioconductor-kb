# BioMate Interactive Tools

All-in-one Docker container for bioinformatics interactive analysis tools.

## Included Tools

### Always Running
| Tool | Port | Description |
|------|------|-------------|
| Nginx | 80 | Reverse proxy & hub landing page |
| JupyterLab | 8888 | Python/R notebooks with scanpy, DESeq2 |
| RStudio Server | 8787 | R IDE with Bioconductor packages |

### On-Demand (Auto-Detected)
| Tool | Port | Trigger Files | Description |
|------|------|---------------|-------------|
| CellxGene | 5005 | `*.h5ad` | Single-cell visualization |
| iSEE | 7777 | `*.rds`, `*.RDS` | SummarizedExperiment explorer |
| HiGlass | 8989 | `*.cool`, `*.mcool` | Hi-C chromatin visualization |
| Pavian | 3838 | `*kraken*`, `*bracken*` | Metagenomics taxonomy |
| OpenRefine | 3333 | `*.csv`, `*.tsv`, `*.json` | Data cleaning tool |
| EtherCalc | 8000 | Always available | Collaborative spreadsheet |

## Architecture Support

- **ARM64** (`Dockerfile.arm64`): Uses `rocker/rstudio:4.3` base image
- **x86_64** (`Dockerfile.x86`): Uses `jupyter/datascience-notebook` + RStudio Server deb

## Building

```bash
# Auto-detect architecture
./build.sh

# Or specify version tag
./build.sh v2.0
```

## Running

```bash
# Basic run
docker run -p 8080:80 biomate/interactive:latest

# With data mounted (enables on-demand services)
docker run -p 8080:80 -v /path/to/data:/import biomate/interactive:latest
```

Access at: http://localhost:8080

## On-Demand Services

Services start automatically based on file types in `/import`:

### CellxGene (Single-Cell)
```bash
docker run -p 8080:80 -v /data/with/h5ad:/import biomate/interactive:latest
# Available at http://localhost:8080/cellxgene/
```

### iSEE (SummarizedExperiment)
```bash
docker run -p 8080:80 -v /data/with/rds:/import biomate/interactive:latest
# Available at http://localhost:8080/isee/
```

### HiGlass (Hi-C Data)
```bash
docker run -p 8080:80 -v /data/with/cooler:/import biomate/interactive:latest
# Available at http://localhost:8080/higlass/
```

### Pavian (Metagenomics)
```bash
docker run -p 8080:80 -v /data/with/kraken:/import biomate/interactive:latest
# Available at http://localhost:8080/shiny/
```

### OpenRefine (Data Cleaning)
```bash
docker run -p 8080:80 -v /data/with/csv:/import biomate/interactive:latest
# Available at http://localhost:8080/openrefine/
```

## Endpoints

| Path | Service |
|------|---------|
| `/` | Redirects to hub |
| `/hub` | Service selection landing page |
| `/jupyter` | JupyterLab |
| `/rstudio/` | RStudio Server |
| `/cellxgene/` | CellxGene (if h5ad found) |
| `/isee/` | iSEE (if rds found) |
| `/higlass/` | HiGlass (if cooler found) |
| `/shiny/` | Pavian (if kraken reports found) |
| `/openrefine/` | OpenRefine (if data files found) |
| `/ethercalc/` | EtherCalc |
| `/data/` | Browse /import directory |
| `/export/` | Browse /export directory |

## Installed Packages

### Python
- **Core**: pandas, numpy, scipy, matplotlib, seaborn, plotly, bokeh, ipywidgets
- **Single-cell**: scanpy, anndata, cellxgene
- **Genomics**: pysam, pybedtools, biopython, pyBigWig
- **Hi-C**: higlass-python, clodius, cooler
- **Other**: gseapy, adjustText, networkx, scikit-learn, bioblend

### R
- **Bioconductor**: DESeq2, edgeR, limma, clusterProfiler, ComplexHeatmap, iSEE, SingleCellExperiment, scater, scran
- **CRAN**: ggplot2, tidyverse, pheatmap, shiny, shinydashboard, plotly, DT, data.table
- **GitHub**: pavian

### Applications
- **OpenRefine**: Data cleaning and transformation
- **EtherCalc**: Collaborative spreadsheet

## Testing Results (ARM64)

Tested on: 2026-01-18

| Service | Status | Notes |
|---------|--------|-------|
| nginx | RUNNING | Reverse proxy working |
| jupyter | RUNNING | JupyterLab accessible |
| rstudio | RUNNING | RStudio Server accessible |
| cellxgene | RUNNING | Loaded test.h5ad successfully |
| shiny (pavian) | RUNNING | Detected kraken reports |

### Test Data Used
- `/tmp/biomate-test-data/test.h5ad` - Synthetic AnnData (100 cells x 50 genes)
- `/tmp/biomate-test-data/test.kreport` - Mock Kraken report

## Environment Variables

| Variable | Description |
|----------|-------------|
| `GALAXY_URL` | Galaxy server URL (for integration) |
| `HISTORY_ID` | Galaxy history ID |

## File Structure

```
biomate-interactive/
├── Dockerfile.arm64      # ARM64 build
├── Dockerfile.x86        # x86_64 build
├── build.sh              # Build script
├── startup.sh            # Container entrypoint
├── supervisord.conf      # Process manager config
├── nginx.conf            # Reverse proxy config
├── jupyter_config.py     # Jupyter configuration
└── README.md             # This file
```

## Galaxy Interactive Tools Coverage

This container provides local equivalents for the following Galaxy Interactive Tools:

| Galaxy Tool | Local Equivalent | Status |
|-------------|------------------|--------|
| `interactive_tool_jupyter_notebook` | JupyterLab | ✅ |
| `interactive_tool_rstudio` | RStudio Server | ✅ |
| `interactive_tool_cellxgene` | CellxGene | ✅ |
| `interactive_tool_isee` | iSEE | ✅ |
| `interactive_tool_higlass` | HiGlass | ✅ |
| `interactive_tool_pavian` | Pavian | ✅ |
| `interactive_tool_openrefine` | OpenRefine | ✅ |
| `interactive_tool_ethercalc` | EtherCalc | ✅ |
