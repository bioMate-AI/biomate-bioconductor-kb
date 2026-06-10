# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("consICA", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(consICA)
library(SummarizedExperiment)

# Reproduce samples_data
data("samples_data")

# Reproduce Var
Var <- data.frame(colData(samples_data))
Var <- Var[,which(colnames(Var) != "time" & colnames(Var) != "event")]

# Reproduce Sur
Sur <- data.frame(colData(samples_data))[,c("time", "event")]

# Serialize the objects to .rds files
saveRDS(samples_data, "samples_data.rds")
saveRDS(Var, "Var.rds")
saveRDS(Sur, "Sur.rds")