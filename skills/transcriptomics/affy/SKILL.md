---
name: bioconductor-affy
description: The package contains functions for exploratory oligonucleotide array analysis. The dependence on tkWidgets only concerns few convenience functions. 'affy' is fully functional without it.
when_to_use: Use when: Importing and summarizing raw Affymetrix probe-level data into an ExpressionSet using classic algorithms like rma() or mas5().; Performing quality control and exploratory data analysis on Affymetrix expression microarrays using MAplot(), boxplot(), and image().; Assessing 5'-to-3' RNA degradation gradients across samples using AffyRNAdeg() and plotAffyRNAdeg().. Not for: For newer Affymetrix Gene ST or Exon ST arrays, use oligo instead, because affy does not correctly handle the probe-design structure of these newer generation chips.; For Illumina, Agilent, or other non-Affymetrix microarray platforms, use limma or b
user-invocable: false
---

# affy

## When to Use
- Importing and summarizing raw Affymetrix probe-level data into an `ExpressionSet` using classic algorithms like `rma()` or `mas5()`.
- Performing quality control and exploratory data analysis on Affymetrix expression microarrays using `MAplot()`, `boxplot()`, and `image()`.
- Assessing 5'-to-3' RNA degradation gradients across samples using `AffyRNAdeg()` and `plotAffyRNAdeg()`.

## When NOT to Use
- For newer Affymetrix Gene ST or Exon ST arrays, use `oligo` instead, because `affy` does not correctly handle the probe-design structure of these newer generation chips.
- For Illumina, Agilent, or other non-Affymetrix microarray platforms, use `limma` or `beadarray` because `affy` is strictly hardcoded for Affymetrix CDF structures.

## Data Requirements
- **Input Format**: Raw Affymetrix data loaded as an `AffyBatch` object (e.g., the `Dilution` dataset).
- **Structure**: Probe-level data containing `pm` (perfect match) and `mm` (mismatch) intensities, mapped via a Chip Definition File (CDF) environment.
- **Normalization State**: Raw, un-normalized probe-level intensities (prior to running `normalize()` or `rma()`).

## Key Parameters
- **pairs** (TRUE): Logical in `MAplot()` indicating whether to plot pairwise comparisons between arrays.
- **plot.method** ("smoothScatter"): Character string in `MAplot()` specifying the method for plotting dense data.
- **col** (c(2,3,4)): Vector of colors passed to `boxplot()` to differentiate arrays.
- **genenames** (NULL): Vector of probe set names to extract specific data in `probeset()`, `pmindex()`, or `mmindex()`.
- **locations** (NULL): A list of physical `pm` and `mm` coordinates passed to `probeset()` for custom probe set definitions.
- **which** ("pm"): Character string in `indexProbes()` specifying which probes to index ("pm", "mm", or "both").
- **addcdf** (FALSE): Logical in `cleancdfname()` indicating whether to append "cdf" to the environment name.
- **compress.cel** (TRUE): Logical option set via `options()` to allow reading compressed `.CEL` files.

## Best Practices
- Run `AffyRNAdeg()` and `plotAffyRNAdeg()` to check for RNA degradation gradients across samples before proceeding with normalization.
- Use `MAplot()` with `plot.method="smoothScatter"` to visualize intensity-dependent biases between arrays.
- Use `boxplot()` to compare the distribution of raw intensities across multiple arrays before normalization.
- Extract specific probe set data using `probeset()` and inspect `pm()` and `mm()` values directly to understand probe-level behavior.

## Common Pitfalls
- **Missing CDF environment**: Functions like `getCdfInfo()` fail if the specific chip definition file (e.g., `HG_U95Av2`) is not installed. *Fix*: Install and load the corresponding CDF package from Bioconductor.
- **Memory exhaustion with large datasets**: Loading many arrays into an `AffyBatch` can consume significant memory. *Fix*: Use `rma()` to directly compute the summarized `ExpressionSet` and discard raw probe data.
- **Incorrect probe indexing**: Using `pm()` or `mm()` without knowing the exact probe locations can lead to misinterpretation. *Fix*: Use `indexProbes()` or `pmindex()` to retrieve the correct physical locations on the chip.

## Alternatives
- **oligo**: For preprocessing newer whole-transcript (WT) Affymetrix arrays.
- **affyPLM**: For advanced probe-level linear modeling and detailed quality metrics (RLE, NUSE plots).
- **limma**: For downstream differential expression analysis after `rma()` preprocessing.

## Citations
- Gautier, L. et al. (2004). "affy—analysis of Affymetrix GeneChip data at the probe level." *Bioinformatics*, 20(3), 307-315.
- Irizarry, R. A. et al. (2003). "Exploration, normalization, and summaries of high density oligonucleotide array probe level data." *Biostatistics*, 4(2), 249-264.

## References
- Homepage: https://bioconductor.org/packages/affy
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/affy/inst/doc/builtinMethods.pdf
