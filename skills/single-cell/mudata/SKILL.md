---
name: bioconductor-mudata
description: Save MultiAssayExperiments to h5mu files supported by muon and mudata. Muon is a Python framework for multimodal omics data analysis. It uses an HDF5-based format for data storage.
when_to_use: Use when: Blood CITE-seq with MuData with MuData; Cord Blood CITE-seq with MuData with MuData; Getting started with MuDataMae with MuData. Not for: MuData requires R/Bioconductor; see installation guide
user-invocable: false
---

# MuData

## Workflows

### Standard Workflow

Save MultiAssayExperiments to h5mu files supported by muon and mudata. Muon is a Python framework for multimodal omics data analysis. It uses an HDF5-based format for data storage.

```r
library(MuData)
library(MultiAssayExperiment)

# Write a MultiAssayExperiment object to an H5MU file
writeH5MU(mae, "citefuse_example.h5mu")

# Read an H5MU file back into a MultiAssayExperiment object (backed on disk)
mae_backed <- readH5MU("citefuse_example.h5mu", backed = TRUE)
```

*Input:* A `MultiAssayExperiment` object containing multimodal single-cell data. *Output:* An HDF5-based `.h5mu` file written to disk, or a `MultiAssayExperiment` object read from disk.

## When to Use
- To save multimodal datasets represented as `MultiAssayExperiment` objects into `.h5mu` files using `writeH5MU` for cross-platform sharing with Python frameworks like `muon` or `mudata`.
- To read `.h5mu` files into R as `MultiAssayExperiment` objects using `readH5MU`.
- To load large-scale multimodal datasets on-disk without loading them fully into memory by setting `backed = TRUE` in `readH5MU` to return a `DelayedMatrix`.

## When NOT to Use
- For storing unimodal datasets, use standard `AnnData` formats or `writeH5AD` because `MuData` is specifically designed for multimodal data.
- For saving complex R-specific objects that have no HDF5/Python equivalent, use `saveRDS` because `writeH5MU` only exports standard modalities and metadata.
- For performing downstream single-cell analysis (like clustering or differential expression) directly on the `.h5mu` file, use packages like `scran` or `Seurat` because `MuData` is strictly an I/O interface.

## Data Requirements
- **Input format:** `MultiAssayExperiment` containing experiments of class `SingleCellExperiment`, `SummarizedExperiment`, or `matrix`.
- **Structure:** Multiple modalities (e.g., `RNA`, `ADT`, `HTO`) stored as distinct experiments within the `MultiAssayExperiment`.
- **Normalization state:** Can store both raw counts (e.g., in `counts` assay) and normalized counts (e.g., in `logcounts` or `clr` assays).

## Key Parameters
- **backed** (FALSE): If set to `TRUE` in `readH5MU`, keeps matrices on disk and loads them as `DelayedMatrix` objects to save memory.

## Best Practices
- Ensure all modalities are properly aligned and harmonized within a `MultiAssayExperiment` before writing.
- Store normalized assays (e.g., `logcounts` or `clr`) in the corresponding experiment layers alongside raw counts.
- Use `backed = TRUE` when reading very large `.h5mu` files to prevent out-of-memory errors.

## Common Pitfalls
- Attempting to read unsupported Python-specific structures (like pairwise graphs or multimodal embeddings) into R: `readH5MU` will skip these because `MultiAssayExperiment` does not natively support them.
- Writing mixed data types or unharmonized sample maps: Ensure the `MultiAssayExperiment` is harmonized using standard constructor checks before calling `writeH5MU`.

## Alternatives
- `SingleCellMultiModal` for downloading pre-packaged multimodal datasets.
- `rhdf5` for low-level HDF5 file manipulation in R.
- `Seurat` for an alternative single-cell multimodal object representation and I/O.

## Citations
- Ramos M, Schiffer L, Re A, Azhar R, Basunia A, Cabrera CR, Chan T, Chapman P, Davis S, Gomez-Cabrero D, Culhane AC, Haibe-Kains B, Hansen K, Kodali H, Louis MS, Mer AS, Reister M, Morgan M, Carey V, Waldron L (2017). "Software For The Integration Of Multi-Omics Experiments In Bioconductor." Cancer Research, 77(21); e39-42.

## References
- Homepage: bioconductor.org/packages/mudata
- Vignette: bioconductor.org/packages/release/bioc/vignettes/mudata/inst/doc/mudata.html
