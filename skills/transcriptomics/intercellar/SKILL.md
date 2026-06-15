---
name: bioconductor-intercellar
description: InterCellar is implemented as an R/Bioconductor Package containing a Shiny app that allows users to interactively analyze cell-cell communication from scRNA-seq data. Starting from precomputed ligand-receptor interactions, InterCellar provides filtering options, annotations and multiple visualizations to explore clusters, genes and functions. Finally, based on functional annotation from Gene Ontology and pathway databases, InterCellar implements data-driven analyses to investigate cell-cell comm
when_to_use: Use when: InterCellar User Guide; Single-cell RNA-seq analysis (InterCellar). Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# InterCellar

## Workflows

### Standard Workflow

Launch the interactive Shiny application to analyze cell-cell communication from precomputed ligand-receptor interactions.

```r
library(InterCellar)
InterCellar::run_app(reproducible = TRUE)
```
*Input: Precomputed ligand-receptor interaction tables (e.g., from CellPhoneDB, CellChat, ICELLNET, or SingleCellSignalR). Output: Interactive Shiny interface in a web browser for filtering, annotation, and visualization.*

## When to Use
- To interactively analyze and visualize cell-cell communication (CCI) from single-cell RNA-seq data using precomputed ligand-receptor interactions.
- To perform functional annotation of interaction pairs using Gene Ontology or pathway databases (via `graphite` or `biomaRt`).
- To compare cell-cell communication across multiple conditions (up to 3) using cluster-based, gene-based, or function-based approaches.

## When NOT to Use
- For performing the initial prediction of ligand-receptor interactions from raw scRNA-seq counts; use tools like `CellChat`, `CellPhoneDB`, or `SingleCellSignalR` instead.
- For non-interactive, high-throughput command-line pipeline execution of cell-cell communication analysis; use `CellChat` or `scran` directly in R.

## Data Requirements
- Precomputed cell-cell interaction (CCI) results from supported tools (CellPhoneDB, CellChat, ICELLNET, SingleCellSignalR) or custom tables containing interaction pairs and scores.
- Output folder path on the local drive where InterCellar can save figures and tables.

## Key Parameters
- **reproducible** (`TRUE`): Flag in `run_app()` to ensure results are reproducible across R sessions.

## Best Practices
- Run the app with `reproducible = TRUE` to ensure analysis consistency across sessions.
- Specify an existing local folder for saving output tables and figures before uploading data.
- Ensure cluster names are consistent across compared conditions when performing multiple-condition analysis.

## Common Pitfalls
- *App does not open automatically*: If the browser does not launch, manually copy and navigate to the local address (e.g., `http://127.0.0.1:6134`) shown in the R console.
- *Inconsistent cluster names in multiple conditions*: Comparing conditions with different cluster compositions can lead to misleading radar or bar plots; ensure cluster names are identical or highly similar.
- *Global filtering effects*: Applying strict p-value or interaction score thresholds in the Cluster-verse will globally subset the dataset and affect downstream Gene-verse and Function-verse analyses.

## Alternatives
- `CellChat` for R-based mechanistic modeling and comparison of cell-cell communication.
- `SingleCellSignalR` for simple ligand-receptor interaction predictions and network construction.
- `scater` / `scran` for general single-cell RNA-seq preprocessing and clustering.

## Citations
- Efremova et al. 2020, Nature Protocols (CellPhoneDBv2)
- Jin et al. 2021, Nature Communications (CellChat)
- Chua et al. 2020, Nature Biotechnology (COVID-19 dataset)

## References
- Homepage: https://bioconductor.org/packages/intercellar
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/intercellar/inst/doc/vignette.html
