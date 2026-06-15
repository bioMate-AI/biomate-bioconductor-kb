---
name: bioconductor-demuxmix
description: A package for demultiplexing single-cell sequencing experiments of pooled cells labeled with barcode oligonucleotides. The package implements methods to fit regression mixture models for a probabilistic classification of cells, including multiplet detection. Demultiplexing error rates can be estimated, and methods for quality control are provided.
when_to_use: Use when: A package for demultiplexing single-cell sequencing experiments of pooled cells labeled with barcode oligonucleotides; installation.install using install; quickstartSimulate using rbind, dmmSimulateHto; quickstartDdemuxmix using demuxmix, summary; quickstartHistogram using plotDmmHistogram; simulate using rbind, dmmSimulateHto. Not for: Requires R ≥ 4.0.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# demuxmix

## Workflows

### Standard Workflow

Demultiplex pooled single-cell samples labeled with multiple hashtag oligonucleotides (HTOs) using regression or naive mixture models.

```r
library(demuxmix)

# Simulate a small example dataset
set.seed(2642)
class <- rbind(
  c(rep(TRUE, 220), rep(FALSE, 200)),
  c(rep(FALSE, 200), rep(TRUE, 220))
)
simdata <- dmmSimulateHto(class)
hto <- simdata$hto
rna <- simdata$rna

# Run demuxmix and summarize results
dmm <- demuxmix(hto, rna = rna)
summary(dmm)

# Classify droplets and plot QC histogram
classes <- dmmClassify(dmm)
table(classes$HTO)
plotDmmHistogram(dmm)
```
*Input/Output Note*: Inputs an HTO count matrix and a vector of detected genes per droplet; outputs a classified data frame of singlets, multiplets, negatives, and uncertain droplets.

### Pooling Non Labeled With Labeled Cells

Demultiplex a mixture of labeled cells and non-labeled cells (e.g., rare cells) using a single HTO channel.

```r
library(demuxmix)
data(csf)

# Filter out low-quality droplets
csf <- csf[csf$NumGenes >= 200, ]
hto <- t(matrix(csf$HTO, dimnames = list(rownames(csf), "HTO")))

# Fit regression mixture model
dmm <- demuxmix(hto, rna = csf$NumGenes)
summary(dmm)
dmmOverlap(dmm)

# Generate QC plots
plotDmmHistogram(dmm)
plotDmmScatter(dmm)

# Classify droplets into labeled (positive) and non-labeled (negative)
class <- dmmClassify(dmm)
table(class$HTO)
```
*Input/Output Note*: Inputs a single-channel HTO matrix and a vector of detected genes; outputs classifications separating labeled cells (positive) from non-labeled cells (negative).

## When to Use
- To demultiplex pooled single-cell RNA-seq samples labeled with hashtag oligonucleotides (HTOs) using negative binomial regression mixture models via `demuxmix()`.
- To leverage the positive association between the number of detected genes per droplet and HTO counts to improve classification accuracy.
- To identify multiplets and estimate false discovery rates (FDR) using `summary()`.
- To demultiplex a mixture of labeled cells (e.g., PBMCs) and non-labeled cells (e.g., rare CSF cells) using a single HTO channel.

## When NOT to Use
- For demultiplexing genetically diverse pooled samples without HTOs; use genetic demultiplexing tools like `freemuxlet` because `demuxmix` requires HTO count data.
- For general cell clustering or cell-type annotation; use `Seurat` or `scran` because `demuxmix` is strictly for sample demultiplexing.
- For processing raw FASTQ files into count matrices; use `CellRanger` or `Alevin` because `demuxmix` requires pre-computed HTO and RNA count matrices.

## Data Requirements
- **Input format**: A raw HTO count matrix (HTOs as rows, droplets/cells as columns) and a vector of the number of detected genes per droplet (RNA).
- **Structure**: Droplets must be pre-filtered to remove empty and low-quality droplets (e.g., using `emptyDrops`).
- **Normalization**: Raw, untransformed integer counts are required for both HTO and gene counts.

## Key Parameters
- **rna** (`NULL`): A numeric vector containing the number of detected genes per droplet.
- **model** (`"regression"`): Character string specifying the mixture model type (`"regression"` or `"naive"`).
- **pAcpt** (`0.9` or `0.729` depending on model): The minimum posterior probability required to classify a droplet; droplets below this are marked as `"uncertain"`.

## Best Practices
- Remove empty and low-quality droplets using `emptyDrops` before running `demuxmix()`.
- Use the default regression mixture model (`model = "regression"`) to leverage the positive correlation between HTO counts and detected genes.
- Verify the model fit by plotting density histograms overlaid with the mixture probability mass function using `plotDmmHistogram()`.
- Check the overlap between positive and negative components using `dmmOverlap()`; an overlap of less than 0.03 indicates excellent separation.

## Common Pitfalls
- **Too many "uncertain" classifications**: Occurs when HTO quality is moderate or background is high. Fix: Lower the acceptance probability `pAcpt` (e.g., `pAcpt(dmm) <- 0.7` or `0`) to force classification, keeping in mind this may increase the error rate.
- **Flat red component in histogram**: Occurs when sequencing depth is very high or many samples are pooled. Fix: Use `coord_cartesian()` to zoom into the critical overlap region of the histogram.
- **Poor regression fit in negative droplets**: Occurs when background HTO staining is extremely low. Fix: The package handles this, but you can switch to `model = "naive"` if the association between HTO and gene counts is absent.

## Alternatives
- `hashedDrops` (from `DropletUtils`): For HTO demultiplexing without explicitly modeling the gene-HTO correlation.
- `Seurat` (HTODemux): For demultiplexing using a k-medoids clustering approach on normalized HTO counts.
- `freemuxlet`: For genetic demultiplexing of pooled samples from genetically unrelated donors.

## Citations
- Stoeckius et al. (2018), Genome Biology.

## References
- Homepage: bioconductor.org/packages/demuxmix
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/demuxmix/inst/doc/demuxmix.html
