# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("mia", "phyloseq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(mia)
library(phyloseq)

# Load and save GlobalPatterns (TreeSummarizedExperiment)
data(GlobalPatterns, package = "mia")
saveRDS(GlobalPatterns, "GlobalPatterns.RDS")

# Load and save esophagus (Phyloseq object)
data(esophagus, package = "phyloseq")
saveRDS(esophagus, "esophagus.RDS")