# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("phenomis", "SummarizedExperiment", "MultiAssayExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(phenomis)
library(SummarizedExperiment)
library(MultiAssayExperiment)

# Construct a synthetic SummarizedExperiment
set.seed(123)
mat <- matrix(rnorm(100), ncol=10)
rownames(mat) <- paste0("feat", 1:10)
colnames(mat) <- paste0("samp", 1:10)
col_data <- DataFrame(group = rep(c("Control", "Treatment"), each=5), row.names = colnames(mat))
se <- SummarizedExperiment(assays = list(exprs = mat), colData = col_data)

saveRDS(se, "SummarizedExperiment.rds")

# Construct a synthetic MultiAssayExperiment
mae <- MultiAssayExperiment(experiments = ExperimentList(assay1 = se), colData = col_data)

saveRDS(mae, "MultiAssayExperiment.rds")