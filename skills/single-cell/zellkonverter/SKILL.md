---
name: bioconductor-zellkonverter
description: Provides methods to convert between Python AnnData objects and SingleCellExperiment objects. These are primarily intended for use by downstream Bioconductor packages that wrap Python methods for single-cell data analysis. It also includes f
when_to_use: Use when: Reading a SingleCellExperiment from a .h5ad file using readH5AD.; Writing a SingleCellExperiment to a .h5ad file using writeH5AD.; Converting directly between SingleCellExperiment and Python AnnData objects in memory using SCE2AnnData and AnnData2SCE.; Setting up consistent Python environments for package developers using AnnDataDependencies.. Not for: For converting Seurat objects directly to Python, use SeuratDisk or convert to SingleCellExperiment first, because zellkonverter strictly interfaces with SingleCellExperiment.; For managing Python environments generally, use basilisk directly, as zel
user-invocable: false
---

# zellkonverter

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.22.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** cli, DelayedArray, Matrix, reticulate, S4Vectors, SingleCellExperiment, SparseArray, SummarizedExperiment
- **Imports:** basilisk, cli, DelayedArray, Matrix, reticulate, S4Vectors, SingleCellExperiment, SparseArray, SummarizedExperiment
- **Install:** `BiocManager::install("zellkonverter")`

## When to Use
- Reading a `SingleCellExperiment` from a `.h5ad` file using `readH5AD`.
- Writing a `SingleCellExperiment` to a `.h5ad` file using `writeH5AD`.
- Converting directly between `SingleCellExperiment` and Python `AnnData` objects in memory using `SCE2AnnData` and `AnnData2SCE`.
- Setting up consistent Python environments for package developers using `AnnDataDependencies`.

## When NOT to Use
- For converting Seurat objects directly to Python, use `SeuratDisk` or convert to `SingleCellExperiment` first, because `zellkonverter` strictly interfaces with `SingleCellExperiment`.
- For managing Python environments generally, use `basilisk` directly, as `zellkonverter` uses it internally but isn't a general-purpose environment manager.

## Data Requirements
- A valid `.h5ad` file on disk for reading.
- A `SingleCellExperiment` object in R for writing or conversion.
- An `AnnData` object in Python (via `reticulate`) for in-memory conversion.

## Key Parameters
- **file**: Path to the input `.h5ad` file in `readH5AD` or output destination in `writeH5AD`.
- **verbose** (FALSE): Logical indicating whether to display progress messages during conversion in `readH5AD`.
- **version**: String specifying the version of `anndata` to return dependencies for in `AnnDataDependencies` (e.g., "0.7.6").
- **env**: The basilisk environment to use, typically set to `zellkonverterAnnDataEnv()` in `basiliskRun`.

## Best Practices
- Use `basiliskRun` with `zellkonverterAnnDataEnv()` to safely execute Python code on `AnnData` objects within a controlled environment.
- Use `AnnDataDependencies()` if you are a package developer to guarantee you are using the same versions of Python packages as `zellkonverter`.
- Turn on global progress messages using `setZellkonverterVerbose(TRUE)` if you want to monitor large conversions.

## Common Pitfalls
- **Python environment mismatches**: Conversion failures due to missing or incompatible Python packages. Fix: Use `basilisk` to set up the Python environment before using `SCE2AnnData` or `AnnData2SCE`.
- **Incompatible anndata versions**: Custom environments failing to parse `.h5ad` files correctly. Fix: Check required versions with `AnnDataDependencies()` to ensure compatibility.
- **Silent execution during long conversions**: The process seems stalled when reading large `.h5ad` files. Fix: Set `verbose = TRUE` in `readH5AD` to display progress messages.

## Alternatives
- **basilisk**: For general R/Python environment management without specific single-cell object conversion.
- **reticulate**: For direct Python interoperability in R, which `zellkonverter` wraps specifically for `AnnData`.
- **scRNAseq**: For accessing standard single-cell datasets natively in R without needing `.h5ad` files.

## Citations
- Luke Zappia and Alan O'Callaghan (2021). "zellkonverter: Coercion Between Python AnnData and R SingleCellExperiment Objects." *Journal of Open Source Software*, 6(68), 3705.

## References
- Homepage: https://bioconductor.org/packages/zellkonverter
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/zellkonverter/inst/doc/zellkonverter.html
