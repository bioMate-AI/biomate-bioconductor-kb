# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("qsvaR", "SummarizedExperiment", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(qsvaR)
library(SummarizedExperiment)
library(GenomicRanges)

# Retrieve the transcripts that qsvaR expects to be present for degradation modeling
# We use the 'cell_component' model transcripts as referenced in the vignette
sig_tx <- select_transcripts(cell_component = TRUE)

# Create a synthetic RangedSummarizedExperiment
# Include a subset of the significant transcripts plus some background ones
tx_ids <- c(sig_tx[1:200], "ENST00000000001", "ENST00000000002")

n_samples <- 30

# Create colData with the exact columns used in the vignette's model.matrix:
# ~ Dx + Age + Sex + Race + Region
col_data <- DataFrame(
    Dx = factor(rep(c("Control", "Schizo", "Bipolar"), length.out = n_samples)),
    Age = runif(n_samples, 20, 60), # Ensures Age > 17 filter passes
    Sex = factor(rep(c("M", "F"), length.out = n_samples)),
    Race = factor(rep(c("CAUC", "AA", "ASIAN"), length.out = n_samples)),
    Region = factor(rep(c("DLPFC", "HIPPO"), length.out = n_samples)),
    row.names = paste0("Sample", 1:n_samples)
)

# Create assay (tpm)
# Values > 0.3 ensure the rowMeans(assays(rse_tx)$tpm) > 0.3 filter passes
set.seed(123)
tpm_matrix <- matrix(runif(length(tx_ids) * n_samples, 0.5, 10), 
                     nrow = length(tx_ids), 
                     ncol = n_samples)
rownames(tpm_matrix) <- tx_ids
colnames(tpm_matrix) <- rownames(col_data)

# Create rowRanges to ensure the object is a RangedSummarizedExperiment
row_ranges <- GRanges(
    seqnames = "chr1",
    ranges = IRanges(start = 1:length(tx_ids), width = 100)
)
names(row_ranges) <- tx_ids

# Construct the RangedSummarizedExperiment object
rse_tx <- SummarizedExperiment(
    assays = list(tpm = tpm_matrix),
    rowRanges = row_ranges,
    colData = col_data
)

# Serialize the S4 object to the expected input file
saveRDS(rse_tx, "rse_tx.rds")