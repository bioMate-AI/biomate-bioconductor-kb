---
name: bioconductor-supersigs
description: Generate SuperSigs (supervised mutational signatures) from single nucleotide variants in the cancer genome. Functions included in the package allow the user to learn supervised mutational signatures from their data and apply them to new data. The methodology is based on the one described in Afsari (2021, ELife).
when_to_use: Use when: Generate SuperSigs (supervised mutational signatures) from single nucleotide variants in the cancer genome. Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# supersigs

## Workflows

### Standard Workflow

Preprocess mutation data, build a trinucleotide feature matrix, and train a supervised mutational signature (SuperSig).

```r
library(supersigs)
library(VariantAnnotation)
library(BSgenome.Hsapiens.UCSC.hg19)
library(dplyr)

# 1. Read VCF and add patient age to colData
fl <- system.file("extdata", "chr22.vcf.gz", package="VariantAnnotation")
vcf <- VariantAnnotation::readVcf(fl, "hg19")
vcf <- vcf[, 1]
positions <- geno(vcf)$GT != "0|0"
vcf <- vcf[positions[, 1],]
colData(vcf)$age <- 50

# 2. Process VCF to a simplified data frame
dt <- process_vcf(vcf)

# 3. Transform mutations into a trinucleotide matrix
input_dt <- make_matrix(dt)

# 4. Add the indicator variable (IndVar)
input_dt <- input_dt %>%
  mutate(IndVar = c(1, 1, 1, 0, 0)) %>%
  relocate(IndVar)

# 5. Train the supervised signature
set.seed(1)
supersig <- get_signature(data = input_dt, factor = "Smoking")

# 6. Simplify the signature for visualization
features <- simplify_signature(object = supersig, iupac = FALSE)
```
Note: Input is a `VCF` object or a data frame of mutations with sample IDs, ages, and genomic coordinates; output is a trained `SuperSig` S4 object and simplified signature features.

### Partial Signature Adjustment

Remove the contribution of a supervised signature from a mutation data frame to adjust for a confounding factor.

```r
library(supersigs)
# Adjust the mutation matrix by removing the signature's contribution
adjusted_dt <- partial_signature(data = input_dt, object = supersig)
```
Note: Input is a feature count data frame and a trained `SuperSig` object; output is an adjusted mutation feature data frame.

### Predict Supersig

Apply a trained or pre-trained SuperSig to a new dataset to predict classification scores.

```r
library(supersigs)
library(dplyr)
# Apply a trained SuperSig to a new dataset
newdata <- predict_signature(supersig, newdata = input_dt, factor = "Smoking")
# Or use a pre-trained signature from supersig_ls
newdata_pretrained <- predict_signature(supersig_ls[["SMOKING (LUAD)"]], newdata = input_dt, factor = "Smoking")
```
Note: Input is a trained `SuperSig` object (or pre-trained from `supersig_ls`) and a new feature count data frame; output is a data frame containing predicted classification scores and feature counts.

## When to Use
- **Supervised Signature Generation**: Generating supervised mutational signatures ("SuperSigs") from single nucleotide variants (SNVs) in cancer genomes (`get_signature`).
- **Exposure Classification**: Predicting exposure classification scores on new datasets using custom or pre-trained TCGA signatures (`predict_signature`, `supersig_ls`).
- **Confounder Adjustment**: Adjusting mutation datasets to remove confounding factors (e.g., aging) before downstream signature analysis (`partial_signature`).

## When NOT to Use
- **Unsupervised Deconvolution**: For unsupervised mutational signature deconvolution (e.g., standard NMF-based signature extraction).
- **Missing Clinical Metadata**: When patient age or clinical exposure indicators are completely unavailable.

## Data Requirements
- Input mutation data containing `sample_id`, `age`, `chromosome`, `position`, `ref`, and `alt` columns.
- A supported reference genome package installed (e.g., `BSgenome.Hsapiens.UCSC.hg19` or `BSgenome.Hsapiens.UCSC.hg38`) for trinucleotide context extraction.

## Key Parameters
- **data**: Input data frame containing `IndVar`, `sample_id`, `age`, and 96 trinucleotide mutation count columns in `get_signature`.
- **factor**: The clinical factor or exposure of interest (e.g., "Smoking", "Age") in `get_signature` and `predict_signature`.
- **object**: A trained `SuperSig` S4 object in `simplify_signature` and `partial_signature`.
- **iupac** (FALSE): Logical indicating whether to use IUPAC labels when simplifying signatures in `simplify_signature`.
- **newdata**: New dataset to predict on in `predict_signature`.

## Best Practices
- Ensure the VCF object contains patient age in `colData(vcf)$age` before calling `process_vcf`.
- Set a random seed (`set.seed`) before running `get_signature` to ensure reproducibility of cross-validation folds.
- Use `simplify_signature(..., iupac = TRUE)` to group trinucleotide features into more interpretable IUPAC representations for plotting.
- Adjust for confounding factors like aging using `partial_signature` before learning other signatures.

## Common Pitfalls
- **Missing IndVar column**: `get_signature` requires a logical/numeric indicator variable named `IndVar` in the input data frame. Fix: Add and relocate the `IndVar` column using `dplyr::mutate` and `dplyr::relocate`.
- **Reference genome mismatch**: Using the wrong reference genome version (e.g., hg19 vs hg38) during `make_matrix`. Fix: Ensure the correct `BSgenome` package is loaded and matches the coordinates in your mutation data.

## Alternatives
- **SomaticSignatures**: For unsupervised mutational signature analysis.
- **MutationalPatterns**: For comprehensive mutational signature extraction and visualization.

## Citations
- Afsari, B. et al. (2021). Supervised mutational signatures for cancer genomics. eLife.

## References
- Homepage: bioconductor.org/packages/supersigs
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/supersigs/inst/doc/supersigs.html
