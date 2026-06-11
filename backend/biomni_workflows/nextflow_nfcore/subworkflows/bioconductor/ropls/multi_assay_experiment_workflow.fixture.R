# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ropls", "MultiAssayExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ropls)
library(MultiAssayExperiment)

# Load the sacurine dataset as described in the vignette
data(sacurine, package = "ropls")

# Construct a MultiAssayExperiment object using the SummarizedExperiment 
# and sample metadata provided in the sacurine dataset
mae <- MultiAssayExperiment(
    experiments = ExperimentList(
        metabolomics = sacurine$se
    ),
    colData = sacurine$sampleMetadata
)

# Serialize the MultiAssayExperiment object to an RDS file
saveRDS(mae, "input.rds")