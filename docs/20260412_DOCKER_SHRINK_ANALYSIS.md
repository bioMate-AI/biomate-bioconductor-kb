# 2026-04-12 — Docker Image Shrink Analysis

## Summary

Two BioMate Docker images account for the majority of pull time and storage cost:
- `biomate-interactive` (161-line Dockerfile): all-in-one Jupyter + RStudio + CellxGene
- `biomni-tools` (112-line Dockerfile): ViennaRNA + AutoDock Vina + RDKit + pharmacology stack

This document: (1) estimates current sizes, (2) proposes split strategies, (3) maps each split image to the workflows that use it.

---

## Current State

### `biomate-interactive` — Estimated 9–14 GB

Built on `jupyter/datascience-notebook:python-3.11` (already ~3 GB), then adds:

| Layer | Estimated size |
|-------|---------------|
| Base jupyter/datascience-notebook | ~3.0 GB |
| RStudio Server binary (.deb) | ~400 MB |
| mamba: scanpy, anndata, bioblend, igv-notebook | ~800 MB |
| mamba: bioconductor-deseq2, edger, limma, etc. | ~1.5 GB |
| R packages: ggplot2, tidyverse, shiny, pheatmap, plotly | ~600 MB |
| pip: cellxgene, gseapy, streamlit, dash | ~400 MB |
| Pavian (R Shiny) | ~200 MB |
| Config files, nginx, supervisor | ~50 MB |
| **Total estimate** | **~7–9 GB** |

No workflow uses all three services simultaneously:
- Bioinformatics code notebooks → Jupyter only
- R/Bioconductor analysis → RStudio only  
- Single-cell visualization → CellxGene only
- Pathogen classification/visualization → Pavian only (RStudio base)

### `biomni-tools` — Estimated 3.5–5 GB

Built on `biomate-nextflow-base` (~1.5 GB with AWS CLI + base Python stack), then adds:

| Layer | Estimated size |
|-------|---------------|
| biomate-nextflow-base (AWS CLI, numpy, scipy, rdkit, biopython) | ~1.5 GB |
| scikit-learn, matplotlib, requests, pubchempy | ~300 MB |
| ViennaRNA | ~200 MB |
| AutoDock Vina + Meeko + openbabel-wheel | ~500 MB |
| codon-tools, python-codon-tables | ~50 MB |
| adjustText, seaborn, plotly | ~200 MB |
| statsmodels, scikit-image | ~300 MB |
| DeepPurpose (MPNN/CNN ADMET) | ~800 MB |
| **Total estimate** | **~3.8–4.8 GB** |

---

## Proposed Splits

### `biomate-interactive` → 3 images

#### 1. `biomate-jupyter` (~3.5 GB, 55% of original)
```dockerfile
FROM jupyter/datascience-notebook:python-3.11
# Python bioinformatics stack only
RUN mamba install -y -c conda-forge -c bioconda \
    pandas numpy scipy matplotlib seaborn plotly bokeh \
    scanpy anndata pysam pyvcf3 biopython pybedtools \
    bioblend pygenometracks igv-notebook h5py openpyxl
RUN pip install --no-cache-dir cellxgene jupyterlab-git gseapy
# Bioconductor: DE analysis only
RUN mamba install -y -c bioconda \
    bioconductor-deseq2 bioconductor-edger bioconductor-limma \
    bioconductor-clusterprofiler bioconductor-enrichplot
EXPOSE 8888
```

Use case: Python notebooks, Jupyter-based analysis, R/Bioconductor DE analysis.

Workflows that use it:
- `interactive_jupyter_notebook`
- Any workflow requesting an interactive Jupyter environment

#### 2. `biomate-rstudio` (~2.5 GB, 35% of original)
```dockerfile
FROM ubuntu:22.04
# Minimal R + RStudio Server + Bioconductor visualization packages
RUN apt-get install -y r-base gdebi-core && \
    curl -o rstudio.deb https://download2.rstudio.org/server/jammy/amd64/rstudio-server-2023.12.1-402-amd64.deb && \
    gdebi -n rstudio.deb
RUN R -e "install.packages(c('ggplot2','pheatmap','ggrepel','viridis','tidyverse','data.table'))"
RUN R -e "BiocManager::install(c('ComplexHeatmap','GenomicRanges','rtracklayer'))"
EXPOSE 8787
```

Use case: R-heavy statistical analysis, custom visualization, Bioconductor workflows that need RStudio IDE.

