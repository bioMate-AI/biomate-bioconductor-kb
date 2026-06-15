---
name: bioconductor-easier
description: This package provides a workflow for the use of EaSIeR tool, developed to assess patients' likelihood to respond to ICB therapies providing just the patients' RNA-seq data as input. We integrate RNA-seq data with different types of prior knowledge to extract quantitative descriptors of the tumor microenvironment from several points of view, including composition of the immune repertoire, and activity of intra- and extra-cellular communications. Then, we use multi-task machine learning trained in
when_to_use: Use when: This package provides a workflow for the use of EaSIeR tool, developed to assess patients' likelihood to respond to ICB; easier User Manual with easier. Not for: Requires R ≥ 4.2.0
user-invocable: false
---

# easier

## Workflows

### Standard Workflow

This package provides a workflow for the use of EaSIeR tool, developed to assess patients' likelihood to respond to ICB therapies providing just the patients' RNA-seq data as input. We integrate RNA-seq data with different types of prior knowledge to extract quantitative descriptors of the tumor microenvironment from several points of view, including composition of the immune repertoire, and activity of intra- and extra-cellular communications. Then, we use multi-task machine learning trained in

```r
library(easier)
library(easierData)
library(SummarizedExperiment)

# Load example dataset
dataset_mariathasan <- get_Mariathasan2018_PDL1_treatment()

# Extract clinical variables
patient_ICBresponse <- colData(dataset_mariathasan)[["BOR"]]
names(patient_ICBresponse) <- colData(dataset_mariathasan)[["pat_id"]]
TMB <- colData(dataset_mariathasan)[["TMB"]]
names(TMB) <- colData(dataset_mariathasan)[["pat_id"]]
cancer_type <- metadata(dataset_mariathasan)[["cancertype"]]

# Extract gene expression data
RNA_counts <- assays(dataset_mariathasan)[["counts"]]
RNA_tpm <- assays(dataset_mariathasan)[["tpm"]]

# 1. Compute hallmarks of immune response
hallmarks_of_immune_response <- c("CYT", "Roh_IS", "chemokines", "Davoli_IS", "IFNy", "Ayers_expIS", "Tcell_inflamed", "RIR", "TLS")
immune_response_scores <- compute_scores_immune_response(RNA_tpm = RNA_tpm, selected_scores = hallmarks_of_immune_response)

# 2. Quantify immune cell fractions using quanTIseq
cell_fractions <- compute_cell_fractions(RNA_tpm = RNA_tpm)

# 3. Infer pathway activities using PROGENy
pathway_activities <- compute_pathway_activity(RNA_counts = RNA_counts, remove_sig_genes_immune_response = TRUE)

# 4. Infer transcription factor activities using DoRothEA
tf_activities <- compute_TF_activity(RNA_tpm = RNA_tpm)

# 5. Quantify ligand-receptor pairs
lrpair_weights <- compute_LR_pairs(RNA_tpm = RNA_tpm, cancer_type = "pancan")

# 6. Quantify cell-cell interactions
ccpair_scores <- compute_CC_pairs(lrpairs = lrpair_weights, cancer_type = "pancan")

# Predict immune response
predictions <- predict_immune_response(
  pathways = pathway_activities, 
  immunecells = cell_fractions, 
  tfs = tf_activities, 
  lrpairs = lrpair_weights, 
  ccpairs = ccpair_scores, 
  cancer_type = cancer_type, 
  verbose = TRUE
)

# Evaluate predictions using patients' immunotherapy response
output_eval_with_resp <- assess_immune_response(
  predictions_immune_response = predictions, 
  patient_response = patient_ICBresponse, 
  RNA_tpm = RNA_tpm, 
  TMB_values = TMB, 
  easier_with_TMB = "weighted_average", 
  weight_penalty = 0.5
)
```
*Note on inputs/outputs*: Input is bulk RNA-seq raw counts and TPM matrices, and output is predicted immune checkpoint blockade (ICB) response scores and evaluation metrics.

## When to Use
- Assessing patient likelihood to respond to immune checkpoint blockade (ICB) therapies using bulk RNA-seq data (`RNA_counts` and `RNA_tpm`).
- Quantifying tumor microenvironment (TME) features such as immune cell fractions via `compute_cell_fractions()`, pathway activities via `compute_pathway_activity()`, and transcription factor activities via `compute_TF_activity()`.
- Computing published transcriptome-based hallmarks of immune response using `compute_scores_immune_response()`.
- Estimating ligand-receptor pair weights and cell-cell interaction scores using `compute_LR_pairs()` and `compute_CC_pairs()`.

## When NOT to Use
- For single-cell RNA-seq data, use packages like `Seurat` or `SingleCellExperiment` because `easier` is designed for bulk-tumor RNA-seq data.
- For non-oncology datasets, use general pathway/TF activity tools directly (like `progeny` or `dorothea`) because `easier` models are specifically trained on cancer datasets (TCGA) to predict anti-cancer immune response.

## Data Requirements
- **Input format**: `RNA_counts` (data.frame of raw counts with HGNC gene symbols as row names and sample IDs as columns) and `RNA_tpm` (data.frame of TPM values with HGNC gene symbols as row names and sample IDs as columns).
- **Optional clinical data**: `patient_response` (character vector with "R" for responders and "NR" for non-responders) and `TMB_values` (numeric vector of tumor mutational burden).

## Key Parameters
- **RNA_tpm**: Data frame containing TPM values.
- **RNA_counts**: Data frame containing raw count values.
- **selected_scores**: Character vector of immune response hallmarks to compute (e.g., `CYT`, `TLS`, `IFNy`).
- **remove_sig_genes_immune_response** (TRUE): Logical indicating whether to remove overlapping immune response signature genes from pathway activity inference.
- **cancer_type**: Character string specifying the cancer-specific model to use (e.g., `"bladder"`, `"pancan"`).
- **easier_with_TMB**: Character string specifying how to combine TMB and easier scores (`"weighted_average"` or `"penalized_score"`).
- **weight_penalty** (0.5): Numeric weight or penalty value for combining TMB and easier scores.

## Best Practices
- Perform gene re-annotation to match approved HGNC symbols before running the pipeline to avoid missing signature genes.
- Set `remove_sig_genes_immune_response = TRUE` when computing pathway activities to prevent circularity/overfitting with downstream immune response scores.
- Use the same `cancer_type` parameter across `compute_LR_pairs()`, `compute_CC_pairs()`, and `predict_immune_response()` to ensure consistency in network prior knowledge.

## Common Pitfalls
- Providing mismatched gene identifiers: If row names are Ensembl IDs instead of HGNC gene symbols, signature matching will fail. Fix by converting row names to HGNC symbols.
- Missing TMB values when using TMB-integrated scoring: If `TMB_values` contains `NA` values, patients with missing TMB will be excluded. Fix by handling or imputing missing TMB values before calling `assess_immune_response()`.

## Alternatives
- `progeny`: For pathway activity inference alone without the ICB response prediction framework.
- `dorothea`: For transcription factor activity estimation alone.
- `immunedeconv`: For running alternative immune cell deconvolution methods.

## Citations
- Lapuente-Santana, O., et al. (2021). "Interpretable systems biomarkers predict response to immune-checkpoint inhibitors." Patterns, 2, 100293.
- Finotello, F., et al. (2019). "Molecular and pharmacological modulators of the tumor microenvironment..." (quanTIseq citation).

## References
- Homepage: https://bioconductor.org/packages/easier
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/easier/inst/doc/easier.html
