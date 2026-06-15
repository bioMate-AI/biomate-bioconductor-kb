---
name: bioconductor-crisprscore
description: Provides R wrappers of several on-target and off-target scoring methods for CRISPR guide RNAs (gRNAs). The following nucleases are supported: SpCas9, AsCas12a, enAsCas12a, and RfxCas13d (CasRx). The available on-target cutting efficiency scoring methods are RuleSet1, Azimuth, DeepHF, DeepCpf1, enPAM+GB, and CRISPRscan. Both the CFD and MIT scoring methods are available for off-target specificity prediction. The package also provides a Lindel-derived score to predict the probability of a gRNA to
when_to_use: Use when: Provides R wrappers of several on-target and off-target scoring methods for CRISPR guide RNAs (gRNAs). Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# crisprScore

## Workflows

### Standard Workflow

```r
library(crisprScore)
spacer <- "ATCGATGCTGATGCTAGATA"
results <- getCRISPRaterScores(spacer)
```
*Inputs: A character vector of 20bp spacer sequences. Outputs: A numeric vector of CRISPRater on-target efficiency scores.*

### Off Target Specificity Prediction

```r
library(crisprScore)
spacer <- "ATCGATGCTGATGCTAGATA"
protospacers <- c("ACCGATGCTGATGCTAGATA", "ATCGATGCTGATGCTAGATT", "ATCGATGCTGATGCTAGATA")
pams <- c("AGG", "AGG", "AGA")

mit_scores <- getMITScores(spacers=spacer, protospacers=protospacers, pams=pams)
cfd_scores <- getCFDScores(spacers=spacer, protospacers=protospacers, pams=pams)
```
*Inputs: Spacer sequence, potential off-target protospacer sequences, and PAM sequences. Outputs: Data frames containing MIT and CFD off-target specificity scores.*

### Indel Frameshift Prediction

```r
library(crisprScore)
flank5 <- "ACCTTTTAATCGA"
spacer <- "TGCTGATGCTAGATATTAAG"
pam    <- "TGG"
flank3 <- "CTTTTAATCGATGCTGATGCTAGATATTA"
input <- paste0(flank5, spacer, pam, flank3)
# results <- getLindelScores(input, condaEnv="/path/to/lindel-env")
```
*Inputs: A 65bp character vector containing flanking and protospacer sequences. Outputs: Predicted proportion of frameshifting indels.*

### Cas12A On Target Scoring

```r
library(crisprScore)
flank5 <- "ACCG"
pam    <- "TTTT"
spacer <- "AATCGATGCTGATGCTAGATATT"
flank3 <- "AAG"
input  <- paste0(flank5, pam, spacer, flank3)
# results <- getEnPAMGBScores(input, condaEnv="/path/to/enpamgb-env")
```
*Inputs: A 34bp character vector containing 4bp upstream, 4bp PAM, 23bp spacer, and 3bp downstream. Outputs: Predicted enPAM+GB on-target efficiency scores.*

### Cas13D On Target Scoring

```r
library(crisprScore)
library(Biostrings)
fasta <- file.path(system.file(package="crisprScore"), "casrxrf/test.fa")
mrnaSequence <- Biostrings::readDNAStringSet(filepath=fasta, format="fasta", use.names=TRUE)
results <- getCasRxRFScores(mrnaSequence)
```
*Inputs: An mRNA sequence as a `DNAStringSet` object. Outputs: A data frame containing predicted CasRx-RF on-target efficiency scores.*

### Off Target Specificity Scoring

```r
library(crisprScore)
spacer <- "ATCGATGCTGATGCTAGATA"
protospacers <- c("ACCGATGCTGATGCTAGATA", "ATCGATGCTGATGCTAGATT", "ATCGATGCTGATGCTAGATA")
pams <- c("AGG", "AGG", "AGA")

mit_res <- getMITScores(spacers=spacer, protospacers=protospacers, pams=pams)
cfd_res <- getCFDScores(spacers=spacer, protospacers=protospacers, pams=pams)
```
*Inputs: Spacer, protospacer, and PAM sequences. Outputs: Data frames containing calculated MIT and CFD specificity scores.*

