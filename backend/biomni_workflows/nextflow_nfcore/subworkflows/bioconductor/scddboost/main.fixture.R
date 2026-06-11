# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scDDboost", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressMessages(library(scDDboost))
suppressMessages(library(SummarizedExperiment))

data(sim_dat)
data_counts <- SummarizedExperiment::assays(sim_dat)$counts
conditions <- SummarizedExperiment::colData(sim_dat)$conditions
rownames(data_counts) <- seq_len(1000)

saveRDS(data_counts, "normalized_counts_matrix.rds")
saveRDS(conditions, "condition_vector.rds")