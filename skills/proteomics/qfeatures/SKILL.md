---
name: bioconductor-qfeatures
description: The QFeatures infrastructure enables the management and processing of quantitative features for high-throughput mass spectrometry assays. It provides a familiar Bioconductor user experience to manages quantitative data across different assa
when_to_use: Use when: Multi-level Quantitative MS Management: Managing multi-level quantitative mass spectrometry data (e.g., PSMs, peptides, and proteins) within a single, integrated object.; Hierarchical Feature Aggregation: Performing hierarchical aggregation of quantitative features (e.g., aggregating PSMs to peptides, or peptides to proteins) using aggregateFeatures.; Data Visualization: Visualizing the hierarchic. Not for: For general-purpose multi-omics integration without hierarchical mass spectrometry relationships, use MultiAssayExperiment directly.; For single-assay data without hierarchical processing steps or multiple linked sets, use SummarizedExperiment instea
user-invocable: false
---

# QFeatures

## When to Use
- **Multi-level Quantitative MS Management**: Managing multi-level quantitative mass spectrometry data (e.g., PSMs, peptides, and proteins) within a single, integrated object.
- **Hierarchical Feature Aggregation**: Performing hierarchical aggregation of quantitative features (e.g., aggregating PSMs to peptides, or peptides to proteins) using `aggregateFeatures`.
- **Data Visualization**: Visualizing the hierarchical relationships between assays using `plot` or exploring the data interactively with `display`.
- **Tabular Data Conversion**: Converting tabular data from identification and quantification software (e.g., MaxQuant, Proteome Discoverer) into a structured object using `readQFeatures`.

## When NOT to Use
- For **general-purpose multi-omics integration** without hierarchical mass spectrometry relationships, use `MultiAssayExperiment` directly.
- For **single-assay data** without hierarchical processing steps or multiple linked sets, use `SummarizedExperiment` instead.
- For **raw sequence or genomic range manipulation**, use `GenomicRanges` or `IRanges` instead, as `QFeatures` is designed for quantitative feature matrices.

## Data Requirements
- **Input Format**: Tabular data (e.g., `data.frame`) containing quantitative columns and feature annotations.
- **Structure**: Rows represent features (e.g., quantified PSMs), and columns represent samples or multiplexing tags (e.g., TMT labels).
- **Sample Annotations**: Sample metadata provided as a `DataFrame` to the `colData` argument, containing at least the quantitative column names.

## Key Parameters
- **quantCols**: A vector of column names or indices identifying the quantitative values in the input table.
- **name**: The name to assign to a newly created assay or set (e.g., `"psms"` or `"peptides"`).
- **fun**: The mathematical function used for feature aggregation in `aggregateFeatures` (e.g., `colMeans`).
- **runCol**: The column name in the assay data used to split the table into multiple sets for multi-run experiments (e.g., `"FileName"`).
- **colData**: A `DataFrame` containing sample annotations to be matched with the quantitative columns.
- **removeEmptyCols**: Logical indicating whether to automatically detect and remove columns containing only `NA`s.
- **interactive**: Logical passed to `plot` to explore the hierarchy of assays through an interactive plotly graph.

## Best Practices
- Initialize your workflow by importing tabular data using `readQFeatures` and specifying the `quantCols`.
- Aggregate features to higher levels (e.g., PSMs to peptides) using `aggregateFeatures` with an appropriate summary function like `colMeans`.
- Use `plot` to visualize the hierarchical relationships between assays via the internal `AssayLinks`.
- Extract quantitative data using `assay()` and metadata using `rowData()` or `colData()` for downstream exploration.
- Use `longForm()` to convert the `QFeatures` object into a long table format, which is ideal for `ggplot2` visualization.

## Common Pitfalls
- **Missing values during aggregation**: `aggregateFeatures` will warn if row data contain missing values. *Fix*: Read the manual page regarding the effects of missing values on data aggregation before proceeding.
- **Overcrowded hierarchy plots**: Datasets with hundreds of batches can lead to an overcrowded `plot`. *Fix*: Use `plot(hl, interactive = TRUE)` to navigate the tree interactively.
- **Empty samples from unused labels**: Missing label channels filled with `NA`s can cause issues. *Fix*: Set `removeEmptyCols = TRUE` in `readQFeatures` to automatically drop them.
- **Multi-set sample mixing**: A quantification column might contain data from multiple samples across different MS runs. *Fix*: Provide a `runCol` to `readQFeatures` to split the table into multiple sets.

## Alternatives
- **MultiAssayExperiment**: A general-purpose container for multi-omics data, which `QFeatures` builds upon and extends for MS data.
- **SummarizedExperiment**: The standard single-assay container used as the building block for individual `QFeatures` sets.
- **SingleCellExperiment**: Used internally by `readQFeatures` before converting the data to a `QFeatures` object.

## Citations
- Gentleman, Robert C., Vincent J. Carey, Douglas M. Bates, Ben Bolstad, Marcel Dettling, Sandrine Dudoit, Byron Ellis, et al. 2004. "Bioconductor: Open Software Development for Computational Biology and Bioinformatics." Genome Biol 5 (10): 80.
- Gu, Zuguang, Roland Eils, and Matthias Schlesner. 2016. "Complex Heatmaps Reveal Patterns and Correlations in Multidimensional Genomic Data." Bioinformatics 32 (18): 2847-9.

## References
- Homepage: https://bioconductor.org/packages/QFeatures
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/QFeatures/inst/doc/QFeatures.html
