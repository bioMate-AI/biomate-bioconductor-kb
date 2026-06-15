---
name: bioconductor-epigrahmm
description: epigraHMM provides a set of tools for the analysis of epigenomic data based on hidden Markov Models. It contains two separate peak callers, one for consensus peaks from biological or technical replicates, and one for differential peaks from multi-replicate multi-condition experiments. In differential peak calling, epigraHMM provides window-specific posterior probabilities associated with every possible combinatorial pattern of read enrichment across conditions.
when_to_use: Use when: Consensus and Differential Peak Calling With epigraHMM; ChIP-seq peak analysis (epigraHMM); ATAC-seq chromatin accessibility (epigraHMM). Not for: Requires biological replicates for statistical analysis; Requires R ≥ 3.5.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# epigraHMM

## Workflows

### Differential Peak Calling

Detect differential enrichment regions (peaks) across multiple experimental conditions and classify peaks into combinatorial patterns of enrichment.

```r
library(epigraHMM)

# Define input BAM files and metadata
bamFiles <- system.file(
  package = "genomationData", 
  "extdata", 
  c("wgEncodeBroadHistoneH1hescCtcfStdAlnRep1.chr21.bam", 
    "wgEncodeBroadHistoneH1hescSuz12051317AlnRep1.chr21.bam")
)
colData <- data.frame(condition = c("CTCF", "SUZ12"), replicate = c(1, 1))

# Create dataset object
object_differential <- epigraHMMDataSetFromBam(
  bamFiles = bamFiles, 
  colData = colData, 
  genome = 'hg19', 
  windowSize = 500, 
  gapTrack = TRUE, 
  blackList = TRUE
)

# Set up EM control and run differential peak calling
control <- controlEM(fileName = 'control-differential', criterion = 'MACPE')
object_differential <- normalizeCounts(object_differential, control)
object_differential <- initializer(object_differential, control)
object_differential <- epigraHMM(object = object_differential, control = control, type = 'differential')

# Call peaks
peaks_differential <- callPeaks(object = object_differential)
```
*Input: BAM files and sample metadata; Output: A GRanges object containing called differential peak regions.*

### Standard Workflow

Detect consensus enrichment regions (peaks) across technical or biological replicates of a single experimental condition.

```r
library(epigraHMM)

# Define input BAM files and metadata
bamFiles <- system.file(
  package = "genomationData", 
  "extdata", 
  "wgEncodeBroadHistoneH1hescCtcfStdAlnRep1.chr21.bam"
)
colData <- data.frame(condition = "CTCF", replicate = 1)

# Create dataset object
object_consensus <- epigraHMMDataSetFromBam(
  bamFiles = bamFiles, 
  colData = colData, 
  genome = 'hg19', 
  windowSize = 500, 
  gapTrack = TRUE, 
  blackList = TRUE
)

# Set up EM control and run consensus peak calling
control <- controlEM(fileName = 'control-consensus')
object_consensus <- normalizeCounts(object_consensus, control = control)
object_consensus <- initializer(object_consensus, control)
object_consensus <- epigraHMM(object = object_consensus, control = control, type = 'consensus')

# Call peaks
peaks_consensus <- callPeaks(object = object_consensus)
```
*Input: BAM files and sample metadata; Output: A GRanges object containing called consensus peak regions.*

## When to Use
- **Consensus Peak Calling**: To identify consistent peaks across technical or biological replicates of a single condition using `epigraHMM` with `type = 'consensus'`.
- **Differential Peak Calling**: To detect genomic regions with differential enrichment across multiple conditions using `epigraHMM` with `type = 'differential'`.
- **Epigenomic Mark Analysis**: When analyzing ChIP-seq, ATAC-seq, or DNase-seq data starting from BAM files (`epigraHMMDataSetFromBam`) or count matrices (`epigraHMMDataSetFromMatrix`).
- **Combinatorial Pattern Classification**: To classify differential peaks into specific combinatorial patterns of enrichment across conditions using `plotPatterns`.

## When NOT to Use
- **Sliding Window Analysis**: For differential binding analysis using sliding windows, use `csaw` because `epigraHMM` operates on fixed genomic windows.
- **Non-HMM Peak Calling**: If a hidden Markov model framework is not desired, use `MACS2` or `DiffBind` for standard peak calling.

## Data Requirements
- **Input Formats**: BAM files (`bamFiles`) or a count matrix (`countData`) of non-negative integers.
- **Metadata**: A `data.frame` (`colData`) containing columns named `condition` and `replicate`.
- **Reference Genome**: A character string specifying a UCSC genome (e.g., 'hg19') or a `GRanges` object with chromosome lengths.

## Key Parameters
- **type** ('consensus'): Type of peak calling, either 'consensus' or 'differential'.
- **dist** ('zinb'): Probabilistic distribution for the counts, either 'zinb' (zero-inflated negative binomial) or 'nb' (negative binomial).
- **windowSize** (250): Size of genomic windows where read counts are computed.
- **gapTrack** (TRUE): Logical indicating whether to exclude genomic coordinates overlapping gap regions.
- **blackList** (TRUE): Logical indicating whether to exclude ENCODE blacklist tracks.
- **method** (0.05): FDR control thresholding level for calling peaks in `callPeaks`.

## Best Practices
- **Biases Correction**: Always use `normalizeCounts` as the last normalization step just prior to peak calling to correct for non-linear biases.
- **Input Controls**: If input control experiments are available, include them in the `controls` matrix/BAM list to model them as a covariate in the HMM.
- **Distribution Choice**: Use `dist = 'zinb'` for consensus peak calling as the zero-inflated negative binomial model provides better results in this setting.
- **Artifact Removal**: Exclude gap and blacklisted regions during dataset creation to avoid technical artifacts.

## Common Pitfalls
- **Missing BAM Indexes**: Ensure `.bai` index files are present in the same directory as BAM files and named with the `.bai` suffix.
- **Incorrect Metadata Columns**: Ensure `colData` contains the exact column names `condition` and `replicate`.
- **Offset Overwriting**: When adding custom offsets with `addOffsets`, run it before `normalizeCounts` so that the non-linear normalization considers existing offsets.

## Alternatives
- **DiffBind**: For differential binding analysis using affinity data.
- **csaw**: For sliding window-based differential binding analysis.
- **MACS2**: For standard peak calling without HMMs.

## Citations
- Baldoni, PL, Rashid, NU, Ibrahim, JG. Improved detection of epigenomic marks with mixed-effects hidden Markov models. Biometrics. 2019; 75(4): 1401-1413.
- Baldoni, PL, Rashid, NU, Ibrahim, JG. Efficient Detection and Classification of Epigenomic Changes Under Multiple Conditions. Biometrics. 2022; 78(3): 1141-1154.

## References
- Homepage: bioconductor.org/packages/epigrahmm
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/epigrahmm/inst/doc/epigrahmm.html
