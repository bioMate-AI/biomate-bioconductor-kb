---
name: bioconductor-macsr
description: The Model-based Analysis of ChIP-Seq (MACS) is a widely used toolkit for identifying transcript factor binding sites. This package is an R wrapper of the lastest MACS3.
when_to_use: Use when: ChIP-seq peak analysis (MACSr); ATAC-seq chromatin accessibility analysis (MACSr). Not for: Requires R ≥ 4.1.0
user-invocable: false
---

# MACSr

## Workflows

### Standard Workflow

```r
library(MACSr)

# Call narrow peaks
cp1 <- callpeak(CHIP, CTRL, gsize = 5.2e7, store_bdg = TRUE,
                name = "run_callpeak_narrow0", outdir = tempdir(),
                cutoff_analysis = TRUE)

# Call broad peaks
cp2 <- callpeak(CHIP, CTRL, gsize = 5.2e7, store_bdg = TRUE,
                name = "run_callpeak_broad", outdir = tempdir(),
                broad = TRUE)
```
Input: ChIP-seq treatment and control alignment files (e.g., BED or BAM format).
Output: A `macsList` object containing paths to called peaks (narrow or broad), summits, and bedGraph files.

## When to Use
- Calling narrow or broad peaks from ChIP-seq alignment files using `callpeak()`.
- Performing ATAC-seq chromatin accessibility peak calling using the Hidden Markov Model-based `hmmratac()`.
- Comparing two signal tracks in bedGraph format using `bdgcmp()` or detecting differential peaks using `bdgdiff()`.
- Predicting fragment size or d from alignment results using `predictd()`.

## When NOT to Use
- For initial sequence alignment or quality control of raw fastq files, use aligners like `Rsubread` or external tools like Bowtie2.
- For downstream peak annotation and motif discovery, use packages like `ChIPseeker` or `motifStack`.

## Data Requirements
- Alignment files in BED, BAM, or other supported formats (can be gzipped).
- Effective genome size (`gsize`) corresponding to the organism of interest.

## Key Parameters
- **gsize** (required): Effective genome size (e.g., `5.2e7` for a subset or standard values for organisms).
- **store_bdg** (FALSE): Logical indicating whether to save pileup and lambda signal tracks in bedGraph format.
- **broad** (FALSE): Logical indicating whether to call broad peaks instead of narrow peaks.
- **cutoff_analysis** (FALSE): Logical indicating whether to perform cutoff vs peak count analysis.
- **name** ("NA"): Character string prefix for output files.
- **outdir** ("."): Directory path where output files will be written.

## Best Practices
- Always provide a control/input sample (`CTRL`) to increase peak-calling specificity and reduce false positives.
- Enable `store_bdg = TRUE` to generate signal tracks for downstream visualization in genome browsers.
- Inspect the execution log stored in the `macsList` object using `cat(paste(cp1$log, collapse="\n"))` to verify model building and fragment size prediction.

## Common Pitfalls
- Using an incorrect effective genome size (`gsize`): This will lead to inaccurate p-value and q-value calculations. Ensure `gsize` matches your target organism.
- Forgetting that MACSr writes files directly to disk: Always specify a valid, writable `outdir` (e.g., `tempdir()`) to avoid permission issues.

## Alternatives
- `BayesPeak`: For Bayesian analysis of ChIP-seq data.
- `csaw`: For window-based de novo detection of differentially bound regions.

## Citations
- Zhang et al. (2008) "Model-based Analysis of ChIP-Seq (MACS)" (implied by the package description and vignette introduction).

## References
- Homepage: bioconductor.org/packages/MACSr
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/MACSr/inst/doc/MACSr.html
