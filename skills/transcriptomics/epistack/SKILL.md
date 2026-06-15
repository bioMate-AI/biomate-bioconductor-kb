---
name: bioconductor-epistack
description: The epistack package main objective is the visualizations of stacks of genomic tracks (such as, but not restricted to, ChIP-seq, ATAC-seq, DNA methyation or genomic conservation data) centered at genomic regions of interest. epistack needs three different inputs: 1) a genomic score objects, such as ChIP-seq coverage or DNA methylation values, provided as a `GRanges` (easily obtained from `bigwig` or `bam` files). 2) a list of feature of interest, such as peaks or transcription start sites, provi
when_to_use: Use when: The epistack package main objective is the visualizations of stacks of genomic tracks (such as, but not restricted to, C; epistack1 using plotEpistack; bining using addBins, plotEpistack; colours using plotEpistack; par using plotEpistack; plotAvgerageProfile using plotAverageProfile. Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# epistack

## Workflows

### Standard Workflow

Visualize ChIP-seq coverage signal centered around merged peak regions, sorted and binned by peak scores.

```r
library(GenomicRanges)
library(SummarizedExperiment)
library(epistack)
library(rtracklayer)
library(EnrichedHeatmap)

# 1. Load peak files
path_peaks <- c(
    peak1 = "https://raw.githubusercontent.com/Bioconductor/CSAMA2016/master/lab-5-chipseq/EpigeneticsCSAMA/inst/bedfiles/Rep1_peaks_ucsc_chr6.bed",
    peak2 = "https://raw.githubusercontent.com/Bioconductor/CSAMA2016/master/lab-5-chipseq/EpigeneticsCSAMA/inst/bedfiles/Rep2_peaks_ucsc_chr6.bed"
)
peaks <- lapply(path_peaks, import)

# 2. Merge peaks across replicates
merged_peaks <- GenomicRanges::union(peaks[[1]], peaks[[2]])

scores_rep1 <- double(length(merged_peaks))
scores_rep1[findOverlaps(peaks[[1]], merged_peaks, select = "first")] <- peaks[[1]]$score

scores_rep2 <- double(length(merged_peaks))
scores_rep2[findOverlaps(peaks[[2]], merged_peaks, select = "first")] <- peaks[[2]]$score

peak_type <- ifelse(
    scores_rep1 != 0 & scores_rep2 != 0, "Both", ifelse(
        scores_rep1 != 0, "Rep1 only", "Rep2 only"
    )
)

mcols(merged_peaks) <- DataFrame(scores_rep1, scores_rep2, peak_type)
merged_peaks$mean_scores <- apply((mcols(merged_peaks)[, c("scores_rep1", "scores_rep2")]), 1, mean)
merged_peaks <- merged_peaks[order(merged_peaks$mean_scores, decreasing = TRUE), ]

# 3. Load aligned reads
path_reads <- c(
    rep1 = "https://raw.githubusercontent.com/Bioconductor/CSAMA2016/master/lab-5-chipseq/EpigeneticsCSAMA/inst/bedfiles/H3K27ac_rep1_filtered_ucsc_chr6.bed",
    rep2 = "https://raw.githubusercontent.com/Bioconductor/CSAMA2016/master/lab-5-chipseq/EpigeneticsCSAMA/inst/bedfiles/H3K27ac_rep2_filtered_ucsc_chr6.bed",
    input = "https://raw.githubusercontent.com/Bioconductor/CSAMA2016/master/lab-5-chipseq/EpigeneticsCSAMA/inst/bedfiles/ES_input_filtered_ucsc_chr6.bed"
)
reads <- lapply(path_reads, import)

# 4. Generate coverage matrices around peak centers
coverage_matrices <- lapply(
    reads,
    function(x) {
        normalizeToMatrix(
            x,
            resize(merged_peaks, width = 1, fix = "center"),
            extend = 5000, w = 250, 
            mean_mode = "coverage"
        )
    }
)
xlabs <- c("-5kb", "peak center", "+5kb")

# 5. Construct a SummarizedExperiment object containing the data
merged_peaks_se <- SummarizedExperiment(
    rowRanges = merged_peaks,
    assays = coverage_matrices
)

# 6. Assign peak types as bins and plot the stacked profiles
rowRanges(merged_peaks_se)$bin <- rowRanges(merged_peaks_se)$peak_type

plotEpistack(
    merged_peaks_se,
    assays = c("rep1", "rep2", "input"),
    tints = c("dodgerblue", "firebrick1", "grey"), 
    titles = c("Rep1", "Rep2" , "Input"),
    x_labels = xlabs,
    zlim = c(0, 4), ylim = c(0, 4), 
    metric_col = "mean_scores", metric_title = "Peak score",
    metric_label = "score",
    bin_palette = colorRampPalette(c("darkorchid1", "dodgerblue", "firebrick1")),
    npix_height = 300
)
```
*Note on inputs/outputs*: Input is peak BED files and read alignment files, and output is a stacked genomic track visualization.

### Promoter Epigenetics Expression

Visualize DNA methylation and ChIP-seq coverage at gene promoters (TSS) sorted and binned by gene expression levels.

```r
library(GenomicRanges)
library(SummarizedExperiment)
... [vignette text truncated]
# 1. Read the declared user input files from the working directory
load(
  system.file("extdata", "chr21_test_data.RData", package = "EnrichedHeatmap"),
  verbose = TRUE
)

# 2. Extract TSS coordinates using GenomicRanges::promoters
tss <- promoters(genes, upstream = 0, downstream = 1)
tss$gene_id <- names(tss)

# 3. Merge expression data with TSS coordinates and sort them
expr <- data.frame(
  gene_id = names(rpkm),
  expr = rpkm
)
epidata <- addMetricAndArrangeGRanges(
  tss,
  expr,
  gr_key = "gene_id",
  order_key = "gene_id",
  order_value = "expr"
)

# 4. Partition the genes into expression bins
epidata <- addBins(epidata, nbins = 5)

# 5. Extract DNA methylation and ChIP-seq signals around TSS
methstack <- normalizeToMatrix(
  meth, epidata, value_column = "meth", extend = 5000, w = 250, mean_mode = "absolute"
)
h3k4me3stack <- normalizeToMatrix(
  H3K4me3, epidata, value_column = "coverage", extend = 5000, w = 250, mean_mode = "coverage"
)

# 6. Assemble the data into a SummarizedExperiment object
epidata_se <- SummarizedExperiment(
  rowRanges = epidata,
  assays = list(DNAme = methstack, H3K4me3 = h3k4me3stack)
)

# 7. Plot the multi-track stacked profiles
plotEpistack(
  epidata_se,
  tints = c("dodgerblue", "orange"),
  zlim = list(c(0, 1), c(0, 25)),
  ylim = list(c(0, 1), c(0, 50)),
  x_labels = c("-5kb", "TSS", "+5kb"),
  legends = c("%mCpG", "Coverage"),
  metric_col = "expr",
  metric_title = "Gene expression",
  metric_label = "log10(RPKM+1)",
  metric_transfunc = function(x) log10(x + 1),
  npix_height = 300
)
```
*Note on inputs/outputs*: Input is genomic coordinates, expression data, and epigenetic signal tracks, and output is a multi-track stacked profile plot.

## When to Use
- Visualizing stacks of genomic tracks (e.g., ChIP-seq coverage, DNA methylation, ATAC-seq) centered at genomic regions of interest using `plotEpistack()`.
- Partitioning genomic regions into bins based on quantitative metrics using `addBins()`.
- Plotting individual panels of stacked profiles or average profiles using `plotStackProfile()` and `plotAverageProfile()`.
- Merging and sorting genomic ranges with associated quantitative metrics using `addMetricAndArrangeGRanges()`.

## When NOT to Use
- For plotting non-centered, continuous genomic tracks across large chromosomal regions, use packages like `Gviz` or `Sushi` because `epistack` is designed specifically for windowed, centered stack profiles.
- For general non-genomic heatmaps, use `ComplexHeatmap` or `pheatmap` because `epistack` requires genomic coordinates (`GRanges` or `RangedSummarizedExperiment`).

## Data Requirements
- **Input format**: A `RangedSummarizedExperiment` object (e.g., `stackepi`) where assays contain matrices of genomic scores (e.g., coverage or methylation values) across windowed genomic bins.
- **Row ranges**: `GRanges` object representing the centered genomic regions of interest (e.g., peaks, promoters, TSS).
- **Metadata**: A numeric column in `rowData` (e.g., `"exp"`, `"mean_scores"`) to sort the features.

## Key Parameters
- **assay**: Name of the assay in the `SummarizedExperiment` to display as a heatmap.
- **metric_col**: Name of the column in `rowData` containing the sorting metric.
- **nbins**: Number of bins to partition the genomic regions into when calling `addBins()`.
- **ylim**: Y-axis limits for the average profile plot.
- **zlim**: Limits for the heatmap intensity scale.
- **x_labels**: Character vector of labels for the X-axis (e.g., `c("-5kb", "TSS", "+5kb")`).
- **tints**: Color or vector of colors to tint the heatmaps.
- **bin_palette**: Palette function used to color-code the bins.

## Best Practices
- Ensure all genomic tracks are aligned to the same genome assembly version before extracting coordinates and signals.
- Sort the `RangedSummarizedExperiment` object by the metric of interest (e.g., using `addMetricAndArrangeGRanges()`) prior to plotting to ensure the stack profile displays a clear gradient.
- Use `addBins()` to group genomic regions (e.g., high vs. low expression) to generate distinct average profiles in the lower panel of the epistack plot.

## Common Pitfalls
- Mismatched row names or keys when merging expression data with GRanges: This will result in missing metric values. Fix by using `addMetricAndArrangeGRanges()` with correct `gr_key` and `order_key` parameters.
- Inconsistent window sizes in the assay matrices: If the matrices in the assays have different numbers of columns, `plotEpistack()` will fail. Fix by ensuring all matrices are generated with the same window parameters in `normalizeToMatrix()`.

## Alternatives
- `EnrichedHeatmap`: For highly customizable enriched heatmaps with complex annotations.
- `ChIPseeker`: For annotating and plotting ChIP-seq peaks relative to TSS.
- `Gviz`: For plotting genomic tracks along genomic coordinates rather than centered stack profiles.

## Citations
- Safia Saci, Guillaume Devailly. epistack: An R package to visualise stack profiles of epigenomic signals. 2021, <hal-03401251v2>.

## References
- Homepage: https://bioconductor.org/packages/epistack
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/epistack/inst/doc/epistack.html
