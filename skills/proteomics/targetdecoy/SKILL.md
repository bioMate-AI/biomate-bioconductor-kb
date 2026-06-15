---
name: bioconductor-targetdecoy
description: A first step in the data analysis of Mass Spectrometry (MS) based proteomics data is to identify peptides and proteins. With this respect the huge number of experimental mass spectra typically have to be assigned to theoretical peptides derived from a sequence database. Search engines are used for this purpose. These tools compare each of the observed spectra to all candidate theoretical spectra derived from the sequence data base and calculate a score for each comparison. The observed spectrum
when_to_use: Use when: Introduction to TargetDecoy; Proteomics quantification (TargetDecoy); Quality control and preprocessing (TargetDecoy). Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# TargetDecoy

## Workflows

### Standard Workflow

A first step in the data analysis of Mass Spectrometry (MS) based proteomics data is to identify peptides and proteins. With this respect the huge number of experimental mass spectra typically have to be assigned to theoretical peptides derived from a sequence database. Search engines are used for this purpose. These tools compare each of the observed spectra to all candidate theoretical spectra derived from the sequence data base and calculate a score for each comparison. The observed spectrum

```r
library(TargetDecoy)
data("ModSwiss")

# 1. Combined 4-plot grid (PP-plot, Histogram, and their zoomed versions)
evalTargetDecoys(ModSwiss, decoy = "isdecoy", score = "ms-gf:specevalue", log10 = TRUE, nBins = 50)

# 2. Individual Histogram
evalTargetDecoysHist(ModSwiss, decoy = "isdecoy", score = "ms-gf:specevalue", log10 = TRUE, nBins = 50)

# 3. Individual PP-plot
evalTargetDecoysPPPlot(ModSwiss, decoy = "isdecoy", score = "ms-gf:specevalue", log10 = TRUE)
```
*Note: Input is a data.frame (or mzID/mzRident object) containing target/decoy designations and search engine scores; outputs are ggplot objects representing diagnostic plots.*

## When to Use
- **Evaluating Target-Decoy Approach (TDA) assumptions**: Generate diagnostic PP-plots and histograms to check if decoy PSM scores are a good simulation of incorrect target PSM scores.
- **Comparing multiple search engines**: Evaluate and compare the performance of different search engines (e.g., MS-GF+, OMSSA, X!Tandem) or search runs using `createPPlotScores()` and `createPPlotObjects()`.

## When NOT to Use
- **For calculating false discovery rates (FDR)**: For peptide/protein quantification or FDR calculation directly, use packages like `MSstats` or `QFeatures` because `TargetDecoy` is strictly for diagnostic evaluation of TDA assumptions.
- **For raw mass spectrometry data visualization**: For plotting raw spectra or chromatograms, use `Spectra` or `Chromatograms` because `TargetDecoy` operates on search engine output scores (PSMs).

## Data Requirements
- **Input Format**: An object of class `mzID` (created via `mzID::mzID()`), `mzRident` (created via `mzR::openIDfile()`), or a standard `data.frame` (e.g., `ModSwiss`).
- **Decoy Indicator**: A boolean variable indicating whether each match is a decoy (typically `"isdecoy"` or `"isDecoy"`).
- **Search Engine Score**: A continuous score variable from a database search engine (e.g., `"ms-gf:specevalue"`, `"x!tandem:expect"`), where larger scores indicate better matches (e-values should be log-transformed).

## Key Parameters
- **object**: An `mzID`, `mzRident`, or `data.frame` object containing the PSM search results.
- **decoy**: Character string specifying the column name indicating decoy status.
- **score**: Character string specifying the column name containing the search engine scores.
- **log10** (TRUE): Logical indicating whether the score should be -log10 transformed (typically used for e-values).
- **nBins** (50): Integer specifying the number of bins in the histogram.
- **zoom** (FALSE): Logical indicating whether to zoom in on the PP-plot or histogram.
- **scores**: Character vector of score variable names for comparing multiple search engines in `createPPlotScores()`.

## Best Practices
- Always check both the histogram and the PP-plot; a linear PP-plot at lower percentiles confirms that the decoy distribution matches the bad target distribution.
- Log-transform e-values or expectation values (set `log10 = TRUE`) so that larger values represent better matches, aligning with the package's assumptions.
- Use `createPPlotScores()` to evaluate how multi-stage search strategies (like X!Tandem's second pass) or combined search engines (like PeptideShaker) affect TDA assumptions.

## Common Pitfalls
- **Violating TDA assumptions via two-pass searches**: Refined searches against subsetted databases (e.g., X!Tandem) can cause decoy scores to be unrepresentative of bad target scores, visible as a deviation from the $\pi_0$ line in the PP-plot.
- **Incorrect score orientation**: Ensure that the score used has larger values for better matches; if not, apply appropriate transformations (e.g., `-log10`).
- **Unknown variable names**: If variable names are unknown, call `evalTargetDecoys()` with only the input object to launch the interactive Shiny gadget.

## Alternatives
- **MSstats**: For statistical relative quantification of proteins and peptides.
- **MSnbase**: For processing and plotting raw mass spectrometry data and quantitative features.
- **Spectra**: For low-level representation and handling of mass spectrometry raw spectra.

## Citations
- Debrie E, Clement L, Malfait M (2026). TargetDecoy: Diagnostic Plots to Evaluate the Target Decoy Approach. doi:10.18129/B9.bioc.TargetDecoy. R package version 1.18.0.

## References
- Homepage: https://bioconductor.org/packages/TargetDecoy
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/TargetDecoy/inst/doc/Introduction_to_TargetDecoy.html
