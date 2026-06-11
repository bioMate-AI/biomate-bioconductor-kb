# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("genomicInstability")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(genomicInstability)

# The vignette uses ExperimentHub to download a SingleCellExperiment object (EH5419)
# containing a TPM matrix with Entrez IDs as rownames.
# Since we must run fully offline, we construct a synthetic TPM matrix 
# with a wide range of Entrez IDs to ensure overlap with the package's internal loci-blocks.

set.seed(1)
# Generate a synthetic TPM matrix
# Rownames are Entrez IDs (1 to 10000 to ensure many valid hits)
genes <- as.character(1:10000)
cells <- paste0("Cell_", 1:100)
tpm_matrix <- matrix(rnbinom(length(genes) * length(cells), mu = 10, size = 1), 
                     nrow = length(genes), ncol = length(cells))
rownames(tpm_matrix) <- genes
colnames(tpm_matrix) <- cells

# Generate a nullmat (subset of cells acting as normal reference, e.g., low GI likelihood)
nullmat <- tpm_matrix[, 1:20, drop = FALSE]

# Serialize the objects to the declared input files
saveRDS(tpm_matrix, "tpm_matrix")
saveRDS(nullmat, "nullmat")