## When to Use
- **Cas9 On-Target Scoring**: Predicting on-target cutting efficiency for SpCas9 using `getRuleSet1Scores`, `getRuleSet3Scores`, `getDeepHFScores`, `getCRISPRscanScores`, or `getCRISPRaterScores`.
- **Cas12a On-Target Scoring**: Predicting on-target cutting efficiency for enAsCas12a using `getEnPAMGBScores`.
- **Cas13d On-Target Scoring**: Predicting on-target efficiency for RfxCas13d (CasRx) using `getCasRxRFScores`.
- **Off-Target Specificity**: Predicting off-target specificity using `getMITScores` and `getCFDScores`.
- **Frameshift Prediction**: Predicting frameshift-inducing indel probabilities using `getLindelScores`.

## When NOT to Use
- **Unsupported R/Bioconductor Versions**: Do not use if R version is less than 4.1 or Bioconductor version is less than 3.16.
- **Python 2 Algorithms**: Do not use for running Python 2-based algorithms (like Azimuth, DeepCpf1, DeepSpCas9, and CRISPRai) which are no longer supported.

## Data Requirements
- **Sequence Lengths**:
  - `getRuleSet1Scores` / `getRuleSet3Scores`: 30bp sequences (4bp upstream + 20bp spacer + 3bp PAM + 3bp downstream).
  - `getCRISPRscanScores`: 35bp sequences (6bp upstream + 20bp spacer + 3bp PAM + 6bp downstream).
  - `getCRISPRaterScores`: 20bp spacer sequences.
  - `getLindelScores`: 65bp sequences (13bp upstream + 20bp spacer + 3bp PAM + 29bp downstream).
  - `getCasRxRFScores`: mRNA sequences as a `DNAStringSet` object.

## Key Parameters
- **tracrRNA** ("Hsu2013"): TracrRNA design type used in `getRuleSet3Scores` (e.g., "Hsu2013" or "Chen2013").
- **condaEnv** (NULL): Path to the conda environment containing Python dependencies for algorithms like RuleSet3, DeepHF, enPAM+GB, and Lindel.
- **enzyme** ("WT"): Cas9 variant for `getDeepHFScores` ("WT", "HF", or "ESP").
- **promoter** ("U6"): Promoter used for expressing sgRNAs in `getDeepHFScores`.
- **directRepeat** ("aacccctaccaactggtcggggtttgaaac"): Direct repeat sequence used in `getCasRxRFScores`.
- **spacers** (no default): Character vector of 20bp spacer sequences for off-target scoring.
- **protospacers** (no default): Character vector of 20bp target protospacer sequences for off-target scoring.
- **pams** (no default): Character vector of PAM sequences.

## Best Practices
- **Conda Environments**: Build the required conda environments manually prior to using Python-based scoring algorithms and pass the path to `condaEnv`.
- **Algorithm Upgrades**: Use `getRuleSet3Scores` or `getDeepHFScores` instead of the deprecated `Azimuth` algorithm.
- **Cas12a Upgrades**: Use `getEnPAMGBScores` instead of the deprecated `DeepCpf1` algorithm.

## Common Pitfalls
- **Missing Conda Environments**: Attempting to run Python-based algorithms without specifying a valid conda environment path. Fix: Set up the environment using the provided `buildingCondaEnvironments.sh` script and pass the path to `condaEnv`.
- **Deprecated Algorithms**: Using Python 2-based algorithms like Azimuth or DeepCpf1. Fix: Use supported alternatives like `getRuleSet3Scores` or `getEnPAMGBScores`.

## Alternatives
- **crisprDesign**: For full gRNA design workflows that internally call `crisprScore`.
- **crisprBase**: For defining CRISPR nucleases and base editors.

## Citations
- Doench, John G, et al. 2014. "Rational Design of Highly Active sgRNAs for Crispr-Cas9–Mediated Gene Inactivation." Nature Biotechnology 32 (12): 1262–7.
- DeWeirdt, Peter C, et al. 2022. "Accounting for Small Variations in the tracrRNA Sequence Improves sgRNA Activity Predictions for Crispr Screening." bioRxiv.
- Wang, Daqi, et al. 2019. "Optimized Crispr Guide Rna Design for Two High-Fidelity Cas9 Variants by Deep Learning." Nature Communications 10 (1): 1–14.
- Chen, Wei, et al. 2019. "Massively Parallel Profiling and Predictive Modeling of the Outcomes of Crispr/Cas9-Mediated Double-Strand Break Repair." Nucleic Acids Research 47 (15): 7989–8003.

## References
- Homepage: bioconductor.org/packages/crisprScore
- Vignette: bioconductor.org/packages/release/bioc/vignettes/crisprScore/inst/doc/crisprScore.html
