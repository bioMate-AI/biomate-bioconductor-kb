# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("genomicInstability", "SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(genomicInstability)
library(SingleCellExperiment)

set.seed(1)
# The vignette uses a TPM matrix where rows are Entrez IDs and columns are cells.
# Since we cannot fetch EH5419 from ExperimentHub offline, we construct a synthetic matrix.
genes <- as.character(1:2000)
cells <- paste0("Cell_", 1:100)

tpm_matrix <- matrix(
    rexp(length(genes) * length(cells), rate = 0.1), 
    nrow = length(genes), 
    ncol = length(cells)
)
rownames(tpm_matrix) <- genes
colnames(tpm_matrix) <- cells

# Serialize the object to the expected input file
saveRDS(tpm_matrix, file = "tpm_matrix")