Workflows that use it:
- `rstudio_deseq2_analysis`
- `r_shiny_dashboard`
- Any workflow producing R markdown reports

#### 3. `biomate-cellxgene` (~1.2 GB, 13% of original)
```dockerfile
FROM python:3.11-slim
RUN pip install --no-cache-dir cellxgene anndata scanpy h5py
EXPOSE 5005
CMD ["cellxgene", "launch", "--host", "0.0.0.0", "--port", "5005"]
```

Use case: Single-cell data visualization, CellxGene browser for `.h5ad` files.

Workflows that use it:
- `cellxgene_visualization`
- `single_cell_atlas_browser`
- Any workflow with `.h5ad` output that needs interactive browsing

**Estimated size reduction: ~9 GB → 3 separate images of 3.5 + 2.5 + 1.2 GB = 7.2 GB total (but each workflow pulls only ~30–40% of the original)**

---

### `biomni-tools` → 3 images

The key insight: ViennaRNA (RNA tools), AutoDock Vina (docking), and DeepPurpose (ADMET) are almost never needed in the same workflow step. Split by domain:

#### 1. `biomni-cheminformatics` (~2.8 GB, 60% of original)
```dockerfile
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest
# Cheminformatics: RDKit already in base, add Vina + docking tools
RUN pip install --no-cache-dir vina meeko openbabel-wheel gemmi pubchempy
RUN pip install --no-cache-dir scikit-learn matplotlib seaborn plotly adjustText
```

Workflows: `predict_admet_properties`, `virtual_screening`, `molecular_docking`, `cro_submission_export`, `assay_ingestion_and_ranking`

#### 2. `biomni-rna-structure` (~2.2 GB, 47% of original)
```dockerfile
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest
RUN pip install --no-cache-dir ViennaRNA codon-tools python-codon-tables
RUN pip install --no-cache-dir biopython matplotlib seaborn
```

Workflows: `predict_rna_secondary_structure`, `rna_folding_mfe`, `codon_optimization`, `synthetic_biology_part_design`

#### 3. `biomni-pharmacology` (~3.5 GB, 73% of original)
```dockerfile
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest
RUN pip install --no-cache-dir statsmodels scikit-image seaborn plotly
RUN pip install --no-cache-dir DeepPurpose || echo "DeepPurpose fallback"
# Pharmacology-specific: xenograft, western blot, MWAS, ADMET deep models
```

Workflows: `grade_adverse_events`, `analyze_xenograft`, `analyze_western_blot`, `perform_mwas_cyp2c19`, `predict_admet_properties` (when DeepPurpose models needed)

**Estimated size reduction per workflow: 4.8 GB → 2.2–3.5 GB (30–55% reduction per pull)**

---

## Implementation Steps

1. **Measure actual ECR sizes** (requires AWS credentials):
   ```bash
   aws ecr describe-images --repository-name biomate/biomate-interactive \
     --query 'imageDetails[*].imageSizeInBytes' --output text
   aws ecr describe-images --repository-name biomate/biomni-tools \
     --query 'imageDetails[*].imageSizeInBytes' --output text
   ```

2. **Build split images** (AMD64 for Batch):
   ```bash
   docker buildx build --platform linux/amd64 \
     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomate-jupyter:latest \
     -f backend/docker/biomate-jupyter/Dockerfile --push .
   ```

3. **Update workflow container directives**: grep all `.nf` files for `biomate-interactive` and `biomni-tools`, remap to the correct split image.

4. **Deprecate originals** after all workflows are migrated.

---

## Workflow → Image Mapping (Current)

```bash
# Workflows currently using biomni-tools
grep -r "biomni-tools" backend/biomni_workflows/ --include="*.nf" -l | wc -l
# Expected: 100+ workflows

# Workflows currently using biomate-interactive
grep -r "biomate-interactive" backend/biomni_workflows/ --include="*.nf" -l | wc -l
# Expected: 5-10 workflows
```

---

## Priority

| Image | Effort | Impact | Priority |
|-------|--------|--------|----------|
| `biomate-cellxgene` (new) | Low (1 day) | High (independent, tiny) | P1 |
| `biomni-cheminformatics` | Medium (2 days) | High (100+ workflows benefit) | P1 |
| `biomni-rna-structure` | Low (1 day) | Medium | P2 |
| `biomate-rstudio` (standalone) | Medium (2 days) | Medium | P2 |
| `biomate-jupyter` (slimmed) | High (3 days, requires migration) | Medium | P3 |
| `biomni-pharmacology` | Medium (2 days) | Medium | P2 |
